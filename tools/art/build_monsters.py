"""Monster sprites in the paper-doll style.

Same rules as tools/art/build_paperdoll.py: bold ink outline, flat fills, one
contour crescent of shade on the lower right, tall pill eyes, no limbs, no
held items, and four facings with the light always from the top-left (west
is drawn, never mirrored).

Humanoids reuse the paper-doll torso and add species features (ears, snout,
tusks, horns, spots). Beasts are a body, a head and a tail. Bosses are drawn
on the same 64-unit grid and rasterised larger.

Run: python3 tools/art/build_monsters.py
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402

ROOT = flat.ROOT
OUT = ROOT / "assets/monsters-v1"
REVIEW = ROOT / "docs/art/monsters-v1"
INK = flat.INK
LINE = flat.LINE
FACINGS = ("south", "east", "west", "north")
BOTTOM = doll.BOTTOM


def shaded(uid, path, fill, shade, dx=3.0, dy=2.3):
    return doll.shaded(uid, path, fill, shade, dx, dy)


def ellipse(cx, cy, rx, ry):
    return f"M{cx - rx} {cy} A{rx} {ry} 0 1 0 {cx + rx} {cy} A{rx} {ry} 0 1 0 {cx - rx} {cy} Z"


def poly(points):
    return "M" + " L".join(f"{x} {y}" for x, y in points) + " Z"


def pills(cx, cy, facing, color=INK, gap=3.0, h=6.4):
    turn = {"east": 1, "west": -1}.get(facing, 0)
    if facing == "north":
        return ""
    if facing == "south":
        spots = [(cx - gap, 3.2), (cx + gap, 3.2)]
    else:
        spots = [(cx + 0.8 * turn, 3.2), (cx + 5.6 * turn, 2.6)]
    return "".join(f'<rect x="{x - w / 2}" y="{cy - h / 2}" width="{w}" height="{h}" rx="{w / 2}" fill="{color}"/>' for x, w in spots)


def shadow(rx, cy=BOTTOM + 2):
    return f'<ellipse cx="32" cy="{cy}" rx="{rx}" ry="3.6" fill="#000" fill-opacity="0.2"/>'


def wrap(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>'


# --- humanoids -------------------------------------------------------------

def humanoid(uid, facing, frame, skin, cloth, ears=None, snout=None, tusks=False, horns=False,
             spots=None, brows=False, eye=INK, mark="", ear_scale=1.0, beard=None):
    s, h, b, top, r = frame
    turn = {"east": 1, "west": -1}.get(facing, 0)
    side = turn != 0
    if side:
        s, h, b = s * 0.72, h * 0.78, b * 0.8
    hx, hy = 32 + 2.5 * turn, top - r + 4
    parts = [shadow(max(s, h) + 4)]
    parts.append(shaded(uid + "b", doll.torso(32, top, s, h, b), *cloth))
    parts.append(mark)
    behind, front = [], []
    if ears == "pointy":
        tip = 0.75 + 1.25 * ear_scale
        left = [(hx - r * 0.75, hy - r * 0.35), (hx - r * tip, hy - r * (0.35 + 0.7 * ear_scale)), (hx - r * 0.55, hy + r * 0.35)]
        right = [(2 * hx - x, y) for x, y in left]
        chosen = {"south": [left, right], "north": [left, right], "east": [left], "west": [right]}[facing]
        for i, ear in enumerate(chosen):
            behind.append(shaded(f"{uid}e{i}", poly(ear), *skin, 1.6, 1.2))
    elif ears == "round":
        spots_ = {"south": [-1, 1], "north": [-1, 1], "east": [-1], "west": [1]}[facing]
        for i, sx in enumerate(spots_):
            behind.append(shaded(f"{uid}e{i}", ellipse(hx + sx * r * 0.7, hy - r * 0.8, r * 0.38, r * 0.42), *skin, 1.4, 1.2))
    if horns:
        for i, sx in enumerate((-1, 1)):
            base = hx + sx * r * 0.45
            behind.append(shaded(f"{uid}h{i}", poly([(base - 2.2, hy - r * 0.8), (base + sx * 3.5, hy - r * 1.55), (base + 2.2, hy - r * 0.7)]),
                                 "#efe2c0", "#d2c29a", 1, 1))
    parts += behind
    parts.append(shaded(uid + "h", ellipse(hx, hy, r, r), *skin, 2.6, 2.2))
    if spots:
        for i, (dx, dy, rr) in enumerate(spots):
            if facing == "north" or abs(dx) < r * 0.9:
                front.append(f'<circle cx="{hx + dx * (1 if turn >= 0 else -1)}" cy="{hy + dy}" r="{rr}" fill="{skin[1]}"/>')
    eye_y = hy - (2.4 if beard else 1.4 if snout else 0)
    if beard and facing != "north":
        bx = hx + turn * r * 0.25
        front.append(shaded(uid + "d", f"M{bx - r * 0.78} {hy + r * 0.32} Q{bx} {hy + r * 0.62} {bx + r * 0.78} {hy + r * 0.32} "
                                        f"Q{bx + r * 0.85} {hy + r * 1.3} {bx} {hy + r * 1.42} Q{bx - r * 0.85} {hy + r * 1.3} {bx - r * 0.78} {hy + r * 0.32} Z",
                            *beard, 1.4, 1.2))
    if snout and facing != "north":
        if side:
            front.append(shaded(uid + "s", ellipse(hx + turn * r * 0.85, hy + r * 0.3, r * 0.58, r * 0.4), *snout, 1.4, 1.2))
            front.append(f'<circle cx="{hx + turn * r * 1.32}" cy="{hy + r * 0.18}" r="1.6" fill="{INK}"/>')
        else:
            front.append(shaded(uid + "s", ellipse(hx, hy + r * 0.5, r * 0.5, r * 0.36), *snout, 1.4, 1.2))
            front.append(f'<ellipse cx="{hx}" cy="{hy + r * 0.36}" rx="2" ry="1.4" fill="{INK}"/>')
    if tusks and facing != "north":
        xs = [hx - 3.4, hx + 3.4] if not side else [hx + turn * 4.2]
        for x in xs:
            front.append(f'<path d="M{x - 1.6} {hy + r * 0.72} L{x} {hy + r * 0.3} L{x + 1.6} {hy + r * 0.72} Z" fill="#fbf6e6" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>')
    if brows and facing != "north":
        if side:
            front.append(f'<path d="M{hx + turn * 0.2} {eye_y - 5.2} L{hx + turn * 6.8} {eye_y - 3.6}" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>')
        else:
            front.append(f'<path d="M{hx - 6} {eye_y - 5.4} L{hx - 1.4} {eye_y - 3.6} M{hx + 6} {eye_y - 5.4} L{hx + 1.4} {eye_y - 3.6}" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>')
    parts += front
    parts.append(pills(hx, eye_y, facing, eye))
    return wrap("".join(parts))


# --- beasts --------------------------------------------------------------

def zigzag(cx, cy, radius, teeth=10, depth=0.8):
    """A frill: a fan of teeth around a centre."""
    import math
    points = []
    for i in range(teeth * 2):
        angle = math.pi * i / teeth
        rr = radius if i % 2 == 0 else radius * depth
        points.append((round(cx + rr * math.cos(angle), 2), round(cy + rr * math.sin(angle), 2)))
    return poly(points)


def spikes(xs, y, color, k):
    return "".join(f'<path d="M{x0 - 2.6 * k} {y + 2} L{x0} {y - 3.5 * k} L{x0 + 2.6 * k} {y + 2} Z" fill="{color}" stroke="{INK}" stroke-width="1.8" stroke-linejoin="round"/>' for x0 in xs)


def tail_path(d, k, tail_color):
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{6 * k}" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="{tail_color}" stroke-width="{2.8 * k}" stroke-linecap="round"/>')


def beast(uid, facing, fur, ear_color, tail_color, size=1.0, frill=None, crest=None, tail_len=1.0, snout_len=1.0):
    """A four-legged critter as three blobs: body, head, snout; ears, a tail,
    and optionally a toothed frill round the neck or spikes down the back."""
    turn = {"east": 1, "west": -1}.get(facing, 0)
    k = size
    parts = [shadow(15 * k + 2)]

    def x(v):  # side views: +v is toward the facing
        return 32 + turn * v

    if turn:
        parts.append(tail_path(f"M{x(-13 * k)} 46 Q{x(-24 * k * tail_len)} 50 {x(-25 * k * tail_len)} 38", k, tail_color))
        parts.append(shaded(uid + "b", ellipse(x(-2 * k), 45, 15 * k, 10 * k), *fur))
        if crest:
            parts.append(spikes([x(v * k) for v in (-10, -3, 4)], 35.5, crest, k))
        if frill:
            parts.append(shaded(uid + "f", zigzag(x(11 * k), 39, 14.5 * k), *frill, 1.6, 1.4))
        parts.append(shaded(uid + "e", ellipse(x(9 * k), 31, 3.8 * k, 4.2 * k), *ear_color, 1, 1))
        parts.append(shaded(uid + "h", ellipse(x(12 * k), 39, 8.5 * k, 7.5 * k), *fur, 2, 1.8))
        parts.append(shaded(uid + "n", ellipse(x((18 + 2 * snout_len) * k), 41, 5 * k * snout_len, 4 * k), *fur, 1.2, 1))
        parts.append(f'<circle cx="{x((22 + 3 * snout_len) * k)}" cy="40.4" r="{1.8 * k}" fill="{tail_color}" stroke="{INK}" stroke-width="1.4"/>')
        parts.append(pills(x(12 * k) - turn * 1, 37.5, facing, INK, h=5.6))
        parts.append(f'<path d="M{x(-8 * k)} 54 L{x(-8 * k)} 57 M{x(6 * k)} 54 L{x(6 * k)} 57" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>')
    elif facing == "south":
        parts.append(tail_path(f"M{32 + 11 * k} 49 Q{32 + 21 * k} 50 {32 + 20 * k * tail_len} 40", k, tail_color))
        # Front view: a big head in front hides most of the body; only the
        # shoulders show either side, and the ears stand clear of the head.
        parts.append(shaded(uid + "b", ellipse(32, 45, 14.5 * k, 9 * k), *fur))
        if frill:
            parts.append(shaded(uid + "f", zigzag(32, 45, 17 * k), *frill, 1.6, 1.4))
        for i, sx in enumerate((-1, 1)):
            parts.append(shaded(f"{uid}e{i}", ellipse(32 + sx * 8.6 * k, 36.5, 4 * k, 4.4 * k), *ear_color, 1.2, 1))
        parts.append(shaded(uid + "h", ellipse(32, 46, 10.5 * k, 9.2 * k), *fur, 2.4, 2))
        parts.append(pills(32, 45, facing, INK, gap=3.4, h=5.6))
        parts.append(f'<circle cx="32" cy="{51.6 + k * 0.5}" r="{2 * k}" fill="{tail_color}" stroke="{INK}" stroke-width="1.4"/>')
    else:  # north: the head sits beyond the body, the tail comes toward us
        if frill:
            parts.append(shaded(uid + "f", zigzag(32, 34, 14.5 * k), *frill, 1.6, 1.4))
        for i, sx in enumerate((-1, 1)):
            parts.append(shaded(f"{uid}e{i}", ellipse(32 + sx * 5.5 * k, 29, 3.2 * k, 3.6 * k), *ear_color, 1, 1))
        parts.append(shaded(uid + "h", ellipse(32, 34, 7.5 * k, 6.5 * k), *fur, 2, 1.8))
        parts.append(shaded(uid + "b", ellipse(32, 45, 13 * k, 10.5 * k), *fur))
        if crest:
            parts.append(spikes([32 - 6 * k, 32, 32 + 6 * k], 36, crest, k))
        parts.append(tail_path(f"M32 {54 + k} Q{32 + 3 * k} 59 {32 + 12 * k * tail_len} 59", k, tail_color))
    return wrap("".join(parts))


# --- bosses ------------------------------------------------------------

def mire(uid, facing):
    """수렁 포식자: a mud mound with a wide toothed maw and three yellow eyes."""
    turn = {"east": 1, "west": -1}.get(facing, 0)
    parts = [shadow(26, 59)]
    mound = "M5 58 Q3 34 18 26 Q32 16 46 26 Q61 34 59 58 Z"
    parts.append(shaded(uid + "m", mound, "#6e7a3c", "#566130", 3.4, 2.6))
    for i, (x0, y0) in enumerate(((14, 30), (48, 32), (30, 20))):
        parts.append(shaded(f"{uid}k{i}", ellipse(x0, y0, 5, 4), "#7f8c46", "#6e7a3c", 1.2, 1))
    if facing != "north":
        mx = 32 + turn * 9
        parts.append(f'<path d="M{mx - 14} 42 Q{mx} 58 {mx + 14} 42 Q{mx} 47 {mx - 14} 42 Z" fill="#2a1a1c" {LINE}/>')
        for i in range(5):
            tx = mx - 10 + i * 5
            parts.append(f'<path d="M{tx - 2} 43.5 L{tx} 48 L{tx + 2} 43.5 Z" fill="#fbf6e6" stroke="{INK}" stroke-width="1.2" stroke-linejoin="round"/>')
        for i, (ex, ey) in enumerate(((mx - 8, 33), (mx + 8, 33), (mx, 28))):
            parts.append(f'<rect x="{ex - 1.8}" y="{ey - 3.4}" width="3.6" height="6.8" rx="1.8" fill="#ffd84a" stroke="{INK}" stroke-width="1.4"/>')
    for x0 in (12, 50):
        parts.append(f'<path d="M{x0} 52 Q{x0 + 1} 58 {x0 - 1} 60" fill="none" stroke="#566130" stroke-width="3" stroke-linecap="round"/>')
    return wrap("".join(parts))


def bomber(uid, facing):
    """폭탄 암살자: a thin hooded figure, a void where the face should be."""
    turn = {"east": 1, "west": -1}.get(facing, 0)
    frame = (9.5, 9.0, 0.5, 30, 11.5)
    s, h, b, top, r = frame
    if turn:
        s, h, b = s * 0.72, h * 0.78, b * 0.8
    hx, hy = 32 + 2.5 * turn, top - r + 4
    parts = [shadow(max(s, h) + 4)]
    parts.append(shaded(uid + "b", doll.torso(32, top, s, h, b), "#4a3566", "#3a2952"))
    parts.append(f'<path d="M{32 - s + 3} {top + 9} L{32 + s - 3} {top + 16}" stroke="#2a1d3c" stroke-width="3.2" stroke-linecap="round"/>')
    hood = f"M{hx - r} {hy + 2} Q{hx - r} {hy - r - 2} {hx + turn * 3} {hy - r - 5} Q{hx + r} {hy - r - 1} {hx + r} {hy + 2} Q{hx + r} {hy + r} {hx} {hy + r} Q{hx - r} {hy + r} {hx - r} {hy + 2} Z"
    parts.append(shaded(uid + "h", hood, "#5a4278", "#46325f", 2.4, 2))
    if facing != "north":
        fx = hx + turn * 3
        parts.append(f'<ellipse cx="{fx}" cy="{hy + 1.5}" rx="{r * 0.62 if not turn else r * 0.5}" ry="{r * 0.55}" fill="#140c1c" {LINE}/>')
        parts.append(pills(fx, hy + 1.2, facing, "#ff5a3a", gap=2.8, h=4.4))
    return wrap("".join(parts))


def giant(uid, facing):
    """과부하 거인: a stone hulk with a small head and glowing overloaded cracks."""
    turn = {"east": 1, "west": -1}.get(facing, 0)
    s, h, b, top, r = (19.0, 14.0, 1.5, 26, 8.5)
    if turn:
        s, h, b = s * 0.72, h * 0.78, b * 0.8
    hx, hy = 32 + 2.5 * turn, top - r + 3
    glow = "#6ff3ff"
    parts = [shadow(max(s, h) + 5, 59)]
    torso = doll.torso(32, top, s, h, b).replace(f"{BOTTOM}", "58")
    parts.append(shaded(uid + "b", torso, "#8d95a3", "#6f7786", 3.4, 2.6))
    parts.append(f'<path d="M{32 - s * 0.6} {top + 8} L{32 - s * 0.2} {top + 14} L{32 - s * 0.5} {top + 22} M{32 + s * 0.5} {top + 6} L{32 + s * 0.25} {top + 13} L{32 + s * 0.55} {top + 20}" fill="none" stroke="{glow}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>')
    if facing != "north":
        cx0 = 32 + turn * 4
        parts.append(f'<circle cx="{cx0}" cy="{top + 14}" r="5.4" fill="{glow}" {LINE}/>')
        parts.append(f'<circle cx="{cx0 - 1.4}" cy="{top + 12.6}" r="1.8" fill="#ffffff"/>')
    parts.append(shaded(uid + "h", ellipse(hx, hy, r, r * 0.9), "#9aa2b0", "#7c8494", 2, 1.8))
    parts.append(pills(hx, hy, facing, glow, gap=2.8, h=5))
    return wrap("".join(parts))


def bat(uid, facing, fur, wing, glow="#ffe14a"):
    """A winged caster silhouette that stays legible at the game's tile size."""
    turn = {"east": 1, "west": -1}.get(facing, 0)
    cx, cy = 32 + 2 * turn, 38
    parts = [shadow(14, 59)]
    spans = {"south": (-1, 1), "north": (-1, 1), "east": (-1,), "west": (1,)}[facing]
    for i, side in enumerate(spans):
        tip = cx + side * 26
        wing_path = (f"M{cx + side * 6} {cy - 6} Q{cx + side * 18} {cy - 20} {tip} {cy - 10} "
                     f"L{cx + side * 20} {cy + 2} L{cx + side * 14} {cy - 2} L{cx + side * 8} {cy + 6} Z")
        parts.append(shaded(f"{uid}w{i}", wing_path, *wing, 2.0, 1.6))
    parts.append(shaded(uid + "b", ellipse(cx, cy, 11, 12), *fur, 2.6, 2.2))
    for i, side in enumerate((-1, 1)):
        ear = poly([(cx + side * 3, cy - 10), (cx + side * 8, cy - 21), (cx + side * 9, cy - 8)])
        parts.append(shaded(f"{uid}e{i}", ear, *fur, 1.2, 1.0))
    parts.append(pills(cx, cy - 2, facing, glow, gap=3.4, h=5.2))
    return wrap("".join(parts))


FLAME = f'<path d="M32 52 Q27.5 48 30.5 42.5 Q32 46 33.5 43.5 Q37 48.5 32 52 Z" fill="#ffb13a" stroke="{INK}" stroke-width="1.4" stroke-linejoin="round"/>'
RUNE = f'<circle cx="32" cy="48" r="3.4" fill="none" stroke="#e7d36a" stroke-width="1.8"/>'
CHAIN = '<path d="M24 46 L40 50" stroke="#c9c9c9" stroke-width="2.4" stroke-linecap="round" stroke-dasharray="3 2"/>'


GOBLIN_SKIN = ("#78c24c", "#5ea338")
MONSTERS = {
    # id: (display name, builder, raster scale)
    "dcss_rat": ("쥐", lambda f: beast("rat" + f, f, ("#8f8f9c", "#737382"), ("#e9a0a6", "#cf8288"), "#e9a0a6", 0.85), 2),
    "dcss_frilled_lizard": ("목도리 도마뱀", lambda f: beast("liz" + f, f, ("#8fb04a", "#74933a"), ("#8fb04a", "#74933a"), "#8fb04a", 0.9,
                                                       frill=("#f08a3a", "#d0702a"), tail_len=1.25, snout_len=1.3), 2),
    "kobold": ("코볼트", lambda f: humanoid("kob" + f, f, (8.5, 7.5, 0.5, 34, 10.0), ("#d0763c", "#b0602c"), ("#8a5a33", "#6f4526"),
                                        snout=("#d0763c", "#b0602c"), horns=True), 2),
    "goblin": ("고블린", lambda f: humanoid("gob" + f, f, (9.5, 8.5, 0.5, 33, 10.5), GOBLIN_SKIN, ("#8a5a33", "#6f4526"), ears="pointy"), 2),
    "dcss_hobgoblin": ("홉고블린", lambda f: humanoid("hob" + f, f, (13.0, 11.0, 1.0, 31, 11.0), ("#d86a3c", "#b8552c"), ("#5a4a3a", "#473a2d"),
                                                ears="pointy", brows=True), 2),
    "dcss_orc": ("오크", lambda f: humanoid("orc" + f, f, (17.0, 12.0, 1.0, 30, 11.5), ("#86a94c", "#6d8e3a"), ("#4d3a2c", "#3a2b20"),
                                         tusks=True, brows=True), 2),
    "dcss_gnoll": ("놀", lambda f: humanoid("gno" + f, f, (13.5, 11.5, 1.0, 31, 11.5), ("#d2a95e", "#b58c48"), ("#6a5a48", "#554737"),
                                       ears="round", snout=("#6a5040", "#553f32"), spots=[(-5, -4, 1.8), (4, -6, 1.5), (6, 2, 1.6), (-7, 3, 1.3)]), 2),
    "dcss_river_rat": ("강쥐", lambda f: beast("rrat" + f, f, ("#5a6a86", "#46546e"), ("#d98a92", "#bf7078"), "#d98a92", 1.08,
                                             crest="#9fb3d4"), 2),
    "kobold_firecaller": ("코볼트 화염술사", lambda f: humanoid("kfc" + f, f, (8.5, 7.5, 0.5, 34, 10.0), ("#d0763c", "#b0602c"), ("#b8412e", "#963223"),
                                                   snout=("#d0763c", "#b0602c"), horns=True, mark=FLAME), 2),
    "frost_imp": ("서리 도깨비", lambda f: humanoid("imp" + f, f, (7.5, 6.5, 0.5, 35, 9.5), ("#9fd3ec", "#7ab5d2"), ("#4d6f9c", "#3c5a80"),
                                         ears="pointy", horns=True, eye="#1d3a5c"), 2),
    "storm_bat": ("폭풍 박쥐", lambda f: bat("sbat" + f, f, ("#4a4f6e", "#3a3e58"), ("#6a6f94", "#555a7a")), 2),
    "goblin_hexer": ("고블린 주술사", lambda f: humanoid("ghx" + f, f, (9.5, 8.5, 0.5, 33, 10.5), GOBLIN_SKIN, ("#6a4a9c", "#553a80"),
                                              ears="pointy", mark=RUNE), 2),
    "gnoll_summoner": ("놀 소환사", lambda f: humanoid("gsm" + f, f, (13.5, 11.5, 1.0, 31, 11.5), ("#d2a95e", "#b58c48"), ("#3f6b5a", "#31554a"),
                                              ears="round", snout=("#6a5040", "#553f32"), spots=[(-5, -4, 1.8), (4, -6, 1.5)], mark=CHAIN), 2),
    "boss_mire": ("수렁 포식자", lambda f: mire("mire" + f, f), 3),
    "boss_bomber": ("폭탄 암살자", lambda f: bomber("bomb" + f, f), 3),
    "boss_giant": ("과부하 거인", lambda f: giant("giant" + f, f), 3),
}


def main() -> None:
    (OUT / "svg").mkdir(parents=True, exist_ok=True)
    (OUT / "png").mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    jobs = []
    for mid, (_, build, scale) in MONSTERS.items():
        for facing in FACINGS:
            source = OUT / "svg" / f"{mid}_{facing}.svg"
            source.write_text(build(facing))
            jobs.append((source, OUT / "png" / f"{mid}_{facing}.png", scale))
    flat.rasterise(jobs)

    font = ImageFont.truetype(str(ROOT / "assets/fonts/Jua-Regular.ttf"), 22)
    cell, pad, label = 128, 14, 170
    rows = []
    for mid, (name, _, scale) in MONSTERS.items():
        rows.append((mid, name, 128 if scale == 2 else 176))
    height = 50 + sum(size + pad for _, _, size in rows)
    width = label + 4 * (176 + pad)
    sheet = Image.new("RGBA", (width, height), "#e9a25c")
    draw = ImageDraw.Draw(sheet)
    for c, facing in enumerate(FACINGS):
        draw.text((label + c * (176 + pad) + 88, 22), facing, font=font, fill=INK, anchor="mm")
    y = 44
    for mid, name, size in rows:
        draw.text((16, y + size // 2), name, font=font, fill=INK, anchor="lm")
        for c, facing in enumerate(FACINGS):
            image = Image.open(OUT / "png" / f"{mid}_{facing}.png").convert("RGBA").resize((size, size), Image.LANCZOS)
            sheet.alpha_composite(image, (label + c * (176 + pad) + (176 - size) // 2, y))
        y += size + pad
    sheet.convert("RGB").save(REVIEW / "monster-sheet.png")


if __name__ == "__main__":
    main()
