"""Bare paper-doll figures: RimWorld body types in the flat cartoon grammar.

No hats, no weapons, no clothing details: a limbless bell-shaped torso with
shoulders (RimWorld's thin / standard / hulk silhouettes), a
round head set on top, tall pill eyes, one flat shade on the right, a thick
ink outline and a flat ground shadow. Four facings: south (front), east and
west (side, eyes toward the facing), north (back, no face). West is drawn,
not mirrored, so the light still falls from the top-left.

Each SVG keeps `shadow`, `body` and `head` as separate groups so hats,
armour and weapons can be layered on later.

Run: python3 tools/art/build_paperdoll.py
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402

ROOT = flat.ROOT
OUT = ROOT / "assets/paperdoll-v1"
REVIEW = ROOT / "docs/art/paperdoll-v1"
INK = flat.INK
LINE = flat.LINE

# shoulder half-width, hip half-width, belly bulge, torso top, head radius
BODIES = {
    "thin": (10.0, 8.5, 0.5, 31, 10.5),
    "standard": (13.0, 11.0, 1.0, 31, 11.0),
    "hulk": (17.0, 12.0, 1.0, 30, 11.5),
}
FACINGS = ("south", "east", "west", "north")
BOTTOM = 55
SKINS = {"light": ("#f6c79a", "#e0a574"), "tan": ("#d99a6c", "#bf7f52"), "dark": ("#9a6444", "#7e4f34")}
CLOTH = {"grey": ("#8a8f9c", "#707584"), "green": ("#6b8f4e", "#56763d"), "blue": ("#4f6fb5", "#3e5a97"),
         "red": ("#b04a3e", "#903a30"), "brown": ("#8a5a33", "#6f4526")}


def torso(cx: float, top: float, s: float, h: float, b: float) -> str:
    """A RimWorld torso: shoulders at the top, flanks curving to the hips,
    a rounded bottom, and a belly bulge that pushes the flanks out."""
    y1 = top + 7
    return (f"M{cx - s} {y1} Q{cx - s} {top} {cx - s + 8} {top} L{cx + s - 8} {top} Q{cx + s} {top} {cx + s} {y1} "
            f"C{cx + s + 1 + b} {top + 11} {cx + h + 1 + b} {BOTTOM - 8} {cx + h} {BOTTOM - 4} "
            f"Q{cx + h - 1} {BOTTOM} {cx + h - 6} {BOTTOM} L{cx - h + 6} {BOTTOM} Q{cx - h + 1} {BOTTOM} {cx - h} {BOTTOM - 4} "
            f"C{cx - h - 1 - b} {BOTTOM - 8} {cx - s - 1 - b} {top + 11} {cx - s} {y1} Z")


def shaded(uid: str, path: str, fill: str, shade: str, dx: float = 3.2, dy: float = 2.4) -> str:
    """A crescent that follows the form: the shape is filled with the shade,
    then the base colour is laid over it nudged toward the light (up-left),
    so only a curved rim on the lower-right stays dark."""
    return (f'<clipPath id="{uid}"><path d="{path}"/></clipPath>'
            f'<path d="{path}" fill="{shade}"/>'
            f'<path d="{path}" fill="{fill}" transform="translate({-dx} {-dy})" clip-path="url(#{uid}m)"/>'
            f'<clipPath id="{uid}m" transform="translate({dx} {dy})"><path d="{path}"/></clipPath>'
            f'<path d="{path}" fill="none" {LINE}/>')


def figure(body: str, facing: str, skin: str, cloth: str) -> str:
    s, h, b, top, r = BODIES[body]
    skin_fill, skin_shade = SKINS[skin]
    cloth_fill, cloth_shade = CLOTH[cloth]
    side = facing in ("east", "west")
    if side:
        s, h, b = s * 0.72, h * 0.78, b * 0.8
    turn = {"east": 1, "west": -1}.get(facing, 0)
    cx = 32
    uid = f"{body}{facing}{skin}{cloth}"
    body_path = torso(cx, top, s, h, b)
    head_cx = cx + 2.5 * turn
    head_cy = top - r + 4
    circle = (f"M{head_cx - r} {head_cy} A{r} {r} 0 1 0 {head_cx + r} {head_cy} "
              f"A{r} {r} 0 1 0 {head_cx - r} {head_cy} Z")
    head = shaded("h" + uid, circle, skin_fill, skin_shade, 2.6, 2.2)
    if facing == "south":
        head += (f'<rect x="{head_cx - 4.6}" y="{head_cy - 1.5}" width="3.2" height="6.4" rx="1.6" fill="{INK}"/>'
                 f'<rect x="{head_cx + 1.4}" y="{head_cy - 1.5}" width="3.2" height="6.4" rx="1.6" fill="{INK}"/>')
    elif side:
        near, far = head_cx + 0.8 * turn, head_cx + 5.6 * turn
        head += (f'<rect x="{near - 1.6}" y="{head_cy - 1.5}" width="3.2" height="6.4" rx="1.6" fill="{INK}"/>'
                 f'<rect x="{far - 1.3}" y="{head_cy - 1.2}" width="2.6" height="5.8" rx="1.3" fill="{INK}"/>')
    shadow_rx = max(s, h) + 4
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            f'<g id="shadow"><ellipse cx="{cx}" cy="{BOTTOM + 2}" rx="{shadow_rx}" ry="3.6" fill="#000" fill-opacity="0.2"/></g>'
            f'<g id="body">{shaded("b" + uid, body_path, cloth_fill, cloth_shade)}</g>'
            f'<g id="head">{head}</g></svg>')


def main() -> None:
    (OUT / "svg").mkdir(parents=True, exist_ok=True)
    (OUT / "png").mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    jobs = []
    # The base set: every body type and facing in one neutral look.
    for body in BODIES:
        for facing in FACINGS:
            name = f"{body}_{facing}"
            source = OUT / "svg" / f"{name}.svg"
            source.write_text(figure(body, facing, "light", "grey"))
            jobs.append((source, OUT / "png" / f"{name}.png", 2))
    # A few skin and clothing combinations to show the recolour range.
    variants = [("standard", "light", "blue"), ("thin", "tan", "red"), ("hulk", "dark", "brown"),
                ("hulk", "tan", "green"), ("thin", "dark", "blue"), ("standard", "dark", "red")]
    for i, (body, skin, cloth) in enumerate(variants):
        source = OUT / "svg" / f"variant_{i}.svg"
        source.write_text(figure(body, "south", skin, cloth))
        jobs.append((source, OUT / "png" / f"variant_{i}.png", 2))
    flat.rasterise(jobs)

    font = ImageFont.truetype(str(ROOT / "assets/fonts/Jua-Regular.ttf"), 22)
    cell, pad, label = 128, 18, 150
    facings = ("south", "east", "west", "north")
    sheet = Image.new("RGBA", (label + len(facings) * (cell + pad), 60 + len(BODIES) * (cell + pad) + 40 + cell), "#e9a25c")
    draw = ImageDraw.Draw(sheet)
    for c, facing in enumerate(facings):
        draw.text((label + c * (cell + pad) + cell // 2, 22), facing, font=font, fill=INK, anchor="mm")
    for r, body in enumerate(BODIES):
        y = 50 + r * (cell + pad)
        draw.text((16, y + cell // 2), body, font=font, fill=INK, anchor="lm")
        for c, facing in enumerate(facings):
            sheet.alpha_composite(Image.open(OUT / "png" / f"{body}_{facing}.png").convert("RGBA"), (label + c * (cell + pad), y))
    y = 50 + len(BODIES) * (cell + pad) + 20
    draw.text((16, y), "색 변형", font=font, fill=INK, anchor="lm")
    for i in range(len(variants)):
        image = Image.open(OUT / "png" / f"variant_{i}.png").convert("RGBA").resize((cell * 3 // 4, cell * 3 // 4), Image.LANCZOS)
        sheet.alpha_composite(image, (16 + (i % 6) * (cell * 3 // 4 + 20), y + 22 + (i // 6) * (cell * 3 // 4 + 4)))
    sheet.convert("RGB").save(REVIEW / "paperdoll-sheet.png")


if __name__ == "__main__":
    main()
