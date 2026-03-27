#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Remove da inicialização do Windows os programas especificados.
.DESCRIPTION
    Desativa e remove entradas de inicialização automatica dos seguintes programas:
      01. WavesSvc
      02. MicrosoftEdgeAutoLaunch
      03. EPSDNMON  (Epson Network Printer Monitor)
      04. EPLTarget (Epson Printer Launcher)
      05. OneDrive

    Vetores cobertos por programa:
      - Chaves Run/RunOnce no registro (HKLM + HKCU + WOW6432Node, 32 e 64 bit)
      - Servicos Windows (Stop + StartupType Disabled)
      - Tarefas agendadas (Disable + Unregister)
      - Pasta Startup do usuario e de todos os usuarios
      - Politicas de grupo (GPO) via registro para travar re-habilitacao
      - Processos ativos (encerramento imediato)
.NOTES
    PowerShell 5.1 / Windows 10-11.
    Execute como Administrador.
    Log salvo em %TEMP%\DisableStartup_<timestamp>.log
    Os programas NAO sao desinstalados — apenas impedidos de iniciar.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ─────────────────────────────────────────────────────────────────────────────
#  INICIALIZACAO
# ─────────────────────────────────────────────────────────────────────────────
$LogFile = "$env:TEMP\DisableStartup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
#  FUNCOES AUXILIARES
# ─────────────────────────────────────────────────────────────────────────────

# Todas as chaves Run/RunOnce em HKLM e HKCU (32 e 64 bit)
$RunKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
)

function Remove-RunEntradas {
    <#
    .SYNOPSIS
        Remove entradas das chaves Run/RunOnce cujo nome OU valor bata com o padrao.
    #>
    param([string]$Padrao)   # Suporta wildcards: 'EPSDNMON', 'OneDrive*', etc.

    foreach ($chave in $RunKeys) {
        if (-not (Test-Path $chave)) { continue }

        $props = Get-ItemProperty $chave -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        $props.PSObject.Properties |
            Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notlike 'PS*' } |
            Where-Object { $_.Name -like $Padrao -or $_.Value -like "*$Padrao*" } |
            ForEach-Object {
                Write-Log "  Run removido : [$chave] → $($_.Name)"
                Write-Log "    Valor era  : $($_.Value)"
                Remove-ItemProperty -Path $chave -Name $_.Name -Force -ErrorAction SilentlyContinue
                if (-not (Get-ItemProperty $chave -Name $_.Name -ErrorAction SilentlyContinue)) {
                    Write-Log "    OK" -Tipo 'OK'
                } else {
                    Write-Log "    Nao removido (permissao?)" -Tipo 'AVISO'
                }
            }
    }
}

function Disable-Servicos {
    param([string[]]$Nomes)
    foreach ($n in $Nomes) {
        # Suporte a wildcard: Get-Service nao aceita wildcard no -Name diretamente,
        # por isso filtramos manualmente.
        $svcs = Get-WmiObject Win32_Service -Filter "Name LIKE '$(
            $n -replace '\*','%' -replace '\?','_'
        )'" -ErrorAction SilentlyContinue

        foreach ($svc in $svcs) {
            Write-Log "  Servico: $($svc.Name)  (inicio atual: $($svc.StartMode))"
            # Parar se estiver rodando
            if ($svc.State -eq 'Running') {
                $null = $svc.StopService()
                Start-Sleep -Milliseconds 800
            }
            # Desabilitar
            $null = $svc.ChangeStartMode('Disabled')
            # Confirmar via Set-Service tambem (dupla garantia)
            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
            $depois = (Get-WmiObject Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue).StartMode
            if ($depois -eq 'Disabled') {
                Write-Log "    Desabilitado" -Tipo 'OK'
            } else {
                Write-Log "    Modo atual: $depois" -Tipo 'AVISO'
            }
        }
    }
}

function Disable-Tarefas {
    <#
    .SYNOPSIS
        Desabilita E remove do agendador tarefas cujo nome bata com o padrao.
    #>
    param([string[]]$Padroes)
    foreach ($p in $Padroes) {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like "*$p*" -or $_.TaskPath -like "*$p*" } |
            ForEach-Object {
                Write-Log "  Tarefa: $($_.TaskPath)$($_.TaskName)  (estado: $($_.State))"
                Disable-ScheduledTask  -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
                Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
                Write-Log "    Desabilitada/Removida" -Tipo 'OK'
            }
    }
}

function Remove-AtalhosStartup {
    <#
    .SYNOPSIS
        Remove atalhos (.lnk) das pastas Startup do usuario e de todos os usuarios.
    #>
    param([string]$Padrao)   # ex: 'OneDrive*', 'Waves*'

    $pastaStartup = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )
    foreach ($pasta in $pastaStartup) {
        if (-not (Test-Path $pasta)) { continue }
        Get-ChildItem $pasta -Filter "$Padrao.lnk" -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Log "  Atalho Startup: $($_.FullName)"
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $_.FullName)) { Write-Log "    Removido" -Tipo 'OK' }
        }
        # Busca por nome parcial tambem (sem wildcards no arquivo)
        Get-ChildItem $pasta -Filter '*.lnk' -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$($Padrao -replace '\*','')*" } |
        ForEach-Object {
            Write-Log "  Atalho Startup: $($_.FullName)"
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $_.FullName)) { Write-Log "    Removido" -Tipo 'OK' }
        }
    }
}

function Garantir-ChaveRegistro {
    param([string]$Caminho)
    if (-not (Test-Path $Caminho)) {
        $null = New-Item $Caminho -Force -ErrorAction SilentlyContinue
    }
}

function Stop-Processos {
    param([string[]]$Nomes)
    foreach ($n in $Nomes) {
        Get-Process -Name $n -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Log "  Encerrando processo: $($_.Name) (PID $($_.Id))"
            $_ | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  EXECUCAO
# ═════════════════════════════════════════════════════════════════════════════

Write-Log ('═' * 60)
Write-Log '  DESATIVACAO DE INICIALIZACAO AUTOMATICA — Inicio'
Write-Log "  Log: $LogFile"
Write-Log ('═' * 60)

# ─────────────────────────────────────────────────────────────────────────────
# 01 ► WavesSvc
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '01/05 — WavesSvc (Waves Audio Service)'

Stop-Processos   @('WavesSvc64', 'WavesSvc', 'WavesUI', 'WavesLocalMediaServer')

# Servicos (WavesSvc pode ser 32 ou 64 bit conforme o sistema)
Disable-Servicos @('WavesSvc64', 'WavesSvc', 'WavesLocalMediaServer')

# Entradas Run no registro
Remove-RunEntradas 'WavesSvc*'
Remove-RunEntradas 'WavesUI*'

# Tarefas agendadas
Disable-Tarefas @('WavesSvc', 'Waves MaxxAudio', 'Waves Audio')

# Atalhos na pasta Startup
Remove-AtalhosStartup 'Waves*'

# Bloquear via politica de imagem (impede WavesSvc de ser registrado de novo
# como servico automatico por instaladores de driver)
$wavesPol = 'HKLM:\SOFTWARE\Policies\Waves Audio'
Garantir-ChaveRegistro $wavesPol
Set-ItemProperty $wavesPol -Name 'DisableAutoStart' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Write-Log '  WavesSvc — concluido' -Tipo 'OK'

# ─────────────────────────────────────────────────────────────────────────────
# 02 ► MicrosoftEdgeAutoLaunch  (Edge Startup Boost / pre-launch)
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '02/05 — MicrosoftEdgeAutoLaunch (Edge Startup Boost)'

# A entrada tem sufixo hash aleatorio: MicrosoftEdgeAutoLaunch_XXXXXXXXXX
# O wildcard * no padrao captura todas as variantes
Remove-RunEntradas 'MicrosoftEdgeAutoLaunch*'

# Edge tambem pode ter entrada de pre-launch generica
Remove-RunEntradas 'Microsoft Edge*'

# --- Politicas de grupo do Edge (impedem re-habilitacao automatica) ---
$edgePol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Garantir-ChaveRegistro $edgePol

$edgePolConfig = @{
    'StartupBoostEnabled'        = 0   # Desativa Startup Boost (roda em bg no login)
    'BackgroundModeEnabled'      = 0   # Desativa modo em background
    'HideFirstRunExperience'     = 1   # Suprime janela inicial que pode re-habilitar
    'RestoreOnStartup'           = 5   # Nao abrir paginas anteriores ao iniciar
    'ShowRecommendationsEnabled' = 0   # Sem pop-ups sugerindo reativar
}
foreach ($kv in $edgePolConfig.GetEnumerator()) {
    Set-ItemProperty $edgePol -Name $kv.Key -Value $kv.Value -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Log "  Edge Policy: $($kv.Key) = $($kv.Value)" -Tipo 'OK'
}

# Desativar via configuracao interna do Edge (nao-GPO, so por garantia)
$edgeConfig = 'HKCU:\SOFTWARE\Microsoft\Edge\Main'
Garantir-ChaveRegistro $edgeConfig
Set-ItemProperty $edgeConfig -Name 'AllowPrelaunch'     -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty $edgeConfig -Name 'StartupBoostEnabled' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

# Tarefas do Edge Update que podem re-registrar o AutoLaunch
Disable-Tarefas @('MicrosoftEdgeAutoLaunch', 'MicrosoftEdge', 'MicrosoftEdgeShadowStack')

# Atalhos
Remove-AtalhosStartup 'Microsoft Edge*'

Write-Log '  MicrosoftEdgeAutoLaunch — concluido' -Tipo 'OK'

# ─────────────────────────────────────────────────────────────────────────────
# 03 ► EPSDNMON  (Epson Network Printer Monitor)
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '03/05 — EPSDNMON (Epson Network Printer Monitor)'

Stop-Processos @('EPSDNMON', 'EpsonNetworkPrinterMonitor', 'EpsonScan2', 'EpsDnMon')

# Remover das chaves Run — nome exato e variacoes conhecidas
Remove-RunEntradas 'EPSDNMON*'
Remove-RunEntradas 'EpsonNetworkPrinterMonitor*'
Remove-RunEntradas 'EPSON_S*'    # EPSON_S-XXX entradas de monitor de scan

# Servicos relacionados
Disable-Servicos @(
    'EPSON_PM_RPCV4_V4',       # Monitor de impressora EPSON
    'EPSON_PM_RPCV4_V3',
    'EPSON_PM_RPCV4_V2',
    'EpsonScanSvc',
    'EpsonNetworkPrinterMonitor'
)

# Tarefas agendadas
Disable-Tarefas @('EPSDNMON', 'EpsonNetworkPrinter', 'EPSON_S')

# Atalhos na pasta Startup
Remove-AtalhosStartup 'EPSDNMON*'
Remove-AtalhosStartup 'Epson*Monitor*'

Write-Log '  EPSDNMON — concluido' -Tipo 'OK'

# ─────────────────────────────────────────────────────────────────────────────
# 04 ► EPLTarget  (Epson Printer Launcher Target)
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '04/05 — EPLTarget (Epson Printer Launcher Target)'

Stop-Processos @('EPLTarget', 'EplTarget')

# Remover das chaves Run
Remove-RunEntradas 'EPLTarget*'
Remove-RunEntradas 'EplTarget*'

# EPLTarget.exe costuma residir no diretorio de driver de impressora.
# Remover do registro de spooler / driver auto-execute se presente.
$spoolerRunKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers'
if (Test-Path $spoolerRunKey) {
    Get-ChildItem $spoolerRunKey -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            $monitorProp = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($monitorProp.Monitor -like '*EPLTarget*') {
                Write-Log "  Spooler Monitor EPLTarget: $($_.PSPath)"
                Remove-ItemProperty $_.PSPath -Name 'Monitor' -Force -ErrorAction SilentlyContinue
            }
        }
}

# Servicos relacionados ao launcher EPSON
Disable-Servicos @('EPLTarget', 'EPSON_L_XXXX_TARGET')

# Tarefas agendadas
Disable-Tarefas @('EPLTarget', 'EplTarget', 'EPSON.*Target', 'EPSON.*Launcher')

# Atalhos
Remove-AtalhosStartup 'EPLTarget*'
Remove-AtalhosStartup 'Epson*Launcher*'

Write-Log '  EPLTarget — concluido' -Tipo 'OK'

# ─────────────────────────────────────────────────────────────────────────────
# 05 ► OneDrive
# ─────────────────────────────────────────────────────────────────────────────
Cabecalho '05/05 — OneDrive'

Stop-Processos @('OneDrive', 'OneDriveStandaloneUpdater')

# --- Chaves Run ---
Remove-RunEntradas 'OneDrive*'
Remove-RunEntradas 'OneDriveSetup*'

# --- Servicos OneDrive ---
# OneDrive nao e sempre servico, mas versoes empresariais podem ter
Disable-Servicos @('OneDrive', 'OneDriveUpdaterService')

# --- Tarefas agendadas ---
Disable-Tarefas @(
    'OneDrive Standalone Update Task',
    'OneDrive Per-Machine Standalone Update Task',
    'OneDrive Reporting Task',
    'OneDriveTask',
    'OneDrive'
)

# --- Atalhos da pasta Startup ---
Remove-AtalhosStartup 'OneDrive*'

# --- Politica de grupo: desabilitar OneDrive como local de salvamento
#     e impedir que se auto-inicie ---
$odPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
Garantir-ChaveRegistro $odPol

$odPolConfig = @{
    'DisableFileSyncNGSC'          = 1  # Bloqueia integracao e auto-inicio
    'DisableFileSync'              = 1  # Desativa sincronizacao
    'PreventNetworkTrafficPreUser' = 1  # Impede trafego de rede antes de login manual
}
foreach ($kv in $odPolConfig.GetEnumerator()) {
    Set-ItemProperty $odPol -Name $kv.Key -Value $kv.Value -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Log "  OneDrive Policy: $($kv.Key) = $($kv.Value)" -Tipo 'OK'
}

# Desativar OneDrive do inicio via configuracao de usuario tambem
$odUserConfig = 'HKCU:\SOFTWARE\Microsoft\OneDrive'
if (Test-Path $odUserConfig) {
    Set-ItemProperty $odUserConfig -Name 'EnableADAL'   -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty $odUserConfig -Name 'DisableSetup' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
}

# Remover OneDrive do painel de navegacao do Explorer (barra lateral)
$clsidOneDrive = 'HKCU:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
Garantir-ChaveRegistro $clsidOneDrive
Set-ItemProperty $clsidOneDrive -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Log "  OneDrive removido da barra lateral do Explorer" -Tipo 'OK'

# Variante 32-bit do CLSID
$clsidOneDrive32 = 'HKCU:\SOFTWARE\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
if (Test-Path $clsidOneDrive32) {
    Set-ItemProperty $clsidOneDrive32 -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
}

Write-Log '  OneDrive — concluido' -Tipo 'OK'

# ═════════════════════════════════════════════════════════════════════════════
#  VERIFICACAO FINAL — listar o que resta nas chaves Run
# ═════════════════════════════════════════════════════════════════════════════
Write-Log ('═' * 60)
Write-Log '  VERIFICACAO — entradas Run remanescentes (todos os programas tratados)'
Write-Log ('═' * 60)

$alvos = @('WavesSvc', 'MicrosoftEdgeAutoLaunch', 'EPSDNMON', 'EPLTarget', 'OneDrive')
$encontrouResiduos = $false

foreach ($chave in $RunKeys) {
    if (-not (Test-Path $chave)) { continue }
    $props = Get-ItemProperty $chave -ErrorAction SilentlyContinue
    if (-not $props) { continue }

    $props.PSObject.Properties |
        Where-Object { $_.MemberType -eq 'NoteProperty' -and $_.Name -notlike 'PS*' } |
        Where-Object {
            $n = $_.Name; $v = "$($_.Value)"
            ($alvos | Where-Object { $n -like "*$_*" -or $v -like "*$_*" }).Count -gt 0
        } |
        ForEach-Object {
            Write-Log "  RESIDUO: [$chave] $($_.Name) = $($_.Value)" -Tipo 'AVISO'
            $encontrouResiduos = $true
        }
}

if (-not $encontrouResiduos) {
    Write-Log '  Nenhum residuo encontrado nas chaves Run.' -Tipo 'OK'
}

# ─────────────────────────────────────────────────────────────────────────────
#  RESUMO FINAL
# ─────────────────────────────────────────────────────────────────────────────
Write-Log ('═' * 60)
Write-Log '  Desativacao de inicializacao concluida!' -Tipo 'OK'
Write-Log "  Log: $LogFile"
Write-Log '  RECOMENDADO: Reinicie para confirmar que nenhum item volta ao startup.'
Write-Log ('═' * 60)

Write-Host "`nPressione ENTER para sair..." -ForegroundColor White
$null = Read-Host
