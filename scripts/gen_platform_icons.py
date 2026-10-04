#!/usr/bin/env python3
"""Emit Linux and Windows icon sizes from assets/neurofeed_icon.png.

Android mipmaps and the adaptive foreground come from
`dart run flutter_launcher_icons` (same master). This script does not
read assets/neurofeed_glyph.png and does not write a Windows runner tree.
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "assets" / "neurofeed_icon.png"
HICOLOR_SIZES = (16, 24, 32, 48, 64, 128, 256, 512)
ICO_SIZES = (16, 24, 32, 48, 64, 128, 256)
ICON_NAME = "org.windwerfer.neurofeed.png"
WINDOW_ICON = ROOT / "linux" / "neurofeed.png"
ICO_PATH = ROOT / "windows" / "app_icon.ico"


def resize_rgba(image: Image.Image, size: int) -> Image.Image:
    image = image.convert("RGBA")
    red, green, blue, alpha = image.split()
    red = ImageChops.multiply(red, alpha)
    green = ImageChops.multiply(green, alpha)
    blue = ImageChops.multiply(blue, alpha)
    red = red.resize((size, size), Image.Resampling.LANCZOS)
    green = green.resize((size, size), Image.Resampling.LANCZOS)
    blue = blue.resize((size, size), Image.Resampling.LANCZOS)
    alpha = alpha.resize((size, size), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (size, size))
    src_r, src_g, src_b, src_a = red.load(), green.load(), blue.load(), alpha.load()
    dst = out.load()
    for y in range(size):
        for x in range(size):
            cover = src_a[x, y]
            if cover == 0:
                dst[x, y] = (0, 0, 0, 0)
            else:
                dst[x, y] = (
                    min(255, src_r[x, y] * 255 // cover),
                    min(255, src_g[x, y] * 255 // cover),
                    min(255, src_b[x, y] * 255 // cover),
                    cover,
                )
    return out


def main() -> int:
    if not MASTER.is_file():
        print(f"missing master: {MASTER}", file=sys.stderr)
        return 1
    master = Image.open(MASTER)
    if master.size != (1024, 1024):
        print(f"expected 1024 master, got {master.size}", file=sys.stderr)
        return 1

    for size in HICOLOR_SIZES:
        dest = (
            ROOT
            / "linux"
            / "icons"
            / "hicolor"
            / f"{size}x{size}"
            / "apps"
            / ICON_NAME
        )
        dest.parent.mkdir(parents=True, exist_ok=True)
        resize_rgba(master, size).save(dest, format="PNG")
        print(dest.relative_to(ROOT))

    resize_rgba(master, 512).save(WINDOW_ICON, format="PNG")
    print(WINDOW_ICON.relative_to(ROOT))

    frames = [resize_rgba(master, size) for size in ICO_SIZES]
    frames[-1].save(
        ICO_PATH,
        format="ICO",
        sizes=[(size, size) for size in ICO_SIZES],
        append_images=frames[:-1],
    )
    print(ICO_PATH.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
