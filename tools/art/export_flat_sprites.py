"""Export the flat cartoon sprites as a game-ready set.

Every sprite is rasterised straight from its SVG at 1x, 2x and 3x (48, 96
and 144 px), never resized from another PNG. Figures come in both facings:
`_r` looks right like the hero on the lane, `_l` looks left like the mob.
A review sheet shows every sprite at 2x on a checkerboard so the
transparent edges are visible.

Run: python3 tools/art/export_flat_sprites.py
(after build_flat_cartoon.py and build_forge_layout.py)
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_flat_cartoon as flat  # noqa: E402
import build_forge_layout as layout  # noqa: E402

OUT = flat.OUT / "sprites"
REVIEW = flat.REVIEW
SCALES = {"1x": 0.75, "2x": 1.5, "3x": 2.25}
GROUPS = {
    "character": flat.SPRITES,
    "prop": flat.PROPS,
    "item": {k: layout.EXTRA[k] for k in ("sword", "helmet", "armor", "shield", "ring", "boots")},
    "icon": {**flat.ICONS, **{k: layout.EXTRA[k] for k in ("crown", "gem", "plus")}},
    "scenery": {k: layout.EXTRA[k] for k in ("tree", "rock", "bones", "pillar")},
}


def main() -> None:
    jobs = []
    for group, sprites in GROUPS.items():
        for name, body in sprites.items():
            source = flat.OUT / "svg" / f"{name}.svg"
            source.write_text(flat.svg(body))
            for tag, scale in SCALES.items():
                folder = OUT / tag / group
                folder.mkdir(parents=True, exist_ok=True)
                jobs.append((source, folder / f"{name}.png", scale))
    flat.rasterise(jobs)

    # Figures also face left: the mob looks back at the hero.
    for tag in SCALES:
        for name in flat.SPRITES:
            right = OUT / tag / "character" / f"{name}.png"
            image = Image.open(right)
            image.save(right.with_name(f"{name}_r.png"))
            image.transpose(Image.FLIP_LEFT_RIGHT).save(right.with_name(f"{name}_l.png"))
            right.unlink()

    font = ImageFont.truetype(str(layout.JUA), 18)
    cell, pad = 96, 14
    rows = []
    for group in GROUPS:
        files = sorted((OUT / "2x" / group).glob("*.png"))
        rows.append((group, files))
    columns = max(len(files) for _, files in rows)
    sheet_w = pad + columns * (cell + pad)
    sheet_h = pad + len(rows) * (cell + 30 + pad)
    sheet = Image.new("RGBA", (sheet_w, sheet_h), "#ffffff")
    draw = ImageDraw.Draw(sheet)
    for r, (group, files) in enumerate(rows):
        y = pad + r * (cell + 30 + pad)
        for c, path in enumerate(files):
            x = pad + c * (cell + pad)
            for cy in range(0, cell, 12):
                for cx in range(0, cell, 12):
                    if (cx + cy) // 12 % 2 == 0:
                        draw.rectangle((x + cx, y + cy, x + cx + 11, y + cy + 11), fill="#e6e8ee")
            image = Image.open(path).convert("RGBA")
            sheet.alpha_composite(image, (x, y))
            draw.text((x + cell // 2, y + cell + 4), path.stem, font=font, fill=flat.INK, anchor="ma")
    sheet.convert("RGB").save(REVIEW / "sprites-2x.png")


if __name__ == "__main__":
    main()
