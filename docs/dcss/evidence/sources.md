# 고정 소스 근거 목록

분석 commit: `2bd8e06e6e5614a6f4917c1c24e04a8922319476`. 모든 링크는 이 commit에 고정된다.

| ID | 코드·데이터 | 확인한 구조 |
|---|---|---|
| S01 | [crawl-ref/source/dungeon.cc:247](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dungeon.cc#L247) | 생성 재시도·branch RNG |
| S02 | [crawl-ref/source/dungeon.cc:2868](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dungeon.cc#L2868) | 생성 파이프라인 |
| S03 | [crawl-ref/source/dungeon.cc:3666](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dungeon.cc#L3666) | primary vault/layout 선택 |
| S04 | [crawl-ref/source/branch-data.h:7](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/branch-data.h#L7) | branch 깊이·입구·규칙 |
| S05 | [crawl-ref/source/branch.cc:170](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/branch.cc#L170) | 분기 교체 |
| S06 | [crawl-ref/source/mapdef.h:1099](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mapdef.h#L1099) | vault 데이터 구조 |
| S07 | [crawl-ref/source/dat/des/builder/layout_loops.des:27](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/des/builder/layout_loops.des#L27) | 절차적 loop layout |
| S08 | [crawl-ref/source/dat/des/builder/layout.des:28](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/des/builder/layout.des#L28) | layout·계단 연결 |
| S09 | [crawl-ref/source/dat/des/arrival/simple.des:9](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/des/arrival/simple.des#L9) | 입구 vault 데이터 |
| S10 | [crawl-ref/source/dungeon.cc:4391](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dungeon.cc#L4391) | D:1 배치 보호 |
| S11 | [crawl-ref/source/dungeon.cc:4486](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dungeon.cc#L4486) | 바닥 아이템 생성 |
| S12 | [crawl-ref/source/traps.cc:745](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/traps.cc#L745) | 탐험 함정 |
| S13 | [crawl-ref/source/traps.cc:921](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/traps.cc#L921) | branch별 바닥 함정 |
| S14 | [crawl-ref/source/stairs.cc:415](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/stairs.cc#L415) | 룬·층 이동 |
| S15 | [crawl-ref/source/travel.cc:599](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/travel.cc#L599) | 자동 탐험 중단 대상 |
| S16 | [crawl-ref/source/dungeon-feature-type.h:14](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dungeon-feature-type.h#L14) | terrain/feature enum |
| S17 | [crawl-ref/source/mon-util.h:133](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-util.h#L133) | 몬스터 정의 구조 |
| S18 | [crawl-ref/source/dat/mons/adder.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/adder.yaml#L1) | adder 데이터 |
| S19 | [crawl-ref/source/dat/mons/hydra.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/hydra.yaml#L1) | hydra 데이터 |
| S20 | [crawl-ref/source/dat/mons/orc-priest.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/orc-priest.yaml#L1) | orc priest 데이터 |
| S21 | [crawl-ref/source/dat/mons/guardian-serpent.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/guardian-serpent.yaml#L1) | guardian serpent 데이터 |
| S22 | [crawl-ref/source/dat/mons/boulder-beetle.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/boulder-beetle.yaml#L1) | boulder beetle 데이터 |
| S23 | [crawl-ref/source/dat/mons/slime-creature.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/slime-creature.yaml#L1) | slime creature 데이터 |
| S24 | [crawl-ref/source/mon-spell.h:424](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-spell.h#L424) | priest 주문 묶음 |
| S25 | [crawl-ref/source/mon-spell.h:1526](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-spell.h#L1526) | 포위 주문 묶음 |
| S26 | [crawl-ref/source/mon-place.cc:1860](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-place.cc#L1860) | band 생성 |
| S27 | [crawl-ref/source/mon-act.cc:1742](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-act.cc#L1742) | 행동 시간 |
| S28 | [crawl-ref/source/mon-behv.cc:1016](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-behv.cc#L1016) | 행동 상태 |
| S29 | [crawl-ref/source/mon-pick-data.h:63](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-pick-data.h#L63) | 깊이별 population |
| S30 | [crawl-ref/source/dat/des/builder/uniques.des:263](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/des/builder/uniques.des#L263) | unique 배치 |
| S31 | [crawl-ref/source/melee-attack.cc:3196](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/melee-attack.cc#L3196) | 히드라 절단·재생 |
| S32 | [crawl-ref/source/mon-abil.cc:559](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-abil.cc#L559) | 슬라임 합체 |
| S33 | [crawl-ref/source/item-def.h:21](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/item-def.h#L21) | 아이템 구조 |
| S34 | [crawl-ref/source/item-prop.cc:312](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/item-prop.cc#L312) | 무기·brand 가중치 |
| S35 | [crawl-ref/source/item-prop.cc:47](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/item-prop.cc#L47) | 갑옷·ego 데이터 |
| S36 | [crawl-ref/source/makeitem.cc:2023](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/makeitem.cc#L2023) | 랜덤 아이템 생성 |
| S37 | [crawl-ref/source/artefact.cc:1486](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/artefact.cc#L1486) | artefact 속성 |
| S38 | [crawl-ref/source/items.cc:1003](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/items.cc#L1003) | 장비·wand 자동 식별 |
| S39 | [crawl-ref/source/acquire.cc:1205](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/acquire.cc#L1205) | 획득 선택 생성 |
| S40 | [crawl-ref/source/xp-evoker-data.h:18](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/xp-evoker-data.h#L18) | XP 재충전 evoker |
| S41 | [crawl-ref/source/skills.cc:766](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/skills.cc#L766) | 훈련 분배 |
| S42 | [crawl-ref/source/skills.cc:2493](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/skills.cc#L2493) | 폐기 skill |
| S43 | [crawl-ref/source/skills.cc:2611](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/skills.cc#L2611) | 적성 비용 |
| S44 | [crawl-ref/source/skill-type.h:10](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/skill-type.h#L10) | skill 목록 |
| S45 | [crawl-ref/source/spl-util.cc:58](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-util.cc#L58) | 주문 구조 |
| S46 | [crawl-ref/source/spl-data.h:26](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-data.h#L26) | 주문 정의 |
| S47 | [crawl-ref/source/spl-cast.cc:469](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-cast.cc#L469) | 실패율 |
| S48 | [crawl-ref/source/spl-cast.cc:564](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-cast.cc#L564) | 마법 위력 |
| S49 | [crawl-ref/source/spl-util.cc:545](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-util.cc#L545) | MP 비용 |
| S50 | [crawl-ref/source/spl-book.cc:223](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-book.cc#L223) | 학습 가능한 주문 판별 |
| S51 | [crawl-ref/source/book-data.h:37](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/book-data.h#L37) | 마법서 내용 |
| S52 | [crawl-ref/source/fight.cc:1742](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/fight.cc#L1742) | Str/Dex 피해 역할 |
| S53 | [crawl-ref/source/player-act.cc:242](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/player-act.cc#L242) | 공격 시간 |
| S54 | [crawl-ref/source/player.cc:2366](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/player.cc#L2366) | EV 계산 |
| S55 | [crawl-ref/source/player.cc:6392](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/player.cc#L6392) | ER·Str·Armour |
| S56 | [crawl-ref/source/player.cc:2406](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/player.cc#L2406) | 갑옷과 마법 |
| S57 | [crawl-ref/source/dat/species/formicid.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/formicid.yaml#L1) | Formicid |
| S58 | [crawl-ref/source/dat/species/octopode.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/octopode.yaml#L1) | Octopode |
| S59 | [crawl-ref/source/dat/species/coglin.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/coglin.yaml#L1) | Coglin |
| S60 | [crawl-ref/source/dat/species/djinni.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/djinni.yaml#L1) | Djinni |
| S61 | [crawl-ref/source/dat/species/gnoll.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/gnoll.yaml#L1) | Gnoll |
| S62 | [crawl-ref/source/dat/species/mountain-dwarf.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/mountain-dwarf.yaml#L1) | Mountain Dwarf |
| S63 | [crawl-ref/source/dat/species/gale-centaur.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/gale-centaur.yaml#L1) | Gale Centaur |
| S64 | [crawl-ref/source/dat/species/poltergeist.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/poltergeist.yaml#L1) | Poltergeist |
| S65 | [crawl-ref/source/god-type.h:5](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/god-type.h#L5) | 신 목록 |
| S66 | [crawl-ref/source/religion.cc:3891](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/religion.cc#L3891) | 입교 |
| S67 | [crawl-ref/source/religion.cc:2864](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/religion.cc#L2864) | 배교 |
| S68 | [crawl-ref/source/god-conduct.cc:217](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/god-conduct.cc#L217) | 금기 |
| S69 | [crawl-ref/source/god-passive.cc:81](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/god-passive.cc#L81) | 신별 passive |
| S70 | [crawl-ref/source/god-abil.cc:2437](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/god-abil.cc#L2437) | 장비 저주 |
| S71 | [crawl-ref/source/god-abil.cc:2471](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/god-abil.cc#L2471) | 저주 해제 비용 |
| S72 | [crawl-ref/source/god-wrath.cc:1740](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/god-wrath.cc#L1740) | 신벌 |
| S73 | [crawl-ref/source/religion.cc:2060](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/religion.cc#L2060) | 신의 선물 |
| S74 | [crawl-ref/source/defines.h:113](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/defines.h#L113) | 기본/최대 시야 |
| S75 | [crawl-ref/source/mon-act.cc:3743](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-act.cc#L3743) | 추격 기회공격 |
| S76 | [crawl-ref/source/dat/clua/autofight.lua:38](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/clua/autofight.lua#L38) | 기존 자동 공격 |
| S77 | [crawl-ref/source/zot.cc:71](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/zot.cc#L71) | 행동 시간 제한 |
| S78 | [crawl-ref/source/transformation.h:5](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/transformation.h#L5) | 변신 상태 |
| S79 | [crawl-ref/source/dat/species/human.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/human.yaml#L1) | Human 탐험 재생 |
| S80 | [crawl-ref/source/dat/species/spriggan.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/spriggan.yaml#L1) | Spriggan |
| S81 | [crawl-ref/source/dat/species/revenant.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/revenant.yaml#L1) | Revenant |
| S82 | [crawl-ref/source/dat/species/draconian-base.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/draconian-base.yaml#L1) | Draconian 기본형 |
| S83 | [crawl-ref/source/dat/mons/death-yak.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/death-yak.yaml#L1) | death yak |
| S84 | [crawl-ref/source/dat/mons/sigmund.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/mons/sigmund.yaml#L1) | Sigmund |
| S85 | [crawl-ref/source/item-prop.cc:2448](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/item-prop.cc#L2448) | 소모품 희귀도 |
| S86 | [crawl-ref/source/spl-util.cc:2232](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-util.cc#L2232) | 제거된 주문 필터 |
| S87 | [crawl-ref/source/mon-cast.cc:5282](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-cast.cc#L5282) | 몬스터 주문 실행 |
| S88 | [crawl-ref/source/shout.cc:385](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/shout.cc#L385) | 소음 전달 |
| S89 | [crawl-ref/source/quiver.cc:68](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/quiver.cc#L68) | 기존 준비 행동 |
| S90 | [crawl-ref/source/dat/species/felid.yaml:1](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/dat/species/felid.yaml#L1) | Felid |
| S91 | [crawl-ref/source/spl-damage.cc:2248](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-damage.cc#L2248) | 독성 cloud→불 |
| S92 | [crawl-ref/source/spl-damage.cc:5244](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-damage.cc#L5244) | Grave Claw 충전 소비 |
| S93 | [crawl-ref/source/spl-other.cc:377](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-other.cc#L377) | 벽 통과 지연과 방어 |
| S94 | [crawl-ref/source/spl-transloc.cc:939](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/spl-transloc.cc#L939) | 무작위 blink와 cooldown |
| S95 | [crawl-ref/source/movement.cc:205](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/movement.cc#L205) | 이동과 위치 방어 마법 |
| S96 | [crawl-ref/source/mon-place.cc:203](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-place.cc#L203) | D:1 OOD 제한 |
| S97 | [crawl-ref/source/mon-death.cc:3601](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/mon-death.cc#L3601) | 몬스터 사망 시 물품 처리 |
| S98 | [crawl-ref/source/acquire.cc:1752](https://github.com/crawl/crawl/blob/2bd8e06e6e5614a6f4917c1c24e04a8922319476/crawl-ref/source/acquire.cc#L1752) | acquirement 선택 |
