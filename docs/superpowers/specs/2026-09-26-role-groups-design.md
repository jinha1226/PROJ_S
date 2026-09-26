# 역할군 5개와 세부 유형

상태: 현재 30종·부위 90개 기준 구현 완료. 실행 결과와 세부 계약은 [구현 기록](../plans/2026-09-26-role-groups.md)을 따른다.
작성일: 2026-09-26 · 상태: **현재 30종 기준 구현 완료, 원정 난이도 조정은 후속 작업**
근거: [영혼석 개편](2026-09-26-soulstone-rework-design.md)(역할 조합 2·4·6), [③ 빌드군과 부위 효과](2026-09-26-build-families-part-effects-design.md)(빌드군 12개), [빌드를 아는 동료 AI](2026-09-26-build-aware-companion-ai-design.md), [장비](2026-09-26-gear-affixes-design.md), [도감](2026-09-26-codex-design.md)
기존 코드·데이터: `data/content/essences.json`(행마다 `role`: PACK·BERSERK·AMBUSH·GUARD·ARCHER·CASTER), `expedition/progression/essences.gd`(`ROLES`), `tag_sets.gd`(`ROLE_TEXT`, 구간), `stone_effects.gd`(역할 조합 수치 `PACK_ATTACK`·`BERSERK_ATTACK`·`AMBUSH_CRIT`·`ARCHER_RANGED`·`CASTER_SPELL`, `GUARD_*`), `bestiary.gd`(`ROLE_POINTS` 영혼석 기본 스탯, `ROLE_HP`·`ROLE_ATTACK` 몬스터 수치), `data/content/stone_effects.json`(효과마다 `families` 1~12), `expedition/ai/build_sense.gd`(`NAMES`), `expedition/actors/npc_essences.gd`, 도감 거르기 칩, 장비 증폭 옵션

## 0. 결정

1. **역할군 5개**: 탱커, 근딜, 원딜, 마법, 지원. 파티 게임에서 가장 직관적인 말이다.
2. **역할군은 영혼석(종족)에 붙는다.** 기본 스탯과 **역할군 조합(2·4·6개)**을 정한다. 보너스는 여기에만 있다.
3. **세부 유형은 부위 효과에 붙는다.** 지금의 빌드군 12개 자리를 17개 세부 유형이 대신한다. **보너스 없음.** 쓰임새: 정체성 표시("방어 60%"), 동료 AI, 도감 거르기, 장비 증폭 옵션.
4. 세부 유형은 역할군에 속하지만, **어느 역할군 영혼석에도 나올 수 있다.** 예: 원딜인 해골 궁수의 손가락은 근딜·분쇄 유형. 그래서 역할군과 세부 유형이 섞여 빌드가 생긴다.
5. **몬스터 수치는 바뀌지 않는다.** 몬스터 체력·공격 배율(`ROLE_HP`·`ROLE_ATTACK`)은 `floor_monsters.json`의 `role`(옛 PACK 등)을 읽고, 이번 개편은 `essences.json`의 `role`만 바꾼다.

## 1. 세부 유형 17개

| 역할군 | id | 세부 유형 | 핵심 |
| --- | --- | --- | --- |
| 탱커 `TANK` | `DEFENSE` | 방어 | 방어·막기·피해 감소, 맞을수록 단단해짐, 동료 대신 맞기 |
| | `EVASION` | 회피 | 회피, 피하면 반격·치명 |
| | `REGEN` | 재생 | 재생·흡혈·처치 회복 |
| | `REFLECT` | 반사 | 반격·반사·막으면 되받아침 |
| 근딜 `MELEE` | `BLEED` | 출혈 | 베기 → 출혈 누적 → 전이 |
| | `CRUSH` | 분쇄 | 타격 → 골절·기절 |
| | `VITAL` | 급소 | 찌르기 → 급소 노출 → 치명타 |
| | `FURY` | 광폭 | 체력이 낮을수록·맞을수록 강함 |
| 원딜 `RANGED` | `SNIPE` | 저격 | 조준, 먼 거리, 사거리 |
| | `VOLLEY` | 연사 | 추가 사격, 관통 |
| | `VENOM` | 맹독 | 중독 누적, 독 폭발 |
| 마법 `MAGIC` | `ELEMENT` | 원소 | 화염·냉기·전기·젖음 반응 |
| | `SUMMON` | 소환 | 소환수 수·세기·효과 공유 |
| | `DEATH` | 사령 | 주변 죽음, 처치한 적 소생, 죽음 유예 |
| 지원 `SUPPORT` | `HEAL` | 회복 | 회복·보호·정화·자원 |
| | `HEX` | 저주 | 약화·해로운 상태 누적 |
| | `BOOST` | 강화 | 동료와 함께일 때 강함, 속도·버프 |

(17개: 탱커 4, 근딜 4, 원딜 3, 마법 3, 지원 3. 옛 빌드군 대응: 출혈→`BLEED`, 분쇄→`CRUSH`, 급소→`VITAL`, 광폭→`FURY`, 원소→`ELEMENT`, 저주→`HEX`, 독→`VENOM`, 소환→`SUMMON`, 사령→`DEATH`. 수호·사수·지원은 효과마다 §4 표로 나눈다.)

## 2. 역할군 기본 스탯과 조합

### 2.1 기본 스탯(영혼석 하나)

| 역할군 | 기본 스탯 | 옛 역할에서 |
| --- | --- | --- |
| 탱커 | 최대 HP +20, 방어 +3 | 수호 |
| 근딜 | 공격력 +4, 최대 HP +8 | 광폭 |
| 원딜 | 공격력 +3, 행동 속도 +5% | 사수 |
| 마법 | 주문력 +4, 최대 MP +8 | 술사 |
| 지원 | 최대 HP +10, 최대 MP +6 | (새) |

### 2.2 역할군 조합 (가장 높은 구간 하나만)

| 역할군 | 2개 | 4개 | 6개 |
| --- | --- | --- | --- |
| 탱커 | 방어 +2 | 방어 +5, 막기 +10 | 방어 +6, 막기 +12, 인접 동료가 받는 피해 −10% |
| 근딜 | 공격력 +12% | 공격력 +25%, 치명 +8 | 공격력 +30%, 치명 +10, 처치 시 HP 5% |
| 원딜 | 사거리 +1 | 원거리 피해 +20% | 원거리 피해 +25%, 15% 확률 추가 사격 |
| 마법 | 주문력 +12% | 주문력 +25%, 라운드마다 MP +2 | 주문력 +30%, 주문 실패 없음 |
| 지원 | 내가 주는 회복·보호 +20% | 회복·보호 +30%, 파티 전원 공격력 +8% | 회복·보호 +40%, 공격력 +10%, 라운드 시작에 인접 동료 해로운 상태 하나 25% 해제 |

- 원칙은 ③ §5와 같다: 2→4는 크게, 4→6은 작게.
- "파티 전원"은 지원 조합이 켜진 파티원 중 가장 높은 구간 하나만 파티에 적용(옛 무리 규칙과 같음).
- 최종 보스 `set_boost`(한 구간 상승)는 역할군 조합에 그대로.

## 3. 종족 배정 (38종 + 보스 3)

| 역할군 | 종족 (영혼석 id) | 수 |
| --- | --- | --- |
| 탱커 | 목도리 도마뱀(`LIZARD_TAIL`), 홉고블린(`HOB_TAUNT`), 고블린 방패병(`SHIELD_STANCE`), 바위 딱정벌레(`BEETLE_CURL`), 신전 뱀(`SERPENT_SHED`), 해골 병사(`SKELETON_WALL`), 망령 기사(`THORN_ARMOUR`), 역병 좀비(새) | 8 |
| 근딜 | 고블린(`GOBLIN_SHIV`), 오크(`ORC_CLEAVER`), 놀(`GNOLL_SPEAR`), 강쥐(`RIVER_RAT_SPLASH`), 광석 골렘(`ORE_SLAM`), 거대 거머리(`LEECH_LATCH`), 구울(`GHOUL_CLAW`), 흡혈 박쥐(`VAMPIRE_BITE`), 폐허 사냥개(새), 미믹(새) | 10 |
| 원딜 | 코볼트(`KOBOLD_SLING`), 폭풍 박쥐(`STORM_BAT`), 고블린 궁수(`GOBLIN_AIM`), 오크 투척병(`ORC_THROW`), 늪 두꺼비(`TOAD_SPIT`), 해골 궁수(`SKELETON_VOLLEY`) | 6 |
| 마법 | 코볼트 화염술사(`FIRE_CALLER`), 서리 도깨비(`FROST_IMP`), 놀 소환사(`GNOLL_SUMMONER`), 묘지기(`GRAVEKEEPER`), 불도롱뇽(새), 광부 유령(새), 뼈 직조공(새) | 7 |
| 지원 | 쥐(`RAT_GNAW`), 고블린 주술사(`GOBLIN_HEXER`), 동굴 거미(`SPIDER_WEB`), 물의 정령(`WATER_WAVE`), 원혼(`WRAITH`), 포자 버섯(새), 신전 시종(새) | 7 |
| 보스 | 고블린 족장(`GOBLIN_CHIEF`) 지원, 용광로 심장(`FURNACE_HEART`) 탱커, 영혼 포식자(`SOUL_EATER`) 마법 | 3 |

- 술사 학파 주문은 그대로 종족에 붙는다(역할군과 무관): 화염술사 화염, 서리 도깨비 냉기, 폭풍 박쥐 전기, 주술사 저주, 놀 소환사 소환 등. **지원 역할군인 주술사도 저주 주문을 준다.**
- 새 종족 8개는 ④-b에서 들어온다. 그전에는 30종 기준: 탱커 7, 근딜 8, 원딜 6, 마법 4, 지원 5.

## 4. 부위 효과의 세부 유형

표기: 부위 cut / broken / pierced 순. (새)는 ④-b 종족.

| 종족 (역할군) | cut | broken | pierced |
| --- | --- | --- | --- |
| 쥐 (지원) | RAT_GNAW 강화 | RAT_INCISOR 출혈 | RAT_HEART 강화 |
| 목도리 도마뱀 (탱커) | LIZARD_TAIL 반사 | LIZARD_FRILL 광폭 | LIZARD_EYE 회피 |
| 코볼트 (원딜) | KOBOLD_HIDE 회피 | KOBOLD_SLING 저격 | KOBOLD_HEART 저격 |
| 고블린 (근딜) | GOBLIN_EAR 급소 | GOBLIN_TOOTH 저주 | GOBLIN_SHIV 급소 |
| 오크 (근딜) | ORC_HIDE 출혈 | ORC_CLEAVER 광폭 | ORC_HEART 광폭 |
| 놀 (근딜) | GNOLL_HIDE 광폭 | GNOLL_BONE 재생 | GNOLL_SPEAR 광폭 |
| 강쥐 (근딜) | RIVER_RAT_SPLASH 원소 | RIVER_RAT_TOOTH 출혈 | RIVER_RAT_HEART 회복 |
| 코볼트 화염술사 (마법) | FIRECALLER_HAND 원소 | FIRECALLER_BONE 원소 | FIRE_CALLER 원소 |
| 서리 도깨비 (마법) | FROST_CLAW 원소 | FROST_HORN 원소 | FROST_IMP 원소 |
| 폭풍 박쥐 (원딜) | STORM_BAT 강화 | BAT_BONE 원소 | BAT_EAR 회피 |
| 고블린 주술사 (지원) | HEXER_HAND 저주 | HEXER_SKULL 저주 | GOBLIN_HEXER 저주 |
| 놀 소환사 (마법) | SUMMONER_HIDE 소환 | SUMMONER_BONE 소환 | GNOLL_SUMMONER 소환 |
| 홉고블린 (탱커) | HOB_HIDE 광폭 | HOB_JAW 분쇄 | HOB_TAUNT 방어 |
| 고블린 궁수 (원딜) | GOBLIN_AIM 저격 | ARCHER_KNUCKLE 연사 | ARCHER_EYE 저격 |
| 고블린 방패병 (탱커) | SHIELD_HIDE 반사 | SHIELD_STANCE 방어 | SHIELD_HEART 분쇄 |
| 오크 투척병 (원딜) | ORC_THROW 연사 | THROWER_SHOULDER 분쇄 | THROWER_EYE 저주 |
| 동굴 거미 (지원) | SPIDER_LEG 급소 | SPIDER_SHELL 저주 | SPIDER_WEB 저주 |
| 바위 딱정벌레 (탱커) | BEETLE_WING 방어 | BEETLE_CURL 방어 | BEETLE_CORE 방어 |
| 광석 골렘 (근딜) | GOLEM_VEIN 분쇄 | ORE_SLAM 분쇄 | GOLEM_CORE 분쇄 |
| 거대 거머리 (근딜) | LEECH_LATCH 출혈 | LEECH_SEGMENT 출혈 | LEECH_SUCKER 재생 |
| 늪 두꺼비 (원딜) | TOAD_TONGUE 맹독 | TOAD_BONE 맹독 | TOAD_SPIT 맹독 |
| 신전 뱀 (탱커) | SERPENT_SHED 방어 | SERPENT_SCALE 맹독 | SERPENT_FANG 맹독 |
| 물의 정령 (지원) | SPIRIT_CURRENT 방어 | SPIRIT_DROP 회복 | WATER_WAVE 회복 |
| 해골 병사 (탱커) | SKELETON_ARM 출혈 | SKELETON_WALL 방어 | SKELETON_SKULL 사령 |
| 해골 궁수 (원딜) | BOWMAN_FINGER 분쇄 | SKELETON_VOLLEY 급소 | BOWMAN_SOCKET 분쇄 |
| 구울 (근딜) | GHOUL_CLAW 재생 | GHOUL_JAW 사령 | GHOUL_HEART 재생 |
| 흡혈 박쥐 (근딜) | VAMPIRE_WING 급소 | VAMPIRE_BITE 재생 | VAMPIRE_HEART 재생 |
| 망령 기사 (탱커) | WRAITH_KNIGHT_CLOAK 저주 | THORN_ARMOUR 반사 | WRAITH_KNIGHT_CORE 분쇄 |
| 원혼 (지원) | WRAITH_SHROUD 저주 | WRAITH_BONE 저주 | WRAITH 저주 |
| 묘지기 (마법) | GRAVEKEEPER_HAND 소환 | GRAVEKEEPER_BONE 소환 | GRAVEKEEPER 사령 |
| 폐허 사냥개 (근딜, 새) | HOUND_EAR 출혈 | HOUND_LEG 강화 | HOUND_NOSE 출혈 |
| 포자 버섯 (지원, 새) | SHROOM_CAP 맹독 | SHROOM_STEM 회복 | SHROOM_SAC 맹독 |
| 불도롱뇽 (마법, 새) | SALAMANDER_TAIL 광폭 | SALAMANDER_SCALE 원소 | SALAMANDER_HEART 원소 |
| 광부 유령 (마법, 새) | GHOST_HAND 사령 | GHOST_CHAIN 급소 | GHOST_CORE 사령 |
| 신전 시종 (지원, 새) | ACOLYTE_HAND 회복 | ACOLYTE_BONE 방어 | ACOLYTE_HEART 회복 |
| 미믹 (근딜, 새) | MIMIC_TONGUE 급소 | MIMIC_TOOTH 급소 | MIMIC_CORE 급소 |
| 뼈 직조공 (마법, 새) | WEAVER_THREAD 소환 | WEAVER_BONE 소환 | WEAVER_CORE 소환 |
| 역병 좀비 (탱커, 새) | ZOMBIE_FLESH 맹독 | ZOMBIE_BONE 재생 | ZOMBIE_HEART 반사 |

- 효과 하나에 세부 유형 하나(옛 `families`는 둘까지 있었다). 데이터 필드는 `subtype`.
- **부품 수**(114개): 방어 9, 회피 3, 재생 7, 반사 4 · 출혈 8, 분쇄 9, 급소 9, 광폭 7 · 저격 4, 연사 2, 맹독 8 · 원소 10, 소환 8, 사령 5 · 회복 6, 저주 11, 강화 4.
  - **얇은 유형: 연사 2, 회피 3, 저격 4, 강화 4, 반사 4.** 장비 옵션과 고정 아티팩트로 먼저 보강하고, 다음 종족 추가 때 채운다.

## 5. 바뀌는 곳

| 곳 | 바뀌는 것 |
| --- | --- |
| `data/content/essences.json` | `role`을 새 역할군 id로(`floor_monsters.json`의 몬스터 `role`은 그대로) |
| `expedition/progression/essences.gd` | `ROLES = {"TANK":"탱커","MELEE":"근딜","RANGED":"원딜","MAGIC":"마법","SUPPORT":"지원"}`. 옛 id 별칭은 두지 않고 테스트를 새 id로 옮긴다 |
| `expedition/progression/bestiary.gd` | `ROLE_POINTS`를 §2.1로(새 id). `ROLE_HP`·`ROLE_ATTACK`은 몬스터 쪽이라 그대로 |
| `expedition/progression/tag_sets.gd` | `ROLE_TEXT`를 §2.2로, 구간 계산은 그대로 |
| `expedition/progression/stone_effects.gd` | 역할 조합 수치 상수를 새 역할군으로(§2.2). 지원 조합의 회복·보호 증가, 공격력, 정화 |
| `data/content/stone_effects.json` | 효과마다 `families` → `subtype`(§4). 장비 효과도 가장 가까운 세부 유형 |
| `expedition/ai/build_sense.gd` | 세부 유형 이름은 `Subtypes`에서 읽고 `subtype_profile`은 유형 비율. `profile`은 내부 전술 채널로 합산하며 탱커 네 유형은 자리 선호로 대응 |
| 동료 태세 기본값 | 주 역할군으로 추천: 탱커 → 수호형, 근딜 → 돌격형, 원딜·마법 → 치고 빠지기, 지원 → 수호형(동료 곁). 추천만 하고 강제하지 않는다 |
| `expedition/actors/npc_essences.gd` | 성격 선호를 역할군으로: 낮은 A → 근딜, 높은 C → 탱커·지원, 높은 O → 마법, 그 밖 → 원딜 |
| 장비 증폭 옵션 | 빌드군 12개 → 세부 유형(있는 것부터). 얇은 유형(회피·연사·저격·강화) 옵션을 우선 추가 |
| 도감 거르기 | 역할군 5 칩 + 누르면 그 아래 세부 유형 칩 |
| 화면 문구 | 영혼석 카드 "탱커 · 방어", 캐릭터 화면 "방어 60% · 반사 30%", 역할군 조합 현황 |

## 6. 테스트

| 스위트 | 검사 |
| --- | --- |
| `tests/role_groups.gd` (새) | 38종(현재 30종)의 역할군 배정, 영혼석의 옛 역할 별칭 없음·몬스터의 기존 역할 유지, 역할군 기본 스탯, 조합 2·4·6 각 구간(지원 조합 포함), 몬스터 수치가 바뀌지 않음 |
| `tests/effect_data.gd` | 모든 부위 효과에 `subtype`이 있고 17개 중 하나 |
| `tests/build_sense.gd`, `build_ai.gd` | 세부 유형 기준으로 옮김, 검사 수 유지 |
| 기존 `tag_sets`, `stone_effects`, `essences`, `npc_essences`, `gear_affixes`, `codex_ui` | 새 이름으로 옮김, 검사 수 유지 |

## 7. 검토할 결정

1. 종족 배정(§3), 특히 도마뱀(탱커), 흡혈 박쥐(근딜), 동굴 거미(지원), 강쥐(근딜), 폭풍 박쥐(원딜).
2. 지원 역할군의 기본 스탯과 조합 수치.
3. 얇은 세부 유형(회피·연사·저격·강화) 보강을 장비로 먼저 할지.
