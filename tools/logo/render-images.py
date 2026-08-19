#!/usr/bin/env python3
"""Render the BSDnas face logo as images (SVG for pages, PNG for avatars).

Same construction as render_logo.py: the letters come out of a vt(4) console
font shipped with FreeBSD, 'b' and 'd' are the eyes and 's' is the nose. Here
each font pixel becomes a square, so the result keeps the blocky look without
depending on how a viewer spaces its text lines — a text logo built from half
blocks grows white seams wherever line-height is not exactly 1, which is the
case in most Markdown renderers.

Usage:
    render-images.py [output-directory]

Writes bsdnas-logo.svg, bsdnas-avatar.png and bsdnas-avatar-wordmark.png.
"""
import sys
import os

from render_logo import DEFAULT_FONT, compose, load, glyph, crop

RED = (171, 43, 40)          # the FreeBSD red
RED_HEX = "#AB2B28"
INK = (225, 225, 225)
BACKGROUND = (13, 13, 13)


def face(font, gap=14, drop=16):
    rows = compose(font, gap, drop)
    width = max(len(r) for r in rows)
    return [r.ljust(width) for r in rows]


def word(text, font, spacing=2):
    """Lay out a word in the same font, glyphs bottom-aligned."""
    w, h, stride, glyphs, charmap = load(font)
    letters = [crop(glyph(c, w, h, stride, glyphs, charmap)) for c in text]
    height = max(len(g) for g in letters)
    padded = []
    for g in letters:
        top_pad = [" " * len(g[0])] * (height - len(g))
        padded.append(top_pad + [r.replace("1", "#").replace("0", " ") for r in g])
    rows = []
    for y in range(height):
        rows.append((" " * spacing).join(g[y] for g in padded))
    width = max(len(r) for r in rows)
    return [r.ljust(width) for r in rows]


def svg(path, font, cell=12, pad=2):
    rows = face(font)
    w = (max(len(r) for r in rows) + 2 * pad) * cell
    h = (len(rows) + 2 * pad) * cell
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" '
           'width="%d" height="%d" role="img" aria-label="BSDnas">' % (w, h, w, h),
           "<title>BSDnas</title>", '<g fill="%s">' % RED_HEX]
    for y, row in enumerate(rows):
        x = 0
        while x < len(row):
            if row[x] != " ":
                run = 1
                while x + run < len(row) and row[x + run] != " ":
                    run += 1
                out.append('<rect x="%d" y="%d" width="%d" height="%d"/>'
                           % ((x + pad) * cell, (y + pad) * cell, run * cell, cell))
                x += run
            else:
                x += 1
    out.append("</g></svg>")
    open(path, "w").write("\n".join(out) + "\n")


def png(path, font, side=800, face_cell=17, word_cell=0, gap_px=0):
    from PIL import Image, ImageDraw

    blocks = [(face(font), face_cell, RED)]
    if word_cell:
        blocks.append((word("bsdnas", font), word_cell, INK))
    total_h = sum(len(rows) * cell for rows, cell, _ in blocks) + gap_px
    image = Image.new("RGB", (side, side), BACKGROUND)
    draw = ImageDraw.Draw(image)
    y = (side - total_h) // 2
    for rows, cell, color in blocks:
        x0 = (side - max(len(r) for r in rows) * cell) // 2
        for row_index, row in enumerate(rows):
            for col, ch in enumerate(row):
                if ch != " ":
                    px, py = x0 + col * cell, y + row_index * cell
                    draw.rectangle([px, py, px + cell - 1, py + cell - 1], fill=color)
        y += len(rows) * cell + gap_px
    image.save(path)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    font = os.environ.get("VT_FONT", DEFAULT_FONT)
    svg(os.path.join(out_dir, "bsdnas-logo.svg"), font)
    png(os.path.join(out_dir, "bsdnas-avatar.png"), font, face_cell=17)
    png(os.path.join(out_dir, "bsdnas-avatar-wordmark.png"), font,
        face_cell=15, word_cell=7, gap_px=70)


if __name__ == "__main__":
    main()
