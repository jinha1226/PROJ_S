"""Floor objects, map features and magic school icons in the paper-doll style.

Objects: the sixteen props of the old floor catalog (same ids), plus the
features the board used to draw as plain vector marks — stairs, the boss
pylon — and one picture per curio so a supply cache, a broken chest, a dead
adventurer and a mushroom patch no longer share one chest.

Schools: fire, ice, air, hex and summon, for the start-screen kit picker and
the mastery tab (the five weapons reuse tools/art/build_gear.py).

Run: python3 tools/art/build_objects.py
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402
import build_potions as potions  # noqa: E402
from build_gear import rrect, circle, svg, ground, WOOD, STEEL, DARK_STEEL, GOLD, LEATHER  # noqa: E402

ROOT = flat.ROOT
OUT = ROOT / "assets/objects-v1"
SCHOOLS_OUT = ROOT / "assets/items-v1/schools"
REVIEW = ROOT / "docs/art/objects-v1"
INK = flat.INK
LINE = flat.LINE
S = doll.shaded

STONE = ("#a7adba", "#848b9a")
DARK_STONE = ("#6f7686", "#565d6c")
DIRT = ("#8a6a48", "#6e5236")
BONE = ("#f1ead6", "#d4c9aa")
FIRE = ("#ff8a2a", "#e0661a")
FLAME_CORE = ("#ffd84a", "#f2b82a")
CYAN = ("#6ff3ff", "#3fc8e0")


def flame(uid, cx, base, width, height):
    outer = (f"M{cx} {base - height} Q{cx + width} {base - height * 0.45} {cx + width * 0.8} {base - height * 0.15} "
             f"Q{cx + width * 0.6} {base} {cx} {base} Q{cx - width * 0.6} {base} {cx - width * 0.8} {base - height * 0.15} "
             f"Q{cx - width} {base - height * 0.45} {cx} {base - height} Z")
    inner = (f"M{cx} {base - height * 0.62} Q{cx + width * 0.5} {base - height * 0.3} {cx + width * 0.35} {base - height * 0.1} "
             f"Q{cx} {base + 1} {cx - width * 0.35} {base - height * 0.1} Q{cx - width * 0.5} {base - height * 0.3} {cx} {base - height * 0.62} Z")
    return S(uid + "o", outer, *FIRE, 1.4, 1.2) + S(uid + "i", inner, *FLAME_CORE, 0.8, 0.8)


def chest_body(uid, lid_path=None):
    lid = lid_path or rrect(9, 20, 55, 34, 6)
    return (S(uid + "b", rrect(11, 31, 53, 54, 3), "#c47d40", "#a7652f", 2.4, 2)
            + f'<path d="M20 31 L20 54 M44 31 L44 54" stroke="{INK}" stroke-width="3"/>'
            + S(uid + "l", lid, "#d68f4e", "#b8743a", 1.8, 1.6))


OBJECTS = {
    "pillar_broken": svg(ground(15) + S("pb", rrect(20, 20, 44, 54, 2), *STONE, 2.2, 1.8)
                         + '<path d="M26 24 L26 50 M32 24 L32 50 M38 24 L38 50" stroke="#848b9a" stroke-width="2.4"/>'
                         + S("pbb", rrect(15, 50, 49, 58, 2), *DARK_STONE, 1.4, 1.2)
                         + S("pbt", "M17 22 L22 12 L29 17 L35 8 L47 15 L47 23 L17 23 Z", "#c2c7d2", "#a7adba", 1.4, 1.2)),
    "rubble": svg(ground(20) + S("r1", "M8 56 L12 44 L22 40 L28 48 L26 56 Z", *STONE, 1.6, 1.4)
                  + S("r2", "M24 56 L27 38 L38 32 L48 40 L50 56 Z", *DARK_STONE, 2, 1.8)
                  + S("r3", "M44 56 L48 46 L56 46 L58 56 Z", *STONE, 1.2, 1)),
    "crate": svg(ground(18) + S("cr", rrect(12, 16, 52, 56, 2), "#b8814a", "#98663a", 2.4, 2)
                 + f'<path d="M12 16 L52 56 M52 16 L12 56" stroke="{INK}" stroke-width="3.2"/>'
                 + '<path d="M13 17 L51 55 M51 17 L13 55" stroke="#d6a064" stroke-width="1.4"/>'
                 + f'<rect x="12" y="16" width="40" height="40" rx="2" fill="none" {LINE}/>'
                 + f'<rect x="16" y="20" width="32" height="32" fill="none" stroke="#7a522c" stroke-width="2"/>'),
    "barrel": svg(ground(15) + S("ba", "M18 12 Q14 34 18 56 L46 56 Q50 34 46 12 Z", "#a8703e", "#865630", 2.4, 2)
                  + f'<path d="M16 24 Q32 28 48 24 M15.5 44 Q32 48 48.5 44" fill="none" stroke="{INK}" stroke-width="4"/>'
                  + '<path d="M16 24 Q32 28 48 24 M15.5 44 Q32 48 48.5 44" fill="none" stroke="#9aa3b3" stroke-width="2"/>'
                  + S("bat", "M18 12 A14 4.5 0 1 0 46 12 A14 4.5 0 1 0 18 12 Z", "#c48a52", "#a8703e", 1.2, 1)),
    "torch_lit": svg(ground(8) + S("tl", rrect(28.5, 28, 35.5, 56, 2), *WOOD, 1, 1)
                     + S("tc", "M21 26 L43 26 L39 33 L25 33 Z", *DARK_STEEL, 1.2, 1) + flame("tf", 32, 27, 11, 24)),
    "torch_unlit": svg(ground(8) + S("tu", rrect(28.5, 28, 35.5, 56, 2), *WOOD, 1, 1)
                       + S("tuc", "M21 26 L43 26 L39 33 L25 33 Z", *DARK_STEEL, 1.2, 1)
                       + S("tus", "M25 26 Q25 18 32 17 Q39 18 39 26 Z", "#4a4038", "#35302a", 1, 1)),
    "brazier": svg(ground(16) + f'<path d="M22 56 L28 38 M42 56 L36 38 M32 56 L32 40" stroke="{INK}" stroke-width="6" stroke-linecap="round"/>'
                   + '<path d="M22 56 L28 38 M42 56 L36 38 M32 56 L32 40" stroke="#6c7686" stroke-width="2.6" stroke-linecap="round"/>'
                   + flame("bf", 32, 30, 14, 26)
                   + S("bb", "M12 28 L52 28 Q50 42 32 42 Q14 42 12 28 Z", *DARK_STEEL, 2, 1.8)),
    "campfire": svg(ground(20)
                    + "".join(S(f"cs{i}", circle(x, y, 4.2), *STONE, 1, 1) for i, (x, y) in enumerate(((12, 52), (20, 56), (32, 58), (44, 56), (52, 52))))
                    + S("cl1", "M12 50 L48 38 L51 44 L15 56 Z", *WOOD, 1.2, 1) + S("cl2", "M52 50 L16 38 L13 44 L49 56 Z", "#b87a44", "#8e5c30", 1.2, 1)
                    + flame("cf", 32, 46, 13, 34)),
    "locked_chest": svg(ground(20) + chest_body("lc")
                        + f'<rect x="9" y="30" width="46" height="5" fill="#f2c64b" {LINE}/>'
                        + S("lck", rrect(27, 33, 37, 45, 2.5), *GOLD, 1, 1)
                        + f'<circle cx="32" cy="38" r="1.8" fill="{INK}"/><path d="M32 39 L32 42" stroke="{INK}" stroke-width="2"/>'),
    "dirt_pile": svg(ground(21) + S("dp", "M6 56 Q10 40 22 38 Q30 28 40 34 Q54 36 58 56 Z", *DIRT, 2.4, 2)
                     + '<circle cx="24" cy="46" r="2" fill="#6e5236"/><circle cx="40" cy="44" r="2.4" fill="#6e5236"/><circle cx="33" cy="51" r="1.6" fill="#6e5236"/>'),
    "sarcophagus": svg(ground(21) + S("sa", rrect(8, 26, 56, 56, 5), *DARK_STONE, 2.4, 2)
                       + S("sl", rrect(6, 20, 58, 34, 6), *STONE, 1.8, 1.6)
                       + S("se", "M32 23 L37 27 L32 31 L27 27 Z", *GOLD, 0.8, 0.8)
                       + '<path d="M14 42 L50 42 M14 48 L50 48" stroke="#565d6c" stroke-width="2"/>'),
    "altar": svg(ground(21) + S("al", rrect(10, 30, 54, 56, 3), *STONE, 2.4, 2)
                 + S("alt", rrect(6, 24, 58, 32, 3), "#c2c7d2", "#a7adba", 1.4, 1.2)
                 + '<path d="M26 42 L32 36 L38 42 L32 48 Z" fill="none" stroke="#6ff3ff" stroke-width="3" stroke-linejoin="round"/>'
                 + S("ac1", rrect(12, 14, 17, 24, 1.5), *BONE, 0.8, 0.8) + S("ac2", rrect(47, 14, 52, 24, 1.5), *BONE, 0.8, 0.8)
                 + "".join(f'<path d="M{x} 4 Q{x + 4} 9 {x + 2.6} 12.5 Q{x} 14.5 {x - 2.6} 12.5 Q{x - 4} 9 {x} 4 Z" fill="#ffb03a" stroke="{INK}" stroke-width="1.6" stroke-linejoin="round"/>'
                           f'<ellipse cx="{x}" cy="11" rx="1.3" ry="2" fill="#fff0a0"/>' for x in (14.5, 49.5))),
    "relic": svg(ground(16) + S("rp", "M18 56 L22 40 L42 40 L46 56 Z", *STONE, 2, 1.8)
                 + S("rpt", rrect(16, 36, 48, 42, 2), "#c2c7d2", "#a7adba", 1.2, 1)
                 + S("rc", "M32 4 L42 18 L32 36 L22 18 Z", *CYAN, 2, 1.8)
                 + '<path d="M32 4 L28 18 L32 36 M22 18 L42 18" fill="none" stroke="#c8fbff" stroke-width="2"/>'
                 + f'<path d="M32 4 L42 18 L32 36 L22 18 Z" fill="none" {LINE}/>'),
    "gate": svg(ground(24) + S("ga", "M6 58 L6 24 Q6 6 32 6 Q58 6 58 24 L58 58 L46 58 L46 26 Q46 18 32 18 Q18 18 18 26 L18 58 Z", *STONE, 2.4, 2)
                + f'<path d="M18 58 L18 26 Q18 18 32 18 Q46 18 46 26 L46 58 Z" fill="#23242e" {LINE}/>'
                + "".join(f'<path d="M{x} 22 L{x} 58" stroke="{INK}" stroke-width="4.4"/><path d="M{x} 22 L{x} 58" stroke="#8e98a8" stroke-width="2"/>' for x in (24, 32, 40))
                + f'<path d="M18 36 L46 36" stroke="{INK}" stroke-width="4.4"/><path d="M18 36 L46 36" stroke="#8e98a8" stroke-width="2"/>'),
    "bones": svg(ground(20) + f'<g transform="rotate(-18 32 46)"><rect x="10" y="44" width="42" height="6" rx="3" fill="#f1ead6" {LINE}/>'
                 + f'<circle cx="10" cy="44" r="4" fill="#f1ead6" {LINE}/><circle cx="10" cy="50" r="4" fill="#f1ead6" {LINE}/>'
                 + f'<circle cx="52" cy="44" r="4" fill="#f1ead6" {LINE}/><circle cx="52" cy="50" r="4" fill="#f1ead6" {LINE}/></g>'
                 + S("bs", "M22 34 Q22 22 33 22 Q44 22 44 34 L44 38 Q44 42 40 42 L26 42 Q22 42 22 38 Z", *BONE, 1.4, 1.2)
                 + f'<rect x="27" y="29" width="3.4" height="6" rx="1.7" fill="{INK}"/><rect x="35" y="29" width="3.4" height="6" rx="1.7" fill="{INK}"/>'),
    "barricade": svg(ground(22) + S("bx1", "M6 50 L52 18 L58 26 L12 58 Z", *WOOD, 1.8, 1.6)
                     + S("bx2", "M58 50 L12 18 L6 26 L52 58 Z", "#b87a44", "#8e5c30", 1.8, 1.6)
                     + S("bxn", circle(32, 38, 3.4), *DARK_STEEL, 0.8, 0.8)),
    # Map features that used to be plain marks.
    "stairs": svg(S("st", rrect(6, 8, 58, 58, 6), *DARK_STONE, 2, 1.8)
                  + f'<rect x="12" y="14" width="40" height="40" rx="3" fill="#15161d" {LINE}/>'
                  + "".join(f'<rect x="{14 + i * 3}" y="{17 + i * 9}" width="{36 - i * 6}" height="6" rx="1.5" fill="{c}"/>'
                            for i, c in enumerate(("#9aa1b0", "#7c8394", "#5f6576", "#444a58")))
                  + '<path d="M32 30 L32 46 M26 40 L32 46 L38 40" fill="none" stroke="#ffd84a" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>'),
    "pylon": svg(ground(16) + S("pyb", "M20 56 L24 30 L40 30 L44 56 Z", *DARK_STEEL, 2, 1.8)
                 + '<path d="M22 44 L42 44" stroke="#8e98a8" stroke-width="2.4"/>'
                 + S("pyc", rrect(18, 24, 46, 32, 2.5), *STEEL, 1.2, 1)
                 + S("pyo", "M32 2 L42 14 L32 26 L22 14 Z", *CYAN, 1.8, 1.6)
                 + '<path d="M14 10 L20 14 M50 10 L44 14 M12 20 L20 18 M52 20 L44 18" stroke="#6ff3ff" stroke-width="2.6" stroke-linecap="round"/>'),
    "supply_cache": svg(ground(20) + S("sc", rrect(10, 28, 54, 56, 3), "#b8814a", "#98663a", 2.4, 2)
                        + f'<path d="M10 42 L54 42" stroke="{INK}" stroke-width="3"/>'
                        + S("sck", "M16 30 Q12 14 26 12 Q34 16 32 30 Z", "#e2cf9a", "#c7b077", 1.4, 1.2)
                        + f'<path d="M20 16 Q24 18 28 15" fill="none" stroke="{INK}" stroke-width="2"/>'
                        + S("scb", "M34 30 Q36 18 46 18 Q54 20 52 30 Z", "#e0a050", "#c4843a", 1.2, 1)
                        + '<path d="M40 22 L44 26 M44 22 L40 26" stroke="#8a5a30" stroke-width="1.6"/>'),
    "broken_chest": svg(ground(20) + chest_body("bc", "M8 22 L50 10 L54 20 L12 34 Z")
                        + f'<path d="M24 31 L28 40 L24 46 M40 31 L37 38" fill="none" stroke="{INK}" stroke-width="2.6" stroke-linecap="round"/>'
                        + S("bcg", circle(18, 30, 3.2), *GOLD, 0.8, 0.8) + S("bcg2", circle(46, 28, 2.6), *GOLD, 0.8, 0.8)),
    "dead_adventurer": svg(ground(24) + S("dab", "M10 52 Q10 42 22 42 L44 42 Q54 42 54 52 Q54 56 48 56 L16 56 Q10 56 10 52 Z", "#6b7a5a", "#56644a", 2, 1.8)
                           + S("das", "M4 44 Q4 32 14 32 Q24 32 24 44 L24 48 Q24 52 20 52 L8 52 Q4 52 4 48 Z", *BONE, 1.4, 1.2)
                           + f'<rect x="8" y="38" width="3.2" height="6" rx="1.6" fill="{INK}"/><rect x="15" y="38" width="3.2" height="6" rx="1.6" fill="{INK}"/>'
                           + S("dap", rrect(30, 28, 50, 44, 4), *LEATHER, 1.4, 1.2)
                           + f'<path d="M34 28 Q40 22 46 28" fill="none" stroke="{INK}" stroke-width="2.6"/>'
                           + f'<g transform="rotate(-60 50 50)"><rect x="47" y="30" width="5" height="26" rx="1.5" fill="#dfe6ef" {LINE}/>'
                           + f'<rect x="43" y="54" width="13" height="4" rx="2" fill="#f2c64b" {LINE}/></g>'),
    "mushrooms": svg(ground(20)
                     + "".join(S(f"ms{i}", rrect(x - 3, y, x + 3, 56, 2), *BONE, 0.8, 0.8) + S(f"mc{i}", f"M{x - r} {y + 1} Q{x - r} {y - r} {x} {y - r} Q{x + r} {y - r} {x + r} {y + 1} Z", *col, 1.4, 1.2)
                               + f'<circle cx="{x - r * 0.35}" cy="{y - r * 0.45}" r="{r * 0.18}" fill="#fff4e6"/><circle cx="{x + r * 0.3}" cy="{y - r * 0.25}" r="{r * 0.14}" fill="#fff4e6"/>'
                               for i, (x, y, r, col) in enumerate(((20, 38, 11, ("#d8503a", "#b83c2c")), (42, 42, 9, ("#e08a3a", "#c06e28")), (31, 48, 6, ("#d8503a", "#b83c2c")))))),
}

SCHOOLS = {
    "fire": potions.EFFECTS["liquid_flame"],
    "ice": potions.EFFECTS["frost"],
    "air": (f'<path d="M6 20 Q28 12 42 20 Q54 26 48 32 Q42 36 38 30" fill="none" stroke="{INK}" stroke-width="9" stroke-linecap="round"/>'
         + '<path d="M6 20 Q28 12 42 20 Q54 26 48 32 Q42 36 38 30" fill="none" stroke="#a6ecff" stroke-width="4" stroke-linecap="round"/>'
         + f'<path d="M10 36 Q30 30 44 38 Q52 44 46 50" fill="none" stroke="{INK}" stroke-width="9" stroke-linecap="round"/>'
         + '<path d="M10 36 Q30 30 44 38 Q52 44 46 50" fill="none" stroke="#6fd0f0" stroke-width="4" stroke-linecap="round"/>'
         + f'<path d="M14 52 Q30 46 40 52 Q46 56 42 60" fill="none" stroke="{INK}" stroke-width="9" stroke-linecap="round"/>'
         + '<path d="M14 52 Q30 46 40 52 Q46 56 42 60" fill="none" stroke="#a6ecff" stroke-width="4" stroke-linecap="round"/>'),
    "hex": S("hexr", circle(32, 32, 26), "#5a3a86", "#46306a", 2.4, 2)
    + f'<path d="{potions.star(32, 32, 20, 8, 6)}" fill="none" stroke="#c9a2ff" stroke-width="3" stroke-linejoin="round"/>'
    + S("hexe", "M18 32 Q32 20 46 32 Q32 44 18 32 Z", "#f4ecd2", "#d6c6a2", 1, 1)
    + S("hexp", circle(32, 32, 5), "#b066e8", "#8a48c8", 0.8, 0.8) + f'<circle cx="32" cy="32" r="2" fill="{INK}"/>',
    "summon": S("smc", circle(32, 32, 26), "#3a6a4a", "#2c5238", 2.4, 2)
    + f'<circle cx="32" cy="32" r="19" fill="none" stroke="#9ae0a0" stroke-width="2.4" stroke-dasharray="5 4"/>'
    + S("smp", "M20 40 Q20 30 32 30 Q44 30 44 40 Q44 46 38 46 Q34 44 32 44 Q30 44 26 46 Q20 46 20 40 Z", "#f4ecd2", "#d6c6a2", 1.2, 1)
    + "".join(S(f"smt{i}", circle(x, y, 4), "#f4ecd2", "#d6c6a2", 0.6, 0.6) for i, (x, y) in enumerate(((20, 26), (28, 20), (36, 20), (44, 26)))),
}


def main() -> None:
    (OUT / "svg").mkdir(parents=True, exist_ok=True)
    (SCHOOLS_OUT / "svg").mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    jobs = []
    for name, body in OBJECTS.items():
        source = OUT / "svg" / f"{name}.svg"
        source.write_text(body)
        jobs.append((source, OUT / f"{name}.png", 3))
    for name, body in SCHOOLS.items():
        source = SCHOOLS_OUT / "svg" / f"{name}.svg"
        source.write_text(potions.icon_svg(body, False))
        jobs.append((source, SCHOOLS_OUT / f"{name}.png", 3))
    flat.rasterise(jobs)

    font = ImageFont.truetype(str(ROOT / "assets/fonts/Jua-Regular.ttf"), 16)
    cell, pad, cols = 104, 14, 8
    names = [("obj", n) for n in OBJECTS] + [("school", n) for n in SCHOOLS]
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGBA", (pad + cols * (cell + pad), rows * (cell + 34) + pad), "#4a4e5c")
    draw = ImageDraw.Draw(sheet)
    for i, (kind, name) in enumerate(names):
        x = pad + (i % cols) * (cell + pad)
        y = pad + (i // cols) * (cell + 34)
        folder = OUT if kind == "obj" else SCHOOLS_OUT
        image = Image.open(folder / f"{name}.png").convert("RGBA").resize((cell, cell), Image.LANCZOS)
        sheet.alpha_composite(image, (x, y))
        draw.text((x + cell // 2, y + cell + 12), name, font=font, fill="#f2eee4", anchor="mm")
    sheet.convert("RGB").save(REVIEW / "objects-sheet.png")


if __name__ == "__main__":
    main()
