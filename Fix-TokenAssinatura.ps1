#Requires -Version 7.5
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
    Requer: PowerShell 7.5 + Administrador
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
    [PSCustomObject]@{
        Nome      = 'SCardSvr'
        Descricao = 'Smart Card'
        Detalhe   = 'Comunicacao com token USB e cartoes inteligentes'
    },
    [PSCustomObject]@{
        Nome      = 'ScDeviceEnum'
        Descricao = 'Smart Card Device Enumeration Service'
        Detalhe   = 'Enumeracao de dispositivos de smart card'
    },
    [PSCustomObject]@{
        Nome      = 'SCPolicySvc'
        Descricao = 'Smart Card Removal Policy'
        Detalhe   = 'Politica de remocao segura do token'
    }
)

# ============================================================
# 1. Restaurar startup type e iniciar cada servico
# ============================================================
Write-Host "[1/3] Restaurando servicos de Smart Card..." -ForegroundColor Yellow
Write-Host ""

foreach ($s in $servicosToken) {
    Write-Host "  Servico : $($s.Nome) ($($s.Descricao))" -ForegroundColor White
    Write-Host "  Funcao  : $($s.Detalhe)" -ForegroundColor DarkGray

    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Nome)"
    if (Test-Path $regPath) {
        # Start = 3 (Manual) - SCardSvr inicia sob demanda ao inserir o token
        Set-ItemProperty -Path $regPath -Name 'Start'            -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name 'DelayedAutostart' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  Registro: Start=3 (Manual), DelayedAutostart=0  OK" -ForegroundColor Green
    } else {
        Write-Host "  Registro: chave nao encontrada (servico pode nao estar instalado)" -ForegroundColor Yellow
    }

    try {
        Set-Service -Name $s.Nome -StartupType Manual -ErrorAction Stop
        Write-Host "  Set-Service: Manual  OK" -ForegroundColor Green
    } catch {
        Write-Host "  Set-Service: $($_.Exception.Message) (ignorado)" -ForegroundColor DarkGray
    }

    try {
        Start-Service -Name $s.Nome -ErrorAction Stop
        Write-Host "  Start-Service: Rodando  OK" -ForegroundColor Green
    } catch {
        sc.exe start $s.Nome | Out-Null
        Start-Sleep -Seconds 1
        $svc = Get-Service -Name $s.Nome -ErrorAction SilentlyContinue
        $status = $svc?.Status ?? 'nao encontrado'
        $cor    = $svc?.Status -eq 'Running' ? 'Green' : 'Yellow'
        Write-Host "  sc.exe start: $status" -ForegroundColor $cor
    }

    Write-Host ""
}

# ============================================================
# 2. Verificar status atual dos tres servicos
# ============================================================
Write-Host "[2/3] Status atual dos servicos..." -ForegroundColor Yellow
Write-Host ""
Write-Host ("  {0,-20} {1,-12} {2}" -f "Servico", "Status", "StartupType") -ForegroundColor DarkGray

foreach ($s in $servicosToken) {
    $svc = Get-Service -Name $s.Nome -ErrorAction SilentlyContinue

    if ($svc) {
        # PS 7.5: Get-CimInstance substitui Get-WmiObject (removido no PS 7)
        $cim      = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($s.Nome)'" -ErrorAction SilentlyContinue
        $startMode = $cim?.StartMode ?? 'Desconhecido'
        $cor       = $svc.Status -eq 'Running' ? 'Green' : 'Yellow'
        Write-Host ("  {0,-20} {1,-12} {2}" -f $s.Nome, $svc.Status, $startMode) -ForegroundColor $cor
    } else {
        Write-Host ("  {0,-20} {1}" -f $s.Nome, 'NAO ENCONTRADO') -ForegroundColor Red
    }
}

Write-Host ""

# ============================================================
# 3. Detectar token USB conectado
# ============================================================
Write-Host "[3/3] Detectando token USB / Smart Card..." -ForegroundColor Yellow
Write-Host ""

# PS 7.5: Get-CimInstance para enumeracao de dispositivos PnP
$tokensWmi = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name     -match 'smart.?card|token|etoken|safenet|certisign|gemalto|oberthur|aladdin|watchdata|icp.?brasil' -or
        $_.PNPClass -eq 'SmartCardReader'
    }

if ($tokensWmi) {
    Write-Host "  Token(s) detectado(s):" -ForegroundColor Green
    foreach ($t in $tokensWmi) {
        Write-Host "    $($t.Name)" -ForegroundColor White
        Write-Host "    Status PnP: $($t.Status)" -ForegroundColor DarkGray
    }
} else {
    # Fallback: Get-PnpDevice (modulo PnP disponivel no Windows 10+)
    $tokensPN = Get-PnpDevice -Class 'SmartCardReader' -ErrorAction SilentlyContinue
    if ($tokensPN) {
        Write-Host "  Token(s) detectado(s) via PnP:" -ForegroundColor Green
        $tokensPN | ForEach-Object {
            Write-Host "    $($_.FriendlyName) [$($_.Status)]" -ForegroundColor White
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
