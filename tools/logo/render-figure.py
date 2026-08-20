#!/usr/bin/env python3
"""Render the BSDnas figure mark.

The mark is the letters of the product name stacked into a standing figure:
`bsd` across the top as shoulders and arms, `a` for the body, `n` for the
legs. The face and the colour are the ones already used on the login screen
(DejaVu Sans Bold, #E2611F), so the mark and the wordmark belong together.

The `s` — the head — carries an outline in the colour of the body letters.
That outline is not decoration: it separates the head from the shoulders,
which touch it on both sides. Its width is what changes with size, and the
rule comes from looking at the result rather than from taste:

    large      outline 3.3% of the type size   — enough to read, does not fatten the letter
    avatar     outline 5.5%                    — thin lines break into dots at 88px;
                                                 this width closes the gaps and holds the shape
    small      no outline at all               — below ~48px the outline eats the counter
                                                 inside the `s` and the letter becomes a blob

Each size is rendered at its own size. Rendering large and scaling down
hides exactly the defects this is meant to catch.

Usage:
    render-figure.py [output-directory]

Writes the SVG (scalable, for pages and the interface) and the PNG set
(avatar and favicons, where pixels are fixed).
"""

import os
import sys

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_STACK = "DejaVu Sans, Verdana, sans-serif"

ORANGE = "#E2611F"          # the same orange as the login screen wordmark
LIGHT_INK = "#F5F5F5"       # body letters on a dark ground
DARK_INK = "#181210"        # body letters on a light ground
DARK_GROUND = "#0D0D0D"
LIGHT_GROUND = "#F6F3F1"

# vertical gap between the three rows, as a fraction of the type size;
# negative pulls them together so the figure reads as one shape
ROW_GAP = -0.25

OUTLINE_LARGE = 0.033
OUTLINE_AVATAR = 0.055
OUTLINE_NONE = 0.0


def metrics(size):
    """Letter widths at a given type size, measured with the real font."""
    from PIL import ImageFont
    font = ImageFont.truetype(FONT_PATH, size)
    return font, {c: font.getlength(c) for c in ("b", "s", "d", "a", "n", "bs", "bsd")}


def png(path, box, outline=OUTLINE_NONE, ground=DARK_GROUND, ink=LIGHT_INK):
    """One square image, drawn at exactly `box` pixels."""
    from PIL import Image, ImageDraw

    size = int(box * 0.42)
    font, w = metrics(size)
    row = int(size * (1.0 + ROW_GAP))
    image = Image.new("RGB", (box, box), ground)
    draw = ImageDraw.Draw(image)
    x = (box - w["bsd"]) / 2
    y = (box - (row * 2 + size)) / 2

    # shoulders first, then the head over them: the outline reads as a gap
    # between the head and the letters it touches
    draw.text((x, y), "b", font=font, fill=ORANGE)
    draw.text((x + w["bs"], y), "d", font=font, fill=ORANGE)
    stroke = int(round(size * outline))
    if stroke:
        draw.text((x + w["b"], y), "s", font=font, fill=ORANGE,
                  stroke_width=stroke, stroke_fill=ink)
    else:
        draw.text((x + w["b"], y), "s", font=font, fill=ORANGE)

    draw.text(((box - w["a"]) / 2, y + row), "a", font=font, fill=ink)
    draw.text(((box - w["n"]) / 2, y + row * 2), "n", font=font, fill=ink)
    image.save(path)


def svg(path, outline=OUTLINE_LARGE, ground=None, ink=LIGHT_INK):
    """Scalable version. Text stays text — the same way the login logo does it.

    paint-order="stroke" puts the outline underneath the fill, so the letter
    keeps its shape and the outline only shows outside it.
    """
    size = 100
    _, w = metrics(size)
    row = int(size * (1.0 + ROW_GAP))
    pad = size * 0.18
    width = w["bsd"] + pad * 2
    height = row * 2 + size * 1.02 + pad * 2
    baseline = pad + size * 0.78          # cap height for this face
    x = pad
    stroke = size * outline

    def letter(char, cx, cy, fill, stroked=False):
        extra = ''
        if stroked and stroke:
            extra = (' stroke="%s" stroke-width="%.2f" paint-order="stroke"'
                     ' stroke-linejoin="round"' % (ink, stroke * 2))
        return ('  <text x="%.2f" y="%.2f" font-family="%s" font-size="%d" '
                'font-weight="700" fill="%s"%s>%s</text>'
                % (cx, cy, FONT_STACK, size, fill, extra, char))

    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f" '
           'role="img" aria-label="BSDnas">' % (width, height),
           '  <title>BSDnas</title>']
    if ground:
        out.append('  <rect width="100%%" height="100%%" fill="%s"/>' % ground)
    out.append(letter("b", x, baseline, ORANGE))
    out.append(letter("d", x + w["bs"], baseline, ORANGE))
    out.append(letter("s", x + w["b"], baseline, ORANGE, stroked=True))
    out.append(letter("a", (width - w["a"]) / 2, baseline + row, ink))
    out.append(letter("n", (width - w["n"]) / 2, baseline + row * 2, ink))
    out.append("</svg>")
    open(path, "w").write("\n".join(out) + "\n")


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    join = lambda name: os.path.join(out_dir, name)

    svg(join("bsdnas-figure.svg"), ink=LIGHT_INK)
    svg(join("bsdnas-figure-onlight.svg"), ink=DARK_INK)

    png(join("bsdnas-avatar.png"), 400, outline=OUTLINE_AVATAR)
    png(join("bsdnas-avatar-88.png"), 88, outline=OUTLINE_AVATAR)
    png(join("bsdnas-favicon-48.png"), 48, outline=OUTLINE_NONE)
    png(join("bsdnas-favicon-32.png"), 32, outline=OUTLINE_NONE)
    png(join("bsdnas-favicon-16.png"), 16, outline=OUTLINE_NONE)

    print("written to %s" % out_dir)


if __name__ == "__main__":
    main()
