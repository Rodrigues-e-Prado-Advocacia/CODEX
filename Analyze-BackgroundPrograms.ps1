#Requires -Version 5.1
<#
.SYNOPSIS
    Analisa e identifica programas rodando desnecessariamente em segundo plano.

.DESCRIPTION
    Este script examina processos em execucao, tarefas agendadas, programas de inicializacao
    e servicos do Windows para identificar o que esta consumindo recursos de forma desnecessaria.
    Gera um relatorio detalhado com recomendacoes de acao.

.NOTES
    Autor: Claude Code
    Versao: 1.0
    Execute como Administrador para resultados completos.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$TopProcessCount = 20,

    [Parameter()]
    [double]$CpuThreshold = 1.0,       # % de CPU considerado relevante

    [Parameter()]
    [double]$MemoryThresholdMB = 50,   # MB de RAM considerado relevante

    [Parameter()]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\Relatorio_Processos_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt",

    [Parameter()]
    [switch]$ExportarRelatorio
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ─────────────────────────────────────────────
#  LISTA DE PROCESSOS ESSENCIAIS DO WINDOWS
# ─────────────────────────────────────────────
$ProcessosEssenciaisWindows = @(
    'System', 'smss', 'csrss', 'wininit', 'winlogon', 'lsass', 'lsm',
    'services', 'svchost', 'dwm', 'explorer', 'taskhost', 'taskhostw',
    'sihost', 'ctfmon', 'fontdrvhost', 'WUDFHost', 'audiodg',
    'Registry', 'Secure System', 'Memory Compression',
    'MsMpEng', 'NisSrv', 'SecurityHealthService',   # Windows Defender
    'spoolsv', 'msdtc', 'dllhost', 'conhost',
    'RuntimeBroker', 'SearchIndexer', 'SearchHost', 'SearchApp',
    'ShellExperienceHost', 'StartMenuExperienceHost',
    'ApplicationFrameHost', 'SystemSettings',
    'WmiPrvSE', 'WmiApSrv', 'wsmprovhost',
    'LogonUI', 'userinit', 'rdpclip',
    'TextInputHost', 'LockApp', 'UserOOBEBroker',
    'sppsvc', 'SgrmBroker', 'MpCopyAccelerator',
    'Idle', 'Interrupts'
)

# ─────────────────────────────────────────────
#  FUNCOES AUXILIARES
# ─────────────────────────────────────────────

function Write-Header {
    param([string]$Titulo)
    $linha = "=" * 70
    Write-Host "`n$linha" -ForegroundColor Cyan
    Write-Host "  $Titulo" -ForegroundColor Yellow
    Write-Host "$linha" -ForegroundColor Cyan
}

function Write-SubHeader {
    param([string]$Titulo)
    Write-Host "`n--- $Titulo ---" -ForegroundColor Magenta
}

function Get-CpuUsagePerProcess {
    <#
        Mede o uso de CPU real em um intervalo de 2 segundos.
        Retorna hashtable: ProcessId -> %CPU
    #>
    $amostra1 = Get-Process | Select-Object Id, CPU
    Start-Sleep -Seconds 2
    $amostra2 = Get-Process | Select-Object Id, CPU

    $resultado = @{}
    foreach ($p2 in $amostra2) {
        $p1 = $amostra1 | Where-Object { $_.Id -eq $p2.Id }
        if ($p1 -and $p2.CPU -and $p1.CPU) {
            $delta = ($p2.CPU - $p1.CPU) / 2 * 100
            if ($delta -lt 0) { $delta = 0 }
            $resultado[$p2.Id] = [math]::Round($delta, 2)
        }
    }
    return $resultado
}

function Get-ProcessStartupType {
    param([string]$ProcessName)
    # Verifica se o processo esta na lista de inicializacao do registro
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    foreach ($path in $paths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($items) {
                $values = $items.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }
                foreach ($v in $values) {
                    if ($v.Value -match [regex]::Escape($ProcessName)) {
                        return "Inicializacao automatica"
                    }
                }
            }
        } catch {}
    }
    return "Nao identificado na inicializacao"
}

function Get-RiskLevel {
    param(
        [double]$Cpu,
        [double]$MemMB,
        [bool]$EhEssencial
    )
    if ($EhEssencial) { return "Sistema" }
    if ($Cpu -gt 20 -or $MemMB -gt 500)  { return "ALTO" }
    if ($Cpu -gt 5  -or $MemMB -gt 200)  { return "MEDIO" }
    if ($Cpu -gt 1  -or $MemMB -gt 50)   { return "BAIXO" }
    return "Minimo"
}

function Get-RiskColor {
    param([string]$Nivel)
    switch ($Nivel) {
        "ALTO"    { return "Red" }
        "MEDIO"   { return "Yellow" }
        "BAIXO"   { return "Cyan" }
        "Sistema" { return "DarkGray" }
        default   { return "White" }
    }
}

# ─────────────────────────────────────────────
#  BANNER INICIAL
# ─────────────────────────────────────────────

Clear-Host
Write-Host @"

  ╔══════════════════════════════════════════════════════════════════╗
  ║       ANALISADOR DE PROGRAMAS EM SEGUNDO PLANO                   ║
  ║       Diagnostico de uso de recursos desnecessarios              ║
  ╚══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "  Computador : $env:COMPUTERNAME" -ForegroundColor White
Write-Host "  Usuario    : $env:USERNAME" -ForegroundColor White
Write-Host "  Data/Hora  : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor White
Write-Host "  OS         : $((Get-CimInstance Win32_OperatingSystem).Caption)" -ForegroundColor White

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n  [!] Execute como Administrador para resultados completos.`n" -ForegroundColor Red
} else {
    Write-Host "`n  [OK] Rodando com privilegios de Administrador.`n" -ForegroundColor Green
}

$relatorio = [System.Collections.Generic.List[string]]::new()
$relatorio.Add("RELATORIO DE ANALISE DE PROCESSOS EM SEGUNDO PLANO")
$relatorio.Add("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
$relatorio.Add("Computador: $env:COMPUTERNAME | Usuario: $env:USERNAME")
$relatorio.Add("=" * 70)

# ─────────────────────────────────────────────
#  ETAPA 1 — RECURSOS DO SISTEMA
# ─────────────────────────────────────────────

Write-Header "ETAPA 1 — VISAO GERAL DOS RECURSOS DO SISTEMA"

$os  = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor

$ramTotal  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$ramLivre  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$ramUsada  = [math]::Round($ramTotal - $ramLivre, 1)
$ramPct    = [math]::Round(($ramUsada / $ramTotal) * 100, 1)

Write-Host "`n  RAM Total  : $ramTotal GB" -ForegroundColor White
Write-Host "  RAM Usada  : $ramUsada GB ($ramPct%)" -ForegroundColor $(if ($ramPct -gt 80) { "Red" } elseif ($ramPct -gt 60) { "Yellow" } else { "Green" })
Write-Host "  RAM Livre  : $ramLivre GB" -ForegroundColor White
Write-Host "  Processador: $($cpu.Name.Trim())" -ForegroundColor White
Write-Host "  Nucleos    : $($cpu.NumberOfCores) fisicos / $($cpu.NumberOfLogicalProcessors) logicos" -ForegroundColor White

$relatorio.Add("`nRECURSOS DO SISTEMA")
$relatorio.Add("  RAM Total : $ramTotal GB | Usada: $ramUsada GB ($ramPct%) | Livre: $ramLivre GB")
$relatorio.Add("  CPU       : $($cpu.Name.Trim()) | Nucleos: $($cpu.NumberOfCores)f / $($cpu.NumberOfLogicalProcessors)l")

# ─────────────────────────────────────────────
#  ETAPA 2 — MEDIR USO DE CPU EM TEMPO REAL
# ─────────────────────────────────────────────

Write-Header "ETAPA 2 — MEDINDO USO DE CPU (aguarde 2 segundos...)"

Write-Host "  Coletando amostras de CPU..." -ForegroundColor Gray
$cpuPorProcesso = Get-CpuUsagePerProcess
Write-Host "  Medicao concluida." -ForegroundColor Green

# ─────────────────────────────────────────────
#  ETAPA 3 — PROCESSOS COM MAIOR CONSUMO
# ─────────────────────────────────────────────

Write-Header "ETAPA 3 — TOP $TopProcessCount PROCESSOS POR USO DE RECURSOS"

$processos = Get-Process | Where-Object { $_.Id -gt 0 } |
    ForEach-Object {
        $cpu2 = if ($cpuPorProcesso.ContainsKey($_.Id)) { $cpuPorProcesso[$_.Id] } else { 0.0 }
        $memMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
        $ehEssencial = $ProcessosEssenciaisWindows -contains $_.ProcessName
        $risco = Get-RiskLevel -Cpu $cpu2 -MemMB $memMB -EhEssencial $ehEssencial
        [PSCustomObject]@{
            PID         = $_.Id
            Nome        = $_.ProcessName
            CPU_Pct     = $cpu2
            RAM_MB      = $memMB
            Janelas     = $_.MainWindowTitle
            Essencial   = $ehEssencial
            Risco       = $risco
            Descricao   = $_.Description
            Caminho     = try { $_.Path } catch { "N/A" }
        }
    } |
    Sort-Object -Property @{E='CPU_Pct'; D=$true}, @{E='RAM_MB'; D=$true} |
    Select-Object -First $TopProcessCount

Write-SubHeader "Processos por consumo de CPU + RAM"

$formatoCabecalho = "  {0,-8} {1,-35} {2,8} {3,10} {4,-10}"
Write-Host ($formatoCabecalho -f "PID", "Processo", "CPU%", "RAM (MB)", "Risco") -ForegroundColor White
Write-Host ("  " + "-" * 75) -ForegroundColor DarkGray

foreach ($p in $processos) {
    $cor = Get-RiskColor -Nivel $p.Risco
    $linha = $formatoCabecalho -f $p.PID, $p.Nome.Substring(0, [Math]::Min($p.Nome.Length, 34)), $p.CPU_Pct, $p.RAM_MB, $p.Risco
    Write-Host $linha -ForegroundColor $cor
    $relatorio.Add($linha)
}

# ─────────────────────────────────────────────
#  ETAPA 4 — PROCESSOS SUSPEITOS / DESNECESSARIOS
# ─────────────────────────────────────────────

Write-Header "ETAPA 4 — PROCESSOS POTENCIALMENTE DESNECESSARIOS"

$todosProcessos = Get-Process | ForEach-Object {
    $cpu2 = if ($cpuPorProcesso.ContainsKey($_.Id)) { $cpuPorProcesso[$_.Id] } else { 0.0 }
    $memMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
    [PSCustomObject]@{
        Nome      = $_.ProcessName
        PID       = $_.Id
        CPU_Pct   = $cpu2
        RAM_MB    = $memMB
        Essencial = ($ProcessosEssenciaisWindows -contains $_.ProcessName)
        SemJanela = ($_.MainWindowHandle -eq 0)
        Caminho   = try { $_.Path } catch { "" }
    }
}

$desnecessarios = $todosProcessos |
    Where-Object {
        -not $_.Essencial -and
        $_.SemJanela -and
        ($_.CPU_Pct -gt $CpuThreshold -or $_.RAM_MB -gt $MemoryThresholdMB)
    } |
    Sort-Object -Property RAM_MB -Descending

if ($desnecessarios.Count -eq 0) {
    Write-Host "`n  Nenhum processo claramente desnecessario identificado." -ForegroundColor Green
} else {
    Write-Host "`n  Encontrados $($desnecessarios.Count) processo(s) rodando em segundo plano sem janela visivel:`n" -ForegroundColor Yellow
    $relatorio.Add("`nPROCESSOS POTENCIALMENTE DESNECESSARIOS ($($desnecessarios.Count) encontrados)")

    foreach ($p in $desnecessarios) {
        $cor = Get-RiskColor -Nivel (Get-RiskLevel -Cpu $p.CPU_Pct -MemMB $p.RAM_MB -EhEssencial $false)
        $info = "  [{0,6}] {1,-35} CPU: {2,6}%  RAM: {3,7} MB  | {4}" -f $p.PID, $p.Nome, $p.CPU_Pct, $p.RAM_MB, $(if ($p.Caminho) { $p.Caminho } else { "Caminho nao disponivel" })
        Write-Host $info -ForegroundColor $cor
        $relatorio.Add($info)
    }
}

# ─────────────────────────────────────────────
#  ETAPA 5 — PROGRAMAS DE INICIALIZACAO
# ─────────────────────────────────────────────

Write-Header "ETAPA 5 — PROGRAMAS QUE INICIAM COM O WINDOWS"

$regPaths = @(
    @{ Nome = "Todos os usuarios (HKLM Run)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" },
    @{ Nome = "Usuario atual (HKCU Run)";     Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" },
    @{ Nome = "Todos (HKLM RunOnce)";         Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" },
    @{ Nome = "Usuario (HKCU RunOnce)";       Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" },
    @{ Nome = "Todos (64-bit WOW)";           Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" }
)

$totalInicio = 0
$relatorio.Add("`nPROGRAMAS DE INICIALIZACAO")

foreach ($reg in $regPaths) {
    try {
        $items = Get-ItemProperty -Path $reg.Path -ErrorAction SilentlyContinue
        if ($items) {
            $valores = $items.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }
            if ($valores.Count -gt 0) {
                Write-SubHeader $reg.Nome
                $relatorio.Add("`n  $($reg.Nome)")
                foreach ($v in $valores) {
                    $totalInicio++
                    $linha = "    [{0,-30}] => {1}" -f $v.Name, $v.Value
                    Write-Host $linha -ForegroundColor Cyan
                    $relatorio.Add($linha)
                }
            }
        }
    } catch {}
}

# Pasta de inicializacao do usuario
$startupFolder = [System.Environment]::GetFolderPath('Startup')
$startupItems  = Get-ChildItem -Path $startupFolder -ErrorAction SilentlyContinue

if ($startupItems -and $startupItems.Count -gt 0) {
    Write-SubHeader "Pasta Inicializacao do Usuario"
    $relatorio.Add("`n  Pasta Inicializacao do Usuario")
    foreach ($item in $startupItems) {
        $totalInicio++
        $linha = "    $($item.Name)"
        Write-Host $linha -ForegroundColor Cyan
        $relatorio.Add($linha)
    }
}

Write-Host "`n  Total de entradas de inicializacao encontradas: $totalInicio" -ForegroundColor $(if ($totalInicio -gt 15) { "Red" } elseif ($totalInicio -gt 8) { "Yellow" } else { "Green" })

# ─────────────────────────────────────────────
#  ETAPA 6 — SERVICOS EM EXECUCAO (nao-Microsoft)
# ─────────────────────────────────────────────

Write-Header "ETAPA 6 — SERVICOS DE TERCEIROS EM EXECUCAO"

$servicosRodando = Get-Service | Where-Object { $_.Status -eq 'Running' }

$servicosTerceiros = $servicosRodando | ForEach-Object {
    try {
        $wmi = Get-CimInstance Win32_Service -Filter "Name='$($_.Name)'" -ErrorAction SilentlyContinue
        if ($wmi -and $wmi.PathName -and
            $wmi.PathName -notmatch 'System32|SysWOW64|\\Windows\\' -and
            $wmi.StartName -ne 'LocalSystem' -or
            ($wmi -and $wmi.PathName -and $wmi.PathName -notmatch 'Microsoft|Windows')) {
            [PSCustomObject]@{
                Nome        = $_.Name
                NomeExibido = $_.DisplayName
                Caminho     = $wmi.PathName
                ContaInicio = $wmi.StartName
            }
        }
    } catch {}
} | Where-Object { $_ -ne $null }

if ($servicosTerceiros.Count -eq 0) {
    Write-Host "`n  Nenhum servico de terceiro claramente identificado (execute como Admin para mais detalhes)." -ForegroundColor Gray
} else {
    Write-Host "`n  Servicos de terceiros em execucao ($($servicosTerceiros.Count)):`n" -ForegroundColor Yellow
    $relatorio.Add("`nSERVICOS DE TERCEIROS EM EXECUCAO")
    foreach ($s in $servicosTerceiros) {
        $linha = "  [{0,-30}] {1}" -f $s.Nome, $s.NomeExibido
        Write-Host $linha -ForegroundColor Cyan
        if ($s.Caminho) {
            Write-Host "    Caminho: $($s.Caminho)" -ForegroundColor DarkGray
        }
        $relatorio.Add($linha)
        $relatorio.Add("    Caminho: $($s.Caminho)")
    }
}

# ─────────────────────────────────────────────
#  ETAPA 7 — TAREFAS AGENDADAS ATIVAS (nao-Microsoft)
# ─────────────────────────────────────────────

Write-Header "ETAPA 7 — TAREFAS AGENDADAS ATIVAS (nao-Microsoft)"

try {
    $tarefas = Get-ScheduledTask |
        Where-Object {
            $_.State -eq 'Ready' -and
            $_.TaskPath -notmatch '\\Microsoft\\' -and
            $_.TaskPath -notmatch '\\Windows\\'
        } |
        Sort-Object TaskName

    if ($tarefas.Count -eq 0) {
        Write-Host "`n  Nenhuma tarefa agendada de terceiros ativa encontrada." -ForegroundColor Green
    } else {
        Write-Host "`n  Tarefas agendadas de terceiros ($($tarefas.Count)):`n" -ForegroundColor Yellow
        $relatorio.Add("`nTAREFAS AGENDADAS DE TERCEIROS ($($tarefas.Count))")
        foreach ($t in $tarefas) {
            $acao = ($t.Actions | ForEach-Object { $_.Execute }) -join "; "
            $linha = "  [{0,-40}] {1}" -f $t.TaskName.Substring(0, [Math]::Min($t.TaskName.Length,39)), $acao
            Write-Host $linha -ForegroundColor Cyan
            $relatorio.Add($linha)
        }
    }
} catch {
    Write-Host "`n  Requer privilegios de Administrador para listar tarefas agendadas." -ForegroundColor DarkYellow
}

# ─────────────────────────────────────────────
#  ETAPA 8 — CONEXOES DE REDE ATIVAS
# ─────────────────────────────────────────────

Write-Header "ETAPA 8 — CONEXOES DE REDE ATIVAS EM SEGUNDO PLANO"

try {
    $conexoes = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            if ($proc -and -not ($ProcessosEssenciaisWindows -contains $proc.ProcessName)) {
                [PSCustomObject]@{
                    Processo  = $proc.ProcessName
                    PID       = $_.OwningProcess
                    LocalPort = $_.LocalPort
                    RemoteIP  = $_.RemoteAddress
                    RemPort   = $_.RemotePort
                }
            }
        } |
        Where-Object { $_ -ne $null } |
        Group-Object Processo |
        Sort-Object Count -Descending

    if ($conexoes.Count -eq 0) {
        Write-Host "`n  Nenhuma conexao de terceiros identificada." -ForegroundColor Green
    } else {
        Write-Host "`n  Processos com conexoes de rede ativas:`n" -ForegroundColor Yellow
        $relatorio.Add("`nCONEXOES DE REDE ATIVAS")
        foreach ($g in $conexoes) {
            $linha = "  [{0,-30}] {1,3} conexao(oes)" -f $g.Name, $g.Count
            Write-Host $linha -ForegroundColor Cyan
            $relatorio.Add($linha)
            foreach ($c in $g.Group | Select-Object -First 3) {
                $detalhe = "    -> $($c.RemoteIP):$($c.RemPort)"
                Write-Host $detalhe -ForegroundColor DarkGray
                $relatorio.Add($detalhe)
            }
        }
    }
} catch {
    Write-Host "`n  Erro ao listar conexoes de rede." -ForegroundColor DarkYellow
}

# ─────────────────────────────────────────────
#  ETAPA 9 — SUMARIO E RECOMENDACOES
# ─────────────────────────────────────────────

Write-Header "ETAPA 9 — SUMARIO E RECOMENDACOES"

$totalProcessos   = (Get-Process).Count
$processosAltoRisco = $todosProcessos | Where-Object {
    -not $_.Essencial -and ($_.CPU_Pct -gt 20 -or $_.RAM_MB -gt 500)
}

Write-Host @"

  SUMARIO:
    Total de processos ativos      : $totalProcessos
    Processos de alto consumo      : $($processosAltoRisco.Count)
    Entradas de inicializacao      : $totalInicio
    Servicos de terceiros ativos   : $($servicosTerceiros.Count)

  RECOMENDACOES GERAIS:
    [1] Abra o Gerenciador de Tarefas (Ctrl+Shift+Esc) para encerrar processos pesados
    [2] Use 'msconfig' -> Inicializacao para desabilitar programas desnecessarios
    [3] Use 'services.msc' para definir servicos de terceiros como 'Manual' ou desabilitar
    [4] Use 'taskschd.msc' para gerenciar tarefas agendadas de terceiros
    [5] Considere ferramentas como Autoruns (Sysinternals) para analise profunda
    [6] Para servicos desnecessarios: clique com botao direito -> Propriedades -> Desabilitar

"@ -ForegroundColor White

$relatorio.Add("`nSUMARIO")
$relatorio.Add("  Total de processos    : $totalProcessos")
$relatorio.Add("  Alto consumo          : $($processosAltoRisco.Count)")
$relatorio.Add("  Entradas inicializacao: $totalInicio")
$relatorio.Add("  Servicos de terceiros : $($servicosTerceiros.Count)")

# ─────────────────────────────────────────────
#  EXPORTAR RELATORIO
# ─────────────────────────────────────────────

if ($ExportarRelatorio) {
    try {
        $relatorio | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "  Relatorio salvo em: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Host "  Erro ao salvar relatorio: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  Dica: Use o parametro -ExportarRelatorio para salvar o relatorio em disco." -ForegroundColor DarkYellow
    Write-Host "  Exemplo: .\Analyze-BackgroundPrograms.ps1 -ExportarRelatorio`n" -ForegroundColor DarkYellow
}

Write-Host "  Analise concluida." -ForegroundColor Green
