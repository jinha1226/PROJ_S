#!/usr/bin/env python3
"""Reproduce a static inventory and commit-pinned source ledger; not a gameplay test."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

import yaml

EXPECTED = '2bd8e06e6e5614a6f4917c1c24e04a8922319476'
# Exact anchors are resolved against the pinned checkout, rather than guessed.
SOURCES = [
 ('S01','dungeon.cc','bool builder(bool','생성 재시도·branch RNG'),
 ('S02','dungeon.cc','static void _build_dungeon_level()\n{','생성 파이프라인'),
 ('S03','dungeon.cc','static bool _builder_normal()\n{','primary vault/layout 선택'),
 ('S04','branch-data.h','const Branch branches','branch 깊이·입구·규칙'),
 ('S05','branch.cc','vector<branch_type> random_choose_disabled_branches()','분기 교체'),
 ('S06','mapdef.h','class map_def\n','vault 데이터 구조'),
 ('S07','dat/des/builder/layout_loops.des','function randomLow','절차적 loop layout'),
 ('S08','dat/des/builder/layout.des','function spotty_stairs','layout·계단 연결'),
 ('S09','dat/des/arrival/simple.des','NAME:   minmay_arrival_doors','입구 vault 데이터'),
 ('S10','dungeon.cc','static void _builder_monsters()\n{','D:1 배치 보호'),
 ('S11','dungeon.cc','static void _builder_items()\n{','바닥 아이템 생성'),
 ('S12','traps.cc','void roll_trap_effects()','탐험 함정'),
 ('S13','traps.cc','dungeon_feature_type random_trap_for_place','branch별 바닥 함정'),
 ('S14','stairs.cc','static void _rune_effect','룬·층 이동'),
 ('S15','travel.cc','#define ES_item','자동 탐험 중단 대상'),
 ('S16','dungeon-feature-type.h','enum dungeon_feature_type','terrain/feature enum'),
 ('S17','mon-util.h','struct monsterentry','몬스터 정의 구조'),
 ('S18','dat/mons/adder.yaml','name:','adder 데이터'),
 ('S19','dat/mons/hydra.yaml','name:','hydra 데이터'),
 ('S20','dat/mons/orc-priest.yaml','name:','orc priest 데이터'),
 ('S21','dat/mons/guardian-serpent.yaml','name:','guardian serpent 데이터'),
 ('S22','dat/mons/boulder-beetle.yaml','name:','boulder beetle 데이터'),
 ('S23','dat/mons/slime-creature.yaml','name:','slime creature 데이터'),
 ('S24','mon-spell.h','{  MST_ORC_PRIEST,','priest 주문 묶음'),
 ('S25','mon-spell.h','{  MST_GUARDIAN_SERPENT,','포위 주문 묶음'),
 ('S26','mon-place.cc','{ MONS_ORC,','band 생성'),
 ('S27','mon-act.cc','static void _monster_add_energy','행동 시간'),
 ('S28','mon-behv.cc','void behaviour_event','행동 상태'),
 ('S29','mon-pick-data.h','{ // Dungeon','깊이별 population'),
 ('S30','dat/des/builder/uniques.des','NAME:   uniq_sigmund','unique 배치'),
 ('S31','melee-attack.cc','bool melee_attack::consider_decapitation','히드라 절단·재생'),
 ('S32','mon-abil.cc','static bool _slime_split_merge(monster* thing)\n{','슬라임 합체'),
 ('S33','item-def.h','struct item_def','아이템 구조'),
 ('S34','item-prop.cc','struct weapon_def','무기·brand 가중치'),
 ('S35','item-prop.cc','struct armour_def','갑옷·ego 데이터'),
 ('S36','makeitem.cc','int items(','랜덤 아이템 생성'),
 ('S37','artefact.cc','int artefact_property(','artefact 속성'),
 ('S38','items.cc','static bool _id_floor_item','장비·wand 자동 식별'),
 ('S39','acquire.cc','int acquirement_create_item(','획득 선택 생성'),
 ('S40','xp-evoker-data.h','struct evoker_data','XP 재충전 evoker'),
 ('S41','skills.cc','void reset_training()','훈련 분배'),
 ('S42','skills.cc','bool is_removed_skill','폐기 skill'),
 ('S43','skills.cc','float apt_to_factor','적성 비용'),
 ('S44','skill-type.h','enum skill_type','skill 목록'),
 ('S45','spl-util.cc','struct spell_desc','주문 구조'),
 ('S46','spl-data.h','static const struct spell_desc spelldata','주문 정의'),
 ('S47','spl-cast.cc','int raw_spell_fail','실패율'),
 ('S48','spl-cast.cc','int calc_spell_power','마법 위력'),
 ('S49','spl-util.cc','int spell_mana','MP 비용'),
 ('S50','spl-book.cc','bool is_player_book_spell','학습 가능한 주문 판별'),
 ('S51','book-data.h','static const vector<spell_type> spellbook_templates','마법서 내용'),
 ('S52','fight.cc','bool weapon_uses_strength','Str/Dex 피해 역할'),
 ('S53','player-act.cc','random_var player::attack_delay_with','공격 시간'),
 ('S54','player.cc','static int _player_evasion(','EV 계산'),
 ('S55','player.cc','int player::adjusted_body_armour_penalty','ER·Str·Armour'),
 ('S56','player.cc','int player_armour_shield_spell_penalty','갑옷과 마법'),
 ('S57','dat/species/formicid.yaml','enum:','Formicid'),
 ('S58','dat/species/octopode.yaml','enum:','Octopode'),
 ('S59','dat/species/coglin.yaml','enum:','Coglin'),
 ('S60','dat/species/djinni.yaml','enum:','Djinni'),
 ('S61','dat/species/gnoll.yaml','enum:','Gnoll'),
 ('S62','dat/species/mountain-dwarf.yaml','enum:','Mountain Dwarf'),
 ('S63','dat/species/gale-centaur.yaml','enum:','Gale Centaur'),
 ('S64','dat/species/poltergeist.yaml','enum:','Poltergeist'),
 ('S65','god-type.h','enum god_type','신 목록'),
 ('S66','religion.cc','void join_religion','입교'),
 ('S67','religion.cc','void excommunication','배교'),
 ('S68','god-conduct.cc','// GOD_TROG,','금기'),
 ('S69','god-passive.cc','static const vector<god_passive> god_passives','신별 passive'),
 ('S70','god-abil.cc','bool ashenzari_curse_item','장비 저주'),
 ('S71','god-abil.cc','bool ashenzari_uncurse_item','저주 해제 비용'),
 ('S72','god-wrath.cc','divine_retribution','신벌'),
 ('S73','religion.cc','bool do_god_gift','신의 선물'),
 ('S74','defines.h','#define LOS_RADIUS','기본/최대 시야'),
 ('S75','mon-act.cc','static void _maybe_launch_opportunity_attack','추격 기회공격'),
 ('S76','dat/clua/autofight.lua','AUTOFIGHT_STOP','기존 자동 공격'),
 ('S77','zot.cc','bool zot_clock_active','행동 시간 제한'),
 ('S78','transformation.h','enum class transformation','변신 상태'),
 ('S79','dat/species/human.yaml','enum:','Human 탐험 재생'),
 ('S80','dat/species/spriggan.yaml','enum:','Spriggan'),
 ('S81','dat/species/revenant.yaml','enum:','Revenant'),
 ('S82','dat/species/draconian-base.yaml','enum:','Draconian 기본형'),
 ('S83','dat/mons/death-yak.yaml','name:','death yak'),
 ('S84','dat/mons/sigmund.yaml','name:','Sigmund'),
 ('S85','item-prop.cc','static map<potion_type, item_rarity_type>','소모품 희귀도'),
 ('S86','spl-util.cc','bool spell_removed','제거된 주문 필터'),
 ('S87','mon-cast.cc','bool handle_mon_spell','몬스터 주문 실행'),
 ('S88','shout.cc','void noisy','소음 전달'),
 ('S89','quiver.cc','namespace quiver','기존 준비 행동'),
 ('S90','dat/species/felid.yaml','enum:','Felid'),
 ('S91','spl-damage.cc','static int _ignite_poison_clouds','독성 cloud→불'),
 ('S92','spl-damage.cc','spret cast_grave_claw','Grave Claw 충전 소비'),
 ('S93','spl-other.cc','spret cast_passwall','벽 통과 지연과 방어'),
 ('S94','spl-transloc.cc','spret cast_blink','무작위 blink와 cooldown'),
 ('S95','movement.cc','void remove_ice_movement()','이동과 위치 방어 마법'),
 ('S96','mon-place.cc','static int _ood_fuzzspan','D:1 OOD 제한'),
 ('S97','mon-death.cc','if (drop_items)\n','몬스터 사망 시 물품 처리'),
 ('S98','acquire.cc','bool acquirement_menu()','acquirement 선택'),
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('checkout', type=Path)
    ap.add_argument('--output', type=Path, default=Path('evidence'))
    args = ap.parse_args()
    root = args.checkout.resolve()
    sha = subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'], text=True).strip()
    if sha != EXPECTED:
        raise SystemExit(f'Expected {EXPECTED}, got {sha}; use a pinned checkout')
    src = root / 'crawl-ref/source'
    records = []
    for sid, rel, anchor, meaning in SOURCES:
        p = src / rel
        content = p.read_text()
        if anchor not in content:
            raise SystemExit(f'Missing source anchor: {sid} {rel} {anchor!r}')
        line = content[:content.index(anchor)].count('\n') + 1
        records.append(dict(id=sid, path='crawl-ref/source/'+rel, line=line,
                            symbol=anchor, meaning=meaning,
                            sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                            url=f'https://github.com/crawl/crawl/blob/{sha}/crawl-ref/source/{rel}#L{line}'))
    species = []
    for p in sorted((src/'dat/species').glob('*.yaml')):
        data = yaml.safe_load(p.read_text())
        if data.get('difficulty') in ('Simple','Intermediate','Advanced'):
            species.append(dict(name=data['name'],file=p.name,aptitudes=data.get('aptitudes',{}),
                                mutations=data.get('mutations',{})))
    # This is deliberately a static-reference count, NOT a runtime spell count.
    util = (src/'spl-util.cc').read_text()
    rem = util.split('set<spell_type> removed_spells',1)[1].split('};',1)[0]
    removed = set(re.findall(r'SPELL_[A-Z_]+',rem))
    refs = set(re.findall(r'SPELL_[A-Z_]+',(src/'book-data.h').read_text())) - removed
    skill_text = (src/'skill-type.h').read_text().split('NUM_SKILLS',1)[0]
    # Enumerated standalone entries only; exclude aliases such as SK_FIRST_SKILL.
    skill_ids = set(re.findall(r'^\s*(SK_[A-Z_]+),',skill_text,re.M))
    removed_skill_text = (src/'skills.cc').read_text().split('bool is_removed_skill',1)[1].split('skill_type random_skill',1)[0]
    removed_skill_ids = set(re.findall(r'case (SK_[A-Z_]+):',removed_skill_text))
    active_skills = sorted(skill_ids - removed_skill_ids)
    god_text = (src/'god-type.h').read_text().split('NUM_GODS',1)[0]
    god_ids = sorted(set(re.findall(r'^\s*(GOD_[A-Z_]+),',god_text,re.M)) - {'GOD_PAKELLAS'})
    inventory = dict(commit=sha, species_selection_entries=len(species), species=species,
        active_skill_count=len(active_skills), active_skills=active_skills,
        god_count_excluding_no_god_and_pakellas=len(god_ids), gods=god_ids,
        monster_yaml_files=len(list((src/'dat/mons').glob('*.yaml'))),
        monster_count_warning='Includes tests, variants, nonspawning entities; not encounter species count.',
        book_spell_static_references_excluding_removed=len(refs), book_spell_references=sorted(refs),
        spell_count_warning='Static enum references, not preprocessed book_exists/runtime availability.',
        method='Static source inspection. No DCSS binary, game simulation, or player timing study was run.')
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'source-ledger.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    (args.output/'inventory.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2)+'\n')
    lines=['# 고정 소스 근거 목록','',f'분석 commit: `{sha}`. 모든 링크는 이 commit에 고정된다.','',
           '| ID | 코드·데이터 | 확인한 구조 |','|---|---|---|']
    lines += [f"| {r['id']} | [{r['path']}:{r['line']}]({r['url']}) | {r['meaning']} |" for r in records]
    (args.output/'sources.md').write_text('\n'.join(lines)+'\n')
    defs='\n'.join(f"[{r['id']}]: {r['url']}" for r in records)+'\n'
    (args.output/'references.txt').write_text(defs)
    print(json.dumps(dict(commit=sha,source_anchors=len(records),species=len(species),
                         skills=len(active_skills),gods=len(god_ids),
                         monster_yaml=inventory['monster_yaml_files'],book_spell_refs=len(refs)),indent=2))

if __name__ == '__main__':
    main()
