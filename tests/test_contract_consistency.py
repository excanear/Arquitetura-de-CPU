"""
tests/test_contract_consistency.py — Consistência de contrato código↔docs

Garante que as tabelas de syscalls documentadas reflitam exatamente os
números definidos em os/os_defs.h.
"""

from pathlib import Path
import re


_ROOT = Path(__file__).resolve().parents[1]


def _extract_define_ints(text: str, names: list[str]) -> dict[str, int]:
    found: dict[str, int] = {}
    for name in names:
        m = re.search(rf"^#define\s+{name}\s+([^\s/]+)", text, flags=re.MULTILINE)
        if not m:
            continue
        raw = m.group(1).rstrip("uUlL")
        found[name] = int(raw, 0)
    return found


def _extract_py_int_consts(text: str, names: list[str]) -> dict[str, int]:
    found: dict[str, int] = {}
    for name in names:
        m = re.search(rf"^{name}\s*=\s*(\d+)\b", text, flags=re.MULTILINE)
        if not m:
            continue
        found[name] = int(m.group(1), 10)
    return found


def _extract_syscalls_from_header(text: str) -> dict[int, str]:
    entries = re.findall(r"^#define\s+(SYS_[A-Z0-9_]+)\s+(\d+)\s*$", text, flags=re.MULTILINE)
    return {int(num): name for name, num in entries}


def _extract_syscalls_from_markdown_table(text: str) -> dict[int, str]:
    entries = re.findall(r"^\|\s*(\d+)\s*\|\s*(SYS_[A-Z0-9_]+)\s*\|", text, flags=re.MULTILINE)
    return {int(num): name for num, name in entries}


def test_os_interface_syscalls_match_os_defs():
    header = (_ROOT / "os" / "os_defs.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "os_interface.md").read_text(encoding="utf-8")

    expected = _extract_syscalls_from_header(header)
    documented = _extract_syscalls_from_markdown_table(doc)

    assert documented == expected


def test_arch_contract_syscalls_match_os_defs():
    header = (_ROOT / "os" / "os_defs.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    expected = _extract_syscalls_from_header(header)
    documented = _extract_syscalls_from_markdown_table(doc)

    assert documented == expected


def test_arch_contract_os_mmio_and_quantum_match_os_defs():
    header = (_ROOT / "os" / "os_defs.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    names = [
        "UART_TXDATA", "UART_RXDATA", "UART_STATUS",
        "TIMER_CMP_ADDR", "TIMER_CNT_ADDR", "TIMER_QUANTUM",
    ]
    vals = _extract_define_ints(header, names)

    assert f"- UART_TXDATA = 0x{vals['UART_TXDATA']:04X};" in doc
    assert f"- UART_RXDATA = 0x{vals['UART_RXDATA']:04X};" in doc
    assert f"- UART_STATUS = 0x{vals['UART_STATUS']:04X};" in doc
    assert f"- TIMER_CMP_ADDR = 0x{vals['TIMER_CMP_ADDR']:04X};" in doc
    assert f"- TIMER_CNT_ADDR = 0x{vals['TIMER_CNT_ADDR']:04X}." in doc
    assert f"- TIMER_QUANTUM = {vals['TIMER_QUANTUM']} ciclos." in doc


def test_memory_system_mmio_table_matches_os_defs():
    header = (_ROOT / "os" / "os_defs.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "memory_system.md").read_text(encoding="utf-8")

    names = [
        "UART_TXDATA", "UART_RXDATA", "UART_STATUS",
        "TIMER_CMP_ADDR", "TIMER_CNT_ADDR",
    ]
    vals = _extract_define_ints(header, names)

    assert f"| 0x{vals['UART_TXDATA']:05X} | UART_TXDATA |" in doc
    assert f"| 0x{vals['UART_RXDATA']:05X} | UART_RXDATA |" in doc
    assert f"| 0x{vals['UART_STATUS']:05X} | UART_STATUS |" in doc
    assert f"| 0x{vals['TIMER_CMP_ADDR']:05X} | TIMER_CMP_ADDR |" in doc
    assert f"| 0x{vals['TIMER_CNT_ADDR']:05X} | TIMER_CNT_ADDR |" in doc


def test_arch_contract_hypervisor_layout_matches_header():
    header = (_ROOT / "hypervisor" / "hypervisor.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    names = [
        "HV_BASE_ADDR", "HV_SIZE", "GUEST_MEM_BASE", "GUEST_MEM_PER_VM",
        "HV_SHARED_BASE", "TOTAL_MEM_SIZE",
    ]
    vals = _extract_define_ints(header, names)

    hv_start = vals["HV_BASE_ADDR"]
    hv_end = hv_start + vals["HV_SIZE"] - 1
    assert f"- 0x{hv_start:08X}-0x{hv_end:08X}: hypervisor;" in doc

    for i in range(4):
        start = vals["GUEST_MEM_BASE"] + i * vals["GUEST_MEM_PER_VM"]
        end = start + vals["GUEST_MEM_PER_VM"] - 1
        assert f"- 0x{start:08X}-0x{end:08X}: memória da VM {i};" in doc

    shared_start = vals["HV_SHARED_BASE"]
    shared_end = vals["TOTAL_MEM_SIZE"] - 1
    assert f"- 0x{shared_start:08X}-0x{shared_end:08X}: região compartilhada/MMIO." in doc


def test_os_interface_uart_mmio_matches_os_defs():
    header = (_ROOT / "os" / "os_defs.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "os_interface.md").read_text(encoding="utf-8")

    vals = _extract_define_ints(header, ["UART_TXDATA", "UART_RXDATA"])

    assert f"- TX: escrever byte em MMIO[0x{vals['UART_TXDATA']:04X}]" in doc
    assert f"- RX: ler byte de MMIO[0x{vals['UART_RXDATA']:04X}]" in doc


def test_arch_contract_hypervisor_trap_codes_match_header():
    header = (_ROOT / "hypervisor" / "hypervisor.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    vals = _extract_define_ints(
        header,
        [
            "TRAP_ILLEGAL_INSTR",
            "TRAP_DIV_ZERO",
            "TRAP_OVERFLOW",
            "TRAP_SYSCALL",
            "TRAP_BREAK",
            "TRAP_PAGE_FAULT",
            "TRAP_MISALIGNED",
            "TRAP_TIMER",
            "TRAP_EXT_IRQ_BASE",
        ],
    )

    assert f"- 0x{vals['TRAP_ILLEGAL_INSTR']:02X}: illegal instruction;" in doc
    assert f"- 0x{vals['TRAP_DIV_ZERO']:02X}: division by zero;" in doc
    assert f"- 0x{vals['TRAP_OVERFLOW']:02X}: overflow;" in doc
    assert f"- 0x{vals['TRAP_SYSCALL']:02X}: syscall;" in doc
    assert f"- 0x{vals['TRAP_BREAK']:02X}: break;" in doc
    assert f"- 0x{vals['TRAP_PAGE_FAULT']:02X}: page fault;" in doc
    assert f"- 0x{vals['TRAP_MISALIGNED']:02X}: misaligned access;" in doc
    assert f"- 0x{vals['TRAP_TIMER']:02X}: timer;" in doc
    assert f"- 0x{vals['TRAP_EXT_IRQ_BASE']:02X}+n: IRQ externa n." in doc


def test_arch_contract_hypercalls_match_header():
    header = (_ROOT / "hypervisor" / "hypervisor.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    names = [
        "HV_CALL_VERSION",
        "HV_CALL_VM_ID",
        "HV_CALL_VM_CREATE",
        "HV_CALL_VM_YIELD",
        "HV_CALL_VM_EXIT",
        "HV_CALL_CONSOLE_PUT",
    ]
    vals = _extract_define_ints(header, names)

    for name in names:
        line_a = f"- 0x{vals[name]:02X}: {name};"
        line_b = f"- 0x{vals[name]:02X}: {name}."
        assert line_a in doc or line_b in doc


def test_abi_register_contract_matches_instruction_set_and_docs():
    isa = (_ROOT / "cpu" / "instruction_set.py").read_text(encoding="utf-8")
    contract = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")
    os_if = (_ROOT / "docs" / "os_interface.md").read_text(encoding="utf-8")

    vals = _extract_py_int_consts(isa, ["ZERO_REG", "SP_REG", "LR_REG"])

    # Fonte de verdade numérica da ISA.
    assert vals["ZERO_REG"] == 0
    assert vals["SP_REG"] == 30
    assert vals["LR_REG"] == 31

    # Contrato arquitetural deve refletir os mesmos registradores especiais.
    assert "- R0: zero hardwired;" in contract
    assert "- R30: stack pointer;" in contract
    assert "- R31: link register." in contract

    # Documento de interface OS também deve manter o mesmo mapeamento.
    assert "R0        zero" in os_if
    assert "R30       sp" in os_if
    assert "R31       lr" in os_if


def test_arch_contract_vm_states_match_hypervisor_header():
    header = (_ROOT / "hypervisor" / "hypervisor.h").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    state_pairs = re.findall(r"^\s*(VM_STATE_[A-Z_]+)\s*=\s*(\d+)\s*,", header, flags=re.MULTILINE)
    assert state_pairs, "Nenhum estado de VM encontrado em hypervisor.h"

    for name, num in state_pairs:
        line_a = f"- {num}: {name};"
        line_b = f"- {num}: {name}."
        assert line_a in doc or line_b in doc


def test_arch_contract_bootloader_ivt_and_bss_match_asm():
    asm = (_ROOT / "boot" / "bootloader.asm").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    assert "- IVT_BASE = 0x0100 e escrita em CSR[1];" in doc
    assert "MOVI    R1, 0x0100" in asm
    assert "MTC     R1, 1" in asm
    assert ".org    0x100" in asm

    assert "- BSS_START = 0x0800;" in doc
    assert "- BSS_END = 0x1000 (intervalo zerado: [0x0800, 0x0FFF])." in doc
    assert "MOVI    R2, 0x0800" in asm
    assert "MOVI    R3, 0x1000" in asm


def test_arch_contract_bootloader_ivt_order_matches_asm():
    asm = (_ROOT / "boot" / "bootloader.asm").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    expected = [
        "ivt_illegal",
        "ivt_divzero",
        "ivt_overflow",
        "ivt_syscall",
        "ivt_break",
        "ivt_ifetch_pf",
        "ivt_load_pf",
        "ivt_store_pf",
        "ivt_unaligned",
        "ivt_timer",
        "ivt_ext0",
        "ivt_ext1",
        "ivt_ext2",
        "ivt_ext3",
        "ivt_ext4",
        "ivt_ext5",
        "ivt_ext6",
    ]

    labels = re.findall(r"^(ivt_[a-z0-9_]+):", asm, flags=re.MULTILINE)
    assert labels == expected

    for name in expected:
        line_a = f"- {name};"
        line_b = f"- {name}."
        assert line_a in doc or line_b in doc


def test_arch_contract_bootloader_c_mode_and_load_policy_match_source():
    src = (_ROOT / "boot" / "bootloader.c").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    assert "- BOOT_SIM = 0;" in doc
    assert "- BOOT_FPGA = 1;" in doc
    assert "- seleção por GPIO_IN bit 4 (0x10): 1 = FPGA, 0 = simulação." in doc
    assert "#define BOOT_SIM    0" in src
    assert "#define BOOT_FPGA   1" in src
    assert "return (GPIO_IN & 0x10u) ? BOOT_FPGA : BOOT_SIM;" in src

    assert "- em BOOT_FPGA: carregar imagem de FLASH_BASE + 0x4000 para 0x00002000, com tamanho 0x2000 bytes;" in doc
    assert "#define KERNEL_FLASH_OFFSET  0x4000u" in src
    assert "#define KERNEL_FLASH_SIZE    0x2000u" in src
    assert "#define KERNEL_LOAD_ADDR     0x00002000u" in src
    assert "load_kernel(KERNEL_FLASH_OFFSET," in src

    assert "- em BOOT_SIM: não recarregar imagem e seguir com execução já presente em IMEM." in doc
    assert "[BOOT] Simulation: kernel already in IMEM, skipping load." in src


def test_arch_contract_bootloader_c_handoff_match_source():
    src = (_ROOT / "boot" / "bootloader.c").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    assert "- com CONFIG_HYPERVISOR: chamar hv_init() antes de hv_main();" in doc
    assert "#ifdef CONFIG_HYPERVISOR" in src
    assert "hv_init();" in src
    assert "hv_main();" in src
    assert src.find("hv_init();") < src.find("hv_main();")

    assert "- sem CONFIG_HYPERVISOR: chamar kernel_main();" in doc
    assert "kernel_main();" in src

    assert "- retorno de hv_main() ou kernel_main() é erro fatal de boot." in doc
    assert "[BOOT] ERROR: kernel returned (should never happen)!" in src


def test_arch_contract_scheduler_behavior_matches_source():
    src = (_ROOT / "os" / "scheduler.c").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    assert "- scheduler_tick deve sanitizar PID atual inválido para PID_IDLE;" in doc
    assert "if (cur_pid < 0 || cur_pid >= MAX_PROCS)" in src
    assert "cur_pid = PID_IDLE;" in src

    assert "- scheduler_tick deve transicionar PROC_RUNNING para PROC_READY antes de escolher o próximo;" in doc
    assert "if (cur_entry[FIELD_STATE] == PROC_RUNNING)" in src
    assert "cur_entry[FIELD_STATE] = PROC_READY;" in src

    assert "- scheduler_tick deve sanitizar PID inválido retornado por schedule() para PID_IDLE;" in doc
    assert "next_pid = schedule();" in src
    assert "if (next_pid < 0 || next_pid >= MAX_PROCS)" in src
    assert "next_pid = PID_IDLE;" in src

    assert "- scheduler_tick deve marcar o próximo processo como PROC_RUNNING." in doc
    assert "next_entry[FIELD_STATE] = PROC_RUNNING;" in src


def test_arch_contract_heap_behavior_matches_source():
    src = (_ROOT / "os" / "memory.c").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    assert "- kmalloc(size <= 0) deve retornar 0;" in doc
    assert "if (size <= 0)" in src
    assert "return (int *)0;" in src

    assert "- kfree(0) deve ser operação nula segura;" in doc
    assert "if (ptr == (int *)0)" in src
    assert "return;   /* kfree(NULL) é operação nula — seguro chamar */" in src

    assert "- kfree deve realizar coalescência forward e backward quando houver blocos livres adjacentes;" in doc
    assert "/* ── Forward merge: combinar com próximo bloco se também livre ── */" in src
    assert "/* ── Backward merge: percorre desde HEAP_START para achar bloco anterior ── */" in src

    assert "- heap_stats deve interromper varredura ao detectar bloco corrompido (size <= 0)." in doc
    assert "if (cur[0] <= 0)" in src
    assert "break;   /* heap corrompido: para contagem */" in src


def test_arch_contract_hypervisor_trap_and_vm_lifecycle_behavior_matches_source():
    trap_src = (_ROOT / "hypervisor" / "trap_handler.c").read_text(encoding="utf-8")
    vm_src = (_ROOT / "hypervisor" / "vm_manager.c").read_text(encoding="utf-8")
    doc = (_ROOT / "docs" / "contrato_arquitetural.md").read_text(encoding="utf-8")

    assert "- TRAP_TIMER deve acionar preempção via vm_schedule_next();" in doc
    assert "case TRAP_TIMER:" in trap_src
    assert "trap_timer();" in trap_src
    assert "vm_schedule_next();" in trap_src

    assert "- TRAP_SYSCALL com número >= 0x80 deve ser tratado como hypercall no hypervisor;" in doc
    assert "if (call >= 0x80u)" in trap_src

    assert "- TRAP_SYSCALL com número < 0x80 deve ser injetado para o guest (trap_inject_to_guest + vcpu_run);" in doc
    assert "trap_inject_to_guest(vm_id, TRAP_SYSCALL, epc);" in trap_src
    assert "vcpu_run(vm_id);" in trap_src

    assert "- TRAP_BREAK deve avançar EPC em +4 e retomar a VM." in doc
    assert "case TRAP_BREAK:" in trap_src
    assert "g_hv.vms[cur].vcpu.pc = epc + 4u;" in trap_src

    assert "- vm_create deve inicializar VM em VM_STATE_CREATED;" in doc
    assert "vm->state    = VM_STATE_CREATED;" in vm_src

    assert "- vm_start deve transicionar VM para VM_STATE_READY;" in doc
    assert "g_hv.vms[vm_id].state = VM_STATE_READY;" in vm_src

    assert "- vm_pause deve transicionar VM RUNNING/READY para VM_STATE_BLOCKED;" in doc
    assert "if (st == VM_STATE_RUNNING || st == VM_STATE_READY)" in vm_src
    assert "g_hv.vms[vm_id].state = VM_STATE_BLOCKED;" in vm_src

    assert "- vm_schedule_next deve salvar contexto e demover VM_STATE_RUNNING para VM_STATE_READY antes de hv_main()." in doc
    assert "vcpu_save_state(cur);" in vm_src
    assert "if (g_hv.vms[cur].state == VM_STATE_RUNNING)" in vm_src
    assert "g_hv.vms[cur].state = VM_STATE_READY;" in vm_src
    assert "hv_main();" in vm_src
