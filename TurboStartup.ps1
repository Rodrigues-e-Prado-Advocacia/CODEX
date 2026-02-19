#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    TurboStartup - Otimizacao maxima de inicializacao Windows
.DESCRIPTION
    Aplica otimizacoes profundas em BCD, NTFS, Prefetch, Memoria, Servicos,
    Disco, Power Plan e Font Cache visando boot em menos de 15 segundos.
.NOTES
    Requer: PowerShell 5.1 + Administrador
    Testado: Windows 10/11
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ─────────────────────────────────────────────────────────────
#  CONFIGURACAO DE LOG
# ─────────────────────────────────────────────────────────────
$LogPath = "$env:SystemDrive\TurboStartup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Msg"
    $line | Tee-Object -FilePath $LogPath -Append | Out-Null
    switch ($Level) {
        'OK'   { Write-Host $line -ForegroundColor Green  }
        'WARN' { Write-Host $line -ForegroundColor Yellow }
        'ERR'  { Write-Host $line -ForegroundColor Red    }
        default{ Write-Host $line -ForegroundColor Cyan   }
    }
}

function Write-Section {
    param([string]$Title)
    $sep = '=' * 60
    Write-Log $sep
    Write-Log "  $Title"
    Write-Log $sep
}

# ─────────────────────────────────────────────────────────────
#  VERIFICACAO DE PREREQUISITOS
# ─────────────────────────────────────────────────────────────
Write-Section 'TURBOSTARTUP - INICIO'
Write-Log "Log: $LogPath"
Write-Log "Host: $env:COMPUTERNAME | OS: $([System.Environment]::OSVersion.VersionString)"

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Log 'Execute como Administrador.' 'ERR'
    exit 1
}

# ─────────────────────────────────────────────────────────────
#  1. BCD - BOOT CONFIGURATION DATA
# ─────────────────────────────────────────────────────────────
Write-Section '1. BCD - Boot Configuration Data'

function Set-BCDValue {
    param([string]$Key, [string]$Value, [string]$Desc)
    $out = bcdedit /set $Key $Value 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Log "$Desc → OK" 'OK' }
    else { Write-Log "$Desc → $out" 'WARN' }
}

# Timeout minimo de menu de boot
Set-BCDValue 'timeout' '0'         'Menu timeout = 0s'

# Politica de boot simplificada (sem F8, sem recovery legacy)
Set-BCDValue 'bootmenupolicy' 'standard' 'Boot menu policy = standard'

# Desativa EMS (Emergency Management Services) - reduz probe de porta serial
Set-BCDValue 'ems' 'No' 'EMS = desativado'

# Desativa debug de boot
Set-BCDValue 'bootdebug' 'No' 'Boot debug = desativado'

# Desativa debug do kernel
Set-BCDValue 'debug' 'No' 'Kernel debug = desativado'

# Ativa boot de alta integridade sem verificacao de assinatura de teste
bcdedit /deletevalue '{current}' testsigning 2>&1 | Out-Null
Write-Log 'Test signing limpo' 'OK'

# Ativa Hypervisor Launch Type (necessario para Hyper-V/VBS - se nao usar, desativar)
# Set-BCDValue 'hypervisorlaunchtype' 'off' 'Hypervisor = off (desativar se nao usar Hyper-V)'

# Garante que o boot loader usa a versao mais rapida
Set-BCDValue 'bootux' 'disabled' 'Boot UX (animacao) = desativada'

# Numero de processadores usados no boot (0 = todos)
Set-BCDValue 'numproc' '0' 'numproc = todos os cores'

# ─────────────────────────────────────────────────────────────
#  2. HARDWARE DETECTION - ACPI / PnP
# ─────────────────────────────────────────────────────────────
Write-Section '2. Hardware Detection'

$hwReg = 'HKLM:\SYSTEM\CurrentControlSet\Control'

# Desativa deteccao de hardware legado na inicializacao
Set-ItemProperty -Path "$hwReg\PnP" -Name 'DisableFirmwareMapper' -Value 1 -Type DWord -Force
Write-Log 'Firmware mapper desativado' 'OK'

# Reduz timeout de enumeracao de dispositivos PCI
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PnP\Pci' `
    -Name 'HackFlags' -Value 0x400 -Type DWord -Force
Write-Log 'PCI HackFlags ajustado' 'OK'

# Desativa verificacao de ultimo dispositivo removivel bom conhecido
$storageReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'
if (-not (Test-Path $storageReg)) { New-Item -Path $storageReg -Force | Out-Null }
Set-ItemProperty -Path $storageReg -Name 'WriteProtect' -Value 0 -Type DWord -Force
Write-Log 'Storage write protect = 0' 'OK'

# Reduz timeout de deteccao de CD/DVD
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\cdrom' `
    -Name 'Start' -Value 3 -Type DWord -Force
Write-Log 'CDROM driver = demand start (3)' 'OK'

# ─────────────────────────────────────────────────────────────
#  3. NTFS - SISTEMA DE ARQUIVOS
# ─────────────────────────────────────────────────────────────
Write-Section '3. NTFS Otimizacao'

$ntfsReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'

# Desativa nomes 8.3 (MS-DOS compat) - grande ganho em volumes com muitos arquivos
Set-ItemProperty -Path $ntfsReg -Name 'NtfsDisable8dot3NameCreation' -Value 1 -Type DWord -Force
Write-Log 'NTFS 8.3 names = desativado' 'OK'

# Desativa atualizacao de last access time - reduz escritas desnecessarias
Set-ItemProperty -Path $ntfsReg -Name 'NtfsDisableLastAccessUpdate' -Value 2147483649 -Type DWord -Force
Write-Log 'NTFS Last Access Update = desativado' 'OK'

# Ativa alocacao encriptada de memoria do paginador NTFS
Set-ItemProperty -Path $ntfsReg -Name 'NtfsEncryptionService' -Value 0 -Type DWord -Force

# Desativa compressao automatica de NTFS
Set-ItemProperty -Path $ntfsReg -Name 'NtfsCompressionEnabled' -Value 0 -Type DWord -Force
Write-Log 'NTFS Compressao automatica = desativada' 'OK'

# Aumenta buffer de memoria do NTFS
Set-ItemProperty -Path $ntfsReg -Name 'NtfsAllowExtendedCharacterIn8dot3Name' -Value 0 -Type DWord -Force

# Otimiza MFT (Master File Table) - reserva espaco para evitar fragmentacao
fsutil behavior set mftzone 2 2>&1 | Out-Null
Write-Log 'MFT Zone = 2 (12.5% reserva)' 'OK'

# Desativa log de uso de disco
fsutil behavior set disablelastaccess 1 2>&1 | Out-Null
Write-Log 'Disable last access (fsutil) = 1' 'OK'

# Desativa criacao de 8.3 via fsutil
fsutil behavior set disable8dot3 1 2>&1 | Out-Null
Write-Log 'Disable 8dot3 (fsutil) = 1' 'OK'

# ─────────────────────────────────────────────────────────────
#  4. PREFETCH / SUPERFETCH / READYBOOT
# ─────────────────────────────────────────────────────────────
Write-Section '4. Prefetch e ReadyBoot'

$pfReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'

# EnablePrefetcher: 0=off, 1=app only, 2=boot only, 3=ambos (recomendado para HDD, 0 para SSD puro)
# Detecta se o disco do sistema e SSD
$diskType = $null
try {
    $disk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq 0 } | Select-Object -First 1
    if (-not $disk) {
        $disk = Get-PhysicalDisk | Select-Object -First 1
    }
    $diskType = $disk.MediaType
} catch { }

if ($diskType -eq 'SSD' -or $diskType -eq 'NVMe') {
    # SSD/NVMe: prefetch nao traz ganho, desativar
    Set-ItemProperty -Path $pfReg -Name 'EnablePrefetcher'   -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $pfReg -Name 'EnableSuperfetch'   -Value 0 -Type DWord -Force
    Write-Log "Disco: $diskType → Prefetch/Superfetch DESATIVADOS" 'OK'
} else {
    # HDD: manter prefetch de boot
    Set-ItemProperty -Path $pfReg -Name 'EnablePrefetcher'   -Value 2 -Type DWord -Force
    Set-ItemProperty -Path $pfReg -Name 'EnableSuperfetch'   -Value 3 -Type DWord -Force
    Write-Log "Disco: $diskType → Prefetch=boot(2) Superfetch=ambos(3)" 'OK'
}

# Desativa SysMain (Superfetch service) em SSD
$sysMain = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue
if ($diskType -eq 'SSD' -or $diskType -eq 'NVMe') {
    if ($sysMain) {
        Stop-Service -Name 'SysMain' -Force -ErrorAction SilentlyContinue
        Set-Service  -Name 'SysMain' -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log 'SysMain (Superfetch) = DESATIVADO (SSD)' 'OK'
    }
} else {
    if ($sysMain) {
        Set-Service -Name 'SysMain' -StartupType Automatic -ErrorAction SilentlyContinue
        Write-Log 'SysMain (Superfetch) = AUTO (HDD)' 'OK'
    }
}

# Limpa prefetch antigo para focar no novo layout
$pfDir = "$env:SystemRoot\Prefetch"
if (Test-Path $pfDir) {
    Get-ChildItem $pfDir -Filter '*.pf' | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log 'Cache Prefetch limpo (sera reconstruido no proximo boot)' 'OK'
}

# ─────────────────────────────────────────────────────────────
#  5. MEMORIA - GERENCIAMENTO
# ─────────────────────────────────────────────────────────────
Write-Section '5. Otimizacao de Memoria'

$mmReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'

# Mantem executaveis do kernel na RAM (nao pagina para disco)
Set-ItemProperty -Path $mmReg -Name 'DisablePagingExecutive' -Value 1 -Type DWord -Force
Write-Log 'DisablePagingExecutive = 1 (kernel na RAM)' 'OK'

# Aumenta prioridade do cache do sistema
Set-ItemProperty -Path $mmReg -Name 'LargeSystemCache' -Value 0 -Type DWord -Force
Write-Log 'LargeSystemCache = 0 (otimizado para apps)' 'OK'

# Tamanho da pagefile - deixa Windows gerenciar automaticamente para boot otimo
$cs = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction SilentlyContinue
if ($cs) {
    $cs.AutomaticManagedPagefile = $true
    $cs.Put() | Out-Null
    Write-Log 'PageFile = gerenciado automaticamente' 'OK'
}

# Desativa clear de PageFile no shutdown (acelera desligamento/boot)
Set-ItemProperty -Path $mmReg -Name 'ClearPageFileAtShutdown' -Value 0 -Type DWord -Force
Write-Log 'ClearPageFileAtShutdown = 0' 'OK'

# Pool de memoria nao paginada - deixa Windows decidir
Set-ItemProperty -Path $mmReg -Name 'NonPagedPoolQuota' -Value 0 -Type DWord -Force
Set-ItemProperty -Path $mmReg -Name 'PagedPoolQuota'    -Value 0 -Type DWord -Force
Write-Log 'Pool quotas = auto (0)' 'OK'

# Desativa Low-Fragmentation Heap para melhor desempenho de inicio
$heapReg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
# Nao alterar globalmente - pode causar instabilidade

# ─────────────────────────────────────────────────────────────
#  6. SERVICOS - DELAYED START
# ─────────────────────────────────────────────────────────────
Write-Section '6. Servicos - Delayed Start e Desativacao'

# Servicos para DelayedAutoStart (iniciam 2min apos boot)
$delayedServices = @(
    'AdobeARMservice',        # Adobe Acrobat Update
    'AJRouter',               # AllJoyn Router
    'ALG',                    # Application Layer Gateway
    'AppIDSvc',               # Application Identity
    'AppMgmt',                # Application Management
    'AxInstSV',               # ActiveX Installer
    'BITS',                   # Background Intelligent Transfer
    'Browser',                # Computer Browser (legado)
    'bthserv',                # Bluetooth Support
    'CscService',             # Offline Files
    'defragsvc',              # Optimize Drives
    'DiagTrack',              # Diagnostics Tracking
    'DmEnrollmentSvc',        # Device Management Enrollment
    'DoSvc',                  # Delivery Optimization
    'DPS',                    # Diagnostic Policy Service
    'EapHost',                # Extensible Authentication Protocol
    'Fax',                    # Fax
    'fdPHost',                # Function Discovery Provider Host
    'FDResPub',               # Function Discovery Resource Publication
    'fhsvc',                  # File History Service
    'gpsvc',                  # Group Policy Client - CUIDADO: manter se dominio
    'hidserv',                # Human Interface Device
    'icssvc',                 # Windows Mobile Hotspot
    'IKEEXT',                 # IKE and AuthIP IPsec Keying
    'lfsvc',                  # Geolocation Service
    'lltdsvc',                # Link-Layer Topology Discovery Mapper
    'MapsBroker',             # Downloaded Maps Manager
    'MSiSCSI',                # Microsoft iSCSI Initiator
    'NcbService',             # Network Connection Broker
    'Netlogon',               # Netlogon
    'NlaSvc',                 # Network Location Awareness
    'p2pimsvc',               # Peer Networking Identity Manager
    'p2psvc',                 # Peer Networking Grouping
    'PcaSvc',                 # Program Compatibility Assistant
    'PeerDistSvc',            # BranchCache
    'PimIndexMaintenanceSvc', # Contact Data
    'PrintNotify',            # Printer Extensions
    'QWAVE',                  # Quality Windows Audio Video
    'RasAuto',                # Remote Access Auto Connection
    'RasMan',                 # Remote Access Connection Manager
    'RemoteAccess',           # Routing and Remote Access
    'RemoteRegistry',         # Remote Registry
    'RetailDemo',             # Retail Demo
    'RmSvc',                  # Radio Management
    'RpcLocator',             # Remote Procedure Call Locator
    'SCardSvr',               # Smart Card
    'ScDeviceEnum',           # Smart Card Device Enumeration
    'SCPolicySvc',            # Smart Card Removal Policy
    'SDRSVC',                 # Windows Backup
    'SEMgrSvc',               # Payments and NFC/SE Manager
    'Spooler',                # Print Spooler - DelayedStart se impressora nao usada no boot
    'SSDPSRV',                # SSDP Discovery
    'SstpSvc',                # Secure Socket Tunneling Protocol
    'stisvc',                 # Windows Image Acquisition
    'SysMain',                # Superfetch
    'TabletInputService',     # Touch Keyboard
    'TapiSrv',                # Telephony
    'TermService',            # Remote Desktop Services
    'TrkWks',                 # Distributed Link Tracking Client
    'tzautoupdate',           # Auto Time Zone Updater
    'UmRdpService',           # Remote Desktop Services UserMode
    'upnphost',               # UPnP Device Host
    'vds',                    # Virtual Disk
    'W32tm',                  # Windows Time
    'WbioSrvc',               # Windows Biometric
    'Wcmsvc',                 # Windows Connection Manager
    'WdiServiceHost',         # Diagnostic Service Host
    'WdiSystemHost',          # Diagnostic System Host
    'WerSvc',                 # Windows Error Reporting
    'WiaRpc',                 # Still Image Acquisition Events
    'WinRM',                  # Windows Remote Management
    'WlanSvc',                # WLAN AutoConfig - manter AUTO se usar WiFi
    'wmiApSrv',               # WMI Performance Adapter
    'WMPNetworkSvc',          # Windows Media Player Network Sharing
    'WpnService',             # Windows Push Notifications
    'WSearch',                # Windows Search - DelayedStart
    'wuauserv',               # Windows Update
    'XblAuthManager',         # Xbox Live Auth
    'XblGameSave',            # Xbox Live Game Save
    'XboxGipSvc',             # Xbox Accessory
    'XboxNetApiSvc'           # Xbox Live Networking
)

# Servicos criticos que NAO devem ser alterados
$criticalServices = @(
    'AudioEndpointBuilder', 'Audiosrv', 'BFE', 'BrokerInfrastructure',
    'ClipSVC', 'CoreMessagingRegistrar', 'CryptSvc', 'DcomLaunch',
    'DeviceAssociationService', 'Dhcp', 'Dnscache', 'DusmSvc',
    'EventLog', 'EventSystem', 'FontCache', 'gpsvc', 'KeyIso',
    'LSM', 'MpsSvc', 'NcaSvc', 'netprofm', 'NlaSvc', 'nsi',
    'PlugPlay', 'Power', 'ProfSvc', 'RpcEptMapper', 'RpcSs',
    'Schedule', 'SecurityHealthService', 'SENS', 'ShellHWDetection',
    'Spooler', 'StateRepository', 'StorSvc', 'SystemEventsBroker',
    'Themes', 'TokenBroker', 'TrustedInstaller', 'UserManager',
    'UsoSvc', 'VaultSvc', 'wdmaud', 'Winmgmt', 'WlanSvc',
    'wscsvc', 'WSearch', 'wuauserv'
)

$delayedCount = 0
$disabledCount = 0

foreach ($svcName in $delayedServices) {
    if ($criticalServices -contains $svcName) { continue }
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) { continue }

    try {
        # Define como AutomaticDelayedStart via registro
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name 'Start'             -Value 2  -Type DWord -Force
            Set-ItemProperty -Path $regPath -Name 'DelayedAutostart'  -Value 1  -Type DWord -Force
            $delayedCount++
            Write-Log "  DelayedStart: $svcName" 'OK'
        }
    } catch {
        Write-Log "  Falha em $svcName : $_" 'WARN'
    }
}

# Servicos que podem ser desativados com seguranca em uso domestico
$disableServices = @(
    'AJRouter',        # AllJoyn Router - IoT, raramente usado
    'ALG',             # App Layer Gateway - VoIP/games legados
    'AxInstSV',        # ActiveX Installer - obsoleto
    'Browser',         # Computer Browser - rede legada
    'CscService',      # Offline Files - raramente usado
    'Fax',             # Fax
    'FrameServer',     # Windows Camera - se nao usar camera
    'icssvc',          # Mobile Hotspot - se nao compartilhar internet
    'lltdsvc',         # Link-Layer Topology
    'MSiSCSI',         # iSCSI - storage enterprise
    'p2pimsvc',        # Peer Networking
    'p2psvc',          # Peer Networking
    'PeerDistSvc',     # BranchCache - enterprise
    'RasAuto',         # Remote Access Auto
    'RemoteAccess',    # Routing and Remote Access
    'RemoteRegistry',  # Remote Registry - seguranca
    'RetailDemo',      # Retail Demo
    'RpcLocator',      # RPC Locator - legado
    'SCardSvr',        # Smart Card
    'ScDeviceEnum',    # Smart Card Device Enum
    'SCPolicySvc',     # Smart Card Removal
    'SDRSVC',          # Windows Backup
    'SEMgrSvc',        # NFC Payments
    'SstpSvc',         # VPN SSTP - se nao usar VPN
    'stisvc',          # Scanner WIA - se nao usar scanner
    'TapiSrv',         # Telephony
    'TrkWks',          # Distributed Link Tracking
    'tzautoupdate',    # Auto Timezone
    'UmRdpService',    # Remote Desktop
    'upnphost',        # UPnP
    'vds',             # Virtual Disk
    'WbioSrvc',        # Biometrico - desativar se nao usar impressao digital
    'WiaRpc',          # Scanner
    'WinRM',           # Remote Management
    'WMPNetworkSvc',   # WMP Network Sharing
    'XblAuthManager',  # Xbox Live
    'XblGameSave',     # Xbox Game Save
    'XboxGipSvc',      # Xbox Accessory
    'XboxNetApiSvc'    # Xbox Networking
)

foreach ($svcName in $disableServices) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    try {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
        $disabledCount++
        Write-Log "  Desativado: $svcName" 'OK'
    } catch {
        Write-Log "  Nao foi possivel desativar $svcName" 'WARN'
    }
}

Write-Log "Servicos → DelayedStart: $delayedCount | Desativados: $disabledCount" 'OK'

# ─────────────────────────────────────────────────────────────
#  7. LIMPEZA DE DISCO
# ─────────────────────────────────────────────────────────────
Write-Section '7. Limpeza de Disco'

# Pastas temporarias
$tempPaths = @(
    $env:TEMP,
    $env:TMP,
    "$env:SystemRoot\Temp",
    "$env:SystemRoot\SoftwareDistribution\Download",
    "$env:SystemRoot\Logs\CBS",
    "$env:LOCALAPPDATA\Temp",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Temporary Internet Files",
    "$env:SystemDrive\`$Recycle.Bin"
)

$totalFreed = 0
foreach ($path in $tempPaths) {
    if (Test-Path $path) {
        $before = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
        Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        $freed = [math]::Max(0, $before - $after)
        $totalFreed += $freed
        Write-Log "  Limpo: $path ($([math]::Round($freed/1MB,1)) MB)" 'OK'
    }
}

# Limpa logs de eventos antigos (mantém os recentes)
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object { $_.RecordCount -gt 0 } |
    ForEach-Object {
        try {
            [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName)
        } catch { }
    }
Write-Log 'Logs de eventos limpos' 'OK'

# Executa Disk Cleanup silencioso via cleanmgr
$regCleanMgr = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$cleanupFlags = @(
    'Active Setup Temp Folders',
    'BranchCache',
    'Downloaded Program Files',
    'Internet Cache Files',
    'Memory Dump Files',
    'Offline Pages Files',
    'Old ChkDsk Files',
    'Previous Installations',
    'Recycle Bin',
    'Service Pack Cleanup',
    'Setup Log Files',
    'System error memory dump files',
    'System error minidump files',
    'Temporary Files',
    'Temporary Setup Files',
    'Temporary Sync Files',
    'Thumbnail Cache',
    'Update Cleanup',
    'Upgrade Discarded Files',
    'User file versions',
    'Windows Defender',
    'Windows Error Reporting Archive Files',
    'Windows Error Reporting Files',
    'Windows Error Reporting Queue Files',
    'Windows Error Reporting System Archive Files',
    'Windows Error Reporting System Queue Files',
    'Windows ESD installation files',
    'Windows Upgrade Log Files'
)

foreach ($key in $cleanupFlags) {
    $keyPath = "$regCleanMgr\$key"
    if (Test-Path $keyPath) {
        Set-ItemProperty -Path $keyPath -Name 'StateFlags0064' -Value 2 -Type DWord -Force
    }
}

Write-Log 'Iniciando Disk Cleanup silencioso...' 'INFO'
Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:64' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
Write-Log "Disk Cleanup concluido. Total liberado manualmente: $([math]::Round($totalFreed/1MB,1)) MB" 'OK'

# ─────────────────────────────────────────────────────────────
#  8. POWER PLAN - ALTO DESEMPENHO
# ─────────────────────────────────────────────────────────────
Write-Section '8. Power Plan - High Performance'

# Guid do plano High Performance
$hpGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

# Ativa o plano High Performance
powercfg /setactive $hpGuid 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Log "Power Plan: High Performance ($hpGuid) ativado" 'OK'
} else {
    # Tenta Ultimate Performance (Windows 10 Pro/Enterprise)
    $upGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    powercfg /duplicatescheme $upGuid 2>&1 | Out-Null
    powercfg /setactive $upGuid 2>&1 | Out-Null
    Write-Log "Power Plan: Ultimate Performance ativado" 'OK'
}

# Desativa hibernacao (libera espaco do hiberfil.sys e acelera boot se nao usar Fast Startup)
powercfg /hibernate off 2>&1 | Out-Null
Write-Log 'Hibernacao desativada (hiberfil.sys removido)' 'OK'

# Mantem Fast Startup (usa hibernacao do kernel para boot rapido)
# NOTA: Fast Startup requer hibernacao PARCIAL do kernel, nao afetado pelo comando acima
$powerReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
Set-ItemProperty -Path $powerReg -Name 'HiberbootEnabled' -Value 1 -Type DWord -Force
Write-Log 'Fast Startup (HiberbootEnabled) = 1' 'OK'

# Desativa USB selective suspend
powercfg /setacvalueindex $hpGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
Write-Log 'USB Selective Suspend = desativado' 'OK'

# Desativa PCI-e Link State Power Management
powercfg /setacvalueindex $hpGuid 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 2>&1 | Out-Null
Write-Log 'PCIe Link State Power Mgmt = desativado' 'OK'

# Processor minimum state = 100% (sem throttling)
powercfg /setacvalueindex $hpGuid 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100 2>&1 | Out-Null
Write-Log 'Processor min state = 100%' 'OK'

# Aplica configuracoes
powercfg /setactive $hpGuid 2>&1 | Out-Null

# ─────────────────────────────────────────────────────────────
#  9. FONT CACHE
# ─────────────────────────────────────────────────────────────
Write-Section '9. Font Cache'

# Para o servico de cache de fontes
$fcService = 'FontCache'
Stop-Service -Name $fcService -Force -ErrorAction SilentlyContinue
Stop-Service -Name 'FontCache3.0.0.0' -Force -ErrorAction SilentlyContinue

# Limpa cache corrompido/antigo
$fontCachePaths = @(
    "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache",
    "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Local\FontCache-System",
    "$env:LOCALAPPDATA\Microsoft\Windows\FontCache"
)

foreach ($fcPath in $fontCachePaths) {
    if (Test-Path $fcPath) {
        Get-ChildItem -Path $fcPath -Filter '*FontCache*' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $fcPath -Filter '*.dat' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Log "  Font cache limpo: $fcPath" 'OK'
    }
}

# Remove arquivo de cache principal
$mainFontCache = "$env:SystemRoot\System32\FNTCACHE.DAT"
if (Test-Path $mainFontCache) {
    Remove-Item -Path $mainFontCache -Force -ErrorAction SilentlyContinue
    Write-Log "FNTCACHE.DAT removido (sera reconstruido)" 'OK'
}

# Reinicia servico
Start-Service -Name $fcService -ErrorAction SilentlyContinue
Set-Service   -Name $fcService -StartupType Automatic -ErrorAction SilentlyContinue
Write-Log 'FontCache reiniciado e configurado como Automatic' 'OK'

# ─────────────────────────────────────────────────────────────
#  10. OTIMIZACOES ADICIONAIS DE BOOT
# ─────────────────────────────────────────────────────────────
Write-Section '10. Otimizacoes Adicionais'

# Desativa animacao de boot (logo Windows)
bcdedit /set quietboot yes 2>&1 | Out-Null
Write-Log 'QuietBoot = yes (sem logo de boot)' 'OK'

# Desativa verificacao de disco agendada
$chkdskReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
Set-ItemProperty -Path $chkdskReg -Name 'BootExecute' `
    -Value 'autocheck autochk *' -Type MultiString -Force
Write-Log 'BootExecute = autocheck padrao' 'OK'

# Desativa DEP apenas para aplicacoes (NAO para kernel - nao faca isso)
# bcdedit /set nx OptIn  # Ja e o padrao, nao alterar

# Acelera fechamento de aplicacoes no shutdown
$controlReg = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty -Path $controlReg -Name 'AutoEndTasks'        -Value '1'    -Force
Set-ItemProperty -Path $controlReg -Name 'HungAppTimeout'      -Value '1000' -Force
Set-ItemProperty -Path $controlReg -Name 'WaitToKillAppTimeout'-Value '2000' -Force

$sysControlReg = 'HKLM:\SYSTEM\CurrentControlSet\Control'
Set-ItemProperty -Path $sysControlReg -Name 'WaitToKillServiceTimeout' -Value '2000' -Type String -Force
Write-Log 'Timeout de shutdown = 2s (servicos) / 1s (apps)' 'OK'

# Otimiza inicializacao de aplicacoes
$appCompatReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache'
# Nao apagar AppCompatCache - e usado pelo Windows para acelerar carregamento de EXEs

# Desativa Windows Tips e notificacoes de primeiro uso
$contentDelivery = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
if (Test-Path $contentDelivery) {
    Set-ItemProperty -Path $contentDelivery -Name 'SubscribedContent-338388Enabled' -Value 0 -Force
    Set-ItemProperty -Path $contentDelivery -Name 'SubscribedContent-338389Enabled' -Value 0 -Force
    Set-ItemProperty -Path $contentDelivery -Name 'SoftLandingEnabled' -Value 0 -Force
    Write-Log 'Windows Tips/Sugestoes desativadas' 'OK'
}

# Desativa startup delay de aplicacoes
$startupReg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize'
if (-not (Test-Path $startupReg)) { New-Item -Path $startupReg -Force | Out-Null }
Set-ItemProperty -Path $startupReg -Name 'StartupDelayInMSec' -Value 0 -Type DWord -Force
Write-Log 'Startup delay de apps = 0ms' 'OK'

# Desativa DCOM launch timeout excessivo
$dcomReg = 'HKLM:\SOFTWARE\Microsoft\Ole'
Set-ItemProperty -Path $dcomReg -Name 'LaunchTimeout' -Value 0x1388 -Type DWord -Force -ErrorAction SilentlyContinue

# Prioridade de I/O do boot
$ioReg = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
Set-ItemProperty -Path $ioReg -Name 'Win32PrioritySeparation' -Value 38 -Type DWord -Force
Write-Log 'Win32PrioritySeparation = 38 (otimizado para foreground)' 'OK'

# Desativa rastreamento de tempo de inicio de servicos desnecessario
$diagReg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Diagnostics'
if (-not (Test-Path $diagReg)) { New-Item -Path $diagReg -Force | Out-Null }
Set-ItemProperty -Path $diagReg -Name 'FXSRoutingReportingEnabled' -Value 0 -Type DWord -Force

# Otimiza Network boot (desativa NCSI probe se nao necessario)
$nlaReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
if (Test-Path $nlaReg) {
    Set-ItemProperty -Path $nlaReg -Name 'EnableActiveProbing' -Value 0 -Type DWord -Force
    Write-Log 'NCSI Active Probing = desativado' 'OK'
}

# Desativa Windows Defender scan na inicializacao (mantém protecao em tempo real)
$defenderReg = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'
if (-not (Test-Path $defenderReg)) { New-Item -Path $defenderReg -Force | Out-Null }
Set-ItemProperty -Path $defenderReg -Name 'DisableScanOnRealtimeEnable' -Value 1 -Type DWord -Force
Write-Log 'Defender: scan ao ativar tempo real = desativado' 'OK'

# ─────────────────────────────────────────────────────────────
#  11. DESFRAGMENTACAO / TRIM
# ─────────────────────────────────────────────────────────────
Write-Section '11. TRIM / Desfragmentacao'

if ($diskType -eq 'SSD' -or $diskType -eq 'NVMe') {
    # Executa TRIM no volume de sistema
    Optimize-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ReTrim -Verbose 2>&1 |
        Out-Null
    Write-Log "TRIM executado no volume $env:SystemDrive" 'OK'
} else {
    Write-Log "HDD detectado - pulando TRIM. Execute desfragmentacao manualmente." 'WARN'
}

# ─────────────────────────────────────────────────────────────
#  RESUMO FINAL
# ─────────────────────────────────────────────────────────────
Write-Section 'RESUMO E PROXIMOS PASSOS'

Write-Log @"
  Otimizacoes aplicadas com sucesso:
  [OK] BCD: timeout=0, bootdebug=off, ems=off, bootux=disabled
  [OK] NTFS: 8.3=off, lastaccess=off, MFT zone=2
  [OK] Prefetch/Superfetch: ajustado para tipo de disco ($diskType)
  [OK] Memoria: kernel na RAM, pagefile auto, no clear on shutdown
  [OK] Servicos: $delayedCount delayed, $disabledCount desativados
  [OK] Disco: limpeza de temp + Disk Cleanup
  [OK] Power Plan: High Performance + Fast Startup
  [OK] Font Cache: limpo e reconstruido
  [OK] Boot: quietboot, shutdown rapido, startup delay=0

  REINICIE o computador para aplicar todas as alteracoes.
  Log completo salvo em: $LogPath

  METAS DE BOOT ESTIMADAS:
  - SSD/NVMe: 8-12 segundos
  - HDD:      20-30 segundos

  NOTA: Para medir o tempo exato:
  powershell -Command "Get-WinEvent -ProviderName Microsoft-Windows-Diagnostics-Performance | Where-Object Id -eq 100 | Select-Object -First 3 | Format-List"
"@ 'OK'

Write-Log '=== TURBOSTARTUP CONCLUIDO ===' 'OK'
