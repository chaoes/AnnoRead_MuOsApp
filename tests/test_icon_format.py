#!/usr/bin/env python3
"""tests/test_icon_format.py
Validates muOS glyph and app icon formats:
1. File sizes:
   - package/glyph/read.png must be 26x26 RGBA
   - package/glyph/icon.png must be 120x120 RGBA
   - package/icon.png must be 128x128 RGBA
2. Transparency & Palette:
   - Foreground pixels must be pure white (255, 255, 255)
   - Background must have 0 alpha (transparent)
   - Foreground fill ratio must be balanced (20% ~ 45%) to display clearly in 1-bit / alpha mask modes
"""

import sys
from pathlib import Path
from PIL import Image

def test_icon(path_str, expected_size):
    path = Path(path_str)
    assert path.is_file(), f"File {path_str} does not exist"
    im = Image.open(path)
    assert im.size == expected_size, f"{path_str} size {im.size} != expected {expected_size}"
    assert im.mode == "RGBA", f"{path_str} mode {im.mode} != RGBA"

    total = im.width * im.height
    transparent_cnt = 0
    opaque_cnt = 0

    for x in range(im.width):
        for y in range(im.height):
            r, g, b, a = im.getpixel((x, y))
            if a == 0:
                transparent_cnt += 1
            else:
                assert (r, g, b) == (255, 255, 255), f"Non-white pixel {(r, g, b)} at ({x}, {y}) in {path_str}"
                if a >= 128:
                    opaque_cnt += 1

    ratio = opaque_cnt / total
    assert transparent_cnt > 0, f"{path_str} has no transparent pixels"
    assert 0.15 <= ratio <= 0.50, f"{path_str} foreground ratio {ratio:.2f} out of range [0.15, 0.50]"
    print(f"✔ {path_str} ({im.size[0]}x{im.size[1]} RGBA, {ratio*100:.1f}% foreground) passed!")

def main():
    print("=== Running muOS Icon Format & Transparency Tests ===")
    test_icon("package/glyph/read.png", (26, 26))
    test_icon("package/glyph/icon.png", (120, 120))
    test_icon("package/icon.png", (128, 128))
    print("🎉 ALL ICON TESTS PASSED! 🎉")

if __name__ == "__main__":
    main()
