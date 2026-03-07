# =============================================================================
# run_sim.ps1
# Script PowerShell para compilar e simular o cpu_top com GHDL
#
# Requisitos:
#   - GHDL instalado e acessível no PATH (https://github.com/ghdl/ghdl)
#   - Executar a partir da raiz do projeto:
#       cd "Arquitetura de CPU"
#       .\sim\run_sim.ps1
# =============================================================================

param(
    [switch]$wave,      # Gerar arquivo VCD para GTKWave
    [switch]$clean      # Limpar arquivos gerados antes de compilar
)

$ErrorActionPreference = "Stop"

$ROOT  = Split-Path -Parent $PSScriptRoot
$SIM   = "$ROOT\sim"
$RTL   = "$ROOT\rtl"
$WORK  = "$SIM\work"

# GHDL não suporta caracteres não-ASCII nos caminhos internos (work-obj08.cf).
# Solucao: criar uma junction ASCII para o projeto e compilar a partir dela.
# Para usar: crie uma junction com:
#   New-Item -ItemType Junction -Path C:\ghdl -Target $ROOT
# O script detecta automaticamente se C:\ghdl existe e aponta para ca.
if (Test-Path "C:\ghdl") {
    $ROOT_ASCII = "C:\ghdl"
    $SIM   = "$ROOT_ASCII\sim"
    $RTL   = "$ROOT_ASCII\rtl"
    $WORK  = "$SIM\work"
    Push-Location $ROOT_ASCII
} else {
    Write-Host "[AVISO] Junction C:\ghdl nao encontrada. GHDL pode falhar com caminho especial." -ForegroundColor Yellow
    Write-Host "[AVISO] Execute: New-Item -ItemType Junction -Path C:\ghdl -Target '$ROOT'" -ForegroundColor Yellow
    Push-Location $ROOT
}

if ($clean -or (-not (Test-Path $WORK))) {
    if ($clean) { Write-Host "[CLEAN] Removendo $WORK ..." -ForegroundColor Yellow }
    if (Test-Path $WORK) { Remove-Item -Recurse -Force $WORK }
    New-Item -ItemType Directory -Path $WORK | Out-Null
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GHDL – Compilando RTL" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Lista de arquivos em ordem de dependência
$files = @(
    # Pacotes primeiro
    "$RTL\pkg\axi4_pkg.vhd",
    "$RTL\pkg\cpu_pkg.vhd",
    # Sub-módulos folha
    "$RTL\mmu\mmu.vhd",
    "$RTL\fetch\pc_reg.vhd",
    "$RTL\fetch\branch_predictor.vhd",
    "$RTL\fetch\branch_handler.vhd",
    "$RTL\fetch\fetch_stage.vhd",
    "$RTL\decode\instruction_decoder.vhd",
    "$RTL\decode\immediate_generator.vhd",
    "$RTL\decode\register_file.vhd",
    "$RTL\decode\decode_stage.vhd",
    "$RTL\execute\alu.vhd",
    "$RTL\execute\branch_comparator.vhd",
    "$RTL\execute\forwarding_unit.vhd",
    "$RTL\execute\execute_stage.vhd",
    "$RTL\memory\load_store_unit.vhd",
    "$RTL\memory\memory_stage.vhd",
    "$RTL\writeback\writeback_stage.vhd",
    "$RTL\csr\csr_reg.vhd",
    "$RTL\cache\icache.vhd",
    "$RTL\cache\dcache.vhd",
    # Topo
    "$RTL\cpu_top.vhd",
    # Testbench
    "$SIM\cpu_top_tb.vhd"
)

foreach ($f in $files) {
    Write-Host "[ANA] $f"
    ghdl -a --std=08 -frelaxed --workdir=$WORK $f
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERRO] Falha ao analisar $f" -ForegroundColor Red
        Pop-Location; exit 1
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GHDL – Elaborando cpu_top_tb" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

ghdl -e --std=08 -frelaxed --workdir=$WORK cpu_top_tb
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERRO] Falha na elaboração." -ForegroundColor Red
    Pop-Location; exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " GHDL – Simulando" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$runArgs = @(
    "-r", "--std=08", "-frelaxed", "--workdir=$WORK", "cpu_top_tb",
    "--stop-time=10us"
)

if ($wave) {
    $vcdFile = "$SIM\cpu_top_tb.vcd"
    $runArgs += "--vcd=$vcdFile"
    Write-Host "[INFO] Gerando VCD em $vcdFile" -ForegroundColor Yellow
}

ghdl @runArgs
$exitCode = $LASTEXITCODE

Pop-Location

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " Simulação concluída com sucesso!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    if ($wave) {
        Write-Host " VCD: $SIM\cpu_top_tb.vcd" -ForegroundColor Yellow
        Write-Host " Abrir com: gtkwave $SIM\cpu_top_tb.vcd" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " Simulação FALHOU (exit $exitCode)" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    exit $exitCode
}
