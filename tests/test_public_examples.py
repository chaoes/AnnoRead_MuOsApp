"""Validate the public templates without reading private local configuration."""

import json
from pathlib import Path


root = Path(__file__).resolve().parents[1]
tts = json.loads((root / "config/mimo_tts.example.json").read_text(encoding="utf-8"))
assert tts["api_key"] == "YOUR_MIMO_API_KEY"
assert tts["voice"] == "茉莉"
assert 0.5 <= tts["speed"] <= 2.0
assert -2 <= tts["pitch"] <= 2
assert tts["voice_style"]

sources = json.loads((root / "examples/book_source.example.json").read_text(encoding="utf-8"))
assert len(sources) == 1
source = sources[0]
assert source["bookSourceUrl"].endswith(".invalid")
assert source["enabled"] is False
for field in ("bookSourceName", "searchUrl", "ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent"):
    assert source[field], field

print("Public MiMo and book-source examples are valid and intentionally unusable")
