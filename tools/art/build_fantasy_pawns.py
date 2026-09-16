"""Extract approved generated art non-destructively. Python 3 + Pillow/NumPy/SciPy.

User authorized scripted background removal/cropping on 2026-09-16.
Dark, closed outlines separate foreground from the baked checkerboard. Only
explicitly seeded enclosed checkerboard holes (bow/ring) are removed inside.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/sources/fantasy_pawns_v1'
OUT = ROOT / 'assets/fantasy_pawns_v1'
LANCZOS = Image.Resampling.LANCZOS


def cutout(image, box, hole_seeds=()):
    rgb = np.asarray(image.crop(box).convert('RGB'))
    dark = rgb.max(axis=2) < 115
    outline = dark
    filled = ndi.binary_fill_holes(outline)
    labels, _ = ndi.label(filled)
    counts = np.bincount(labels.ravel()); counts[0] = 0
    mask = labels == counts.argmax()
    for x, y in hole_seeds:
        seed = np.zeros(mask.shape, dtype=bool)
        seed[y - box[1], x - box[0]] = True
        hole = ndi.binary_propagation(seed, mask=~outline)
        assert not hole[0].any() and not hole[-1].any(), 'Hole escaped outline'
        mask &= ~hole
    rgba = np.dstack([rgb, mask.astype(np.uint8) * 255])
    rgba[~mask, :3] = 0
    result = Image.fromarray(rgba)
    assert result.getbbox() is not None
    return result.crop(result.getbbox())


def fitted(image, size=128, fraction=0.86, bottom=None):
    scale = size * fraction / max(image.size)
    image = image.resize(tuple(max(1, round(v * scale)) for v in image.size), LANCZOS)
    canvas = Image.new('RGBA', (size, size))
    y = round(size * bottom) - image.height if bottom is not None else (size-image.height)//2
    canvas.alpha_composite(image, ((size-image.width)//2, y))
    return canvas


def main():
    for folder in ['species', 'items', 'tiles', 'walls']:
        (OUT/folder).mkdir(parents=True, exist_ok=True)
    manifest = json.loads((SOURCE/'manifest.json').read_text())
    records = []
    for sheet in manifest['sheets']:
        original = Image.open(SOURCE/sheet['file'])
        assert hashlib.sha256((SOURCE/sheet['file']).read_bytes()).hexdigest() == sheet['sha256']
        for entry in sheet['entries']:
            name, col, row = entry['id'], entry['column'], entry['row']
            if sheet['id'] == 'species':
                box = (col*418, row*627, (col+1)*418, (row+1)*627)
                sprite = cutout(original, box)
                fraction = {'dwarf':0.78, 'goblin':0.70}.get(name, 0.86)
                output = fitted(sprite, fraction=fraction, bottom=0.94)
            elif sheet['id'] == 'items':
                xs, ys = [0,315,630,945,1261], [0,345,633,936,1247]
                box = (xs[col],ys[row],xs[col+1],ys[row+1])
                holes = {'bow':[(812,180)], 'ring':[(1123,514)]}.get(name, [])
                output = fitted(cutout(original, box, holes))
            else:
                # Exclude the generated sheet's black separator frame.
                box = (round(col*original.width/4)+7, round(row*original.height/4)+7,
                       round((col+1)*original.width/4)-7, round((row+1)*original.height/4)-7)
                output = original.crop(box).convert('RGBA').resize((64,64), LANCZOS)
            path = OUT/sheet['id']/(name+'.png')
            output.save(path)
            records.append({'file':str(path.relative_to(OUT)), 'source':sheet['file'],
                            'crop':box, 'size':output.size})

    # Reuse the generated stone cap and face. Join cap surfaces across walls;
    # expose the shaded front only at a known south floor boundary. Never rotate
    # a shaded face. N/E/S/W floor-neighbor bits = 1/2/4/8.
    sheet = Image.open(SOURCE/'tiles.png').convert('RGBA')
    # One stone's interior avoids squeezing three mortar seams into every cell.
    cap = sheet.crop((105,328,200,388)).resize((64,64),LANCZOS)
    face = sheet.crop((8,408,305,494)).resize((64,16),LANCZOS)
    for bits in range(16):
        tile = cap.copy()
        draw = ImageDraw.Draw(tile)
        if bits & 4:
            tile.paste(face,(0,48)); draw.line((0,48,63,48),fill='#252b2c',width=2)
            draw.line((0,63,63,63),fill='#252b2c',width=2)
        if bits & 1: draw.line((0,0,63,0),fill='#252b2c',width=2)
        if bits & 2: draw.line((63,0,63,63),fill='#252b2c',width=2)
        if bits & 8: draw.line((0,0,0,63),fill='#252b2c',width=2)
        tile.save(OUT/'walls'/f'wall_{bits:02d}.png')
    # Vertical doorway derives from the same approved image; preserve upright
    # perspective rather than rotating the whole tile (and its shading).
    for state in ['closed','open']:
        floor = Image.open(OUT/'tiles/stone_floor_a.png')
        door = Image.open(OUT/'tiles'/f'door_{state}.png')
        floor.alpha_composite(door.resize((32,64),LANCZOS),(16,0))
        floor.save(OUT/'tiles'/f'door_{state}_vertical.png')
    (OUT/'extraction.json').write_text(json.dumps({'sources':manifest['sheets'],
        'outputs':records,'wall_neighbor_bits':{'N':1,'E':2,'S':4,'W':8}},indent=2)+'\n')

    # Review actual exported sprites against a dark game background.
    review = Image.new('RGB',(768,480),'#394349')
    draw = ImageDraw.Draw(review)
    for i,path in enumerate(sorted((OUT/'species').glob('*.png'))+sorted((OUT/'items').glob('*.png'))):
        x,y=(i%8)*96,(i//8)*130
        sprite=Image.open(path).resize((80,80),LANCZOS)
        review.paste(sprite,(x+8,y+8),sprite)
        draw.text((x+3,y+92),path.stem,fill='white')
    review.save(OUT/'cutout-review.png')
    print('Extracted 6 species + 16 items + 18 tiles + 16 connected wall variants.')


if __name__ == '__main__':
    main()
