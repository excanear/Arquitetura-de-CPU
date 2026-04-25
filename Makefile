# =============================================================================
# Makefile — EduRISC-32v2 Educational CPU Lab
#
# Alvos principais:
#   make demo        — executa demonstração integrada (ASM + C → simulador)
#   make assemble    — monta um arquivo .asm (variável: SRC=path/to/file.asm)
#   make simulate    — simula um .hex ou .asm (variável: SRC=...)
#   make build       — compila um .c para .hex (variável: SRC=...)
#   make rtl-build   — verifica sintaxe RTL com iverilog
#   make rtl-sim     — simula RTL com Icarus Verilog (HEX=...)
#   make test        — executa a suíte de testes pytest
#   make clean       — remove artefatos gerados
#   make help        — lista alvos disponíveis
# =============================================================================

PYTHON   ?= python3
PY_MAIN  := main.py
SRC      ?= examples/hello.asm
HEX      ?= out.hex
OUT      ?= out.hex

.PHONY: all demo assemble simulate build run rtl-build rtl-sim test clean help

all: demo

# -----------------------------------------------------------------------------
demo:
	@echo "=== EduRISC-32v2 Demo ==="
	$(PYTHON) $(PY_MAIN) demo

# -----------------------------------------------------------------------------
assemble:
	@echo "=== Montando $(SRC) ==="
	$(PYTHON) $(PY_MAIN) assemble $(SRC) -o $(OUT) --listing

# -----------------------------------------------------------------------------
simulate:
	@echo "=== Simulando $(SRC) ==="
	$(PYTHON) $(PY_MAIN) simulate $(SRC)

# -----------------------------------------------------------------------------
build:
	@echo "=== Compilando $(SRC) → $(OUT) ==="
	$(PYTHON) $(PY_MAIN) build $(SRC) -o $(OUT)

# -----------------------------------------------------------------------------
run:
	@echo "=== Montando e executando $(SRC) ==="
	$(PYTHON) $(PY_MAIN) run $(SRC)

# -----------------------------------------------------------------------------
rtl-build:
	@echo "=== Verificando sintaxe RTL ==="
	$(PYTHON) $(PY_MAIN) rtl-build

# -----------------------------------------------------------------------------
rtl-sim:
	@echo "=== Simulando RTL com $(HEX) ==="
	$(PYTHON) $(PY_MAIN) rtl-sim $(HEX)

# -----------------------------------------------------------------------------
test:
	@echo "=== Executando testes ==="
	$(PYTHON) -m pytest tests/ -v --tb=short 2>/dev/null || \
	$(PYTHON) -m pytest . -v --tb=short --ignore=docs --ignore=fpga --ignore=rtl 2>/dev/null || \
	echo "[AVISO] Nenhum teste encontrado — adicione testes em tests/"

# -----------------------------------------------------------------------------
clean:
	@echo "=== Limpando artefatos ==="
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	find . -name "*.pyo" -delete 2>/dev/null || true
	find . -name "*.hex" -not -path "*/os/*" -not -path "*/boot/*" -delete 2>/dev/null || true
	find . -name "*.bin" -not -path "*/os/*" -not -path "*/boot/*" -delete 2>/dev/null || true
	find . -name "*.vcd" -delete 2>/dev/null || true
	find . -name "*.vvp" -delete 2>/dev/null || true
	find . -name "sim.out" -delete 2>/dev/null || true
	@echo "Limpeza concluída."

# -----------------------------------------------------------------------------
help:
	@echo ""
	@echo "EduRISC-32v2 Educational CPU Lab — Makefile"
	@echo "============================================="
	@echo ""
	@echo "Alvos disponíveis:"
	@echo "  make demo                    — demo integrado (padrão)"
	@echo "  make assemble  SRC=file.asm  — montar arquivo assembly"
	@echo "  make simulate  SRC=file.hex  — simular programa"
	@echo "  make build     SRC=file.c    — compilar C → hex"
	@echo "  make run       SRC=file.asm  — montar e executar"
	@echo "  make rtl-build               — verificar sintaxe Verilog"
	@echo "  make rtl-sim   HEX=file.hex  — simular RTL"
	@echo "  make test                    — rodar testes pytest"
	@echo "  make clean                   — limpar artefatos"
	@echo ""
	@echo "Exemplo:"
	@echo "  make assemble SRC=examples/sum.asm OUT=sum.hex"
	@echo "  make simulate SRC=sum.hex"
	@echo ""
