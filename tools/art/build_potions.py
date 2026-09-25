"""Potions: one flask, ten liquids, and effect icons to overlay on them.

The flask is drawn once; only the liquid changes, in the order of
consumables.json `appearances.potion` (붉은, 푸른, 녹색, 호박색, 보라색, 은빛,
검은, 하얀, 탁한, 황금빛). Effect icons follow the potion kinds and come bare
and on a round badge that sits on the flask's lower-right corner, so a known
potion reads as "this colour + this effect" and an unknown one shows "?".

Same grammar as the paper dolls: bold ink outline, flat fills, one contour
crescent of shade on the lower right.

Run: python3 tools/art/build_potions.py
"""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_paperdoll as doll  # noqa: E402

ROOT = flat.ROOT
OUT = ROOT / "assets/items-v1"
REVIEW = ROOT / "docs/art/items-v1"
INK = flat.INK
LINE = flat.LINE

# id, Korean appearance, liquid, liquid shade, surface, bubble
LIQUIDS = [
    ("red", "붉은", "#e0453a", "#b8322b", "#f07a6c", "#ffb0a6"),
    ("blue", "푸른", "#3f7fe0", "#2f62b8", "#74a6f2", "#bcd6ff"),
    ("green", "녹색", "#4fbf4a", "#3a9a38", "#86dc72", "#c4f2b4"),
    ("amber", "호박색", "#e8952e", "#c27622", "#f4bb5e", "#ffe0a6"),
    ("purple", "보라색", "#9a52d0", "#7a3eaa", "#bc84e8", "#e2c6fa"),
    ("silver", "은빛", "#b8c2d0", "#8f9aab", "#e2e8f0", "#ffffff"),
    ("black", "검은", "#35303e", "#221e29", "#5a5268", "#8f86a0"),
    ("white", "하얀", "#eeeae0", "#cfc9ba", "#ffffff", "#ffffff"),
    ("murky", "탁한", "#7a7a42", "#5f5f32", "#9a9a5c", "#b8b884"),
    ("golden", "황금빛", "#f2c33a", "#d19e22", "#fbe07a", "#fff4c0"),
]
GLASS = ("#dcecf7", "#b8d0e2")


def potion_svg(uid: str, liquid: str, shade: str, surface: str, bubble: str) -> str:
    """The flask: cork, neck, round belly; liquid fills the belly to a level
    line, with a lighter surface, two bubbles and the glass glint on top."""
    body = doll.shaded(uid + "g", "M15 42 A17 17 0 1 0 49 42 A17 17 0 1 0 15 42 Z", *GLASS, 2.4, 2)
    liquid_shape = f'<clipPath id="{uid}c"><circle cx="32" cy="42" r="15.5"/></clipPath>'
    liquid_fill = (f'<g clip-path="url(#{uid}c)">'
                   f'<rect x="10" y="34" width="44" height="30" fill="{shade}"/>'
                   f'<circle cx="29" cy="40" r="15.5" fill="{liquid}"/>'
                   f'<ellipse cx="32" cy="34.5" rx="15" ry="3.2" fill="{surface}"/>'
                   f'<circle cx="26" cy="47" r="2.2" fill="{bubble}"/><circle cx="36" cy="51" r="1.5" fill="{bubble}"/>'
                   f'<circle cx="39" cy="44" r="1.1" fill="{bubble}"/></g>')
    outline = f'<circle cx="32" cy="42" r="17" fill="none" {LINE}/>'
    neck = doll.shaded(uid + "n", "M26.5 14 L37.5 14 L37.5 27 L26.5 27 Z", *GLASS, 1.4, 1)
    cork = doll.shaded(uid + "k", "M24.5 7 Q24.5 5 27 5 L37 5 Q39.5 5 39.5 7 L39.5 13 Q39.5 15 37 15 L27 15 Q24.5 15 24.5 13 Z",
                       "#b07840", "#8e5c2e", 1.4, 1.2)
    glint = ('<path d="M20 38 Q21 31 27 28" fill="none" stroke="#ffffff" stroke-width="3.2" stroke-linecap="round" opacity="0.9"/>'
             '<circle cx="21" cy="44" r="1.6" fill="#ffffff" opacity="0.9"/>')
    shadow = '<ellipse cx="32" cy="60" rx="13" ry="2.8" fill="#000" fill-opacity="0.18"/>'
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            + shadow + neck + body + liquid_shape + liquid_fill + outline + cork + glint + '</svg>')


def ring(points):
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in points) + " Z"


def star(cx, cy, outer, inner, n=5, rotate=-90):
    pts = []
    for i in range(n * 2):
        a = math.radians(rotate + i * 180 / n)
        r = outer if i % 2 == 0 else inner
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return ring(pts)


# Effect icons on the 64 grid, bold and simple enough to read at badge size.
EFFECTS = {
    "healing": doll.shaded("heal", "M32 54 L12 34 Q4 24 12 16 Q22 8 32 20 Q42 8 52 16 Q60 24 52 34 Z", "#ec4a4a", "#c63434", 2.6, 2.2)
    + '<path d="M18 22 Q21 17 26 18" fill="none" stroke="#ffb0b0" stroke-width="3.5" stroke-linecap="round"/>',
    "strength": doll.shaded("strb", "M20 28 L44 28 L44 36 L20 36 Z", "#b8c2d0", "#8f9aab", 1.4, 1.2)
    + doll.shaded("strl", "M8 18 Q8 15 11 15 L18 15 Q21 15 21 18 L21 46 Q21 49 18 49 L11 49 Q8 49 8 46 Z", "#5a6272", "#434a58", 2, 1.6)
    + doll.shaded("strr", "M43 18 Q43 15 46 15 L53 15 Q56 15 56 18 L56 46 Q56 49 53 49 L46 49 Q43 49 43 46 Z", "#5a6272", "#434a58", 2, 1.6),
    "haste": doll.shaded("hst", "M36 4 L14 36 L29 36 L24 60 L50 24 L34 24 Z", "#ffd23a", "#e0ac1c", 2.4, 2),
    "liquid_flame": doll.shaded("flo", "M32 4 Q48 20 48 36 Q48 56 32 56 Q16 56 16 36 Q16 26 24 18 Q24 28 30 30 Q26 16 32 4 Z", "#ff7a2a", "#e05a1a", 2.4, 2)
    + doll.shaded("fli", "M32 26 Q40 34 40 42 Q40 50 32 50 Q24 50 24 42 Q24 36 32 26 Z", "#ffd84a", "#f2b82a", 1.4, 1.2),
    "frost": "".join(f'<g transform="rotate({a} 32 32)"><path d="M32 6 L32 58 M32 14 L25 8 M32 14 L39 8 M32 50 L25 56 M32 50 L39 56" '
                     f'fill="none" stroke="{INK}" stroke-width="8" stroke-linecap="round"/></g>' for a in (0, 60, 120))
    + "".join(f'<g transform="rotate({a} 32 32)"><path d="M32 6 L32 58 M32 14 L25 8 M32 14 L39 8 M32 50 L25 56 M32 50 L39 56" '
              f'fill="none" stroke="#9fdcff" stroke-width="3.6" stroke-linecap="round"/></g>' for a in (0, 60, 120)),
    "toxic_gas": doll.shaded("tox", "M12 44 Q4 44 6 34 Q8 26 16 28 Q16 14 30 14 Q42 12 46 24 Q58 22 58 34 Q60 46 48 46 Z", "#7cd04a", "#5eae34", 2.4, 2)
    + f'<path d="M22 30 L28 36 M28 30 L22 36 M36 30 L42 36 M42 30 L36 36" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'
    + f'<path d="M26 42 Q32 38 38 42" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>',
    "experience": doll.shaded("exp", star(32, 34, 27, 12), "#ffd23a", "#e0ac1c", 2.4, 2)
    + '<path d="M24 26 L28 22" stroke="#fff4c0" stroke-width="3.5" stroke-linecap="round"/>',
    "calm": doll.shaded("clm", "M40 6 A26 26 0 1 0 58 44 A20 20 0 1 1 40 6 Z", "#8fb8f0", "#6a96d8", 2.2, 1.8)
    + f'<path d="M44 12 L52 12 L44 20 L52 20" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>',
    "unknown": f'<path d="M22 22 Q22 10 32 10 Q43 10 43 21 Q43 28 36 31 Q32 33 32 39" fill="none" stroke="{INK}" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>'
    + '<path d="M22 22 Q22 10 32 10 Q43 10 43 21 Q43 28 36 31 Q32 33 32 39" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>'
    + f'<circle cx="32" cy="52" r="6" fill="#ffffff" {LINE}/>',
}


def icon_svg(body: str, badge: bool) -> str:
    """Bare, or shrunk onto a cream disc with an ink rim so it reads over any liquid."""
    if badge:
        body = (f'<circle cx="32" cy="32" r="29" fill="#fff6e2" stroke="{INK}" stroke-width="4.5"/>'
                f'<g transform="translate(32 32) scale(0.72) translate(-32 -32)">{body}</g>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>'


def main() -> None:
    folders = {name: OUT / name for name in ("potions", "potion-effects", "potion-effects-badge")}
    for folder in folders.values():
        (folder / "svg").mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    jobs = []
    for pid, _, *colours in LIQUIDS:
        source = folders["potions"] / "svg" / f"{pid}.svg"
        source.write_text(potion_svg("p" + pid, *colours))
        jobs.append((source, folders["potions"] / f"{pid}.png", 3))
    for kind, body in EFFECTS.items():
        for key, badge in (("potion-effects", False), ("potion-effects-badge", True)):
            source = folders[key] / "svg" / f"{kind}.svg"
            source.write_text(icon_svg(body, badge))
            jobs.append((source, folders[key] / f"{kind}.png", 3))
    flat.rasterise(jobs)

    # Review sheet: the ten flasks; the icons bare; every effect on a flask.
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Jua-Regular.ttf"), 20)
    cell, pad = 120, 16
    width = pad + 10 * (cell + pad)
    sheet = Image.new("RGBA", (width, 3 * (cell + 44) + 60), "#e9a25c")
    draw = ImageDraw.Draw(sheet)

    def potion(pid):
        return Image.open(folders["potions"] / f"{pid}.png").convert("RGBA").resize((cell, cell), Image.LANCZOS)

    for i, (pid, name, *_) in enumerate(LIQUIDS):
        x = pad + i * (cell + pad)
        sheet.alpha_composite(potion(pid), (x, 12))
        draw.text((x + cell // 2, cell + 20), name, font=font, fill=INK, anchor="mm")
    y = cell + 50
    for i, kind in enumerate(EFFECTS):
        x = pad + i * (cell + pad)
        icon = Image.open(folders["potion-effects"] / f"{kind}.png").convert("RGBA").resize((cell - 30, cell - 30), Image.LANCZOS)
        sheet.alpha_composite(icon, (x + 15, y))
        draw.text((x + cell // 2, y + cell - 12), kind, font=font, fill=INK, anchor="mm")
    y += cell + 44
    for i, kind in enumerate(EFFECTS):
        x = pad + i * (cell + pad)
        pid = LIQUIDS[i % len(LIQUIDS)][0]
        sheet.alpha_composite(potion(pid), (x, y))
        badge = Image.open(folders["potion-effects-badge"] / f"{kind}.png").convert("RGBA").resize((cell * 11 // 20, cell * 11 // 20), Image.LANCZOS)
        sheet.alpha_composite(badge, (x + cell - badge.width + 4, y + cell - badge.height + 2))
    sheet.convert("RGB").save(REVIEW / "potions-sheet.png")


if __name__ == "__main__":
    main()
