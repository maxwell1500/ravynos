#!/usr/bin/env python3
"""Generate the fleet's application icons.

Every icon is a 64x64 RGBA PNG drawn deterministically from the table below:
a rounded-rect badge in the app's colour with a simple vector glyph.  The
image set is what the Dock, Filer and NSBundleReadImage read as
Contents/Resources/icon.png; before this the bundles carried no icon at all
and every Dock tile showed the same grey placeholder.

Usage: python3 make_app_icons.py [--out DIR]
"""
import argparse
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 64
RADIUS = 14


def rounded_badge(draw, colour):
    draw.rounded_rectangle([(2, 2), (SIZE - 3, SIZE - 3)], radius=RADIUS,
                           fill=colour)


def glyph_terminal(draw):
    draw.rectangle([(14, 20), (26, 22)], fill=(126, 231, 135))
    draw.line([(14, 20), (20, 26)], fill=(126, 231, 135), width=3)
    draw.line([(20, 26), (14, 32)], fill=(126, 231, 135), width=3)
    draw.rectangle([(28, 31), (42, 34)], fill=(126, 231, 135))


def glyph_textedit(draw):
    for y in (22, 30, 38, 46):
        draw.rectangle([(16, y), (44, y + 2)], fill=(74, 92, 120))
    draw.polygon([(38, 16), (46, 24), (34, 34), (30, 28)], fill=(43, 108, 214))


def glyph_calculator(draw):
    draw.rectangle([(14, 16), (50, 28)], fill=(230, 232, 236))
    for row in range(3):
        for col in range(3):
            x = 16 + col * 12
            y = 32 + row * 10
            draw.rectangle([(x, y), (x + 8, y + 7)],
                           fill=(255, 149, 0) if col == 2 else (108, 117, 130))


def glyph_preview(draw):
    draw.ellipse([(16, 18), (36, 38)], outline=(247, 247, 247), width=4)
    draw.line([(34, 36), (46, 48)], fill=(247, 247, 247), width=5)
    draw.polygon([(20, 30), (26, 23), (32, 30)], fill=(255, 255, 255))


def glyph_fontbook(draw):
    draw.rectangle([(14, 16), (50, 48)], fill=(247, 243, 232))
    draw.line([(20, 42), (26, 22)], fill=(140, 45, 70), width=3)
    draw.line([(26, 22), (32, 42)], fill=(140, 45, 70), width=3)
    draw.line([(22, 34), (30, 34)], fill=(140, 45, 70), width=3)


def glyph_screenshot(draw):
    for (x, y, dx, dy) in ((16, 16, 1, 1), (48, 16, -1, 1),
                           (16, 48, 1, -1), (48, 48, -1, -1)):
        draw.line([(x, y), (x + 8 * dx, y)], fill=(255, 255, 255), width=3)
        draw.line([(x, y), (x, y + 8 * dy)], fill=(255, 255, 255), width=3)
    draw.ellipse([(26, 26), (38, 38)], outline=(255, 255, 255), width=3)


def glyph_activity(draw):
    points = [(14, 36), (22, 36), (26, 22), (32, 46), (37, 30), (42, 36),
              (50, 36)]
    draw.line(points, fill=(80, 250, 123), width=3)


def glyph_disk(draw):
    draw.rounded_rectangle([(14, 16), (50, 46)], radius=6, fill=(236, 239, 243))
    draw.ellipse([(24, 24), (40, 40)], outline=(150, 160, 172), width=3)
    draw.ellipse([(31, 31), (33, 33)], fill=(80, 160, 120))


def glyph_console(draw):
    for i, y in enumerate((22, 31, 40)):
        draw.rectangle([(16, y), (16 + 22 - i * 5, y + 3)],
                       fill=(240, 200, 90))


def glyph_keychain(draw):
    draw.ellipse([(18, 18), (34, 34)], outline=(250, 214, 96), width=5)
    draw.line([(33, 33), (48, 48)], fill=(250, 214, 96), width=5)
    draw.line([(42, 42), (46, 38)], fill=(250, 214, 96), width=4)
    draw.line([(45, 45), (49, 41)], fill=(250, 214, 96), width=4)


def glyph_archive(draw):
    for y in range(18, 46, 6):
        draw.rectangle([(28, y), (36, y + 3)], fill=(90, 72, 48))


def glyph_preferences(draw):
    draw.ellipse([(20, 20), (44, 44)], outline=(245, 246, 248), width=4)
    draw.ellipse([(28, 28), (36, 36)], fill=(245, 246, 248))
    for (x0, y0, x1, y1) in ((31, 14, 33, 22), (31, 42, 33, 50),
                             (14, 31, 22, 33), (42, 31, 50, 33)):
        draw.rectangle([(x0, y0), (x1, y1)], fill=(245, 246, 248))


ICONS = {
    "com.ravynos.Terminal": ((30, 34, 42), glyph_terminal),
    "com.ravynos.TextEdit": ((247, 243, 232), glyph_textedit),
    "com.ravynos.Calculator": ((45, 49, 57), glyph_calculator),
    "com.ravynos.Preview": ((43, 125, 233), glyph_preview),
    "com.ravynos.FontBook": ((140, 45, 70), glyph_fontbook),
    "com.ravynos.Screenshot": ((59, 73, 144), glyph_screenshot),
    "com.ravynos.ActivityMonitor": ((28, 36, 43), glyph_activity),
    "com.ravynos.DiskUtility": ((200, 207, 216), glyph_disk),
    "com.ravynos.Console": ((38, 33, 28), glyph_console),
    "com.ravynos.KeychainAccess": ((29, 111, 114), glyph_keychain),
    "com.ravynos.ArchiveUtility": ((194, 155, 97), glyph_archive),
    "com.ravynos.Preferences": ((91, 102, 117), glyph_preferences),
}


def render(bundle_id):
    colour, glyph = ICONS[bundle_id]
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rounded_badge(draw, colour)
    glyph(draw)
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(HERE, "work", "icons"))
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for bundle_id in ICONS:
        path = os.path.join(args.out, bundle_id + ".png")
        render(bundle_id).save(path, "PNG")
        print("%s -> %s" % (bundle_id, path))


if __name__ == "__main__":
    main()
