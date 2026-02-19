#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restaura o servico Windows Biometric (WbioSrvc) desativado pelo TurboStartup.ps1

.DESCRIPTION
    O TurboStartup.ps1 desativou o WbioSrvc por engano na lista de servicos opcionais.
    Este script restaura o servico para Automatic e reinicia o leitor de impressao digital.

.NOTES
    Execute como Administrador.
#>

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "=== Reparo do Leitor de Impressao Digital ===" -ForegroundColor Cyan
Write-Host ""

# 1. Restaurar Windows Biometric Service
Write-Host "[1/4] Restaurando servico WbioSrvc (Windows Biometric Service)..." -ForegroundColor Yellow
try {
    Set-Service -Name 'WbioSrvc' -StartupType Automatic -ErrorAction Stop
    Write-Host "      StartupType -> Automatic  OK" -ForegroundColor Green
} catch {
    Write-Host "      ERRO: $_" -ForegroundColor Red
}

# 2. Iniciar o servico agora
Write-Host "[2/4] Iniciando WbioSrvc..." -ForegroundColor Yellow
try {
    Start-Service -Name 'WbioSrvc' -ErrorAction Stop
    Write-Host "      Servico iniciado  OK" -ForegroundColor Green
} catch {
    Write-Host "      Tentando via sc.exe..." -ForegroundColor Yellow
    sc.exe start WbioSrvc | Out-Null
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name WbioSrvc -ErrorAction SilentlyContinue
    if ($svc.Status -eq 'Running') {
        Write-Host "      Servico iniciado via sc.exe  OK" -ForegroundColor Green
    } else {
        Write-Host "      ERRO: Nao foi possivel iniciar o servico." -ForegroundColor Red
    }
}

# 3. Verificar status atual
Write-Host "[3/4] Verificando status..." -ForegroundColor Yellow
$svc = Get-Service -Name WbioSrvc -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "      Nome    : $($svc.DisplayName)" -ForegroundColor White
    Write-Host "      Status  : $($svc.Status)" -ForegroundColor White
    $startType = (Get-WmiObject Win32_Service -Filter "Name='WbioSrvc'").StartMode
    Write-Host "      Startup : $startType" -ForegroundColor White
}

# 4. Reiniciar driver biometrico para forcar re-enumeracao
Write-Host "[4/4] Reiniciando dispositivos biometricos..." -ForegroundColor Yellow
$bioDevices = Get-PnpDevice -Class 'Biometric' -ErrorAction SilentlyContinue
if ($bioDevices) {
    foreach ($dev in $bioDevices) {
        Write-Host "      Dispositivo: $($dev.FriendlyName)" -ForegroundColor White
        try {
            Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 1
            Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction Stop
            Write-Host "      Reiniciado  OK" -ForegroundColor Green
        } catch {
            Write-Host "      AVISO: $_" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "      Nenhum dispositivo biometrico PnP detectado." -ForegroundColor Yellow
    Write-Host "      Verifique o Gerenciador de Dispositivos." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Proximo passo: teste o leitor de impressao digital agora." -ForegroundColor White
Write-Host "Se ainda nao funcionar, reinicie o computador." -ForegroundColor White
Write-Host ""

# Perguntar se quer reiniciar
$resp = Read-Host "Deseja reiniciar o computador agora? (S/N)"
if ($resp -match '^[Ss]') {
    Write-Host "Reiniciando em 10 segundos... (Ctrl+C para cancelar)" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
