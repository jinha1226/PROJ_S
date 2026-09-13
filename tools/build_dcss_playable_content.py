"""Author our existing content schemas from the pinned numerical reference.
No DCSS runtime implementation is copied. Run after build_dcss_balance_catalog.py.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import re

EARLY_WEAPONS = {"club", "whip", "flail", "dagger", "falchion", "long sword", "scimitar", "war axe", "trident", "staff", "quarterstaff", "orcbow"}
VERSION = "dcss-balance-0.34.1-2026-09-13-v1"
UNSAFE = {"unique", "cant_spawn", "stationary", "flies", "insubstantial", "batty", "burrows", "no_exp_gain", "no_reward", "projectile", "maintain_range", "archer", "no_gen_derived", "ghost_demon", "amorphous"}
BLOCKED = {"shapeshifter", "glowing-shapeshifter", "starcursed-mass", "elf", "human", "spriggan", "purple-draconian", "abomination-large"}
BLUNT = {"club", "whip", "flail", "morningstar", "demon whip", "sacred scourge", "dire flail", "eveningstar", "great mace", "giant club", "giant spiked club", "staff", "quarterstaff", "lajatang"}
AXES = {"war axe", "broad axe", "battleaxe", "executioner's axe"}
POLEARMS = {"trident", "halberd", "partisan", "demon trident", "trishula", "glaive", "bardiche"}
RANGED = {"orcbow", "longbow", "triple crossbow"}
TWO_HANDED = {"dire flail", "great mace", "giant club", "giant spiked club", "great sword", "triple sword", "battleaxe", "executioner's axe", "halberd", "glaive", "bardiche", "quarterstaff", "lajatang", "orcbow", "longbow", "triple crossbow"}
WEAPON_LABELS = {"club":"몽둥이","whip":"채찍","flail":"플레일","morningstar":"모닝스타","demon whip":"악마 채찍","sacred scourge":"성스러운 채찍","dire flail":"쌍두 플레일","eveningstar":"이브닝스타","great mace":"대형 철퇴","giant club":"거인 몽둥이","giant spiked club":"거인 가시 몽둥이","dagger":"단도","quick blade":"쾌검","falchion":"팔시온","long sword":"장검","scimitar":"시미터","demon blade":"악마 검","eudemon blade":"성령 검","double sword":"이중검","great sword":"대검","triple sword":"삼중검","war axe":"전투 도끼","broad axe":"넓은날 도끼","battleaxe":"양손 도끼","executioner's axe":"처형자의 도끼","trident":"삼지창","halberd":"할버드","partisan":"파르티잔","demon trident":"악마 삼지창","trishula":"트리슐라","glaive":"글레이브","bardiche":"바디시","staff":"지팡이","quarterstaff":"봉","lajatang":"라자탕","orcbow":"오크 활","longbow":"장궁","triple crossbow":"삼중 쇠뇌"}
MONSTER_LABELS = {"death-yak":"죽음의 야크","frilled-lizard":"목도리 도마뱀","gnoll-sergeant":"놀 부대장","gnoll":"놀","hobgoblin":"홉고블린","iguana":"이구아나","kobold-brigand":"코볼트 강도","komodo-dragon":"코모도 왕도마뱀","lemure":"레무레","merfolk-impaler":"인어 창잡이","merfolk":"인어","ogre":"오우거","orc-warrior":"오크 전사","orc":"오크","rat":"쥐","river-rat":"강쥐","stone-giant":"돌거인","vault-guard":"보고 경비병","yak":"야크"}


def read(root, name):
    return json.loads((root / "data/content" / name).read_text())


def append_rows(root, name, key, rows):
    """Preserve the hand-authored formatting outside the appended array rows."""
    path = root / "data/content" / name
    text = path.read_text()
    data = json.loads(text)
    identity = {"definitions":"weapon_id" if name == "weapons.json" else "definition_id", "non_player_species":"species_id", "tables":"species_id"}[key]
    present = {r[identity] for r in data[key]}
    fresh = [r for r in rows if r[identity] not in present]
    text = re.sub(r'("content_version"\s*:\s*)"[^"]+"', lambda m:m.group(1)+'"'+VERSION+'"', text, count=1)
    if fresh:
        match = re.search(r'"'+re.escape(key)+r'"\s*:\s*(\[)', text)
        if not match:
            raise ValueError(f"Unexpected document layout: {name}")
        first = match.start(1)
        _, consumed = json.JSONDecoder().raw_decode(text[first:])
        last = first + consumed - 1
        encoded = ",\n".join(json.dumps(r, ensure_ascii=False, indent=2) for r in fresh)
        text = text[:last].rstrip() + ",\n" + encoded + "\n  " + text[last:]
    expected = deepcopy(data)
    expected[key].extend(fresh)
    expected["content_version"] = VERSION
    if json.loads(text) != expected:
        raise ValueError(f"Unexpected mutation: {name}")
    path.write_text(text)


def eligible_monster(m):
    r=m["reference"]; attacks=r["attacks"]
    return (r.get("hd",99)<=2 and m["id"] not in BLOCKED and not r.get("spells") and not r.get("resists") and len(attacks)==1
            and attacks[0].get("flavour","plain")=="plain" and not set(r.get("flags",[])) & UNSAFE
            and r.get("speed",10)==10 and r.get("hp_10x",0)>0)


def build(root):
    catalog_path=root/"data/reference/dcss-0.34.1-catalog.json"
    catalog=json.loads(catalog_path.read_text())
    existing=read(root,"weapons.json")
    templates={r['weapon_id']:r for r in existing['definitions']}
    item_template=next(r for r in read(root,"items.json")['definitions'] if r['definition_id']=='WEAPON_SHORT_SWORD')
    new_weapons=[];new_items=[];new_catalog=[]
    for w in catalog['weapons']:
        name=w['name']
        if name.startswith('old ') or name in {'sling','hand cannon'}:
            w['status']='legacy_reference' if name.startswith('old ') else 'reference_only_missing_ammo'
            continue
        if w.get('status')=='adapted_existing':
            continue
        if name not in EARLY_WEAPONS:
            w.pop('game_weapon_id',None);w.pop('adaptation',None)
            w['status']='reference_only_outside_early_scope'
            continue
        family='MACE' if name in BLUNT else 'HAND_AXE' if name in AXES else 'SPEAR' if name in POLEARMS else ('CROSSBOW' if name=='triple crossbow' else 'BOW') if name in RANGED else 'SHORT_SWORD'
        row=deepcopy(templates[family]);wid='DCSS_'+w['id'].removeprefix('WPN_')
        damage=w['reference']['base_damage'];delay=w['reference']['delay_aut']*10
        row.update(weapon_id=wid,label=WEAPON_LABELS.get(name,name),base_damage=max(0,damage*5-24),accuracy_milli=w['reference']['accuracy_bonus']*10,attack_time=max(1,delay-row['reload_time']),two_handed=name in TWO_HANDED,natural_weapon=False)
        new_weapons.append(row)
        item=deepcopy(item_template)
        required=max(4,min(12,(damage+2)//2))
        stat='DEX' if name in {'dagger','quick blade','demon blade','eudemon blade'} or family=='BOW' else 'STR'
        item.update(definition_id='WEAPON_'+wid,label=row['label'],weapon_id=wid,equip_slots=['MAIN_HAND'])
        item['requirements']={'STR':0,'DEX':0,'INT':0};item['requirements'][stat]=required
        if row['two_handed']:item['requirements']['STR']=max(item['requirements']['STR'],6)
        new_items.append(item)
        depth=1 if damage<=8 and name!='quick blade' else 2 if damage<=12 else 3 if damage<=16 else 4
        new_catalog.append({'definition_id':item['definition_id'],'family':'WEAPON','tier':min(3,depth),'min_depth':depth,'buy_price':damage*5+delay//10,'sell_price':max(1,damage*2),'effect_kind':'NONE','effect_power':0})
        w.update(game_weapon_id=wid,status='adapted_registered',adaptation={'neutral_raw_damage':24+row['base_damage'],'delay_with_reload':row['attack_time']+row['reload_time'],'family_proxy':family,'requirements':item['requirements'],'min_depth':depth})
    monsters=[];species=[];drops=[]
    body=next(r for r in read(root,'species_catalog.json')['non_player_species'] if r['species_id']=='generic_humanoid')['body']
    for m in catalog['monsters']:
        if m['id'] in {'goblin','kobold'}:
            continue
        if not eligible_monster(m):
            m['status']='reference_only_outside_early_scope' if m['reference'].get('hd',99)>2 else 'reference_only_special_behavior'
            m.pop('game_species_id',None);m.pop('adaptation',None)
            continue
        r=m['reference'];sid='dcss_'+m['id'].replace('-','_');wid='DCSS_NATURAL_'+m['id'].replace('-','_').upper();pid='dcss-'+m['id']+'-v1'
        armed=r.get('uses')=='weapons_armour';damage=r['attacks'][0]['damage']*5
        attack=deepcopy(templates['UNARMED_STRIKE'])
        attack.update(weapon_id=wid,label='기본 공격',base_damage=max(0,damage-1),attack_time=100,accuracy_milli=0,natural_weapon=True,scaling={'STR':'NONE','DEX':'NONE','INT':'NONE'})
        new_weapons.append(attack)
        species.append({'species_id':sid,'label':MONSTER_LABELS.get(m['id'],m['name']),'base_stats':{'STR':5,'DEX':5,'INT':5},'natural_weapon_id':wid,'body':deepcopy(body)})
        profile={'profile_id':pid,'accuracy_milli':min(600,220+r['hd']*20),'evasion_milli':min(700,r['ev']*10),'power':24+damage if armed else 1,'armor_flat':r['ac']*2,'bleed_proc_milli':100,'bleed_resist_milli':0}
        monsters.append({'species_id':sid,'reference_id':m['id'],'display_name':MONSTER_LABELS.get(m['id'],m['name']),'glyph':'o' if armed else 'm','sight_range':6,'perception':500,'max_health':r['hp_10x'],'entity_kind':'melee_enemy','combat_profile':profile,'hd':r['hd'],'loadout_id':'DCSS_MONSTER_CLUB_V1' if armed else '', 'body_proxy':'generic_humanoid','default_attack_time':100})
        drops.append({'species_id':sid,'rolls':[],'reward_rows':[]})
        m.update(game_species_id=sid,status='adapted_registered',adaptation={'body_proxy':'generic_humanoid','equipped_weapon':'DCSS_CLUB' if armed else wid,'spawn_hd':r['hd']})
    append_rows(root,'weapons.json','definitions',new_weapons)
    append_rows(root,'items.json','definitions',new_items)
    append_rows(root,'item_catalog.json','definitions',new_catalog)
    append_rows(root,'species_catalog.json','non_player_species',species)
    # Drop tables and loadouts enforce globally sorted IDs.
    path=root/'data/content/species_drop_tables.json';data=json.loads(path.read_text());present={r['species_id'] for r in data['tables']}
    data['tables'].extend(r for r in drops if r['species_id'] not in present);data['tables'].sort(key=lambda r:r['species_id']);data['content_version']=VERSION;path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    path=root/'data/content/actor_loadouts.json';data=json.loads(path.read_text())
    if not any(r['loadout_id']=='DCSS_MONSTER_CLUB_V1' for r in data['loadouts']):data['loadouts'].append({'loadout_id':'DCSS_MONSTER_CLUB_V1','items':[{'entry_id':'MAIN_WEAPON','definition_id':'WEAPON_DCSS_CLUB','quantity':1,'equip_slot':'MAIN_HAND'}]})
    data['loadouts'].sort(key=lambda r:r['loadout_id']);data['content_version']=VERSION;path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    (root/'data/content/dcss_enemies.json').write_text(json.dumps({'content_schema_version':1,'content_version':VERSION,'content_type':'DCSS_ENEMIES','definitions':monsters},ensure_ascii=False,indent=2)+'\n')
    catalog['runtime_enabled']=False
    catalog['adapted_counts']={'dcss_weapon_types':sum(w['status'] in {'adapted_existing','adapted_registered'} for w in catalog['weapons']),'registered_new_weapon_types':sum(w['status']=='adapted_registered' for w in catalog['weapons']),'dcss_monster_types':len(monsters)+2,'registered_new_monster_types':len(monsters)}
    catalog_path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(catalog['adapted_counts']))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path('.'));args=parser.parse_args();build(args.root.resolve())
