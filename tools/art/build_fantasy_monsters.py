"""Cut the generated monster sheet using the user-approved scripted workflow."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
from build_fantasy_pawns import cutout, fitted

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT/'art/sources/fantasy_monsters_v1/source/monsters.png'
OUT = ROOT/'assets/fantasy_pawns_v1/monsters'
IDS = ['fire_lizard','frost_spider','water_slime','electric_eel',
       'dcss_rat','dcss_river_rat','dcss_frilled_lizard','dcss_gnoll',
       'dcss_hobgoblin','kobold','slime','beetle']


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    source=Image.open(SOURCE)
    assert source.size==(1448,1086), 'Review crop regions for a changed source'
    records=[]
    review=Image.new('RGB',(768,600),'#394349')
    draw=ImageDraw.Draw(review)
    for i,name in enumerate(IDS):
        x,y=i%4,i//4
        box=(x*362,y*362,(x+1)*362,(y+1)*362)
        sprite=cutout(source,box)
        fraction={'dcss_rat':0.66,'dcss_river_rat':0.78,'beetle':0.72,'kobold':0.76}.get(name,0.86)
        sprite=fitted(sprite,fraction=fraction,bottom=0.94)
        sprite.save(OUT/(name+'.png'))
        records.append({'species_id':name,'source_crop':box,'fraction':fraction,'foot_anchor_ratio':0.94})
        px,py=x*192,y*200
        review.paste(sprite.resize((96,96),Image.Resampling.LANCZOS),(px+48,py+8),
                     sprite.resize((96,96),Image.Resampling.LANCZOS))
        draw.text((px+8,py+111),name,fill='white')
        for n,size in enumerate([24,32,48]):
            small=sprite.resize((size,size),Image.Resampling.LANCZOS)
            review.paste(small,(px+16+n*56,py+142),small)
    preview=ROOT/'docs/art/fantasy-monsters-v1'
    preview.mkdir(parents=True,exist_ok=True)
    review.save(preview/'sprites.png')
    (OUT/'extraction.json').write_text(json.dumps({'source':str(SOURCE.relative_to(ROOT)),
        'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'sprites':records},indent=2)+'\n')
    print('12 monster PNGs and 24/32/48px review saved.')


if __name__=='__main__':main()
