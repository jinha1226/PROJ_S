"""Spell icons in the paper-doll style: 50 school spells and 12 basic ones.

Every icon is a card in its school's colours (dark ground, bright rim) with a
glyph built from the spell's data in combat.json: its shape (bolt, burst,
mark, wall, line, cone, self, summon) and its status (burn, freeze, slow,
confuse, bind ...). Conventions carry across schools: an "accumulate" spell
shows rising chevrons, every rank-10 "mastery" spell wears a crown.

Run: python3 tools/art/build_spells.py
"""
import itertools
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402
import build_potions as potions  # noqa: E402
from build_gear import rrect, circle  # noqa: E402

ROOT = flat.ROOT
OUT = ROOT / "assets/items-v1/spells"
REVIEW = ROOT / "docs/art/spells-v1"
INK = flat.INK
LINE = flat.LINE
_uid = itertools.count()


def S(path, fill, shade, dx=1.6, dy=1.4):
    return doll.shaded(f"g{next(_uid)}", path, fill, shade, dx, dy)


# school: ground, rim, main glyph colour + shade, light accent
SCHOOL = {
    "fire": ("#4a2420", "#ff7a3a", ("#ff8a2a", "#e0661a"), "#ffd84a"),
    "ice": ("#1c3150", "#7ac8ff", ("#9fdcff", "#6fb8e8"), "#e8f8ff"),
    "air": ("#1b3a48", "#6fe0ff", ("#ffd23a", "#e0ac1c"), "#c8f4ff"),
    "hex": ("#31204c", "#b98af0", ("#a06ae0", "#8050c0"), "#e6d4ff"),
    "summon": ("#1f3a28", "#8fd88a", ("#f1ead6", "#d4c9aa"), "#c8f0c0"),
    "poison": ("#233a1c", "#9ae05a", ("#7cd04a", "#5eae34"), "#d8ffb0"),
}


def card(school, body):
    ground, rim, _, _ = SCHOOL[school]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            f'<path d="{rrect(3, 3, 61, 61, 12)}" fill="{INK}"/>'
            f'<path d="{rrect(5.5, 5.5, 58.5, 58.5, 10)}" fill="{rim}"/>'
            f'<path d="{rrect(8.5, 8.5, 55.5, 55.5, 8)}" fill="{ground}"/>'
            f'<path d="M12 14 Q12 11 16 11 L30 11" fill="none" stroke="{rim}" stroke-width="2" stroke-linecap="round" opacity="0.6"/>'
            + body + '</svg>')


# --- glyphs ---------------------------------------------------------------

def flame(cx, cy, s, outer=("#ff8a2a", "#e0661a"), inner=("#ffd84a", "#f2b82a")):
    h, w = 22 * s, 11 * s
    base = cy + h * 0.45
    o = (f"M{cx} {base - h} Q{cx + w} {base - h * 0.45} {cx + w * 0.8} {base - h * 0.15} Q{cx + w * 0.6} {base} {cx} {base} "
         f"Q{cx - w * 0.6} {base} {cx - w * 0.8} {base - h * 0.15} Q{cx - w} {base - h * 0.45} {cx} {base - h} Z")
    i = (f"M{cx} {base - h * 0.6} Q{cx + w * 0.5} {base - h * 0.3} {cx + w * 0.35} {base - h * 0.1} Q{cx} {base + 1} "
         f"{cx - w * 0.35} {base - h * 0.1} Q{cx - w * 0.5} {base - h * 0.3} {cx} {base - h * 0.6} Z")
    return S(o, *outer) + S(i, *inner, 0.8, 0.8)


def snowflake(cx, cy, s, color="#9fdcff"):
    arm = 13 * s
    out = []
    for width, col in ((7 * s + 1.5, INK), (3 * s + 0.6, color)):
        for a in (0, 60, 120):
            out.append(f'<g transform="rotate({a} {cx} {cy})"><path d="M{cx} {cy - arm} L{cx} {cy + arm} M{cx} {cy - arm * 0.55} '
                       f'L{cx - arm * 0.3} {cy - arm * 0.85} M{cx} {cy - arm * 0.55} L{cx + arm * 0.3} {cy - arm * 0.85} '
                       f'M{cx} {cy + arm * 0.55} L{cx - arm * 0.3} {cy + arm * 0.85} M{cx} {cy + arm * 0.55} L{cx + arm * 0.3} {cy + arm * 0.85}" '
                       f'fill="none" stroke="{col}" stroke-width="{width}" stroke-linecap="round"/></g>')
    return "".join(out)


def lightning(cx, cy, s, colors=("#ffd23a", "#e0ac1c")):
    pts = [(2, -16), (-8, 2), (-1, 2), (-5, 16), (9, -3), (2, -3), (6, -16)]
    return S("M" + " L".join(f"{cx + x * s} {cy + y * s}" for x, y in pts) + " Z", *colors, 1.4, 1.2)


def ball(cx, cy, r, colors, core):
    return S(circle(cx, cy, r), *colors, 1.4, 1.2) + f'<circle cx="{cx - r * 0.3}" cy="{cy - r * 0.3}" r="{r * 0.35}" fill="{core}"/>'


def streaks(cx, cy, length, color, angle=225):
    out = []
    for i, off in enumerate((-5, 0, 5)):
        a = math.radians(angle)
        nx, ny = -math.sin(a) * off, math.cos(a) * off
        x0, y0 = cx + nx + math.cos(a) * 6, cy + ny + math.sin(a) * 6
        x1, y1 = x0 + math.cos(a) * length * (1 - abs(off) / 12), y0 + math.sin(a) * length * (1 - abs(off) / 12)
        out.append(f'<path d="M{x0} {y0} L{x1} {y1}" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
                   f'<path d="M{x0} {y0} L{x1} {y1}" stroke="{color}" stroke-width="2.6" stroke-linecap="round"/>')
    return "".join(out)


def burst(cx, cy, r, colors, core, points=8):
    return (S(potions.star(cx, cy, r, r * 0.52, points, -90 + 180 / points), *colors, 2, 1.8)
            + f'<circle cx="{cx}" cy="{cy}" r="{r * 0.3}" fill="{core}"/>')


def ring(cx, cy, r, color, dash=""):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{INK}" stroke-width="6"{d}/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{color}" stroke-width="2.8"{d}/>')


def reticle(cx, cy, r, color):
    ticks = "".join(f'<path d="M{cx + dx * r * 0.6} {cy + dy * r * 0.6} L{cx + dx * r * 1.3} {cy + dy * r * 1.3}" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
                    f'<path d="M{cx + dx * r * 0.6} {cy + dy * r * 0.6} L{cx + dx * r * 1.3} {cy + dy * r * 1.3}" stroke="{color}" stroke-width="2.6" stroke-linecap="round"/>'
                    for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)))
    return ring(cx, cy, r, color) + ticks


def figure(cx, cy, s, body=("#8a8f9c", "#707584")):
    """A tiny paper doll: rounded body, round head."""
    return (S(rrect(cx - 7 * s, cy, cx + 7 * s, cy + 12 * s, 5 * s), *body, 1.2, 1)
            + S(circle(cx, cy - 4 * s, 6 * s), "#f6c79a", "#e0a574", 1, 1))


def chevrons(cx, cy, color):
    return "".join(f'<path d="M{cx - 7} {cy + i * 7} L{cx} {cy - 6 + i * 7} L{cx + 7} {cy + i * 7}" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>'
                   f'<path d="M{cx - 7} {cy + i * 7} L{cx} {cy - 6 + i * 7} L{cx + 7} {cy + i * 7}" fill="none" stroke="{color}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>'
                   for i in range(2))


def crown(cx, cy, s=1.0):
    return S(f"M{cx - 11 * s} {cy + 6 * s} L{cx - 12 * s} {cy - 6 * s} L{cx - 5 * s} {cy} L{cx} {cy - 9 * s} L{cx + 5 * s} {cy} "
             f"L{cx + 12 * s} {cy - 6 * s} L{cx + 11 * s} {cy + 6 * s} Z", "#f5c84a", "#d19e22", 1.2, 1)


def swirl(cx, cy, s, color):
    d = (f"M{cx} {cy} m0 {-3 * s} a{3 * s} {3 * s} 0 1 1 {-3 * s} {3 * s} a{6 * s} {6 * s} 0 1 1 {6 * s} {6 * s} "
         f"a{9 * s} {9 * s} 0 1 1 {-9 * s} {-9 * s}")
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="3.2" stroke-linecap="round"/>')


def eye(cx, cy, s, iris="#b066e8"):
    return (S(f"M{cx - 14 * s} {cy} Q{cx} {cy - 11 * s} {cx + 14 * s} {cy} Q{cx} {cy + 11 * s} {cx - 14 * s} {cy} Z", "#f4ecd2", "#d6c6a2", 1, 1)
            + S(circle(cx, cy, 5.5 * s), iris, "#6a3aa8", 0.8, 0.8) + f'<circle cx="{cx}" cy="{cy}" r="{2.2 * s}" fill="{INK}"/>')


def hourglass(cx, cy, s=1.0):
    return (S(f"M{cx - 9 * s} {cy - 13 * s} L{cx + 9 * s} {cy - 13 * s} Q{cx + 9 * s} {cy - 4 * s} {cx} {cy} "
              f"Q{cx + 9 * s} {cy + 4 * s} {cx + 9 * s} {cy + 13 * s} L{cx - 9 * s} {cy + 13 * s} Q{cx - 9 * s} {cy + 4 * s} {cx} {cy} "
              f"Q{cx - 9 * s} {cy - 4 * s} {cx - 9 * s} {cy - 13 * s} Z", "#e6f5ff", "#c6e2f5", 1, 1)
            + f'<path d="M{cx - 5 * s} {cy - 9 * s} L{cx + 5 * s} {cy - 9 * s} L{cx} {cy - 2 * s} Z M{cx - 6 * s} {cy + 11 * s} Q{cx} {cy + 4 * s} {cx + 6 * s} {cy + 11 * s} Z" fill="#f5c84a"/>')


def wall(kind):
    out = []
    for i, x in enumerate((18, 32, 46)):
        if kind == "fire":
            out.append(flame(x, 32, 0.85))
        else:
            out.append(S(rrect(x - 6, 22, x + 6, 44, 2), "#bfe6ff", "#8cc6ee", 1.2, 1)
                       + f'<path d="M{x - 3} 26 L{x - 3} 34" stroke="#ffffff" stroke-width="2" stroke-linecap="round"/>')
    out.append(f'<path d="M12 46 L52 46" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>')
    return "".join(out)


def spear(x0, y0, x1, y1, width, colors, tip=True):
    a = math.atan2(y1 - y0, x1 - x0)
    nx, ny = -math.sin(a) * width / 2, math.cos(a) * width / 2
    tx, ty = x1 + math.cos(a) * width * 1.6, y1 + math.sin(a) * width * 1.6
    path = f"M{x0 + nx} {y0 + ny} L{x1 + nx} {y1 + ny} L{tx} {ty} L{x1 - nx} {y1 - ny} L{x0 - nx} {y0 - ny} Z"
    return S(path, *colors, 1.2, 1)


def cone(color_pair, accent):
    return (S("M14 50 L50 14 Q58 30 50 50 Q34 58 14 50 Z", *color_pair, 1.8, 1.6)
            + f'<path d="M22 42 L44 22 M26 48 L48 30" stroke="{accent}" stroke-width="2.4" stroke-linecap="round"/>')


def chains():
    out = []
    for i, (x, y) in enumerate(((16, 42), (26, 34), (36, 26), (46, 18))):
        out.append(f'<g transform="rotate(-45 {x} {y})"><rect x="{x - 7}" y="{y - 4}" width="14" height="8" rx="4" fill="none" stroke="{INK}" stroke-width="6"/>'
                   f'<rect x="{x - 7}" y="{y - 4}" width="14" height="8" rx="4" fill="none" stroke="#c9d1dc" stroke-width="2.6"/></g>')
    return "".join(out)


def crack(cx, cy, s, color=INK):
    return f'<path d="M{cx - 2 * s} {cy - 10 * s} L{cx + 2 * s} {cy - 3 * s} L{cx - 3 * s} {cy + 2 * s} L{cx + 2 * s} {cy + 10 * s}" fill="none" stroke="{color}" stroke-width="2.6" stroke-linejoin="round"/>'


def crystal(cx, cy, s, colors=("#bfe6ff", "#8cc6ee")):
    return S(f"M{cx} {cy - 16 * s} L{cx + 10 * s} {cy - 4 * s} L{cx + 6 * s} {cy + 14 * s} L{cx - 6 * s} {cy + 14 * s} L{cx - 10 * s} {cy - 4 * s} Z", *colors, 1.6, 1.4)


def branches(cx, cy, color):
    out = [S(circle(cx - 12, cy + 8, 5), "#b066e8", "#8a48c8", 0.8, 0.8)]
    for x, y in ((cx + 12, cy - 12), (cx + 14, cy + 8), (cx - 4, cy - 16)):
        out.insert(0, f'<path d="M{cx - 12} {cy + 8} L{x} {y}" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
                      f'<path d="M{cx - 12} {cy + 8} L{x} {y}" stroke="{color}" stroke-width="2.6" stroke-linecap="round"/>')
        out.append(S(circle(x, y, 4), "#e6d4ff", "#c0a8ea", 0.6, 0.6))
    return "".join(out)


def head(kind, cx, cy, s=1.0):
    fur = {"hound": ("#b0784a", "#8e5c36"), "imp": ("#d8503a", "#b83c2c"), "rat": ("#8f8f9c", "#737382"), "wolf": ("#9aa0ac", "#7c8290")}[kind]
    out = []
    if kind in ("hound",):
        out.append(S(f"M{cx - 10 * s} {cy - 4 * s} L{cx - 14 * s} {cy + 8 * s} L{cx - 6 * s} {cy + 4 * s} Z", "#8e5c36", "#6e4428", 0.8, 0.8))
        out.append(S(f"M{cx + 10 * s} {cy - 4 * s} L{cx + 14 * s} {cy + 8 * s} L{cx + 6 * s} {cy + 4 * s} Z", "#8e5c36", "#6e4428", 0.8, 0.8))
    if kind in ("wolf",):
        out.append(S(f"M{cx - 9 * s} {cy - 4 * s} L{cx - 9 * s} {cy - 16 * s} L{cx - 2 * s} {cy - 8 * s} Z", *fur, 0.8, 0.8))
        out.append(S(f"M{cx + 9 * s} {cy - 4 * s} L{cx + 9 * s} {cy - 16 * s} L{cx + 2 * s} {cy - 8 * s} Z", *fur, 0.8, 0.8))
    if kind == "imp":
        out.append(S(f"M{cx - 7 * s} {cy - 7 * s} L{cx - 12 * s} {cy - 17 * s} L{cx - 3 * s} {cy - 10 * s} Z", "#efe2c0", "#d2c29a", 0.6, 0.6))
        out.append(S(f"M{cx + 7 * s} {cy - 7 * s} L{cx + 12 * s} {cy - 17 * s} L{cx + 3 * s} {cy - 10 * s} Z", "#efe2c0", "#d2c29a", 0.6, 0.6))
    if kind == "rat":
        out.append(S(circle(cx - 8 * s, cy - 8 * s, 4.5 * s), "#e9a0a6", "#cf8288", 0.6, 0.6))
        out.append(S(circle(cx + 8 * s, cy - 8 * s, 4.5 * s), "#e9a0a6", "#cf8288", 0.6, 0.6))
    out.append(S(circle(cx, cy, 10 * s), *fur, 1.4, 1.2))
    if kind in ("hound", "wolf", "rat"):
        out.append(S(f"M{cx - 5 * s} {cy + 3 * s} Q{cx} {cy + 12 * s} {cx + 5 * s} {cy + 3 * s} Z", "#f1ead6" if kind != "rat" else "#b8b8c4", "#d4c9aa", 0.6, 0.6))
        out.append(f'<ellipse cx="{cx}" cy="{cy + 4 * s}" rx="{2.2 * s}" ry="{1.6 * s}" fill="{INK}"/>')
    eye_color = "#ffd84a" if kind == "imp" else INK
    out.append(f'<rect x="{cx - 5 * s}" y="{cy - 4 * s}" width="{3 * s}" height="{5 * s}" rx="{1.5 * s}" fill="{eye_color}"/>'
               f'<rect x="{cx + 2 * s}" y="{cy - 4 * s}" width="{3 * s}" height="{5 * s}" rx="{1.5 * s}" fill="{eye_color}"/>')
    return "".join(out)


def paw(cx, cy, s=1.0, colors=("#f1ead6", "#d4c9aa")):
    return (S(f"M{cx - 8 * s} {cy + 6 * s} Q{cx - 8 * s} {cy - 2 * s} {cx} {cy - 2 * s} Q{cx + 8 * s} {cy - 2 * s} {cx + 8 * s} {cy + 6 * s} "
              f"Q{cx + 8 * s} {cy + 10 * s} {cx + 4 * s} {cy + 10 * s} Q{cx} {cy + 8 * s} {cx - 4 * s} {cy + 10 * s} Q{cx - 8 * s} {cy + 10 * s} {cx - 8 * s} {cy + 6 * s} Z", *colors, 1, 1)
            + "".join(S(circle(cx + x * s, cy + y * s, 3 * s), *colors, 0.5, 0.5) for x, y in ((-8, -7), (-3, -11), (3, -11), (8, -7))))


def cloud(cx, cy, s, colors):
    return S(f"M{cx - 16 * s} {cy + 8 * s} Q{cx - 22 * s} {cy + 8 * s} {cx - 20 * s} {cy} Q{cx - 18 * s} {cy - 6 * s} {cx - 10 * s} {cy - 4 * s} "
             f"Q{cx - 8 * s} {cy - 14 * s} {cx + 2 * s} {cy - 13 * s} Q{cx + 12 * s} {cy - 13 * s} {cx + 12 * s} {cy - 4 * s} "
             f"Q{cx + 22 * s} {cy - 4 * s} {cx + 20 * s} {cy + 4 * s} Q{cx + 20 * s} {cy + 8 * s} {cx + 14 * s} {cy + 8 * s} Z", *colors, 1.6, 1.4)


def heart(cx, cy, s, colors=("#ec4a4a", "#c63434")):
    return S(f"M{cx} {cy + 12 * s} L{cx - 12 * s} {cy} Q{cx - 16 * s} {cy - 8 * s} {cx - 8 * s} {cy - 11 * s} Q{cx - 2 * s} {cy - 12 * s} {cx} {cy - 5 * s} "
             f"Q{cx + 2 * s} {cy - 12 * s} {cx + 8 * s} {cy - 11 * s} Q{cx + 16 * s} {cy - 8 * s} {cx + 12 * s} {cy} Z", *colors, 1.4, 1.2)


# --- compositions ----------------------------------------------------------

F = SCHOOL["fire"][2]
I = SCHOOL["ice"][2]
H = SCHOOL["hex"][2]
WHITE_HOT = ("#fff4c8", "#ffd88a")
ICE_SPEAR = ("#bfe6ff", "#8cc6ee")
ELECTRIC = ("#6fe0ff", "#3fbce0")

SPELLS = {
    "fire_1": ("fire", streaks(34, 30, 18, "#ffb03a") + ball(35, 29, 12, F, "#ffd84a")),
    "fire_2": ("fire", flame(26, 32, 1.1) + chevrons(46, 30, "#ffd84a")),
    "fire_3": ("fire", burst(32, 32, 20, F, "#ffd84a")),
    "fire_4": ("fire", reticle(32, 32, 16, "#ff7a3a") + flame(32, 32, 0.7)),
    "fire_5": ("fire", ring(32, 34, 20, "#ffb03a", "4 4") + figure(32, 32, 1.4) + flame(20, 22, 0.5) + flame(44, 22, 0.5)),
    "fire_6": ("fire", wall("fire")),
    "fire_7": ("fire", flame(18, 42, 0.7) + flame(32, 32, 0.75) + flame(46, 22, 0.7)
               + '<path d="M20 36 L28 32 M36 26 L44 22" stroke="#ffd84a" stroke-width="2.6" stroke-dasharray="3 3"/>'),
    "fire_8": ("fire", streaks(34, 30, 20, "#fff4c8") + ball(35, 29, 14, WHITE_HOT, "#ffffff")),
    "fire_9": ("fire", ring(32, 32, 22, "#ff7a3a", "6 4") + burst(32, 32, 17, F, "#ffd84a", 10)),
    "fire_10": ("fire", flame(32, 38, 1.0) + crown(32, 15, 0.9)),
    "ice_1": ("ice", spear(14, 50, 44, 20, 8, ICE_SPEAR)),
    "ice_2": ("ice", snowflake(26, 34, 1.1) + chevrons(47, 30, "#e8f8ff")),
    "ice_3": ("ice", reticle(32, 32, 16, "#7ac8ff") + snowflake(32, 32, 0.8)),
    "ice_4": ("ice", cone(I, "#e8f8ff") + hourglass(44, 44, 0.55)),
    "ice_5": ("ice", crystal(32, 32, 1.3) + crack(32, 32, 1.3)),
    "ice_6": ("ice", wall("ice")),
    "ice_7": ("ice", cone(I, "#e8f8ff") + snowflake(46, 22, 0.45) + snowflake(40, 42, 0.4)),
    "ice_8": ("ice", ring(32, 32, 22, "#e8f8ff", "5 4") + snowflake(32, 32, 1.4, "#ffffff")),
    "ice_9": ("ice", spear(10, 54, 46, 18, 12, ICE_SPEAR)),
    "ice_10": ("ice", snowflake(32, 38, 1.0) + crown(32, 15, 0.9)),
    "air_1": ("air", lightning(32, 32, 1.4)),
    "air_2": ("air", lightning(26, 32, 1.2) + chevrons(47, 30, "#c8f4ff")),
    "air_3": ("air", "".join(f'<path d="M10 {y} Q30 {y - 8} 52 {y}" fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round"/>'
                             f'<path d="M10 {y} Q30 {y - 8} 52 {y}" fill="none" stroke="#c8f4ff" stroke-width="3.6" stroke-linecap="round"/>' for y in (24, 36, 48))),
    "air_4": ("air", burst(32, 32, 18, ELECTRIC, "#ffffff") + lightning(32, 32, 0.6)),
    "air_5": ("air", '<path d="M12 44 L22 30 L28 40 L38 22 L44 34 L52 18" fill="none" stroke="#1c1b22" stroke-width="8" stroke-linejoin="round" stroke-linecap="round"/>'
              '<path d="M12 44 L22 30 L28 40 L38 22 L44 34 L52 18" fill="none" stroke="#ffd23a" stroke-width="3.6" stroke-linejoin="round" stroke-linecap="round"/>'
              + "".join(S(circle(x, y, 4), "#6fe0ff", "#3fbce0", 0.6, 0.6) for x, y in ((12, 44), (28, 40), (44, 34)))),
    "air_6": ("air", ring(32, 32, 22, "#6fe0ff", "6 4") + burst(32, 32, 16, ELECTRIC, "#ffffff", 10)),
    "air_7": ("air", spear(10, 50, 48, 18, 10, ("#ffd23a", "#e0ac1c")) + '<path d="M20 30 L26 26 M34 44 L40 40" stroke="#c8f4ff" stroke-width="2.6" stroke-linecap="round"/>'),
    "air_8": ("air", swirl(33, 30, 1.25, "#c8f4ff") + eye(32, 32, 0.55, "#6fe0ff")),
    "air_9": ("air", cloud(32, 20, 0.9, ("#8a93a8", "#6a7388")) + lightning(33, 42, 0.9)),
    "air_10": ("air", lightning(32, 38, 1.0) + crown(32, 15, 0.9)),
    "hex_1": ("hex", figure(32, 36, 1.3) + swirl(32, 16, 0.9, "#e6d4ff")),
    "hex_2": ("hex", figure(24, 36, 1.2, ("#8a6ab0", "#6c5090")) + f'<path d="M46 20 L46 42 M39 35 L46 42 L53 35" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>'
              '<path d="M46 20 L46 42 M39 35 L46 42 L53 35" fill="none" stroke="#ff7a6a" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>'),
    "hex_3": ("hex", chains()),
    "hex_4": ("hex", hourglass(26, 32, 1.0) + f'<path d="M44 26 L44 40 M37 33 L51 33" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
              '<path d="M44 26 L44 40 M37 33 L51 33" stroke="#e6d4ff" stroke-width="3.2" stroke-linecap="round"/>'),
    "hex_5": ("hex", eye(32, 32, 1.2) + '<path d="M10 46 Q18 40 26 46 Q34 52 42 46 Q48 42 54 46" fill="none" stroke="#e6d4ff" stroke-width="2.6"/>'),
    "hex_6": ("hex", S("M32 8 L52 16 Q52 42 32 56 Q12 42 12 16 Z", "#8a93a8", "#6a7388", 2, 1.8) + crack(32, 32, 2.2, "#1c1b22")
              + '<path d="M26 20 L30 30 L24 38" fill="none" stroke="#ff7a6a" stroke-width="2.6" stroke-linejoin="round"/>'),
    "hex_7": ("hex", burst(32, 32, 20, H, "#e6d4ff") + swirl(32, 32, 0.8, "#e6d4ff")),
    "hex_8": ("hex", branches(32, 32, "#e6d4ff")),
    "hex_9": ("hex", figure(32, 40, 1.2, ("#8a6ab0", "#6c5090")) + crown(32, 18, 0.8)
              + '<path d="M22 12 L24 30 M42 12 L40 30" stroke="#e6d4ff" stroke-width="1.6" stroke-dasharray="2 2"/>'),
    "hex_10": ("hex", eye(32, 40, 1.0) + crown(32, 17, 0.9)),
    "summon_1": ("summon", ring(32, 34, 20, "#8fd88a", "4 4") + head("hound", 32, 34, 1.3)),
    "summon_2": ("summon", ring(24, 32, 11, "#f5c84a") + ring(40, 32, 11, "#8fd88a")),
    "summon_3": ("summon", ring(32, 34, 20, "#8fd88a", "4 4") + head("imp", 32, 36, 1.2)),
    "summon_4": ("summon", paw(26, 32, 1.1) + hourglass(46, 32, 0.55)),
    "summon_5": ("summon", burst(32, 32, 19, ("#ec4a4a", "#c63434"), "#ffd0a0") + paw(32, 32, 0.7)),
    "summon_6": ("summon", head("rat", 20, 38, 0.8) + head("rat", 44, 38, 0.8) + head("rat", 32, 24, 0.85)),
    "summon_7": ("summon", ring(32, 34, 20, "#8fd88a", "4 4") + head("wolf", 32, 36, 1.3)),
    "summon_8": ("summon", ring(32, 32, 22, "#c8f0c0", "3 3") + ring(32, 32, 14, "#8fd88a") + paw(32, 30, 0.7)),
    "summon_9": ("summon", head("wolf", 20, 40, 0.85) + head("wolf", 44, 40, 0.85) + head("wolf", 32, 26, 0.95)),
    "summon_10": ("summon", paw(32, 38, 1.2) + crown(32, 15, 0.9)),
    # The twelve basic spells.
    "bolt": ("fire", streaks(34, 30, 18, "#ffb03a") + ball(35, 29, 12, F, "#ffd84a")),
    "blast": ("fire", burst(32, 32, 20, F, "#ffd84a")),
    "cone": ("ice", cone(I, "#e8f8ff")),
    "cloud": ("poison", cloud(32, 30, 1.1, ("#7cd04a", "#5eae34")) + '<circle cx="24" cy="46" r="3" fill="#b8f08a"/><circle cx="36" cy="50" r="2.4" fill="#b8f08a"/>'),
    "confuse": ("hex", figure(32, 36, 1.3) + swirl(32, 16, 0.9, "#e6d4ff")),
    "blink": ("air", swirl(32, 31, 1.25, "#c8f4ff") + S(circle(46, 18, 5), "#6fe0ff", "#3fbce0", 0.6, 0.6)),
    "passwall": ("air", S(rrect(28, 12, 38, 52, 2), "#8a93a8", "#6a7388", 1, 1) + figure(18, 30, 1.0) + figure(46, 30, 1.0, ("#6fe0ff", "#3fbce0"))),
    "ward": ("ice", S("M32 8 L52 16 Q52 42 32 56 Q12 42 12 16 Z", *ICE_SPEAR, 2, 1.8) + snowflake(32, 30, 0.7, "#ffffff")),
    "hound": ("summon", ring(32, 34, 20, "#8fd88a", "4 4") + head("hound", 32, 34, 1.3)),
    "turret": ("summon", S(rrect(20, 30, 44, 52, 3), "#8a93a8", "#6a7388", 1.4, 1.2) + S(rrect(24, 20, 40, 32, 3), "#a7adba", "#848b9a", 1, 1)
               + spear(38, 26, 54, 18, 5, ("#c9d1dc", "#9aa3b3"), False)),
    "ignite": ("poison", flame(32, 32, 1.2, ("#7cd04a", "#5eae34"), ("#e0ffb0", "#b8f08a"))),
    "mend": ("hex", heart(26, 34, 1.1) + '<path d="M40 22 Q52 28 44 40" fill="none" stroke="#1c1b22" stroke-width="7" stroke-linecap="round"/>'
             '<path d="M40 22 Q52 28 44 40" fill="none" stroke="#e6d4ff" stroke-width="3.2" stroke-linecap="round"/>'
             '<path d="M40 40 L44 40 L44 36" fill="none" stroke="#e6d4ff" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>'),
}


def main() -> None:
    (OUT / "svg").mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    jobs = []
    for sid, (school, body) in SPELLS.items():
        source = OUT / "svg" / f"{sid}.svg"
        source.write_text(card(school, body))
        jobs.append((source, OUT / f"{sid}.png", 2))
    flat.rasterise(jobs)

    font = ImageFont.truetype(str(ROOT / "assets/fonts/Jua-Regular.ttf"), 15)
    cell, pad, cols = 88, 10, 10
    ids = list(SPELLS)
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGBA", (pad + cols * (cell + pad), rows * (cell + 26) + pad), "#2a2b36")
    draw = ImageDraw.Draw(sheet)
    for i, sid in enumerate(ids):
        x, y = pad + (i % cols) * (cell + pad), pad + (i // cols) * (cell + 26)
        sheet.alpha_composite(Image.open(OUT / f"{sid}.png").convert("RGBA").resize((cell, cell), Image.LANCZOS), (x, y))
        draw.text((x + cell // 2, y + cell + 11), sid, font=font, fill="#f2eee4", anchor="mm")
    sheet.convert("RGB").save(REVIEW / "spells-sheet.png")


if __name__ == "__main__":
    main()
