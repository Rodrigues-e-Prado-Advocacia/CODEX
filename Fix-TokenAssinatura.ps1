#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restaura servicos de Smart Card desativados pelo TurboStartup.ps1

.DESCRIPTION
    O TurboStartup.ps1 desativou SCardSvr, ScDeviceEnum e SCPolicySvc,
    que sao obrigatorios para tokens USB de assinatura digital
    (eToken, SafeNet, Certisign, Serasa, OAB, NF-e, etc.).
    Este script restaura os tres servicos e verifica o token.

.NOTES
    Requer: PowerShell 5.1 + Administrador
    Testado: Windows 10/11
#>

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "=== Reparo de Token USB de Assinatura Digital ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# Servicos obrigatorios para tokens USB / Smart Cards
# ============================================================
$servicosToken = @(
    'SCardSvr',
    'ScDeviceEnum',
    'SCPolicySvc'
)

$descricoes = @{
    'SCardSvr'      = 'Smart Card - comunicacao com token USB'
    'ScDeviceEnum'  = 'Smart Card Device Enumeration Service'
    'SCPolicySvc'   = 'Smart Card Removal Policy'
}

# ============================================================
# 1. Restaurar startup type e iniciar cada servico
# ============================================================
Write-Host "[1/3] Restaurando servicos de Smart Card..." -ForegroundColor Yellow
Write-Host ""

foreach ($nome in $servicosToken) {
    Write-Host ("  Servico : {0} - {1}" -f $nome, $descricoes[$nome]) -ForegroundColor White

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$nome"
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name 'Start'            -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name 'DelayedAutostart' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  Registro: Start=3 (Manual), DelayedAutostart=0  OK" -ForegroundColor Green
    } else {
        Write-Host "  Registro: chave nao encontrada" -ForegroundColor Yellow
    }

    try {
        Set-Service -Name $nome -StartupType Manual -ErrorAction Stop
        Write-Host "  Set-Service: Manual  OK" -ForegroundColor Green
    } catch {
        Write-Host "  Set-Service: ignorado" -ForegroundColor DarkGray
    }

    try {
        Start-Service -Name $nome -ErrorAction Stop
        Write-Host "  Start-Service: Rodando  OK" -ForegroundColor Green
    } catch {
        sc.exe start $nome | Out-Null
        Start-Sleep -Seconds 1
        $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Host "  sc.exe start: Rodando  OK" -ForegroundColor Green
        } else {
            $st = if ($svc) { $svc.Status } else { 'nao encontrado' }
            Write-Host ("  sc.exe start: {0}" -f $st) -ForegroundColor Yellow
        }
    }

    Write-Host ""
}

# ============================================================
# 2. Verificar status atual dos tres servicos
# ============================================================
Write-Host "[2/3] Status atual dos servicos..." -ForegroundColor Yellow
Write-Host ""
Write-Host ("  {0,-20} {1,-12} {2}" -f "Servico", "Status", "StartupType") -ForegroundColor DarkGray

foreach ($nome in $servicosToken) {
    $svc = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if ($svc) {
        $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$nome'" -ErrorAction SilentlyContinue
        if ($cim) {
            $startMode = $cim.StartMode
        } else {
            $startMode = 'Desconhecido'
        }
        if ($svc.Status -eq 'Running') {
            $cor = 'Green'
        } else {
            $cor = 'Yellow'
        }
        Write-Host ("  {0,-20} {1,-12} {2}" -f $nome, $svc.Status, $startMode) -ForegroundColor $cor
    } else {
        Write-Host ("  {0,-20} NAO ENCONTRADO" -f $nome) -ForegroundColor Red
    }
}

Write-Host ""

# ============================================================
# 3. Detectar token USB conectado
# ============================================================
Write-Host "[3/3] Detectando token USB / Smart Card..." -ForegroundColor Yellow
Write-Host ""

$tokensEncontrados = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name     -match 'smart.?card|token|etoken|safenet|certisign|gemalto|oberthur|aladdin|watchdata|icp.?brasil' -or
        $_.PNPClass -eq 'SmartCardReader'
    }

if ($tokensEncontrados) {
    Write-Host "  Token(s) detectado(s):" -ForegroundColor Green
    foreach ($t in $tokensEncontrados) {
        Write-Host ("    {0}" -f $t.Name) -ForegroundColor White
        Write-Host ("    Status PnP: {0}" -f $t.Status) -ForegroundColor DarkGray
    }
} else {
    $pnpDisponivel = [bool](Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)
    if ($pnpDisponivel) {
        $tokensPN = Get-PnpDevice -Class 'SmartCardReader' -ErrorAction SilentlyContinue
        if ($tokensPN) {
            Write-Host "  Token(s) detectado(s) via PnP:" -ForegroundColor Green
            foreach ($t in $tokensPN) {
                Write-Host ("    {0} [{1}]" -f $t.FriendlyName, $t.Status) -ForegroundColor White
            }
        } else {
            Write-Host "  Nenhum token detectado no momento." -ForegroundColor Yellow
            Write-Host "  Insira o token USB e aguarde 5 segundos." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Nenhum token detectado no momento." -ForegroundColor Yellow
        Write-Host "  Insira o token USB e aguarde 5 segundos." -ForegroundColor Yellow
    }
}

# ============================================================
# Instrucoes finais
# ============================================================
Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Proximos passos:" -ForegroundColor White
Write-Host "  1. Remova e reinsira o token USB." -ForegroundColor White
Write-Host "  2. Aguarde o Windows reconhecer o dispositivo (~5s)." -ForegroundColor White
Write-Host "  3. Tente acessar o token no software de assinatura." -ForegroundColor White
Write-Host ""
Write-Host "Se ainda nao funcionar:" -ForegroundColor Yellow
Write-Host "  - Reinicie o computador (garante carregamento do driver)." -ForegroundColor Yellow
Write-Host "  - Verifique se o middleware do token esta instalado" -ForegroundColor Yellow
Write-Host "    (SafeNet Authentication Client, Pronova, etc.)." -ForegroundColor Yellow
Write-Host ""

$resp = Read-Host "Deseja reiniciar o computador agora? (S/N)"
if ($resp -match '^[Ss]') {
    Write-Host "Reiniciando em 10 segundos... (Ctrl+C para cancelar)" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
