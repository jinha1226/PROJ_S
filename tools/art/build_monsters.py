"""Monster sprites in the paper-doll style.

Same rules as tools/art/build_paperdoll.py: bold ink outline, flat fills, one
contour crescent of shade on the lower right, tall pill eyes, no limbs, no
held items, and four facings with the light always from the top-left (west
is drawn, never mirrored).

Humanoids reuse the paper-doll torso and add species features (ears, snout,
tusks, horns, spots). Beasts are a body, a head and a tail. Every species is drawn on the same 64-unit grid.

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


QUIVER = '<path d="M38 40 L42 52" stroke="#8a5a33" stroke-width="3" stroke-linecap="round"/>'
BUCKLER = f'<circle cx="26" cy="46" r="5" fill="#b0b8c0" stroke="{INK}" stroke-width="1.6"/>'
AXE = '<path d="M24 44 L30 38" stroke="#c9c9c9" stroke-width="3" stroke-linecap="round"/>'
LANTERN = f'<circle cx="38" cy="48" r="3.4" fill="#ffd36a" stroke="{INK}" stroke-width="1.4"/>'
BONE = ("#e8e2d0", "#c9c2ad")
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
    "goblin_archer": ("고블린 궁수", lambda f: _held(humanoid("gar" + f, f, (9.5, 8.5, 0.5, 33, 10.5), GOBLIN_SKIN, ("#5a7a3a", "#476030"),
                                                         ears="pointy"), bow_prop(f)), 2),
    "goblin_shield": ("고블린 방패병", lambda f: _held(humanoid("gsh" + f, f, (10.5, 9.5, 1.0, 33, 10.5), GOBLIN_SKIN, ("#6d7680", "#565e66"),
                                                           ears="pointy", brows=True), shield_prop(f)), 2),
    "orc_thrower": ("오크 투척병", lambda f: _held(humanoid("otr" + f, f, (15.0, 11.5, 1.0, 31, 11.0), ("#86a94c", "#6d8e3a"), ("#7a4a2c", "#603a22"),
                                                       tusks=True), axe_prop(f)), 2),
    "cave_spider": ("동굴 거미", lambda f: spider("spd" + f, f, ("#3a3440", "#2a2530"), "#c8303e"), 2),
    "rock_beetle": ("바위 딱정벌레", lambda f: beetle("btl" + f, f, ("#7a746a", "#5f5a52"), ("#5a5550", "#46423e")), 2),
    "ore_golem": ("광석 골렘", lambda f: rock_golem("gol" + f, f, ("#8a8680", "#6e6a64"), ("#e08a3a", "#b86a22")), 2),
    "giant_leech": ("거대 거머리", lambda f: leech("lee" + f, f, ("#6a3a4e", "#52293a"), "#8a5064"), 2),
    "swamp_toad": ("늪 두꺼비", lambda f: toad("toad" + f, f, ("#6a8a3a", "#55702e"), ("#d8d08a", "#bab070"), "#3a4a1c"), 2),
    "temple_serpent": ("신전 뱀", lambda f: serpent("srp" + f, f, ("#3f7a6a", "#315f53"), ("#d8c878", "#b8a860"), "#f2c64b"), 2),
    "water_spirit": ("물의 정령", lambda f: water_body("wsp" + f, f, ("#5fb0f0", "#3f8ad0"), ("#2a6aa8", "#1d3a5c")), 2),
    "skeleton_soldier": ("해골 병사", lambda f: _held(humanoid("sks" + f, f, (13.0, 11.0, 1.0, 31, 11.0), BONE, ("#6a6a72", "#55555c"),
                                                          eye="#1a1a1a"), shield_prop(f, ("#8a8a94", "#6c6c76"), "#e8e2d0")), 2),
    "skeleton_archer": ("해골 궁수", lambda f: _held(humanoid("ska" + f, f, (10.0, 8.5, 0.5, 31, 10.5), BONE, ("#5a4a3a", "#473a2d"),
                                                         eye="#1a1a1a"), bow_prop(f)), 2),
    "ghoul": ("구울", lambda f: ghoul_body("gho" + f, f, ("#9aa88a", "#7e8c70"), ("#4a4038", "#3a322b")), 2),
    "vampire_bat": ("흡혈 박쥐", lambda f: bat("vbat" + f, f, ("#3a2030", "#2a1822"), ("#6a2a3a", "#541f2d"), glow="#ff4a5a"), 2),
    "wraith_knight": ("망령 기사", lambda f: humanoid("wkn" + f, f, (16.0, 12.0, 1.0, 30, 11.5), ("#5a5a70", "#46465a"), ("#2f2f3a", "#22222b"),
                                              horns=True, eye="#b889ff"), 2),
    "wraith": ("원혼", lambda f: ghost("wra" + f, f, ("#c9c2e8", "#aaa2cc"), "#7a5ae0"), 2),
    "gravekeeper": ("묘지기", lambda f: _held(humanoid("grv" + f, f, (13.0, 11.0, 1.0, 31, 11.0), ("#b8a890", "#9a8c76"), ("#3a3a44", "#2c2c34"),
                                                   brows=True), lantern_prop(f)), 2),
}


# --- distinct silhouettes (redrawn 2026-09-26) -------------------------------------
# Every creature below has a body of its own, so thirty species stay apart on
# a crowded board: legs for the spider, a shell for the beetle, a coil for the
# serpent, no legs at all for the spirit and the wraith.

def _face(facing, cx, cy, color=INK, gap=3.0, h=5.6):
    return "" if facing == "north" else pills(cx, cy, facing, color, gap=gap, h=h)


def _turn(facing):
    return {"east": 1, "west": -1}.get(facing, 0)


def spider(uid, facing, body, mark, eye="#ff4a5a"):
    t = _turn(facing)
    cx = 32 - 3 * t
    parts = [shadow(18, 58)]
    for side in (-1, 1):
        for i, (reach, lift) in enumerate(((20, -10), (23, -3), (22, 4), (18, 9))):
            knee = (cx + side * reach * 0.7, 40 + lift - 8)
            foot = (cx + side * reach, 50 + lift * 0.5 + 4)
            d = f"M{cx + side * 5} {42 + i} L{knee[0]:.1f} {knee[1]:.1f} L{foot[0]:.1f} {foot[1]:.1f}"
            parts.append(f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>')
            parts.append(f'<path d="{d}" fill="none" stroke="{body[0]}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append(shaded(uid + "a", ellipse(cx - 2 * t, 38 if facing != "south" else 36, 13, 11), *body))
    parts.append(f'<path d="M{cx - 2 * t - 3} 31 L{cx - 2 * t + 3} 31 L{cx - 2 * t} 36 Z M{cx - 2 * t - 3} 41 L{cx - 2 * t + 3} 41 L{cx - 2 * t} 36 Z" fill="{mark}"/>'
                 if facing == "north" else "")
    if facing != "north":
        hx = cx + 4 * t
        parts.append(shaded(uid + "h", ellipse(hx, 46, 8.5, 7), *body, 1.6, 1.4))
        parts.append(f'<path d="M{hx - 3} 52 L{hx - 2} 56 M{hx + 3} 52 L{hx + 2} 56" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/>')
        for ex, ey, r in ((-3, 44, 1.9), (3, 44, 1.9), (-5.5, 41.5, 1.1), (5.5, 41.5, 1.1)):
            parts.append(f'<circle cx="{hx + ex + 2 * t}" cy="{ey}" r="{r}" fill="{eye}"/>')
    return wrap("".join(parts))


def beetle(uid, facing, shell, belly, moss="#6a8a4a"):
    t = _turn(facing)
    parts = [shadow(18, 58)]
    for side in (-1, 1):
        for i, y in enumerate((44, 50, 55)):
            parts.append(f'<path d="M{32 + side * 12} {y} L{32 + side * 19} {y + 2 - i}" stroke="{INK}" stroke-width="3.2" stroke-linecap="round"/>')
    if facing != "north":
        hx = 32 + 10 * t
        hy = 50 if facing == "south" else 46
        parts.append(shaded(uid + "h", ellipse(hx, hy, 7.5, 5.5), *belly, 1.2, 1))
        for side in (-1, 1):
            parts.append(f'<path d="M{hx + side * 3} {hy + 3} Q{hx + side * 7} {hy + 8} {hx + side * 3} {hy + 9}" fill="none" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/>')
    dome = f"M13 {46} Q13 {22} 32 {22} Q51 {22} 51 {46} Q51 50 46 50 L18 50 Q13 50 13 46 Z"
    if facing == "south":
        dome = "M13 44 Q13 24 32 24 Q51 24 51 44 Q51 47 47 47 L17 47 Q13 47 13 44 Z"
    parts.append(shaded(uid + "s", dome, *shell, 3.0, 2.4))
    parts.append(f'<path d="M32 25 L32 {47 if facing == "south" else 50}" stroke="{INK}" stroke-width="2"/>')
    for x, y, rx, ry in ((22, 32, 4, 2.4), (41, 36, 3.4, 2), (26, 41, 3, 1.8)):
        parts.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{moss}" opacity="0.9"/>')
    parts.append('<path d="M20 30 Q24 26 29 26" fill="none" stroke="#ffffff" stroke-width="2" stroke-linecap="round" opacity="0.6"/>')
    if facing != "north":
        hx = 32 + 10 * t
        parts.append(_face(facing, hx, 49 if facing == "south" else 45, "#ffcf40", gap=2.6, h=3.6))
    return wrap("".join(parts))


def leech(uid, facing, skin, stripe, mouth="#f07a8a"):
    t = _turn(facing)
    parts = [shadow(12, 58)]
    segs = [(32 + 6 * t, 52, 11), (32 + 2 * t, 44, 10), (32 - 3 * t, 36, 9), (32 - 1 * t, 28, 8.5)]
    for i, (x, y, r) in enumerate(segs):
        parts.append(shaded(f"{uid}g{i}", ellipse(x, y, r, r * 0.78), *skin, 1.8, 1.4))
        parts.append(f'<path d="M{x - r * 0.7} {y} Q{x} {y + r * 0.35} {x + r * 0.7} {y}" fill="none" stroke="{stripe}" stroke-width="2"/>')
    hx, hy, r = segs[-1]
    if facing != "north":
        parts.append(f'<ellipse cx="{hx + 2 * t}" cy="{hy - 2}" rx="5.4" ry="4.4" fill="{mouth}" stroke="{INK}" stroke-width="2"/>')
        parts.append("".join(f'<path d="M{hx + 2 * t + 4 * math.cos(a):.1f} {hy - 2 + 3.4 * math.sin(a):.1f} L{hx + 2 * t + 2 * math.cos(a):.1f} {hy - 2 + 1.6 * math.sin(a):.1f}" stroke="#fbf6e6" stroke-width="1.6"/>'
                             for a in [i * math.pi / 4 for i in range(8)]))
        parts.append(f'<circle cx="{hx - 5 + 2 * t}" cy="{hy - 7}" r="1.4" fill="{INK}"/><circle cx="{hx + 5 + 2 * t}" cy="{hy - 7}" r="1.4" fill="{INK}"/>')
    return wrap("".join(parts))


def toad(uid, facing, skin, belly, wart):
    t = _turn(facing)
    parts = [shadow(18, 58)]
    for side in (-1, 1):
        parts.append(shaded(f"{uid}l{side}", ellipse(32 + side * 15, 53, 7, 4.2), *skin, 1.2, 1))
    parts.append(shaded(uid + "b", "M12 50 Q10 34 32 32 Q54 34 52 50 Q50 56 32 56 Q14 56 12 50 Z", *skin, 3, 2.2))
    if facing != "north":
        parts.append(shaded(uid + "y", "M20 52 Q20 44 32 44 Q44 44 44 52 Q38 55 32 55 Q26 55 20 52 Z", *belly, 1.2, 1))
        parts.append(f'<path d="M18 42 Q32 {48} 46 42" fill="none" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>')
    for i, side in enumerate((-1, 1)):
        ex = 32 + side * 9 + 3 * t
        parts.append(shaded(f"{uid}e{i}", ellipse(ex, 31, 6, 5.5), *skin, 1.2, 1))
        if facing != "north":
            parts.append(f'<circle cx="{ex + t}" cy="31" r="3.4" fill="#ffe14a" stroke="{INK}" stroke-width="1.4"/>'
                         f'<rect x="{ex + t - 0.9}" y="28.6" width="1.8" height="4.8" rx="0.9" fill="{INK}"/>')
    for x, y in ((18, 40), (46, 39), (25, 36), (40, 36)):
        parts.append(f'<circle cx="{x}" cy="{y}" r="1.6" fill="{wart}"/>')
    return wrap("".join(parts))


def serpent(uid, facing, scales, belly, hood_mark):
    t = _turn(facing)
    parts = [shadow(17, 58)]
    parts.append(shaded(uid + "c1", ellipse(32, 51, 17, 6.5), *scales, 2.4, 1.8))
    parts.append(shaded(uid + "c2", ellipse(32 - 2 * t, 45, 13, 5.5), *scales, 2, 1.6))
    parts.append(f'<path d="M20 51 Q32 55 44 51" fill="none" stroke="{belly[0]}" stroke-width="2.4" stroke-linecap="round"/>')
    neck = f"M{30 - 2 * t} 44 Q{27 - 4 * t} 32 {32 + 2 * t} 24"
    parts.append(f'<path d="{neck}" fill="none" stroke="{INK}" stroke-width="10" stroke-linecap="round"/>')
    parts.append(f'<path d="{neck}" fill="none" stroke="{scales[0]}" stroke-width="6.4" stroke-linecap="round"/>')
    hx = 32 + 3 * t
    hood = f"M{hx - 11} 22 Q{hx - 12} 10 {hx} 9 Q{hx + 12} 10 {hx + 11} 22 Q{hx + 6} 30 {hx} 30 Q{hx - 6} 30 {hx - 11} 22 Z"
    parts.append(shaded(uid + "hd", hood, *scales, 2, 1.6))
    if facing != "north":
        parts.append(f'<path d="M{hx - 4} 18 L{hx} 13 L{hx + 4} 18 L{hx} 23 Z" fill="{hood_mark}" stroke="{INK}" stroke-width="1.4"/>')
        parts.append(f'<rect x="{hx - 5.5}" y="19" width="2.4" height="4" rx="1.2" fill="{INK}"/><rect x="{hx + 3.1}" y="19" width="2.4" height="4" rx="1.2" fill="{INK}"/>')
        parts.append(f'<path d="M{hx} 29 L{hx} 34 M{hx} 34 L{hx - 2} 36 M{hx} 34 L{hx + 2} 36" stroke="#e0453a" stroke-width="1.4" stroke-linecap="round"/>')
    else:
        parts.append(f'<path d="M{hx - 4} 18 L{hx} 13 L{hx + 4} 18 L{hx} 23 Z" fill="{belly[1]}" opacity="0.6"/>')
    return wrap("".join(parts))


def rock_golem(uid, facing, rock, ore, glow="#ffb13a"):
    t = _turn(facing)
    parts = [shadow(19, 58)]
    for x in (22, 42):
        parts.append(shaded(f"{uid}l{x}", "M{a} 48 L{b} 48 L{b} 57 L{a} 57 Z".format(a=x - 6, b=x + 6), *rock, 1.4, 1))
    boulder = "M14 30 L22 18 L38 15 L50 24 L52 42 L44 50 L20 50 L12 42 Z"
    parts.append(shaded(uid + "b", boulder, *rock, 3, 2.4))
    for side, x in ((-1, 10), (1, 54)):
        fist = "M{a} 34 L{b} 30 L{c} 38 L{d} 46 L{a} 46 Z".format(a=x - 6, b=x + 2, c=x + 6, d=x + 4)
        parts.append(shaded(f"{uid}f{side}", fist, *rock, 1.6, 1.2))
    for pts in (((20, 26), (24, 22), (27, 28)), ((38, 34), (43, 30), (45, 37)), ((24, 40), (28, 37), (30, 43))):
        parts.append(f'<path d="{poly(pts)}" fill="{ore[0]}" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>')
    parts.append(f'<path d="M30 20 L33 28 L29 36 M44 26 L40 32" fill="none" stroke="{glow}" stroke-width="1.8" stroke-linecap="round" opacity="0.9"/>')
    if facing != "north":
        parts.append(_face(facing, 32 + 4 * t, 25, glow, gap=4, h=3.4))
    return wrap("".join(parts))


def water_body(uid, facing, water, deep, foam="#e8f8ff"):
    t = _turn(facing)
    parts = [f'<ellipse cx="32" cy="57" rx="17" ry="4" fill="{deep[0]}" stroke="{INK}" stroke-width="2"/>']
    column = "M18 54 Q16 40 22 30 Q26 18 34 12 Q34 18 40 22 Q48 30 46 42 Q46 50 44 54 Z"
    parts.append(shaded(uid + "c", column, *water, 3, 2.4))
    parts.append(f'<path d="M34 12 Q30 20 26 20 Q30 14 34 12 Z" fill="{foam}"/>')
    parts.append(f'<path d="M24 46 Q30 40 36 44 Q40 48 34 50" fill="none" stroke="{foam}" stroke-width="2" stroke-linecap="round" opacity="0.8"/>')
    parts.append(f'<path d="M22 32 Q24 26 28 24" fill="none" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round"/>')
    for x, y, r in ((12, 52, 2.4), (52, 50, 2), (48, 56, 1.6)):
        parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{water[0]}" stroke="{INK}" stroke-width="1.2"/>')
    parts.append(_face(facing, 33 + 3 * t, 33, deep[1], gap=3.4, h=5.4))
    return wrap("".join(parts))


def ghost(uid, facing, cloak, glow="#b889ff"):
    t = _turn(facing)
    parts = [f'<ellipse cx="32" cy="58" rx="9" ry="2.4" fill="#000" fill-opacity="0.16"/>']
    body = ("M32 8 Q46 8 47 24 Q48 36 44 44 Q42 50 38 46 Q36 54 32 48 Q28 54 26 46 Q22 50 20 44 "
            "Q16 36 17 24 Q18 8 32 8 Z")
    for side in (-1, 1):
        arm = f"M{32 + side * 12} 26 Q{32 + side * 22} 30 {32 + side * 24} 40 Q{32 + side * 19} 36 {32 + side * 13} 34 Z"
        parts.append(shaded(f"{uid}a{side}", arm, *cloak, 1.4, 1))
    parts.append(shaded(uid + "b", body, *cloak, 2.6, 2))
    if facing != "north":
        parts.append(f'<path d="M24 16 Q32 10 40 16 L39 28 Q32 33 25 28 Z" fill="#1c1428"/>')
        parts.append(_face(facing, 32 + 2 * t, 21, glow, gap=3.6, h=5))
        parts.append(f'<ellipse cx="{32 + 2 * t}" cy="28" rx="2.6" ry="1.8" fill="{INK}"/>')
    return wrap("".join(parts))


def ghoul_body(uid, facing, skin, rag, eye="#ffe14a"):
    t = _turn(facing)
    parts = [shadow(16, 58)]
    for side in (-1, 1):
        arm = f"M{32 + side * 9} 32 Q{32 + side * 20} 38 {32 + side * 19} 52"
        parts.append(f'<path d="{arm}" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>')
        parts.append(f'<path d="{arm}" fill="none" stroke="{skin[0]}" stroke-width="3.6" stroke-linecap="round"/>')
        for k in (-2, 0, 2):
            parts.append(f'<path d="M{32 + side * 19 + k} 52 L{32 + side * 19 + k * 1.6} 57" stroke="{INK}" stroke-width="2" stroke-linecap="round"/>')
    torso = "M22 52 Q20 38 26 30 Q32 25 38 30 Q44 38 42 52 Z"
    parts.append(shaded(uid + "t", torso, *skin, 2.2, 1.8))
    parts.append(f'<path d="M26 36 Q32 38 38 36 M27 41 Q32 43 37 41" fill="none" stroke="{skin[1]}" stroke-width="1.6"/>')
    parts.append(shaded(uid + "r", "M22 48 L42 48 L40 56 L36 52 L32 57 L28 52 L24 56 Z", *rag, 1.2, 1))
    hx, hy = 32 + 5 * t, 24
    parts.append(shaded(uid + "h", ellipse(hx, hy, 9, 8.5), *skin, 1.8, 1.6))
    if facing != "north":
        parts.append(f'<ellipse cx="{hx - 3.4 + t}" cy="{hy - 1}" rx="2.6" ry="2.2" fill="#2a2420"/><ellipse cx="{hx + 3.4 + t}" cy="{hy - 1}" rx="2.6" ry="2.2" fill="#2a2420"/>')
        parts.append(f'<circle cx="{hx - 3.4 + t}" cy="{hy - 1}" r="1.2" fill="{eye}"/><circle cx="{hx + 3.4 + t}" cy="{hy - 1}" r="1.2" fill="{eye}"/>')
        parts.append(f'<path d="M{hx - 4} {hy + 4} L{hx - 2} {hy + 6.5} L{hx} {hy + 4} L{hx + 2} {hy + 6.5} L{hx + 4} {hy + 4}" fill="#fbf6e6" stroke="{INK}" stroke-width="1.2" stroke-linejoin="round"/>')
    return wrap("".join(parts))


def _held(svg_body, extra):
    return svg_body.replace("</svg>", extra + "</svg>")


def bow_prop(facing):
    if facing == "north":
        return '<path d="M40 30 L46 18" stroke="#8a5a33" stroke-width="4" stroke-linecap="round"/>'
    x = 46 if facing != "west" else 18
    s = 1 if facing != "west" else -1
    bow = f"M{x} 26 Q{x + s * 9} 40 {x} 54"
    return (f'<path d="{bow}" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
            f'<path d="{bow}" fill="none" stroke="#a8703e" stroke-width="3" stroke-linecap="round"/>'
            f'<path d="M{x} 26 L{x} 54" stroke="#efe6cc" stroke-width="1.2"/>'
            f'<path d="M{x - s * 12} 40 L{x + s * 4} 40" stroke="{INK}" stroke-width="3.6" stroke-linecap="round"/>'
            f'<path d="M{x - s * 12} 40 L{x + s * 4} 40" stroke="#d4dbe4" stroke-width="1.6" stroke-linecap="round"/>'
            f'<path d="M{x + s * 4} 37.5 L{x + s * 8} 40 L{x + s * 4} 42.5 Z" fill="#d4dbe4" stroke="{INK}" stroke-width="1.2"/>')


def shield_prop(facing, face=("#b0b8c0", "#8c949c"), boss="#d19e22"):
    if facing == "north":
        return shaded("shb", "M36 32 L50 32 L50 44 Q50 52 43 55 Q36 52 36 44 Z", *face, 1.2, 1)
    x = 24 if facing != "east" else 40
    d = f"M{x - 11} 34 L{x + 11} 34 L{x + 11} 46 Q{x + 11} 56 {x} 59 Q{x - 11} 56 {x - 11} 46 Z"
    return shaded("shf" + facing, d, *face, 2, 1.6) + f'<circle cx="{x}" cy="44" r="3.2" fill="{boss}" stroke="{INK}" stroke-width="1.6"/>'


def axe_prop(facing):
    s = -1 if facing == "west" else 1
    x = 32 + s * 17
    haft = f"M{x - s * 2} 58 L{x + s * 2} 24"
    head = f"M{x + s * 1} 22 Q{x + s * 12} 18 {x + s * 13} 30 Q{x + s * 6} 32 {x + s * 2} 30 Z"
    return (f'<path d="{haft}" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
            f'<path d="{haft}" stroke="#a8703e" stroke-width="3" stroke-linecap="round"/>'
            + shaded("axp" + facing, head, "#d4dbe4", "#a8b3c2", 1.2, 1))


def lantern_prop(facing):
    s = -1 if facing == "west" else 1
    x = 32 + s * 16
    return (f'<path d="M{x} 30 L{x} 38" stroke="{INK}" stroke-width="2.6"/>'
            + shaded("lnt" + facing, f"M{x - 5} 38 L{x + 5} 38 L{x + 6} 50 L{x - 6} 50 Z", "#3a3a44", "#2c2c34", 1, 1)
            + f'<path d="M{x - 3} 41 L{x + 3} 41 L{x + 3.6} 48 L{x - 3.6} 48 Z" fill="#9ae07a"/>'
            + f'<circle cx="{x}" cy="44.5" r="2" fill="#e8ffd0"/>'
            + f'<path d="M{x - 12} 30 L{x + 4} 30" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>')


import math  # noqa: E402  (used by the silhouettes above)


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
