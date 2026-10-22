#!/usr/bin/env python3
"""Header-level guards for the muOS staged ELF architecture check."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "package"))
from make_muxapp import REQUIRED_ELF_PATHS, validate_stage  # noqa: E402


def elf_header(machine: int, *, elf_class: int = 2, data: int = 1) -> bytes:
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4] = elf_class
    header[5] = data
    header[6] = 1
    header[18:20] = machine.to_bytes(2, "little")
    return bytes(header)


class StageArchitectureTest(unittest.TestCase):
    def make_stage(self, root: Path) -> None:
        for relative in REQUIRED_ELF_PATHS:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(elf_header(183))

    def test_accepts_aarch64_runtime_headers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_stage(root)
            validate_stage(root)

    def test_rejects_x86_64_shared_library(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_stage(root)
            (root / "libs/libluajit-5.1.so.2").write_bytes(elf_header(62))
            with self.assertRaisesRegex(ValueError, r"expected AArch64 \(183\)"):
                validate_stage(root)

    def test_rejects_malformed_elf_and_unlisted_x86_elf(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_stage(root)
            (root / "src/liblegado_qjs.so").write_bytes(b"\x7fELF\x02")
            with self.assertRaisesRegex(ValueError, "truncated ELF header"):
                validate_stage(root)

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.make_stage(root)
            extra = root / "plugins/accidental.so"
            extra.parent.mkdir()
            extra.write_bytes(elf_header(62))
            with self.assertRaisesRegex(ValueError, r"expected AArch64 \(183\)"):
                validate_stage(root)


if __name__ == "__main__":
    unittest.main()
