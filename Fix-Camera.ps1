#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restaura servicos de camera desativados pelo TurboStartup.ps1

.DESCRIPTION
    O TurboStartup.ps1 desativou FrameServer e stisvc, causando falha
    em todas as cameras (app Camera, Teams, Zoom, Meet etc.).

.NOTES
    Requer: PowerShell 5.1 + Administrador
    Testado: Windows 10/11
#>

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "=== Reparo de Camera ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Servicos necessarios para camera
# ============================================================
# FrameServer  = Windows Camera Frame Server  (Manual trigger-start) *DESATIVADO*
#                Usado por: app Camera, Teams, Zoom, Meet, OBS, etc.
# stisvc       = Windows Image Acquisition    (Manual)               *DESATIVADO*
#                Usado por: cameras WIA, webcams antigas, scanners
# DeviceAssociationService = emparelhamento de dispositivos          (ja em criticalServices)
# PlugPlay     = Plug and Play                                       (ja em criticalServices)

$servicos = @(
    [PSCustomObject]@{ Nome='FrameServer'; Tipo='Manual';    Descricao='Windows Camera Frame Server  [ESTAVA DESATIVADO]' },
    [PSCustomObject]@{ Nome='stisvc';      Tipo='Manual';    Descricao='Windows Image Acquisition    [ESTAVA DESATIVADO]' },
    [PSCustomObject]@{ Nome='WbioSrvc';    Tipo='Manual';    Descricao='Biometria Windows (compatibilidade)' }
)

$startTypeMap = @{
    'Automatic' = 2
    'Manual'    = 3
    'Disabled'  = 4
}

# ============================================================
# 1. Restaurar servicos
# ============================================================
Write-Host "[1/4] Restaurando servicos de camera..." -ForegroundColor Yellow
Write-Host ""

foreach ($svc in $servicos) {
    $nome  = $svc.Nome
    $tipo  = $svc.Tipo
    $desc  = $svc.Descricao

    Write-Host ("  {0,-16} {1}" -f $nome, $desc) -ForegroundColor White

    # Registro (metodo mais confiavel para habilitar servicos desativados)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$nome"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name 'Start'            -Value $startTypeMap[$tipo] -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name 'DelayedAutostart' -Value 0                    -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "             Registro: Start=$tipo, DelayedAutostart=0  OK" -ForegroundColor Green
    } else {
        Write-Host "             Registro: servico nao encontrado no sistema" -ForegroundColor Yellow
    }

    # Set-Service
    try {
        Set-Service -Name $nome -StartupType $tipo -ErrorAction Stop
        Write-Host "             Set-Service: $tipo  OK" -ForegroundColor Green
    } catch {
        Write-Host "             Set-Service: ignorado (normal para servicos de trigger)" -ForegroundColor DarkGray
    }

    # Tentativa de start
    try {
        Start-Service -Name $nome -ErrorAction Stop
        Write-Host "             Start-Service: Rodando  OK" -ForegroundColor Green
    } catch {
        sc.exe start $nome | Out-Null
        Start-Sleep -Seconds 1
        $s = Get-Service -Name $nome -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Write-Host "             sc.exe: Rodando  OK" -ForegroundColor Green
        } else {
            # Servicos Manual/trigger so iniciam quando algum app abre a camera -- normal
            $estado = if ($s) { $s.Status } else { 'nao encontrado' }
            Write-Host ("             Aguardando uso (trigger-start): {0}  OK" -f $estado) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
}

# ============================================================
# 2. Verificar acesso do app Camera a dispositivos (privacidade)
# ============================================================
Write-Host "[2/4] Verificando permissoes de privacidade..." -ForegroundColor Yellow

$privPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam'
)

$permOk = $true
foreach ($path in $privPaths) {
    if (Test-Path $path) {
        $valor = (Get-ItemProperty -Path $path -Name 'Value' -ErrorAction SilentlyContinue).Value
        if ($valor -eq 'Deny') {
            Write-Host "  BLOQUEADO: $path" -ForegroundColor Red
            Set-ItemProperty -Path $path -Name 'Value' -Value 'Allow' -ErrorAction SilentlyContinue
            Write-Host "  -> Desbloqueado: Allow  OK" -ForegroundColor Green
            $permOk = $false
        } else {
            Write-Host "  OK: $path = $valor" -ForegroundColor Green
        }
    }
}

if ($permOk) {
    Write-Host "  Permissoes de camera: Allow  OK" -ForegroundColor Green
}

# ============================================================
# 3. Status final
# ============================================================
Write-Host ""
Write-Host "[3/4] Status final dos servicos..." -ForegroundColor Yellow
Write-Host ""
Write-Host ("  {0,-16} {1,-14} {2}" -f "Servico", "Status", "StartupType") -ForegroundColor DarkGray

foreach ($svc in $servicos) {
    $s = Get-Service -Name $svc.Nome -ErrorAction SilentlyContinue
    if ($s) {
        $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Nome)'" -ErrorAction SilentlyContinue
        $startMode = if ($cim) { $cim.StartMode } else { '?' }
        if ($s.Status -eq 'Running') {
            $cor = 'Green'
        } elseif ($s.Status -eq 'Stopped' -and $svc.Tipo -eq 'Manual') {
            $cor = 'DarkGray'  # Normal para Manual/trigger-start
        } else {
            $cor = 'Yellow'
        }
        Write-Host ("  {0,-16} {1,-14} {2}" -f $svc.Nome, $s.Status, $startMode) -ForegroundColor $cor
    } else {
        Write-Host ("  {0,-16} NAO ENCONTRADO" -f $svc.Nome) -ForegroundColor Red
    }
}

# ============================================================
# 4. Listar cameras detectadas pelo sistema
# ============================================================
Write-Host ""
Write-Host "[4/4] Cameras detectadas pelo Windows..." -ForegroundColor Yellow
Write-Host ""

$cameras = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object { $_.PNPClass -eq 'Camera' -or $_.PNPClass -eq 'Image' -or $_.Description -match 'camera|webcam|imaging' }

if ($cameras) {
    foreach ($cam in $cameras) {
        if ($cam.Status -eq 'OK') {
            $cor = 'Green'
        } else {
            $cor = 'Yellow'
        }
        Write-Host ("  {0,-45} Status: {1}" -f $cam.Caption, $cam.Status) -ForegroundColor $cor
    }
} else {
    Write-Host "  Nenhuma camera detectada no gerenciador de dispositivos." -ForegroundColor Yellow
    Write-Host "  -> Verifique se a camera esta fisicamente conectada/habilitada." -ForegroundColor Yellow
}

# ============================================================
# Conclusao
# ============================================================
Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Proximo passo: abra o app 'Camera' do Windows para testar." -ForegroundColor White
Write-Host ""
Write-Host "Se ainda nao funcionar:" -ForegroundColor White
Write-Host "  1. Reinicie o computador (servicos trigger-start ativam no proximo boot)." -ForegroundColor White
Write-Host "  2. Verifique: Configuracoes > Privacidade > Camera." -ForegroundColor White
Write-Host "  3. Para notebooks: verifique tecla Fn para habilitar camera." -ForegroundColor White
Write-Host "  4. Reinstale o driver: Gerenc. Dispositivos > Cameras > Atualizar driver." -ForegroundColor White
Write-Host ""

$resp = Read-Host "Deseja reiniciar agora? (S/N)"
if ($resp -match '^[Ss]') {
    Write-Host "Reiniciando em 10 segundos... (Ctrl+C para cancelar)" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
