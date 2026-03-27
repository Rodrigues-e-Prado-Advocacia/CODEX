#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Desinstala e expurga completamente programas específicos do Windows.
.DESCRIPTION
    Remove os aplicativos listados usando todos os métodos disponíveis:
    registro, MSI/msiexec, WMI, AppX/UWP, uninstallers nativos, arquivos
    residuais em disco, chaves de registro, serviços e tarefas agendadas.

    Programas tratados:
      01. Intel Processor Diagnostic Tool
      02. Microsoft XNA Framework Redistributable 4.0
      03. NVIDIA GeForce NOW
      04. NVIDIA FrameView
      05. NVIDIA FrameView SDK
      06. EPSON Scan OCR Component
      07. Epson Printer Connection Checker
      08. Epson Printer Driver Security
      09. Epson Software Updater
      10. Notion (desktop)
      11. Dell Digital Delivery
      12. Microsoft Gaming App
      13. Microsoft Edge Game Assist
      14. Microsoft Outlook for Windows (UWP)
      15. Language.Basic — todos os idiomas exceto o principal definido abaixo
.NOTES
    Testado em PowerShell 5.1 / Windows 10-11.
    Execute como Administrador.
    Um log completo e salvo em %TEMP%\PurgeApps_<timestamp>.log
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ─────────────────────────────────────────────────────────────────────────────
#  CONFIGURAÇÃO  ←  Altere aqui o idioma principal a manter (alem de en-US)
# ─────────────────────────────────────────────────────────────────────────────
$IdiomasManter = @('pt-BR', 'en-US')   # Todos os demais Language.Basic sao removidos

# ─────────────────────────────────────────────────────────────────────────────
#  INICIALIZACAO
# ─────────────────────────────────────────────────────────────────────────────
$LogFile = "$env:TEMP\PurgeApps_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$null = New-Item -Path $LogFile -ItemType File -Force

function Write-Log {
    param(
        [string]$Msg,
        [ValidateSet('INFO','OK','AVISO','ERRO')]
        [string]$Tipo = 'INFO'
    )
    $linha = "[$(Get-Date -Format 'HH:mm:ss')] [$Tipo] $Msg"
    Add-Content -Path $LogFile -Value $linha -Encoding UTF8
    $cor = switch ($Tipo) {
        'OK'    { 'Green'  }
        'AVISO' { 'Yellow' }
        'ERRO'  { 'Red'    }
        default { 'Cyan'   }
    }
    Write-Host $linha -ForegroundColor $cor
}

function Cabecalho {
    param([string]$Titulo)
    Write-Log ('-' * 60)
    Write-Log "  $Titulo"
    Write-Log ('-' * 60)
}

# ─────────────────────────────────────────────────────────────────────────────
#  FUNCOES DE REMOCAO
# ─────────────────────────────────────────────────────────────────────────────

function Stop-Processos {
    param([string[]]$Nomes)
    foreach ($n in $Nomes) {
        $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Log "Encerrando processo: $n"
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
    }
}

function Remove-ViaRegistro {
    param([string]$NomeParcial)

    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($chave in $chaves) {
        if (-not (Test-Path $chave)) { continue }
        $entradas = Get-ChildItem $chave -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                    Where-Object { $_.DisplayName -like "*$NomeParcial*" }

        foreach ($e in $entradas) {
            Write-Log "Registro: $($e.DisplayName)  [$($e.PSPath)]"

            # --- MSI ---
            $guidMatch = [regex]::Match($e.UninstallString + $e.PSChildName, '\{[0-9A-Fa-f\-]{36}\}')
            if ($guidMatch.Success) {
                $guid = $guidMatch.Value
                Write-Log "  → msiexec /x $guid"
                $proc = Start-Process 'msiexec.exe' `
                    -ArgumentList "/x `"$guid`" /qn /norestart REBOOT=ReallySuppress" `
                    -Wait -PassThru -NoNewWindow
                if ($proc.ExitCode -eq 0) { Write-Log "  OK" -Tipo 'OK' }
                else { Write-Log "  Codigo de saida: $($proc.ExitCode)" -Tipo 'AVISO' }
                continue
            }

            # --- EXE generico (NSIS / Inno / Squirrel) ---
            if ($e.UninstallString) {
                # Separar executavel de argumentos existentes
                $rawCmd = $e.UninstallString.Trim()
                if ($rawCmd -match '^"([^"]+)"(.*)') {
                    $exe  = $matches[1]
                    $args = $matches[2].Trim()
                } elseif ($rawCmd -match '^(\S+)(.*)') {
                    $exe  = $matches[1]
                    $args = $matches[2].Trim()
                } else {
                    continue
                }

                if (-not (Test-Path $exe)) { continue }

                # Tentar flags silenciosas em ordem de preferencia
                foreach ($silencioso in @('/S', '/SILENT', '/VERYSILENT /NORESTART', '-uninstall -silent', '--uninstall')) {
                    Write-Log "  → $exe $args $silencioso"
                    $proc = Start-Process $exe -ArgumentList "$args $silencioso" -Wait -PassThru -NoNewWindow
                    if ($proc.ExitCode -le 1) {
                        Write-Log "  OK (saida $($proc.ExitCode))" -Tipo 'OK'
                        break
                    }
                }
            }
        }
    }
}

function Remove-ViaGUID {
    param([string[]]$GUIDs)
    foreach ($guid in $GUIDs) {
        $encontrado = $false
        foreach ($raiz in @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$guid",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$guid"
        )) {
            if (Test-Path $raiz) { $encontrado = $true; break }
        }
        if ($encontrado) {
            Write-Log "MSI GUID: $guid"
            $proc = Start-Process 'msiexec.exe' `
                -ArgumentList "/x `"$guid`" /qn /norestart REBOOT=ReallySuppress" `
                -Wait -PassThru -NoNewWindow
            Write-Log "  Saida: $($proc.ExitCode)"
        }
    }
}

function Remove-ViaWMI {
    param([string]$NomeParcial)
    $produtos = Get-WmiObject -Class Win32_Product -Filter "Name LIKE '%$NomeParcial%'" -ErrorAction SilentlyContinue
    foreach ($p in $produtos) {
        Write-Log "WMI: $($p.Name)"
        $r = $p.Uninstall()
        if ($r.ReturnValue -eq 0) { Write-Log "  WMI OK" -Tipo 'OK' }
        else { Write-Log "  WMI retornou $($r.ReturnValue)" -Tipo 'AVISO' }
    }
}

function Remove-Exe {
    # Executa um uninstaller especifico se existir
    param([string]$Caminho, [string]$Argumentos = '/S')
    $exp = [Environment]::ExpandEnvironmentVariables($Caminho)
    if (Test-Path $exp) {
        Write-Log "Uninstaller: $exp $Argumentos"
        Start-Process $exp -ArgumentList $Argumentos -Wait -NoNewWindow
    }
}

function Remove-Dirs {
    param([string[]]$Caminhos)
    foreach ($c in $Caminhos) {
        $exp = [Environment]::ExpandEnvironmentVariables($c)
        # Suporte a wildcards no ultimo segmento
        $dir  = Split-Path $exp
        $leaf = Split-Path $exp -Leaf
        if ($leaf -match '\*|\?') {
            if (Test-Path $dir) {
                Get-ChildItem $dir -Filter $leaf -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Dir $_.FullName }
            }
        } else {
            Remove-Dir $exp
        }
    }
}

function Remove-Dir {
    param([string]$Caminho)
    if (-not (Test-Path $Caminho)) { return }
    Write-Log "  Dir: $Caminho"
    Remove-Item $Caminho -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $Caminho) {
        # Fallback: robocopy mirror com pasta vazia para forcar exclusao
        $vazio = "$env:TEMP\_vazio_$(Get-Random)"
        $null = New-Item $vazio -ItemType Directory -Force
        robocopy $vazio $Caminho /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        Remove-Item $Caminho -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $vazio   -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $Caminho)) { Write-Log "  Dir removido (robocopy): $Caminho" -Tipo 'OK' }
        else { Write-Log "  Nao foi possivel remover: $Caminho" -Tipo 'ERRO' }
    } else {
        Write-Log "  Dir removido: $Caminho" -Tipo 'OK'
    }
}

function Remove-RegKeys {
    param([string[]]$Chaves)
    foreach ($c in $Chaves) {
        if (Test-Path $c) {
            Write-Log "  RegKey: $c"
            Remove-Item $c -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $c)) { Write-Log "  Removida" -Tipo 'OK' }
            else { Write-Log "  Nao removida: $c" -Tipo 'AVISO' }
        }
    }
}

function Remove-AppX {
    param([string[]]$NomesParciais)
    foreach ($nome in $NomesParciais) {
        # Pacotes instalados (todos os usuarios)
        Get-AppxPackage -Name "*$nome*" -AllUsers -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Log "AppX: $($_.PackageFullName)"
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers   -ErrorAction SilentlyContinue
            Remove-AppxPackage -Package $_.PackageFullName             -ErrorAction SilentlyContinue
            Write-Log "  AppX removido" -Tipo 'OK'
        }
        # Pacotes provisionados (novos usuarios)
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "*$nome*" -or $_.DisplayName -like "*$nome*" } |
        ForEach-Object {
            Write-Log "AppX Prov: $($_.PackageName)"
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue
        }
    }
}

function Remove-Servicos {
    param([string[]]$Nomes)
    foreach ($n in $Nomes) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log "Servico: $n"
            Stop-Service  -Name $n -Force -ErrorAction SilentlyContinue
            & sc.exe delete $n | Out-Null
            Write-Log "  Servico removido" -Tipo 'OK'
        }
    }
}

function Remove-Tarefas {
    param([string[]]$NomesParciais)
    foreach ($nome in $NomesParciais) {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like "*$nome*" -or $_.TaskPath -like "*$nome*" } |
        ForEach-Object {
            Write-Log "Tarefa agendada: $($_.TaskPath)$($_.TaskName)"
            Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

function Remove-Atalhos {
    param([string[]]$Padroes)
    foreach ($p in $Padroes) {
        $exp = [Environment]::ExpandEnvironmentVariables($p)
        Get-Item $exp -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "  Atalho: $($_.FullName)"
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-PrefetchEntradas {
    param([string]$Regex)
    Get-ChildItem "$env:SystemRoot\Prefetch" -Filter '*.pf' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $Regex } |
    ForEach-Object {
        Write-Log "  Prefetch: $($_.Name)"
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  EXECUCAO
# ═════════════════════════════════════════════════════════════════════════════

Write-Log ('═' * 60)
Write-Log '  EXPURGO COMPLETO DE APLICATIVOS  —  Inicio'
Write-Log "  Log: $LogFile"
Write-Log ('═' * 60)

# ─────────────────────────────────────────────────────────────────────────────
# 01 ► Intel Processor Diagnostic Tool
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '01/15 — Intel Processor Diagnostic Tool'

Stop-Processos   @('Intel-PDT-Win-*', 'IntelPDT*', 'IPDTSetup*')
Remove-Tarefas   @('IntelPDT', 'Intel Processor Diagnostic')
Remove-ViaRegistro 'Intel Processor Diagnostic Tool'
Remove-ViaGUID   @(
    '{E0810F75-9726-4F4C-B218-67FA2ABA80F7}',
    '{E29D5C9E-7A56-48CF-84FB-28B0B48AECFA}'
)
Remove-ViaWMI    'Intel Processor Diagnostic Tool'
Remove-Dirs @(
    "$env:ProgramFiles\Intel\Intel(R) Processor Diagnostic Tool",
    "$env:ProgramFiles\Intel\Intel Processor Diagnostic Tool",
    "${env:ProgramFiles(x86)}\Intel\Intel(R) Processor Diagnostic Tool",
    "${env:ProgramFiles(x86)}\Intel\Intel Processor Diagnostic Tool",
    "$env:ProgramData\Intel\Intel(R) Processor Diagnostic Tool"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\Intel\IntelPDT',
    'HKLM:\SOFTWARE\WOW6432Node\Intel\IntelPDT',
    'HKLM:\SOFTWARE\Intel\Intel(R) Processor Diagnostic Tool',
    'HKLM:\SOFTWARE\WOW6432Node\Intel\Intel(R) Processor Diagnostic Tool'
)
Remove-PrefetchEntradas 'INTEL.*DIAG|INTELCPU'

# ─────────────────────────────────────────────────────────────────────────────
# 02 ► Microsoft XNA Framework Redistributable 4.0
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '02/15 — Microsoft XNA Framework Redistributable 4.0'

Remove-ViaRegistro 'XNA Framework'
Remove-ViaRegistro 'XNA Game Studio'
# GUIDs conhecidos do XNA 4.0 (todas as variantes)
Remove-ViaGUID @(
    '{2BFC7AA0-544C-4E3A-8796-67F3BE655BE9}',
    '{9AC08E99-230B-47E8-9721-4577B7F124EA}',
    '{EFB5C5BD-C009-4DAD-8A28-1A53DF9BDF44}',
    '{C0E48977-2A5F-4BC8-B0EB-5E4E8E6E3F3B}',
    '{A43BF6A5-D5F0-4AAA-BF41-65995063EC44}',
    '{DB0DAE04-4D41-4703-A5EC-A07A1B1B6EEB}',
    '{FF6B5C05-EFBD-4E4A-BF45-EDEAED9DD5E3}',
    '{9A7FEC2B-5E4A-4C7D-B5FA-6F235B8F4A0D}',
    '{60B7A014-2D22-4CC4-913A-F54B3E81A40C}'
)
Remove-ViaWMI 'XNA Framework'
Remove-Dirs @(
    "${env:ProgramFiles(x86)}\Microsoft XNA",
    "${env:ProgramFiles(x86)}\Microsoft Games For Windows - LIVE",
    "$env:SystemRoot\assembly\GAC_32\Microsoft.Xna.Framework*",
    "$env:SystemRoot\assembly\GAC_MSIL\Microsoft.Xna.Framework*"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\Microsoft\XNA',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\XNA'
)
Remove-PrefetchEntradas 'XNA'

# ─────────────────────────────────────────────────────────────────────────────
# 03 ► NVIDIA GeForce NOW
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '03/15 — NVIDIA GeForce NOW'

Stop-Processos   @('GeForceNOW', 'GeForceNow', 'nvstreamsvc', 'nvstreamnetworksvc')
Remove-Servicos  @('nvstreamsvc', 'NvStreamNetworkService', 'NvStreamUserAgent')
Remove-Tarefas   @('GeForceNow', 'NVIDIA GeForce NOW', 'NvTmRep_GeForceNow*')

# Uninstaller nativo
Remove-Exe "$env:ProgramFiles\NVIDIA Corporation\GeForce NOW\uninstall.exe"
Remove-Exe "$env:LOCALAPPDATA\NVIDIA Corporation\GeForce NOW\uninstall.exe"

Remove-ViaRegistro 'GeForce NOW'
Remove-ViaRegistro 'NVIDIA GeForce NOW'
Remove-ViaWMI      'GeForce NOW'

Remove-Dirs @(
    "$env:ProgramFiles\NVIDIA Corporation\GeForce NOW",
    "$env:LOCALAPPDATA\NVIDIA Corporation\GeForce NOW",
    "$env:APPDATA\NVIDIA Corporation\GeForce NOW",
    "$env:ProgramData\NVIDIA Corporation\GeForce NOW",
    "$env:ProgramData\NVIDIA GeForce NOW",
    "$env:LOCALAPPDATA\GeForceNow"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\NVIDIA Corporation\GeForce NOW',
    'HKLM:\SOFTWARE\WOW6432Node\NVIDIA Corporation\GeForce NOW',
    'HKCU:\SOFTWARE\NVIDIA Corporation\GeForce NOW'
)
Remove-PrefetchEntradas 'GEFORCE|GEFORCENOW'

# ─────────────────────────────────────────────────────────────────────────────
# 04 ► NVIDIA FrameView
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '04/15 — NVIDIA FrameView'

Stop-Processos  @('NvFrameViewSvc', 'FrameView*')
Remove-Servicos @('NvFrameViewSvc')
Remove-Tarefas  @('FrameView', 'NvFrameView')

Remove-Exe "$env:ProgramFiles\NVIDIA Corporation\FrameView\uninstall.exe"
Remove-Exe "${env:ProgramFiles(x86)}\NVIDIA Corporation\FrameView\uninstall.exe"

Remove-ViaRegistro 'NVIDIA FrameView'
Remove-ViaRegistro 'FrameView'
Remove-ViaWMI      'NVIDIA FrameView'
Remove-ViaWMI      'FrameView'

Remove-Dirs @(
    "$env:ProgramFiles\NVIDIA Corporation\FrameView",
    "${env:ProgramFiles(x86)}\NVIDIA Corporation\FrameView",
    "$env:LOCALAPPDATA\NVIDIA Corporation\FrameView",
    "$env:ProgramData\NVIDIA Corporation\FrameView"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\NVIDIA Corporation\FrameView',
    'HKLM:\SOFTWARE\WOW6432Node\NVIDIA Corporation\FrameView',
    'HKCU:\SOFTWARE\NVIDIA Corporation\FrameView'
)
Remove-PrefetchEntradas 'FRAMEVIEW|NVFRAMEVIEW'

# ─────────────────────────────────────────────────────────────────────────────
# 05 ► NVIDIA FrameView SDK
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '05/15 — NVIDIA FrameView SDK'

Remove-ViaRegistro 'FrameView SDK'
Remove-ViaRegistro 'NvFVSDK'
Remove-ViaRegistro 'NVIDIA FrameView SDK'
Remove-ViaWMI      'FrameView SDK'
Remove-ViaGUID @(
    '{BBD41B4B-A014-4827-96DE-C27B5A4B4C45}',
    '{A3D2F68E-9B42-4A6C-A9D3-15D8F534B92E}'
)
Remove-Dirs @(
    "$env:ProgramFiles\NVIDIA Corporation\FrameViewSDK",
    "${env:ProgramFiles(x86)}\NVIDIA Corporation\FrameViewSDK",
    "$env:ProgramFiles\NVIDIA Corporation\NvFVSDK",
    "${env:ProgramFiles(x86)}\NVIDIA Corporation\NvFVSDK"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\NVIDIA Corporation\FrameViewSDK',
    'HKLM:\SOFTWARE\WOW6432Node\NVIDIA Corporation\FrameViewSDK',
    'HKLM:\SOFTWARE\NVIDIA Corporation\NvFVSDK',
    'HKLM:\SOFTWARE\WOW6432Node\NVIDIA Corporation\NvFVSDK'
)

# ─────────────────────────────────────────────────────────────────────────────
# 06 ► EPSON Scan OCR Component
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '06/15 — EPSON Scan OCR Component'

Stop-Processos   @('EsOcr*', 'ESCNDV*')
Remove-Tarefas   @('EPSON Scan OCR', 'EsOcr')
Remove-ViaRegistro 'EPSON Scan OCR'
Remove-ViaRegistro 'Epson Scan OCR'
Remove-ViaWMI      'EPSON Scan OCR'
Remove-Dirs @(
    "$env:ProgramFiles\EPSON\ESCNDV",
    "${env:ProgramFiles(x86)}\EPSON\ESCNDV",
    "$env:ProgramData\EPSON\ESCNDV",
    "$env:ProgramFiles\EPSON Software\ESCNDV",
    "${env:ProgramFiles(x86)}\EPSON Software\ESCNDV",
    "$env:ProgramData\EPSON Software\ESCNDV"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\EPSON\ESCNDV',
    'HKLM:\SOFTWARE\WOW6432Node\EPSON\ESCNDV',
    'HKCU:\SOFTWARE\EPSON\ESCNDV'
)
Remove-PrefetchEntradas 'ESCNDV|EPSON.*OCR'

# ─────────────────────────────────────────────────────────────────────────────
# 07 ► Epson Printer Connection Checker
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '07/15 — Epson Printer Connection Checker'

Stop-Processos   @('EPCSCore*', 'EpsonConnectionChecker*')
Remove-Tarefas   @('EpsonPrinterConnectionChecker', 'EPCSCore', 'Epson Connection')
Remove-ViaRegistro 'Epson Printer Connection Checker'
Remove-ViaRegistro 'EPCSCore'
Remove-ViaWMI      'Epson Printer Connection Checker'
Remove-Dirs @(
    "${env:ProgramFiles(x86)}\Epson Software\EPCSCore",
    "$env:ProgramData\Epson Software\EPCSCore",
    "$env:LOCALAPPDATA\Epson Software\EPCSCore",
    "$env:APPDATA\Epson Software\EPCSCore"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\EPSON\EPCSCore',
    'HKLM:\SOFTWARE\WOW6432Node\EPSON\EPCSCore',
    'HKCU:\SOFTWARE\EPSON\EPCSCore'
)
Remove-PrefetchEntradas 'EPCS|EPSONCONNECTION'

# ─────────────────────────────────────────────────────────────────────────────
# 08 ► Epson Printer Driver Security
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '08/15 — Epson Printer Driver Security'

Stop-Processos   @('EPDS*', 'EpsonDriverSec*')
Remove-Tarefas   @('EPDS', 'Epson Printer Driver Security', 'EpsonSecurity')
Remove-ViaRegistro 'Epson Printer Driver Security'
Remove-ViaRegistro 'EPSON Security'
Remove-ViaRegistro 'EPDS'
Remove-ViaWMI      'Epson Printer Driver Security'
Remove-Dirs @(
    "${env:ProgramFiles(x86)}\Epson Software\EPDS",
    "$env:ProgramData\Epson Software\EPDS",
    "$env:LOCALAPPDATA\Epson Software\EPDS"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\EPSON\EPDS',
    'HKLM:\SOFTWARE\WOW6432Node\EPSON\EPDS',
    'HKCU:\SOFTWARE\EPSON\EPDS'
)
Remove-PrefetchEntradas 'EPDS|EPSONDRIVER'

# ─────────────────────────────────────────────────────────────────────────────
# 09 ► Epson Software Updater
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '09/15 — Epson Software Updater'

Stop-Processos   @('EpsonSoftwareUpdater*', 'EsfUpdater*', 'SFX*Epson*')
Remove-Tarefas   @('EpsonSoftwareUpdater', 'Epson Software Updater', 'EsfUpdater')
Remove-ViaRegistro 'Epson Software Updater'
Remove-ViaRegistro 'EpsonSoftwareUpdater'
Remove-ViaWMI      'Epson Software Updater'
Remove-Exe "${env:ProgramFiles(x86)}\Epson Software\SFX\EpsonSoftwareUpdater\uninstall.exe" '/quiet'
Remove-Exe "${env:ProgramFiles(x86)}\Epson Software\Update\uninstall.exe" '/quiet'
Remove-Dirs @(
    "${env:ProgramFiles(x86)}\Epson Software\SFX",
    "${env:ProgramFiles(x86)}\Epson Software\Update",
    "$env:ProgramData\Epson Software\SFX",
    "$env:ProgramData\Epson Software\Update",
    "$env:LOCALAPPDATA\Epson Software\SFX",
    "$env:LOCALAPPDATA\EpsonSoftwareUpdater"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\EPSON\SFX',
    'HKLM:\SOFTWARE\WOW6432Node\EPSON\SFX',
    'HKCU:\SOFTWARE\EPSON\SFX'
)

# Limpeza de residuos gerais EPSON (apos todos os componentes serem removidos)
Write-Log '  → Verificando residuos EPSON gerais...'
foreach ($raizEpson in @(
    'HKLM:\SOFTWARE\EPSON',
    'HKLM:\SOFTWARE\WOW6432Node\EPSON',
    'HKCU:\SOFTWARE\EPSON'
)) {
    if (Test-Path $raizEpson) {
        $subchaves = Get-ChildItem $raizEpson -ErrorAction SilentlyContinue
        if (-not $subchaves) {
            Write-Log "  Removendo chave EPSON vazia: $raizEpson"
            Remove-Item $raizEpson -Force -ErrorAction SilentlyContinue
        }
    }
}
Remove-PrefetchEntradas 'EPSON|EPSONSOFTWARE'

# ─────────────────────────────────────────────────────────────────────────────
# 10 ► Notion (Desktop)
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '10/15 — Notion'

Stop-Processos @('Notion', 'notion')

# Uninstallers (Squirrel/Electron — varia conforme versao instalada)
Remove-Exe "$env:LOCALAPPDATA\Programs\Notion\Uninstall Notion.exe" '/S'
Remove-Exe "$env:LOCALAPPDATA\Programs\Notion\Uninstall.exe"        '/S'
Remove-Exe "$env:APPDATA\Notion\uninstall.exe"                      '/S'
Remove-Exe "$env:LOCALAPPDATA\notion-updater\Update.exe"            '--uninstall -s'

Remove-Tarefas   @('Notion', 'notion')
Remove-ViaRegistro 'Notion'
Remove-ViaWMI      'Notion'
Remove-AppX        @('Notion')

Remove-Dirs @(
    "$env:LOCALAPPDATA\Programs\Notion",
    "$env:APPDATA\Notion",
    "$env:LOCALAPPDATA\Notion",
    "$env:APPDATA\notion-updater",
    "$env:LOCALAPPDATA\notion-updater",
    "$env:LOCALAPPDATA\Packages\notion*"
)
Remove-RegKeys @(
    'HKCU:\SOFTWARE\Notion',
    'HKLM:\SOFTWARE\Notion',
    'HKCU:\SOFTWARE\Classes\notion',
    'HKLM:\SOFTWARE\Classes\notion',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Notion'
)
Remove-Atalhos @(
    "$env:USERPROFILE\Desktop\Notion.lnk",
    "$env:PUBLIC\Desktop\Notion.lnk",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Notion.lnk",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Notion\*.lnk"
)
Remove-PrefetchEntradas 'NOTION'

# ─────────────────────────────────────────────────────────────────────────────
# 11 ► Dell Digital Delivery
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '11/15 — Dell Digital Delivery'

Stop-Processos   @('Dell.ClientFulfillmentService*', 'DeliveryTrust*', 'DellDigitalDelivery*', 'DDVDataCollector*')
Remove-Servicos  @('Dell.ClientFulfillmentService', 'DellClientFulfillmentService', 'DDVDataCollector')
Remove-Tarefas   @('Dell Digital Delivery', 'DellDigitalDelivery', 'Dell.DigitalDelivery')

Remove-ViaRegistro 'Dell Digital Delivery'
Remove-ViaRegistro 'DellDigitalDelivery'
Remove-ViaWMI      'Dell Digital Delivery'

# Locais possiveis do uninstaller
Remove-Exe "$env:ProgramFiles\Dell\Dell Digital Delivery\uninstall.exe"     '/quiet'
Remove-Exe "${env:ProgramFiles(x86)}\Dell\Dell Digital Delivery\uninstall.exe" '/quiet'

Remove-Dirs @(
    "$env:ProgramFiles\Dell\Dell Digital Delivery",
    "${env:ProgramFiles(x86)}\Dell\Dell Digital Delivery",
    "$env:ProgramData\Dell\Dell Digital Delivery",
    "$env:ProgramData\Dell\DigitalDelivery",
    "$env:APPDATA\Dell\DigitalDelivery",
    "$env:LOCALAPPDATA\Dell\DigitalDelivery"
)
Remove-RegKeys @(
    'HKLM:\SOFTWARE\Dell\DigitalDelivery',
    'HKLM:\SOFTWARE\WOW6432Node\Dell\DigitalDelivery',
    'HKCU:\SOFTWARE\Dell\DigitalDelivery',
    'HKLM:\SYSTEM\CurrentControlSet\Services\Dell.ClientFulfillmentService'
)
Remove-PrefetchEntradas 'DELL.*DELIVER|DELLDIGITAL'

# ─────────────────────────────────────────────────────────────────────────────
# 12 ► Microsoft Gaming App (+ Xbox overlay / identidade)
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '12/15 — Microsoft Gaming App'

Stop-Processos @('GameBar*', 'Xbox*', 'XboxGameBar*', 'GamingServices*')
Remove-Servicos @('GamingServices', 'GamingServicesNet')
Remove-Tarefas  @('Microsoft Gaming', 'Gaming App', 'GamingApp', 'XboxGameBar')

Remove-AppX @(
    'Microsoft.GamingApp',
    'Microsoft.Gaming.App',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxGameBar',
    'Microsoft.Xbox.TCUI',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.GamingServices'
)
Remove-ViaRegistro 'Microsoft Gaming App'
Remove-ViaRegistro 'Xbox Game Bar'

Remove-Dirs @(
    "$env:LOCALAPPDATA\Packages\Microsoft.GamingApp_*",
    "$env:LOCALAPPDATA\Packages\Microsoft.XboxGamingOverlay_*",
    "$env:LOCALAPPDATA\Packages\Microsoft.Xbox.TCUI_*",
    "$env:LOCALAPPDATA\Packages\Microsoft.XboxIdentityProvider_*",
    "$env:LOCALAPPDATA\Packages\Microsoft.XboxGameBar_*"
)
Remove-RegKeys @(
    'HKCU:\SOFTWARE\Microsoft\GameBar',
    'HKCU:\System\GameConfigStore'
)
Remove-PrefetchEntradas 'GAMINGAPP|GAMINGSERV|XBOXGAME'

# ─────────────────────────────────────────────────────────────────────────────
# 13 ► Microsoft Edge Game Assist
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '13/15 — Microsoft Edge Game Assist'

# Edge Game Assist nao tem pacote separado; e desabilitado via politica de grupo
Write-Log '  Desabilitando Edge Game Assist via politica de grupo...'

$edgePol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
if (-not (Test-Path $edgePol)) { $null = New-Item $edgePol -Force }
Set-ItemProperty $edgePol 'AllowGameAssist'          -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty $edgePol 'EdgeGameAssistEnabled'    -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty $edgePol 'ShowGamingOverlay'        -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty $edgePol 'GamingOverlayEnabled'     -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Log '  Politica aplicada: Game Assist desabilitado' -Tipo 'OK'

# Tentar remover como AppX (caso em versoes futuras exista pacote separado)
Remove-AppX @('EdgeGameAssist', 'Microsoft.EdgeGameAssist', 'GameAssist')

# Remover extensao da pasta de dados do Edge (caso exista artefato)
Remove-Tarefas  @('EdgeGameAssist', 'GameAssist')
Remove-ViaRegistro 'Edge Game Assist'

Remove-PrefetchEntradas 'EDGEGAME|GAMEASSIST'

# ─────────────────────────────────────────────────────────────────────────────
# 14 ► Microsoft Outlook for Windows (UWP / "New Outlook")
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '14/15 — Microsoft Outlook for Windows (UWP)'

Stop-Processos   @('olk', 'Outlook', 'OutlookForWindows*')
Remove-Tarefas   @('Outlook', 'OutlookForWindows', 'Microsoft.OutlookForWindows')
Remove-AppX      @('Microsoft.OutlookForWindows', 'OutlookForWindows', 'OutlookNew')
Remove-ViaRegistro 'Microsoft Outlook for Windows'

Remove-Dirs @(
    "$env:LOCALAPPDATA\Packages\Microsoft.OutlookForWindows_*",
    "$env:LOCALAPPDATA\Microsoft\Olk"
)
Remove-PrefetchEntradas 'OUTLOOKFORWINDOWS|OLK\.EXE'

# ─────────────────────────────────────────────────────────────────────────────
# 15 ► Language.Basic — remover todos os idiomas nao listados em $IdiomasManter
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '15/15 — Language.Basic (idiomas excedentes)'

Write-Log "  Idiomas a manter: $($IdiomasManter -join ', ')"

# Montar regex de correspondencia para os idiomas que devem ser mantidos
$regexManter = ($IdiomasManter | ForEach-Object { [regex]::Escape($_) }) -join '|'

# Remover Language.* capabilities desnecessarias
$caps = Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Language.*' -and $_.State -eq 'Installed' }

foreach ($cap in $caps) {
    # Extrair codigo de idioma: Language.Basic~~~pt-BR~0.0.1.0 → pt-BR
    $codigo = ($cap.Name -split '~~~' | Select-Object -Last 1) -split '~' | Select-Object -First 1

    if ($codigo -match $regexManter) {
        Write-Log "  Mantendo : $($cap.Name)" -Tipo 'OK'
        continue
    }
    Write-Log "  Removendo: $($cap.Name)"
    Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction SilentlyContinue | Out-Null
}

# Remover language packs UI (MUI) que nao sao necessarios
try {
    $langsInstaladas = Get-WinUserLanguageList -ErrorAction Stop
    $novaLista = $langsInstaladas | Where-Object { $_.LanguageTag -match $regexManter }
    if ($novaLista.Count -gt 0 -and $novaLista.Count -lt $langsInstaladas.Count) {
        Write-Log "  Atualizando lista de idiomas do usuario..."
        Set-WinUserLanguageList $novaLista -Force -ErrorAction SilentlyContinue
        Write-Log "  Lista atualizada" -Tipo 'OK'
    }
} catch {
    Write-Log "  Nao foi possivel modificar lista de idiomas do usuario: $_" -Tipo 'AVISO'
}

# ═════════════════════════════════════════════════════════════════════════════
#  LIMPEZA FINAL
# ═════════════════════════════════════════════════════════════════════════════
Write-Log ('═' * 60)
Write-Log '  LIMPEZA FINAL'
Write-Log ('═' * 60)

# Limpar Temp do sistema
Write-Log '  Limpando %TEMP% e %SystemRoot%\Temp...'
@($env:TEMP, $env:TMP, "$env:SystemRoot\Temp") | ForEach-Object {
    if (Test-Path $_) {
        Get-ChildItem $_ -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# Limpar cache do Windows Update para evitar reinstalacao automatica
Write-Log '  Limpando cache do Windows Update...'
Stop-Service wuauserv  -Force -ErrorAction SilentlyContinue
Stop-Service bits      -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv -ErrorAction SilentlyContinue
Start-Service bits     -ErrorAction SilentlyContinue

# Limpar Lixeira de todos os usuarios
Write-Log '  Esvaziando Lixeira...'
$shell = New-Object -ComObject Shell.Application
$shell.NameSpace(10).Items() | ForEach-Object {
    Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue
}

# Forcar refresh do cache de atalhos/icones do shell
Write-Log '  Atualizando cache de icones do Shell...'
& ie4uinit.exe -show 2>$null
& rundll32.exe user32.dll,UpdatePerUserSystemParameters ,1 ,True 2>$null

# Limpar entradas de aplicativo recentes do registro
Write-Log '  Removendo entradas "MRU" residuais...'
$mruRegex = 'Notion|GeForce|FrameView|Epson|EPSON|IntelDiag|XNA|Dell.*Deliv|OutlookNew'
foreach ($mruChave in @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\RunMRU'
)) {
    if (-not (Test-Path $mruChave)) { continue }
    $props = Get-ItemProperty $mruChave -ErrorAction SilentlyContinue
    if (-not $props) { continue }
    $props.PSObject.Properties |
        Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notlike 'PS*' } |
        ForEach-Object {
            $val = try { [System.Text.Encoding]::Unicode.GetString($_.Value) } catch { "$($_.Value)" }
            if ($val -match $mruRegex) {
                Write-Log "    MRU removido: $mruChave → $($_.Name)"
                Remove-ItemProperty -Path $mruChave -Name $_.Name -Force -ErrorAction SilentlyContinue
            }
        }
}

Write-Log ('═' * 60)
Write-Log '  Expurgo concluido com sucesso!' -Tipo 'OK'
Write-Log "  Log completo salvo em: $LogFile"
Write-Log '  RECOMENDADO: Reinicie o computador para finalizar a remocao.'
Write-Log ('═' * 60)

Write-Host "`nPressione ENTER para sair..." -ForegroundColor White
$null = Read-Host
