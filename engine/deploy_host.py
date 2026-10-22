#!/usr/bin/env python3
"""Atomically replace the deployed host library without truncating loaded inodes."""
import os
import shutil
import sys
import tempfile


def deploy(source: str, destination: str) -> None:
    destination_dir = os.path.dirname(os.path.abspath(destination))
    prefix = "." + os.path.basename(destination) + "."
    fd, temporary = tempfile.mkstemp(prefix=prefix, suffix=".tmp", dir=destination_dir)
    os.close(fd)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} SOURCE DESTINATION", file=sys.stderr)
        return 2
    deploy(argv[1], argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
