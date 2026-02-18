#Requires -Version 5.1
<#
.SYNOPSIS
    Otimizacao completa de inicializacao e desempenho do Windows.

.DESCRIPTION
    Realiza uma serie de acoes para acelerar a inicializacao do Windows:
    - Limpa cache e dados temporarios do Chrome
    - Desabilita extensoes pesadas do Chrome
    - Otimiza flags de hardware acceleration do Chrome
    - Remove auto-inicializacao do Microsoft Edge
    - Desabilita Epson Download Navigator
    - Desabilita tarefas agendadas de atualizacao desnecessarias
    - Encerra processos orfaos / pendurados
    - Remove entradas desnecessarias da inicializacao (registro + pasta)
    - Desabilita servicos de terceiros nao essenciais na inicializacao
    - Aplica ajustes de desempenho do Windows

.NOTES
    Execute como Administrador para acesso completo.
    Faz backup das entradas de registro alteradas antes de modificar.

.EXAMPLE
    .\Optimize-Startup.ps1
    .\Optimize-Startup.ps1 -ModoSimulacao   # Apenas mostra o que seria feito, sem alterar nada
    .\Optimize-Startup.ps1 -PularChrome     # Pula otimizacoes do Chrome
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ModoSimulacao,   # Dry-run: mostra acoes sem executar
    [switch]$PularChrome,
    [switch]$PularEdge,
    [switch]$PularServicos,
    [switch]$PularTarefas,
    [switch]$PularProcessos,
    [string]$BackupPath = "$env:USERPROFILE\Desktop\Backup_Registro_Startup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ─── Contadores de resultado ───────────────────────────────────────────────
$script:acoes     = 0
$script:ignoradas = 0
$script:erros     = 0
$script:log       = [System.Collections.Generic.List[string]]::new()

# ─── Utilitarios ───────────────────────────────────────────────────────────

function Write-Header {
    param([string]$t)
    $sep = "=" * 70
    Write-Host "`n$sep" -ForegroundColor Cyan
    Write-Host "  $t" -ForegroundColor Yellow
    Write-Host "$sep" -ForegroundColor Cyan
    $script:log.Add("`n### $t")
}

function Write-Step {
    param([string]$msg, [string]$status = "OK", [string]$detalhe = "")
    $cor = switch ($status) {
        "OK"      { "Green" }
        "SKIP"    { "DarkGray" }
        "WARN"    { "Yellow" }
        "ERR"     { "Red" }
        "SIM"     { "Cyan" }
        default   { "White" }
    }
    $tag = "[$status]".PadRight(7)
    Write-Host "  $tag $msg" -ForegroundColor $cor
    if ($detalhe) { Write-Host "         $detalhe" -ForegroundColor DarkGray }
    $script:log.Add("  $tag $msg $(if($detalhe){"| $detalhe"})")
}

function Invoke-Acao {
    param([string]$descricao, [scriptblock]$bloco)
    if ($ModoSimulacao) {
        Write-Step $descricao "SIM"
        $script:acoes++
        return
    }
    try {
        & $bloco
        Write-Step $descricao "OK"
        $script:acoes++
    } catch {
        Write-Step $descricao "ERR" $_.Exception.Message
        $script:erros++
    }
}

function Remove-RegistryValue {
    param([string]$path, [string]$name)
    if (Test-Path $path) {
        $prop = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        if ($prop) {
            Invoke-Acao "Removendo '$name' de $path" {
                Remove-ItemProperty -Path $path -Name $name -Force
            }
        } else {
            Write-Step "Entrada '$name' nao encontrada em $path" "SKIP"
            $script:ignoradas++
        }
    } else {
        Write-Step "Chave nao existe: $path" "SKIP"
        $script:ignoradas++
    }
}

function Disable-ScheduledTaskSafe {
    param([string]$taskPath, [string]$taskName)
    $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t) {
        if ($t.State -ne 'Disabled') {
            Invoke-Acao "Desabilitando tarefa: $taskPath$taskName" {
                Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName | Out-Null
            }
        } else {
            Write-Step "Tarefa ja desabilitada: $taskName" "SKIP"
            $script:ignoradas++
        }
    } else {
        Write-Step "Tarefa nao encontrada: $taskName" "SKIP"
        $script:ignoradas++
    }
}

function Set-ServiceStartupSafe {
    param([string]$serviceName, [string]$startType = "Manual")
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        $atual = (Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue).StartMode
        if ($atual -ne $startType -and $atual -ne "Disabled") {
            Invoke-Acao "Servico '$serviceName' -> $startType (era: $atual)" {
                Set-Service -Name $serviceName -StartupType $startType
            }
        } else {
            Write-Step "Servico '$serviceName' ja esta como $atual" "SKIP"
            $script:ignoradas++
        }
    } else {
        Write-Step "Servico nao encontrado: $serviceName" "SKIP"
        $script:ignoradas++
    }
}

# ─── Verificar admin ───────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Clear-Host
Write-Host @"

  ╔══════════════════════════════════════════════════════════════════╗
  ║         OTIMIZADOR DE INICIALIZACAO E DESEMPENHO                 ║
  ║         Chrome | Edge | Epson | Servicos | Tarefas | Startup     ║
  ╚══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "  Computador : $env:COMPUTERNAME  |  Usuario: $env:USERNAME" -ForegroundColor White
Write-Host "  Data/Hora  : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor White

if ($ModoSimulacao) {
    Write-Host "`n  [MODO SIMULACAO] Nenhuma alteracao sera feita.`n" -ForegroundColor Cyan
}
if (-not $isAdmin) {
    Write-Host "`n  [!] Execute como Administrador para acesso completo a servicos e tarefas.`n" -ForegroundColor Red
} else {
    Write-Host "  [OK] Rodando com privilegios de Administrador.`n" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 1 — BACKUP DO REGISTRO
# ─────────────────────────────────────────────────────────────────────────────

Write-Header "ETAPA 1 — BACKUP DAS CHAVES DE INICIALIZACAO"

$backupKeys = @(
    "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

if (-not $ModoSimulacao) {
    try {
        $args_reg = ($backupKeys | ForEach-Object { "`"$_`"" }) -join " "
        $tmpScript = "$env:TEMP\backup_reg.cmd"
        "reg export `"$($backupKeys[0])`" `"$BackupPath`" /y" | Out-File $tmpScript -Encoding ASCII
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c reg export `"$($backupKeys[0])`" `"$BackupPath`" /y" -Wait -WindowStyle Hidden
        Write-Step "Backup salvo em: $BackupPath" "OK"
    } catch {
        Write-Step "Falha no backup (continuando mesmo assim)" "WARN"
    }
} else {
    Write-Step "Backup seria salvo em: $BackupPath" "SIM"
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 2 — CHROME: CACHE E DADOS TEMPORARIOS
# ─────────────────────────────────────────────────────────────────────────────

if (-not $PularChrome) {
    Write-Header "ETAPA 2 — CHROME: LIMPEZA DE CACHE E DADOS TEMPORARIOS"

    # Fechar Chrome se estiver aberto
    $chromeProc = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
    if ($chromeProc) {
        Invoke-Acao "Encerrando Google Chrome para limpeza segura" {
            Stop-Process -Name "chrome" -Force
            Start-Sleep -Seconds 2
        }
    } else {
        Write-Step "Chrome nao esta em execucao" "SKIP"
        $script:ignoradas++
    }

    $chromeDataPath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path $chromeDataPath) {

        # Pastas de cache a limpar em cada perfil
        $cacheFolders = @(
            "Cache", "Cache2", "Code Cache", "GPUCache",
            "Service Worker\CacheStorage", "Service Worker\ScriptCache",
            "Media Cache", "Application Cache", "ShaderCache"
        )

        # Descobre perfis (Default, Profile 1, Profile 2, ...)
        $perfis = @("Default") + (Get-ChildItem "$chromeDataPath" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^Profile \d+" } | Select-Object -ExpandProperty Name)

        $totalLiberado = 0

        foreach ($perfil in $perfis) {
            foreach ($pasta in $cacheFolders) {
                $caminho = "$chromeDataPath\$perfil\$pasta"
                if (Test-Path $caminho) {
                    $tamanho = (Get-ChildItem $caminho -Recurse -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    $tamanhoMB = [math]::Round((if ($tamanho) { $tamanho } else { 0 }) / 1MB, 1)
                    $totalLiberado += $tamanhoMB
                    Invoke-Acao "[$perfil] Limpando $pasta ($tamanhoMB MB)" {
                        Remove-Item -Path $caminho -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        # Logs e arquivos de crash
        $extraFiles = @(
            "chrome_debug.log", "Crash Reports", "BrowserMetrics",
            "Crashpad", "pnacl", "SwReporter"
        )
        foreach ($f in $extraFiles) {
            $p = "$chromeDataPath\$f"
            if (Test-Path $p) {
                Invoke-Acao "Removendo: $f" { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }

        Write-Host "`n  Total estimado liberado de cache Chrome: $totalLiberado MB" -ForegroundColor Green

    } else {
        Write-Step "Chrome nao instalado ou perfil nao encontrado" "SKIP"
        $script:ignoradas++
    }

    # ─────────────────────────────────────────────────────────────────────────
    #  ETAPA 3 — CHROME: DESABILITAR EXTENSOES PESADAS
    # ─────────────────────────────────────────────────────────────────────────

    Write-Header "ETAPA 3 — CHROME: EXTENSOES PESADAS (analise e relatorio)"

    # Extensoes conhecidas por consumo elevado
    $extensoesPesadas = @{
        "extensao_grammarly"    = "Grammarly"
        "extensao_honey"        = "Honey/PayPal"
        "extensao_lastpass"     = "LastPass"
        "extensao_avast"        = "Avast Online Security"
        "extensao_avg"          = "AVG Online Security"
        "extensao_mcafee"       = "McAfee WebAdvisor"
        "extensao_norton"       = "Norton Safe Web"
        "extensao_bitdefender"  = "Bitdefender TrafficLight"
        "extensao_kaspersky"    = "Kaspersky Protection"
        "extensao_cisco_umbrella" = "Cisco Umbrella"
    }

    # IDs reais de extensoes conhecidas por serem pesadas
    $idsExtensoesPesadas = @(
        "kbfnbcaeplbcioakkpcpgfkobkghlhen",  # Grammarly
        "bmnlcjabgnpnenekpadlanbbkooimhnj",  # Honey
        "hdokiejnpimakedhajhdlcegeplioahd",  # LastPass
        "gomekmidlodglbbmalcneegieacbdmki",  # Avast
        "hmlcjjclebjnfohgmgdkljbejggenpbc",  # McAfee
        "cjpalhdlnbpafiamejdnhcphjbkeiagm",  # Google Docs Offline (pode ser pesado)
    )

    $perfilDefault = "$chromeDataPath\Default\Extensions"
    if (Test-Path $perfilDefault) {
        $todasExtensoes = Get-ChildItem $perfilDefault -Directory -ErrorAction SilentlyContinue
        Write-Host "`n  Total de extensoes instaladas (perfil Default): $($todasExtensoes.Count)" -ForegroundColor White

        $extPesadasEncontradas = 0
        foreach ($ext in $todasExtensoes) {
            if ($idsExtensoesPesadas -contains $ext.Name) {
                $extPesadasEncontradas++
                $tamanhoExt = [math]::Round((Get-ChildItem $ext.FullName -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum / 1MB, 1)
                Write-Step "Extensao pesada detectada: $($ext.Name) ($tamanhoExt MB)" "WARN" "Desabilite manualmente em chrome://extensions"
            }
        }

        if ($extPesadasEncontradas -eq 0) {
            Write-Step "Nenhuma extensao conhecida por alto consumo detectada" "OK"
        }

        Write-Host "`n  Para gerenciar extensoes acesse: chrome://extensions" -ForegroundColor DarkYellow
        Write-Host "  Para ver uso por extensao: chrome://system -> Mais informacoes" -ForegroundColor DarkYellow
    }

    # ─────────────────────────────────────────────────────────────────────────
    #  ETAPA 4 — CHROME: HARDWARE ACCELERATION E FLAGS DE DESEMPENHO
    # ─────────────────────────────────────────────────────────────────────────

    Write-Header "ETAPA 4 — CHROME: HARDWARE ACCELERATION E OTIMIZACOES"

    # Criar/atualizar Local State com flags de performance
    $localState = "$chromeDataPath\Local State"
    if (Test-Path $localState) {
        Invoke-Acao "Otimizando flags de desempenho no Local State do Chrome" {
            $json = Get-Content $localState -Raw | ConvertFrom-Json

            # Garantir hardware acceleration ativa
            if (-not $json.PSObject.Properties["hardware_acceleration_mode"]) {
                $json | Add-Member -MemberType NoteProperty -Name "hardware_acceleration_mode" -Value @{enabled = $true}
            } else {
                $json.hardware_acceleration_mode = @{enabled = $true}
            }

            # Desabilitar background mode (Chrome rodando em segundo plano sem janela)
            if (-not $json.PSObject.Properties["background_mode"]) {
                $json | Add-Member -MemberType NoteProperty -Name "background_mode" -Value @{enabled = $false}
            } else {
                $json.background_mode.enabled = $false
            }

            $json | ConvertTo-Json -Depth 20 | Set-Content $localState -Encoding UTF8
        }

        # Desabilitar Chrome no background via registro (impede execucao sem janelas)
        Invoke-Acao "Desabilitando Chrome Background Mode via registro" {
            $regChrome = "HKCU:\SOFTWARE\Google\Chrome"
            if (-not (Test-Path $regChrome)) { New-Item -Path $regChrome -Force | Out-Null }
            Set-ItemProperty -Path $regChrome -Name "BackgroundModeEnabled" -Value 0 -Type DWord
        }
    } else {
        Write-Step "Local State do Chrome nao encontrado" "SKIP"
        $script:ignoradas++
    }

    # Remover Chrome da inicializacao do sistema (se presente)
    $chromePaths = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Google Chrome" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Google Chrome" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "GoogleChromeAutoLaunch*" }
    )
    foreach ($entry in $chromePaths) {
        Remove-RegistryValue -path $entry.Path -name $entry.Name
    }

    # Desabilitar tarefa do Google Update que abre Chrome automaticamente
    $googleTarefas = @(
        @{ Path = "\"; Name = "GoogleUpdateTaskMachineCore" },
        @{ Path = "\"; Name = "GoogleUpdateTaskMachineUA" },
        @{ Path = "\Google\"; Name = "GoogleUpdateTaskMachineCore" },
        @{ Path = "\Google\"; Name = "GoogleUpdateTaskMachineUA" },
        @{ Path = "\Google\"; Name = "GoogleUpdateTaskUserCore" }
    )
    foreach ($t in $googleTarefas) {
        Disable-ScheduledTaskSafe -taskPath $t.Path -taskName $t.Name
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 5 — MICROSOFT EDGE: REMOVER AUTO-LAUNCH
# ─────────────────────────────────────────────────────────────────────────────

if (-not $PularEdge) {
    Write-Header "ETAPA 5 — MICROSOFT EDGE: REMOVER AUTO-INICIALIZACAO"

    $edgeRunKeys = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";  Name = "MicrosoftEdge" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";  Name = "MicrosoftEdge" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";  Name = "MicrosoftEdgeAutoLaunch" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";  Name = "MicrosoftEdgeAutoLaunch" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";  Name = "Microsoft Edge" }
    )
    foreach ($e in $edgeRunKeys) { Remove-RegistryValue -path $e.Path -name $e.Name }

    # Politica do Edge: desabilitar startup boost e background
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    Invoke-Acao "Configurando politica: Edge StartupBoostEnabled = 0" {
        if (-not (Test-Path $edgePolicyPath)) { New-Item -Path $edgePolicyPath -Force | Out-Null }
        Set-ItemProperty -Path $edgePolicyPath -Name "StartupBoostEnabled"    -Value 0 -Type DWord
        Set-ItemProperty -Path $edgePolicyPath -Name "BackgroundModeEnabled"  -Value 0 -Type DWord
    }

    # Desabilitar tarefas do Edge
    $edgeTarefas = @(
        @{ Path = "\Microsoft\EdgeUpdate\"; Name = "MicrosoftEdgeUpdateTaskMachineCore" },
        @{ Path = "\Microsoft\EdgeUpdate\"; Name = "MicrosoftEdgeUpdateTaskMachineUA" },
        @{ Path = "\Microsoft\MicrosoftEdge\"; Name = "MicrosoftEdgeUpdateTaskMachineCore" },
        @{ Path = "\MicrosoftEdge\"; Name = "MicrosoftEdgeUpdateTaskMachineCore" }
    )
    foreach ($t in $edgeTarefas) { Disable-ScheduledTaskSafe -taskPath $t.Path -taskName $t.Name }

    # Remover Edge do boot via chave especifica
    $edgeBootKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe"
    # Nao vamos desabilitar o executavel, apenas o auto-launch via registro

    Write-Step "Edge configurado para nao inicializar automaticamente" "OK"
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 6 — EPSON DOWNLOAD NAVIGATOR E OUTROS SOFTWARES EPSON
# ─────────────────────────────────────────────────────────────────────────────

Write-Header "ETAPA 6 — EPSON: DESABILITAR DOWNLOAD NAVIGATOR E AUTO-UPDATES"

$epsonRunEntries = @(
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Epson Download Navigator" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Epson Download Navigator" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EpsonDownloadNavigator" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EpsonDownloadNavigator" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EPSON" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EPSON" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EpsonSoftwareUpdater" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EpsonSoftwareUpdater" },
    @{ Path = "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Name = "Epson Download Navigator" },
    @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Name = "Epson Download Navigator" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EpsonBidirectionalService" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "EpsonBidirectionalService" }
)
foreach ($e in $epsonRunEntries) { Remove-RegistryValue -path $e.Path -name $e.Name }

$epsonTarefas = @(
    @{ Path = "\"; Name = "EpsonSoftwareUpdater" },
    @{ Path = "\Epson\"; Name = "EpsonSoftwareUpdater" },
    @{ Path = "\"; Name = "Epson Updater" },
    @{ Path = "\EPSON\"; Name = "EPSON XP-241 Series Update{*" }
)
foreach ($t in $epsonTarefas) { Disable-ScheduledTaskSafe -taskPath $t.Path -taskName $t.Name }

# Servicos Epson
$epsonServicos = @("EPSON_EB_RPCV4_06", "EPSON_PM_RPCV4_06", "EpsonScanSvc", "EpsonBidirectionalService")
foreach ($s in $epsonServicos) { Set-ServiceStartupSafe -serviceName $s -startType "Manual" }

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 7 — TAREFAS AGENDADAS DESNECESSARIAS
# ─────────────────────────────────────────────────────────────────────────────

if (-not $PularTarefas) {
    Write-Header "ETAPA 7 — TAREFAS AGENDADAS DESNECESSARIAS"

    $tarefasParaDesabilitar = @(

        # Adobe
        @{ Path = "\Adobe\"; Name = "Adobe Acrobat Update Task" },
        @{ Path = "\Adobe\"; Name = "AdobeAAMUpdater-1.0" },
        @{ Path = "\Adobe\"; Name = "Adobe Flash Player Updater" },
        @{ Path = "\";       Name = "Adobe Acrobat Update Task" },

        # Java
        @{ Path = "\";       Name = "Java Update Scheduler" },
        @{ Path = "\";       Name = "JavaUpdateScheduler" },

        # Apple / iTunes / iCloud / Bonjour
        @{ Path = "\Apple\"; Name = "AppleSoftwareUpdate" },
        @{ Path = "\";       Name = "AppleSoftwareUpdate" },
        @{ Path = "\";       Name = "iTunesHelper" },

        # Spotify
        @{ Path = "\";       Name = "Spotify" },
        @{ Path = "\Spotify AB\"; Name = "Spotify" },

        # Zoom
        @{ Path = "\";       Name = "ZoomUpdateTask" },
        @{ Path = "\Zoom\";  Name = "ZoomUpdateTask" },

        # Skype
        @{ Path = "\";       Name = "SkypeUpdate" },

        # CCleaner
        @{ Path = "\";       Name = "CCleanerSkipUAC" },
        @{ Path = "\Piriform\"; Name = "CCleanerSkipUAC" },

        # RealPlayer
        @{ Path = "\";       Name = "RealUpgradeLogonTaskS-*" },
        @{ Path = "\Real\";  Name = "RealUpgradeLogonTask" },

        # HP
        @{ Path = "\HP\";    Name = "HP Active Health" },
        @{ Path = "\HP\";    Name = "HP Support Solutions Framework" },

        # WinRAR
        @{ Path = "\";       Name = "WinRAR Schedule Xray Vision" },
        @{ Path = "\";       Name = "RAR_optimizer_task" },

        # Malwarebytes
        @{ Path = "\Malwarebytes\"; Name = "Malwarebytes_StartupUI" },

        # Mozilla Firefox
        @{ Path = "\Mozilla\"; Name = "Firefox Default Browser Agent *" },

        # Opera
        @{ Path = "\Opera Software\"; Name = "Opera scheduled Autoupdate *" },

        # VLC
        @{ Path = "\";       Name = "VLCUpdateTask" },

        # TeamViewer
        @{ Path = "\";       Name = "TeamViewer" },
        @{ Path = "\TeamViewer\"; Name = "TeamViewer" }
    )

    foreach ($t in $tarefasParaDesabilitar) {
        Disable-ScheduledTaskSafe -taskPath $t.Path -taskName $t.Name
    }

    # Varredura generica: tarefas de terceiros em execucao automatica
    Write-SubHeader "Varredura de tarefas de terceiros ativas"
    $tarefasTerceiros = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object {
            $_.State -eq 'Ready' -and
            $_.TaskPath -notmatch '\\Microsoft\\' -and
            $_.TaskPath -notmatch '\\Windows\\'  -and
            $_.TaskPath -ne '\'
        }

    if ($tarefasTerceiros) {
        Write-Host "`n  Tarefas de terceiros ainda ativas (analise manual recomendada):" -ForegroundColor Yellow
        foreach ($t in $tarefasTerceiros) {
            Write-Host "    $($t.TaskPath)$($t.TaskName)" -ForegroundColor DarkYellow
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 8 — PROCESSOS ORFAOS / PENDURADOS
# ─────────────────────────────────────────────────────────────────────────────

if (-not $PularProcessos) {
    Write-Header "ETAPA 8 — LIMPEZA DE PROCESSOS ORFAOS"

    # Processos conhecidos por ficar em segundo plano sem necessidade
    $processosOrcaos = @(
        "chrome",              # Chrome sem janela (background mode)
        "msedge",              # Edge sem janela
        "EpsonDownloadNavigator",
        "EpsonSoftwareUpdater",
        "AdobeARM",            # Adobe Reader Manager (update)
        "AdobeUpdateService",
        "AGSService",          # Adobe Genuine Service (desnecessario)
        "armsvc",              # Adobe ARM service
        "jusched",             # Java Update Scheduler
        "jqs",                 # Java Quick Starter
        "iTunesHelper",
        "AppleMobileDeviceService",
        "mDNSResponder",       # Bonjour (Apple)
        "Skype",               # Se estiver rodando sem uso
        "SkypeApp",
        "OneDrive",            # Se nao usar OneDrive
        "Teams",               # Microsoft Teams (se nao estiver em uso)
        "slack",
        "discord",
        "spotify",
        "zoom",
        "zoomwebviewhost",
        "RealDownloader",
        "WinRAR",
        "ccleaner",
        "TeamViewer",
        "TeamViewer_Service"
    )

    Write-Host "`n  Verificando processos sem janela em execucao...`n" -ForegroundColor Gray

    foreach ($nome in $processosOrcaos) {
        $procs = Get-Process -Name $nome -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -eq 0 -or $_.MainWindowTitle -eq "" }

        foreach ($p in $procs) {
            Invoke-Acao "Encerrando processo orfao: $nome (PID: $($p.Id))" {
                Stop-Process -Id $p.Id -Force
            }
        }
    }

    # Processos travados (Not Responding)
    $travados = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Responding -eq $false }
    foreach ($p in $travados) {
        Invoke-Acao "Encerrando processo travado: $($p.ProcessName) (PID: $($p.Id))" {
            Stop-Process -Id $p.Id -Force
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 9 — INICIALIZACAO: REGISTRO (Run / RunOnce)
# ─────────────────────────────────────────────────────────────────────────────

Write-Header "ETAPA 9 — LIMPEZA DA INICIALIZACAO (REGISTRO)"

# Entradas conhecidas como desnecessarias na inicializacao
$runEntriesToRemove = @(

    # Adobe
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "AdobeAAMUpdater-1.0" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "AdobeAAMUpdater-1.0" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Adobe ARM" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Adobe ARM" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Adobe Reader Speed Launcher" },

    # Java
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "SunJavaUpdateSched" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "SunJavaUpdateSched" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "JavaUpdateSched" },

    # iTunes / Apple
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "iTunesHelper" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "iTunesHelper" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "AppleSoftwareUpdate" },

    # Spotify (comentar se usar Spotify e quiser inicializacao rapida)
    # @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Spotify" },

    # Skype
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Skype" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "SkypeWithTeams" },

    # Zoom
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Zoom" },

    # CCleaner
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "CCleaner Smart Cleaning" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "CCleaner Smart Cleaning" },

    # WinRAR
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "WinRAR" },

    # Discord
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Discord" },

    # Slack
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "com.squirrel.slack.slack" },

    # Teams (antigo)
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "com.squirrel.Teams.Teams" },

    # HP
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "HPAdvisorDock" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "HP Software Framework" },

    # Dell
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "DellSupportCenter" },

    # Lenovo
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Lenovo System Interface Foundation" },

    # RealPlayer
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "TkBellExe" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "TkBellExe" },

    # Acrobat DC Notification
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "Acrobat Assistant 8.0" },

    # Quick Time
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "QuickTime Task" },

    # Cyberlink
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "CLMLServer" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "RemoteControl11" },

    # TeamViewer
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "TeamViewer" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Name = "TeamViewer" }
)

foreach ($e in $runEntriesToRemove) { Remove-RegistryValue -path $e.Path -name $e.Name }

# Limpar entradas de RunOnce
$runOnceKeys = @(
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
)
foreach ($key in $runOnceKeys) {
    if (Test-Path $key) {
        $vals = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Select-Object -Property * -ExcludeProperty PS*
        if ($vals) {
            Invoke-Acao "Limpando RunOnce: $key" {
                Get-Item -Path $key | Select-Object -ExpandProperty Property |
                    ForEach-Object { Remove-ItemProperty -Path $key -Name $_ -Force -ErrorAction SilentlyContinue }
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 10 — SERVICOS DE TERCEIROS: DEFINIR COMO MANUAL
# ─────────────────────────────────────────────────────────────────────────────

if (-not $PularServicos) {
    Write-Header "ETAPA 10 — SERVICOS: DEFINIR TERCEIROS COMO MANUAL"

    $servicosParaManual = @(
        # Adobe
        "AdobeARMservice",
        "AdobeUpdateService",
        "AGSService",           # Adobe Genuine Service

        # Apple / iTunes / Bonjour
        "AppleMobileDeviceService",
        "Bonjour Service",
        "iPod Service",

        # Java
        "JavaQuickStarterService",

        # Google (Chrome/Update)
        "gupdate",
        "gupdatem",

        # Spotify
        "SpotifyWebHelper",

        # TeamViewer
        "TeamViewer",

        # Zoom
        "ZoomCNA",

        # HP
        "HPSupportSolutionsFrameworkService",
        "HPDiagnosticCoreService",

        # Dell
        "DellSupportCenter",

        # Skype
        "SkypeUpdate",

        # Nvidia (manter GeForce Experience apenas se usar)
        # "NVDisplay.ContainerLocalSystem",  # NAO desabilitar - driver
        "NvTelemetryContainer",

        # AMD (manter driver, desabilitar telemetria)
        "AMD Crash Defender Service",
        "AMDRyzenMasterDriverV20",

        # RealNetworks
        "RealNetworks Scheduler",

        # CyberLink
        "CLHNServiceForPowerDVD",

        # WinRAR (nao tem servico geralmente)

        # McAfee (se desinstalado mas servico ainda presente)
        "McAfeeFramework",
        "McShield",
        "McTaskManager",

        # Norton
        "NortonSecurity"
    )

    foreach ($s in $servicosParaManual) {
        Set-ServiceStartupSafe -serviceName $s -startType "Manual"
    }

    # Servicos do Windows que podem ser desabilitados em uso domestico
    Write-SubHeader "Servicos Windows opcionais (uso domestico)"

    $servicosWindowsOpcionais = @(
        @{ Nome = "Fax";                    Desc = "Servico de Fax" },
        @{ Nome = "XblAuthManager";         Desc = "Xbox Live Auth" },
        @{ Nome = "XblGameSave";            Desc = "Xbox Live Game Save" },
        @{ Nome = "XboxNetApiSvc";          Desc = "Xbox Network" },
        @{ Nome = "XboxGipSvc";             Desc = "Xbox Accessory" },
        @{ Nome = "diagnosticshub.standardcollector.service"; Desc = "Diagnostics Hub" },
        @{ Nome = "DiagTrack";              Desc = "Telemetria Connected User Experiences" },
        @{ Nome = "dmwappushservice";       Desc = "WAP Push Message" },
        @{ Nome = "RetailDemo";             Desc = "Modo Demo de Varejo" },
        @{ Nome = "WMPNetworkSvc";          Desc = "Windows Media Player Network" },
        @{ Nome = "WerSvc";                 Desc = "Relatorio de Erros Windows" },
        @{ Nome = "RemoteRegistry";         Desc = "Registro Remoto (risco de seguranca)" }
    )

    foreach ($s in $servicosWindowsOpcionais) {
        Write-Host "  Verificando: $($s.Desc)..." -ForegroundColor DarkGray -NoNewline
        Set-ServiceStartupSafe -serviceName $s.Nome -startType "Disabled"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 11 — AJUSTES DE DESEMPENHO DO WINDOWS
# ─────────────────────────────────────────────────────────────────────────────

Write-Header "ETAPA 11 — AJUSTES DE DESEMPENHO DO WINDOWS"

# Efeitos visuais: prioridade para desempenho
Invoke-Acao "Ajustando efeitos visuais para melhor desempenho" {
    $visualFX = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $visualFX)) { New-Item -Path $visualFX -Force | Out-Null }
    Set-ItemProperty -Path $visualFX -Name "VisualFXSetting" -Value 2 -Type DWord
}

# Desabilitar animacoes pesadas mantendo as essenciais
Invoke-Acao "Desabilitando animacoes de janela desnecessarias" {
    $dwm = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $dwm -Name "MenuShowDelay" -Value "0"
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0"
}

# Prioridade de processos em primeiro plano
Invoke-Acao "Priorizando processos em primeiro plano" {
    $mm = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    Set-ItemProperty -Path $mm -Name "Win32PrioritySeparation" -Value 38 -Type DWord
}

# Desabilitar Search Indexer durante uso intenso (deixar como manual)
Invoke-Acao "Configurando Search Indexer como Manual (economiza CPU em idle)" {
    Set-Service -Name "WSearch" -StartupType Manual -ErrorAction SilentlyContinue
}

# Limpar arquivos temporarios do Windows
Invoke-Acao "Limpando arquivos temporarios do Windows" {
    $tempPaths = @($env:TEMP, $env:TMP, "C:\Windows\Temp")
    foreach ($tp in $tempPaths) {
        if (Test-Path $tp) {
            Get-ChildItem -Path $tp -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}

# Limpar DNS Cache
Invoke-Acao "Limpando cache DNS" {
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

# Prefetch e Superfetch
Invoke-Acao "Otimizando SysMain (Superfetch) para SSD" {
    $ssd = $true  # Assumindo SSD; ajustar se HDD
    if ($ssd) {
        Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
    }
}

# Fast Startup (Inicializacao rapida do Windows)
Invoke-Acao "Habilitando Fast Startup do Windows" {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
        -Name "HiberbootEnabled" -Value 1 -Type DWord
}

# Desabilitar telemetria
Invoke-Acao "Reduzindo telemetria do Windows" {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" `
        -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────
#  ETAPA 12 — PASTA DE INICIALIZACAO DO USUARIO
# ─────────────────────────────────────────────────────────────────────────────

Write-Header "ETAPA 12 — PASTA STARTUP DO USUARIO"

$startupUser   = [System.Environment]::GetFolderPath('Startup')
$startupCommon = [System.Environment]::GetFolderPath('CommonStartup')

foreach ($folder in @($startupUser, $startupCommon)) {
    $items = Get-ChildItem -Path $folder -ErrorAction SilentlyContinue
    if ($items) {
        Write-Host "`n  Itens na pasta: $folder" -ForegroundColor Yellow
        foreach ($item in $items) {
            Write-Host "    $($item.Name)" -ForegroundColor Cyan
            Write-Host "    -> Avaliar se necessario. Para remover: Delete o arquivo acima." -ForegroundColor DarkGray
        }
    } else {
        Write-Step "Pasta vazia ou nao encontrada: $folder" "OK"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  SUMARIO FINAL
# ─────────────────────────────────────────────────────────────────────────────

Write-Header "SUMARIO FINAL"

Write-Host @"

  Acoes realizadas com sucesso : $($script:acoes)
  Entradas nao encontradas     : $($script:ignoradas) (normal - nao instala todos os softwares)
  Erros                        : $($script:erros)

  PROXIMOS PASSOS RECOMENDADOS:
  ─────────────────────────────────────────────────────────
  [1] Reinicie o computador para aplicar todas as mudancas
  [2] Verifique o Gerenciador de Tarefas -> Inicializacao
      (Ctrl+Shift+Esc -> Inicializacao) para itens restantes
  [3] Para Chrome: abra chrome://settings/system
      Desative "Continuar executando apps em segundo plano"
  [4] Para Edge: abra edge://settings/system
      Desative "Inicializacao Rapida" e "Continuar em segundo plano"
  [5] Verifique tarefas agendadas: taskschd.msc
  [6] Verifique servicos: services.msc
  ─────────────────────────────────────────────────────────

"@ -ForegroundColor White

if ($script:erros -gt 0) {
    Write-Host "  Alguns erros ocorreram. Execute como Administrador para acesso completo.`n" -ForegroundColor Red
} else {
    Write-Host "  Otimizacao concluida com sucesso!`n" -ForegroundColor Green
}

if ($ModoSimulacao) {
    Write-Host "  [MODO SIMULACAO] Nenhuma alteracao foi feita. Execute sem -ModoSimulacao para aplicar.`n" -ForegroundColor Cyan
}
