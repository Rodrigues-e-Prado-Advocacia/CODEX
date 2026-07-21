<#
  trocar_ip.ps1 — Troca o IP publico dinamico SEM reiniciar o modem, via UPnP/TR-064.
  Derruba a sessao WAN (ForceTermination); o roteador reconecta sozinho,
  normalmente com um IP novo.

  Confirmado no cenario: ZTE F6600P (fibra, IP publico direto na WAN, SEM CGNAT).
  Funciona em qualquer roteador que exponha WANPPPConnection/WANIPConnection por UPnP.
  Nao instala nada (usa o PowerShell nativo do Windows).

  Uso (no PowerShell):
      .\trocar_ip.ps1            # mostra o IP e pede confirmacao
      .\trocar_ip.ps1 -Sim       # troca direto, sem perguntar
      .\trocar_ip.ps1 -Mostrar   # SO mostra o IP atual (nao altera nada)

  Se o Windows bloquear o arquivo, rode antes nesta mesma janela:
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

  ATENCAO: derruba a internet por alguns segundos enquanto reconecta.
  Quem decide o IP final e a operadora; o script apenas forca a renegociacao.
#>
param([switch]$Sim, [switch]$Mostrar)

function Find-Igd {
  $udp = New-Object System.Net.Sockets.UdpClient
  $udp.Client.ReceiveTimeout = 3000
  $m = "M-SEARCH * HTTP/1.1`r`nHOST:239.255.255.250:1900`r`nMAN:`"ssdp:discover`"`r`nMX:2`r`nST:urn:schemas-upnp-org:device:InternetGatewayDevice:1`r`n`r`n"
  $b = [Text.Encoding]::ASCII.GetBytes($m)
  [void]$udp.Send($b, $b.Length, (New-Object Net.IPEndPoint([Net.IPAddress]::Parse("239.255.255.250"), 1900)))
  $loc = $null
  try { for ($i=0; $i -lt 8; $i++) { $rep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0); $resp = [Text.Encoding]::ASCII.GetString($udp.Receive([ref]$rep)); if ($resp -match "(?im)^LOCATION:\s*(\S+)") { $loc = $matches[1]; break } } } catch {}
  $udp.Close()
  return $loc
}

function Get-WanService {
  $loc = Find-Igd
  if (-not $loc) { return $null }
  $xml  = [xml](Invoke-WebRequest $loc -UseBasicParsing -TimeoutSec 6).Content
  $base = if ($xml.root.URLBase) { $xml.root.URLBase.TrimEnd('/') } else { ([uri]$loc).GetLeftPart([UriPartial]::Authority) }
  $model = ($xml.SelectNodes("//*[local-name()='device']") | Where-Object { $_.modelName } | Select-Object -First 1).modelName
  $svc = $null
  foreach ($key in @("WANPPPConnection", "WANIPConnection")) {
    $svc = $xml.SelectNodes("//*[local-name()='service']") | Where-Object { $_.serviceType -match $key } | Select-Object -First 1
    if ($svc) { break }
  }
  if (-not $svc) { return $null }
  $c = $svc.controlURL
  if ($c -notmatch '^http') { if ($c[0] -ne '/') { $c = '/' + $c }; $c = $base + $c }
  return [pscustomobject]@{ ServiceType = $svc.serviceType; ControlUrl = $c; Model = $model }
}

function Invoke-Soap($st, $url, $action) {
  $soap = '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:' + $action + ' xmlns:u="' + $st + '"/></s:Body></s:Envelope>'
  return Invoke-WebRequest $url -Method POST -Headers @{ "SOAPAction" = '"' + $st + '#' + $action + '"' } -ContentType "text/xml; charset=utf-8" -Body $soap -UseBasicParsing -TimeoutSec 6
}

function Get-ExtIp($st, $url) {
  try {
    $r = Invoke-Soap $st $url "GetExternalIPAddress"
    if ($r.Content -match "<NewExternalIPAddress>(.*?)</NewExternalIPAddress>") {
      $ip = $matches[1]
      if ($ip -match '^\d+\.\d+\.\d+\.\d+$' -and $ip -ne '0.0.0.0') { return $ip }
    }
  } catch {}
  return $null
}

# ------------------------------- principal -------------------------------- #
Write-Host "`n=== Troca de IP dinamico via UPnP/TR-064 ==="
$w = Get-WanService
if (-not $w) {
  Write-Host "  Nenhum roteador com servico WAN via UPnP encontrado."
  Write-Host "  Ligue o UPnP no roteador, ou use o painel http://192.168.1.1 (WAN -> Desconectar/Conectar)."
  return
}
Write-Host ("  Roteador: {0}" -f $w.Model)
Write-Host ("  Servico : {0}" -f ($w.ServiceType -replace '.*:service:', ''))

$old = Get-ExtIp $w.ServiceType $w.ControlUrl
Write-Host ("  IP atual: {0}" -f $(if ($old) { $old } else { '(desconectado?)' }))

if ($Mostrar) { return }

if (-not $Sim) {
  Write-Host "`n  Isto vai DERRUBAR sua internet por alguns segundos para pegar um IP novo."
  $r = Read-Host "  Continuar? [s/N]"
  if ($r -notmatch '^(s|sim|y|yes)$') { Write-Host "  Cancelado."; return }
}

Write-Host "  Derrubando a sessao WAN (ForceTermination)..."
$done = $false
foreach ($act in @("ForceTermination", "RequestTermination")) {
  try { [void](Invoke-Soap $w.ServiceType $w.ControlUrl $act); $done = $true; break } catch {}
}
if (-not $done) {
  Write-Host "  !! O roteador recusou o comando de desconexao (o UPnP dele deve permitir so leitura)."
  Write-Host "     Alternativa: painel http://192.168.1.1 -> Internet/WAN -> Desconectar e Conectar."
  return
}

Start-Sleep -Seconds 6
try { [void](Invoke-Soap $w.ServiceType $w.ControlUrl "RequestConnection") } catch {}   # garante o retorno se o auto-reconectar estiver off

Write-Host -NoNewline "  Aguardando reconectar..."
$new = $null; $t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 90) {
  Start-Sleep -Seconds 3; Write-Host -NoNewline "."
  $cur = Get-ExtIp $w.ServiceType $w.ControlUrl
  if ($cur -and $cur -ne $old) { $new = $cur; break }
}
Write-Host ""

if ($new) {
  Write-Host ("  >>> IP TROCADO:  {0}  ->  {1}" -f $old, $new) -ForegroundColor Green
} elseif ((Get-ExtIp $w.ServiceType $w.ControlUrl) -eq $old) {
  Write-Host ("  A conexao voltou, mas com O MESMO IP ({0})." -f $old)
  Write-Host "  A operadora reatribuiu o mesmo IP. Tente de novo mais tarde."
} else {
  Write-Host "  Nao consegui confirmar o novo IP a tempo. Se a internet nao voltar em ~1 min, reinicie o modem."
}
