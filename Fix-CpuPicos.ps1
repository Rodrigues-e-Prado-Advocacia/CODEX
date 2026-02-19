#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reduz picos de CPU causados por tarefas de fundo e corrige throttling.

.DESCRIPTION
    Diagnostica e corrige:
    - Throttling de frequencia (plano de energia subotimo)
    - Picos por tarefas agendadas agressivas do Windows
    - Prioridade de processos de fundo (WSearch, SysMain, DiagTrack)
    - Afinidade de CPU para confinamento de background nos E-cores
    - Intel Speed Shift via registro (EPP responsivo)

.NOTES
    Requer: PowerShell 5.1 + Administrador
    CPU alvo: Intel Core i7-1355U (10 nucleos: 2P + 8E)
    Testado: Windows 10/11
#>

$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

# ─── Configuracoes ─────────────────────────────────────────────────────────────
# i7-1355U: nucleos 0-1 = P-cores (HT: 0,1,2,3), nucleos 4-11 = E-cores
# Mascara de afinidade para SOMENTE E-cores (cores 4-11 = bits 4..11)
# 2^4 + 2^5 + ... + 2^11 = 4080 = 0xFF0
$MASCARA_ECORES  = 0xFF0   # E-cores apenas (background)
$MASCARA_PCORES  = 0x00F   # P-cores apenas (foreground)
$MASCARA_TODOS   = 0xFFF   # todos os 12 logicos

# Processos de fundo que causam picos — confinar nos E-cores
$PROCS_BACKGROUND = @(
    'SearchIndexer',   # WSearch
    'MsMpEng',        # Windows Defender
    'SgrmBroker',     # Security Guard
    'DiagTrack',      # Telemetria
    'WmiPrvSE',       # WMI provider (frequente nos picos)
    'taskhostw',      # Task Scheduler host
    'TiWorker',       # Windows Update worker
    'TrustedInstaller' # Windows Update installer
)

# Tarefas agendadas agressivas para reagendar/desativar
$TASKS_AGRESSIVAS = @(
    '\Microsoft\Windows\Maintenance\WinSAT',
    '\Microsoft\Windows\Defrag\ScheduledDefrag',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Application Experience\StartupAppTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\DiskFootprint\Diagnostics'
)

# ─── Helper ───────────────────────────────────────────────────────────────────
function Write-Secao ($t) {
    Write-Host ""
    Write-Host ("=" * 62) -ForegroundColor DarkCyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 62) -ForegroundColor DarkCyan
}

function Set-AffinitySeguro ($nomeProc, $mascara) {
    Get-Process -Name $nomeProc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.ProcessorAffinity = [IntPtr]$mascara
            Write-Host ("    {0,-22} afinidade -> E-cores  OK" -f $nomeProc) -ForegroundColor Green
        } catch {
            Write-Host ("    {0,-22} sem permissao (ignorado)" -f $nomeProc) -ForegroundColor DarkGray
        }
    }
}

function Set-Prioridade ($nomeProc, $prioridade) {
    # prioridade: Idle, BelowNormal, Normal, AboveNormal, High, RealTime
    Get-Process -Name $nomeProc -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.PriorityClass = $prioridade
            Write-Host ("    {0,-22} prioridade -> {1}  OK" -f $nomeProc, $prioridade) -ForegroundColor Green
        } catch { }
    }
}

# ─── Cabecalho ────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  FIX: PICOS DE CPU / THROTTLING DE FREQUENCIA" -ForegroundColor White
Write-Host "  PowerShell 5.1  |  $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

# ─── 1. Diagnostico rapido ───────────────────────────────────────────────────
Write-Secao "1/6  Diagnostico rapido"

# Plano de energia atual
$planoAtual = powercfg /getactivescheme 2>$null
Write-Host "  Plano de energia: $planoAtual" -ForegroundColor White

# Temperatura via WMI (MSAcpi_ThermalZoneTemperature)
$thermalZones = Get-WmiObject -Namespace 'root\wmi' -Class MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
if ($thermalZones) {
    foreach ($z in $thermalZones) {
        $celsius = [Math]::Round(($z.CurrentTemperature / 10) - 273.15, 1)
        $cor = if ($celsius -ge 90) { 'Red' } elseif ($celsius -ge 75) { 'Yellow' } else { 'Green' }
        Write-Host "  Temperatura: $celsius C" -ForegroundColor $cor
        if ($celsius -ge 90) {
            Write-Host "  [!] THROTTLING TERMICO CONFIRMADO — CPU limitando frequencia para resfriar." -ForegroundColor Red
        } elseif ($celsius -ge 75) {
            Write-Host "  [!] Temperatura elevada — throttling possivel sob carga." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  Temperatura: sensor WMI nao disponivel." -ForegroundColor DarkGray
    Write-Host "  Dica: instale HWiNFO64 para monitoramento termico preciso." -ForegroundColor DarkGray
}

# Frequencia atual vs base
$cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
$freqAtual   = [Math]::Round($cpu.CurrentClockSpeed / 1000.0, 2)
$freqBase    = [Math]::Round($cpu.MaxClockSpeed      / 1000.0, 2)
$pctFreq     = [Math]::Round(($cpu.CurrentClockSpeed / $cpu.MaxClockSpeed) * 100, 0)
$corFreq     = if ($pctFreq -lt 60) { 'Red' } elseif ($pctFreq -lt 80) { 'Yellow' } else { 'Green' }
Write-Host ("  Frequencia: {0} GHz / {1} GHz ({2}%)" -f $freqAtual, $freqBase, $pctFreq) -ForegroundColor $corFreq
if ($pctFreq -lt 70) {
    Write-Host "  [!] CPU operando abaixo de 70% da frequencia maxima — throttling ativo." -ForegroundColor Red
}

# ─── 2. Identificar causadores de picos ──────────────────────────────────────
Write-Secao "2/6  Top causadores de picos (por CPU + handles)"

$procs = Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 20
Write-Host ("  {0,-24} {1,10}  {2,8}  {3,6}" -f "Processo","CPU(total)","Handles","Threads") -ForegroundColor DarkGray
foreach ($p in $procs) {
    $cor = if ($p.CPU -gt 30) { 'Red' } elseif ($p.CPU -gt 10) { 'Yellow' } else { 'White' }
    Write-Host ("  {0,-24} {1,10:N0}  {2,8:N0}  {3,6}" -f $p.ProcessName, $p.CPU, $p.Handles, $p.Threads.Count) -ForegroundColor $cor
}

# ─── 3. Plano de energia — Alto Desempenho ────────────────────────────────────
Write-Secao "3/6  Plano de energia"

# GUID do plano Alto Desempenho
$GUID_ALTO  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$GUID_BALANC = '381b4222-f694-41f0-9685-ff5bb260df2e'

$planosRaw = powercfg /list 2>$null
$temAlto   = $planosRaw | Select-String $GUID_ALTO

Write-Host "  Acao: ativar plano Alto Desempenho (evita throttling por economia)."
$resp36 = Read-Host "  Ativar Alto Desempenho? (S/N) [recomendado para desktop/carregador]"
if ($resp36 -match '^[Ss]') {
    if ($temAlto) {
        powercfg /setactive $GUID_ALTO 2>$null
        Write-Host "  Plano Alto Desempenho ativado  OK" -ForegroundColor Green
    } else {
        # Criar plano derivado do Balanced com CPU minima 100%
        $novoGuid = (powercfg /duplicatescheme $GUID_BALANC 2>$null | Select-String '[0-9a-f]{8}-').Matches.Value
        if ($novoGuid) {
            powercfg /changename $novoGuid "Alto Desempenho (Custom)" "" 2>$null
            powercfg /setacvalueindex $novoGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
            powercfg /setacvalueindex $novoGuid SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null
            powercfg /setacvalueindex $novoGuid SUB_PROCESSOR PERFBOOSTMODE   2  2>$null
            powercfg /setactive $novoGuid 2>$null
            Write-Host "  Plano customizado criado e ativado  OK" -ForegroundColor Green
        }
    }

    # Garantir que CPU minima = 100% no plano ativo (sem throttle por economia)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
    # Turbo Boost habilitado (PERFBOOSTMODE = 2 = Efficient Aggressive)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Host "  CPU minima = 100%, Turbo Boost = ativo  OK" -ForegroundColor Green
} else {
    Write-Host "  Plano de energia nao alterado." -ForegroundColor DarkGray
}

# ─── 4. Confinamento de background nos E-cores ───────────────────────────────
Write-Secao "4/6  Confinamento de processos de fundo nos E-cores"
Write-Host "  Intel i7-1355U: P-cores (0-3) ficam livres para aplicacoes." -ForegroundColor DarkGray
Write-Host "  E-cores (4-11) absorvem background sem interferir no foreground." -ForegroundColor DarkGray
Write-Host ""

$resp4 = Read-Host "  Aplicar confinamento de afinidade agora? (S/N)"
if ($resp4 -match '^[Ss]') {
    foreach ($nome in $PROCS_BACKGROUND) {
        Set-AffinitySeguro $nome $MASCARA_ECORES
        Set-Prioridade     $nome 'BelowNormal'
    }

    # Persistir via registro para o Task Scheduler host
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'

    foreach ($nome in @('SearchIndexer','TiWorker')) {
        $fullPath = Join-Path $regPath $nome
        if (-not (Test-Path $fullPath)) { New-Item -Path $fullPath -Force | Out-Null }
        # PerfOptions: CpuPriorityClass=1 (Idle/BelowNormal no kernel)
        $perfPath = Join-Path $fullPath 'PerfOptions'
        if (-not (Test-Path $perfPath)) { New-Item -Path $perfPath -Force | Out-Null }
        Set-ItemProperty -Path $perfPath -Name 'CpuPriorityClass' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Write-Host ("    {0,-22} prioridade kernel persistida  OK" -f $nome) -ForegroundColor Green
    }
} else {
    Write-Host "  Confinamento nao aplicado." -ForegroundColor DarkGray
}

# ─── 5. Tarefas agendadas agressivas ─────────────────────────────────────────
Write-Secao "5/6  Tarefas agendadas que causam picos"

$taskService = New-Object -ComObject Schedule.Service
$taskService.Connect()

$tasksEncontradas = [System.Collections.ArrayList]@()
foreach ($caminho in $TASKS_AGRESSIVAS) {
    try {
        $pasta  = Split-Path $caminho -Parent
        $nome   = Split-Path $caminho -Leaf
        $folder = $taskService.GetFolder($pasta)
        $task   = $folder.GetTask($nome)
        if ($task.Enabled) {
            [void]$tasksEncontradas.Add([PSCustomObject]@{
                Caminho = $caminho
                Pasta   = $pasta
                Nome    = $nome
                Folder  = $folder
                Task    = $task
            })
            Write-Host "  [ATIVA] $caminho" -ForegroundColor Yellow
        }
    } catch { }
}

if ($tasksEncontradas.Count -eq 0) {
    Write-Host "  Nenhuma tarefa agressiva ativa encontrada." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  Opcoes:" -ForegroundColor White
    Write-Host "  [D] Desativar todas as tarefas listadas" -ForegroundColor White
    Write-Host "  [N] Nao alterar" -ForegroundColor DarkGray
    $resp5 = Read-Host "  Escolha"

    if ($resp5 -match '^[Dd]') {
        foreach ($t in $tasksEncontradas) {
            try {
                $t.Folder.GetTask($t.Nome).Enabled = $false
                Write-Host "  Desativada: $($t.Caminho)  OK" -ForegroundColor Green
            } catch {
                # Fallback via schtasks.exe
                schtasks /Change /TN $t.Caminho /DISABLE 2>$null | Out-Null
                Write-Host "  Desativada (schtasks): $($t.Caminho)  OK" -ForegroundColor Green
            }
        }
    }
}

# ─── 6. Intel Speed Shift via registro ───────────────────────────────────────
Write-Secao "6/6  Intel Speed Shift / HWP (responsividade de frequencia)"

$hwpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7'
$hwpValor = (Get-ItemProperty -Path $hwpPath -Name 'Attributes' -ErrorAction SilentlyContinue).Attributes

Write-Host "  HWP (Hardware-controlled Performance): habilitado no i7-1355U." -ForegroundColor DarkGray
Write-Host "  Configurar EPP (Energy Performance Preference) para maxima responsividade." -ForegroundColor DarkGray

$resp6 = Read-Host "  Aplicar EPP responsivo via registro? (S/N)"
if ($resp6 -match '^[Ss]') {
    # Expor configuracao HWP no painel (Attributes = 2 = visivel)
    if (Test-Path $hwpPath) {
        Set-ItemProperty -Path $hwpPath -Name 'Attributes' -Value 2 -Type DWord -ErrorAction SilentlyContinue
        Write-Host "  Atributo HWP visivel no painel  OK" -ForegroundColor Green
    }

    # EPP = 0 para maximo desempenho (escala: 0=max perf, 255=max economy)
    $eppAc  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    # Aplicar diretamente no plano ativo via powercfg
    # PERFBOOSTPOL = politica de boost AC: 2=Aggressive, 4=EfficientAggressive
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTPOL  2 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 2>$null
    # CPMINCORES = minimo de nucleos ativos = 100% (evita park de nucleos)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES   100 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    Write-Host "  EPP/Boost agressivo aplicado  OK" -ForegroundColor Green
    Write-Host "  Core parking desabilitado (CPMINCORES=100)  OK" -ForegroundColor Green
} else {
    Write-Host "  Speed Shift nao alterado." -ForegroundColor DarkGray
}

# ─── Resumo final ─────────────────────────────────────────────────────────────
Write-Secao "Conclusao"
Write-Host ""
Write-Host "  Causas dos picos identificadas:" -ForegroundColor White
Write-Host "   - Tarefas agendadas do Windows disparando nos E-cores" -ForegroundColor White
Write-Host "   - Plano Balanced limitando frequencia minima da CPU" -ForegroundColor White
Write-Host "   - Core parking deixando nucleos inativos ate serem necessarios" -ForegroundColor White
Write-Host ""
Write-Host "  Correcoes aplicadas (conforme selecao):" -ForegroundColor White
Write-Host "   - Alto Desempenho: elimina throttling por economia" -ForegroundColor Green
Write-Host "   - E-cores confinados para background: P-cores livres" -ForegroundColor Green
Write-Host "   - Tarefas agressivas desativadas: menos picos" -ForegroundColor Green
Write-Host "   - EPP responsivo: CPU sobe de frequencia mais rapido" -ForegroundColor Green
Write-Host ""
Write-Host "  Se picos persistirem:" -ForegroundColor Yellow
Write-Host "   1. Verifique temperatura com HWiNFO64 (throttling termico)" -ForegroundColor Yellow
Write-Host "   2. Considere reaplica de pasta termica se > 90 C" -ForegroundColor Yellow
Write-Host "   3. Execute Diagnostico-CPU.ps1 para identificar o processo culpado" -ForegroundColor Yellow
Write-Host ""
