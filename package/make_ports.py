#!/usr/bin/env python3
"""Build an isolated PortMaster ZIP; never include personal sources or keys."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from make_muxapp import ELF_AARCH64, add_path, elf_machine

PROJECT = Path(__file__).resolve().parents[1]


def build_package(project: Path, output: Path) -> None:
    engine = project / "engine/liblegado_qjs_aarch64.so"
    if elf_machine(engine) != ELF_AARCH64:
        raise ValueError("PortMaster engine must be AArch64; run make cross first")
    versions = subprocess.check_output(
        ["readelf", "--version-info", str(engine)], text=True
    )
    required = sorted(
        {tuple(map(int, v.split('.'))) for v in re.findall(r"GLIBC_(\d+\.\d+(?:\.\d+)?)", versions)}
    )
    minimum = '.'.join(map(str, required[-1])) if required else "2.38"
    if tuple(map(int, minimum.split('.'))) > (2, 38):
        raise ValueError(f"Engine requires GLIBC {minimum}, above the launcher's 2.38 baseline")

    with tempfile.TemporaryDirectory(prefix="annoread-ports-") as temporary:
        stage = Path(temporary)
        app = stage / "annoread"
        app.mkdir()
        for name in ("main.lua", "conf.lua"):
            shutil.copy2(project / name, app / name)
        # Lua-only source tree: the host .so is deliberately excluded.
        for source in (project / "src").rglob("*.lua"):
            target = app / source.relative_to(project)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        shutil.copy2(engine, app / "src/liblegado_qjs.so")
        # Whitelist assets rather than copying ignored sources/config/cache.
        shutil.copytree(project / "assets/fonts", app / "assets/fonts")
        (app / "sources").mkdir()
        shutil.copy2(project / "sources/README.md", app / "sources/README.md")
        (app / "config").mkdir()
        shutil.copy2(project / "config/mimo_tts.example.json", app / "config/mimo_tts.example.json")
        licenses = app / "licenses"
        licenses.mkdir()
        for source, name in (
            ("LICENSE", "LICENSE.txt"),
            ("engine/quickjs/LICENSE", "LICENSE-quickjs.txt"),
            ("engine/vendor/Copyright.libxml2", "COPYRIGHT-libxml2.txt"),
            ("assets/fonts/OFL-MapleMono.txt", "OFL-MapleMono.txt"),
        ):
            shutil.copy2(project / source, licenses / name)
        shutil.copy2(project / "THIRD_PARTY_NOTICES.md", app / "THIRD_PARTY_NOTICES.md")
        shutil.copy2(project / "package/ports/README.md", app / "README.md")
        shutil.copy2(project / "package/ports/port.json", app / "port.json")
        launcher = stage / "AnnoRead.sh"
        launcher.write_text((project / "package/ports/AnnoRead.sh").read_text().replace('\r\n', '\n'))
        launcher.chmod(0o755)
        # Preserve the measured ABI requirement for troubleshooting.
        (app / "build-info.json").write_text(json.dumps({
            "arch": "aarch64", "engine_min_glibc": minimum,
            "package_min_glibc": "2.38", "runtime": "love_11.5",
            "keyboard": "built-in src/keyboard.lua", "layout": "720x720",
        }, indent=2) + '\n')
        for path in app.rglob('*'):
            if path.is_file():
                machine = elf_machine(path)
                if machine is not None and machine != ELF_AARCH64:
                    raise ValueError(f"Non-AArch64 ELF in package: {path}")
        output.parent.mkdir(parents=True, exist_ok=True)
        # Replace only after the complete archive has been assembled successfully.
        with tempfile.NamedTemporaryFile(dir=output.parent, suffix='.zip', delete=False) as handle:
            archive_path = Path(handle.name)
        try:
            with zipfile.ZipFile(archive_path, 'w', allowZip64=True) as archive:
                for path in sorted(stage.rglob('*')):
                    add_path(archive, path, path.relative_to(stage).as_posix())
            archive_path.replace(output)
            output.chmod(0o644)
        finally:
            archive_path.unlink(missing_ok=True)
    print(f"Created {output} (AArch64, GLIBC >= 2.38; built-in keyboard unchanged)")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=PROJECT / 'dist/annoread.zip')
    args = parser.parse_args()
    build_package(PROJECT, args.output.resolve())
