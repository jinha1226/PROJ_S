"""Extract transparent worn layers; keep drawings and species bases unchanged."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
from build_fantasy_items_v2 import transparent_source

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/sources/fantasy_equipment_materials_v1'
DEST = ROOT / 'assets/fantasy_pawns_v1/equipment'

def main():
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    for entry in manifest['assets']:
        image = transparent_source(Image.open(SOURCE / (entry['id']+'.png')), entry)
        bounds = image.getchannel('A').point(lambda v: 255 if v >= 32 else 0).getbbox()
        image = image.crop(bounds)
        image.thumbnail((256,256), Image.Resampling.LANCZOS)
        image.save(DEST / (entry['id']+'.png'))
    board = Image.new('RGB', (850,350), '#303941')
    draw = ImageDraw.Draw(board)
    for col, name in enumerate(['cloth','leather','padded','chain','plate']):
        draw.text((col*170+16,10),name.upper(),fill='white')
        for row, part in enumerate(['helmet','armor']):
            filename = name+'_'+part
            if filename == 'leather_armor': filename = 'leather'
            if filename == 'plate_helmet': filename = 'iron_helmet'
            image = Image.open(DEST / (filename+'.png')).convert('RGBA')
            image.thumbnail((140,140),Image.Resampling.LANCZOS)
            board.paste(image,(col*170+(170-image.width)//2,35+row*150),image)
    board.save(ROOT / 'docs/art/equipment-overlays/material-assets.png')

if __name__ == '__main__':
    main()
