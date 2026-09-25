"""Scrolls, weapons, armour, shield, rings and the spellbook.

Scrolls work like the potions (tools/art/build_potions.py): one rolled sheet,
ten looks told apart by the ribbon and wax seal, in consumables.json
`appearances.scroll` order, and an effect badge per scroll kind. Gear follows
combat.json: seven weapons, four armours, the shield, six rings that differ
only in their gem, and one spellbook.

Same grammar as the paper dolls: bold ink outline, flat fills, one contour
crescent of shade on the lower right.

Run: python3 tools/art/build_gear.py
"""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402
import build_potions as potions  # noqa: E402

ROOT = flat.ROOT
OUT = ROOT / "assets/items-v1"
REVIEW = ROOT / "docs/art/items-v1"
INK = flat.INK
LINE = flat.LINE
S = doll.shaded

# The ten seal colours reuse the potion liquids, in appearance order.
SEALS = [(pid, colours[0], colours[1], colours[2]) for pid, _, *colours in potions.LIQUIDS]
SCROLL_LOOKS = ["zelgo_mer", "kirje", "andova", "pratyav", "venzar", "nafa", "temov", "gari", "lomas", "xixaxa"]
PARCHMENT = ("#f4e4bc", "#dcc690")
ROLL = ("#e6cf98", "#c9ae72")
STEEL = ("#d4dbe4", "#a8b3c2")
DARK_STEEL = ("#8e98a8", "#6c7686")
WOOD = ("#a8703e", "#865630")
GOLD = ("#f2c64b", "#d19e22")
LEATHER = ("#9a6436", "#7a4c28")


def svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>'


def rrect(x0, y0, x1, y1, r):
    return (f"M{x0 + r} {y0} L{x1 - r} {y0} Q{x1} {y0} {x1} {y0 + r} L{x1} {y1 - r} Q{x1} {y1} {x1 - r} {y1} "
            f"L{x0 + r} {y1} Q{x0} {y1} {x0} {y1 - r} L{x0} {y0 + r} Q{x0} {y0} {x0 + r} {y0} Z")


def circle(cx, cy, r):
    return f"M{cx - r} {cy} A{r} {r} 0 1 0 {cx + r} {cy} A{r} {r} 0 1 0 {cx - r} {cy} Z"


def ground(rx=14):
    return f'<ellipse cx="32" cy="60" rx="{rx}" ry="2.8" fill="#000" fill-opacity="0.18"/>'


# --- scrolls ---------------------------------------------------------------

def scroll_svg(uid, ribbon, seal, glint):
    return svg(ground(18)
               + S(uid + "p", rrect(16, 12, 48, 52, 2), *PARCHMENT, 2.4, 2)
               + '<path d="M21 21 L36 21 M21 26.5 L41 26.5 M21 43 L38 43 M21 48 L33 48" stroke="#9a7a4a" stroke-width="2.6" stroke-linecap="round"/>'
               + S(uid + "t", rrect(11, 7, 53, 16, 4.5), *ROLL, 1.4, 1.2)
               + S(uid + "b", rrect(11, 48, 53, 57, 4.5), *ROLL, 1.4, 1.2)
               + S(uid + "r", rrect(16, 31, 48, 37, 1), ribbon, seal, 1, 1)
               + S(uid + "s", circle(32, 34, 7.5), seal, ribbon, 1.2, 1.2)
               + f'<path d="{potions.star(32, 34, 4, 1.8)}" fill="{glint}"/>'
               + '<path d="M13 10 L22 10" stroke="#fff6dc" stroke-width="2.4" stroke-linecap="round"/>')


SCROLL_EFFECTS = {
    "identify": f'<rect x="38" y="36" width="10" height="24" rx="4" transform="rotate(-45 43 48)" fill="{WOOD[0]}" {LINE}/>'
    + S("idg", circle(26, 26, 18), "#a8ddff", "#86c6ef", 2.4, 2)
    + '<path d="M16 20 A11 11 0 0 1 25 14" fill="none" stroke="#ffffff" stroke-width="4.5" stroke-linecap="round"/>',
    "upgrade": S("upa", "M32 4 L56 30 L42 30 L42 58 L22 58 L22 30 L8 30 Z", "#5fd35a", "#43ae40", 2.6, 2.2)
    + '<path d="M28 34 L28 52" stroke="#b8f2a8" stroke-width="4" stroke-linecap="round"/>',
    "magic_mapping": S("mp", "M6 14 L22 8 L42 14 L58 8 L58 50 L42 56 L22 50 L6 56 Z", "#f4e4bc", "#dcc690", 2.4, 2)
    + f'<path d="M22 8 L22 50 M42 14 L42 56" stroke="{INK}" stroke-width="2.2"/>'
    + '<path d="M12 44 Q20 30 30 34 Q40 38 46 24" fill="none" stroke="#c0392f" stroke-width="3" stroke-dasharray="4 4" stroke-linecap="round"/>'
    + f'<path d="M44 18 L52 26 M52 18 L44 26" stroke="#c0392f" stroke-width="4" stroke-linecap="round"/>',
    "teleportation": S("tpo", circle(32, 32, 26), "#9a52d0", "#7a3eaa", 2.6, 2.2)
    + '<path d="M32 32 m0 -4 a4 4 0 1 1 -4 4 a8 8 0 1 1 8 8 a12 12 0 1 1 -12 -12 a16 16 0 1 1 16 16" fill="none" stroke="#e2c6fa" stroke-width="3.6" stroke-linecap="round"/>',
    "mirror_image": S("mib", "M34 58 Q34 40 46 38 Q58 40 58 58 Z", "#bcd6ff", "#94b8ea", 1.6, 1.4) + S("mih", circle(46, 26, 9), "#bcd6ff", "#94b8ea", 1.6, 1.4)
    + S("mfb", "M8 58 Q8 38 22 36 Q36 38 36 58 Z", "#6f9ae8", "#5580d0", 2, 1.8) + S("mfh", circle(22, 23, 10), "#6f9ae8", "#5580d0", 2, 1.8),
    "lullaby": f'<path d="M22 44 L22 12 L50 6 L50 38" fill="none" stroke="{INK}" stroke-width="9" stroke-linejoin="round"/>'
    + '<path d="M22 44 L22 12 L50 6 L50 38" fill="none" stroke="#6f9ae8" stroke-width="3.8" stroke-linejoin="round"/>'
    + S("lu1", "M8 48 A8 6 0 1 0 24 48 A8 6 0 1 0 8 48 Z", "#6f9ae8", "#5580d0", 1.6, 1.4)
    + S("lu2", "M36 42 A8 6 0 1 0 52 42 A8 6 0 1 0 36 42 Z", "#6f9ae8", "#5580d0", 1.6, 1.4),
    "rage": S("rgf", circle(32, 32, 26), "#ec4a4a", "#c63434", 2.6, 2.2)
    + f'<path d="M14 20 L27 26 M50 20 L37 26" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>'
    + f'<rect x="19" y="27" width="6" height="8" rx="3" fill="{INK}"/><rect x="39" y="27" width="6" height="8" rx="3" fill="{INK}"/>'
    + f'<path d="M20 46 L25 41 L30 46 L34 41 L39 46 L44 41" fill="none" stroke="{INK}" stroke-width="3.4" stroke-linejoin="round" stroke-linecap="round"/>',
    "recharging": S("rcg", "M32 4 L52 24 L32 60 L12 24 Z", "#5fb8f4", "#3f96d8", 2.4, 2)
    + '<path d="M32 4 L24 24 L32 60 M12 24 L52 24" fill="none" stroke="#bfe6ff" stroke-width="2.6"/>'
    + f'<path d="M32 4 L52 24 L32 60 L12 24 Z" fill="none" {LINE}/>',
}


# --- gear -------------------------------------------------------------------

def diagonal(body):
    """Weapons are drawn upright and turned 45 degrees: grip lower-left, point upper-right."""
    return svg(ground(14) + f'<g transform="rotate(45 32 32)">{body}</g>')


WEAPONS = {
    "sword": diagonal(S("swb", "M29 4 L32 0 L35 4 L35 40 L29 40 Z", *STEEL, 1.4, 1.2)
                      + S("swg", rrect(20, 39, 44, 45, 3), *GOLD, 1.2, 1) + S("swh", rrect(29.5, 45, 34.5, 57, 2), *WOOD, 1, 1)
                      + S("swp", circle(32, 59, 3.4), *GOLD, 1, 1)),
    "dagger": diagonal(S("dab", "M28.5 16 L32 10 L35.5 16 L35.5 40 L28.5 40 Z", *STEEL, 1.4, 1.2)
                       + S("dag", rrect(23, 39, 41, 44, 2.5), *GOLD, 1, 1) + S("dah", rrect(29.5, 44, 34.5, 54, 2), *LEATHER, 1, 1)),
    "spear": diagonal(S("sps", rrect(30, 16, 34, 62, 2), *WOOD, 1, 1)
                      + S("spt", "M32 0 L39 12 L32 20 L25 12 Z", *STEEL, 1.4, 1.2)
                      + S("spb", rrect(28.5, 18, 35.5, 22, 1.5), *GOLD, 1, 1)),
    "mace": diagonal(S("mah", rrect(29.5, 24, 34.5, 60, 2.5), *WOOD, 1, 1)
                     + S("mas", potions.star(32, 15, 15, 10, 8, -90), *DARK_STEEL, 1.6, 1.4)
                     + S("mab", circle(32, 15, 9), *STEEL, 1.6, 1.4)),
    "axe": diagonal(S("axh", rrect(29.5, 6, 34.5, 60, 2.5), *WOOD, 1, 1)
                    + S("axb", "M34 8 Q52 8 56 20 Q52 32 34 30 Z", *STEEL, 1.8, 1.4)
                    + S("axc", rrect(28, 12, 36, 26, 2), *DARK_STEEL, 1, 1)),
    "bow": svg(ground(14)
               + '<path d="M18 8 L46 56" stroke="#fff6dc" stroke-width="2.4"/>'
               + S("bow", "M18 8 Q54 14 46 56 Q48 20 18 8 Z", *WOOD, 1.6, 1.4)
               + S("bgr", rrect(35, 26, 43, 36, 2), *LEATHER, 1, 1)),
    "staff": diagonal(S("sts", rrect(30, 14, 34, 62, 2), *WOOD, 1, 1)
                      + S("stc", "M24 16 Q24 6 32 4 Q40 6 40 16 L36 18 L28 18 Z", *WOOD, 1.2, 1)
                      + S("sto", circle(32, 11, 6.5), "#6ff3ff", "#3fc8e0", 1.2, 1)
                      + '<circle cx="30" cy="9" r="1.8" fill="#ffffff"/>'),
}

ARMOURS = {
    "robe": svg(ground(16) + S("rob", "M22 6 L32 12 L42 6 L50 14 L46 22 L50 58 L14 58 L18 22 L14 14 Z", "#6a60b8", "#544a98", 2.4, 2)
                + f'<path d="M22 6 L32 20 L42 6" fill="none" {LINE}/>'
                + f'<path d="M18 32 L46 32" stroke="#f2c64b" stroke-width="3.4" stroke-linecap="round"/>'
                + f'<path d="M30 32 L27 44 M34 32 L37 44" stroke="#f2c64b" stroke-width="3" stroke-linecap="round"/>'),
    "leather": svg(ground(16) + S("lea", "M16 12 L26 8 Q32 14 38 8 L48 12 L55 26 L46 30 L46 56 L18 56 L18 30 L9 26 Z", *LEATHER, 2.4, 2)
                   + f'<path d="M32 16 L32 56" stroke="{INK}" stroke-width="2.6"/>'
                   + '<path d="M22 22 L22 50 M42 22 L42 50" stroke="#c8925a" stroke-width="2" stroke-dasharray="3 3"/>'
                   + S("le1", circle(32, 28, 2.6), *GOLD, 0.6, 0.6) + S("le2", circle(32, 40, 2.6), *GOLD, 0.6, 0.6)),
    "mail": svg(ground(16) + S("mai", "M16 12 L26 8 Q32 14 38 8 L48 12 L55 28 L46 32 L46 56 L18 56 L18 32 L9 28 Z", *DARK_STEEL, 2.4, 2)
                + "".join(f'<circle cx="{x}" cy="{y}" r="2.2" fill="none" stroke="#c9d1dc" stroke-width="1.4"/>'
                          for y in range(18, 54, 6) for x in range(22 + (3 if (y // 6) % 2 else 0), 44, 6))
                + f'<path d="M16 12 L26 8 Q32 14 38 8 L48 12 L55 28 L46 32 L46 56 L18 56 L18 32 L9 28 Z" fill="none" {LINE}/>'),
    "plate": svg(ground(16) + S("plb", "M18 14 L46 14 L48 34 Q46 52 32 56 Q18 52 16 34 Z", *STEEL, 2.4, 2)
                 + S("pll", "M6 22 Q6 10 18 10 L22 12 L20 26 Q12 28 6 22 Z", *STEEL, 1.4, 1.2)
                 + S("plr", "M58 22 Q58 10 46 10 L42 12 L44 26 Q52 28 58 22 Z", *STEEL, 1.4, 1.2)
                 + f'<path d="M32 16 L32 54" stroke="#a8b3c2" stroke-width="2.6"/><path d="M20 34 Q32 38 44 34" fill="none" stroke="#a8b3c2" stroke-width="2.6"/>'
                 + '<path d="M22 20 Q24 17 28 17" fill="none" stroke="#ffffff" stroke-width="2.6" stroke-linecap="round"/>'),
}

SHIELD = svg(ground(15) + S("shs", "M32 4 L54 12 Q54 44 32 58 Q10 44 10 12 Z", "#3f7fe0", "#2f62b8", 2.6, 2.2)
             + f'<path d="M32 4 L54 12 Q54 44 32 58 Q10 44 10 12 Z" fill="none" stroke="#f2c64b" stroke-width="0"/>'
             + '<path d="M32 14 L32 48 M18 26 L46 26" stroke="#f2c64b" stroke-width="5.5" stroke-linecap="round"/>'
             + '<path d="M16 16 Q20 13 25 12" fill="none" stroke="#9fc0f5" stroke-width="3" stroke-linecap="round"/>')

# Ring gems: fire, ice, poison, electric, power, evasion.
RINGS = {"fire": ("#ec4a3a", "#c63428"), "ice": ("#8fdcff", "#5fb8e8"), "poison": ("#6fd04a", "#4eae34"),
         "air": ("#ffe04a", "#e0b82a"), "power": ("#b066e8", "#8a48c8"), "ev": ("#e8f0f8", "#b8c6d6")}


def ring_svg(uid, gem):
    return svg(ground(13)
               + f'<circle cx="32" cy="40" r="15" fill="none" stroke="{INK}" stroke-width="11"/>'
               + f'<circle cx="32" cy="40" r="15" fill="none" stroke="{GOLD[1]}" stroke-width="6"/>'
               + f'<path d="M20 32 A15 15 0 0 1 36 25.5" fill="none" stroke="{GOLD[0]}" stroke-width="4" stroke-linecap="round"/>'
               + S(uid + "c", rrect(24, 18, 40, 28, 3), *GOLD, 1.2, 1)
               + S(uid + "g", "M32 4 L42 14 L32 26 L22 14 Z", *gem, 1.6, 1.4)
               + '<path d="M27 13 L31 9" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round"/>')


BOOK = svg(ground(16) + S("bkp", rrect(14, 10, 52, 56, 3), "#f4e4bc", "#dcc690", 1, 1)
           + S("bkc", rrect(10, 6, 48, 54, 4), "#7a3a8a", "#5e2a6c", 2.4, 2)
           + S("bks", rrect(10, 6, 17, 54, 3), "#5e2a6c", "#4a1f56", 1, 1)
           + "".join(S(f"bk{i}", f"M{x} {y} L{x + 7 * sx} {y} L{x} {y + 7 * sy} Z", *GOLD, 0.6, 0.6)
                     for i, (x, y, sx, sy) in enumerate(((48, 6, -1, 1), (48, 54, -1, -1))))
           + S("bkg", "M32 20 L39 30 L32 40 L25 30 Z", "#6ff3ff", "#3fc8e0", 1.2, 1))


def main() -> None:
    dirs = {k: OUT / k for k in ("scrolls", "scroll-effects", "scroll-effects-badge", "gear/weapons", "gear/armours", "gear/rings", "gear")}
    for d in dirs.values():
        (d / "svg").mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    entries = []
    for look, (pid, fill, shade, glint) in zip(SCROLL_LOOKS, SEALS):
        entries.append(("scrolls", look, scroll_svg("s" + look, fill, shade, glint)))
    for kind, body in SCROLL_EFFECTS.items():
        entries.append(("scroll-effects", kind, potions.icon_svg(body, False)))
        entries.append(("scroll-effects-badge", kind, potions.icon_svg(body, True)))
    entries += [("gear/weapons", k, v) for k, v in WEAPONS.items()]
    entries += [("gear/armours", k, v) for k, v in ARMOURS.items()]
    entries += [("gear/rings", k, ring_svg("r" + k, gem)) for k, gem in RINGS.items()]
    entries += [("gear", "shield", SHIELD), ("gear", "book", BOOK)]
    jobs = []
    for key, name, body in entries:
        source = dirs[key] / "svg" / f"{name}.svg"
        source.write_text(body)
        jobs.append((source, dirs[key] / f"{name}.png", 3))
    flat.rasterise(jobs)

    font = ImageFont.truetype(str(ROOT / "assets/fonts/Jua-Regular.ttf"), 18)
    cell, pad = 104, 14
    rows = [[("scrolls", n) for n in SCROLL_LOOKS],
            [("scroll-effects", n) for n in SCROLL_EFFECTS],
            [("scrolls", SCROLL_LOOKS[i]) for i in range(len(SCROLL_EFFECTS))],
            [("gear/weapons", n) for n in WEAPONS] + [("gear", "shield"), ("gear", "book")],
            [("gear/armours", n) for n in ARMOURS] + [("gear/rings", n) for n in RINGS]]
    width = pad + 10 * (cell + pad)
    sheet = Image.new("RGBA", (width, len(rows) * (cell + 36) + pad), "#e9a25c")
    draw = ImageDraw.Draw(sheet)
    for r, row in enumerate(rows):
        y = pad + r * (cell + 36)
        for c, (key, name) in enumerate(row):
            x = pad + c * (cell + pad)
            image = Image.open(dirs[key] / f"{name}.png").convert("RGBA").resize((cell, cell), Image.LANCZOS)
            sheet.alpha_composite(image, (x, y))
            if r == 2:
                kind = list(SCROLL_EFFECTS)[c]
                badge = Image.open(dirs["scroll-effects-badge"] / f"{kind}.png").convert("RGBA").resize((cell * 11 // 20,) * 2, Image.LANCZOS)
                sheet.alpha_composite(badge, (x + cell - badge.width + 4, y + cell - badge.height + 2))
            draw.text((x + cell // 2, y + cell + 14), name, font=font, fill=INK, anchor="mm")
    sheet.convert("RGB").save(REVIEW / "gear-sheet.png")


if __name__ == "__main__":
    main()
