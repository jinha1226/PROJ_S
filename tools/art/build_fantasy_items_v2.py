"""Normalize generated transparent item icons without repainting their contents."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/sources/fantasy_items_v2'
OUT = ROOT / 'assets/fantasy_pawns_v1/items'

def transparent_source(image, entry):
    image = image.convert('RGBA')
    if image.getchannel('A').getextrema() == (0, 255):
        return image
    # Some reference edits bake a checkerboard despite requesting alpha.
    # User-authorized background removal: retain the closed dark silhouette;
    # explicitly remove only seeded enclosed background holes, never gray steel.
    import numpy as np
    from scipy import ndimage as ndi
    rgb = np.asarray(image.convert('RGB'))
    outline = rgb.max(axis=2) < entry.get('outline_threshold', 80)
    filled = ndi.binary_fill_holes(outline)
    labels, _ = ndi.label(filled)
    counts = np.bincount(labels.ravel()); counts[0] = 0
    mask = labels == counts.argmax()
    for x, y in entry.get('hole_seeds', []):
        assert not outline[y, x], 'Hole seed landed on item outline'
        seed = np.zeros(mask.shape, dtype=bool); seed[y, x] = True
        hole = ndi.binary_propagation(seed, mask=~outline)
        assert not hole[0].any() and not hole[-1].any(), 'Hole escaped outline'
        mask &= ~hole
    rgba = np.dstack([rgb, mask.astype('uint8')*255])
    rgba[~mask, :3] = 0
    return Image.fromarray(rgba)


def main():
    manifest = json.loads((SOURCE / 'manifest.json').read_text())
    preview = Image.new('RGB', (480, 220), '#303941')
    draw = ImageDraw.Draw(preview)
    draw.text((8, 5), 'EXISTING STYLE REFERENCES', fill='#eee6d5')
    for index, name in enumerate(['bow', 'axe', 'sword', 'staff', 'potion', 'potion']):
        reference = Image.open(OUT / (name+'.png')).convert('RGBA').resize((64, 64), Image.Resampling.LANCZOS)
        preview.paste(reference, (index*80+8, 23), reference)
        draw.text((index*80+3, 88), name, fill='#eee6d5')
    draw.text((8, 111), 'REDRAWN ITEMS', fill='#eee6d5')
    for index, entry in enumerate(manifest['items']):
        image = transparent_source(Image.open(SOURCE / entry['file']), entry)
        assert image.getchannel('A').getextrema() == (0, 255), 'Expected real transparency'
        # Ignore near-invisible alpha specks when centering/scaling the silhouette.
        bounds = image.getchannel('A').point(lambda a: 255 if a >= 32 else 0).getbbox()
        assert bounds is not None
        image = image.crop(bounds)
        image.thumbnail((110, 110), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', (128, 128))
        canvas.alpha_composite(image, ((128-image.width)//2, (128-image.height)//2))
        canvas.save(OUT / (entry['id']+'.png'))
        x, y = (index % 6) * 80, 130 + (index // 6) * 90
        small = canvas.resize((64, 64), Image.Resampling.LANCZOS)
        preview.paste(small, (x+8, y), small)
        draw.text((x+3, y+65), entry['id'], fill='#eee6d5')
    preview.save(ROOT / 'docs/art/fantasy-items-v2/icons.png')

if __name__ == '__main__':
    main()
