#!/usr/bin/env python3
"""Check Lua JSON escape semantics and optionally round-trip the 31-source snapshot."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
ROUNDTRIP = ROOT / "tests" / "json_roundtrip.lua"


def lua_roundtrip(raw: str) -> object:
    with tempfile.TemporaryDirectory() as tmp:
        input_path = Path(tmp) / "input.json"
        output_path = Path(tmp) / "output.json"
        input_path.write_text(raw, encoding="utf-8")
        proc = subprocess.run(
            ["luajit", str(ROUNDTRIP), str(input_path), str(output_path)],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        if proc.returncode:
            raise AssertionError(proc.stderr or proc.stdout or "Lua JSON round-trip failed")
        return json.loads(output_path.read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--collection", help="optional full source collection JSON snapshot")
    args = parser.parse_args()

    fixture = r'{"literal":"\\n","actual":"\n","quote":"a\"b","slash":"https:\/\/host\/x","pair":"\uD83D\uDE80"}'
    expected = json.loads(fixture)
    actual = lua_roundtrip(fixture)
    assert actual == expected, f"escape round-trip mismatch: {actual!r} != {expected!r}"
    assert actual["literal"] == "\\n" and actual["actual"] == "\n"
    assert actual["pair"] == "🚀"

    # Invalid escape sequences must fail with a useful diagnostic. The existing
    # decode() first return stays nil on failure; callers may inspect the second.
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "bad.json"
        bad.write_text(r'{"broken":"\q"}', encoding="utf-8")
        subprocess.run(
            ["luajit", str(ROUNDTRIP), str(bad), str(Path(tmp) / "unused.json"), "expect-error"],
            cwd=ROOT,
            check=True,
        )

    collection = args.collection or os.getenv("ANNO_SOURCE_COLLECTION")
    if collection:
        path = Path(collection)
        raw = path.read_text(encoding="utf-8")
        expected_collection = json.loads(raw)
        actual_collection = lua_roundtrip(raw)
        assert actual_collection == expected_collection, "Lua round-trip changed source collection fields"
        assert isinstance(actual_collection, list) and len(actual_collection) == 31
        print(f"JSON escape and 31-source round-trip checks passed: {path}")
    else:
        print("JSON escape checks passed (set ANNO_SOURCE_COLLECTION to run the full source snapshot check)")


if __name__ == "__main__":
    main()
