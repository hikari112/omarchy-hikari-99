#!/usr/bin/env python3
"""Pre-draw the Hikari 99 boot screen and write its Plymouth script.

Plymouth has no shaders and no clock, so everything the Hikari 99 lock screen
works out live is drawn here ahead of time, on the same pixel grid (the art is
800 pixels across) and in the same process (4 bits per channel, noise
dithered):

  the sky      eight frames in which a fifth of the cells change every second,
               each at its own moment, the way the shader re-rolls its dither;
               光's deep periwinkle glow is part of it
  光           each of its six strokes in six steps, for writing it in order
  the prompt   pencil 〇 marks (half drawn, then whole), the line of light, the
               breathing cursor, the words
  the events   the cloud shadow of a wrong passphrase, the light that floods
               in when the clouds part, 光 lighting up while the disk checks

usage: render.py <out-dir> <wallpaper> <colors-json> <fonts-json> <sizes>
  sizes: comma separated, WIDTHxHEIGHT (or a bare width for 16:9), one
  drawing set each; every screen at boot uses the set nearest its size
Only PIL is needed.
"""
import json
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

out, wallpaper, colors_json, fonts_json, sizes_arg = sys.argv[1:6]
C = json.loads(colors_json)
F = json.loads(fonts_json)


def parse_size(s):
    w, _, h = s.strip().lower().partition("x")
    return int(w), int(h) if h else round(int(w) * 9 / 16)


SIZES = list(dict.fromkeys(parse_size(s) for s in sizes_arg.split(",") if s.strip()))
HERE = os.path.dirname(os.path.realpath(__file__))
STROKES = json.load(open(os.path.join(HERE, "strokes.json")))
SEGMENTS = 6       # steps per stroke when 光 is written
FRAMES = 8         # sky frames; shown four a second
os.makedirs(out, exist_ok=True)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


NIGHT = rgb(C["night"])
ACCENT = rgb(C["accent"])
LILAC = rgb(C["lilac"])
LIGHT = rgb(C["light"])
INK = rgb(C["ink"])
ERROR = rgb(C["error"])
DEEP = mix(ACCENT, NIGHT, 0.55)          # 光's glow on a bright cloud
SHADOW_NAVY = (5, 10, 36)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def stroke_width(kind, u):
    """The textbook hand: a press to start, a sweep that thins out, a dot that
    presses in, a hook that flicks off (the same profile as the lock screen)."""
    if kind == "㇒":
        return max(0.18, 1.08 - 0.9 * u ** 1.5)
    if kind == "㇔":
        return 0.55 + 0.6 * u
    if kind == "㇟":
        return max(0.2, 1 - (u - 0.9) * 8) if u > 0.9 else 1.02 - 0.1 * min(1, u * 6)
    return 1.12 - 0.14 * min(1, u * 5) + ((u - 0.94) * 2 if u > 0.94 else 0)


def stroke_progress(kind, u):
    if kind == "㇒":
        return u ** 1.45
    return 2 * u * u if u < 0.5 else 1 - 2 * (1 - u) * (1 - u)


def draw_stroke(draw, stroke, reach, x0, y0, k):
    """Draw the first `reach` (0..1) of a stroke with its width profile."""
    pts = stroke["points"]
    n = len(pts)
    last = reach * (n - 1)
    base = 5.4 * k
    for j in range(int(math.ceil(last))):
        f = min(1.0, last - j)
        ax, ay = x0 + pts[j][0] * k, y0 + pts[j][1] * k
        bx = ax + (x0 + pts[j + 1][0] * k - ax) * f
        by = ay + (y0 + pts[j + 1][1] * k - ay) * f
        w = base * stroke_width(stroke["type"], (j + f) / (n - 1))
        draw.line([(ax, ay), (bx, by)], fill=255, width=max(1, int(round(w))))
        r = w / 2
        draw.ellipse([ax - r, ay - r, ax + r, ay + r], fill=255)
        draw.ellipse([bx - r, by - r, bx + r, by + r], fill=255)


def to_grid_mask(img_l, cols, rows, threshold=0.5):
    """A full-resolution drawing to the art's grid: a cell is lit when the
    drawing covers at least `threshold` of it."""
    small = img_l.resize((cols, rows), Image.BOX)
    cut = int(threshold * 255)
    return small.point(lambda v: 255 if v >= cut else 0)


def sprite_from_grid(mask_grid, color, cell, box, alpha=255):
    """Cells of mask_grid inside box (grid units) as an RGBA sprite at screen
    size, hard-edged."""
    region = mask_grid.crop(box)
    w, h = region.size
    a = region.point(lambda v: alpha if v else 0).resize((w * cell, h * cell), Image.NEAREST)
    solid = Image.new("RGB", a.size, tuple(int(round(c)) for c in color))
    img = solid.convert("RGBA")
    img.putalpha(a)
    return img


def text_image(text, font_path, size, color, alpha=1.0, spacing=0.0):
    """Words on the glass: crisp text with the soft navy shadow the lock
    screen gives its words."""
    font = ImageFont.truetype(font_path, size)
    chars = list(text)
    widths = [font.getlength(ch) for ch in chars]
    tw = int(math.ceil(sum(widths) + spacing * max(0, len(chars) - 1)))
    asc, desc = font.getmetrics()
    pad = max(4, size // 3)
    W, H = tw + pad * 2, asc + desc + pad * 2

    def paint(fill):
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x = pad
        for ch, cw in zip(chars, widths):
            d.text((x, pad), ch, font=font, fill=fill)
            x += cw + spacing
        return layer

    shadow = paint(SHADOW_NAVY + (int(140 * alpha),)).filter(ImageFilter.GaussianBlur(max(1.5, size * 0.08)))
    shadow = Image.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, 0)), shadow)
    offset = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    offset.paste(shadow, (0, max(1, size // 24)))
    text_layer = paint(tuple(int(c) for c in color) + (int(255 * alpha),))
    return Image.alpha_composite(offset, text_layer)


def save(img, name):
    img.save(os.path.join(out, name), compress_level=9)


layout = {}
rng = random.Random(99)

for W, H in SIZES:
    cell = max(1, round(W / 800))
    cols = (W + cell - 1) // cell
    rows = (H + cell - 1) // cell
    u = round(min(H * 0.27, W * 0.2))
    kanji_top = round(H / 2 + u * 0.1 - u)
    kanji_x = round((W - u) / 2)
    tag = f"{W}x{H}"

    # ---- 光, whole, on the grid (for the glow and the grid box)
    full = Image.new("L", (W, H), 0)
    fd = ImageDraw.Draw(full)
    k = u / 109
    for s in STROKES:
        draw_stroke(fd, s, 1.0, kanji_x, kanji_top, k)
    kanji_grid = to_grid_mask(full, cols, rows, 0.45)
    # The grid box round 光, with room for its sweep and hook
    gx0 = max(0, kanji_x // cell - 2)
    gy0 = max(0, kanji_top // cell - 2)
    gx1 = min(cols, (kanji_x + u) // cell + 3)
    gy1 = min(rows, (kanji_top + u) // cell + 3)
    kbox = (gx0, gy0, gx1, gy1)

    # ---- the sky, at the grid: the wallpaper averaged down (like reading a
    # few mip levels down), the shade in the middle, 光's glow
    wall = Image.open(wallpaper).convert("RGB")
    ww, wh = wall.size
    s = max(cols / ww, rows / wh)
    cw, ch = int(math.ceil(cols / s)), int(math.ceil(rows / s))
    wall = wall.crop(((ww - cw) // 2, (wh - ch) // 2, (ww - cw) // 2 + cw, (wh - ch) // 2 + ch))
    grid = wall.resize((cols, rows), Image.BOX)
    halo = kanji_grid.filter(ImageFilter.GaussianBlur(max(1.0, 0.045 * u / cell)))
    gp = grid.load()
    hp = halo.load()
    base = []
    for y in range(rows):
        vy = (y + 0.5) / rows
        row = []
        for x in range(cols):
            vx = (x + 0.5) / cols
            r, g, b = gp[x, y]
            mx, my = (vx - 0.5) * 1.5, (vy - 0.5) * 1.35
            shade = 1 - 0.24 * math.exp(-(mx * mx + my * my) * 3.2)
            c = (r / 255 * shade, g / 255 * shade, b / 255 * shade)
            hv = min(0.6, hp[x, y] / 255 * 1.4)
            c = tuple(a + (d / 255 - a) * hv for a, d in zip(c, DEEP))
            row.append(c)
        base.append(row)

    # Two dithers of the same picture. A fifth of the cells... more exactly:
    # 40% of cells take part, each swapping between its two dithers twice per
    # 8-frame cycle at its own phase; about half of those swaps change the
    # level, so about a fifth of the cells change each second at four frames
    # a second, like the shader's re-roll.
    def dither(seed):
        rr = random.Random(seed)
        img = Image.new("RGB", (cols, rows))
        px = img.load()
        for y in range(rows):
            row = base[y]
            for x in range(cols):
                c = row[x]
                px[x, y] = tuple(int(min(15, max(0, math.floor(v * 15 + rr.random())))) * 17 for v in c)
        return img

    dA = dither(1)
    dB = dither(2)
    phases = Image.new("L", (cols, rows))
    ph = phases.load()
    pr = random.Random(3)
    for y in range(rows):
        for x in range(cols):
            ph[x, y] = pr.randrange(FRAMES) + 1 if pr.random() < 0.4 else 0
    for f in range(FRAMES):
        # Cell uses dither B while (f - phase) mod 8 is in the first half
        mask = phases.point(lambda p, f=f: 255 if p and ((f - (p - 1)) % FRAMES) < FRAMES // 2 else 0)
        frame = Image.composite(dB, dA, mask)
        big = frame.resize((cols * cell, rows * cell), Image.NEAREST).crop((0, 0, W, H))
        save(big, f"h99-{tag}-sky-{f}.png")

    # ---- 光, stroke by stroke: each stroke in SEGMENTS steps, one sprite each
    for i, st in enumerate(STROKES):
        for j in range(SEGMENTS):
            reach = stroke_progress(st["type"], (j + 1) / SEGMENTS)
            canvas = Image.new("L", (W, H), 0)
            draw_stroke(ImageDraw.Draw(canvas), st, reach, kanji_x, kanji_top, k)
            g = to_grid_mask(canvas, cols, rows, 0.45)
            save(sprite_from_grid(g, LIGHT, cell, kbox), f"h99-{tag}-k{i}-{j}.png")

    # 光 lighting up: a light, lilac glow round the whole character
    bloom_a = kanji_grid.filter(ImageFilter.GaussianBlur(max(1.5, 0.07 * u / cell))).crop(kbox)
    bw, bh = bloom_a.size
    bloom_a = bloom_a.point(lambda v: min(255, int(v * 2.2))).resize((bw * cell, bh * cell), Image.NEAREST)
    bloom = Image.new("RGB", bloom_a.size, tuple(int(c) for c in mix(LIGHT, LILAC, 0.4))).convert("RGBA")
    bloom.putalpha(bloom_a)
    save(bloom, f"h99-{tag}-bloom.png")

    # ---- the prompt: a line of light, pencil 〇 marks, the cursor
    step = max(cell * 4, round(u * 0.1 / cell) * cell)
    slots = 20
    marks_top = round((kanji_top + u + u * 0.1) / cell) * cell
    line_w = slots * step
    line_h = cell
    line = Image.new("RGBA", (line_w, line_h))
    lp = line.load()
    for x in range(line_w):
        t = x / (line_w - 1)
        a = smoothstep(0.0, 0.25, t) * (1 - smoothstep(0.75, 1.0, t)) * 0.6
        for y in range(line_h):
            lp[x, y] = LIGHT + (int(255 * a),)
    save(line, f"h99-{tag}-line.png")
    cursor = Image.new("RGBA", (cell, max(cell * 3, round(step * 0.5 / cell) * cell)), LIGHT + (255,))
    save(cursor, f"h99-{tag}-cursor.png")

    gcells = step // cell
    for v in range(4):
        seed = abs(math.sin((v + 1) * 12.9898) * 43758.5453) % 1
        for f, sweep in enumerate((0.55, 1.0)):
            canvas = Image.new("L", (step, step), 0)
            d = ImageDraw.Draw(canvas)
            cx = step / 2 + (seed - 0.5) * step * 0.06
            cy = step / 2 + ((seed * 7) % 1 - 0.5) * step * 0.06
            rx = step * (0.25 + seed * 0.03)
            ry = step * (0.23 + ((seed * 3) % 1) * 0.04)
            start = -110 + seed * 40
            end = start + (335 + seed * 25) * sweep
            d.arc([cx - rx, cy - ry, cx + rx, cy + ry], start, end, fill=255, width=max(1, int(round(cell * 1.15))))
            g = to_grid_mask(canvas, gcells, gcells, 0.35)
            save(sprite_from_grid(g, LIGHT, cell, (0, 0, gcells, gcells)), f"h99-{tag}-mark{v}-{f}.png")

    # ---- words
    klee = F["klee"]
    murecho = F["murecho"]
    furi = text_image("ひかり", klee, round(u * 0.075), INK, 0.75, u * 0.035)
    save(furi, f"h99-{tag}-furigana.png")
    words = {
        "greet": text_image("おかえりなさい", klee, round(u * 0.06), INK, 0.9, u * 0.01),
        "hint": text_image("Type your passphrase", murecho, max(12, round(u * 0.034)), INK, 0.8, 1),
        "checkjp": text_image("確認中…", klee, round(u * 0.06), INK, 0.9, u * 0.01),
        "checken": text_image("Checking…", murecho, max(12, round(u * 0.034)), INK, 0.8, 1),
        "wrongjp": text_image("もう一度どうぞ", klee, round(u * 0.06), ERROR, 0.95, u * 0.01),
        "wrongen": text_image("Wrong passphrase, try again", murecho, max(12, round(u * 0.034)), ERROR, 0.9, 1),
        "caps": text_image("CAPS", murecho, max(12, round(u * 0.034)), INK, 0.85, 2),
    }
    for name, img in words.items():
        save(img, f"h99-{tag}-{name}.png")

    # ---- the lilac corner, breathing: a soft light from the lower left
    gw, gh = round(W * 0.62), round(H * 0.7)
    glow = Image.new("RGBA", (gw // 4, gh // 4))
    gpx = glow.load()
    warm = mix(LILAC, LIGHT, 0.45)
    aspect = W / H
    qw, qh = gw // 4, gh // 4
    for y in range(qh):
        vy = (H - gh + (y + 0.5) * 4) / H
        for x in range(qw):
            vx = ((x + 0.5) * 4) / W
            dl2 = (vx * aspect - 0.08 * aspect) ** 2 + (vy - 0.98) ** 2
            # fade out toward the image's right and top edges: no hard line
            edge = smoothstep(1.0, 0.8, x / qw) * smoothstep(0.0, 0.2, y / qh)
            a = math.exp(-dl2 * 0.9) * 0.3 * edge
            gpx[x, y] = tuple(int(c) for c in warm) + (int(255 * a),)
    save(glow.resize((gw, gh), Image.BILINEAR), f"h99-{tag}-glow.png")

    # ---- a wrong passphrase: the shadow of a cloud, a slanted soft band
    # (drawn at a quarter size and scaled up: it is all soft gradient)
    def slanted_band(width, color, peak):
        q = 4
        full_w = width + round(H * 0.35)
        img_q = Image.new("RGBA", (full_w // q, H // q))
        pq = img_q.load()
        for y in range(H // q):
            lean = (H / 2 - y * q) * 0.35
            for x in range(full_w // q):
                d = abs(x * q - full_w / 2 - lean)
                pq[x, y] = tuple(int(c) for c in color) + (int(255 * smoothstep(width / 2, 0, d) * peak),)
        return img_q.resize((full_w, H), Image.BILINEAR)

    band = slanted_band(round(H * 0.75), SHADOW_NAVY, 0.45)
    save(band, f"h99-{tag}-shadow.png")

    # ---- the unlock: a band of light along the slant (two of them part)
    fl = mix(LIGHT, LILAC, 0.22)
    flood = slanted_band(round(H * 0.5), fl, 0.85)
    save(flood, f"h99-{tag}-flood.png")
    save(Image.new("RGBA", (8, 8), tuple(int(c) for c in fl) + (255,)), f"h99-{tag}-light.png")

    layout[tag] = {
        "W": W, "H": H, "cell": cell, "u": u,
        "kx": gx0 * cell, "ky": gy0 * cell,
        "furi_y": kanji_top - furi.size[1] + round(u * 0.02),
        "step": step, "slots": slots, "marks_top": marks_top,
        "line_y": marks_top + round(step * 0.95 / cell) * cell,
        "hints_top": marks_top + step + round(u * 0.09),
        "hint_gap": round(u * 0.015),
        "shadow_w": band.size[0], "flood_w": flood.size[0],
        "glow_w": gw, "glow_h": gh,
    }

json.dump(layout, open(os.path.join(out, "layout.json"), "w"), indent=1)

# ---------------------------------------------------------------- the script
def floats(c):
    return ", ".join("%.3f" % (v / 255) for v in c)


def schedule():
    """When each stroke starts and how long it takes, in 50 Hz ticks: the
    lock screen's timing (220 ms + 8 ms per unit of length, a 150 ms lift
    between strokes), starting 0.7 s in."""
    out_, at = [], 700
    for st in STROKES:
        dur = 220 + st["length"] * 8
        out_.append((round(at / 20), max(1, round(dur / 20))))
        at += dur + 150
    return out_


SCH = schedule()
WRITE_END = SCH[-1][0] + SCH[-1][1]


# One complete scene per screen: see script_multi.py
sys.path.insert(0, HERE)
from script_multi import write_script  # noqa: E402

write_script(out, layout, STROKES, SEGMENTS, FRAMES, SCH, NIGHT, INK)

# The explorer's preview, 720 x 405: the 16:9 set nearest 1920 wide (or the
# nearest to 1920 x 1080)
tag = min(layout, key=lambda t: (abs(layout[t]["W"] * 9 - layout[t]["H"] * 16) > layout[t]["W"] // 50,
                                 abs(layout[t]["W"] - 1920) + abs(layout[t]["H"] - 1080)))
L = layout[tag]
prev = Image.open(os.path.join(out, f"h99-{tag}-sky-0.png")).convert("RGBA")
for i in range(len(STROKES)):
    prev.alpha_composite(Image.open(os.path.join(out, f"h99-{tag}-k{i}-{SEGMENTS - 1}.png")), (L["kx"], L["ky"]))
furi = Image.open(os.path.join(out, f"h99-{tag}-furigana.png"))
prev.alpha_composite(furi, ((L["W"] - furi.size[0]) // 2, L["furi_y"]))
line = Image.open(os.path.join(out, f"h99-{tag}-line.png"))
lx = (L["W"] - line.size[0]) // 2 // L["cell"] * L["cell"]
prev.alpha_composite(line, (lx, L["line_y"]))
for i in range(4):
    m = Image.open(os.path.join(out, f"h99-{tag}-mark{i}-1.png"))
    prev.alpha_composite(m, ((L["W"] - 4 * L["step"]) // 2 // L["cell"] * L["cell"] + i * L["step"], L["marks_top"]))
greet = Image.open(os.path.join(out, f"h99-{tag}-greet.png"))
prev.alpha_composite(greet, ((L["W"] - greet.size[0]) // 2, L["hints_top"]))
hint = Image.open(os.path.join(out, f"h99-{tag}-hint.png"))
prev.alpha_composite(hint, ((L["W"] - hint.size[0]) // 2, L["hints_top"] + greet.size[1] + L["hint_gap"]))
pw, ph = prev.size
cw, ch = min(pw, ph * 16 // 9), min(ph, pw * 9 // 16)   # cut to 16:9 round the middle
thumb = prev.crop(((pw - cw) // 2, (ph - ch) // 2, (pw - cw) // 2 + cw, (ph - ch) // 2 + ch))
thumb.convert("RGB").resize((720, 405), Image.LANCZOS).save(os.path.join(out, "preview.png"))
prev.convert("RGB").save(os.path.join(out, "preview-full.png"))
print(json.dumps({k: {"W": v["W"], "cell": v["cell"], "u": v["u"]} for k, v in layout.items()}))
