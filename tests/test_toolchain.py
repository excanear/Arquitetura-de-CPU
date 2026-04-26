"""
tests/test_toolchain.py — Testes de integração da toolchain EduRISC-32v2

Cobre:
  - Wrapper do assembler da toolchain gerando Intel HEX válido
  - Loader convertendo HEX para lista de memória e formato .mem
"""

from assembler.assembler import Assembler
from toolchain.assembler import ToolchainAssembler
from toolchain.compiler import ToolchainCompiler
from toolchain.linker import Linker
from toolchain.loader import Loader


def test_toolchain_assembler_hex_round_trip(tmp_path):
    source = """
        .org 0x0
        MOVI R1, 42
        HLT
    """

    src_path = tmp_path / "prog.asm"
    hex_path = tmp_path / "prog.hex"
    mem_path = tmp_path / "prog.mem"

    src_path.write_text(source, encoding="utf-8")

    expected_words = Assembler().assemble(source)

    asm_tool = ToolchainAssembler(listing=True)
    result = asm_tool.assemble_file(str(src_path), str(hex_path), fmt="hex")

    assert result["success"] is True
    assert result["errors"] == []
    assert result["bytes"] == len(expected_words) * 4
    assert hex_path.exists()
    assert (tmp_path / "prog.lst").exists()

    loader = Loader()
    loader.load_hex(hex_path)
    loaded_words = loader.to_mem_list(size=len(expected_words))
    assert loaded_words == expected_words

    loader.write_mem(mem_path, size=len(expected_words))
    mem_lines = mem_path.read_text(encoding="ascii").splitlines()
    assert mem_lines == [f"{word:08X}" for word in expected_words]


def test_toolchain_compiler_hex_round_trip(tmp_path):
    source_c = """
      int main() {
        int x = 40;
        return x + 2;
      }
    """

    src_path = tmp_path / "prog.c"
    hex_path = tmp_path / "prog.hex"
    asm_path = tmp_path / "prog.asm"

    src_path.write_text(source_c, encoding="utf-8")

    tc = ToolchainCompiler()
    result = tc.compile_file(str(src_path), str(hex_path), assemble=True)

    assert result["success"] is True
    assert result["errors"] == []
    assert result["hex_path"] == str(hex_path)
    assert result["asm_path"] == str(asm_path)
    assert asm_path.exists()
    assert hex_path.exists()

    loader = Loader()
    loader.load_hex(hex_path)
    words = loader.to_mem_list(size=64)
    assert any(word != 0 for word in words)


def test_toolchain_linker_multiobj_round_trip(tmp_path):
    src1 = """
      .org 0x0
      MOVI R1, 1
      HLT
    """
    src2 = """
      .org 0x0
      MOVI R2, 2
      HLT
    """

    asm1 = tmp_path / "mod1.asm"
    asm2 = tmp_path / "mod2.asm"
    obj1 = tmp_path / "mod1.obj"
    obj2 = tmp_path / "mod2.obj"
    linked_hex = tmp_path / "linked.hex"

    asm1.write_text(src1, encoding="utf-8")
    asm2.write_text(src2, encoding="utf-8")

    tool = ToolchainAssembler()
    res1 = tool.assemble_file(str(asm1), str(obj1), fmt="obj")
    res2 = tool.assemble_file(str(asm2), str(obj2), fmt="obj")

    assert res1["success"] is True and res1["errors"] == []
    assert res2["success"] is True and res2["errors"] == []
    assert obj1.exists() and obj2.exists()

    linker = Linker()
    linker.add_object(obj1)
    linker.add_object(obj2)
    linker.link(linked_hex)

    loader = Loader()
    loader.load_hex(linked_hex)
    words = loader.to_mem_list(size=4)

    expected1 = Assembler().assemble(src1)
    expected2 = Assembler().assemble(src2)
    assert words == expected1 + expected2