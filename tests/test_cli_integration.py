"""
tests/test_cli_integration.py — Integração de CLI end-to-end

Valida comandos do main.py usados no pipeline unificado.
"""

from pathlib import Path
import json
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def _run_cli(args: list[str], cwd: Path) -> subprocess.CompletedProcess:
    cmd = [sys.executable, "main.py"] + args
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def test_main_cli_link_then_load_vinit(tmp_path):
    obj1 = tmp_path / "a.obj"
    obj2 = tmp_path / "b.obj"
    out_hex = tmp_path / "linked.hex"
    out_vinit = tmp_path / "linked_init.v"

    # Dois módulos mínimos sem relocação, em formato aceito pelo linker.
    obj1.write_text(
        json.dumps(
            {
                "format": "edurisc32v2-obj-v1",
                "source": "a.asm",
                "text": [[0, 0xDEADBEEF]],
                "data": [],
                "bss_size": 0,
                "symbols": {},
                "relocs": [],
            }
        ),
        encoding="utf-8",
    )
    obj2.write_text(
        json.dumps(
            {
                "format": "edurisc32v2-obj-v1",
                "source": "b.asm",
                "text": [[0, 0xC001D00D]],
                "data": [],
                "bss_size": 0,
                "symbols": {},
                "relocs": [],
            }
        ),
        encoding="utf-8",
    )

    r_link = _run_cli(["link", str(obj1), str(obj2), "-o", str(out_hex)], ROOT)
    assert r_link.returncode == 0, r_link.stderr or r_link.stdout
    assert out_hex.exists()
    assert ":00000001FF" in out_hex.read_text(encoding="ascii")

    r_load = _run_cli(["load", str(out_hex), "--format", "vinit", "-o", str(out_vinit)], ROOT)
    assert r_load.returncode == 0, r_load.stderr or r_load.stdout
    assert out_vinit.exists()

    text = out_vinit.read_text(encoding="ascii")
    assert "initial begin" in text
    assert "32'hDEADBEEF" in text
    assert "32'hC001D00D" in text


def test_main_cli_build_then_load_mem(tmp_path):
    src_c = tmp_path / "prog.c"
    out_hex = tmp_path / "prog.hex"
    out_mem = tmp_path / "prog.mem"

    src_c.write_text(
        """
        int main() {
            int x = 5;
            return x + 7;
        }
        """,
        encoding="utf-8",
    )

    r_build = _run_cli(["build", str(src_c), "-o", str(out_hex)], ROOT)
    assert r_build.returncode == 0, r_build.stderr or r_build.stdout
    assert out_hex.exists()

    r_load = _run_cli(["load", str(out_hex), "--format", "mem", "-o", str(out_mem)], ROOT)
    assert r_load.returncode == 0, r_load.stderr or r_load.stdout
    assert out_mem.exists()

    mem_lines = [line.strip() for line in out_mem.read_text(encoding="ascii").splitlines() if line.strip()]
    assert len(mem_lines) > 0
    assert any(line != "00000000" for line in mem_lines)
