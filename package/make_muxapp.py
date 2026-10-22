#!/usr/bin/env python3
"""Create a STORE-only muOS archive with Unix file modes preserved."""
from __future__ import annotations

import os
from pathlib import Path
import stat
import shutil
import sys
import zipfile

REQUIRED_ELF_PATHS = (
    "love",
    "libs/liblove-11.5.so",
    "libs/libluajit-5.1.so.2",
    "src/liblegado_qjs.so",
)
ELF_AARCH64 = 183


def elf_machine(path: Path) -> int | None:
    """Return e_machine for ELF files, rejecting malformed/unsupported headers."""
    with path.open("rb") as source:
        header = source.read(20)
    if not header.startswith(b"\x7fELF"):
        return None
    if len(header) < 20:
        raise ValueError(f"truncated ELF header: {path}")
    if header[4] != 2 or header[5] != 1:
        raise ValueError(f"ELF must be 64-bit little-endian: {path}")
    return int.from_bytes(header[18:20], "little")


def validate_stage(root: Path) -> None:
    """Require packaged executables/libraries and every staged ELF to be AArch64."""
    for relative in REQUIRED_ELF_PATHS:
        path = root / relative
        if not path.is_file():
            raise ValueError(f"required runtime ELF is missing: {path}")
        machine = elf_machine(path)
        if machine is None:
            raise ValueError(f"required runtime file is not ELF: {path}")
        if machine != ELF_AARCH64:
            raise ValueError(f"wrong ELF machine {machine} in {path}; expected AArch64 (183)")

    for path in root.rglob("*"):
        if not path.is_file():
            continue
        machine = elf_machine(path)
        if machine is not None and machine != ELF_AARCH64:
            raise ValueError(f"wrong ELF machine {machine} in {path}; expected AArch64 (183)")


def add_path(archive: zipfile.ZipFile, path: Path, archive_name: str) -> None:
    info = zipfile.ZipInfo(archive_name)
    info.create_system = 3  # Unix, so external_attr carries POSIX modes.
    mode = stat.S_IMODE(path.stat().st_mode)
    if path.is_dir():
        info.filename = archive_name.rstrip("/") + "/"
        info.external_attr = ((stat.S_IFDIR | mode) << 16) | 0x10
        info.compress_type = zipfile.ZIP_STORED
        archive.writestr(info, b"")
        return

    info.external_attr = (stat.S_IFREG | mode) << 16
    info.compress_type = zipfile.ZIP_STORED
    info.file_size = path.stat().st_size
    with path.open("rb") as source, archive.open(info, mode="w") as target:
        shutil.copyfileobj(source, target)


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("usage: make_muxapp.py STAGE_ROOT APP_DIR OUTPUT")
    stage_root, app_dir, output = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    root = stage_root / app_dir
    if not root.is_dir():
        raise SystemExit(f"application directory not found: {root}")
    try:
        validate_stage(root)
    except ValueError as error:
        raise SystemExit(f"refusing to package invalid muOS stage: {error}") from error
    output.parent.mkdir(parents=True, exist_ok=True)

    # Opening with mode 'w' replaces an older archive instead of updating it.
    with zipfile.ZipFile(output, mode="w", allowZip64=True) as archive:
        add_path(archive, root, app_dir + "/")
        for path in sorted(root.rglob("*")):
            relative = path.relative_to(stage_root).as_posix()
            if relative == f"{app_dir}/conf" or relative.startswith(f"{app_dir}/conf/"):
                continue
            archive_name = relative + ("/" if path.is_dir() else "")
            add_path(archive, path, archive_name)


if __name__ == "__main__":
    main()
