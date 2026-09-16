"""Normalize generated transparent item icons without repainting their contents."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/sources/fantasy_items_v2'
OUT = ROOT / 'assets/fantasy_pawns_v1/items'

def main():
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    preview = Image.new('RGB', (480, 180), '#303941')
    draw = ImageDraw.Draw(preview)
    for index, entry in enumerate(manifest['items']):
        image = Image.open(SOURCE / entry['file']).convert('RGBA')
        assert image.getchannel('A').getextrema() == (0, 255), 'Expected real transparency'
        image = image.crop(image.getbbox())
        image.thumbnail((110, 110), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (128, 128))
        canvas.alpha_composite(image, ((128-image.width)//2, (128-image.height)//2))
        canvas.save(OUT / (entry['id']+'.png'))
        x, y = (index % 6) * 80, (index // 6) * 90
        small = canvas.resize((64, 64), Image.Resampling.LANCZOS)
        preview.paste(small, (x+8, y), small)
        draw.text((x+3, y+65), entry['id'], fill='#eee6d5')
    preview.save(ROOT / 'docs/art/fantasy-items-v2/icons.png')

if __name__ == '__main__':
    main()
