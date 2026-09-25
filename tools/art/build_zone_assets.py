"""Art for the four zones, their bosses and the soul stones.

Everything here is in the paper-doll grammar (bold ink outline, flat fills,
one contour crescent of shade on the lower right) so it sits next to the
monsters, objects and items already in the game:

- soul stones: one cut stone in seven colours (no element + six element
  tags), ten family emblems to lay on it, and two tier glows;
- status badges for the reactions and new statuses;
- three boss figures (the fallen adventurer is a party paper doll, so it gets
  an aura to stand in instead);
- boss-room props;
- temple and crypt floor/wall sheets in the flat-v1 2x2 layout, and hazard
  and reaction tiles.

Nothing is wired into the game here: docs/art/zones-v1.md says where each
file plugs in.

Run: python3 tools/art/build_zone_assets.py
"""
import math
import random
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402
import build_monsters as mon  # noqa: E402
from build_gear import rrect, circle, svg, ground, WOOD, STEEL, DARK_STEEL, GOLD  # noqa: E402

ROOT = flat.ROOT
INK = flat.INK
LINE = flat.LINE
THIN = f'stroke="{INK}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"'
REVIEW = ROOT / "docs/art/zones-v1"
FONT = ROOT / "assets/fonts/Jua-Regular.ttf"


def shaded(uid, path, fill, shade, dx=2.4, dy=1.8):
    return doll.shaded(uid, path, fill, shade, dx, dy)


def poly(points):
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in points) + " Z"


def ellipse(cx, cy, rx, ry):
    return f"M{cx - rx} {cy} A{rx} {ry} 0 1 0 {cx + rx} {cy} A{rx} {ry} 0 1 0 {cx - rx} {cy} Z"


# --- soul stones -------------------------------------------------------------

# element id -> (face, shade, light facet, glow)
STONE_COLOURS = {
    "none": ("#b9aec8", "#948aa6", "#e2dbec", "#f4efff"),
    "fire": ("#ef6a3a", "#c24a22", "#ffae7a", "#ffd27a"),
    "ice": ("#6cc6ec", "#4296c4", "#c4ecff", "#e6fbff"),
    "air": ("#f2cf3e", "#c9a322", "#fff09a", "#fffbd0"),
    "poison": ("#7ac04a", "#57952f", "#bfe88e", "#e4ffc0"),
    "will": ("#9a66d6", "#7446ae", "#cfa8f4", "#efdcff"),
    "bleed": ("#c8303e", "#98202c", "#f07480", "#ffc0c6"),
}
STONE = [(32, 7), (48, 17), (51, 38), (32, 57), (13, 38), (16, 17)]


def stone_svg(element):
    face, shade, light, _ = STONE_COLOURS[element]
    uid = "st" + element
    body = shaded(uid, poly(STONE), face, shade, 3.2, 2.6)
    facets = (f'<path d="{poly([(32, 7), (48, 17), (32, 24), (16, 17)])}" fill="{light}" opacity="0.85"/>'
              f'<path d="M16 17 L32 24 L48 17 M32 24 L32 57" fill="none" stroke="{INK}" stroke-width="1.4" opacity="0.35"/>')
    glint = '<path d="M20 22 L24 19" stroke="#ffffff" stroke-width="3" stroke-linecap="round"/>'
    outline = f'<path d="{poly(STONE)}" fill="none" {LINE}/>'
    return svg(ground(15) + body + facets + glint + outline)


def glyph(path, fill="#ffffff"):
    """An emblem: white fill, ink edge, so it reads on every stone colour."""
    return f'<path d="{path}" fill="{fill}" {THIN}/>'


EMBLEMS = {
    # a rat's head in profile: round ear, long snout, whisker
    "rat": glyph("M22 38 Q22 30 30 29 Q34 26 37 29 Q38 25 42 26 Q45 28 42 32 L46 36 Q44 40 38 40 Z")
           + f'<circle cx="37" cy="33" r="1.4" fill="{INK}"/><path d="M44 37 L48 39" {THIN}/>',
    # a goblin's face: two long ears
    "goblin": glyph("M24 32 L14 26 L24 38 Q26 44 32 44 Q38 44 40 38 L50 26 L40 32 Q38 27 32 27 Q26 27 24 32 Z")
              + f'<circle cx="28.5" cy="35" r="1.6" fill="{INK}"/><circle cx="35.5" cy="35" r="1.6" fill="{INK}"/>',
    # a reptile's eye: slit pupil
    "reptile": glyph(ellipse(32, 35, 11, 7)) + f'<path d="M32 29 Q34.5 35 32 41 Q29.5 35 32 29 Z" fill="{INK}"/>',
    # a kobold's head: blunt snout and one horn nub
    "kobold": glyph("M20 36 Q20 28 29 28 L31 24 L34 28 Q41 29 45 34 Q46 38 40 39 L30 42 Q21 42 20 36 Z")
              + f'<circle cx="33" cy="33" r="1.5" fill="{INK}"/>',
    # two tusks rising from a jaw line
    "orc": glyph("M20 40 Q32 46 44 40 L44 36 Q32 41 20 36 Z")
           + glyph("M24 37 Q22 29 26 25 Q26 31 28 37 Z") + glyph("M40 37 Q42 29 38 25 Q38 31 36 37 Z"),
    # a flame-drop swirl
    "elemental": glyph("M32 22 Q42 32 40 39 Q38 45 32 45 Q25 45 24 39 Q23 32 32 22 Z")
                 + f'<path d="M32 42 Q28 40 29 36 Q31 33 34 35" fill="none" {THIN}/>',
    # a beetle: shell with split and two feelers
    "insect": glyph(ellipse(32, 37, 9, 10)) + f'<path d="M32 27 L32 47 M28 27 L25 22 M36 27 L39 22" fill="none" {THIN}/>'
              + glyph(ellipse(32, 27, 5, 3)),
    # a hyena's head with a spear behind
    "gnoll": f'<path d="M42 20 L22 48" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>'
             + f'<path d="M42 20 L22 48" stroke="#ffffff" stroke-width="1.6" stroke-linecap="round"/>'
             + glyph("M23 34 L21 25 L28 30 Q32 28 36 30 L43 25 L41 34 Q41 42 32 44 Q23 42 23 34 Z")
             + f'<circle cx="28.5" cy="35" r="1.5" fill="{INK}"/><circle cx="35.5" cy="35" r="1.5" fill="{INK}"/>',
    # a skull
    "undead": glyph("M22 33 Q22 23 32 23 Q42 23 42 33 Q42 38 38 40 L38 45 L26 45 L26 40 Q22 38 22 33 Z")
              + f'<circle cx="28" cy="33" r="2.8" fill="{INK}"/><circle cx="36" cy="33" r="2.8" fill="{INK}"/>'
              + f'<path d="M30 45 L30 42 M34 45 L34 42" {THIN}/>',
    # spread wings
    "bat": glyph("M32 30 Q28 26 18 25 Q20 30 16 34 Q22 33 24 38 Q27 34 32 38 Q37 34 40 38 Q42 33 48 34 Q44 30 46 25 Q36 26 32 30 Z")
           + f'<circle cx="30" cy="32" r="1" fill="{INK}"/><circle cx="34" cy="32" r="1" fill="{INK}"/>',
}


def emblem_svg(family):
    return svg(EMBLEMS[family])


def tier_svg(tier):
    """Tier two: a thin halo. Tier three: a bright halo and four sparks."""
    _, _, _, glow = STONE_COLOURS["none"]
    halo = (f'<path d="{poly(STONE)}" fill="none" stroke="#fff6c8" stroke-width="{3 if tier == 2 else 5}" '
            f'opacity="{0.75 if tier == 2 else 0.95}" transform="translate(32 32) scale(1.14) translate(-32 -32)"/>')
    sparks = ""
    if tier == 3:
        for cx, cy, r in ((52, 10, 4.5), (10, 48, 3.6), (56, 44, 3.0), (9, 14, 2.6)):
            sparks += (f'<path d="M{cx} {cy - r} L{cx + r * 0.3} {cy - r * 0.3} L{cx + r} {cy} L{cx + r * 0.3} {cy + r * 0.3} '
                       f'L{cx} {cy + r} L{cx - r * 0.3} {cy + r * 0.3} L{cx - r} {cy} L{cx - r * 0.3} {cy - r * 0.3} Z" '
                       f'fill="#fff6c8" stroke="{INK}" stroke-width="1.2" stroke-linejoin="round"/>')
    pips = "".join(f'<circle cx="{26 + i * 6}" cy="61" r="2.4" fill="#fff6c8" stroke="{INK}" stroke-width="1.4"/>' for i in range(tier))
    return svg(halo + sparks + pips)


def boss_rim_svg():
    """A gold rim for a boss's stone."""
    return svg(f'<path d="{poly(STONE)}" fill="none" stroke="{INK}" stroke-width="7" stroke-linejoin="round"/>'
               f'<path d="{poly(STONE)}" fill="none" stroke="{GOLD[0]}" stroke-width="3.6" stroke-linejoin="round"/>'
               f'<path d="M26 4 L29 9 L32 3 L35 9 L38 4 L37 11 L27 11 Z" fill="{GOLD[0]}" {THIN}/>')


# --- status badges -----------------------------------------------------------

BADGE_COLOURS = {"wet": "#3f86d6", "stun": "#e0b020", "taunt": "#d0492e", "bleed": "#b02434", "burn": "#e8702a",
                 "poison": "#5fa83a", "freeze": "#4cb4dc", "confuse": "#9a5cd0", "slow": "#6b7c96", "sealed": "#5a4a7a",
                 "cracked": "#8a6a4a", "marked": "#c8303e", "steam": "#9aa6b4"}


def badge(uid, colour, inner):
    ring = shaded(uid, circle(32, 32, 24), colour, doll_darker(colour), 2.6, 2.0)
    return svg(ring + inner)


def doll_darker(colour, k=0.78):
    c = colour.lstrip("#")
    r, g, b = (int(c[i:i + 2], 16) for i in (0, 2, 4))
    return "#%02x%02x%02x" % (int(r * k), int(g * k), int(b * k))


W = "#ffffff"
STATUS = {
    "wet": glyph("M32 16 Q42 30 42 36 Q42 46 32 46 Q22 46 22 36 Q22 30 32 16 Z"),
    "stun": glyph("M35 14 L22 34 L31 34 L27 50 L42 28 L33 28 Z", "#fff6a0"),
    "taunt": glyph("M16 20 Q16 14 22 14 L42 14 Q48 14 48 20 L48 34 Q48 40 42 40 L30 40 L22 48 L23 40 L22 40 Q16 40 16 34 Z")
             + f'<path d="M32 19 L32 29" stroke="{INK}" stroke-width="4.4" stroke-linecap="round"/><circle cx="32" cy="35" r="2.4" fill="{INK}"/>',
    "bleed": glyph("M32 14 Q41 28 41 35 Q41 44 32 44 Q23 44 23 35 Q23 28 32 14 Z", "#ffd0d4")
             + glyph("M40 42 Q44 48 44 50 Q44 54 40 54 Q36 54 36 50 Q36 48 40 42 Z", "#ffd0d4"),
    "burn": glyph("M32 14 Q44 26 42 38 Q41 46 32 48 Q23 46 22 38 Q21 30 27 24 Q28 32 32 32 Q30 22 32 14 Z", "#ffe08a"),
    "poison": glyph("M22 30 Q22 20 32 20 Q42 20 42 30 Q42 34 39 36 L39 40 L25 40 L25 36 Q22 34 22 30 Z", "#e4ffc0")
              + f'<circle cx="28" cy="29" r="2.6" fill="{INK}"/><circle cx="36" cy="29" r="2.6" fill="{INK}"/>'
              + glyph("M27 44 L37 44 L37 48 L27 48 Z", "#e4ffc0"),
    "freeze": "".join(f'<path d="M32 32 L{32 + 17 * math.cos(a):.1f} {32 + 17 * math.sin(a):.1f}" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
                      f'<path d="M32 32 L{32 + 17 * math.cos(a):.1f} {32 + 17 * math.sin(a):.1f}" stroke="{W}" stroke-width="3" stroke-linecap="round"/>'
                      for a in [i * math.pi / 3 for i in range(6)]),
    "confuse": f'<path d="M32 32 Q32 26 37 27 Q43 29 41 36 Q38 43 30 42 Q21 40 22 31 Q24 20 35 19" fill="none" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
               f'<path d="M32 32 Q32 26 37 27 Q43 29 41 36 Q38 43 30 42 Q21 40 22 31 Q24 20 35 19" fill="none" stroke="{W}" stroke-width="3" stroke-linecap="round"/>',
    "slow": glyph("M22 18 L42 18 L34 32 L42 46 L22 46 L30 32 Z") + f'<path d="M26 42 L38 42 L32 36 Z" fill="{INK}"/>',
    "sealed": glyph(rrect(22, 30, 42, 46, 3)) + f'<path d="M26 30 L26 25 Q26 18 32 18 Q38 18 38 25 L38 30" fill="none" stroke="{INK}" stroke-width="6"/>'
              + f'<path d="M26 30 L26 25 Q26 18 32 18 Q38 18 38 25 L38 30" fill="none" stroke="{W}" stroke-width="2.6"/>'
              + f'<circle cx="32" cy="37" r="2.4" fill="{INK}"/>',
    "cracked": glyph("M20 18 L44 18 L44 32 Q44 44 32 50 Q20 44 20 32 Z")
               + f'<path d="M34 18 L29 28 L35 32 L28 42 L31 50" fill="none" stroke="{INK}" stroke-width="2.6" stroke-linejoin="round"/>',
    "marked": f'<circle cx="32" cy="32" r="13" fill="none" stroke="{INK}" stroke-width="6"/><circle cx="32" cy="32" r="13" fill="none" stroke="{W}" stroke-width="3"/>'
              + "".join(f'<path d="{p}" stroke="{INK}" stroke-width="6" stroke-linecap="round"/><path d="{p}" stroke="{W}" stroke-width="3" stroke-linecap="round"/>'
                        for p in ("M32 12 L32 22", "M32 42 L32 52", "M12 32 L22 32", "M42 32 L52 32"))
              + f'<circle cx="32" cy="32" r="3" fill="{W}" {THIN}/>',
    "steam": "".join(glyph(ellipse(cx, cy, rx, ry)) for cx, cy, rx, ry in ((26, 36, 8, 6), (38, 34, 8, 7), (32, 26, 9, 7))),
}


def status_svg(sid):
    return badge("sb" + sid, BADGE_COLOURS[sid], STATUS[sid])


# --- bosses --------------------------------------------------------------------

GOBLIN_SKIN = mon.GOBLIN_SKIN


def goblin_chief_svg():
    """The chief: a big goblin in a red mantle with a fur collar, an iron
    crown and a skull-topped staff."""
    staff = (f'<path d="M51 38 L51 61" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>'
             f'<path d="M51 38 L51 61" stroke="{WOOD[0]}" stroke-width="2.4" stroke-linecap="round"/>'
             + shaded("gcs", "M45 34 Q45 26 51 26 Q57 26 57 34 Q57 38 54 39 L54 42 L48 42 L48 39 Q45 38 45 34 Z", "#efe6cc", "#cfc4a4", 1.4, 1.2)
             + f'<circle cx="49" cy="34" r="1.7" fill="{INK}"/><circle cx="53" cy="34" r="1.7" fill="{INK}"/>')
    collar = shaded("gcf", "M17 33 Q32 25 47 33 Q48 39 44 40 Q32 35 20 40 Q16 39 17 33 Z", "#d8c8a8", "#b8a684", 1.6, 1.2)
    body = mon.humanoid("gchief", "south", (15.0, 12.0, 1.0, 31, 12.5), GOBLIN_SKIN, ("#a83a2e", "#862c22"),
                        ears="pointy", ear_scale=1.05, brows=True, mark=collar)
    crown = (shaded("gcc", "M22 13 L22 4 L26.5 9 L32 2 L37.5 9 L42 4 L42 13 Z", "#9aa4b2", "#76808e", 1.4, 1.2)
             + f'<circle cx="32" cy="10" r="2" fill="#e0453a" {THIN}/>')
    return body.replace("</svg>", staff + crown + "</svg>")


def furnace_golem_svg():
    """A walking smelter: a stone body around a glowing furnace mouth, lava in
    its seams, fists of slag and a chimney breathing smoke."""
    rock, rock_shade = "#7a6c60", "#5c5046"
    parts = [f'<ellipse cx="32" cy="60" rx="22" ry="3.6" fill="#000" fill-opacity="0.22"/>']
    for x in (22, 42):
        parts.append(shaded(f"fgl{x}", rrect(x - 6, 48, x + 6, 60, 3), rock, rock_shade, 1.6, 1.2))
    parts.append(shaded("fgc", "M50 8 L57 8 L57 24 L50 24 Z", "#5a5048", "#443c36", 1.2, 1))
    for i, (cx, cy, r) in enumerate(((54, 5, 3.4), (58, 1.5, 2.6))):
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#9aa0a8" {THIN}/>')
    parts.append(shaded("fgb", "M14 22 Q14 14 22 14 L42 14 Q50 14 50 22 L52 46 Q52 52 46 52 L18 52 Q12 52 12 46 Z", rock, rock_shade, 3.2, 2.4))
    for x, flip in ((8, -1), (56, 1)):
        parts.append(shaded(f"fga{x}", ellipse(x, 38, 7, 8.5), "#6a5c50", "#4e443a", 1.8, 1.4))
        parts.append(f'<path d="M{x - 4} {35} L{x + 3} {41}" stroke="#ffa030" stroke-width="2" stroke-linecap="round"/>')
    parts.append(shaded("fgm", rrect(21, 27, 43, 45, 5), "#3a2420", "#2a1a16", 1.4, 1))
    parts.append(f'<path d="{rrect(24, 32, 40, 44, 4)}" fill="#ff8a2a"/><path d="{rrect(26, 36, 38, 44, 3)}" fill="#ffd060"/>')
    for x in (27, 32, 37):
        parts.append(f'<path d="M{x} 29 L{x} 45" stroke="{INK}" stroke-width="2.4"/>')
    parts.append(f'<path d="{rrect(21, 27, 43, 45, 5)}" fill="none" {LINE}/>')
    for d in ("M16 24 L20 30 L18 36", "M47 20 L45 26 L48 31", "M15 44 L20 48"):
        parts.append(f'<path d="{d}" fill="none" stroke="#ffa030" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>')
    parts.append(shaded("fgh", rrect(24, 6, 40, 18, 4), "#6a5c50", "#4e443a", 1.6, 1.2))
    parts.append('<path d="M27 12 L31 12 M33 12 L37 12" stroke="#ffcf40" stroke-width="3" stroke-linecap="round"/>')
    return svg("".join(parts))


def soul_eater_svg():
    """A hooded wraith that feeds on souls: a hollow cowl, a jagged mouth,
    claws, and three stolen soul stones circling it."""
    robe, robe_shade = "#4a3a6e", "#352a52"
    parts = [f'<ellipse cx="32" cy="60" rx="14" ry="3" fill="#000" fill-opacity="0.18"/>']
    for i, (cx, cy, element) in enumerate(((9, 22, "fire"), (55, 26, "ice"), (50, 50, "poison"))):
        face, shade, light, _ = STONE_COLOURS[element]
        gem = [(cx, cy - 6), (cx + 5, cy - 2), (cx + 4, cy + 4), (cx, cy + 7), (cx - 4, cy + 4), (cx - 5, cy - 2)]
        parts.append(f'<path d="M{cx} {cy} Q{32 + (cx - 32) * 0.4} {cy + 6} 32 34" fill="none" stroke="#7ff0e0" stroke-width="1.6" opacity="0.7"/>')
        parts.append(shaded(f"sg{i}", poly(gem), face, shade, 1.2, 1))
    body = ("M32 4 Q49 4 50 24 Q51 38 46 46 Q44 52 40 50 Q38 58 34 54 Q32 60 29 54 Q25 58 23 50 Q19 52 17 46 "
            "Q12 36 14 24 Q15 4 32 4 Z")
    parts.append(shaded("seb", body, robe, robe_shade, 3.4, 2.6))
    parts.append(f'<path d="M22 14 Q32 6 42 14 L41 30 Q32 36 23 30 Z" fill="#1c1428"/>')
    parts.append('<ellipse cx="27.5" cy="19" rx="2.6" ry="3.4" fill="#7ff0e0"/><ellipse cx="36.5" cy="19" rx="2.6" ry="3.4" fill="#7ff0e0"/>')
    parts.append(f'<path d="M25 25 L27 28 L29 25 L31 29 L33 25 L35 29 L37 25 L39 28 L39 31 Q32 34 25 31 Z" fill="#fbf6e6" {THIN}/>')
    for x, flip in ((16, -1), (48, 1)):
        claw = f"M{x} 34 L{x + flip * 8} 40 L{x + flip * 5} 41 L{x + flip * 9} 44 L{x + flip * 4} 44 L{x + flip * 6} 48 L{x} 42 Z"
        parts.append(shaded(f"sec{x}", claw, "#cfc6e0", "#aaa0c0", 1.2, 1))
    parts.append('<path d="M20 44 Q18 50 22 54 M44 44 Q47 50 43 55" fill="none" stroke="#7ff0e0" stroke-width="1.6" opacity="0.6"/>')
    return svg("".join(parts))


def fallen_aura_svg():
    """Laid behind a paper doll: tongues of dark violet flame rising around
    the figure and a red-rimmed shadow pool, the look of an adventurer come
    back wrong."""
    rng = random.Random(12)
    tongues = []
    for i, x in enumerate((12, 21, 32, 43, 52)):
        base = 52 if i in (0, 4) else 46
        height = 22 + rng.random() * 6 + (8 if i == 2 else 0)
        w = 8.5
        lean = rng.uniform(-4, 4)
        tip = (x + lean, base - height)
        d = (f"M{x - w:.1f} {base:.1f} C{x - w - 2:.1f} {base - height * 0.4:.1f} {tip[0] - 5:.1f} {tip[1] + 8:.1f} {tip[0]:.1f} {tip[1]:.1f} "
             f"C{tip[0] + 3:.1f} {tip[1] + 9:.1f} {x + w + 3:.1f} {base - height * 0.45:.1f} {x + w:.1f} {base:.1f} Z")
        inner = (f"M{x - w * 0.45:.1f} {base:.1f} C{x - w * 0.5:.1f} {base - height * 0.35:.1f} {tip[0] - 2:.1f} {tip[1] + 12:.1f} {tip[0] + 0.5:.1f} {tip[1] + 9:.1f} "
                 f"C{tip[0] + 2:.1f} {tip[1] + 14:.1f} {x + w * 0.6:.1f} {base - height * 0.3:.1f} {x + w * 0.45:.1f} {base:.1f} Z")
        tongues.append(f'<path d="{d}" fill="#5a2680" stroke="{INK}" stroke-width="1.8" stroke-linejoin="round"/>'
                       f'<path d="{inner}" fill="#b060d8"/>')
    pool = (f'<ellipse cx="32" cy="57" rx="22" ry="5" fill="#2a1038" opacity="0.8"/>'
            f'<ellipse cx="32" cy="57" rx="22" ry="5" fill="none" stroke="#c8303e" stroke-width="1.8"/>')
    return svg(pool + "".join(tongues))


# --- boss-room props -----------------------------------------------------------

STONE_GREY = ("#9a96a0", "#78747e")


def throne_svg():
    back = shaded("thb", "M16 8 L20 4 L26 8 L32 2 L38 8 L44 4 L48 8 L48 40 L16 40 Z", "#8a7f74", "#6a6058")
    seat = shaded("ths", rrect(12, 36, 52, 50, 3), "#8a7f74", "#6a6058")
    cushion = shaded("thc", rrect(18, 30, 46, 40, 4), "#b8412e", "#963223", 1.4, 1)
    legs = "".join(shaded(f"thl{x}", rrect(x, 48, x + 8, 60, 2), "#7a7066", "#5c544c", 1.2, 1) for x in (14, 42))
    skulls = "".join(shaded(f"thk{x}", ellipse(x, 12, 3.4, 3.2), "#efe6cc", "#cfc4a4", 0.8, 0.8)
                     + f'<circle cx="{x - 1.2}" cy="12" r="0.9" fill="{INK}"/><circle cx="{x + 1.2}" cy="12" r="0.9" fill="{INK}"/>'
                     for x in (20, 44))
    banner = (shaded("thn", "M26 12 L38 12 L38 28 L32 24 L26 28 Z", "#6a8a3a", "#557030", 1.2, 1)
              + f'<path d="M29 16 L35 16 L32 21 Z" fill="#efe6cc" {THIN}/>')
    return svg(ground(22) + legs + back + banner + skulls + seat + cushion)


def lever_svg(up):
    base = shaded("lvb", rrect(18, 46, 46, 58, 3), *STONE_GREY)
    angle = -35 if up else 35
    rad = math.radians(angle - 90)
    tx, ty = 32 + 26 * math.cos(rad), 50 + 26 * math.sin(rad)
    handle = (f'<path d="M32 50 L{tx:.1f} {ty:.1f}" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
              f'<path d="M32 50 L{tx:.1f} {ty:.1f}" stroke="{DARK_STEEL[0]}" stroke-width="3.6" stroke-linecap="round"/>')
    knob = shaded("lvk", circle(tx, ty, 5), "#e0453a", "#b8322b", 1, 1)
    pivot = f'<circle cx="32" cy="50" r="4" fill="{STEEL[0]}" {THIN}/>'
    water = '<path d="M20 58 Q26 55 32 58 Q38 61 44 58" fill="none" stroke="#5fa0e0" stroke-width="2.4"/>' if not up else ""
    return svg(ground(16) + base + handle + knob + pivot + water)


def furnace_svg():
    body = shaded("fnb", "M12 22 L52 22 L54 58 L10 58 Z", "#8a5a44", "#6c4434")
    bricks = "".join(f'<path d="M{12 + (y % 2) * 6} {y} L{52 - (y % 2) * 2} {y}" stroke="{INK}" stroke-width="1.2" opacity="0.4"/>'
                     for y in (30, 38, 46, 54))
    mouth = shaded("fnm", "M20 58 L20 42 Q32 30 44 42 L44 58 Z", "#3a2420", "#2a1a16", 1, 1)
    fire = f'<path d="M22 58 Q24 46 30 50 Q31 42 35 48 Q38 44 42 58 Z" fill="#ff8a2a"/><path d="M27 58 Q30 51 33 54 Q36 51 38 58 Z" fill="#ffd060"/>'
    chimney = shaded("fnc", rrect(36, 4, 46, 24, 2), "#7a4e3c", "#5c3a2c", 1.2, 1)
    smoke = "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#a8a8b0" {THIN}/>' for cx, cy, r in ((44, 3, 3), (50, 1, 2.2)))
    return svg(ground(22) + chimney + smoke + body + bricks + mouth + fire)


def binding_altar_svg():
    rings = "".join(f'<circle cx="{x}" cy="57" r="3" fill="none" stroke="{INK}" stroke-width="3"/>'
                    f'<circle cx="{x}" cy="57" r="3" fill="none" stroke="{DARK_STEEL[0]}" stroke-width="1.4"/>' for x in (8, 56))
    chains = "".join(f'<path d="M{x} 57 Q{(x + 32) / 2} {50} {32 + (x - 32) * 0.45} 36" fill="none" stroke="{INK}" stroke-width="4" stroke-dasharray="3 2"/>'
                     f'<path d="M{x} 57 Q{(x + 32) / 2} {50} {32 + (x - 32) * 0.45} 36" fill="none" stroke="{DARK_STEEL[0]}" stroke-width="2" stroke-dasharray="3 2"/>'
                     for x in (8, 56))
    slab = shaded("bab", rrect(14, 30, 50, 52, 3), *STONE_GREY)
    top = shaded("bat", rrect(12, 24, 52, 32, 2), "#b0acb6", "#8e8a96", 1.2, 1)
    runes = ('<path d="M24 40 L28 36 L32 44 L36 36 L40 40" fill="none" stroke="#7ff0e0" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>'
             '<path d="M20 28 L44 28" stroke="#7ff0e0" stroke-width="1.6" opacity="0.7"/>')
    return svg(ground(22) + rings + slab + top + runes + chains)


def chain_post_svg():
    post = shaded("cpp", rrect(28, 14, 36, 58, 2), DARK_STEEL[0], DARK_STEEL[1], 1.2, 1)
    cap = shaded("cpc", rrect(25, 10, 39, 16, 2), STEEL[0], STEEL[1], 1, 1)
    chain = "".join(f'<ellipse cx="{38 + i * 4}" cy="{24 + i * 7}" rx="2.6" ry="3.8" fill="none" stroke="{INK}" stroke-width="3"/>'
                    f'<ellipse cx="{38 + i * 4}" cy="{24 + i * 7}" rx="2.6" ry="3.8" fill="none" stroke="{STEEL[0]}" stroke-width="1.4"/>'
                    for i in range(5))
    glow = '<path d="M28 34 L36 34" stroke="#7ff0e0" stroke-width="2" opacity="0.8"/>'
    return svg(ground(12) + post + cap + glow + chain)


def gravestone_svg():
    stone = shaded("gsb", "M18 58 L18 24 Q18 10 32 10 Q46 10 46 24 L46 58 Z", *STONE_GREY)
    cross = f'<path d="M32 18 L32 36 M25 24 L39 24" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>'
    moss = '<path d="M18 50 Q24 46 28 52 Q34 48 38 54 L18 58 Z" fill="#5a8a4a" opacity="0.8"/>'
    crack = f'<path d="M40 14 L37 22 L41 28" fill="none" stroke="{INK}" stroke-width="1.4"/>'
    dirt = shaded("gsd", ellipse(32, 58, 18, 4), "#6a5a48", "#554737", 1, 0.6)
    return svg(ground(20) + dirt + stone + cross + crack + moss)


def open_coffin_svg():
    box = shaded("ocb", "M14 20 L22 10 L42 10 L50 20 L46 58 L18 58 Z", "#5a4a5e", "#443848")
    inside = f'<path d="M19 22 L25 14 L39 14 L45 22 L42 54 L22 54 Z" fill="#1c1428" />'
    glow = '<ellipse cx="32" cy="34" rx="9" ry="14" fill="#9a66d6" opacity="0.45"/>'
    lid = shaded("ocl", "M46 26 L60 30 L56 60 L42 58 Z", "#6a586e", "#524456", 1.4, 1)
    return svg(ground(22) + box + inside + glow + lid)


PROPS = {"throne": throne_svg, "lever_up": lambda: lever_svg(True), "lever_down": lambda: lever_svg(False),
         "furnace": furnace_svg, "binding_altar": binding_altar_svg, "chain_post": chain_post_svg,
         "gravestone": gravestone_svg, "open_coffin": open_coffin_svg}


# --- floor and wall sheets (flat-v1 layout: 2x2 quadrants of 627) --------------

SHEET = 1254
HALF = SHEET // 2

THEMES = {
    # face, face light, face dark, grout, accent a, accent b
    "temple": {"floor": ("#3d5a5c", "#557576", "#2b4244", "#152022"), "moss": "#56834a", "stain": "#4e7a86",
               "wall_face": ("#2f4549", "#3f5a5e", "#223336"), "wall_top": ("#6d8f90", "#86a8a8", "#557474")},
    "crypt": {"floor": ("#3b3545", "#524a5e", "#2a2532", "#141118"), "moss": "#6a5e4a", "stain": "#5a4a6a",
              "wall_face": ("#2c2735", "#3c3548", "#201c27"), "wall_top": ("#655b74", "#7c7290", "#4e4660")},
}


def slab(x, y, w, h, face, light, dark, rng, crack=False, deco=""):
    m = 26
    r = 22
    x0, y0, x1, y1 = x + m, y + m, x + w - m, y + h - m
    out = [f'<path d="{rrect(x0, y0, x1, y1, r)}" fill="{dark}"/>',
           f'<path d="{rrect(x0, y0, x1 - 10, y1 - 12, r)}" fill="{face}"/>',
           f'<path d="M{x0 + r} {y0 + 8} L{x1 - r - 10} {y0 + 8}" stroke="{light}" stroke-width="7" stroke-linecap="round" opacity="0.7"/>',
           f'<path d="M{x0 + 8} {y0 + r} L{x0 + 8} {y1 - r - 12}" stroke="{light}" stroke-width="5" stroke-linecap="round" opacity="0.45"/>']
    for _ in range(9):
        cx, cy = rng.uniform(x0 + 40, x1 - 50), rng.uniform(y0 + 40, y1 - 50)
        rr = rng.uniform(4, 10)
        out.append(f'<path d="{poly([(cx, cy - rr), (cx + rr, cy), (cx, cy + rr * 0.8), (cx - rr * 0.9, cy)])}" fill="{dark}" opacity="0.55"/>')
    if crack:
        cx, cy = rng.uniform(x0 + 120, x1 - 160), y0 + 6
        pts = [(cx, cy)]
        for _ in range(5):
            cx += rng.uniform(-40, 40); cy += rng.uniform(40, 70)
            pts.append((cx, min(cy, y1 - 30)))
        out.append(f'<path d="M{" L".join(f"{px:.0f} {py:.0f}" for px, py in pts)}" fill="none" stroke="#10151a" stroke-width="6" stroke-linejoin="round"/>')
    out.append(deco)
    return "".join(out)


def moss_patch(cx, cy, colour, rng, n=6):
    return "".join(f'<ellipse cx="{cx + rng.uniform(-50, 50):.0f}" cy="{cy + rng.uniform(-30, 30):.0f}" rx="{rng.uniform(18, 40):.0f}" '
                   f'ry="{rng.uniform(12, 26):.0f}" fill="{colour}" opacity="0.8"/>' for _ in range(n))


def rune_ring(cx, cy, colour):
    ticks = "".join(f'<path d="M{cx + 118 * math.cos(a):.0f} {cy + 118 * math.sin(a):.0f} L{cx + 96 * math.cos(a):.0f} {cy + 96 * math.sin(a):.0f}" '
                    f'stroke="{colour}" stroke-width="8" stroke-linecap="round"/>' for a in [i * math.pi / 6 for i in range(12)])
    return (f'<circle cx="{cx}" cy="{cy}" r="130" fill="none" stroke="{colour}" stroke-width="10"/>'
            f'<circle cx="{cx}" cy="{cy}" r="84" fill="none" stroke="{colour}" stroke-width="6"/>' + ticks)


def floor_sheet_svg(theme):
    t = THEMES[theme]
    face, light, dark, grout = t["floor"]
    rng = random.Random(hash(theme) & 0xffff)
    body = [f'<rect width="{SHEET}" height="{SHEET}" fill="{grout}"/>']
    for q in range(4):
        x, y = (q % 2) * HALF, (q // 2) * HALF
        deco = ""
        if theme == "temple" and q in (1, 2):
            deco = moss_patch(x + 200 + q * 60, y + 420, t["moss"], rng)
        if theme == "temple" and q == 3:
            deco = f'<ellipse cx="{x + 330}" cy="{y + 300}" rx="170" ry="110" fill="{t["stain"]}" opacity="0.5"/>'
        if theme == "crypt" and q == 3:
            deco = rune_ring(x + 300, y + 300, "#4a4258")
        if theme == "crypt" and q == 1:
            deco = "".join(f'<path d="M{x + bx} {y + by} l30 -8 l4 10 l-30 8 Z" fill="#cfc4a4" stroke="#141118" stroke-width="4"/>'
                           for bx, by in ((200, 420), (330, 380), (260, 470)))
        body.append(slab(x, y, HALF, HALF, face, light, dark, rng, crack=q in (1, 2), deco=deco))
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{SHEET}" height="{SHEET}" viewBox="0 0 {SHEET} {SHEET}">{"".join(body)}</svg>'


def wall_sheet_svg(theme):
    """Top-left and bottom-left: wall fronts (a ledge over a darker face).
    Top-right and bottom-right: wall tops."""
    t = THEMES[theme]
    face, face_light, face_dark = t["wall_face"]
    top, top_light, top_dark = t["wall_top"]
    grout = t["floor"][3]
    rng = random.Random((hash(theme) >> 3) & 0xffff)
    body = [f'<rect width="{SHEET}" height="{SHEET}" fill="{grout}"/>']
    for row in range(2):
        y = row * HALF
        m = 26
        body.append(f'<path d="{rrect(m, y + m, HALF - m, y + HALF - m, 18)}" fill="{face_dark}"/>')
        body.append(f'<path d="{rrect(m, y + 150, HALF - m - 8, y + HALF - m - 20, 12)}" fill="{face}"/>')
        body.append(f'<path d="{rrect(m, y + m, HALF - m, y + 150, 16)}" fill="{top}"/>')
        body.append(f'<path d="M{m + 20} {y + m + 12} L{HALF - m - 20} {y + m + 12}" stroke="{top_light}" stroke-width="8" stroke-linecap="round"/>')
        body.append(f'<path d="M{m} {y + 150} L{HALF - m} {y + 150}" stroke="{face_dark}" stroke-width="10"/>')
        if theme == "temple":
            waves = "".join(f'<path d="M{80 + i * 90} {y + 250} q22 -30 45 0 t45 0" fill="none" stroke="{face_light}" stroke-width="10" stroke-linecap="round"/>'
                            for i in range(5))
            body.append(waves)
            if row == 1:
                body.append("".join(f'<path d="M{vx} {y + 150} q{rng.uniform(-20, 20):.0f} 120 {rng.uniform(-10, 10):.0f} {rng.uniform(180, 320):.0f}" '
                                    f'fill="none" stroke="{t["moss"]}" stroke-width="14" stroke-linecap="round"/>' for vx in (140, 250, 460)))
        else:
            cx = HALF // 2
            niche = (f'<path d="M{cx - 90} {y + 520} L{cx - 90} {y + 300} Q{cx} {y + 200} {cx + 90} {y + 300} L{cx + 90} {y + 520} Z" fill="{face_dark}"/>'
                     f'<ellipse cx="{cx}" cy="{y + 420}" rx="46" ry="42" fill="#cfc4a4" stroke="#141118" stroke-width="6"/>'
                     f'<circle cx="{cx - 16}" cy="{y + 415}" r="11" fill="#141118"/><circle cx="{cx + 16}" cy="{y + 415}" r="11" fill="#141118"/>')
            body.append(niche if row == 0 else
                        "".join(f'<path d="M{50} {y + 250 + i * 90} L{HALF - 60} {y + 250 + i * 90}" stroke="{face_light}" stroke-width="6" opacity="0.6"/>' for i in range(4)))
        x = HALF
        body.append(slab(x, y, HALF, HALF, top, top_light, top_dark, rng, crack=row == 1,
                         deco=moss_patch(x + 300, y + 330, t["moss"], rng, 4) if theme == "temple" and row == 1 else ""))
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{SHEET}" height="{SHEET}" viewBox="0 0 {SHEET} {SHEET}">{"".join(body)}</svg>'


# --- hazard and reaction tiles (64 units, 256 px) ------------------------------

def tile_svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>'


def lava_svg():
    rng = random.Random(7)
    plates = []
    for (x, y, w, h) in ((2, 2, 26, 20), (32, 4, 28, 16), (4, 26, 18, 22), (26, 24, 20, 18), (48, 24, 14, 22),
                         (2, 50, 24, 12), (28, 46, 22, 16), (52, 50, 10, 12)):
        pts = [(x + rng.uniform(0, 3), y + rng.uniform(0, 3)), (x + w - rng.uniform(0, 3), y + rng.uniform(0, 3)),
               (x + w - rng.uniform(0, 3), y + h - rng.uniform(0, 3)), (x + rng.uniform(0, 3), y + h - rng.uniform(0, 3))]
        plates.append(f'<path d="{poly(pts)}" fill="#3a2a26" stroke="#241816" stroke-width="1.4" stroke-linejoin="round"/>')
        plates.append(f'<path d="M{pts[0][0] + 2:.1f} {pts[0][1] + 2:.1f} L{pts[1][0] - 3:.1f} {pts[1][1] + 2:.1f}" stroke="#5a4038" stroke-width="1.4"/>')
    glow = '<rect width="64" height="64" fill="#ff7a1a"/><circle cx="24" cy="30" r="14" fill="#ffc040" opacity="0.8"/><circle cx="48" cy="46" r="10" fill="#ffc040" opacity="0.7"/>'
    return tile_svg(glow + "".join(plates))


def deep_water_svg():
    ripples = "".join(f'<path d="M{x} {y} q5 -3 10 0 t10 0" fill="none" stroke="#6fa6d8" stroke-width="1.6" stroke-linecap="round" opacity="0.8"/>'
                      for x, y in ((6, 12), (34, 8), (18, 30), (40, 36), (8, 50), (36, 54)))
    return tile_svg('<rect width="64" height="64" fill="#1d4a74"/><circle cx="32" cy="32" r="22" fill="#163c60"/>' + ripples)


def bog_svg():
    rng = random.Random(3)
    bubbles = "".join(f'<circle cx="{rng.uniform(6, 58):.1f}" cy="{rng.uniform(6, 58):.1f}" r="{rng.uniform(1.2, 2.8):.1f}" fill="#8aa050" stroke="#2c3818" stroke-width="0.8"/>'
                      for _ in range(9))
    reeds = "".join(f'<path d="M{x} 62 Q{x + 1} 50 {x + 3} 44" fill="none" stroke="#6a7a3a" stroke-width="1.8" stroke-linecap="round"/>' for x in (8, 12, 52))
    return tile_svg('<rect width="64" height="64" fill="#46562c"/><ellipse cx="30" cy="30" rx="24" ry="18" fill="#38461f"/>' + bubbles + reeds)


def gas_svg():
    crack = f'<path d="M18 44 L26 38 L30 42 L38 34 L46 38" fill="none" stroke="{INK}" stroke-width="2.4" stroke-linejoin="round"/>'
    puffs = "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#c8d860" opacity="0.55" stroke="#8a9a30" stroke-width="1"/>'
                    for cx, cy, r in ((30, 32, 7), (38, 24, 6), (26, 20, 5), (34, 14, 4)))
    return tile_svg(crack + puffs)


def fog_svg():
    wisps = "".join(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#d8d0ec" opacity="0.32"/>'
                    for cx, cy, rx, ry in ((20, 20, 22, 10), (44, 30, 24, 11), (24, 46, 26, 12), (50, 54, 18, 8)))
    return tile_svg(wisps)


def collapse_svg(armed):
    cracks = "".join(f'<path d="M32 32 L{32 + 26 * math.cos(a):.1f} {32 + 26 * math.sin(a):.1f}" stroke="{INK}" stroke-width="1.8" stroke-linecap="round" opacity="0.8"/>'
                     for a in (0.3, 1.5, 2.6, 3.9, 5.1))
    pebbles = "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#8a8078" stroke="{INK}" stroke-width="1"/>'
                      for cx, cy, r in ((20, 26, 2.2), (42, 22, 1.8), (36, 44, 2.4), (18, 42, 1.6)))
    warning = ('<circle cx="32" cy="32" r="20" fill="#d0492e" opacity="0.28"/>'
               '<circle cx="32" cy="32" r="20" fill="none" stroke="#d0492e" stroke-width="2.4" stroke-dasharray="5 3"/>') if armed else ""
    return tile_svg(warning + cracks + pebbles)


def steam_svg():
    clouds = "".join(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#f4f6f8" opacity="0.62" stroke="#c8d0d8" stroke-width="1"/>'
                     for cx, cy, rx, ry in ((22, 38, 14, 10), (42, 34, 14, 11), (32, 22, 15, 10), (18, 20, 9, 7), (48, 50, 10, 7)))
    return tile_svg(clouds)


def ice_svg():
    sheet = '<path d="M4 8 L60 4 L62 58 L6 60 Z" fill="#bfe8f8" opacity="0.62"/>'
    lines = "".join(f'<path d="{d}" fill="none" stroke="#ffffff" stroke-width="1.6" stroke-linecap="round" opacity="0.9"/>'
                    for d in ("M10 16 L26 30 L22 46", "M40 10 L36 26 L52 38", "M30 50 L44 44"))
    edge = '<path d="M4 8 L60 4 L62 58 L6 60 Z" fill="none" stroke="#7ec4e4" stroke-width="2"/>'
    return tile_svg(sheet + lines + edge)


def poison_pool_svg():
    pool = f'<path d="M10 32 Q8 16 26 14 Q40 8 52 20 Q60 32 52 46 Q40 58 24 54 Q10 50 10 32 Z" fill="#6a9a3a" opacity="0.78" stroke="#3a5a20" stroke-width="1.6"/>'
    inner = '<path d="M20 32 Q20 22 30 22 Q42 20 46 30 Q48 40 36 44 Q22 46 20 32 Z" fill="#9a6ac0" opacity="0.55"/>'
    bubbles = "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#c4e890" stroke="#3a5a20" stroke-width="0.8"/>' for cx, cy, r in ((28, 30, 2.2), (38, 36, 1.6), (44, 26, 1.4)))
    return tile_svg(pool + inner + bubbles)


HAZARDS = {"lava": lava_svg, "deep_water": deep_water_svg, "bog": bog_svg, "gas": gas_svg, "fog": fog_svg,
           "collapse": lambda: collapse_svg(False), "collapse_armed": lambda: collapse_svg(True),
           "steam": steam_svg, "ice": ice_svg, "poison_pool": poison_pool_svg}


# --- build -----------------------------------------------------------------------

OUT = ROOT / "assets/zones-v1"


def main() -> None:
    groups = {
        "soulstones": {**{f"stone_{e}": stone_svg(e) for e in STONE_COLOURS},
                       **{f"emblem_{f}": emblem_svg(f) for f in EMBLEMS},
                       "tier_2": tier_svg(2), "tier_3": tier_svg(3), "boss_rim": boss_rim_svg()},
        "status": {sid: status_svg(sid) for sid in STATUS},
        "bosses": {"goblin_chief": goblin_chief_svg(), "furnace_golem": furnace_golem_svg(),
                   "soul_eater": soul_eater_svg(), "fallen_aura": fallen_aura_svg()},
        "props": {pid: build() for pid, build in PROPS.items()},
        "hazards": {hid: build() for hid, build in HAZARDS.items()},
    }
    scale = {"soulstones": 2, "status": 2, "bosses": 3, "props": 3, "hazards": 4}
    jobs = []
    for group, entries in groups.items():
        folder = OUT / group
        (folder / "svg").mkdir(parents=True, exist_ok=True)
        for name, body in entries.items():
            source = folder / "svg" / f"{name}.svg"
            source.write_text(body)
            jobs.append((source, folder / f"{name}.png", scale[group]))
    tiles = OUT / "tiles"
    (tiles / "svg").mkdir(parents=True, exist_ok=True)
    for theme in THEMES:
        for kind, build in (("floor-slabs", floor_sheet_svg), ("wall-blocks", wall_sheet_svg)):
            source = tiles / "svg" / f"{theme}-{kind}.svg"
            source.write_text(build(theme))
            jobs.append((source, tiles / f"{theme}-{kind}.png", 1))
    flat.rasterise(jobs)
    review(groups)


def review(groups) -> None:
    REVIEW.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(FONT), 20)
    small = ImageFont.truetype(str(FONT), 15)

    def sheet_of(entries, folder, cell, cols, bg, name):
        rows = math.ceil(len(entries) / cols)
        img = Image.new("RGBA", (cols * (cell + 20) + 20, rows * (cell + 44) + 20), bg)
        draw = ImageDraw.Draw(img)
        for i, key in enumerate(entries):
            x, y = 20 + (i % cols) * (cell + 20), 20 + (i // cols) * (cell + 44)
            pic = Image.open(OUT / folder / f"{key}.png").convert("RGBA").resize((cell, cell), Image.LANCZOS)
            img.alpha_composite(pic, (x, y))
            draw.text((x + cell // 2, y + cell + 18), key, font=small, fill=INK, anchor="mm")
        img.convert("RGB").save(REVIEW / name)

    sheet_of(list(groups["soulstones"]), "soulstones", 112, 7, "#e9a25c", "soulstone-parts.png")
    sheet_of(list(groups["status"]), "status", 96, 7, "#e9a25c", "status-badges.png")
    sheet_of(list(groups["bosses"]), "bosses", 220, 4, "#e9a25c", "bosses.png")
    sheet_of(list(groups["props"]), "props", 160, 4, "#e9a25c", "props.png")
    sheet_of(list(groups["hazards"]), "hazards", 128, 5, "#5a5a62", "hazards.png")

    # composed soul stones: element x family, with tiers on the last row
    families = list(EMBLEMS)
    elements = list(STONE_COLOURS)
    cell = 96
    img = Image.new("RGBA", (140 + len(families) * (cell + 8), 50 + (len(elements) + 1) * (cell + 8)), "#2a2630")
    draw = ImageDraw.Draw(img)
    folder = OUT / "soulstones"

    def compose(element, family, tier=1, boss=False):
        base = Image.open(folder / f"stone_{element}.png").convert("RGBA")
        base.alpha_composite(Image.open(folder / f"emblem_{family}.png").convert("RGBA"))
        if tier > 1:
            base.alpha_composite(Image.open(folder / f"tier_{tier}.png").convert("RGBA"))
        if boss:
            base.alpha_composite(Image.open(folder / "boss_rim.png").convert("RGBA"))
        return base.resize((cell, cell), Image.LANCZOS)

    for c, family in enumerate(families):
        draw.text((140 + c * (cell + 8) + cell // 2, 26), family, font=small, fill="#f0e8d8", anchor="mm")
    for r, element in enumerate(elements):
        y = 50 + r * (cell + 8)
        draw.text((16, y + cell // 2), element, font=font, fill="#f0e8d8", anchor="lm")
        for c, family in enumerate(families):
            img.alpha_composite(compose(element, family), (140 + c * (cell + 8), y))
    y = 50 + len(elements) * (cell + 8)
    draw.text((16, y + cell // 2), "tier/boss", font=font, fill="#f0e8d8", anchor="lm")
    for c, (element, family, tier, boss) in enumerate((("fire", "orc", 1, False), ("fire", "orc", 2, False), ("fire", "orc", 3, False),
                                                      ("ice", "undead", 3, False), ("none", "goblin", 1, True), ("fire", "elemental", 1, True),
                                                      ("will", "undead", 3, True))):
        img.alpha_composite(compose(element, family, tier, boss), (140 + c * (cell + 8), y))
    img.convert("RGB").save(REVIEW / "soulstones.png")

    # tile sheets side by side
    tiles = OUT / "tiles"
    names = ["temple-floor-slabs", "temple-wall-blocks", "crypt-floor-slabs", "crypt-wall-blocks"]
    img = Image.new("RGB", (4 * 330 + 50, 380), "#e9a25c")
    draw = ImageDraw.Draw(img)
    for i, name in enumerate(names):
        pic = Image.open(tiles / f"{name}.png").convert("RGB").resize((320, 320), Image.LANCZOS)
        img.paste(pic, (10 + i * 340, 10))
        draw.text((10 + i * 340 + 160, 350), name, font=small, fill=INK, anchor="mm")
    img.save(REVIEW / "tiles.png")


if __name__ == "__main__":
    main()
