#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restaura servicos de impressao desativados/atrasados pelo TurboStartup.ps1

.DESCRIPTION
    O TurboStartup.ps1 desativou upnphost e atrasou fdPHost, FDResPub
    e PrintNotify, causando falha em impressoras USB e de rede (WSD/WiFi).
    Este script restaura todos os servicos e limpa a fila de impressao.

.NOTES
    Requer: PowerShell 5.1 + Administrador
    Testado: Windows 10/11
#>

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "=== Reparo de Impressora ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Servicos necessarios para impressao
# ============================================================
# Spooler      = motor de impressao (Automatic)
# PrintNotify  = notificacoes/UI de impressao (Manual)
# fdPHost      = Function Discovery - protocolo WSD moderno (Automatic)
# FDResPub     = publicacao de dispositivos na rede (Automatic)
# upnphost     = UPnP - descoberta de impressoras de rede (Manual) *DESATIVADO*
# SSDPSRV      = SSDP Discovery - suporte a UPnP (Manual)

$servicos = @(
    'Spooler',
    'PrintNotify',
    'fdPHost',
    'FDResPub',
    'upnphost',
    'SSDPSRV'
)

$startTypes = @{
    'Spooler'     = 2   # Automatic
    'PrintNotify' = 3   # Manual
    'fdPHost'     = 2   # Automatic
    'FDResPub'    = 2   # Automatic
    'upnphost'    = 3   # Manual
    'SSDPSRV'     = 3   # Manual
}

$startNames = @{
    'Spooler'     = 'Automatic'
    'PrintNotify' = 'Manual'
    'fdPHost'     = 'Automatic'
    'FDResPub'    = 'Automatic'
    'upnphost'    = 'Manual'
    'SSDPSRV'     = 'Manual'
}

$descricoes = @{
    'Spooler'     = 'Motor de impressao'
    'PrintNotify' = 'Interface e notificacoes de impressao'
    'fdPHost'     = 'Function Discovery - protocolo WSD (impressoras modernas)'
    'FDResPub'    = 'Publicacao de dispositivos na rede'
    'upnphost'    = 'UPnP - descoberta de impressoras de rede  [ESTAVA DESATIVADO]'
    'SSDPSRV'     = 'SSDP Discovery - suporte a UPnP'
}

# ============================================================
# 1. Restaurar e iniciar servicos
# ============================================================
Write-Host "[1/4] Restaurando servicos de impressao..." -ForegroundColor Yellow
Write-Host ""

foreach ($nome in $servicos) {
    $desc = $descricoes[$nome]
    $tipo = $startNames[$nome]
    Write-Host ("  {0,-14} {1}" -f $nome, $desc) -ForegroundColor White

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$nome"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name 'Start'            -Value $startTypes[$nome] -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name 'DelayedAutostart' -Value 0                  -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host ("             Registro: Start={0}, DelayedAutostart=0  OK" -f $tipo) -ForegroundColor Green
    }

    try {
        Set-Service -Name $nome -StartupType $tipo -ErrorAction Stop
        Write-Host ("             Set-Service: {0}  OK" -f $tipo) -ForegroundColor Green
    } catch {
        Write-Host "             Set-Service: ignorado" -ForegroundColor DarkGray
    }

    try {
        Start-Service -Name $nome -ErrorAction Stop
        Write-Host "             Start-Service: Rodando  OK" -ForegroundColor Green
    } catch {
        sc.exe start $nome | Out-Null
        Start-Sleep -Seconds 1
        $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Host "             sc.exe: Rodando  OK" -ForegroundColor Green
        } else {
            $st = if ($svc) { $svc.Status } else { 'nao encontrado' }
            Write-Host ("             sc.exe: {0}" -f $st) -ForegroundColor Yellow
        }
    }

    Write-Host ""
}

# ============================================================
# 2. Limpar fila de impressao travada (causa comum de impressora inacessivel)
# ============================================================
Write-Host "[2/4] Limpando fila de impressao..." -ForegroundColor Yellow

try {
    Stop-Service -Name Spooler -Force -ErrorAction Stop
    Write-Host "  Spooler parado  OK" -ForegroundColor Green
} catch {
    sc.exe stop Spooler | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "  Spooler parado via sc.exe" -ForegroundColor Green
}

$spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
if (Test-Path $spoolPath) {
    $arquivos = Get-ChildItem -Path $spoolPath -Force -ErrorAction SilentlyContinue
    if ($arquivos) {
        $arquivos | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "  Fila limpa ($($arquivos.Count) arquivo(s) removido(s))  OK" -ForegroundColor Green
    } else {
        Write-Host "  Fila ja estava vazia  OK" -ForegroundColor Green
    }
}

try {
    Start-Service -Name Spooler -ErrorAction Stop
    Write-Host "  Spooler reiniciado  OK" -ForegroundColor Green
} catch {
    sc.exe start Spooler | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "  Spooler reiniciado via sc.exe" -ForegroundColor Green
}

# ============================================================
# 3. Status final dos servicos
# ============================================================
Write-Host ""
Write-Host "[3/4] Status final dos servicos..." -ForegroundColor Yellow
Write-Host ""
Write-Host ("  {0,-14} {1,-12} {2}" -f "Servico", "Status", "StartupType") -ForegroundColor DarkGray

foreach ($nome in $servicos) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if ($svc) {
        $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$nome'" -ErrorAction SilentlyContinue
        if ($cim) {
            $startMode = $cim.StartMode
        } else {
            $startMode = '?'
        }
        if ($svc.Status -eq 'Running') {
            $cor = 'Green'
        } else {
            $cor = 'Yellow'
        }
        Write-Host ("  {0,-14} {1,-12} {2}" -f $nome, $svc.Status, $startMode) -ForegroundColor $cor
    } else {
        Write-Host ("  {0,-14} NAO ENCONTRADO" -f $nome) -ForegroundColor Red
    }
}

# ============================================================
# 4. Listar impressoras instaladas
# ============================================================
Write-Host ""
Write-Host "[4/4] Impressoras instaladas..." -ForegroundColor Yellow
Write-Host ""

$impressoras = Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue
if ($impressoras) {
    foreach ($imp in $impressoras) {
        if ($imp.WorkOffline) {
            $estado = 'OFFLINE'
            $cor = 'Red'
        } else {
            $estado = 'Online'
            $cor = 'Green'
        }
        Write-Host ("  {0,-40} {1}" -f $imp.Name, $estado) -ForegroundColor $cor
    }
} else {
    Write-Host "  Nenhuma impressora encontrada." -ForegroundColor Yellow
    Write-Host "  Reconecte a impressora ou verifique o driver." -ForegroundColor Yellow
}

# ============================================================
# Conclusao
# ============================================================
Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Se a impressora ainda nao responder:" -ForegroundColor White
Write-Host "  1. Desligue e ligue a impressora." -ForegroundColor White
Write-Host "  2. Desconecte e reconecte o cabo USB." -ForegroundColor White
Write-Host "  3. Para impressora de rede: reconecte ao WiFi/cabo." -ForegroundColor White
Write-Host "  4. Se necessario, reinstale o driver da impressora." -ForegroundColor White
Write-Host ""

$resp = Read-Host "Deseja reiniciar o computador agora? (S/N)"
if ($resp -match '^[Ss]') {
    Write-Host "Reiniciando em 10 segundos... (Ctrl+C para cancelar)" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
