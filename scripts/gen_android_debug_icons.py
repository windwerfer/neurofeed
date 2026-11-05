#!/usr/bin/env python3
"""Emit debug-only Android launcher mipmaps with an orange 'DEBUG' banner.

Source: assets/neurofeed_icon.png (same master as the release icons).
Output: apps/neurofeed-android/android/app/src/debug/res/mipmap-*/ic_launcher.png
These override src/main/res only for the debug build type; release is untouched.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_platform_icons import MASTER, ROOT, resize_rgba  # noqa: E402

RES = ROOT / "apps" / "neurofeed-android" / "android" / "app" / "src" / "debug" / "res"
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FONTS = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "DejaVuSans-Bold.ttf",
)


def font(size: int) -> ImageFont.FreeTypeFont:
    for name in FONTS:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def badge(master: Image.Image) -> Image.Image:
    img = master.convert("RGBA").copy()
    w, h = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    # Rounded banner across the lower part, kept inside the icon margins.
    top, bottom, mx = int(h * 0.66), int(h * 0.90), int(w * 0.08)
    d.rounded_rectangle((mx, top, w - mx, bottom), radius=int(h * 0.06),
                        fill=(235, 72, 20, 255), outline=(255, 255, 255, 255),
                        width=int(w * 0.018))
    f = font(int((bottom - top) * 0.72))
    d.text((w / 2, (top + bottom) / 2), "DEBUG", font=f, anchor="mm",
           fill=(255, 255, 255, 255))
    return Image.alpha_composite(img, overlay)


def main() -> int:
    debug = badge(Image.open(MASTER))
    for dens, size in DENSITIES.items():
        dest = RES / f"mipmap-{dens}" / "ic_launcher.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        resize_rgba(debug, size).save(dest, format="PNG")
        print(dest.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
