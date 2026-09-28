#!/usr/bin/env python3
"""Lays the rasterised soul stone icons out on one sheet for review:
twelve effects with their names, then the sample stones (one per trigger
colour and the red bleed badge ladder).
    python3 tools/art/soulstone_icon_preview.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import sys
sys.path.insert(0, str(Path(__file__).parent))
from build_soulstone_icons import EFFECTS, SAMPLES, FRAMES, OUT

PNG = OUT / "png"
BG = (32, 29, 34, 255)
font = None
for f in ["/usr/share/fonts/truetype/nanum/NanumGothic.ttf", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
          str(Path(__file__).resolve().parents[2] / "assets/fonts/NanumGothic.ttf")]:
    if Path(f).exists(): font = ImageFont.truetype(f, 18); break
if font is None:
    fonts = list((Path(__file__).resolve().parents[2] / "assets" / "fonts").glob("*.[to]t[fc]"))
    font = ImageFont.truetype(str(fonts[0]), 18) if fonts else ImageFont.load_default()

cell, label = 150, 30
cols = 6
rows_fx = (len(EFFECTS) + cols - 1) // cols
sample_keys = list(SAMPLES)
sheet = Image.new("RGBA", (cols * cell, (rows_fx + 1) * (cell + label) + 40), BG)
draw = ImageDraw.Draw(sheet)
for i, (key, (name, _)) in enumerate(EFFECTS.items()):
    im = Image.open(PNG / "effects" / f"{key}.png").convert("RGBA")
    x, y = (i % cols) * cell + (cell - 128) // 2, (i // cols) * (cell + label) + 8
    sheet.alpha_composite(im, (x, y))
    draw.text(((i % cols) * cell + cell // 2, y + 132), name, fill=(230, 222, 210), font=font, anchor="mt")
y0 = rows_fx * (cell + label) + 30
draw.line((10, y0 - 12, cols * cell - 10, y0 - 12), fill=(80, 74, 86), width=2)
names = {"red_bleed": "빨강·때리면 출혈", "purple_burn": "보라·대기하면 화상", "green_thorns": "초록·맞으면 반사",
         "red_bleed_boost": "출혈 대상 강화", "red_bleed_burst": "출혈 터뜨림"}
for i, key in enumerate(sample_keys):
    im = Image.open(PNG / "samples" / f"{key}.png").convert("RGBA")
    x = i * (cell + 12) + 12
    sheet.alpha_composite(im, (x, y0))
    draw.text((x + 64, y0 + 132), names.get(key, key), fill=(230, 222, 210), font=font, anchor="mt")
out = OUT / "preview.png"
sheet.save(out)
print(out)
