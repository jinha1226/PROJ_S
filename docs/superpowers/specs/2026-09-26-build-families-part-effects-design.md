# ③ 빌드군과 부위 효과

작성일: 2026-09-26 · 상태: **검토 반영·② 완료 후 빌드군별 구현** · 수치는 모두 첫 값이며 난이도 게이트로 다시 맞춘다
근거: [공격 형태·부위 영혼석](2026-09-26-damage-forms-part-stones-design.md) · [② 발동 엔진](2026-09-26-trigger-engine-design.md)(키워드 사전) · 참고 [`docs/reference/barbarian-abilities.ko.md`](../../reference/barbarian-abilities.ko.md)
구현: [④ 부위 영혼석 구현](2026-09-26-part-stones-implementation-design.md)

## 0. 방법

1. 빌드군 12개를 먼저 정한다. 빌드군마다 **핵심 고리**(무엇을 걸고, 무엇이 그것을 받아 터뜨리는지)와 **부품 목록**을 적는다.
2. 부품을 38종 × 3부위에 나눠 담는다. 한 종족의 세 부위는 보통 두 빌드군에 걸친다. 그래야 "이 종족은 누가 잡아도 쓸모가 있다".
3. 기존 대표 효과 30개는 버리지 않고 그 종족의 한 부위로 들어간다(동작 그대로).
4. 부위는 `cut`(잘린 부위: 베기로 잘 나옴), `broken`(부서진 부위: 타격), `pierced`(꿰뚫린 부위: 찌르기).

## 1. 빌드군 12개

| # | 빌드군 | 핵심 고리 | 주 형태·수단 | 잘 맞는 역할 조합 |
| --- | --- | --- | --- | --- |
| 1 | 출혈 | 베기로 출혈을 걸고 → 출혈 대상에게 더 세게, 처치하면 퍼뜨림 | 베기, 광역(도끼) | 광폭·무리 |
| 2 | 분쇄 | 타격으로 골절·기절 → 움직이지 못하는 적을 부숨, 밀어서 벽에 박음 | 타격, 방패 | 수호·광폭 |
| 3 | 급소 | 찌르기로 급소를 드러냄 → 치명타, 치명타가 속도·재사용으로 돌아옴 | 찌르기, 단검·창 | 기습·사수 |
| 4 | 광폭 | 체력이 낮을수록 강함, 맞을수록 분노, 처치로 회복 | 근접 | 광폭 |
| 5 | 수호 | 막고, 버티고, 동료 대신 맞고, 맞을수록 단단해짐, 되받아침 | 방패, 근접 | 수호 |
| 6 | 사수 | 가만히 조준할수록 강함, 멀수록 강함, 추가 사격·관통·표식 | 활, 투척 | 사수 |
| 7 | 원소 | 화염·냉기·전기와 젖음 → 반응 → 반응이 자원·피해로 | 주문, 속성 무기 | 술사 |
| 8 | 저주 | 해로운 상태를 여럿 겹침 → 겹친 수만큼 피해, 죽으면 옮김 | 저주 주문, 약화 | 술사·기습 |
| 9 | 독 | 중독을 쌓음 → 쌓인 만큼 틱 피해, 죽으면 독 폭발 | 찌르기, 독 부여 | 사수·기습 |
| 10 | 소환 | 소환수를 늘리고 강하게 → 내 효과를 나눠 줌, 사라지면 자원 환급 | 소환 주문 | 술사 |
| 11 | 사령 | 죽음을 자원으로: 주변 죽음이 힘, 처치한 적이 일어남, 죽음 유예 | 무엇이든 | 술사·광폭 |
| 12 | 지원 | 회복·보호막·속도, 동료 위기 구하기, 받는 버프 강화 | 무엇이든 | 무리·수호 |

## 2. 새 종족 8개

구역마다 2종. 비어 있던 빌드군(사령, 지원, 독, 소환, 급소)을 채운다.

| 구역 | id | 이름 | 역할 | 공격 형태 | 피부 | 뼈 | 대표 부위 | 액티브(파츠) 초안 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 무너진 성채 지하 | `ruin_hound` | 폐허 사냥개 | 무리 | 베기 | 0 | 0 | 코 | 물어뜯기: 인접 1 피해 8, 출혈 |
| 1 | `spore_shroom` | 포자 버섯 | 사수 | 찌르기 | -1 | 1 | 포자낭 | 포자 살포: 사거리 3 반경 1 중독 |
| 2 불타는 폐광 | `ember_salamander` | 불도롱뇽 | 광폭 | 베기 | 1 | 0 | 꼬리 | 불꽃 돌진: 2칸 돌진, 경로 화상 |
| 2 | `mine_ghost` | 광부 유령 | 기습 | 베기 | -1 | 1 | 영혼핵 | 벽 통과: 벽 너머 3칸 순간이동 |
| 3 잠긴 지하 신전 | `temple_acolyte` | 신전 시종 | 수호 | 타격 | 0 | 0 | 심장 | 치유 기도: 인접 동료 HP 15% 회복 |
| 3 | `mimic` | 미믹 | 기습 | 찌르기 | 1 | 0 | 이빨 | 삼키기: 인접 1 속박 1라운드 + 피해 10 |
| 4 망자의 묘역 | `bone_weaver` | 뼈 직조공 | 술사(소환) | 찌르기 | -1 | -1 | 핵 | 뼈 병사 소환(소환 학파 주문) |
| 4 | `plague_zombie` | 역병 좀비 | 광폭 | 타격 | -1 | -1 | 심장 | 역병 토사: 원뿔 2칸 중독 |

- 역할 수(보스 제외): 무리 6, 광폭 7, 기습 6, 수호 6, 사수 6, 술사 7. 합계 38종이며 보스 3종은 별도다.
- 층 배치·희귀도·위협도는 ④에서 `floor_monsters.json` 행으로 정한다(구역 내 기존 종족과 같은 범위).

## 3. 부위 효과 114개

표기: **굵은 효과 id**는 기존 대표 효과(동작 그대로). ★는 그 종족의 **대표 부위**(몬스터가 쓰는 효과, ④ §4). 빌드군 번호는 §1.
부위 이름은 초안이다(검토 결정 §6).

### 3.1 구역 1

| 종족 | 부위 | 효과 id | 효과 | 발동 | 빌드군 |
| --- | --- | --- | --- | --- | --- |
| 쥐 | cut 꼬리 ★ | **RAT_GNAW** | 인접 동료 1명당 공격력 +10% | 상시 | 12 |
| | broken 앞니 | RAT_INCISOR | 베기·찌르기 공격의 출혈 확률 +10%p | 상시 | 1 |
| | pierced 심장 | RAT_HEART | 동료가 적을 처치하면 내 다음 공격 +20% | 처치(동료) → 쌓임 | 12 |
| 목도리 도마뱀 | cut 꼬리 ★ | **LIZARD_TAIL** | 근접 공격을 받으면 25% 확률로 반격(공격력의 60%) | 피격 | 5 |
| | broken 목도리 | LIZARD_FRILL | 피격될 때마다 분노 +1(최대 5), 분노당 공격력 +5%, 내가 공격하면 분노 초기화 | 피격 → 쌓임 | 4 |
| | pierced 눈 | LIZARD_EYE | 공격을 피하면 다음 공격 치명타 확률 +30 | 회피 | 3 |
| 코볼트 | cut 가죽 | KOBOLD_HIDE | 인접한 적이 없으면 회피 +10 | 상시 | 6 |
| | broken 손뼈 ★ | **KOBOLD_SLING** | 원거리 피해 +25% | 상시 | 6 |
| | pierced 심장 | KOBOLD_HEART | 이동하지 않은 라운드마다 조준 +1(최대 3), 조준당 원거리 피해 +10%, 이동하면 초기화 | 라운드 시작 → 쌓임 | 6 |
| 고블린 | cut 귀 | GOBLIN_EAR | 전투의 첫 공격은 반드시 치명타 | 공격 | 3 |
| | broken 이빨 | GOBLIN_TOOTH | 해로운 상태를 걸 때마다 대상 방어 −1(누적 최대 −5, 300 tick) | 상태 부여 | 8 |
| | pierced 심장 ★ | **GOBLIN_SHIV** | 체력이 가득한 대상에게 주는 첫 피해 ×2 | 공격 | 3 |
| 고블린 궁수 | cut 깃 ★ | **GOBLIN_AIM** | 원거리 사거리 +2 | 상시 | 6 |
| | broken 손가락뼈 | ARCHER_KNUCKLE | 원거리 명중 시 20% 확률로 대상 뒤 한 칸의 적에게도 피해 50% | 명중 | 6 |
| | pierced 눈 | ARCHER_EYE | 4칸 이상 떨어진 대상에게 피해 +20% | 상시 | 6 |
| 고블린 방패병 | cut 가죽 | SHIELD_HIDE | 막으면 공격자에게 반격(공격력의 60%) | 막기 | 5 |
| | broken 팔뼈 ★ | **SHIELD_STANCE** | 막기 확률 +20 | 상시 | 5 |
| | pierced 심장 | SHIELD_HEART | 막으면 공격자에게 골절 판정(타격 부상 확률 그대로) | 막기 | 2 |
| 홉고블린 | cut 가죽 | HOB_HIDE | 공격할 때 내 HP 2% 소모, 공격력 +30% | 공격 | 4 |
| | broken 턱뼈 | HOB_JAW | 타격 공격의 골절 확률 +10%p | 상시 | 2 |
| | pierced 심장 ★ | **HOB_TAUNT** | 최대 HP +20% | 상시 | 5 |
| 고블린 주술사 | cut 손 | HEXER_HAND | 대상에게 걸린 해로운 상태 1개당 주는 피해 +8% | 상시 | 8 |
| | broken 두개골 | HEXER_SKULL | 저주 학파 주문의 의지 판정 −20(더 잘 걸림) | 상시 | 8 |
| | pierced 눈 ★ | **GOBLIN_HEXER** | 내가 거는 상태이상 지속 +50% | 상시 | 8 |
| 폐허 사냥개 (새) | cut 귀 | HOUND_EAR | 출혈 중인 대상에게 주는 피해 +20% | 상시 | 1 |
| | broken 다리뼈 | HOUND_LEG | 이번 라운드에 동료가 친 대상을 치면 피해 +15% | 상시 | 12 |
| | pierced 코 ★ | HOUND_NOSE | 출혈 중인 대상을 처치하면 반경 1의 적에게 출혈 | 처치 | 1 |
| 포자 버섯 (새) | cut 갓 | SHROOM_CAP | 모든 공격에 독 피해 +2 | 명중 | 9 |
| | broken 줄기 | SHROOM_STEM | 라운드마다 20% 확률로 인접 동료 하나의 해로운 상태 하나를 지움 | 라운드 시작 | 12 |
| | pierced 포자낭 ★ | SHROOM_SAC | 중독된 대상을 처치하면 반경 1에 독 폭발(중독 300 tick) | 처치 | 9 |

### 3.2 구역 2

| 종족 | 부위 | 효과 id | 효과 | 발동 | 빌드군 |
| --- | --- | --- | --- | --- | --- |
| 오크 | cut 가죽 | ORC_HIDE | 이미 출혈 중인 대상에게 출혈을 다시 걸면 출혈 틱 3번 분량의 피해를 바로 줌 | 부상 | 1 |
| | broken 뼈 ★ | **ORC_CLEAVER** | 공격력 +20%, 받는 피해 +10% | 상시 | 4 |
| | pierced 심장 | ORC_HEART | 체력 30% 이하에서 받는 피해 −25% | 상시 | 4 |
| 오크 투척병 | cut 팔 ★ | **ORC_THROW** | 원거리 공격이 20% 확률로 한 번 더 | 명중 | 6 |
| | broken 어깨뼈 | THROWER_SHOULDER | 타격 명중 시 15% 확률로 대상을 한 칸 밀침, 밀 곳이 막혀 있으면 추가 피해 8 | 명중 | 2 |
| | pierced 눈 | THROWER_EYE | 원거리 명중 시 20% 확률로 표식(받는 피해 +20%, 300 tick) | 명중 | 6·8 |
| 동굴 거미 | cut 다리 | SPIDER_LEG | 치명타를 내면 다음 행동 지연 −30% | 치명타 | 3 |
| | broken 껍질 | SPIDER_SHELL | 해로운 상태가 3개 이상인 대상에게 피해 +30% | 상시 | 8 |
| | pierced 실샘 ★ | **SPIDER_WEB** | 공격에 25% 확률로 속박 1라운드 | 명중 | 8 |
| 바위 딱정벌레 | cut 날개 | BEETLE_WING | 라운드 시작에 인접한 적 1명당 방어 +2(그 라운드) | 라운드 시작 | 5 |
| | broken 껍질 ★ | **BEETLE_CURL** | 받는 피해 −15% | 상시 | 5 |
| | pierced 핵 | BEETLE_CORE | 피격될 때마다 방어 +1(전투 동안, 최대 +8) | 피격 → 쌓임 | 5 |
| 광석 골렘 | cut 광맥 | GOLEM_VEIN | 타격 공격이 방어를 완전히 무시 | 상시 | 2 |
| | broken 몸돌 ★ | **ORE_SLAM** | 공격에 20% 확률로 기절 1라운드 | 명중 | 2 |
| | pierced 핵 | GOLEM_CORE | 기절·빙결·골절 대상에게 피해 +30% | 상시 | 2 |
| 코볼트 화염술사 | cut 손 | FIRECALLER_HAND | 화상 중인 대상에게 주는 피해 +20% | 상시 | 7 |
| | broken 뼈 | FIRECALLER_BONE | 원소 반응을 일으키면 MP +2 | 반응 | 7 |
| | pierced 심장 ★ | **FIRE_CALLER** | 화염 피해 +30%, 공격에 15% 확률로 화상 | 상시·명중 | 7 |
| 폭풍 박쥐 | cut 날개 ★ | **STORM_BAT** | 행동 속도 +20% | 상시 | 12 |
| | broken 뼈 | BAT_BONE | 전기 피해 +30%, 젖은 대상에게 전기 피해 시 20% 확률로 기절 1라운드 | 상시·명중 | 7 |
| | pierced 귀 | BAT_EAR | 이번 라운드에 이동했으면 회피 +15 | 상시 | 12 |
| 불도롱뇽 (새) | cut 꼬리 ★ | SALAMANDER_TAIL | 처치할 때마다 다음 공격 +25%(최대 3번 쌓임, 공격하면 하나 소모) | 처치 → 쌓임 | 4 |
| | broken 비늘 | SALAMANDER_SCALE | 원소 반응 피해 +50% | 상시 | 7 |
| | pierced 심장 | SALAMANDER_HEART | 체력 절반 이하일 때 모든 명중에 화염 피해 +4 | 명중 | 4·7 |
| 광부 유령 (새) | cut 손 | GHOST_HAND | 반경 3 안에서 누가 쓰러질 때마다 공격력 +5%(전투 동안, 최대 +25%) | 주변 죽음 → 쌓임 | 11 |
| | broken 사슬 | GHOST_CHAIN | 치명타 확률 +10 | 상시 | 3 |
| | pierced 영혼핵 ★ | GHOST_CORE | 쓰러질 피해를 받으면 3라운드 동안 버티다 쓰러짐(그동안 회복 불가, 전투당 1회) | 치명상 | 11 |

### 3.3 구역 3

| 종족 | 부위 | 효과 id | 효과 | 발동 | 빌드군 |
| --- | --- | --- | --- | --- | --- |
| 강쥐 | cut 꼬리 ★ | **RIVER_RAT_SPLASH** | 젖은 칸(또는 물)에 서 있으면 모든 피해 +25% | 상시 | 7 |
| | broken 이빨 | RIVER_RAT_TOOTH | 출혈을 걸 때 대상 방어 −2(300 tick) | 부상 | 1 |
| | pierced 심장 | RIVER_RAT_HEART | 피격되지 않은 라운드마다 MP +1 | 라운드 시작 | 12 |
| 거대 거머리 | cut 입 ★ | **LEECH_LATCH** | 같은 대상을 연달아 칠 때마다 피해 +15%(최대 +60%) | 공격 → 쌓임 | 1 |
| | broken 몸마디 | LEECH_SEGMENT | 출혈 틱 피해 +2 | 상시 | 1 |
| | pierced 흡반 | LEECH_SUCKER | 출혈 중인 대상에게 준 피해의 10% 흡혈 | 명중 | 1 |
| 늪 두꺼비 | cut 혀 | TOAD_TONGUE | 이미 중독된 대상에게 다시 중독을 걸면 틱 피해 +1(최대 +4) | 상태 부여 | 9 |
| | broken 뼈 | TOAD_BONE | 중독된 적에게 받는 피해 −15% | 상시 | 9 |
| | pierced 독샘 ★ | **TOAD_SPIT** | 공격에 30% 확률로 중독 | 명중 | 9 |
| 신전 뱀 | cut 허물 ★ | **SERPENT_SHED** | 걸리는 상태이상을 50% 확률로 막음 | 상태 받음 | 12 |
| | broken 비늘 | SERPENT_SCALE | 독 저항 +50, 중독에 걸리지 않음 | 상시 | 9 |
| | pierced 독니 | SERPENT_FANG | 중독된 대상에게 주는 피해 +15% | 상시 | 9 |
| 물의 정령 | cut 물살 | SPIRIT_CURRENT | 젖은 칸에 서 있으면 받는 피해 −15% | 상시 | 5·7 |
| | broken 물방울 | SPIRIT_DROP | 내가 누군가를 회복시키면 그 대상 방어 +3(200 tick) | 회복 | 12 |
| | pierced 핵 ★ | **WATER_WAVE** | 라운드마다 자신과 인접 동료 HP 3% 회복 | 라운드 시작 | 12 |
| 놀 | cut 가죽 | GNOLL_HIDE | 잃은 체력 10%당 행동 속도 +3% | 상시 | 4 |
| | broken 뼈 | GNOLL_BONE | 외부 회복을 받지 못하는 대신 라운드마다 최대 HP 4% 재생 | 상시·라운드 시작 | 4 |
| | pierced 심장 ★ | **GNOLL_SPEAR** | 체력 절반 이하일 때 공격력 +35% | 상시 | 4 |
| 서리 도깨비 | cut 발톱 | FROST_CLAW | 빙결 중인 대상을 처치하면 반경 1의 적에게 20% 확률로 빙결 1라운드 | 처치 | 7 |
| | broken 뿔 | FROST_HORN | 내가 거는 화상·빙결 지속 +50% | 상시 | 7 |
| | pierced 심장 ★ | **FROST_IMP** | 냉기 피해 +30%, 공격에 10% 확률로 빙결 1라운드 | 상시·명중 | 7 |
| 놀 소환사 | cut 가죽 | SUMMONER_HIDE | 내 소환수 둘 이상이 같은 대상을 치면 그 피해 +15% | 상시 | 10 |
| | broken 뼈 | SUMMONER_BONE | 소환수 최대 HP +50% | 상시 | 10 |
| | pierced 심장 ★ | **GNOLL_SUMMONER** | 동시에 부를 수 있는 소환수 +1, 소환수 피해 +50% | 상시 | 10 |
| 신전 시종 (새) | cut 손 | ACOLYTE_HAND | 전투 시작 때 파티 전원에게 보호(`ward`, 200 tick) | 전투 시작 | 12 |
| | broken 뼈 | ACOLYTE_BONE | 인접 동료가 쓰러질 피해를 받으면 대신 받음(전투당 1회) | 동료 위기 | 5 |
| | pierced 심장 ★ | ACOLYTE_HEART | 인접 동료의 체력이 25% 이하로 떨어지면 그 동료 HP 15% 회복(전투당 1회) | 동료 위기 | 12 |
| 미믹 (새) | cut 혀 | MIMIC_TONGUE | 급소 노출 대상에게 치명타 확률 추가 +25 | 상시 | 3 |
| | broken 이빨 ★ | MIMIC_TOOTH | 찌르기 공격의 급소 노출 확률 +10%p | 상시 | 3 |
| | pierced 핵 | MIMIC_CORE | 치명타로 처치하면 내 파츠 재사용 대기 −1 | 처치 | 3 |

### 3.4 구역 4

| 종족 | 부위 | 효과 id | 효과 | 발동 | 빌드군 |
| --- | --- | --- | --- | --- | --- |
| 해골 병사 | cut 팔 | SKELETON_ARM | 내가 거는 출혈 지속 +50% | 상시 | 1 |
| | broken 갈비뼈 ★ | **SKELETON_WALL** | 인접 동료가 받는 피해 −10% | 상시 | 5 |
| | pierced 두개골 | SKELETON_SKULL | 내가 처치한 적이 20% 확률로 해골 소환수로 일어남(300 tick) | 처치 | 11 |
| 해골 궁수 | cut 손가락 | BOWMAN_FINGER | 골절 중인 대상에게 주는 피해 +20% | 상시 | 2 |
| | broken 등뼈 ★ | **SKELETON_VOLLEY** | 치명타 확률 +15%, 치명타 피해 +50% | 상시 | 3 |
| | pierced 눈구멍 | BOWMAN_SOCKET | 원거리 명중이 형태와 관계없이 10% 확률로 골절 | 명중 | 2·6 |
| 구울 | cut 발톱 ★ | **GHOUL_CLAW** | 처치하면 최대 HP의 15% 회복 | 처치 | 4 |
| | broken 턱 | GHOUL_JAW | 내가 처치한 적이 1라운드 뒤 반경 1로 터짐(피해 = 그 적 최대 HP의 10%) | 처치 | 11 |
| | pierced 심장 | GHOUL_HEART | 해로운 상태가 걸린 적을 처치하면 HP 5% 회복 | 처치 | 11 |
| 흡혈 박쥐 | cut 날개 | VAMPIRE_WING | 이동한 뒤 첫 공격 피해 +20% | 상시 | 3 |
| | broken 이빨 ★ | **VAMPIRE_BITE** | 준 피해의 15%를 흡혈 | 명중 | 11 |
| | pierced 심장 | VAMPIRE_HEART | 흡혈로 HP가 넘치면 넘친 만큼 보호(최대 최대 HP의 20%, 300 tick) | 회복 | 11 |
| 망령 기사 | cut 망토 | WRAITH_KNIGHT_CLOAK | 근접 공격을 받으면 20% 확률로 공격자 약화 | 피격 | 8 |
| | broken 갑주 ★ | **THORN_ARMOUR** | 받은 근접 피해의 30% 반사 | 피격 | 5 |
| | pierced 핵 | WRAITH_KNIGHT_CORE | 골절을 걸 때 20% 확률로 기절 1라운드 | 부상 | 2 |
| 원혼 | cut 수의 | WRAITH_SHROUD | 해로운 상태가 걸린 적을 처치하면 그 상태들을 반경 2의 다른 적 하나에게 옮김 | 처치 | 8 |
| | broken 뼈 | WRAITH_BONE | 해로운 상태를 걸 때마다 HP 2 회복 | 상태 부여 | 8 |
| | pierced 핵 ★ | **WRAITH** | 공격에 20% 확률로 약화, 처치하면 반경 2 적 혼란 1라운드 | 명중·처치 | 8 |
| 묘지기 | cut 손 | GRAVEKEEPER_HAND | 내 소환수가 처치하면 내 HP 5% 회복 | 소환수 처치 | 10 |
| | broken 뼈 | GRAVEKEEPER_BONE | 내 소환수가 쓰러지면 그 자리에 반경 1 폭발(피해 10) | 소환 끝 | 10·11 |
| | pierced 등불 ★ | **GRAVEKEEPER** | 전투마다 한 번, 쓰러질 피해를 받으면 HP 30%로 일어남 | 치명상 | 11 |
| 뼈 직조공 (새) | cut 실 | WEAVER_THREAD | 내 첫 슬롯의 부위 효과를 내 소환수도 가짐 | 상시(code) | 10 |
| | broken 뼈 | WEAVER_BONE | 소환수 지속 +50% | 상시 | 10 |
| | pierced 핵 ★ | WEAVER_CORE | 내 소환수가 사라지거나 쓰러지면 MP +4 | 소환 끝 | 10 |
| 역병 좀비 (새) | cut 살점 | ZOMBIE_FLESH | 중독된 대상이 받는 회복 절반 | 상시 | 9 |
| | broken 뼈 | ZOMBIE_BONE | 반경 2 안의 적이 중독 피해를 입을 때마다 HP 1 회복 | 지속 피해 | 9·11 |
| | pierced 심장 ★ | ZOMBIE_HEART | 근접 공격을 받으면 20% 확률로 공격자 중독 | 피격 | 9 |

### 3.5 빌드군별 부품 수

| 빌드군 | 부품 | 대표 부품 |
| --- | --- | --- |
| 1 출혈 | 10 | RAT_INCISOR, HOUND_EAR, HOUND_NOSE, ORC_HIDE, RIVER_RAT_TOOTH, LEECH 셋, SKELETON_ARM |
| 2 분쇄 | 9 | SHIELD_HEART, HOB_JAW, THROWER_SHOULDER, 골렘 셋, BOWMAN_FINGER, BOWMAN_SOCKET, WRAITH_KNIGHT_CORE |
| 3 급소 | 11 | LIZARD_EYE, GOBLIN_EAR, GOBLIN_SHIV, SPIDER_LEG, GHOST_CHAIN, 미믹 셋, SKELETON_VOLLEY, VAMPIRE_WING |
| 4 광폭 | 10 | LIZARD_FRILL, HOB_HIDE, ORC_CLEAVER, ORC_HEART, SALAMANDER_TAIL·HEART, 놀 셋, GHOUL_CLAW |
| 5 수호 | 11 | LIZARD_TAIL, 방패병 둘, HOB_TAUNT, 딱정벌레 셋, SPIRIT_CURRENT, ACOLYTE_BONE, SKELETON_WALL, THORN_ARMOUR |
| 6 사수 | 9 | 코볼트 셋, 고블린 궁수 셋, ORC_THROW, THROWER_EYE, BOWMAN_SOCKET |
| 7 원소 | 11 | 화염술사 셋, BAT_BONE, SALAMANDER_SCALE·HEART, RIVER_RAT_SPLASH, SPIRIT_CURRENT, 서리 도깨비 셋 |
| 8 저주 | 11 | GOBLIN_TOOTH, 주술사 셋, THROWER_EYE, SPIDER_SHELL, SPIDER_WEB, WRAITH_KNIGHT_CLOAK, 원혼 셋 |
| 9 독 | 10 | SHROOM_CAP·SAC, 두꺼비 셋, SERPENT_SCALE·FANG, 좀비 셋 |
| 10 소환 | 9 | 놀 소환사 셋, GRAVEKEEPER_HAND·BONE, 뼈 직조공 셋 |
| 11 사령 | 11 | GHOST_HAND·CORE, SKELETON_SKULL, 구울 둘, VAMPIRE_BITE·HEART, GRAVEKEEPER, GRAVEKEEPER_BONE, ZOMBIE_BONE |
| 12 지원 | 12 | RAT_GNAW, RAT_HEART, HOUND_LEG, SHROOM_STEM, STORM_BAT, BAT_EAR, RIVER_RAT_HEART, SERPENT_SHED, SPIRIT_DROP, WATER_WAVE, ACOLYTE_HAND·HEART |

(두 빌드군에 걸친 부품은 양쪽에 센다.)

## 4. 완성 빌드 예시

영혼석 슬롯 10개(레벨 10) 기준. 설계 검증용이며 플레이어에게 보여 주는 목록이 아니다.

| 빌드 | 무기 | 부위 영혼석 | 도는 방식 |
| --- | --- | --- | --- |
| 피의 사냥꾼 | 도끼 | RAT_INCISOR, HOUND_EAR, HOUND_NOSE, ORC_HIDE, LEECH_SEGMENT, LEECH_SUCKER, SKELETON_ARM, RIVER_RAT_TOOTH, GHOUL_CLAW, ORC_CLEAVER | 도끼 휘말림까지 출혈(휘말린 적도 부상 판정, ①) → 출혈 대상에게 +20%·흡혈, 다시 걸면 터뜨림 → 처치하면 퍼짐, 처치 회복 |
| 뼈 부수는 자 | 철퇴 + 방패 | HOB_JAW, GOLEM_VEIN, ORE_SLAM, GOLEM_CORE, BOWMAN_FINGER, WRAITH_KNIGHT_CORE, SHIELD_HEART, SHIELD_STANCE, THROWER_SHOULDER, BEETLE_CURL | 골절·기절 → 움직이지 못하는 적에게 +30%, 막으면 공격자까지 골절 |
| 급소 사냥꾼 | 단검 | MIMIC_TOOTH, MIMIC_TONGUE, MIMIC_CORE, GOBLIN_EAR, GOBLIN_SHIV, SPIDER_LEG, SKELETON_VOLLEY, GHOST_CHAIN, LIZARD_EYE, VAMPIRE_WING | 급소 노출 → 치명타 확률 폭증 → 치명타가 속도·재사용으로 |
| 역병 술사 | 지팡이(저주) | SHROOM_CAP, SHROOM_SAC, TOAD_TONGUE, TOAD_SPIT, SERPENT_FANG, ZOMBIE_FLESH, ZOMBIE_BONE, GOBLIN_HEXER, HEXER_HAND, WRAITH_SHROUD | 중독 쌓기 + 저주 겹치기 → 처치 시 독 폭발·상태 전이, 중독 틱으로 회복 |
| 뼈 군단장 | 지팡이(소환) | GNOLL_SUMMONER, SUMMONER_HIDE, SUMMONER_BONE, WEAVER_THREAD, WEAVER_BONE, WEAVER_CORE, GRAVEKEEPER_HAND, GRAVEKEEPER_BONE, SKELETON_SKULL, GHOST_HAND | 소환수 늘리기 → 집중 공격 → 쓰러지면 폭발·MP 환급 → 처치한 적도 해골로 |
| 방벽 | 창 + 방패 | 딱정벌레 셋, SKELETON_WALL, ACOLYTE_BONE, ACOLYTE_HEART, SHIELD_STANCE, SHIELD_HIDE, THORN_ARMOUR, HOB_TAUNT | 맞을수록 방어 누적, 막으면 반격, 동료 위기 대신 맞기 |

## 5. 역할 조합 재조정

한 역할로 6개를 몰아넣는 것이 정답이 되지 않도록, **4개 구간이 효율이 가장 좋게** 바꾼다(구간 효과 내용은 [영혼석 개편](2026-09-26-soulstone-rework-design.md) §3 그대로, 수치만).

| 역할 | 2개 | 4개 | 6개 |
| --- | --- | --- | --- |
| 무리 | 공격력 +8% | 공격력 +18%, 동료 최대 HP +15% | 공격력 +22%, 처치 시 파티 HP 3% |
| 광폭 | 공격력 +12% | 공격력 +25%, 절반 이하 속도 +15% | 공격력 +30%, 처치 시 HP 6% |
| 기습 | 치명 +8 | 치명 +16, 치명 피해 +40% | 치명 +20, 치명 피해 +40%, 가득한 대상 항상 치명 |
| 수호 | 방어 +2 | 방어 +5, 막기 +10 | 방어 +6, 막기 +12, 인접 동료 −10% |
| 사수 | 사거리 +1 | 원거리 피해 +20% | 원거리 피해 +25%, 15% 추가 사격 |
| 술사 | 주문력 +12% | 주문력 +25%, 라운드마다 MP +2 | 주문력 +30%, 주문 실패 없음 |

- 원칙: 2→4는 크게, 4→6은 작게. 6개 구간의 고유 효과(항상 치명, 실패 없음)는 남겨 "몰아넣는 맛"은 유지한다.

## 6. 검토할 결정

1. 부위 이름(종족마다 셋)과 새 종족 8개의 이름·콘셉트.
2. 수치 전부(첫 값). 특히 GOLEM_VEIN(방어 완전 무시), GOBLIN_EAR(첫 공격 반드시 치명), GNOLL_BONE(외부 회복 불가)처럼 강한 효과.
3. 몬스터는 대표 부위(★) 하나만 쓴다(④ §4). 새 종족의 ★ 선택.
4. 역할 조합 재조정 수치(§5).
5. 보스 영혼석 3개(`GOBLIN_CHIEF`, `FURNACE_HEART`, `SOUL_EATER`)는 부위 없이 지금처럼 하나로 둔다.

## 구현 보정

`ACOLYTE_BONE`의 치명상 대신 맞기는 `ALLY_LETHAL`로, `ACOLYTE_HEART`의 위기 회복은 `ALLY_CRISIS`로 처리한다. 동일 타격의 보호 재지정은 한 번만 허용한다. 상태 처치 효과는 피해 직전 상태 스냅샷을 사용한다.
