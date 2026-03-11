#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Diagnostica anomalias de CPU, handles e threads; oferece limpeza segura.

.DESCRIPTION
    Analisa os processos responsaveis por alto numero de handles, threads e CPU.
    Identifica vazamentos de handles (handle leaks) e oferece acoes corretivas
    sem encerrar processos criticos do sistema.

.NOTES
    Requer: PowerShell 5.1 + Administrador
    Testado: Windows 10/11 (Intel i7-1355U e similares)
#>

$ErrorActionPreference = 'Continue'
Set-StrictMode -Off

# ─── Thresholds ────────────────────────────────────────────────────────────────
$HANDLE_WARN   = 2000   # handles por processo — aviso
$HANDLE_CRITIC = 5000   # handles por processo — critico
$THREAD_WARN   = 80     # threads por processo — aviso
$CPU_WARN      = 15     # % CPU por processo — aviso (medido em 2 amostras)

# ─── Processos do sistema que NUNCA devem ser encerrados ───────────────────────
$PROC_PROTEGIDOS = @(
    'System','Idle','smss','csrss','wininit','winlogon','services',
    'lsass','svchost','dwm','fontdrvhost','MsMpEng','NisSrv',
    'Memory Compression','Registry','spoolsv','explorer'
)

# ─── Helpers ───────────────────────────────────────────────────────────────────
function Write-Secao ($texto) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
    Write-Host "  $texto" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkCyan
}

function Status-Cor ($valor, $aviso, $critico) {
    if ($valor -ge $critico) { return 'Red' }
    if ($valor -ge $aviso)   { return 'Yellow' }
    return 'Green'
}

# ─── Cabecalho ─────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  DIAGNOSTICO DE CPU / HANDLES / THREADS" -ForegroundColor White
Write-Host "  PowerShell 5.1  |  $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

# ─── 1. Snapshot do sistema ────────────────────────────────────────────────────
Write-Secao "1/5  Resumo do sistema"

$os       = Get-WmiObject Win32_OperatingSystem
$cpu      = Get-WmiObject Win32_Processor | Select-Object -First 1
$uptime   = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
$allProcs = Get-Process -ErrorAction SilentlyContinue

$totalHandles = ($allProcs | Measure-Object Handles -Sum).Sum
$totalThreads = ($allProcs | Measure-Object Threads.Count -Sum).Sum
$totalProcs   = $allProcs.Count

$corH = Status-Cor $totalHandles 45000 65000
$corT = Status-Cor $totalThreads 1500  2000

Write-Host "  CPU       : $($cpu.Name.Trim())"                    -ForegroundColor White
Write-Host "  Uptime    : $($uptime.Hours)h $($uptime.Minutes)m"  -ForegroundColor White
Write-Host "  Processos : $totalProcs"                             -ForegroundColor White
Write-Host ("  Handles   : {0:N0}" -f $totalHandles)              -ForegroundColor $corH
Write-Host ("  Threads   : {0:N0}" -f $totalThreads)              -ForegroundColor $corT

if ($totalHandles -ge 65000) {
    Write-Host ""
    Write-Host "  [!] Handle leak detectado — risco de instabilidade." -ForegroundColor Red
} elseif ($totalHandles -ge 45000) {
    Write-Host ""
    Write-Host "  [!] Handles elevados — monitorar." -ForegroundColor Yellow
}

# ─── 2. Top 15 por handles ─────────────────────────────────────────────────────
Write-Secao "2/5  Top 15 processos por handles"
Write-Host ("  {0,-28} {1,8}  {2,-8}" -f "Processo","Handles","Status") -ForegroundColor DarkGray

$topHandles = $allProcs | Sort-Object Handles -Descending | Select-Object -First 15
foreach ($p in $topHandles) {
    $h   = $p.Handles
    $cor = Status-Cor $h $HANDLE_WARN $HANDLE_CRITIC
    $tag = if ($h -ge $HANDLE_CRITIC) { 'CRITICO' } elseif ($h -ge $HANDLE_WARN) { 'AVISO' } else { 'OK' }
    Write-Host ("  {0,-28} {1,8}  {2,-8}" -f $p.ProcessName, ("{0:N0}" -f $h), $tag) -ForegroundColor $cor
}

# ─── 3. Top 15 por threads ────────────────────────────────────────────────────
Write-Secao "3/5  Top 15 processos por threads"
Write-Host ("  {0,-28} {1,8}  {2,-8}" -f "Processo","Threads","Status") -ForegroundColor DarkGray

$topThreads = $allProcs | Sort-Object { $_.Threads.Count } -Descending | Select-Object -First 15
foreach ($p in $topThreads) {
    $t   = $p.Threads.Count
    $cor = Status-Cor $t $THREAD_WARN ($THREAD_WARN * 3)
    $tag = if ($t -ge ($THREAD_WARN * 3)) { 'CRITICO' } elseif ($t -ge $THREAD_WARN) { 'AVISO' } else { 'OK' }
    Write-Host ("  {0,-28} {1,8}  {2,-8}" -f $p.ProcessName, $t, $tag) -ForegroundColor $cor
}

# ─── 4. Top 10 por CPU (2 amostras, delta 1 s) ────────────────────────────────
Write-Secao "4/5  Top 10 processos por CPU (amostra 1 s)"
Write-Host "  Aguardando amostra..." -ForegroundColor DarkGray

$snap1 = Get-WmiObject Win32_PerfRawData_PerfProc_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } |
    Select-Object Name, PercentProcessorTime, Timestamp_Sys100NS

Start-Sleep -Seconds 1

$snap2 = Get-WmiObject Win32_PerfRawData_PerfProc_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } |
    Select-Object Name, PercentProcessorTime, Timestamp_Sys100NS

$numCores = ($allProcs | Where-Object { $_.ProcessName -eq 'System' } | Select-Object -First 1) | ForEach-Object { [Environment]::ProcessorCount }
if (-not $numCores) { $numCores = 1 }

$cpuDelta = foreach ($s2 in $snap2) {
    $s1 = $snap1 | Where-Object { $_.Name -eq $s2.Name } | Select-Object -First 1
    if ($s1) {
        $dCPU  = $s2.PercentProcessorTime - $s1.PercentProcessorTime
        $dTime = $s2.Timestamp_Sys100NS    - $s1.Timestamp_Sys100NS
        if ($dTime -gt 0) {
            $pct = [Math]::Round(($dCPU / $dTime) * 100 / $numCores, 1)
            [PSCustomObject]@{ Nome = $s2.Name; CPU = $pct }
        }
    }
}

Write-Host ("  {0,-28} {1,8}" -f "Processo","CPU %") -ForegroundColor DarkGray
$cpuDelta | Sort-Object CPU -Descending | Select-Object -First 10 | ForEach-Object {
    $cor = Status-Cor $_.CPU $CPU_WARN ($CPU_WARN * 3)
    Write-Host ("  {0,-28} {1,8:N1} %" -f $_.Nome, $_.CPU) -ForegroundColor $cor
}

# ─── 5. Limpeza segura ────────────────────────────────────────────────────────
Write-Secao "5/5  Limpeza segura (sem reinicio)"

$acoes = [System.Collections.ArrayList]@()

# 5a. Flush DNS
[void]$acoes.Add([PSCustomObject]@{
    Descricao = 'Limpar cache DNS (ipconfig /flushdns)'
    Acao      = { ipconfig /flushdns | Out-Null }
    Risco     = 'Nenhum'
})

# 5b. Limpar arquivos temporarios do usuario
[void]$acoes.Add([PSCustomObject]@{
    Descricao = "Excluir temporarios do usuario ($env:TEMP)"
    Acao      = {
        Get-ChildItem -Path $env:TEMP -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Risco     = 'Baixo'
})

# 5c. Liberar Working Set de processos nao protegidos (reduz uso de RAM sem encerrar)
[void]$acoes.Add([PSCustomObject]@{
    Descricao = 'Minimizar Working Set de processos de terceiros (libera RAM/handles)'
    Acao      = {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ProcMem {
    [DllImport("kernel32.dll")] public static extern bool SetProcessWorkingSetSize(IntPtr h, IntPtr min, IntPtr max);
}
'@ -ErrorAction SilentlyContinue
        $protNames = @('System','Idle','smss','csrss','wininit','winlogon','services',
                       'lsass','svchost','dwm','fontdrvhost','MsMpEng','NisSrv',
                       'Memory Compression','Registry','spoolsv','explorer')
        Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $protNames -notcontains $_.ProcessName
        } | ForEach-Object {
            try { [ProcMem]::SetProcessWorkingSetSize($_.Handle, [IntPtr](-1), [IntPtr](-1)) | Out-Null }
            catch { }
        }
        Write-Host "      Working sets minimizados." -ForegroundColor Green
    }
    Risco     = 'Nenhum'
})

# 5d. Reiniciar servicos conhecidos por vazar handles
$svcLeakers = @('WSearch','DiagTrack','TabletInputService','WerSvc','SysMain')
$svcsParaReiniciar = [System.Collections.ArrayList]@()
foreach ($svcName in $svcLeakers) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        [void]$svcsParaReiniciar.Add($svcName)
    }
}

if ($svcsParaReiniciar.Count -gt 0) {
    $nomes = $svcsParaReiniciar -join ', '
    [void]$acoes.Add([PSCustomObject]@{
        Descricao = "Reiniciar servicos suspeitos de handle leak: $nomes"
        Acao      = {
            foreach ($sn in $svcsParaReiniciar) {
                try {
                    Restart-Service -Name $sn -Force -ErrorAction Stop
                    Write-Host "      $sn reiniciado  OK" -ForegroundColor Green
                } catch {
                    Write-Host "      $sn ERRO: $_" -ForegroundColor Yellow
                }
            }
        }
        Risco     = 'Baixo'
    })
}

# 5e. Processos nao protegidos com handles criticos — perguntar um a um
$candidatos = $allProcs | Where-Object {
    $_.Handles -ge $HANDLE_CRITIC -and ($PROC_PROTEGIDOS -notcontains $_.ProcessName)
} | Sort-Object Handles -Descending

foreach ($c in $candidatos) {
    $nomeCap = $c.ProcessName
    [void]$acoes.Add([PSCustomObject]@{
        Descricao = "Encerrar '$nomeCap' (PID $($c.Id)) — $("{0:N0}" -f $c.Handles) handles"
        Acao      = {
            $proc = Get-Process -Id $c.Id -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-Process -Id $c.Id -Force -ErrorAction SilentlyContinue
                Write-Host "      $($c.ProcessName) encerrado." -ForegroundColor Green
            }
        }
        Risco     = 'Medio — o aplicativo sera fechado'
    })
}

# ─── Exibir acoes e perguntar ─────────────────────────────────────────────────
Write-Host ""
Write-Host "  Acoes disponiveis:" -ForegroundColor White
Write-Host ""
for ($i = 0; $i -lt $acoes.Count; $i++) {
    $a = $acoes[$i]
    Write-Host ("  [{0}] {1}" -f ($i + 1), $a.Descricao) -ForegroundColor White
    Write-Host ("       Risco: {0}" -f $a.Risco) -ForegroundColor DarkGray
}
Write-Host "  [T] Executar TODAS as acoes automaticamente" -ForegroundColor Cyan
Write-Host "  [N] Nenhuma — apenas exibir relatorio"      -ForegroundColor DarkGray
Write-Host ""

$resp = Read-Host "  Escolha (numeros separados por virgula, T ou N)"

$executarTodas = $resp -match '^[Tt]$'
$pular         = $resp -match '^[Nn]$'

if (-not $pular) {
    Write-Host ""
    for ($i = 0; $i -lt $acoes.Count; $i++) {
        $executar = $executarTodas -or ($resp -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq ($i + 1).ToString() }).Count -gt 0
        if ($executar) {
            Write-Host "  >> $($acoes[$i].Descricao)" -ForegroundColor Yellow
            & $acoes[$i].Acao
        }
    }
}

# ─── Resumo final ─────────────────────────────────────────────────────────────
Write-Secao "Relatorio salvo"

$relPath = "$env:USERPROFILE\Desktop\Diagnostico-CPU_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$relatorio = @"
DIAGNOSTICO DE CPU / HANDLES / THREADS
Gerado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
CPU: $($cpu.Name.Trim())
Uptime: $($uptime.Hours)h $($uptime.Minutes)m
Processos: $totalProcs  |  Handles: $("{0:N0}" -f $totalHandles)  |  Threads: $("{0:N0}" -f $totalThreads)

--- TOP 15 HANDLES ---
$($topHandles | Format-Table ProcessName,Handles -AutoSize | Out-String)

--- TOP 15 THREADS ---
$($topThreads | Format-Table ProcessName,@{N='Threads';E={$_.Threads.Count}} -AutoSize | Out-String)

--- TOP 10 CPU ---
$($cpuDelta | Sort-Object CPU -Descending | Select-Object -First 10 | Format-Table -AutoSize | Out-String)
"@

$relatorio | Out-File -FilePath $relPath -Encoding UTF8 -ErrorAction SilentlyContinue
Write-Host ""
if (Test-Path $relPath) {
    Write-Host "  Relatorio salvo em: $relPath" -ForegroundColor Green
} else {
    Write-Host "  Nao foi possivel salvar o relatorio." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Se os handles continuarem altos apos a limpeza, reinicie o computador." -ForegroundColor White
Write-Host ""
