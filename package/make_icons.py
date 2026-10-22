#!/usr/bin/env python3
"""Generate AnnoRead app icons (book outline with letter A) for muOS.

Produces:
    package/glyph/read.png   26x26  muOS Applications-list glyph (transparent background)
    package/glyph/icon.png   120x120 muOS Applications-list backup glyph
    package/icon.png         128x128 install / app icon
"""

from pathlib import Path
from PIL import Image, ImageDraw


def render_book_icon(target_size=26, scale=16):
    """Render an open book contour with an inner uppercase letter 'A'.

    The resulting image has a transparent background with pure white (255, 255, 255)
    foreground pixels and anti-aliased alpha, guaranteeing high contrast and
    legibility in 1-bit or alpha-masked launcher lists as well as normal renderers.
    """
    w = target_size * scale
    h = target_size * scale
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    cx = (w - 1) / 2.0

    # Book bounding box proportions
    book_w = w * 0.86
    book_h = h * 0.72

    half_bw = book_w / 2.0
    left = cx - half_bw
    right = cx + half_bw

    top = (h - book_h) / 2.0 - h * 0.03
    bot = top + book_h

    stroke = max(2, int(w * 0.065))

    # Curve parameters
    top_outer = top + h * 0.04
    top_arch = top - h * 0.035
    top_spine = top + h * 0.075

    bot_outer = bot - h * 0.05
    bot_arch = bot - h * 0.065
    bot_spine = bot + h * 0.045

    def bezier_half(x0, y0, x1, y1, x2, y2, n=100):
        pts = []
        for i in range(n + 1):
            t = i / float(n)
            px = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * x1 + t ** 2 * x2
            py = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * y1 + t ** 2 * y2
            pts.append((px, py))
        return pts

    left_arch_x = left + half_bw * 0.5
    top_left_curve = bezier_half(left, top_outer, left_arch_x, top_arch, cx, top_spine)
    bot_left_curve = bezier_half(left, bot_outer, left_arch_x, bot_arch, cx, bot_spine)

    # Mirror right side to guarantee exact symmetry
    top_right_curve = [(2 * cx - px, py) for px, py in reversed(top_left_curve)]
    bot_right_curve = [(2 * cx - px, py) for px, py in reversed(bot_left_curve)]

    # Draw book page curves
    d.line(top_left_curve, fill=(255, 255, 255, 255), width=stroke, joint="curve")
    d.line(top_right_curve, fill=(255, 255, 255, 255), width=stroke, joint="curve")

    # Draw outer vertical edges
    d.line([(left, top_outer), (left, bot_outer)], fill=(255, 255, 255, 255), width=stroke)
    d.line([(right, top_outer), (right, bot_outer)], fill=(255, 255, 255, 255), width=stroke)

    # Draw bottom page curves
    d.line(bot_left_curve, fill=(255, 255, 255, 255), width=stroke, joint="curve")
    d.line(bot_right_curve, fill=(255, 255, 255, 255), width=stroke, joint="curve")

    # Bottom book thickness rim
    rim_dy = h * 0.045
    bot_left_rim = [(px, py + rim_dy) for px, py in bot_left_curve]
    bot_right_rim = [(px, py + rim_dy) for px, py in bot_right_curve]

    d.line([(left, bot_outer), (left, bot_outer + rim_dy)], fill=(255, 255, 255, 255), width=stroke)
    d.line([(right, bot_outer), (right, bot_outer + rim_dy)], fill=(255, 255, 255, 255), width=stroke)
    d.line(bot_left_rim, fill=(255, 255, 255, 255), width=stroke, joint="curve")
    d.line(bot_right_rim, fill=(255, 255, 255, 255), width=stroke, joint="curve")

    # Spine ticks
    d.line([(cx, top_spine), (cx, top_spine + h * 0.065)], fill=(255, 255, 255, 255), width=stroke)
    d.line([(cx, bot_spine - h * 0.04), (cx, bot_spine + rim_dy)], fill=(255, 255, 255, 255), width=stroke)

    # Capital letter 'A' in the center
    a_h = h * 0.44
    a_w = w * 0.30
    a_stroke = max(2, int(w * 0.075))

    a_cy = (top_spine + bot_spine) / 2.0 - h * 0.01
    a_top_y = a_cy - a_h / 2.0
    a_bot_y = a_cy + a_h / 2.0

    a_left_x = cx - a_w / 2.0
    a_right_x = cx + a_w / 2.0

    bar_ratio = 0.62
    bar_y = a_top_y + (a_bot_y - a_top_y) * bar_ratio
    bar_xl = cx - (a_w / 2.0) * bar_ratio
    bar_xr = cx + (a_w / 2.0) * bar_ratio

    d.line([(bar_xl, bar_y), (bar_xr, bar_y)], fill=(255, 255, 255, 255), width=a_stroke)
    d.line([(cx, a_top_y), (a_left_x, a_bot_y)], fill=(255, 255, 255, 255), width=a_stroke)
    d.line([(cx, a_top_y), (a_right_x, a_bot_y)], fill=(255, 255, 255, 255), width=a_stroke)

    return im.resize((target_size, target_size), Image.LANCZOS)


def main():
    pkg_dir = Path("package")
    glyph_dir = pkg_dir / "glyph"
    glyph_dir.mkdir(parents=True, exist_ok=True)

    # 1. 26x26 muOS list glyph
    read_img = render_book_icon(26, scale=32)
    read_img.save(glyph_dir / "read.png")
    print(f"Generated {glyph_dir / 'read.png'} (26x26)")

    # 2. 120x120 muOS list fallback glyph
    glyph_icon_img = render_book_icon(120, scale=8)
    glyph_icon_img.save(glyph_dir / "icon.png")
    print(f"Generated {glyph_dir / 'icon.png'} (120x120)")

    # 3. 128x128 muOS app / install icon
    app_icon_img = render_book_icon(128, scale=8)
    app_icon_img.save(pkg_dir / "icon.png")
    print(f"Generated {pkg_dir / 'icon.png'} (128x128)")


if __name__ == "__main__":
    main()
