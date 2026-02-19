#Requires -Version 5.1
<#
.SYNOPSIS
    Mapeamento avancado e completo de todos os softwares/programas instalados no computador.

.DESCRIPTION
    Varre 11 fontes distintas para localizar, identificar e catalogar cada aplicativo,
    programa, driver, feature, pacote e extensao presente no sistema:

      [1]  Registro HKLM 64-bit  (programas instalados globalmente, 64 bits)
      [2]  Registro HKLM 32-bit  (programas instalados globalmente, 32 bits / WOW64)
      [3]  Registro HKCU         (programas instalados apenas para o usuario atual)
      [4]  Apps UWP / Loja       (Microsoft Store, MSIX, Appx)
      [5]  Features do Windows   (recursos opcionais via DISM / Get-WindowsOptionalFeature)
      [6]  Capacidades Windows   (Get-WindowsCapability - FODs)
      [7]  Servicos instalados    (Win32 Services catalogados)
      [8]  Scan de executaveis    (Program Files, Program Files(x86), AppData)
      [9]  Pacotes Chocolatey     (se Choco estiver instalado)
      [10] Pacotes Winget         (se Winget estiver instalado)
      [11] Inicializacao (Startup) (Run keys + pastas Startup)

    Exporta relatorio HTML interativo com busca em tempo real, filtros por categoria,
    ordenacao por colunas e grafico de resumo. Tambem gera CSV e JSON completos.

.PARAMETER OutputDir
    Pasta de destino dos relatorios. Padrao: Desktop do usuario.

.PARAMETER ScanProgramFiles
    Incluir varredura de executaveis em Program Files (pode ser lento). Padrao: $true.

.PARAMETER ScanFeatures
    Incluir features/capacidades do Windows (requer admin). Padrao: $true.

.PARAMETER ScanServicos
    Incluir servicos do Windows. Padrao: $true.

.PARAMETER ScanStartup
    Incluir itens de inicializacao. Padrao: $true.

.PARAMETER FiltroNome
    Filtrar resultados por nome (suporta wildcards). Ex: -FiltroNome "*Adobe*".

.PARAMETER FiltroCategoria
    Mostrar apenas uma categoria especifica (Registro, UWP, Feature, Servico, Executavel, Startup, Choco, Winget).

.PARAMETER AbrirRelatorio
    Abrir o relatorio HTML automaticamente ao finalizar. Padrao: $true.

.EXAMPLE
    .\Map-InstalledSoftware.ps1
    # Varredura completa, relatorio no Desktop.

.EXAMPLE
    .\Map-InstalledSoftware.ps1 -FiltroNome "*Adobe*" -AbrirRelatorio $false
    # Busca apenas por produtos Adobe, sem abrir o navegador.

.EXAMPLE
    .\Map-InstalledSoftware.ps1 -ScanProgramFiles $false -ScanFeatures $false
    # Varredura rapida: somente registro + UWP + startup.

.NOTES
    Autor   : Claude Code
    Versao  : 2.0
    Execute como Administrador para resultados completos (features, capacidades).
    Sem admin, fontes que exigem elevacao sao ignoradas graciosamente.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDir = "$env:USERPROFILE\Desktop",

    [Parameter()]
    [bool]$ScanProgramFiles = $true,

    [Parameter()]
    [bool]$ScanFeatures = $true,

    [Parameter()]
    [bool]$ScanServicos = $true,

    [Parameter()]
    [bool]$ScanStartup = $true,

    [Parameter()]
    [string]$FiltroNome = "",

    [Parameter()]
    [ValidateSet("", "Registro", "UWP", "Feature", "Capacidade", "Servico", "Executavel", "Startup", "Chocolatey", "Winget")]
    [string]$FiltroCategoria = "",

    [Parameter()]
    [bool]$AbrirRelatorio = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference    = "SilentlyContinue"

# ═══════════════════════════════════════════════════════════════════
#  VARIAVEIS GLOBAIS
# ═══════════════════════════════════════════════════════════════════
$Script:Timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:DataHora    = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
$Script:NomePC      = $env:COMPUTERNAME
$Script:Usuario     = $env:USERNAME
$Script:SistemaOS   = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$Script:Arquitetura = $env:PROCESSOR_ARCHITECTURE
$Script:IsAdmin     = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")

$Script:TodosItens  = [System.Collections.Generic.List[PSCustomObject]]::new()
$Script:Contadores  = @{
    Registro    = 0
    UWP         = 0
    Feature     = 0
    Capacidade  = 0
    Servico     = 0
    Executavel  = 0
    Startup     = 0
    Chocolatey  = 0
    Winget      = 0
}

# ═══════════════════════════════════════════════════════════════════
#  FUNCOES AUXILIARES
# ═══════════════════════════════════════════════════════════════════

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        MAP-INSTALLED-SOFTWARE  v2.0  — Mapeamento Total      ║" -ForegroundColor Cyan
    Write-Host "  ║              Rodrigues e Prado Advocacia  |  CODEX            ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Maquina  : $Script:NomePC" -ForegroundColor Gray
    Write-Host "  Usuario  : $Script:Usuario" -ForegroundColor Gray
    Write-Host "  Sistema  : $Script:SistemaOS" -ForegroundColor Gray
    Write-Host "  Admin    : $(if ($Script:IsAdmin) { 'SIM (resultados completos)' } else { 'NAO (alguns dados podem estar incompletos)' })" -ForegroundColor $(if ($Script:IsAdmin) { "Green" } else { "Yellow" })
    Write-Host "  Inicio   : $Script:DataHora" -ForegroundColor Gray
    Write-Host ""
}

function Write-Etapa {
    param([string]$Numero, [string]$Descricao)
    Write-Host "  [$Numero] " -ForegroundColor Yellow -NoNewline
    Write-Host $Descricao -ForegroundColor White
}

function Write-SubInfo {
    param([string]$Texto)
    Write-Host "       $Texto" -ForegroundColor DarkGray
}

function Write-OK {
    param([string]$Texto)
    Write-Host "       OK  $Texto" -ForegroundColor Green
}

function Write-Aviso {
    param([string]$Texto)
    Write-Host "       !   $Texto" -ForegroundColor Yellow
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-TamanhoDir {
    param([string]$Caminho)
    try {
        if ([string]::IsNullOrEmpty($Caminho) -or -not (Test-Path $Caminho)) { return "" }
        $tamanho = (Get-ChildItem -Path $Caminho -Recurse -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($tamanho) { return Format-Bytes $tamanho } else { return "" }
    } catch { return "" }
}

function Adicionar-Item {
    param(
        [string]$Categoria,
        [string]$Nome,
        [string]$Versao        = "",
        [string]$Publicador    = "",
        [string]$DataInstalacao = "",
        [string]$CaminhoInstall = "",
        [string]$Tamanho       = "",
        [string]$Arquitetura   = "",
        [string]$GUID          = "",
        [string]$Descricao     = "",
        [string]$FonteDetalhe  = "",
        [string]$Status        = "",
        [string]$Extra1Label   = "",
        [string]$Extra1Valor   = ""
    )

    # Aplicar filtros
    if ($FiltroNome -ne "" -and $Nome -notlike $FiltroNome) { return }
    if ($FiltroCategoria -ne "" -and $Categoria -ne $FiltroCategoria) { return }

    $Script:TodosItens.Add([PSCustomObject]@{
        Categoria       = $Categoria
        Nome            = $Nome
        Versao          = $Versao
        Publicador      = $Publicador
        DataInstalacao  = $DataInstalacao
        CaminhoInstall  = $CaminhoInstall
        Tamanho         = $Tamanho
        Arquitetura     = $Arquitetura
        GUID            = $GUID
        Descricao       = $Descricao
        FonteDetalhe    = $FonteDetalhe
        Status          = $Status
        Extra1Label     = $Extra1Label
        Extra1Valor     = $Extra1Valor
    })

    $Script:Contadores[$Categoria]++
}

# ═══════════════════════════════════════════════════════════════════
#  [1] [2] [3]  REGISTRO DO WINDOWS (HKLM 64, HKLM 32, HKCU)
# ═══════════════════════════════════════════════════════════════════
function Scan-Registro {
    Write-Etapa "1/2/3" "Registro do Windows (HKLM 64-bit + HKLM 32-bit + HKCU)"

    $chaves = @(
        @{ Caminho = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";            Arq = "64-bit"; Cat = "Registro" },
        @{ Caminho = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"; Arq = "32-bit"; Cat = "Registro" },
        @{ Caminho = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";            Arq = "User";   Cat = "Registro" }
    )

    foreach ($fonte in $chaves) {
        Write-SubInfo "Varrendo $($fonte.Caminho) ..."

        if (-not (Test-Path $fonte.Caminho)) {
            Write-Aviso "Chave nao encontrada: $($fonte.Caminho)"
            continue
        }

        $subchaves = Get-ChildItem -Path $fonte.Caminho -ErrorAction SilentlyContinue
        $count = 0

        foreach ($subchave in $subchaves) {
            $props = Get-ItemProperty -Path $subchave.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { continue }

            $nome = $props.DisplayName
            if ([string]::IsNullOrWhiteSpace($nome)) { continue }

            # Data de instalacao: pode vir como yyyyMMdd
            $dataInstall = ""
            if ($props.InstallDate -and $props.InstallDate -match "^\d{8}$") {
                try {
                    $d = [datetime]::ParseExact($props.InstallDate, "yyyyMMdd", $null)
                    $dataInstall = $d.ToString("dd/MM/yyyy")
                } catch { $dataInstall = $props.InstallDate }
            }

            $caminho = if ($props.InstallLocation) { $props.InstallLocation.TrimEnd("\") }
                       elseif ($props.InstallSource)   { $props.InstallSource.TrimEnd("\") }
                       else { "" }

            $tamanho = ""
            if ($props.EstimatedSize -and $props.EstimatedSize -gt 0) {
                $tamanho = Format-Bytes ($props.EstimatedSize * 1KB)
            } elseif ($caminho -and (Test-Path $caminho)) {
                # Nao calcular tamanho em tempo real aqui para manter velocidade
                $tamanho = "(calcular)"
            }

            Adicionar-Item `
                -Categoria       "Registro" `
                -Nome            $nome `
                -Versao          ($props.DisplayVersion ?? "") `
                -Publicador      ($props.Publisher ?? "") `
                -DataInstalacao  $dataInstall `
                -CaminhoInstall  $caminho `
                -Tamanho         $tamanho `
                -Arquitetura     $fonte.Arq `
                -GUID            ($subchave.PSChildName) `
                -Descricao       ($props.Comments ?? "") `
                -FonteDetalhe    $fonte.Caminho `
                -Status          $(if ($props.SystemComponent -eq 1) { "Componente Sistema" } else { "Aplicativo" }) `
                -Extra1Label     "UninstallString" `
                -Extra1Valor     ($props.UninstallString ?? "")

            $count++
        }
        Write-OK "$count programas encontrados em $($fonte.Arq)"
    }
}

# ═══════════════════════════════════════════════════════════════════
#  [4]  APPS UWP / MICROSOFT STORE (MSIX / APPX)
# ═══════════════════════════════════════════════════════════════════
function Scan-UWP {
    Write-Etapa "4" "Apps UWP / Microsoft Store (Appx / MSIX)"

    $apps = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    if (-not $apps) {
        $apps = Get-AppxPackage -ErrorAction SilentlyContinue
    }

    $count = 0
    foreach ($app in $apps) {
        $manifest = $null
        try { $manifest = Get-AppxPackageManifest -Package $app.PackageFullName -ErrorAction SilentlyContinue } catch {}

        $descricao = ""
        $publicador = $app.Publisher
        if ($manifest) {
            $descricao  = $manifest.Package.Properties.Description ?? ""
            if ([string]::IsNullOrEmpty($publicador)) {
                $publicador = $manifest.Package.Properties.PublisherDisplayName ?? ""
            }
        }

        $caminho = $app.InstallLocation ?? ""

        $tipo = switch -Wildcard ($app.PackageFullName) {
            "*Framework*"   { "Framework" }
            "*Runtime*"     { "Runtime" }
            "*VCLibs*"      { "VC Redistributable" }
            "*Microsoft*"   { "Microsoft" }
            default         { "App Loja" }
        }

        Adicionar-Item `
            -Categoria       "UWP" `
            -Nome            ($app.Name) `
            -Versao          ($app.Version.ToString()) `
            -Publicador      $publicador `
            -DataInstalacao  "" `
            -CaminhoInstall  $caminho `
            -Tamanho         "" `
            -Arquitetura     ($app.Architecture.ToString()) `
            -GUID            ($app.PackageFullName) `
            -Descricao       $descricao `
            -FonteDetalhe    "Get-AppxPackage" `
            -Status          $(if ($app.IsFramework) { "Framework" } else { $tipo }) `
            -Extra1Label     "PackageFamilyName" `
            -Extra1Valor     ($app.PackageFamilyName ?? "")

        $count++
    }
    Write-OK "$count apps UWP/Store encontrados"
}

# ═══════════════════════════════════════════════════════════════════
#  [5]  FEATURES OPCIONAIS DO WINDOWS (DISM)
# ═══════════════════════════════════════════════════════════════════
function Scan-Features {
    Write-Etapa "5" "Features Opcionais do Windows (Get-WindowsOptionalFeature)"

    if (-not $Script:IsAdmin) {
        Write-Aviso "Admin necessario para features do Windows — ignorado."
        return
    }

    $features = Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue
    if (-not $features) { Write-Aviso "Nao foi possivel obter features."; return }

    $count = 0
    foreach ($f in $features) {
        Adicionar-Item `
            -Categoria       "Feature" `
            -Nome            ($f.FeatureName) `
            -Versao          "" `
            -Publicador      "Microsoft" `
            -DataInstalacao  "" `
            -CaminhoInstall  "" `
            -Tamanho         "" `
            -Arquitetura     "" `
            -GUID            "" `
            -Descricao       ($f.Description ?? "") `
            -FonteDetalhe    "Get-WindowsOptionalFeature" `
            -Status          ($f.State.ToString()) `
            -Extra1Label     "Estado" `
            -Extra1Valor     ($f.State.ToString())

        $count++
    }
    Write-OK "$count features mapeadas ($( ($features | Where-Object State -eq 'Enabled').Count ) habilitadas)"
}

# ═══════════════════════════════════════════════════════════════════
#  [6]  CAPACIDADES DO WINDOWS (FOD - Features on Demand)
# ═══════════════════════════════════════════════════════════════════
function Scan-Capacidades {
    Write-Etapa "6" "Capacidades do Windows (Get-WindowsCapability / FOD)"

    if (-not $Script:IsAdmin) {
        Write-Aviso "Admin necessario para capacidades — ignorado."
        return
    }

    $caps = Get-WindowsCapability -Online -ErrorAction SilentlyContinue
    if (-not $caps) { Write-Aviso "Nao foi possivel obter capacidades."; return }

    $count = 0
    foreach ($c in $caps) {
        Adicionar-Item `
            -Categoria       "Capacidade" `
            -Nome            ($c.Name) `
            -Versao          "" `
            -Publicador      "Microsoft" `
            -DataInstalacao  "" `
            -CaminhoInstall  "" `
            -Tamanho         "" `
            -Arquitetura     "" `
            -GUID            "" `
            -Descricao       "" `
            -FonteDetalhe    "Get-WindowsCapability" `
            -Status          ($c.State.ToString()) `
            -Extra1Label     "Estado" `
            -Extra1Valor     ($c.State.ToString())

        $count++
    }
    Write-OK "$count capacidades mapeadas ($( ($caps | Where-Object State -eq 'Installed').Count ) instaladas)"
}

# ═══════════════════════════════════════════════════════════════════
#  [7]  SERVICOS DO WINDOWS
# ═══════════════════════════════════════════════════════════════════
function Scan-Servicos {
    Write-Etapa "7" "Servicos do Windows (Win32 Services)"

    $servicos = Get-Service -ErrorAction SilentlyContinue
    $wmiServicos = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue

    # Indexar WMI por nome para lookup rapido
    $wmiIndex = @{}
    if ($wmiServicos) {
        foreach ($ws in $wmiServicos) {
            $wmiIndex[$ws.Name] = $ws
        }
    }

    $count = 0
    foreach ($svc in $servicos) {
        $wmi = $wmiIndex[$svc.Name]

        $caminho = ""
        $publicador = ""
        $descricao = $svc.DisplayName

        if ($wmi) {
            $caminho  = $wmi.PathName ?? ""
            $descricao = $wmi.Description ?? $svc.DisplayName
        }

        # Tentar obter publicador do executavel
        $exePath = ""
        if ($caminho -match '"([^"]+)"') { $exePath = $Matches[1] }
        elseif ($caminho -match '^(\S+\.exe)') { $exePath = $Matches[1] }

        if ($exePath -and (Test-Path $exePath -ErrorAction SilentlyContinue)) {
            $vi = (Get-Item $exePath -ErrorAction SilentlyContinue).VersionInfo
            if ($vi) { $publicador = $vi.CompanyName ?? "" }
        }

        Adicionar-Item `
            -Categoria       "Servico" `
            -Nome            ($svc.DisplayName) `
            -Versao          "" `
            -Publicador      $publicador `
            -DataInstalacao  "" `
            -CaminhoInstall  $caminho `
            -Tamanho         "" `
            -Arquitetura     "" `
            -GUID            ($svc.Name) `
            -Descricao       $descricao `
            -FonteDetalhe    "Get-Service" `
            -Status          ($svc.Status.ToString()) `
            -Extra1Label     "StartType" `
            -Extra1Valor     ($svc.StartType.ToString())

        $count++
    }
    Write-OK "$count servicos mapeados ($( ($servicos | Where-Object Status -eq 'Running').Count ) em execucao)"
}

# ═══════════════════════════════════════════════════════════════════
#  [8]  SCAN DE EXECUTAVEIS EM PROGRAM FILES
# ═══════════════════════════════════════════════════════════════════
function Scan-Executaveis {
    Write-Etapa "8" "Varredura de executaveis (Program Files + AppData\Local\Programs)"

    $dirs = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        "$env:LOCALAPPDATA\Programs",
        "$env:APPDATA\Programs"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    $count = 0

    foreach ($dir in $dirs) {
        Write-SubInfo "Varrendo: $dir"

        # Varrer apenas nivel 1 e 2 de subpastas (evitar recursao total que e muito lenta)
        $subpastas = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue

        foreach ($pasta in $subpastas) {
            # Procurar executavel principal (mesmo nome da pasta ou qualquer .exe)
            $exes = Get-ChildItem -Path $pasta.FullName -Filter "*.exe" -Depth 1 -ErrorAction SilentlyContinue |
                    Sort-Object -Property Length -Descending |
                    Select-Object -First 3

            if (-not $exes) { continue }

            $exePrincipal = $exes | Select-Object -First 1
            $vi = $exePrincipal.VersionInfo

            $nome      = if ($vi.ProductName) { $vi.ProductName } else { $pasta.Name }
            $versao    = if ($vi.ProductVersion) { $vi.ProductVersion } else { $vi.FileVersion ?? "" }
            $publicador = $vi.CompanyName ?? ""
            $tamanho   = Get-TamanhoDir -Caminho $pasta.FullName

            # Verificar se ja foi mapeado pelo registro (evitar duplicata exata)
            $jaExiste = $Script:TodosItens | Where-Object {
                $_.Categoria -eq "Registro" -and
                $_.CaminhoInstall -and
                ($pasta.FullName -like "$($_.CaminhoInstall)*" -or $_.CaminhoInstall -like "$($pasta.FullName)*")
            }

            if ($jaExiste) { continue }

            Adicionar-Item `
                -Categoria       "Executavel" `
                -Nome            $nome `
                -Versao          $versao `
                -Publicador      $publicador `
                -DataInstalacao  ($pasta.CreationTime.ToString("dd/MM/yyyy")) `
                -CaminhoInstall  ($pasta.FullName) `
                -Tamanho         $tamanho `
                -Arquitetura     "" `
                -GUID            "" `
                -Descricao       ($vi.FileDescription ?? "") `
                -FonteDetalhe    $dir `
                -Status          "Detectado (sem desinstalador)" `
                -Extra1Label     "Executavel" `
                -Extra1Valor     ($exePrincipal.FullName)

            $count++
        }
    }
    Write-OK "$count programas detectados por varredura de diretorio"
}

# ═══════════════════════════════════════════════════════════════════
#  [9]  PACOTES CHOCOLATEY
# ═══════════════════════════════════════════════════════════════════
function Scan-Chocolatey {
    Write-Etapa "9" "Pacotes Chocolatey"

    $chocoPath = (Get-Command choco -ErrorAction SilentlyContinue)?.Source
    if (-not $chocoPath) {
        # Tentar caminho padrao
        $chocoPath = "$env:ChocolateyInstall\bin\choco.exe"
        if (-not (Test-Path $chocoPath -ErrorAction SilentlyContinue)) {
            Write-Aviso "Chocolatey nao encontrado — ignorado."
            return
        }
    }

    Write-SubInfo "Chocolatey encontrado em: $chocoPath"

    try {
        $saida = & choco list --local-only --no-color 2>&1
        $count = 0

        foreach ($linha in $saida) {
            if ($linha -match "^(\S+)\s+(\S+)$" -and $linha -notmatch "packages installed") {
                $nome   = $Matches[1]
                $versao = $Matches[2]
                if ($nome -eq "Chocolatey") { continue }

                $caminho = "$env:ChocolateyInstall\lib\$nome"

                Adicionar-Item `
                    -Categoria       "Chocolatey" `
                    -Nome            $nome `
                    -Versao          $versao `
                    -Publicador      "" `
                    -DataInstalacao  "" `
                    -CaminhoInstall  $caminho `
                    -Tamanho         "" `
                    -Arquitetura     "" `
                    -GUID            "" `
                    -Descricao       "" `
                    -FonteDetalhe    "choco list --local-only" `
                    -Status          "Instalado" `
                    -Extra1Label     "Gerenciador" `
                    -Extra1Valor     "Chocolatey"

                $count++
            }
        }
        Write-OK "$count pacotes Chocolatey encontrados"
    } catch {
        Write-Aviso "Erro ao consultar Chocolatey: $($_.Exception.Message)"
    }
}

# ═══════════════════════════════════════════════════════════════════
#  [10] PACOTES WINGET
# ═══════════════════════════════════════════════════════════════════
function Scan-Winget {
    Write-Etapa "10" "Pacotes Winget (Windows Package Manager)"

    $wingetPath = (Get-Command winget -ErrorAction SilentlyContinue)?.Source
    if (-not $wingetPath) {
        Write-Aviso "Winget nao encontrado — ignorado."
        return
    }

    Write-SubInfo "Winget encontrado em: $wingetPath"

    try {
        # Winget exporta em JSON — mais confiavel
        $tempJson = [System.IO.Path]::GetTempFileName() + ".json"
        & winget export -o $tempJson --accept-source-agreements 2>&1 | Out-Null

        $count = 0
        if (Test-Path $tempJson) {
            $dados = Get-Content $tempJson -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($dados -and $dados.Sources) {
                foreach ($fonte in $dados.Sources) {
                    foreach ($pkg in $fonte.Packages) {
                        Adicionar-Item `
                            -Categoria       "Winget" `
                            -Nome            ($pkg.PackageIdentifier) `
                            -Versao          ($pkg.Version ?? "") `
                            -Publicador      "" `
                            -DataInstalacao  "" `
                            -CaminhoInstall  "" `
                            -Tamanho         "" `
                            -Arquitetura     "" `
                            -GUID            ($pkg.PackageIdentifier) `
                            -Descricao       "" `
                            -FonteDetalhe    "winget export" `
                            -Status          "Instalado" `
                            -Extra1Label     "SourceName" `
                            -Extra1Valor     ($fonte.SourceDetails.Name ?? "")

                        $count++
                    }
                }
            }
            Remove-Item $tempJson -Force -ErrorAction SilentlyContinue
        }

        # Fallback: winget list em texto
        if ($count -eq 0) {
            $saida = & winget list --accept-source-agreements 2>&1
            foreach ($linha in $saida) {
                if ($linha -match "^\S" -and $linha -notmatch "^Name|^---|-") {
                    $partes = $linha -split "\s{2,}"
                    if ($partes.Count -ge 2) {
                        Adicionar-Item `
                            -Categoria       "Winget" `
                            -Nome            ($partes[0].Trim()) `
                            -Versao          ($partes[2]?.Trim() ?? "") `
                            -Publicador      "" `
                            -DataInstalacao  "" `
                            -CaminhoInstall  "" `
                            -Tamanho         "" `
                            -Arquitetura     "" `
                            -GUID            ($partes[1]?.Trim() ?? "") `
                            -Descricao       "" `
                            -FonteDetalhe    "winget list" `
                            -Status          "Instalado" `
                            -Extra1Label     "ID" `
                            -Extra1Valor     ($partes[1]?.Trim() ?? "")

                        $count++
                    }
                }
            }
        }

        Write-OK "$count pacotes Winget encontrados"
    } catch {
        Write-Aviso "Erro ao consultar Winget: $($_.Exception.Message)"
    }
}

# ═══════════════════════════════════════════════════════════════════
#  [11] ITENS DE INICIALIZACAO (STARTUP)
# ═══════════════════════════════════════════════════════════════════
function Scan-Startup {
    Write-Etapa "11" "Itens de Inicializacao (Run Keys + Pastas Startup)"

    $fontesRun = @(
        @{ Chave = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                     Escopo = "Sistema (HKLM)" },
        @{ Chave = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";                 Escopo = "Sistema RunOnce" },
        @{ Chave = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";         Escopo = "Sistema 32-bit" },
        @{ Chave = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                     Escopo = "Usuario (HKCU)" },
        @{ Chave = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";                 Escopo = "Usuario RunOnce" }
    )

    $count = 0

    # Run Keys
    foreach ($fonte in $fontesRun) {
        if (-not (Test-Path $fonte.Chave -ErrorAction SilentlyContinue)) { continue }

        $props = Get-ItemProperty -Path $fonte.Chave -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        foreach ($prop in ($props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" })) {
            $exePath = $prop.Value
            $publicador = ""
            $versao = ""

            # Extrair caminho do executavel
            $exeReal = ""
            if ($exePath -match '"([^"]+\.exe)"') { $exeReal = $Matches[1] }
            elseif ($exePath -match '^([^\s]+\.exe)') { $exeReal = $Matches[1] }

            if ($exeReal -and (Test-Path $exeReal -ErrorAction SilentlyContinue)) {
                $vi = (Get-Item $exeReal -ErrorAction SilentlyContinue)?.VersionInfo
                if ($vi) {
                    $publicador = $vi.CompanyName ?? ""
                    $versao     = $vi.ProductVersion ?? $vi.FileVersion ?? ""
                }
            }

            Adicionar-Item `
                -Categoria       "Startup" `
                -Nome            ($prop.Name) `
                -Versao          $versao `
                -Publicador      $publicador `
                -DataInstalacao  "" `
                -CaminhoInstall  $exePath `
                -Tamanho         "" `
                -Arquitetura     "" `
                -GUID            "" `
                -Descricao       "Inicializacao automatica" `
                -FonteDetalhe    $fonte.Chave `
                -Status          $fonte.Escopo `
                -Extra1Label     "Comando" `
                -Extra1Valor     $exePath

            $count++
        }
    }

    # Pastas de Startup
    $pastaStartup = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )

    foreach ($pasta in $pastaStartup) {
        if (-not (Test-Path $pasta -ErrorAction SilentlyContinue)) { continue }

        $itens = Get-ChildItem -Path $pasta -ErrorAction SilentlyContinue
        foreach ($item in $itens) {
            $alvo = ""
            if ($item.Extension -eq ".lnk") {
                try {
                    $shell   = New-Object -ComObject WScript.Shell -ErrorAction SilentlyContinue
                    $atalho  = $shell?.CreateShortcut($item.FullName)
                    $alvo    = $atalho?.TargetPath ?? ""
                } catch {}
            } else {
                $alvo = $item.FullName
            }

            $publicador = ""
            if ($alvo -and (Test-Path $alvo -ErrorAction SilentlyContinue)) {
                $vi = (Get-Item $alvo -ErrorAction SilentlyContinue)?.VersionInfo
                if ($vi) { $publicador = $vi.CompanyName ?? "" }
            }

            Adicionar-Item `
                -Categoria       "Startup" `
                -Nome            ($item.BaseName) `
                -Versao          "" `
                -Publicador      $publicador `
                -DataInstalacao  "" `
                -CaminhoInstall  $alvo `
                -Tamanho         "" `
                -Arquitetura     "" `
                -GUID            "" `
                -Descricao       "Atalho na pasta Startup" `
                -FonteDetalhe    $pasta `
                -Status          "Pasta Startup" `
                -Extra1Label     "Atalho" `
                -Extra1Valor     ($item.FullName)

            $count++
        }
    }

    Write-OK "$count itens de inicializacao mapeados"
}

# ═══════════════════════════════════════════════════════════════════
#  EXPORTACAO CSV
# ═══════════════════════════════════════════════════════════════════
function Export-CSV {
    param([string]$Caminho)

    $Script:TodosItens |
        Select-Object Categoria, Nome, Versao, Publicador, DataInstalacao,
                      CaminhoInstall, Tamanho, Arquitetura, GUID, Status,
                      Descricao, FonteDetalhe, Extra1Label, Extra1Valor |
        Export-Csv -Path $Caminho -NoTypeInformation -Encoding UTF8 -ErrorAction SilentlyContinue

    Write-OK "CSV exportado: $Caminho"
}

# ═══════════════════════════════════════════════════════════════════
#  EXPORTACAO JSON
# ═══════════════════════════════════════════════════════════════════
function Export-JSON {
    param([string]$Caminho)

    $Script:TodosItens | ConvertTo-Json -Depth 5 |
        Set-Content -Path $Caminho -Encoding UTF8 -ErrorAction SilentlyContinue

    Write-OK "JSON exportado: $Caminho"
}

# ═══════════════════════════════════════════════════════════════════
#  RELATORIO HTML INTERATIVO
# ═══════════════════════════════════════════════════════════════════
function Export-HTML {
    param([string]$Caminho)

    # Montar linhas da tabela
    $linhasHtml = [System.Text.StringBuilder]::new()

    foreach ($item in $Script:TodosItens) {
        $corCategoria = switch ($item.Categoria) {
            "Registro"    { "#3b82f6" }
            "UWP"         { "#8b5cf6" }
            "Feature"     { "#06b6d4" }
            "Capacidade"  { "#0891b2" }
            "Servico"     { "#f59e0b" }
            "Executavel"  { "#10b981" }
            "Startup"     { "#ef4444" }
            "Chocolatey"  { "#d97706" }
            "Winget"      { "#7c3aed" }
            default       { "#6b7280" }
        }

        $nomeEsc      = [System.Web.HttpUtility]::HtmlEncode($item.Nome)
        $versaoEsc    = [System.Web.HttpUtility]::HtmlEncode($item.Versao)
        $pubEsc       = [System.Web.HttpUtility]::HtmlEncode($item.Publicador)
        $dataEsc      = [System.Web.HttpUtility]::HtmlEncode($item.DataInstalacao)
        $caminhoEsc   = [System.Web.HttpUtility]::HtmlEncode($item.CaminhoInstall)
        $tamEsc       = [System.Web.HttpUtility]::HtmlEncode($item.Tamanho)
        $arqEsc       = [System.Web.HttpUtility]::HtmlEncode($item.Arquitetura)
        $guidEsc      = [System.Web.HttpUtility]::HtmlEncode($item.GUID)
        $statusEsc    = [System.Web.HttpUtility]::HtmlEncode($item.Status)
        $descEsc      = [System.Web.HttpUtility]::HtmlEncode($item.Descricao)

        $null = $linhasHtml.AppendLine(@"
        <tr class="data-row" data-categoria="$($item.Categoria)">
          <td><span class="badge" style="background:$corCategoria">$($item.Categoria)</span></td>
          <td class="nome-col" title="$descEsc">$nomeEsc</td>
          <td>$versaoEsc</td>
          <td>$pubEsc</td>
          <td>$dataEsc</td>
          <td class="caminho-col" title="$caminhoEsc">$caminhoEsc</td>
          <td>$tamEsc</td>
          <td>$arqEsc</td>
          <td class="guid-col" title="$guidEsc">$guidEsc</td>
          <td>$statusEsc</td>
        </tr>
"@)
    }

    # Dados para o grafico de categorias
    $graficoDados = ($Script:Contadores.GetEnumerator() |
        Where-Object { $_.Value -gt 0 } |
        Sort-Object Value -Descending |
        ForEach-Object { "{label:'$($_.Key)',value:$($_.Value)}" }) -join ","

    $totalGeral = $Script:TodosItens.Count

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Mapeamento de Software — $Script:NomePC</title>
<style>
  :root {
    --bg: #0f172a; --bg2: #1e293b; --bg3: #334155;
    --txt: #e2e8f0; --txt2: #94a3b8; --accent: #3b82f6;
    --border: #334155; --green: #10b981; --red: #ef4444;
    --yellow: #f59e0b;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--txt); font-family: 'Segoe UI', system-ui, sans-serif; font-size: 13px; }

  /* HEADER */
  .header { background: linear-gradient(135deg, #1e3a5f 0%, #0f172a 100%);
            padding: 28px 32px; border-bottom: 2px solid var(--accent); }
  .header h1 { font-size: 22px; font-weight: 700; color: #fff; margin-bottom: 6px; }
  .header .meta { color: var(--txt2); font-size: 12px; display: flex; gap: 24px; flex-wrap: wrap; margin-top: 8px; }
  .header .meta span { display: flex; align-items: center; gap: 6px; }

  /* CARDS RESUMO */
  .resumo { display: flex; gap: 12px; padding: 20px 32px; flex-wrap: wrap; }
  .card { background: var(--bg2); border: 1px solid var(--border); border-radius: 10px;
          padding: 14px 20px; min-width: 130px; flex: 1; transition: transform .15s; }
  .card:hover { transform: translateY(-2px); border-color: var(--accent); }
  .card .num { font-size: 26px; font-weight: 800; color: var(--accent); }
  .card .lbl { font-size: 11px; color: var(--txt2); margin-top: 4px; text-transform: uppercase; letter-spacing: .5px; }

  /* GRAFICO BARRAS */
  .grafico-section { padding: 0 32px 20px; }
  .grafico-section h3 { color: var(--txt2); font-size: 11px; text-transform: uppercase;
                        letter-spacing: 1px; margin-bottom: 12px; }
  .barra-wrap { display: flex; flex-direction: column; gap: 6px; }
  .barra-item { display: flex; align-items: center; gap: 10px; }
  .barra-label { width: 110px; font-size: 12px; color: var(--txt2); text-align: right; }
  .barra-track { flex: 1; background: var(--bg3); border-radius: 4px; height: 18px; overflow: hidden; }
  .barra-fill { height: 100%; border-radius: 4px; display: flex; align-items: center;
                padding-left: 8px; font-size: 11px; font-weight: 600; color: #fff;
                transition: width .5s ease; }
  .barra-count { width: 50px; font-size: 12px; font-weight: 700; color: var(--txt); }

  /* CONTROLES */
  .controles { padding: 0 32px 16px; display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
  .search-box { flex: 1; min-width: 220px; position: relative; }
  .search-box input { width: 100%; background: var(--bg2); border: 1px solid var(--border);
                      border-radius: 8px; padding: 9px 14px 9px 36px; color: var(--txt);
                      font-size: 13px; outline: none; transition: border .2s; }
  .search-box input:focus { border-color: var(--accent); }
  .search-box .ico { position: absolute; left: 11px; top: 50%; transform: translateY(-50%);
                     color: var(--txt2); font-size: 14px; }
  .filtro-btns { display: flex; gap: 6px; flex-wrap: wrap; }
  .filtro-btn { background: var(--bg2); border: 1px solid var(--border); border-radius: 6px;
                padding: 7px 12px; cursor: pointer; color: var(--txt2); font-size: 12px;
                transition: all .15s; }
  .filtro-btn:hover, .filtro-btn.ativo { background: var(--accent); color: #fff; border-color: var(--accent); }
  .contador-visivel { color: var(--txt2); font-size: 12px; align-self: center; margin-left: auto; }

  /* TABELA */
  .tabela-wrap { padding: 0 32px 32px; overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; }
  thead tr { background: var(--bg3); }
  th { padding: 10px 12px; text-align: left; font-size: 11px; text-transform: uppercase;
       letter-spacing: .5px; color: var(--txt2); cursor: pointer; user-select: none;
       white-space: nowrap; border-bottom: 2px solid var(--border); }
  th:hover { color: var(--txt); }
  th .sort-ico { margin-left: 4px; opacity: .4; }
  th.sorted .sort-ico { opacity: 1; color: var(--accent); }
  td { padding: 8px 12px; border-bottom: 1px solid var(--border); vertical-align: top;
       max-width: 0; }
  tr:hover td { background: rgba(59,130,246,.07); }
  .nome-col   { max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 500; }
  .caminho-col{ max-width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
                font-size: 11px; color: var(--txt2); font-family: monospace; }
  .guid-col   { max-width: 160px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
                font-size: 11px; color: var(--txt2); font-family: monospace; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 10px;
           font-weight: 700; color: #fff; white-space: nowrap; }
  .sem-resultado { text-align: center; color: var(--txt2); padding: 48px; font-size: 15px; display: none; }

  /* RODAPE */
  .rodape { text-align: center; color: var(--txt2); font-size: 11px; padding: 16px;
            border-top: 1px solid var(--border); margin-top: 8px; }
  .highlight { background: rgba(251,191,36,.35); border-radius: 2px; }
</style>
</head>
<body>

<div class="header">
  <h1>Mapeamento Completo de Software Instalado</h1>
  <div class="meta">
    <span>🖥️ $Script:NomePC</span>
    <span>👤 $Script:Usuario</span>
    <span>🪟 $Script:SistemaOS</span>
    <span>⚙️ $Script:Arquitetura</span>
    <span>📅 $Script:DataHora</span>
    <span>🔒 Admin: $(if ($Script:IsAdmin) { 'Sim' } else { 'Nao' })</span>
  </div>
</div>

<div class="resumo">
  <div class="card"><div class="num" style="color:#e2e8f0">$totalGeral</div><div class="lbl">Total Mapeado</div></div>
  <div class="card"><div class="num" style="color:#3b82f6">$($Script:Contadores.Registro)</div><div class="lbl">Registro</div></div>
  <div class="card"><div class="num" style="color:#8b5cf6">$($Script:Contadores.UWP)</div><div class="lbl">UWP / Store</div></div>
  <div class="card"><div class="num" style="color:#06b6d4">$($Script:Contadores.Feature)</div><div class="lbl">Features</div></div>
  <div class="card"><div class="num" style="color:#0891b2">$($Script:Contadores.Capacidade)</div><div class="lbl">Capacidades</div></div>
  <div class="card"><div class="num" style="color:#f59e0b">$($Script:Contadores.Servico)</div><div class="lbl">Servicos</div></div>
  <div class="card"><div class="num" style="color:#10b981">$($Script:Contadores.Executavel)</div><div class="lbl">Executaveis</div></div>
  <div class="card"><div class="num" style="color:#ef4444">$($Script:Contadores.Startup)</div><div class="lbl">Startup</div></div>
  <div class="card"><div class="num" style="color:#d97706">$($Script:Contadores.Chocolatey)</div><div class="lbl">Chocolatey</div></div>
  <div class="card"><div class="num" style="color:#7c3aed">$($Script:Contadores.Winget)</div><div class="lbl">Winget</div></div>
</div>

<div class="grafico-section">
  <h3>Distribuicao por Categoria</h3>
  <div class="barra-wrap" id="grafico"></div>
</div>

<div class="controles">
  <div class="search-box">
    <span class="ico">🔍</span>
    <input type="text" id="busca" placeholder="Buscar por nome, publicador, versao, caminho..." oninput="filtrar()"/>
  </div>
  <div class="filtro-btns">
    <button class="filtro-btn ativo" onclick="setCategoria('')">Todos</button>
    <button class="filtro-btn" onclick="setCategoria('Registro')">Registro</button>
    <button class="filtro-btn" onclick="setCategoria('UWP')">UWP</button>
    <button class="filtro-btn" onclick="setCategoria('Feature')">Feature</button>
    <button class="filtro-btn" onclick="setCategoria('Capacidade')">Capacidade</button>
    <button class="filtro-btn" onclick="setCategoria('Servico')">Servico</button>
    <button class="filtro-btn" onclick="setCategoria('Executavel')">Executavel</button>
    <button class="filtro-btn" onclick="setCategoria('Startup')">Startup</button>
    <button class="filtro-btn" onclick="setCategoria('Chocolatey')">Choco</button>
    <button class="filtro-btn" onclick="setCategoria('Winget')">Winget</button>
  </div>
  <span class="contador-visivel" id="contadorVis"></span>
</div>

<div class="tabela-wrap">
  <table id="tabela">
    <thead>
      <tr>
        <th onclick="ordenar(0)">Categoria<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(1)">Nome<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(2)">Versao<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(3)">Publicador<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(4)">Instalacao<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(5)">Caminho<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(6)">Tamanho<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(7)">Arq.<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(8)">GUID / ID<span class="sort-ico">↕</span></th>
        <th onclick="ordenar(9)">Status<span class="sort-ico">↕</span></th>
      </tr>
    </thead>
    <tbody id="tbody">
      $($linhasHtml.ToString())
    </tbody>
  </table>
  <div class="sem-resultado" id="semResultado">Nenhum item encontrado para os filtros aplicados.</div>
</div>

<div class="rodape">
  Gerado por Map-InstalledSoftware.ps1 v2.0 — CODEX | Rodrigues e Prado Advocacia &nbsp;|&nbsp; $Script:DataHora
</div>

<script>
  var categoriaAtual = '';
  var colOrdem = -1;
  var ascending = true;

  // ── Grafico de barras ──────────────────────────────────────────
  var dados = [$graficoDados];
  var maxVal = Math.max.apply(null, dados.map(function(d){ return d.value; }));
  var cores = {
    Registro:'#3b82f6', UWP:'#8b5cf6', Feature:'#06b6d4', Capacidade:'#0891b2',
    Servico:'#f59e0b', Executavel:'#10b981', Startup:'#ef4444',
    Chocolatey:'#d97706', Winget:'#7c3aed'
  };
  var gDiv = document.getElementById('grafico');
  dados.forEach(function(d) {
    if (d.value === 0) return;
    var pct = maxVal > 0 ? Math.max((d.value / maxVal * 100), 3) : 3;
    var cor = cores[d.label] || '#6b7280';
    gDiv.innerHTML += '<div class="barra-item">'
      + '<span class="barra-label">' + d.label + '</span>'
      + '<div class="barra-track"><div class="barra-fill" style="width:' + pct + '%;background:' + cor + '">'
      + (pct > 15 ? d.value : '') + '</div></div>'
      + '<span class="barra-count">' + (pct <= 15 ? d.value : '') + '</span>'
      + '</div>';
  });

  // ── Filtrar ────────────────────────────────────────────────────
  function filtrar() {
    var busca = document.getElementById('busca').value.toLowerCase();
    var rows  = document.querySelectorAll('#tbody .data-row');
    var vis   = 0;
    rows.forEach(function(r) {
      var cat  = r.getAttribute('data-categoria');
      var txt  = r.innerText.toLowerCase();
      var show = (categoriaAtual === '' || cat === categoriaAtual) && txt.includes(busca);
      r.style.display = show ? '' : 'none';

      // Highlight
      if (show && busca.length > 1) {
        r.querySelectorAll('td').forEach(function(td) {
          var orig = td.getAttribute('data-orig') || td.textContent;
          td.setAttribute('data-orig', orig);
          var re = new RegExp('(' + busca.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'gi');
          td.innerHTML = orig.replace(re, '<span class="highlight">$1</span>');
        });
      } else if (!busca) {
        r.querySelectorAll('td').forEach(function(td) {
          var orig = td.getAttribute('data-orig');
          if (orig) { td.textContent = orig; td.removeAttribute('data-orig'); }
        });
      }

      if (show) vis++;
    });
    document.getElementById('contadorVis').textContent = vis + ' itens visiveis';
    document.getElementById('semResultado').style.display = vis === 0 ? 'block' : 'none';
  }

  function setCategoria(cat) {
    categoriaAtual = cat;
    document.querySelectorAll('.filtro-btn').forEach(function(b) {
      b.classList.toggle('ativo', b.textContent.trim() === (cat || 'Todos'));
    });
    filtrar();
  }

  // ── Ordenar colunas ────────────────────────────────────────────
  function ordenar(col) {
    var tbody = document.getElementById('tbody');
    var rows  = Array.from(tbody.querySelectorAll('.data-row'));
    if (colOrdem === col) { ascending = !ascending; } else { ascending = true; colOrdem = col; }

    rows.sort(function(a, b) {
      var va = a.cells[col].innerText.toLowerCase();
      var vb = b.cells[col].innerText.toLowerCase();
      return ascending ? va.localeCompare(vb) : vb.localeCompare(va);
    });
    rows.forEach(function(r) { tbody.appendChild(r); });

    document.querySelectorAll('th').forEach(function(th, i) {
      th.classList.toggle('sorted', i === col);
      var ico = th.querySelector('.sort-ico');
      if (ico) ico.textContent = i === col ? (ascending ? ' ↑' : ' ↓') : ' ↕';
    });
  }

  // Inicializar contador
  filtrar();
</script>
</body>
</html>
"@

    $html | Set-Content -Path $Caminho -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-OK "HTML exportado: $Caminho"
}

# ═══════════════════════════════════════════════════════════════════
#  RESUMO FINAL NO CONSOLE
# ═══════════════════════════════════════════════════════════════════
function Show-Resumo {
    $largura = 66
    Write-Host ""
    Write-Host ("  " + "═" * $largura) -ForegroundColor Cyan
    Write-Host "  RESUMO DO MAPEAMENTO" -ForegroundColor Cyan
    Write-Host ("  " + "═" * $largura) -ForegroundColor Cyan

    $categorias = @(
        @{ Nome = "Registro (HKLM 64 + HKLM 32 + HKCU)"; Chave = "Registro";   Cor = "Blue" },
        @{ Nome = "Apps UWP / Microsoft Store";            Chave = "UWP";        Cor = "Magenta" },
        @{ Nome = "Features Opcionais do Windows";         Chave = "Feature";    Cor = "Cyan" },
        @{ Nome = "Capacidades (FOD)";                     Chave = "Capacidade"; Cor = "DarkCyan" },
        @{ Nome = "Servicos do Windows";                   Chave = "Servico";    Cor = "Yellow" },
        @{ Nome = "Executaveis (Program Files)";           Chave = "Executavel"; Cor = "Green" },
        @{ Nome = "Itens de Inicializacao (Startup)";      Chave = "Startup";    Cor = "Red" },
        @{ Nome = "Pacotes Chocolatey";                    Chave = "Chocolatey"; Cor = "DarkYellow" },
        @{ Nome = "Pacotes Winget";                        Chave = "Winget";     Cor = "DarkMagenta" }
    )

    foreach ($c in $categorias) {
        $n = $Script:Contadores[$c.Chave]
        Write-Host "  " -NoNewline
        Write-Host (" {0,-45}" -f $c.Nome) -ForegroundColor $c.Cor -NoNewline
        Write-Host ("{0,6} itens" -f $n) -ForegroundColor White
    }

    Write-Host ("  " + "─" * $largura) -ForegroundColor DarkGray
    Write-Host ("  {0,-45}{1,6} itens" -f "TOTAL GERAL", $Script:TodosItens.Count) -ForegroundColor White
    Write-Host ("  " + "═" * $largura) -ForegroundColor Cyan
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════
#  MAIN — EXECUCAO PRINCIPAL
# ═══════════════════════════════════════════════════════════════════

Write-Header

# Garantir pasta de saida
if (-not (Test-Path $OutputDir -ErrorAction SilentlyContinue)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$baseNome   = "MapSoftware_$($Script:NomePC)_$Script:Timestamp"
$pathHTML   = Join-Path $OutputDir "$baseNome.html"
$pathCSV    = Join-Path $OutputDir "$baseNome.csv"
$pathJSON   = Join-Path $OutputDir "$baseNome.json"

Write-Host "  Arquivos de saida:" -ForegroundColor DarkGray
Write-Host "    HTML : $pathHTML" -ForegroundColor DarkGray
Write-Host "    CSV  : $pathCSV"  -ForegroundColor DarkGray
Write-Host "    JSON : $pathJSON" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Iniciando varredura..." -ForegroundColor White
Write-Host ""

# ── Executar todas as varreduras ──────────────────────────────────
Scan-Registro

Scan-UWP

if ($ScanFeatures) {
    Scan-Features
    Scan-Capacidades
} else {
    Write-Aviso "Features/Capacidades ignorados (ScanFeatures=false)"
}

if ($ScanServicos) {
    Scan-Servicos
} else {
    Write-Aviso "Servicos ignorados (ScanServicos=false)"
}

if ($ScanProgramFiles) {
    Scan-Executaveis
} else {
    Write-Aviso "Varredura de executaveis ignorada (ScanProgramFiles=false)"
}

Scan-Chocolatey
Scan-Winget

if ($ScanStartup) {
    Scan-Startup
} else {
    Write-Aviso "Startup ignorado (ScanStartup=false)"
}

# ── Exportar ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Exportando relatorios..." -ForegroundColor White
Write-Host ""

Export-HTML -Caminho $pathHTML
Export-CSV  -Caminho $pathCSV
Export-JSON -Caminho $pathJSON

# ── Resumo ────────────────────────────────────────────────────────
Show-Resumo

Write-Host "  Relatorios salvos em: $OutputDir" -ForegroundColor Green
Write-Host ""

if ($AbrirRelatorio -and (Test-Path $pathHTML)) {
    Write-Host "  Abrindo relatorio HTML no navegador..." -ForegroundColor Cyan
    Start-Process $pathHTML
}

Write-Host "  Concluido em $($Script:DataHora)" -ForegroundColor DarkGray
Write-Host ""
