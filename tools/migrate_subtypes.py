"""Idempotent effect classification; never edits a combat rule.

The table in the role-groups spec is authoritative, including future species.
Gear without an existing build category stays unclassified unless explicitly mapped.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = dict(zip(
    ['방어', '회피', '재생', '반사', '출혈', '분쇄', '급소', '광폭', '저격', '연사', '맹독', '원소', '소환', '사령', '회복', '저주', '강화'],
    ['DEFENSE', 'EVASION', 'REGEN', 'REFLECT', 'BLEED', 'CRUSH', 'VITAL', 'FURY', 'SNIPE', 'VOLLEY', 'VENOM', 'ELEMENT', 'SUMMON', 'DEATH', 'HEAL', 'HEX', 'BOOST']))
LEGACY = {i: v for i, v in enumerate(['BLEED','CRUSH','VITAL','FURY','DEFENSE','SNIPE','ELEMENT','HEX','VENOM','SUMMON','DEATH','HEAL'], 1)}
OVERRIDES = {'UNRAND_SHIELD':'DEFENSE', 'GEAR_FORM_SAW':'BLEED', 'GEAR_FORM_TIP':'VITAL',
             'GEAR_FORM_WEIGHT':'CRUSH', 'GEAR_FORM_EDGE':'BLEED', 'GEAR_COMP_CRISIS':'DEFENSE',
             'GEAR_COMP_SHOVE':'EVASION', 'GEAR_COMP_PETS':'SUMMON', 'GEAR_COMP_OPENING':'BOOST',
             'GEAR_COMP_MELEE':'DEFENSE', 'GEAR_COMP_BLOCK':'REFLECT', 'GEAR_COMP_CLEANSE':'BOOST',
             'GEAR_COMP_MP':'BOOST'}

def migrate(path):
    data = json.loads(path.read_text())
    spec = (ROOT/'docs/superpowers/specs/2026-09-26-role-groups-design.md').read_text()
    part = {id: NAMES[name] for id, name in re.findall(r'\b([A-Z][A-Z_]+) (방어|회피|재생|반사|출혈|분쇄|급소|광폭|저격|연사|맹독|원소|소환|사령|회복|저주|강화)\b', spec)}
    for id, row in data['effects'].items():
        old = row.pop('families', [])
        subtype = part.get(id, OVERRIDES.get(id, row.get('subtype', LEGACY.get(int(old[0]), '') if old else '')))
        if subtype:
            row['subtype'] = subtype
        if old:
            print(id, old, '->', subtype)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')

if __name__ == '__main__':
    migrate(Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'data/content/stone_effects.json')
