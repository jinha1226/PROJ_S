# 공격·대기 영혼석 — 실행 매핑

2026-09-27 · `attack_wait_v1` · 일반 원정 기본 규칙

시작 화면 → **새 탐험**에서 공격·대기 규칙을 사용한다. 주인공·동료·NPC가 같은 규칙을 쓰며 몬스터는 기존 고유 기술을 유지한다. 화염·냉기·전기·주박·소환 시작 장비는 해당 영혼석의 자동 효과로 시작한다. 전투 시험에서도 **공격·대기 영혼석**을 선택하고 인물마다 0~6개를 구성할 수 있다. 기존 전투 시험과 명시적인 `legacy` 세션은 비교용으로 유지한다. 새 에셋 없이 기존 그림과 VFX를 사용한다.

실행 데이터는 개정 2다. 발동 문법은 다음 세 가지로 제한한다.

- **공격**: 공격 확정 또는 적중 시 효과가 작동한다. 빗나간 공격은 적중 효과를 만들지 않는다.
- **대기**: 의도적 대기 한 번으로 효과가 작동하거나 다음 공격·피격 효과를 준비한다. 연속 대기·조준 누적은 없다.
- **연쇄**: 공격·대기에 대상 상태 하나, 자신의 축복 또는 자기 소환수 존재 중 하나만 추가한다. 예: 화상 적중 → 폭발, 젖은 적중 → 연쇄 번개, 소환수와 함께 대기 → 강화.

체력 임계값, 이동·회피·막기·처치 이력, 무기 종류, 거리별 발동 조건, 서로 다른 상태 둘과 원소 피해의 동시 조건, 추가 발동 확률을 없앴다. 범위·사거리·유효 대상 판정과 기본 공격의 명중·회피·저항은 유지한다. 영혼석 효과는 MP나 추가 행동을 소비하지 않는다. 영혼석 6칸·영구 흡수·기존 부위와 변형 연결도 유지한다.

공격의 접근 이동은 발동하지 않으며, 강제 대기도 대기 효과를 만들지 않는다. 상태 부여를 먼저 처리한 뒤 연쇄를 판정하며, 추가타가 다시 기본 적중을 만들지 않는다. 새로 생긴 빙결을 같은 공격에서 즉시 파쇄하지 않으며 중복 파쇄로 같은 빙결을 두 번 소비하지 않는다. 행동당 발동 한도와 비상 큐 한도는 별개다.

대기 방어는 다음 합법적인 자기 행동까지 유지하고 같은 종류끼리 중첩하지 않는다. 피격 반응은 유효 직접 피격에 한 번 확정 발동한다. 전기막은 재사용 3턴이며 적의 기존 저항·재봉쇄 면역을 따른다. 대기 유인은 한 번으로 일정한 위협 보정만 주며 이미 보이는 적의 선택에만 영향을 준다.

치유는 HP가 최대치보다 낮은 아군 중 가장 낮은 HP 비율을 선택한다. 강한 대기 치유는 조우당 2회·재사용 3턴이며 시야 이탈로 횟수가 복원되지 않는다. 소환은 공용 한도 1명·빈 인접 칸·재사용 3턴을 사용한다. 소환수 강화·연장은 소환수가 있다는 조건 하나만 확인한다. 호위는 실제 피해 대신 받기 경로를 사용한다.

공격·대기 아이콘, 공격 준비·유인·치유 잔여 횟수, 영혼석 요약·흡수 카드·연계 적합성은 같은 실행 데이터를 읽는다. 중복된 조건 설명과 별도 반응 묶음을 없앴다. NPC Utility AI도 같은 조건과 효과 가치를 읽으며 예측은 RNG·상태를 변경하지 않는다. 상태 갱신이 실패해도 실제 피해가 발생한 효과는 발동·기여·표시를 기록한다.

수치는 초기 시험값이다. 테스트 통과는 모바일 재미·층 전체 밸런스 검증을 의미하지 않는다. 일반 원정에 적용했으며 실제 모바일 플레이로 확인한다. MP·수동 기술 버튼은 일반 원정 HUD와 상태 수치에서 숨긴다. 장비의 주문력은 공격력으로, 최대 MP는 두 배의 최대 HP로 읽으며 감소 속성도 같은 비율로 적용한다. 지팡이 집중 +4·오브 +3·마력 반지 +5는 일반 공격력으로 계산한다. MP 회복 장비는 같은 양의 HP 회복, 오브의 최대 MP 감소 대가는 최대 HP 감소로 바꾼다. 재충전 두루마리는 영혼석 재사용 대기만 해제하며 조우당 사용 한도는 복원하지 않는다. 가방·장비 미리보기에도 같은 수치를 표시하고 기존 규칙의 원본 데이터는 보존한다.

## 영혼석 고정 보상

새 프로필의 인물·동료·NPC에게 같은 표를 적용한다. 변형 영혼석의 기존 속성 저항은 유지한다. 보상에 MP와 주문력을 추가하지 않으며 능력치 계산·흡수 전 상세·효과 요약이 같은 표를 읽는다. 드롭·영구 흡수·교체 제한은 변경하지 않는다.

| 역할 | 고정 보상 |
| --- | --- |
| 서포터 | 최대 HP +16 |
| 근접 딜러 | 공격력 +4 · 최대 HP +8 |
| 탱커 | 최대 HP +20 · 방어 +3 |
| 원거리 딜러 | 공격력 +3 · 행동 속도 +5% |
| 캐스터 | 공격력 +2 · 최대 HP +12 |

## 부위별 효과

이 표는 `data/content/attack_wait_effects.json`에서 내보낸다. 한 행이 실제 효과 하나이며 계열은 피해 타입 추가를 뜻하지 않는다.

| 부위 ID | 이름 | 역할 | 계열 | 사건 | 효과 | 재사용/횟수 |
| --- | --- | --- | --- | --- | --- | --- |
| `RAT_GNAW/cut` | 쥐 꼬리 | 방어형 | bless | 대기 | 대기 시 주변 2칸 아군 보호 | — |
| `RAT_GNAW/cut@air` | 쥐 꼬리 · air | 공격형 | air | 적중 | 적중 시 전하·전기 피해 | — |
| `RAT_GNAW/cut@will` | 쥐 꼬리 · will | 연쇄형 | bless | 적중 | 축복 중 적중 시 보호 | — |
| `RAT_GNAW/cut@bleed` | 쥐 꼬리 · bleed | 공격형 | bleed | 대기 | 대기 시 1칸 출혈 | — |
| `RAT_GNAW/broken` | 쥐 앞니 | 공격형 | bleed | 적중 | 적중 시 출혈 | — |
| `RAT_GNAW/pierced` | 쥐 심장 | 연쇄형 | bless | 적중 | 축복 중 공격 시 주변 아군 HP 2 회복 | — |
| `LIZARD_TAIL/cut` | 목도리 도마뱀 꼬리 | 공격형 | evasion | 적중 | 적중 시 추가타 | — |
| `LIZARD_TAIL/cut@air` | 목도리 도마뱀 꼬리 · air | 연쇄형 | air | 적중 | 전하 상태의 적 공격 시 주변에 전하 전이 | — |
| `LIZARD_TAIL/cut@will` | 목도리 도마뱀 꼬리 · will | 방어형 | vital | 대기 | 대기 시 받는 피해 20% 감소 | — |
| `LIZARD_TAIL/broken` | 목도리 도마뱀 목도리 | 공격형 | reflect | 적중 | 적중 후 다음 직접 피격 반사 | — |
| `LIZARD_TAIL/pierced` | 목도리 도마뱀 눈 | 공격형 | wind | 대기 | 대기 후 다음 공격 피해 +20% | — |
| `KOBOLD_SLING/cut` | 코볼트 가죽 | 방어형 | evasion | 대기 | 대기 시 회피 +10 | — |
| `KOBOLD_SLING/broken` | 코볼트 손뼈 | 공격형 | rapid | 적중 | 기본 적중 후 추가타 | — |
| `KOBOLD_SLING/broken@air` | 코볼트 손뼈 · air | 공격형 | wind | 대기 | 대기 후 다음 공격 돌풍 | — |
| `KOBOLD_SLING/broken@bleed` | 코볼트 손뼈 · bleed | 공격형 | rapid | 대기 | 대기 후 다음 공격 연타 | — |
| `KOBOLD_SLING/pierced` | 코볼트 심장 | 공격형 | focus | 대기 | 대기 후 다음 공격 피해 +20% | — |
| `GOBLIN_SHIV/cut` | 고블린 귀 | 연쇄형 | vital | 적중 | 약점 상태의 적 공격 시 추가 피해 4 | — |
| `GOBLIN_SHIV/broken` | 고블린 이빨 | 연쇄형 | hex | 적중 | 약화 적중 시 취약 | — |
| `GOBLIN_SHIV/pierced` | 고블린 심장 | 공격형 | vital | 적중 | 적중 시 약점 표식 | — |
| `ORC_CLEAVER/cut` | 오크 가죽 | 연쇄형 | bleed | 적중 | 출혈 적중 시 추가타 | — |
| `ORC_CLEAVER/broken` | 오크 뼈 | 공격형 | rapid | 대기 | 대기 후 다음 공격 연타 | — |
| `ORC_CLEAVER/pierced` | 오크 심장 | 방어형 | fury | 대기 | 대기 시 받는 피해 25% 감소 | — |
| `GNOLL_SPEAR/cut` | 놀 가죽 | 공격형 | fury | 적중 | 적중 시 HP 2 회복 | — |
| `GNOLL_SPEAR/broken` | 놀 뼈 | 방어형 | regen | 대기 | 대기 시 부상 재생 · 재사용 3턴 | 3턴 |
| `GNOLL_SPEAR/pierced` | 놀 심장 | 공격형 | fury | 공격 확정 | 공격 시 피해 +15% | — |
| `RIVER_RAT_SPLASH/cut` | 강쥐 꼬리 | 공격형 | water | 적중 | 적중 시 젖음 | — |
| `RIVER_RAT_SPLASH/cut@fire` | 강쥐 꼬리 · fire | 방어형 | fire | 대기 | 대기 후 인접 피격 시 화염막 | — |
| `RIVER_RAT_SPLASH/cut@ice` | 강쥐 꼬리 · ice | 연쇄형 | water | 적중 | 젖은 적 공격 시 빙결 | — |
| `RIVER_RAT_SPLASH/cut@air` | 강쥐 꼬리 · air | 연쇄형 | water | 적중 | 젖은 적 공격 시 최대 4명 연쇄 번개 | — |
| `RIVER_RAT_SPLASH/broken` | 강쥐 이빨 | 방어형 | bleed | 대기 | 대기 후 인접 피격 시 출혈 | — |
| `RIVER_RAT_SPLASH/pierced` | 강쥐 심장 | 방어형 | water | 대기 | 대기 시 화염 저항 +30 | — |
| `FIRE_CALLER/cut` | 코볼트 화염술사 손 | 연쇄형 | fire | 적중 | 화상 적중 시 주변 폭발 | — |
| `FIRE_CALLER/broken` | 코볼트 화염술사 뼈 | 공격형 | fire | 대기 | 대기 시 3칸 화상 | — |
| `FIRE_CALLER/pierced` | 코볼트 화염술사 심장 | 공격형 | fire | 적중 | 적중 시 화상 | — |
| `FIRE_CALLER/pierced@poison` | 코볼트 화염술사 심장 · poison | 연쇄형 | fire | 적중 | 중독 상태의 적 공격 시 주변 독성 폭발 | — |
| `FIRE_CALLER/pierced@will` | 코볼트 화염술사 심장 · will | 방어형 | mental | 대기 | 대기 시 의지 저항 +30 | — |
| `FROST_IMP/cut` | 서리 도깨비 발톱 | 연쇄형 | ice | 적중 | 둔화 적중 시 빙결 | — |
| `FROST_IMP/broken` | 서리 도깨비 뿔 | 공격형 | ice | 대기 | 대기 시 3칸 둔화 | — |
| `FROST_IMP/pierced` | 서리 도깨비 심장 | 공격형 | ice | 적중 | 적중 시 둔화 | — |
| `STORM_BAT/cut` | 폭풍 박쥐 날개 | 공격형 | air | 대기 | 대기 시 4칸 전하 | — |
| `STORM_BAT/cut@fire` | 폭풍 박쥐 날개 · fire | 공격형 | fire | 대기 | 대기 시 3칸 화상 | — |
| `STORM_BAT/cut@ice` | 폭풍 박쥐 날개 · ice | 공격형 | water | 대기 | 대기 시 3칸 젖음 | — |
| `STORM_BAT/cut@will` | 폭풍 박쥐 날개 · will | 공격형 | mental | 대기 | 대기 시 4칸 혼란 | — |
| `STORM_BAT/cut@bleed` | 폭풍 박쥐 날개 · bleed | 공격형 | wind | 적중 | 적중 시 밀치기 | — |
| `STORM_BAT/broken` | 폭풍 박쥐 뼈 | 연쇄형 | air | 적중 | 전하 적중 시 최대 3명 연쇄 | — |
| `STORM_BAT/pierced` | 폭풍 박쥐 귀 | 방어형 | air | 대기 | 대기 후 피격 시 공격자 마비 · 재사용 3턴 | 3턴 |
| `GOBLIN_HEXER/cut` | 고블린 주술사 손 | 공격형 | hex | 적중 | 적중 시 약화 | — |
| `GOBLIN_HEXER/broken` | 고블린 주술사 두개골 | 연쇄형 | hex | 적중 | 약화 상태의 적 공격 시 정신 피해 | — |
| `GOBLIN_HEXER/pierced` | 고블린 주술사 눈 | 공격형 | hex | 대기 | 대기 시 3칸 약화 | — |
| `GNOLL_SUMMONER/cut` | 놀 소환사 가죽 | 연쇄형 | summon | 대기 | 소환수가 있으면 대기 시 다음 소환수 공격 강화 | — |
| `GNOLL_SUMMONER/broken` | 놀 소환사 뼈 | 방어형 | summon | 대기 | 대기 시 호위 소환수 · 공용 한도 1 | 3턴 · 소환 1명 |
| `GNOLL_SUMMONER/pierced` | 놀 소환사 심장 | 공격형 | summon | 대기 | 대기 시 사냥개 · 최대 1 · 재사용 3턴 | 3턴 · 소환 1명 |
| `GNOLL_SUMMONER/pierced@air` | 놀 소환사 심장 · air | 연쇄형 | summon | 적중 | 소환수가 있으면 공격 시 목표 집중 | — |
| `HOB_TAUNT/cut` | 홉고블린 가죽 | 공격형 | defense | 적중 | 적중 시 다음 피격 보호 | — |
| `HOB_TAUNT/broken` | 홉고블린 턱뼈 | 공격형 | crush | 적중 | 적중 시 밀치기 · 벽 충돌 피해 | — |
| `HOB_TAUNT/pierced` | 홉고블린 심장 | 방어형 | defense | 대기 | 대기 시 적의 시선 끌기 | — |
| `GOBLIN_AIM/cut` | 고블린 궁수 깃 | 공격형 | focus | 적중 | 적중 시 추가 피해 3 | — |
| `GOBLIN_AIM/broken` | 고블린 궁수 손가락뼈 | 연쇄형 | focus | 적중 | 약점 상태의 적 공격 시 추가타 | — |
| `GOBLIN_AIM/pierced` | 고블린 궁수 눈 | 방어형 | focus | 대기 | 대기 시 회피 +15 | — |
| `SHIELD_STANCE/cut` | 고블린 방패병 가죽 | 공격형 | defense | 공격 확정 | 공격 시 피해 +10% | — |
| `SHIELD_STANCE/broken` | 고블린 방패병 팔뼈 | 방어형 | defense | 대기 | 대기 시 직접 피해 20% 감소 | — |
| `SHIELD_STANCE/pierced` | 고블린 방패병 심장 | 연쇄형 | bless | 적중 | 축복 중 공격 시 주변 아군 보호 | — |
| `ORC_THROW/cut` | 오크 투척병 팔 | 공격형 | volley | 적중 | 적중 시 추가타 | — |
| `ORC_THROW/cut@air` | 오크 투척병 팔 · air | 연쇄형 | wind | 적중 | 둔화된 적 공격 시 추가타 | — |
| `ORC_THROW/broken` | 오크 투척병 어깨뼈 | 연쇄형 | crush | 적중 | 약점 상태의 적 공격 시 추가 피해 3 | — |
| `ORC_THROW/pierced` | 오크 투척병 눈 | 연쇄형 | volley | 적중 | 약점 상태의 적 공격 시 추가타 | — |
| `SPIDER_WEB/cut` | 동굴 거미 다리 | 방어형 | rapid | 적중 | 적중 후 회피 +10 | — |
| `SPIDER_WEB/broken` | 동굴 거미 껍질 | 연쇄형 | mental | 적중 | 혼란 적중 시 정신 피해 | — |
| `SPIDER_WEB/pierced` | 동굴 거미 실샘 | 공격형 | mental | 적중 | 적중 시 혼란 | — |
| `BEETLE_CURL/cut` | 바위 딱정벌레 날개 | 방어형 | crush | 대기 | 대기 후 밀치기 저항 | — |
| `BEETLE_CURL/broken` | 바위 딱정벌레 껍질 | 방어형 | ice | 대기 | 대기 시 방어 +4 | — |
| `BEETLE_CURL/pierced` | 바위 딱정벌레 핵 | 방어형 | regen | 대기 | 대기 시 HP 재생 · 재사용 3턴 | 3턴 |
| `ORE_SLAM/cut` | 광석 골렘 광맥 | 연쇄형 | ice | 적중 | 빙결 상태의 적 공격 시 파쇄 | — |
| `ORE_SLAM/broken` | 광석 골렘 몸돌 | 공격형 | crush | 대기 | 대기 후 다음 공격 강타 | — |
| `ORE_SLAM/pierced` | 광석 골렘 핵 | 연쇄형 | ice | 적중 | 기존 빙결 적중 시 파쇄 | — |
| `LEECH_LATCH/cut` | 거대 거머리 입 | 공격형 | bleed | 대기 | 대기 후 다음 공격 출혈 | — |
| `LEECH_LATCH/broken` | 거대 거머리 몸마디 | 연쇄형 | fire | 적중 | 출혈 상태의 적 공격 시 추가 화염 피해 | — |
| `LEECH_LATCH/pierced` | 거대 거머리 흡반 | 공격형 | heal | 적중 | 실제 피해 15% 회복 · 최대 4 | 최대 4 |
| `TOAD_SPIT/cut` | 늪 두꺼비 혀 | 연쇄형 | poison | 적중 | 중독 적중 시 주변 전이 | — |
| `TOAD_SPIT/broken` | 늪 두꺼비 뼈 | 방어형 | poison | 대기 | 대기 후 인접 피격 시 중독 | — |
| `TOAD_SPIT/pierced` | 늪 두꺼비 독샘 | 공격형 | poison | 적중 | 적중 시 중독 | — |
| `SERPENT_SHED/cut` | 신전 뱀 허물 | 방어형 | heal | 대기 | 대기 시 주변 아군 상태이상 1개 해제 | — |
| `SERPENT_SHED/broken` | 신전 뱀 비늘 | 공격형 | poison | 대기 | 대기 시 4칸 중독 | — |
| `SERPENT_SHED/pierced` | 신전 뱀 독니 | 연쇄형 | poison | 적중 | 중독 상태의 적 공격 시 주변 중독 연장 | — |
| `WATER_WAVE/cut` | 물의 정령 물살 | 방어형 | water | 대기 | 대기 시 받는 피해 20% 감소 | — |
| `WATER_WAVE/broken` | 물의 정령 물방울 | 방어형 | heal | 대기 | 대기 시 받는 피해 20% 감소 | — |
| `WATER_WAVE/pierced` | 물의 정령 핵 | 방어형 | heal | 대기 | 대기 시 주변 아군 HP 8 회복 · 전투당 2회 · 재사용 3턴 | 3턴 · 조우당 2회 |
| `SKELETON_WALL/cut` | 해골 병사 팔 | 연쇄형 | bless | 대기 | 소환수가 있으면 대기 시 소환수 축복 | — |
| `SKELETON_WALL/broken` | 해골 병사 갈비뼈 | 연쇄형 | death | 대기 | 소환수가 있으면 대기 시 피해 분담 | — |
| `SKELETON_WALL/pierced` | 해골 병사 두개골 | 연쇄형 | death | 적중 | 낙인 상태의 적 공격 시 해골 소환 · 최대 1 · 재사용 3턴 | 3턴 · 소환 1명 |
| `SKELETON_VOLLEY/cut` | 해골 궁수 손가락 | 연쇄형 | water | 적중 | 젖은 적 공격 시 최대 4명 연쇄 번개 | — |
| `SKELETON_VOLLEY/broken` | 해골 궁수 등뼈 | 방어형 | volley | 대기 | 대기 시 회피 +10 | — |
| `SKELETON_VOLLEY/pierced` | 해골 궁수 눈구멍 | 연쇄형 | water | 적중 | 젖은 적 공격 시 빙결 | — |
| `GHOUL_CLAW/cut` | 구울 발톱 | 연쇄형 | bleed | 적중 | 출혈 상태의 적 공격 시 HP 2 회복 | — |
| `GHOUL_CLAW/broken` | 구울 턱 | 연쇄형 | fire | 적중 | 화상 상태의 적 공격 시 주변에 화상 전이 | — |
| `GHOUL_CLAW/pierced` | 구울 심장 | 연쇄형 | fire | 적중 | 중독 상태의 적 공격 시 주변 독성 폭발 | — |
| `VAMPIRE_BITE/cut` | 흡혈 박쥐 날개 | 공격형 | evasion | 공격 확정 | 공격 시 피해 +10% | — |
| `VAMPIRE_BITE/broken` | 흡혈 박쥐 이빨 | 공격형 | regen | 적중 | 실제 피해 후 HP 2 재생 | 3턴 |
| `VAMPIRE_BITE/pierced` | 흡혈 박쥐 심장 | 공격형 | reflect | 적중 | 적중 시 HP 2 회복 | — |
| `THORN_ARMOUR/cut` | 망령 기사 망토 | 방어형 | hex | 대기 | 대기 후 피격 시 공격자 약화 | — |
| `THORN_ARMOUR/broken` | 망령 기사 갑주 | 방어형 | reflect | 대기 | 대기 후 피격 피해 30% 반사 | — |
| `THORN_ARMOUR/broken@air` | 망령 기사 갑주 · air | 방어형 | wind | 대기 | 대기 시 회피 +15 | — |
| `THORN_ARMOUR/pierced` | 망령 기사 핵 | 방어형 | wind | 대기 | 대기 시 회피 +10 | — |
| `WRAITH/cut` | 원혼 수의 | 연쇄형 | hex | 적중 | 약화 상태의 적 공격 시 주변에 약화 전이 | — |
| `WRAITH/broken` | 원혼 뼈 | 연쇄형 | death | 적중 | 낙인 상태의 적 공격 시 추가 정신 피해 3 | — |
| `WRAITH/pierced` | 원혼 핵 | 공격형 | death | 적중 | 적중 시 사령 낙인·정신 피해 | — |
| `WRAITH/pierced@will` | 원혼 핵 · will | 연쇄형 | mental | 적중 | 혼란 상태의 적 공격 시 다음 공격 강화 | — |
| `GRAVEKEEPER/cut` | 묘지기 손 | 연쇄형 | summon | 대기 | 소환수가 있으면 대기 시 지속 +1턴 · 재사용 3턴 | 3턴 |
| `GRAVEKEEPER/broken` | 묘지기 뼈 | 연쇄형 | death | 적중 | 낙인 상태의 적 공격 시 주변에 약화 | — |
| `GRAVEKEEPER/pierced` | 묘지기 등불 | 공격형 | death | 대기 | 대기 시 해골 · 최대 1 · 재사용 3턴 | 3턴 · 소환 1명 |
| `GRAVEKEEPER/pierced@poison` | 묘지기 등불 · poison | 공격형 | poison | 대기 | 대기 시 4칸 중독 | — |
| `GOBLIN_CHIEF` | 족장의 뿔나팔 | 공격형 | bless | 적중 | 적중 후 다음 공격 축복 | — |
| `FURNACE_HEART` | 용광로 심장 | 방어형 | fire | 대기 | 대기 후 인접 피격 시 화염막 | — |
| `SOUL_EATER` | 포식자의 핵 | 방어형 | mental | 대기 | 대기 시 의지 저항 +30 | — |

## 검증

이번 개정은 변경 영역의 세 검사만 실행했다. `tests/attack_wait.gd` 432항목, `tests/stone_drop.gd` 38항목, `tests/attack_wait_ui.gd` 23항목이 통과했다. 무조건 공격·이동 이력 없는 밀치기·무기 종류와 무관한 추가타·체력 임계값 없는 치유·한 번의 대기로 소환 및 강화·고정 위협·확정 피격 반응·연쇄 조건 하나·카드의 연계 판단을 확인했다. 기본 명중·상태 면역·강제 대기·사용 한도·소환 한도·UI와 보상 매핑 검사도 포함한다. 이 결과는 실제 모바일 재미나 원정 누적 밸런스의 확정을 뜻하지 않는다.

원인 행동/부모 이벤트/주체/규칙/대상 기록은 `session.aw_trace`, 비상 한도 발생은 `aw_overflows`, 효과 기여 집계는 `battle_stats.members`에서 확인한다. 발동 설명 팝업은 추가하지 않았다.
