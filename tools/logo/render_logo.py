#!/usr/bin/env python3
"""Render the BSDnas text logo from a FreeBSD console font.

The logo is the three letters of "bsd" arranged as a face: 'b' and 'd' are the
eyes (their bowls face inward), 's' is the nose, set below them. The glyphs are
not drawn by hand — they are taken straight out of a vt(4) console font that
ships with FreeBSD, so the shapes are the ones the system itself renders.

Usage:
    render_logo.py [font.fnt] [gap] [drop]

    font    vt font file, default /usr/share/vt/fonts/terminus-b32.fnt (bold)
    gap     columns between the eyes, default 14
    drop    rows the nose sits below the top of the eyes, default 16

Two output rows are packed into one line of half-block characters, which keeps
the proportions right in a terminal.
"""
import struct
import sys

DEFAULT_FONT = "/usr/share/vt/fonts/terminus-b32.fnt"


def load(path):
    """Parse a vt(4) font (VFNT0002): header, glyph bitmaps, character map."""
    data = open(path, "rb").read()
    if data[:8] != b"VFNT0002":
        raise SystemExit("%s is not a VFNT0002 font" % path)
    width, height = data[8], data[9]
    (glyph_count,) = struct.unpack(">I", data[12:16])
    map_counts = struct.unpack(">4I", data[16:32])
    stride = (width + 7) // 8
    offset = 32
    glyphs = data[offset:offset + glyph_count * stride * height]
    offset += glyph_count * stride * height
    charmap = {}
    for i in range(map_counts[0]):          # map 0 is the normal (non-bold) map
        src, dst, run = struct.unpack(">IHH", data[offset + i * 8:offset + i * 8 + 8])
        for k in range(run + 1):
            charmap[src + k] = dst + k
    return width, height, stride, glyphs, charmap


def glyph(char, width, height, stride, glyphs, charmap):
    index = charmap[ord(char)]
    rows = []
    for y in range(height):
        base = index * stride * height + y * stride
        bits = "".join(format(glyphs[base + s], "08b") for s in range(stride))
        rows.append(bits[:width])
    return rows


def crop(rows):
    while rows and "1" not in rows[0]:
        rows = rows[1:]
    while rows and "1" not in rows[-1]:
        rows = rows[:-1]
    left = min(r.index("1") for r in rows if "1" in r)
    right = max(len(r) - 1 - r[::-1].index("1") for r in rows if "1" in r)
    return [r[left:right + 1] for r in rows]


def compose(font, gap, drop):
    width, height, stride, glyphs, charmap = load(font)
    letters = {c: crop(glyph(c, width, height, stride, glyphs, charmap)) for c in "bsd"}
    eye_w, eye_h = len(letters["b"][0]), len(letters["b"])
    nose_w, nose_h = len(letters["s"][0]), len(letters["s"])
    canvas_w = eye_w + gap + len(letters["d"][0])
    canvas_h = max(eye_h, drop + nose_h)
    canvas = [[" "] * canvas_w for _ in range(canvas_h)]

    def blit(rows, x0, y0):
        for y, row in enumerate(rows):
            for x, bit in enumerate(row):
                if bit == "1":
                    canvas[y0 + y][x0 + x] = "#"

    blit(letters["b"], 0, 0)
    blit(letters["d"], eye_w + gap, 0)
    blit(letters["s"], (canvas_w - nose_w) // 2, drop)
    return ["".join(row) for row in canvas]


def to_half_blocks(rows):
    width = max(len(r) for r in rows)
    rows = [r.ljust(width) for r in rows]
    if len(rows) % 2:
        rows.append(" " * width)
    out = []
    for i in range(0, len(rows), 2):
        top, bottom = rows[i], rows[i + 1]
        line = ""
        for x in range(width):
            t, b = top[x] != " ", bottom[x] != " "
            line += "█" if t and b else "▀" if t else "▄" if b else " "
        out.append(line.rstrip())
    return out


def main():
    font = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FONT
    gap = int(sys.argv[2]) if len(sys.argv) > 2 else 14
    drop = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    print("\n".join(to_half_blocks(compose(font, gap, drop))))


if __name__ == "__main__":
    main()
