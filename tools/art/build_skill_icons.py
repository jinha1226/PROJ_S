"""Skill icons for every active a member can use: the species actives, the
two basic actions and the three boss-stone actives.

Same card as the spell icons (tools/art/build_spells.py) so they sit side by
side on the battle bar, but the rim follows the essence's ROLE instead of a
spell school, so a player reads "what kind of move" at a glance:
PACK amber, BERSERK red, AMBUSH teal, GUARD steel, ARCHER olive, basic
actions bone, boss stones gold. File names are the ids in abilities.gd /
essences.json.

Run: python3 tools/art/build_skill_icons.py
"""
import itertools
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402
from build_gear import rrect, circle  # noqa: E402

ROOT = flat.ROOT
OUT = ROOT / "assets/items-v1/skills"
REVIEW = ROOT / "docs/art/skills-v1"
INK = flat.INK
LINE = flat.LINE
THIN = f'stroke="{INK}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"'
_uid = itertools.count()

# role: ground, rim
ROLE = {
    "PACK": ("#3b2a18", "#f0a848"),
    "BERSERK": ("#461a1a", "#f0503c"),
    "AMBUSH": ("#15342c", "#4fd8a8"),
    "GUARD": ("#252c38", "#b8c6d8"),
    "ARCHER": ("#2c3314", "#cad84a"),
    "BASIC": ("#2e2a26", "#e2d6b8"),
    "BOSS": ("#3a2a0e", "#f6c64a"),
}

BONE = ("#efe6cc", "#cfc4a4")
STEEL = ("#d4dbe4", "#a8b3c2")
DARK_STEEL = ("#8e98a8", "#6c7686")
WOOD = ("#a8703e", "#865630")
BLOOD = ("#d8323e", "#a82430")
GREEN = ("#7cd04a", "#5eae34")
WATER = ("#5aa8f0", "#3a84cc")
STONE = ("#9a8e82", "#786e64")
GOLD = ("#f2c64b", "#d19e22")
PURPLE = ("#a06ae0", "#8050c0")
WHITE = ("#ffffff", "#dde4ee")


def S(path, fill, shade, dx=1.6, dy=1.4):
    return doll.shaded(f"k{next(_uid)}", path, fill, shade, dx, dy)


def poly(points):
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in points) + " Z"


def ellipse(cx, cy, rx, ry):
    return f"M{cx - rx} {cy} A{rx} {ry} 0 1 0 {cx + rx} {cy} A{rx} {ry} 0 1 0 {cx - rx} {cy} Z"


def stroke(d, color, width=3.2):
    """A line with an ink edge."""
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{width + 2.6}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')


def swoosh(d, color="#ffffff", width=2.4, opacity=0.85):
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" opacity="{opacity}"/>'


def card(role, body):
    ground, rim = ROLE[role]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            f'<path d="{rrect(3, 3, 61, 61, 12)}" fill="{INK}"/>'
            f'<path d="{rrect(5.5, 5.5, 58.5, 58.5, 10)}" fill="{rim}"/>'
            f'<path d="{rrect(8.5, 8.5, 55.5, 55.5, 8)}" fill="{ground}"/>'
            f'<path d="M12 14 Q12 11 16 11 L30 11" fill="none" stroke="{rim}" stroke-width="2" stroke-linecap="round" opacity="0.6"/>'
            + body + '</svg>')


# --- shared pieces --------------------------------------------------------------

def shield(cx, cy, s, face=STEEL, boss=DARK_STEEL):
    w, h = 12 * s, 15 * s
    d = f"M{cx - w} {cy - h} L{cx + w} {cy - h} L{cx + w} {cy} Q{cx + w} {cy + h * 0.8} {cx} {cy + h} Q{cx - w} {cy + h * 0.8} {cx - w} {cy} Z"
    return S(d, *face, 2.0, 1.6) + f'<circle cx="{cx}" cy="{cy - h * 0.2}" r="{3 * s}" fill="{boss[0]}" {THIN}/>'


def blade(x0, y0, x1, y1, width=4.5, face=STEEL):
    """A straight blade from hilt (x0,y0) to tip (x1,y1), with a cross-guard."""
    dx, dy = x1 - x0, y1 - y0
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n
    px, py = -uy, ux
    w = width / 2
    body = poly([(x0 + px * w, y0 + py * w), (x1 - ux * 5 + px * w, y1 - uy * 5 + py * w), (x1, y1),
                 (x1 - ux * 5 - px * w, y1 - uy * 5 - py * w), (x0 - px * w, y0 - py * w)])
    gx, gy = x0 + ux * 2, y0 + uy * 2
    guard = stroke(f"M{gx + px * 7:.1f} {gy + py * 7:.1f} L{gx - px * 7:.1f} {gy - py * 7:.1f}", GOLD[0], 2.6)
    grip = stroke(f"M{x0:.1f} {y0:.1f} L{x0 - ux * 8:.1f} {y0 - uy * 8:.1f}", WOOD[0], 3)
    return grip + S(body, *face, 1.2, 1) + guard


def drop(cx, cy, s, colour=BLOOD):
    return S(f"M{cx} {cy - 8 * s} Q{cx + 6 * s} {cy} {cx + 5 * s} {cy + 3 * s} Q{cx + 4 * s} {cy + 7 * s} {cx} {cy + 7 * s} "
             f"Q{cx - 4 * s} {cy + 7 * s} {cx - 5 * s} {cy + 3 * s} Q{cx - 6 * s} {cy} {cx} {cy - 8 * s} Z", *colour, 1, 1)


def tooth_row(y, x0, x1, n, down=True, colour=BONE):
    step = (x1 - x0) / n
    pts = []
    for i in range(n):
        a = x0 + i * step
        pts += [(a, y), (a + step / 2, y + (7 if down else -7)), (a + step, y)]
    pts.append((x1, y - (3 if down else -3)))
    pts.append((x0, y - (3 if down else -3)))
    return S(poly(pts), *colour, 0.8, 0.8)


def arrow(x0, y0, x1, y1, shaft=WOOD, head=STEEL, fletch="#e0453a"):
    dx, dy = x1 - x0, y1 - y0
    n = math.hypot(dx, dy)
    ux, uy = dx / n, dy / n
    px, py = -uy, ux
    tip = poly([(x1, y1), (x1 - ux * 8 + px * 4.5, y1 - uy * 8 + py * 4.5), (x1 - ux * 8 - px * 4.5, y1 - uy * 8 - py * 4.5)])
    fl = poly([(x0, y0), (x0 + ux * 6 + px * 4, y0 + uy * 6 + py * 4), (x0 + ux * 9, y0 + uy * 9),
               (x0 + ux * 6 - px * 4, y0 + uy * 6 - py * 4)])
    return (stroke(f"M{x0:.1f} {y0:.1f} L{x1 - ux * 6:.1f} {y1 - uy * 6:.1f}", shaft[0], 2.6)
            + S(tip, *head, 0.8, 0.8) + f'<path d="{fl}" fill="{fletch}" {THIN}/>')


def motion(lines):
    return "".join(swoosh(f"M{x0} {y0} L{x1} {y1}", "#ffffff", 2.2, 0.7) for x0, y0, x1, y1 in lines)


# --- icons ------------------------------------------------------------------------

def push():
    """An open palm shoving right."""
    palm = S("M18 22 Q18 18 22 18 L40 18 Q44 18 44 22 L44 42 Q44 46 40 46 L22 46 Q18 46 18 42 Z", "#f6c79a", "#e0a574")
    thumb = S("M18 30 Q12 30 12 36 Q12 40 18 40 Z", "#f6c79a", "#e0a574", 1, 1)
    fingers = "".join(f'<path d="M44 {y} L50 {y}" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
                      f'<path d="M44 {y} L50 {y}" stroke="#f6c79a" stroke-width="3.4" stroke-linecap="round"/>' for y in (22, 28.5, 35, 41.5))
    return card("BASIC", motion([(8, 26, 12, 26), (8, 44, 12, 44)]) + thumb + palm + fingers
                + '<path d="M24 26 Q30 24 36 26" fill="none" stroke="#e0a574" stroke-width="2" stroke-linecap="round"/>')


def guard():
    ally = S(ellipse(40, 26, 6, 6), "#f6c79a", "#e0a574") + S("M31 50 Q31 36 40 36 Q49 36 49 50 Z", "#4f6fb5", "#3e5a97")
    return card("BASIC", ally + shield(24, 34, 1.1))


def rat_gnaw():
    return card("PACK", tooth_row(22, 14, 50, 5) + tooth_row(42, 14, 50, 5, down=False)
                + swoosh("M12 32 Q32 26 52 32", "#ffffff", 1.6, 0.4) + drop(46, 48, 0.5))


def lizard_tail():
    tail = S("M14 44 Q20 26 36 22 Q50 20 52 30 Q46 26 38 28 Q26 32 22 46 Z", "#8fb04a", "#74933a")
    spikes = "".join(f'<path d="M{x} {y} l3 -5 l2 5 Z" fill="#f08a3a" {THIN}/>' for x, y in ((28, 25), (35, 22), (42, 21)))
    return card("BERSERK", swoosh("M10 36 Q30 58 54 38", "#ffffff", 2.6, 0.7) + tail + spikes)


def kobold_sling():
    strap = stroke("M14 44 Q20 26 30 30 Q34 32 30 40", "#8a5a33", 2.4)
    stone = S(ellipse(44, 22, 8, 7), *STONE)
    return card("ARCHER", strap + motion([(30, 30, 36, 26), (30, 36, 38, 30)]) + stone)


def goblin_shiv():
    return card("AMBUSH", motion([(10, 46, 20, 40), (12, 52, 22, 46), (18, 50, 26, 44)]) + blade(22, 44, 48, 18, 5))


def hob_taunt():
    waves = "".join(swoosh(f"M{42 + i * 5} {22 - i * 2} Q{48 + i * 6} 32 {42 + i * 5} {42 + i * 2}", "#ffffff", 2.4, 0.9 - i * 0.2) for i in range(3))
    club = stroke("M16 48 L30 22", WOOD[0], 4.5) + S(ellipse(31, 20, 5, 6.5), *WOOD)
    return card("GUARD", shield(28, 34, 0.95) + club + waves)


def goblin_aim():
    ring = (f'<circle cx="32" cy="32" r="15" fill="none" stroke="{INK}" stroke-width="5"/>'
            f'<circle cx="32" cy="32" r="15" fill="none" stroke="#e0453a" stroke-width="2.6"/>'
            + "".join(stroke(d, "#e0453a", 2.4) for d in ("M32 12 L32 20", "M32 44 L32 52", "M12 32 L20 32", "M44 32 L52 32")))
    return card("ARCHER", ring + arrow(14, 50, 32, 32))


def shield_stance():
    brace = "".join(stroke(f"M{x} 54 L{x + 4} 48", "#ffffff", 1.6) for x in (16, 44))
    return card("GUARD", S("M16 14 L48 14 L48 40 Q48 52 32 56 Q16 52 16 40 Z", *STEEL, 2.4, 1.8)
                + stroke("M32 18 L32 50 M20 30 L44 30", DARK_STEEL[0], 2.6) + brace)


def orc_cleaver():
    arc = swoosh("M12 40 A22 22 0 0 1 48 16", "#ffffff", 3, 0.75)
    handle = stroke("M20 50 L40 24", WOOD[0], 3.6)
    head = S("M36 16 Q48 12 52 22 Q48 30 40 30 Z", *STEEL, 1.4, 1.2)
    return card("BERSERK", arc + handle + head)


def orc_throw():
    spin = "".join(swoosh(f"M{32 + 16 * math.cos(a):.1f} {32 + 16 * math.sin(a):.1f} A16 16 0 0 1 {32 + 16 * math.cos(a + 1):.1f} {32 + 16 * math.sin(a + 1):.1f}", "#ffffff", 2.4, 0.7)
                   for a in (0.4, 2.5, 4.6))
    handle = stroke("M26 40 L38 24", WOOD[0], 3)
    head = S("M34 20 Q44 16 46 26 Q42 32 36 28 Z", *STEEL, 1.2, 1)
    return card("ARCHER", spin + motion([(10, 48, 18, 42)]) + handle + head)


def spider_web():
    spokes = "".join(f'<path d="M32 32 L{32 + 21 * math.cos(a):.1f} {32 + 21 * math.sin(a):.1f}" stroke="#ffffff" stroke-width="1.6" opacity="0.9"/>'
                     for a in [i * math.pi / 4 for i in range(8)])
    rings = "".join(f'<path d="{poly([(32 + r * math.cos(i * math.pi / 4), 32 + r * math.sin(i * math.pi / 4)) for i in range(8)])}" '
                    f'fill="none" stroke="#ffffff" stroke-width="1.6" opacity="0.9"/>' for r in (7, 13, 19))
    spider = S(ellipse(40, 40, 5, 4.5), "#3a3040", "#2a2230") + "".join(
        f'<path d="M40 40 l{dx} {dy}" stroke="{INK}" stroke-width="1.6"/>' for dx, dy in ((-8, -4), (-8, 4), (8, -4), (8, 4)))
    return card("AMBUSH", spokes + rings + spider)


def beetle_curl():
    ball = S(circle(32, 34, 17), "#6a5a44", "#4e4232", 2.4, 2)
    plates = "".join(f'<path d="M{32 + 17 * math.cos(a):.1f} {34 + 17 * math.sin(a):.1f} Q32 34 {32 + 17 * math.cos(a + 2.4):.1f} {34 + 17 * math.sin(a + 2.4):.1f}" fill="none" stroke="{INK}" stroke-width="1.8"/>'
                     for a in (-2.2, -1.2, -0.2))
    ring = f'<circle cx="32" cy="34" r="22" fill="none" stroke="#b8c6d8" stroke-width="2.4" stroke-dasharray="5 3"/>'
    return card("GUARD", ring + ball + plates + '<path d="M22 26 Q26 20 32 19" fill="none" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round"/>')


def ore_slam():
    """A stone fist driven down, knuckles first, cracking the floor."""
    wrist = S("M24 8 L40 8 L40 20 L24 20 Z", *STONE, 1.2, 1)
    fist = S("M16 22 Q16 18 20 18 L44 18 Q48 18 48 22 L48 36 L16 36 Z", *STONE, 2, 1.6)
    knuckles = "".join(S(ellipse(x, 38, 4.4, 4), *STONE, 1, 1) for x in (21, 29.5, 38, 46 - 1.5))
    seam = '<path d="M20 26 L28 28 L34 25 L42 28" fill="none" stroke="#ffa030" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'
    crack = stroke("M32 46 L27 51 L33 54 L29 58 M32 46 L41 51 M32 46 L22 49", "#ffffff", 1.8)
    return card("BERSERK", wrist + fist + knuckles + seam + crack)


def leech_latch():
    mouth = S(circle(30, 30, 14), "#6a4a5a", "#4e3644", 2, 1.6)
    ring = "".join(f'<path d="M{30 + 9 * math.cos(a):.1f} {30 + 9 * math.sin(a):.1f} L{30 + 4.5 * math.cos(a + 0.2):.1f} {30 + 4.5 * math.sin(a + 0.2):.1f} L{30 + 9 * math.cos(a + 0.4):.1f} {30 + 9 * math.sin(a + 0.4):.1f} Z" fill="#efe6cc" {THIN}/>'
                   for a in [i * math.pi / 5 for i in range(10)])
    return card("AMBUSH", mouth + f'<circle cx="30" cy="30" r="9" fill="#2a1a22"/>' + ring + drop(46, 44, 0.8))


def toad_spit():
    arc = swoosh("M14 44 Q24 18 44 20", "#9ae05a", 2.6, 0.8)
    needle = stroke("M34 28 L48 16", "#e4ffc0", 2.2)
    return card("ARCHER", arc + needle + drop(46, 42, 0.9, GREEN) + drop(38, 48, 0.55, GREEN))


def serpent_shed():
    skin = (f'<path d="M18 46 Q12 34 22 28 Q32 22 40 28 Q48 34 40 42 Q34 46 28 40" fill="none" stroke="#efe6cc" stroke-width="7" stroke-linecap="round" stroke-dasharray="4 3"/>')
    snake = stroke("M26 40 Q24 32 32 30 Q40 30 42 22", "#8fb04a", 4.6) + S(ellipse(44, 19, 4.5, 3.6), "#8fb04a", "#74933a")
    sparkle = "".join(f'<path d="M{x} {y - 4} L{x + 1.2} {y - 1.2} L{x + 4} {y} L{x + 1.2} {y + 1.2} L{x} {y + 4} L{x - 1.2} {y + 1.2} L{x - 4} {y} L{x - 1.2} {y - 1.2} Z" fill="#fff6c8" {THIN}/>'
                      for x, y in ((16, 18), (50, 44)))
    return card("GUARD", skin + snake + sparkle)


def water_wave():
    wave = S("M10 50 Q14 30 30 22 Q46 16 52 28 Q44 24 38 30 Q46 30 44 40 Q40 34 34 38 Q30 44 34 50 Z", *WATER, 2, 1.6)
    foam = '<path d="M30 22 Q40 18 48 22" fill="none" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round"/>'
    return card("PACK", wave + foam + motion([(42, 46, 52, 46)]))


def river_rat_splash():
    drops = "".join(drop(32 + 14 * math.cos(a), 34 + 12 * math.sin(a), 0.55, WATER) for a in (-2.4, -1.6, -0.8, 0, -3.1))
    pool = S(ellipse(32, 44, 14, 5), *WATER, 1, 0.8)
    return card("PACK", pool + drops + '<circle cx="32" cy="32" r="3" fill="#bcd6ff" stroke="#1c1b22" stroke-width="1.6"/>')


def gnoll_spear():
    return card("BERSERK", motion([(10, 50, 18, 44), (14, 56, 22, 50)]) + stroke("M16 50 L46 20", WOOD[0], 3.2)
                + S(poly([(52, 12), (48, 24), (44, 20)]), *STEEL, 0.8, 0.8))


def skeleton_wall():
    return card("PACK", shield(18, 34, 0.62, BONE, STONE) + shield(46, 34, 0.62, BONE, STONE) + shield(32, 32, 0.75, BONE, STONE))


def skeleton_volley():
    return card("ARCHER", arrow(12, 38, 50, 20, BONE, BONE, "#9a96a0") + arrow(14, 50, 52, 32, BONE, BONE, "#9a96a0"))


def ghoul_claw():
    slashes = "".join(stroke(f"M{18 + i * 9} 14 Q{26 + i * 9} 32 {16 + i * 9} 52", BLOOD[0], 3.2) for i in range(3))
    return card("BERSERK", slashes + drop(50, 46, 0.6))


def vampire_bite():
    fangs = S("M20 18 L44 18 Q46 28 40 30 L38 42 L35 30 L29 30 L26 42 L24 30 Q18 28 20 18 Z", "#efe6cc", "#cfc4a4")
    heart = S("M44 40 Q44 36 48 36 Q52 36 52 40 Q52 44 44 50 Q36 44 36 40 Q36 36 40 36 Q44 36 44 40 Z", *BLOOD, 1, 1)
    return card("AMBUSH", fangs + drop(26, 48, 0.55) + heart)


def thorn_armour():
    plate = S("M18 18 Q32 12 46 18 L44 44 Q32 52 20 44 Z", *DARK_STEEL, 2, 1.6)
    thorns = "".join(f'<path d="M{x} {y} l{dx} {dy} l{ex} {ey} Z" fill="#d4dbe4" {THIN}/>'
                     for x, y, dx, dy, ex, ey in ((18, 22, -8, -2, 7, 6), (46, 22, 8, -2, -7, 6), (19, 36, -8, 2, 7, 3), (45, 36, 8, 2, -7, 3),
                                                  (28, 14, -2, -8, 5, 7), (36, 14, 2, -8, -5, 7)))
    return card("GUARD", thorns + plate + stroke("M32 20 L32 42", STEEL[0], 2))


def goblin_chief():
    pole = stroke("M18 54 L18 12", WOOD[0], 3)
    flag = S("M18 12 L46 14 L40 22 L46 30 L18 30 Z", "#a83a2e", "#862c22", 1.4, 1)
    mark = (f'<circle cx="44" cy="44" r="8" fill="none" stroke="{INK}" stroke-width="4.4"/>'
            f'<circle cx="44" cy="44" r="8" fill="none" stroke="#f6c64a" stroke-width="2.2"/><circle cx="44" cy="44" r="2" fill="#f6c64a"/>')
    return card("BOSS", pole + flag + '<path d="M26 18 L34 18 L30 25 Z" fill="#efe6cc" stroke="#1c1b22" stroke-width="1.4"/>' + mark)


def furnace_heart():
    plate = S("M16 18 Q32 10 48 18 L46 42 Q32 52 18 42 Z", "#7a6c60", "#5c5046", 2, 1.6)
    core = S(circle(32, 30, 8), "#ff8a2a", "#e0661a", 1, 1) + '<circle cx="32" cy="30" r="3.6" fill="#ffd060"/>'
    heat = "".join(swoosh(f"M{x} 54 Q{x + 3} 50 {x} 46 Q{x - 3} 42 {x} 38", "#ffa030", 2, 0.8) for x in (12, 52))
    return card("BOSS", heat + plate + core)


def soul_eater():
    maw = S("M12 30 Q12 14 32 14 Q52 14 52 30 Q52 46 32 50 Q12 46 12 30 Z", "#4a3a6e", "#352a52", 2, 1.6)
    throat = '<path d="M16 30 Q32 18 48 30 Q32 46 16 30 Z" fill="#1c1428"/>'
    teeth = tooth_row(24, 16, 48, 4) + tooth_row(37, 16, 48, 4, down=False)
    gem = S(poly([(32, 24), (37, 29), (32, 36), (27, 29)]), "#7ff0e0", "#4cc8b8", 0.8, 0.8)
    return card("BOSS", maw + throat + gem + teeth)


ICONS = {
    "PUSH": ("밀치기", push), "GUARD": ("엄호", guard),
    "RAT_GNAW": ("물어뜯기", rat_gnaw), "LIZARD_TAIL": ("꼬리치기", lizard_tail), "KOBOLD_SLING": ("투석", kobold_sling),
    "GOBLIN_SHIV": ("기습", goblin_shiv), "HOB_TAUNT": ("도발", hob_taunt), "GOBLIN_AIM": ("조준 사격", goblin_aim),
    "SHIELD_STANCE": ("방패 자세", shield_stance), "ORC_CLEAVER": ("휘두르기", orc_cleaver), "ORC_THROW": ("도끼 투척", orc_throw),
    "SPIDER_WEB": ("거미줄", spider_web), "BEETLE_CURL": ("몸 말기", beetle_curl), "ORE_SLAM": ("내려찍기", ore_slam),
    "RIVER_RAT_SPLASH": ("물세례", river_rat_splash), "LEECH_LATCH": ("달라붙기", leech_latch), "TOAD_SPIT": ("독침", toad_spit),
    "SERPENT_SHED": ("허물 벗기", serpent_shed), "WATER_WAVE": ("해일", water_wave), "GNOLL_SPEAR": ("창 찌르기", gnoll_spear),
    "SKELETON_WALL": ("방패벽", skeleton_wall), "SKELETON_VOLLEY": ("뼈화살 연사", skeleton_volley), "GHOUL_CLAW": ("할퀴기", ghoul_claw),
    "VAMPIRE_BITE": ("흡혈 물기", vampire_bite), "THORN_ARMOUR": ("가시 갑옷", thorn_armour),
    "GOBLIN_CHIEF": ("지휘", goblin_chief), "FURNACE_HEART": ("과열 장갑", furnace_heart), "SOUL_EATER": ("영혼 먹기", soul_eater),
}


def main() -> None:
    (OUT / "svg").mkdir(parents=True, exist_ok=True)
    jobs = []
    for sid, (_, build) in ICONS.items():
        source = OUT / "svg" / f"{sid}.svg"
        source.write_text(build())
        jobs.append((source, OUT / f"{sid}.png", 2))
    flat.rasterise(jobs)

    REVIEW.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Jua-Regular.ttf"), 17)
    cell, cols = 104, 7
    rows = math.ceil(len(ICONS) / cols)
    sheet = Image.new("RGB", (cols * (cell + 24) + 24, rows * (cell + 44) + 24), "#262229")
    draw = ImageDraw.Draw(sheet)
    for i, (sid, (name, _)) in enumerate(ICONS.items()):
        x, y = 24 + (i % cols) * (cell + 24), 24 + (i // cols) * (cell + 44)
        pic = Image.open(OUT / f"{sid}.png").convert("RGBA").resize((cell, cell), Image.LANCZOS)
        sheet.paste(pic, (x, y), pic)
        draw.text((x + cell // 2, y + cell + 18), name, font=font, fill="#f0e8d8", anchor="mm")
    sheet.save(REVIEW / "skills-sheet.png")


if __name__ == "__main__":
    main()
