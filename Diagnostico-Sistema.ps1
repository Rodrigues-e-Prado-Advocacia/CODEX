#Requires -Version 5.1
<#
.SYNOPSIS
    Script de Diagnostico e Analise do Sistema
.DESCRIPTION
    Coleta informacoes detalhadas sobre hardware, desempenho, disco,
    memoria, rede, processos e eventos do sistema para auxiliar na
    otimizacao e resolucao de problemas.
.NOTES
    Execute como Administrador para resultados completos.
    Autor: Claude Code
    Versao: 1.0
#>

[CmdletBinding()]
param(
    [string]$RelatorioPath = "$env:USERPROFILE\Desktop\Diagnostico_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

# ───────────────────────────────────────────────────────────
# Configuracao de cores e funcoes auxiliares
# ───────────────────────────────────────────────────────────
$Separador = "=" * 70

function Write-Secao {
    param([string]$Titulo)
    Write-Host "`n$Separador" -ForegroundColor Cyan
    Write-Host "  $Titulo" -ForegroundColor Yellow
    Write-Host "$Separador" -ForegroundColor Cyan
}

function Write-Ok   { param([string]$msg) Write-Host "  [OK]  $msg" -ForegroundColor Green }
function Write-Aviso { param([string]$msg) Write-Host "  [!]   $msg" -ForegroundColor Yellow }
function Write-Critico { param([string]$msg) Write-Host "  [X]   $msg" -ForegroundColor Red }
function Write-Info { param([string]$msg) Write-Host "  [-]   $msg" -ForegroundColor White }

$linhasRelatorio = [System.Collections.Generic.List[string]]::new()
function Registrar { param([string]$linha) $linhasRelatorio.Add($linha) }

# ───────────────────────────────────────────────────────────
# CABECALHO
# ───────────────────────────────────────────────────────────
$dataInicio = Get-Date
Write-Host "`n$Separador" -ForegroundColor Magenta
Write-Host "   DIAGNOSTICO DO SISTEMA - $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Magenta
Write-Host "$Separador`n" -ForegroundColor Magenta
Registrar "DIAGNOSTICO DO SISTEMA - $($dataInicio.ToString('dd/MM/yyyy HH:mm:ss'))"
Registrar $Separador

# ───────────────────────────────────────────────────────────
# 1. INFORMACOES DO SISTEMA OPERACIONAL
# ───────────────────────────────────────────────────────────
Write-Secao "1. SISTEMA OPERACIONAL"
Registrar "`n[1. SISTEMA OPERACIONAL]"

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

    Write-Info "Nome do Computador : $($cs.Name)"
    Write-Info "Sistema Operacional: $($os.Caption)"
    Write-Info "Versao / Build     : $($os.Version) (Build $($os.BuildNumber))"
    Write-Info "Arquitetura        : $($os.OSArchitecture)"
    Write-Info "Ultimo Boot        : $($os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm:ss'))"
    Write-Info "Uptime             : $uptimeStr"
    Write-Info "Dominio / Grupo    : $($cs.Domain)"
    Write-Info "Fabricante         : $($cs.Manufacturer) $($cs.Model)"

    Registrar "  Computador   : $($cs.Name)"
    Registrar "  OS           : $($os.Caption) - $($os.Version)"
    Registrar "  Ultimo Boot  : $($os.LastBootUpTime)"
    Registrar "  Uptime       : $uptimeStr"

    if ($uptime.Days -ge 14) {
        Write-Aviso "O sistema esta ligado ha $($uptime.Days) dias. Considere reiniciar."
    } else {
        Write-Ok "Uptime dentro do normal."
    }
} catch {
    Write-Critico "Erro ao obter informacoes do SO: $_"
}

# ───────────────────────────────────────────────────────────
# 2. PROCESSADOR (CPU)
# ───────────────────────────────────────────────────────────
Write-Secao "2. PROCESSADOR (CPU)"
Registrar "`n[2. PROCESSADOR]"

try {
    $cpus = Get-CimInstance Win32_Processor
    foreach ($cpu in $cpus) {
        Write-Info "Modelo      : $($cpu.Name.Trim())"
        Write-Info "Nucleos     : $($cpu.NumberOfCores) fisicos / $($cpu.NumberOfLogicalProcessors) logicos"
        Write-Info "Velocidade  : $($cpu.MaxClockSpeed) MHz"
        Write-Info "Arquitetura : $($cpu.AddressWidth)-bit"
        Registrar "  CPU: $($cpu.Name.Trim()) | Nucleos: $($cpu.NumberOfCores) | $($cpu.MaxClockSpeed) MHz"
    }

    # Uso atual da CPU (media de 2 amostras)
    Write-Host ""
    Write-Info "Coletando uso da CPU (aguarde 2 segundos)..."
    $cargaCPU1 = (Get-CimInstance Win32_Processor).LoadPercentage
    Start-Sleep -Seconds 2
    $cargaCPU2 = (Get-CimInstance Win32_Processor).LoadPercentage
    $cargaMedia = [math]::Round(($cargaCPU1 + $cargaCPU2) / 2, 1)

    $mensagemCPU = "Uso atual da CPU: $cargaMedia%"
    Registrar "  $mensagemCPU"
    if ($cargaMedia -gt 85) {
        Write-Critico "$mensagemCPU - USO CRITICO!"
    } elseif ($cargaMedia -gt 60) {
        Write-Aviso "$mensagemCPU - Uso elevado"
    } else {
        Write-Ok "$mensagemCPU"
    }
} catch {
    Write-Critico "Erro ao obter informacoes da CPU: $_"
}

# ───────────────────────────────────────────────────────────
# 3. MEMORIA RAM
# ───────────────────────────────────────────────────────────
Write-Secao "3. MEMORIA RAM"
Registrar "`n[3. MEMORIA RAM]"

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $livreGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usadaGB  = [math]::Round($totalGB - $livreGB, 2)
    $percentual = [math]::Round(($usadaGB / $totalGB) * 100, 1)

    Write-Info "Total    : $totalGB GB"
    Write-Info "Em uso   : $usadaGB GB ($percentual%)"
    Write-Info "Livre    : $livreGB GB"
    Registrar "  RAM Total: $totalGB GB | Usada: $usadaGB GB ($percentual%) | Livre: $livreGB GB"

    $paginacao = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    if ($paginacao) {
        $pgTotal = [math]::Round($paginacao.AllocatedBaseSize / 1024, 2)
        $pgUso   = [math]::Round($paginacao.CurrentUsage / 1024, 2)
        Write-Info "Paginacao: $pgUso GB de $pgTotal GB"
        Registrar "  Paginacao: $pgUso GB / $pgTotal GB"
    }

    if ($percentual -gt 90) {
        Write-Critico "Memoria critica! Apenas $livreGB GB livres."
    } elseif ($percentual -gt 75) {
        Write-Aviso "Uso de memoria elevado: $percentual%"
    } else {
        Write-Ok "Uso de memoria normal: $percentual%"
    }

    # Slots de memoria fisica
    $slots = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    if ($slots) {
        Write-Host ""
        Write-Info "Modulos de RAM instalados:"
        foreach ($slot in $slots) {
            $slotGB = [math]::Round($slot.Capacity / 1GB, 0)
            Write-Info "  -> $($slot.BankLabel) | $slotGB GB | $($slot.Speed) MHz | $($slot.MemoryType)"
        }
    }
} catch {
    Write-Critico "Erro ao obter informacoes de memoria: $_"
}

# ───────────────────────────────────────────────────────────
# 4. DISCO / ARMAZENAMENTO
# ───────────────────────────────────────────────────────────
Write-Secao "4. DISCO / ARMAZENAMENTO"
Registrar "`n[4. DISCO / ARMAZENAMENTO]"

try {
    $discos = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }
    foreach ($disco in $discos) {
        $totalGB = [math]::Round(($disco.Used + $disco.Free) / 1GB, 2)
        $usadoGB = [math]::Round($disco.Used / 1GB, 2)
        $livreGB = [math]::Round($disco.Free / 1GB, 2)
        if ($totalGB -gt 0) {
            $pct = [math]::Round(($usadoGB / $totalGB) * 100, 1)
            $msg = "Drive $($disco.Name): $usadoGB GB usados de $totalGB GB ($pct% cheio) | Livre: $livreGB GB"
            Registrar "  $msg"
            if ($pct -gt 90) {
                Write-Critico $msg
            } elseif ($pct -gt 75) {
                Write-Aviso $msg
            } else {
                Write-Ok $msg
            }
        }
    }

    # Informacoes dos discos fisicos
    $hds = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
    if ($hds) {
        Write-Host ""
        Write-Info "Discos Fisicos:"
        foreach ($hd in $hds) {
            $hdGB = [math]::Round($hd.Size / 1GB, 0)
            $tipo = if ($hd.MediaType -like "*SSD*" -or $hd.Model -like "*SSD*" -or $hd.Model -like "*NVMe*") { "SSD/NVMe" } else { "HDD" }
            Write-Info "  -> $($hd.Model) | $hdGB GB | $tipo | Partições: $($hd.Partitions)"
            Registrar "  HD Fisico: $($hd.Model) | $hdGB GB | $tipo"
        }
    }
} catch {
    Write-Critico "Erro ao obter informacoes de disco: $_"
}

# ───────────────────────────────────────────────────────────
# 5. PLACA DE REDE / CONECTIVIDADE
# ───────────────────────────────────────────────────────────
Write-Secao "5. REDE E CONECTIVIDADE"
Registrar "`n[5. REDE]"

try {
    $adaptadores = Get-CimInstance Win32_NetworkAdapterConfiguration |
        Where-Object { $_.IPEnabled -eq $true }

    foreach ($nic in $adaptadores) {
        Write-Info "Adaptador  : $($nic.Description)"
        Write-Info "IP         : $($nic.IPAddress -join ', ')"
        Write-Info "Gateway    : $($nic.DefaultIPGateway -join ', ')"
        Write-Info "DNS        : $($nic.DNSServerSearchOrder -join ', ')"
        Write-Info "MAC        : $($nic.MACAddress)"
        Write-Host ""
        Registrar "  NIC: $($nic.Description) | IP: $($nic.IPAddress -join ',') | MAC: $($nic.MACAddress)"
    }

    # Teste de conectividade
    Write-Info "Testando conectividade com a Internet..."
    $pingGoogle = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue
    if ($pingGoogle) {
        $latencia = (Test-Connection -ComputerName "8.8.8.8" -Count 4 |
            Measure-Object -Property ResponseTime -Average).Average
        $latencia = [math]::Round($latencia, 0)
        $msgPing = "Internet OK - Latencia media: $latencia ms"
        Registrar "  $msgPing"
        if ($latencia -gt 100) {
            Write-Aviso $msgPing
        } else {
            Write-Ok $msgPing
        }
    } else {
        Write-Critico "Sem conectividade com a Internet (8.8.8.8 inacessivel)"
        Registrar "  FALHA: Sem conectividade com a Internet"
    }
} catch {
    Write-Critico "Erro ao obter informacoes de rede: $_"
}

# ───────────────────────────────────────────────────────────
# 6. TOP 10 PROCESSOS (CPU e Memoria)
# ───────────────────────────────────────────────────────────
Write-Secao "6. TOP 10 PROCESSOS POR CONSUMO"
Registrar "`n[6. TOP PROCESSOS]"

try {
    Write-Info "--- Top 10 por Memoria ---"
    Registrar "  Top 10 Processos por Memoria:"
    $topMem = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10
    foreach ($p in $topMem) {
        $memMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        $linha = "  $($p.Name.PadRight(28)) $memMB MB"
        Write-Host $linha
        Registrar $linha
    }

    Write-Host ""
    Write-Info "--- Top 10 por CPU (snapshot) ---"
    Registrar "  Top 10 Processos por CPU:"
    $topCPU = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10
    foreach ($p in $topCPU) {
        $cpuSec = [math]::Round($p.CPU, 1)
        $linha = "  $($p.Name.PadRight(28)) $cpuSec s CPU acumulado"
        Write-Host $linha
        Registrar $linha
    }
} catch {
    Write-Critico "Erro ao listar processos: $_"
}

# ───────────────────────────────────────────────────────────
# 7. SERVICOS COM PROBLEMAS
# ───────────────────────────────────────────────────────────
Write-Secao "7. SERVICOS DO SISTEMA"
Registrar "`n[7. SERVICOS]"

try {
    $servicosParados = Get-Service |
        Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } |
        Select-Object Name, DisplayName, Status

    if ($servicosParados) {
        Write-Aviso "Servicos automaticos que NAO estao em execucao:"
        Registrar "  Servicos automaticos parados:"
        foreach ($svc in $servicosParados) {
            $linha = "  $($svc.Name.PadRight(30)) [$($svc.Status)]"
            Write-Host $linha -ForegroundColor Yellow
            Registrar $linha
        }
    } else {
        Write-Ok "Todos os servicos automaticos estao em execucao."
        Registrar "  Todos os servicos automaticos em execucao."
    }
} catch {
    Write-Critico "Erro ao verificar servicos: $_"
}

# ───────────────────────────────────────────────────────────
# 8. PROGRAMAS NA INICIALIZACAO
# ───────────────────────────────────────────────────────────
Write-Secao "8. PROGRAMAS NA INICIALIZACAO (STARTUP)"
Registrar "`n[8. STARTUP]"

try {
    $chaves = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    )
    $startups = @()
    foreach ($chave in $chaves) {
        if (Test-Path $chave) {
            $itens = Get-ItemProperty -Path $chave -ErrorAction SilentlyContinue
            $itens.PSObject.Properties |
                Where-Object { $_.Name -notlike "PS*" } |
                ForEach-Object { $startups += $_.Name }
        }
    }

    Write-Info "Entradas no Registro:"
    if ($startups.Count -gt 0) {
        $startups | ForEach-Object { Write-Info "  -> $_"; Registrar "  Startup: $_" }
    } else {
        Write-Info "  Nenhuma entrada encontrada no registro."
    }

    # Via WMI (mais completo)
    $wmiStartup = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
    if ($wmiStartup) {
        Write-Host ""
        Write-Info "Total de itens na inicializacao (WMI): $($wmiStartup.Count)"
        if ($wmiStartup.Count -gt 20) {
            Write-Aviso "Muitos itens na inicializacao ($($wmiStartup.Count)). Isso pode atrasar o boot."
        } else {
            Write-Ok "Quantidade de itens na inicializacao aceitavel: $($wmiStartup.Count)"
        }
        Registrar "  Startup WMI: $($wmiStartup.Count) itens"
    }
} catch {
    Write-Critico "Erro ao verificar startup: $_"
}

# ───────────────────────────────────────────────────────────
# 9. EVENTOS CRITICOS RECENTES (Ultimas 24h)
# ───────────────────────────────────────────────────────────
Write-Secao "9. EVENTOS CRITICOS (ultimas 24 horas)"
Registrar "`n[9. EVENTOS CRITICOS]"

try {
    $desde = (Get-Date).AddHours(-24)
    $logs = @("System", "Application")
    foreach ($log in $logs) {
        $eventos = Get-EventLog -LogName $log -EntryType Error, Warning -After $desde `
            -ErrorAction SilentlyContinue | Select-Object -First 5

        Write-Info "Log: $log"
        Registrar "  Log $log:"
        if ($eventos) {
            foreach ($ev in $eventos) {
                $tipo = if ($ev.EntryType -eq "Error") { "ERRO" } else { "AVISO" }
                $linha = "    [$tipo] $($ev.TimeGenerated.ToString('dd/MM HH:mm')) | $($ev.Source) | $($ev.Message -replace '\s+', ' ' | Select-Object -First 1)"
                if ($ev.EntryType -eq "Error") {
                    Write-Host $linha -ForegroundColor Red
                } else {
                    Write-Host $linha -ForegroundColor Yellow
                }
                Registrar $linha
            }
        } else {
            Write-Ok "Sem erros/avisos nas ultimas 24h no log $log."
            Registrar "  Sem eventos criticos."
        }
        Write-Host ""
    }
} catch {
    Write-Aviso "Erro ao ler logs de eventos (pode exigir privilegios de admin): $_"
    Registrar "  AVISO: Erro ao ler logs (privilégios insuficientes)"
}

# ───────────────────────────────────────────────────────────
# 10. TEMPERATURA (via OpenHardwareMonitor, se disponivel)
# ───────────────────────────────────────────────────────────
Write-Secao "10. TEMPERATURA (WMI)"
Registrar "`n[10. TEMPERATURA]"

try {
    $temps = Get-CimInstance -Namespace "root/WMI" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue
    if ($temps) {
        foreach ($t in $temps) {
            $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
            $msg = "Zona Termica [$($t.InstanceName)]: $celsius C"
            Registrar "  $msg"
            if ($celsius -gt 90) {
                Write-Critico $msg
            } elseif ($celsius -gt 75) {
                Write-Aviso $msg
            } else {
                Write-Ok $msg
            }
        }
    } else {
        Write-Info "Dados de temperatura nao disponiveis via WMI neste sistema."
        Write-Info "Instale o HWMonitor ou OpenHardwareMonitor para leituras detalhadas."
        Registrar "  Temperatura nao disponivel via WMI."
    }
} catch {
    Write-Info "Temperatura nao disponivel neste hardware/sistema."
}

# ───────────────────────────────────────────────────────────
# 11. BATERIA (Notebooks)
# ───────────────────────────────────────────────────────────
Write-Secao "11. BATERIA"
Registrar "`n[11. BATERIA]"

try {
    $bateria = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    if ($bateria) {
        foreach ($b in $bateria) {
            $carga = $b.EstimatedChargeRemaining
            $status = switch ($b.BatteryStatus) {
                1 { "Descarregando" }
                2 { "Conectada na tomada" }
                3 { "Carregamento completo" }
                6 { "Carregando" }
                default { "Status $($b.BatteryStatus)" }
            }
            $msg = "Bateria: $carga% | Status: $status"
            Registrar "  $msg"
            if ($carga -lt 20 -and $b.BatteryStatus -eq 1) {
                Write-Critico "$msg - BATERIA BAIXA!"
            } elseif ($carga -lt 40 -and $b.BatteryStatus -eq 1) {
                Write-Aviso $msg
            } else {
                Write-Ok $msg
            }
        }
    } else {
        Write-Info "Nenhuma bateria detectada (Desktop ou bateria nao reportada)."
        Registrar "  Sem bateria detectada."
    }
} catch {
    Write-Info "Informacoes de bateria nao disponiveis."
}

# ───────────────────────────────────────────────────────────
# 12. WINDOWS UPDATE
# ───────────────────────────────────────────────────────────
Write-Secao "12. WINDOWS UPDATE"
Registrar "`n[12. WINDOWS UPDATE]"

try {
    $updateSvc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    if ($updateSvc) {
        $statusWU = $updateSvc.Status
        Write-Info "Servico Windows Update: $statusWU"
        Registrar "  Windows Update servico: $statusWU"
    }

    # Ultima vez que updates foram instalados (registro)
    $regWU = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install" -ErrorAction SilentlyContinue
    if ($regWU -and $regWU.LastSuccessTime) {
        $ultimoUpdate = [datetime]::Parse($regWU.LastSuccessTime)
        $diasSemUpdate = ((Get-Date) - $ultimoUpdate).Days
        $msg = "Ultimo update instalado: $($ultimoUpdate.ToString('dd/MM/yyyy')) ($diasSemUpdate dias atras)"
        Registrar "  $msg"
        if ($diasSemUpdate -gt 60) {
            Write-Critico $msg
        } elseif ($diasSemUpdate -gt 30) {
            Write-Aviso $msg
        } else {
            Write-Ok $msg
        }
    } else {
        Write-Info "Nao foi possivel obter data do ultimo Windows Update."
        Registrar "  Data do ultimo update nao disponivel."
    }
} catch {
    Write-Info "Verificacao de Windows Update nao disponivel."
}

# ───────────────────────────────────────────────────────────
# 13. RESUMO E RECOMENDACOES
# ───────────────────────────────────────────────────────────
Write-Secao "13. RESUMO DAS RECOMENDACOES"
Registrar "`n[13. RECOMENDACOES]"

$recomendacoes = @()

# CPU
if ($cargaMedia -gt 60) {
    $recomendacoes += "- CPU com uso elevado ($cargaMedia%). Verifique processos no Task Manager."
}

# RAM
if ($percentual -gt 75) {
    $recomendacoes += "- Memoria RAM com uso alto ($percentual%). Feche programas desnecessarios ou considere upgrade."
}

# Startup
if ($wmiStartup -and $wmiStartup.Count -gt 20) {
    $recomendacoes += "- Muitos itens na inicializacao ($($wmiStartup.Count)). Desative itens desnecessarios no 'Gerenciador de Tarefas > Inicializar'."
}

# Uptime
if ($uptime.Days -ge 14) {
    $recomendacoes += "- Sistema ligado ha $($uptime.Days) dias. Reiniciar pode liberar recursos e aplicar updates pendentes."
}

if ($recomendacoes.Count -gt 0) {
    foreach ($rec in $recomendacoes) {
        Write-Host "  $rec" -ForegroundColor Yellow
        Registrar "  $rec"
    }
} else {
    Write-Ok "Sistema aparentemente saudavel! Nenhuma recomendacao critica."
    Registrar "  Sistema saudavel - sem recomendacoes criticas."
}

# ───────────────────────────────────────────────────────────
# SALVAR RELATORIO
# ───────────────────────────────────────────────────────────
$duracao = [math]::Round(((Get-Date) - $dataInicio).TotalSeconds, 1)
Registrar "`n$Separador"
Registrar "Diagnostico concluido em $duracao segundos."
Registrar "Gerado por: $($env:USERNAME) em $($env:COMPUTERNAME)"

try {
    $linhasRelatorio | Out-File -FilePath $RelatorioPath -Encoding UTF8
    Write-Host "`n$Separador" -ForegroundColor Magenta
    Write-Host "  Diagnostico concluido em $duracao segundos." -ForegroundColor Green
    Write-Host "  Relatorio salvo em: $RelatorioPath" -ForegroundColor Cyan
    Write-Host "$Separador`n" -ForegroundColor Magenta
} catch {
    Write-Aviso "Nao foi possivel salvar o relatorio: $_"
}
