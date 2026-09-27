# 공격·대기 영혼석 — 실행 매핑

2026-09-27 · `attack_wait_v1` · 일반 원정 기본 규칙

시작 화면 → **새 탐험**에서 공격·대기 규칙을 사용한다. 주인공·동료·NPC가 같은 규칙을 쓰며 몬스터는 기존 고유 기술을 유지한다. 화염·냉기·전기·주박·소환 시작 장비는 해당 영혼석의 자동 효과로 시작한다. 전투 시험에서도 **공격·대기 영혼석**을 선택하고 인물마다 0~6개를 구성할 수 있다. 기존 전투 시험과 명시적인 `legacy` 세션은 비교용으로 유지한다. 새 에셋 없이 기존 그림과 VFX를 사용한다.

주인공은 이동·공격·대기를 직접 선택한다. 공격의 접근 이동은 발동하지 않으며, 의도적 대기만 대기 효과를 만든다. 영혼석 효과는 MP와 추가 행동을 소비하지 않는다. 상태 부여를 먼저 처리한 뒤 연쇄를 판정하며, 추가타는 다시 기본 적중을 발행하지 않는다. 효과별 행동당 한도와 비상 큐 한도를 구분한다.

원소 연결은 해당 영혼석이 있을 때만 실행한다. 전하 공격에는 명시적 전기 피해 2가 포함되어 물+전기 연결을 활성화한다. 상태 갱신이 없어도 실제 피해가 발생하면 발동·기여·표시를 기록한다. 상태 변화와 피해가 모두 없으면 기록하지 않는다. 물/지형의 젖음과 기존 환경 갱신은 유지하지만 새 효과는 기존 자동 독성 폭발·파쇄·지형 방전을 동시에 실행하지 않는다. 몬스터의 기존 대표 효과는 기존 반응 정책이다.

대기 방어는 다음 합법적인 자기 행동까지 유지한다. 피격 준비는 유효 직접 피격에 1회 시도하고 확률 실패에도 소비한다. 자세 감소는 중첩하지 않는다. 빙결·기절 재적용은 정상 행동 기회를 얻기 전까지 막는다. 새 규칙에서 부여한 혼란은 물리 공격 명중을 20%p 낮추며 진영과 행동 횟수를 바꾸지 않는다. 위협은 이미 보이는 대상의 다음 선택 점수만 보정한다.

치유는 부상한 실제 아군 중 가장 낮은 HP 비율을 선택하며 강한 대기 치유는 70% 이하·조우당 2회·재사용 3턴이다. 동일 적의 시야 이탈로 횟수가 복원되지 않는다. 소환은 공용 한도 1명·빈 인접 칸·재사용 3턴을 사용한다. 호위는 실제 피해 대신 받기 경로를 사용하며 자연 만료는 사망 연쇄를 만들지 않는다.

공격/대기 아이콘, 준비·위협·조준·치유 잔여 횟수, 흡수한 효과 요약과 상세 조건은 같은 실행 데이터를 읽는다. 새 프로필에서 MP·수동 주문 바는 기본 HUD에 표시하지 않는다. NPC Utility AI는 효과의 예상 가치를 읽고 소환수 목표 집중은 다음 정상 행동에 적용한다. 확률 예측에서 RNG와 상태를 변경하지 않는다.

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

이 표는 `data/content/attack_wait_effects.json`에서 내보낸다. 같은 영혼석이 역할 세 개를 모두 주지 않는다. 한 행이 실제 효과 하나이며 계열은 피해 타입 추가를 뜻하지 않는다.

| 부위 ID | 이름 | 역할 | 계열 | 사건 | 효과 | 재사용/횟수 |
| --- | --- | --- | --- | --- | --- | --- |
| `RAT_GNAW/cut` | 쥐 꼬리 | 방어형 | bless | 대기 | 대기 시 주변 2칸 아군 보호 | — |
| `RAT_GNAW/cut@air` | 쥐 꼬리 · air | 공격형 | air | 적중 | 적중 시 전하·전기 피해 | — |
| `RAT_GNAW/cut@will` | 쥐 꼬리 · will | 연쇄형 | bless | 적중 | 축복 중 적중 시 보호 | — |
| `RAT_GNAW/cut@bleed` | 쥐 꼬리 · bleed | 공격형 | bleed | 대기 | 대기 시 1칸 출혈 | — |
| `RAT_GNAW/broken` | 쥐 앞니 | 공격형 | bleed | 적중 | 적중 시 출혈 | — |
| `RAT_GNAW/pierced` | 쥐 심장 | 연쇄형 | bless | 처치 | 축복 중 처치 시 부상 아군 회복 | — |
| `LIZARD_TAIL/cut` | 목도리 도마뱀 꼬리 | 연쇄형 | evasion | 회피 | 실제 회피 후 반격 | — |
| `LIZARD_TAIL/cut@air` | 목도리 도마뱀 꼬리 · air | 연쇄형 | air | 처치 | 전하 적 처치 시 표식 전이 | — |
| `LIZARD_TAIL/cut@will` | 목도리 도마뱀 꼬리 · will | 방어형 | vital | 회피 | 약점 대상 회피 시 보호 | — |
| `LIZARD_TAIL/broken` | 목도리 도마뱀 목도리 | 공격형 | reflect | 적중 | 적중 후 다음 직접 피격 반사 | — |
| `LIZARD_TAIL/pierced` | 목도리 도마뱀 눈 | 연쇄형 | wind | 회피 | 회피 후 다음 공격 +20% | — |
| `KOBOLD_SLING/cut` | 코볼트 가죽 | 방어형 | evasion | 이동 | 이동 후 다음 피격 회피 +10 | — |
| `KOBOLD_SLING/broken` | 코볼트 손뼈 | 공격형 | rapid | 적중 | 기본 적중 후 추가타 | — |
| `KOBOLD_SLING/broken@air` | 코볼트 손뼈 · air | 공격형 | wind | 대기 | 대기 후 다음 공격 돌풍 | — |
| `KOBOLD_SLING/broken@bleed` | 코볼트 손뼈 · bleed | 공격형 | rapid | 대기 | 대기 후 다음 공격 연타 | — |
| `KOBOLD_SLING/pierced` | 코볼트 심장 | 공격형 | focus | 대기 | 대기 시 조준 +1 · 최대 3 · 이동 시 해제 | — |
| `GOBLIN_SHIV/cut` | 고블린 귀 | 연쇄형 | vital | 공격 확정 | 약점 대상 다음 공격 강화 | — |
| `GOBLIN_SHIV/broken` | 고블린 이빨 | 연쇄형 | hex | 적중 | 약화 적중 시 취약 | — |
| `GOBLIN_SHIV/pierced` | 고블린 심장 | 공격형 | vital | 적중 | 적중 시 약점 표식 | — |
| `ORC_CLEAVER/cut` | 오크 가죽 | 연쇄형 | bleed | 적중 | 출혈 적중 시 추가타 | — |
| `ORC_CLEAVER/broken` | 오크 뼈 | 공격형 | rapid | 대기 | 대기 후 다음 공격 연타 | — |
| `ORC_CLEAVER/pierced` | 오크 심장 | 방어형 | fury | 대기 | HP 35% 이하 대기 시 직접 피해 25% 감소 | — |
| `GNOLL_SPEAR/cut` | 놀 가죽 | 연쇄형 | fury | 처치 | HP 35% 이하 처치 시 회복 | — |
| `GNOLL_SPEAR/broken` | 놀 뼈 | 방어형 | regen | 대기 | 대기 시 부상 재생 · 재사용 3턴 | 3턴 |
| `GNOLL_SPEAR/pierced` | 놀 심장 | 공격형 | fury | 공격 확정 | HP 35% 이하 공격 +25% | — |
| `RIVER_RAT_SPLASH/cut` | 강쥐 꼬리 | 공격형 | water | 적중 | 적중 시 젖음 | — |
| `RIVER_RAT_SPLASH/cut@fire` | 강쥐 꼬리 · fire | 방어형 | fire | 대기 | 대기 후 인접 피격 시 화염막 | — |
| `RIVER_RAT_SPLASH/cut@ice` | 강쥐 꼬리 · ice | 연쇄형 | water | 적중 | 젖은 둔화 대상 적중 시 빙결 | — |
| `RIVER_RAT_SPLASH/cut@air` | 강쥐 꼬리 · air | 연쇄형 | water | 적중 | 젖은 전기 적중 시 최대 4명 연쇄 | — |
| `RIVER_RAT_SPLASH/broken` | 강쥐 이빨 | 방어형 | bleed | 대기 | 대기 후 인접 피격 시 출혈 | — |
| `RIVER_RAT_SPLASH/pierced` | 강쥐 심장 | 방어형 | water | 대기 | 대기 시 화염 저항 +30 | — |
| `FIRE_CALLER/cut` | 코볼트 화염술사 손 | 연쇄형 | fire | 적중 | 화상 적중 시 주변 폭발 | — |
| `FIRE_CALLER/broken` | 코볼트 화염술사 뼈 | 공격형 | fire | 대기 | 대기 시 3칸 화상 | — |
| `FIRE_CALLER/pierced` | 코볼트 화염술사 심장 | 공격형 | fire | 적중 | 적중 시 화상 | — |
| `FIRE_CALLER/pierced@poison` | 코볼트 화염술사 심장 · poison | 연쇄형 | fire | 적중 | 화상·중독 적중 시 독성 폭발 | — |
| `FIRE_CALLER/pierced@will` | 코볼트 화염술사 심장 · will | 방어형 | mental | 대기 | 대기 시 의지 저항 +30 | — |
| `FROST_IMP/cut` | 서리 도깨비 발톱 | 연쇄형 | ice | 적중 | 둔화 적중 시 빙결 | — |
| `FROST_IMP/broken` | 서리 도깨비 뿔 | 공격형 | ice | 대기 | 대기 시 3칸 둔화 | — |
| `FROST_IMP/pierced` | 서리 도깨비 심장 | 공격형 | ice | 적중 | 적중 시 둔화 | — |
| `STORM_BAT/cut` | 폭풍 박쥐 날개 | 공격형 | air | 대기 | 대기 시 4칸 전하 | — |
| `STORM_BAT/cut@fire` | 폭풍 박쥐 날개 · fire | 공격형 | fire | 대기 | 대기 시 3칸 화상 | — |
| `STORM_BAT/cut@ice` | 폭풍 박쥐 날개 · ice | 공격형 | water | 대기 | 대기 시 3칸 젖음 | — |
| `STORM_BAT/cut@will` | 폭풍 박쥐 날개 · will | 공격형 | mental | 대기 | 대기 시 4칸 혼란 | — |
| `STORM_BAT/cut@bleed` | 폭풍 박쥐 날개 · bleed | 공격형 | wind | 적중 | 이동 후 첫 적중 시 밀치기 | — |
| `STORM_BAT/broken` | 폭풍 박쥐 뼈 | 연쇄형 | air | 적중 | 전하 적중 시 최대 3명 연쇄 | — |
| `STORM_BAT/pierced` | 폭풍 박쥐 귀 | 방어형 | air | 대기 | 대기 후 피격 시 15% 마비 | — |
| `GOBLIN_HEXER/cut` | 고블린 주술사 손 | 공격형 | hex | 적중 | 적중 시 약화 | — |
| `GOBLIN_HEXER/broken` | 고블린 주술사 두개골 | 연쇄형 | hex | 적중 | 약화·혼란 적중 시 정신 피해 | — |
| `GOBLIN_HEXER/pierced` | 고블린 주술사 눈 | 공격형 | hex | 대기 | 대기 시 3칸 약화 | — |
| `GNOLL_SUMMONER/cut` | 놀 소환사 가죽 | 연쇄형 | summon | 소환수 적중 | 주인과 같은 적 적중 후 소환수 강화 | — |
| `GNOLL_SUMMONER/broken` | 놀 소환사 뼈 | 방어형 | summon | 대기 | 대기 시 호위 소환수 · 공용 한도 1 | 3턴 · 소환 1명 |
| `GNOLL_SUMMONER/pierced` | 놀 소환사 심장 | 공격형 | summon | 대기 | 대기 시 사냥개 · 최대 1 · 재사용 3턴 | 3턴 · 소환 1명 |
| `GNOLL_SUMMONER/pierced@air` | 놀 소환사 심장 · air | 공격형 | summon | 적중 | 적중 시 소환수 목표 집중 | — |
| `HOB_TAUNT/cut` | 홉고블린 가죽 | 공격형 | defense | 적중 | 적중 시 다음 피격 보호 | — |
| `HOB_TAUNT/broken` | 홉고블린 턱뼈 | 공격형 | crush | 적중 | 적중 시 밀치기 · 벽 충돌 피해 | — |
| `HOB_TAUNT/pierced` | 홉고블린 심장 | 연쇄형 | defense | 대기 | 연속 대기 위협도 1~3 | — |
| `GOBLIN_AIM/cut` | 고블린 궁수 깃 | 공격형 | focus | 적중 | 4칸 이상 사격 시 추가 피해 | — |
| `GOBLIN_AIM/broken` | 고블린 궁수 손가락뼈 | 연쇄형 | focus | 적중 | 조준 소비 후 추가 사격 | — |
| `GOBLIN_AIM/pierced` | 고블린 궁수 눈 | 방어형 | focus | 대기 | 대기 후 다음 원거리 피격 회피 +15 | — |
| `SHIELD_STANCE/cut` | 고블린 방패병 가죽 | 연쇄형 | defense | 막기 | 실제 막기 후 반격 | — |
| `SHIELD_STANCE/broken` | 고블린 방패병 팔뼈 | 방어형 | defense | 대기 | 대기 시 직접 피해 20% 감소 | — |
| `SHIELD_STANCE/pierced` | 고블린 방패병 심장 | 연쇄형 | bless | 막기 | 축복 중 막기 시 가까운 아군 보호 | — |
| `ORC_THROW/cut` | 오크 투척병 팔 | 공격형 | volley | 적중 | 원거리 적중 후 추가 사격 | — |
| `ORC_THROW/cut@air` | 오크 투척병 팔 · air | 연쇄형 | wind | 밀침 성공 | 실제 밀침 후 추가타 | — |
| `ORC_THROW/broken` | 오크 투척병 어깨뼈 | 연쇄형 | crush | 벽 충돌 | 실제 벽 충돌 후 추가 피해 | — |
| `ORC_THROW/pierced` | 오크 투척병 눈 | 연쇄형 | volley | 적중 | 같은 적 연속 원거리 적중 후 추가 사격 | — |
| `SPIDER_WEB/cut` | 동굴 거미 다리 | 방어형 | rapid | 적중 | 적중 후 다음 피격 회피 +10 | — |
| `SPIDER_WEB/broken` | 동굴 거미 껍질 | 연쇄형 | mental | 적중 | 혼란 적중 시 정신 피해 | — |
| `SPIDER_WEB/pierced` | 동굴 거미 실샘 | 공격형 | mental | 적중 | 적중 시 혼란 | — |
| `BEETLE_CURL/cut` | 바위 딱정벌레 날개 | 방어형 | crush | 대기 | 대기 후 밀치기 저항 | — |
| `BEETLE_CURL/broken` | 바위 딱정벌레 껍질 | 방어형 | ice | 대기 | 대기 시 방어 +4 | — |
| `BEETLE_CURL/pierced` | 바위 딱정벌레 핵 | 방어형 | regen | 피격 | 적대 직접 피격 후 재생 | 3턴 |
| `ORE_SLAM/cut` | 광석 골렘 광맥 | 연쇄형 | ice | 적중 | 빙결 강타 적중 시 강화 파쇄 | — |
| `ORE_SLAM/broken` | 광석 골렘 몸돌 | 공격형 | crush | 대기 | 대기 후 다음 공격 강타 | — |
| `ORE_SLAM/pierced` | 광석 골렘 핵 | 연쇄형 | ice | 적중 | 기존 빙결 적중 시 파쇄 | — |
| `LEECH_LATCH/cut` | 거대 거머리 입 | 공격형 | bleed | 대기 | 대기 후 다음 공격 출혈 | — |
| `LEECH_LATCH/broken` | 거대 거머리 몸마디 | 연쇄형 | fire | 적중 | 화상·출혈 적중 시 추가 피해 | — |
| `LEECH_LATCH/pierced` | 거대 거머리 흡반 | 공격형 | heal | 적중 | 실제 피해 15% 회복 · 최대 4 | 최대 4 |
| `TOAD_SPIT/cut` | 늪 두꺼비 혀 | 연쇄형 | poison | 적중 | 중독 적중 시 주변 전이 | — |
| `TOAD_SPIT/broken` | 늪 두꺼비 뼈 | 방어형 | poison | 대기 | 대기 후 인접 피격 시 중독 | — |
| `TOAD_SPIT/pierced` | 늪 두꺼비 독샘 | 공격형 | poison | 적중 | 적중 시 중독 | — |
| `SERPENT_SHED/cut` | 신전 뱀 허물 | 연쇄형 | heal | 처치 | 처치 시 인접 아군 상태 1개 정화 | — |
| `SERPENT_SHED/broken` | 신전 뱀 비늘 | 공격형 | poison | 대기 | 대기 시 4칸 중독 | — |
| `SERPENT_SHED/pierced` | 신전 뱀 독니 | 연쇄형 | poison | 처치 | 중독 적 처치 시 주변 독 연장 | — |
| `WATER_WAVE/cut` | 물의 정령 물살 | 연쇄형 | water | 정화 성공 | 실제 정화 후 보호 | — |
| `WATER_WAVE/broken` | 물의 정령 물방울 | 연쇄형 | heal | 치유 성공 | 실제 치유 후 보호 | — |
| `WATER_WAVE/pierced` | 물의 정령 핵 | 방어형 | heal | 대기 | 대기 시 HP 70% 이하 아군 치유 · 조우당 2회 | 3턴 · 조우당 2회 |
| `SKELETON_WALL/cut` | 해골 병사 팔 | 연쇄형 | bless | 소환 성공 | 실제 소환 성공 시 소환수 축복 | — |
| `SKELETON_WALL/broken` | 해골 병사 갈비뼈 | 방어형 | death | 대기 | 대기 후 직접 피해 25%를 자기 해골과 분담 | — |
| `SKELETON_WALL/pierced` | 해골 병사 두개골 | 연쇄형 | death | 처치 | 낙인 몬스터 처치 시 해골 | 소환 1명 |
| `SKELETON_VOLLEY/cut` | 해골 궁수 손가락 | 연쇄형 | water | 적중 | 젖은 전기 적중 시 최대 4명 연쇄 | — |
| `SKELETON_VOLLEY/broken` | 해골 궁수 등뼈 | 방어형 | volley | 적중 | 이동 후 적중 시 회피 준비 | — |
| `SKELETON_VOLLEY/pierced` | 해골 궁수 눈구멍 | 연쇄형 | water | 적중 | 젖은 둔화 대상 적중 시 빙결 | — |
| `GHOUL_CLAW/cut` | 구울 발톱 | 연쇄형 | bleed | 처치 | 출혈 적 처치 시 HP 4 회복 | — |
| `GHOUL_CLAW/broken` | 구울 턱 | 연쇄형 | fire | 처치 | 화상 적 처치 시 주변 화상 | — |
| `GHOUL_CLAW/pierced` | 구울 심장 | 연쇄형 | fire | 적중 | 화상·중독 적중 시 독성 폭발 | — |
| `VAMPIRE_BITE/cut` | 흡혈 박쥐 날개 | 공격형 | evasion | 공격 확정 | 이동 후 첫 공격 +20% | — |
| `VAMPIRE_BITE/broken` | 흡혈 박쥐 이빨 | 공격형 | regen | 적중 | 실제 피해 후 HP 2 재생 | 3턴 |
| `VAMPIRE_BITE/pierced` | 흡혈 박쥐 심장 | 연쇄형 | reflect | 처치 | 반사 처치 시 HP 3 회복 | — |
| `THORN_ARMOUR/cut` | 망령 기사 망토 | 방어형 | hex | 대기 | 대기 후 피격 시 공격자 약화 | — |
| `THORN_ARMOUR/broken` | 망령 기사 갑주 | 방어형 | reflect | 대기 | 대기 후 피격 피해 30% 반사 | — |
| `THORN_ARMOUR/broken@air` | 망령 기사 갑주 · air | 방어형 | wind | 대기 | 대기 후 다음 피격 회피 +15 | — |
| `THORN_ARMOUR/pierced` | 망령 기사 핵 | 연쇄형 | wind | 밀침 성공 | 원거리 밀침 성공 후 회피 준비 | — |
| `WRAITH/cut` | 원혼 수의 | 연쇄형 | hex | 처치 | 약화 적 처치 시 저주 전이 | — |
| `WRAITH/broken` | 원혼 뼈 | 연쇄형 | death | 처치 | 약화·사령 낙인 처치 시 해골 강화 | — |
| `WRAITH/pierced` | 원혼 핵 | 공격형 | death | 적중 | 적중 시 사령 낙인·정신 피해 | — |
| `WRAITH/pierced@will` | 원혼 핵 · will | 연쇄형 | mental | 처치 | 혼란 적 처치 시 다음 공격 강화 | — |
| `GRAVEKEEPER/cut` | 묘지기 손 | 연쇄형 | summon | 소환수 처치 | 소환수 처치 시 지속 +1턴 | — |
| `GRAVEKEEPER/broken` | 묘지기 뼈 | 연쇄형 | death | 소환수 사망 | 적에게 죽은 자기 해골 주변 저주 | — |
| `GRAVEKEEPER/pierced` | 묘지기 등불 | 공격형 | death | 대기 | 대기 시 해골 · 최대 1 · 재사용 3턴 | 3턴 · 소환 1명 |
| `GRAVEKEEPER/pierced@poison` | 묘지기 등불 · poison | 공격형 | poison | 대기 | 대기 시 4칸 중독 | — |
| `GOBLIN_CHIEF` | 족장의 뿔나팔 | 공격형 | bless | 적중 | 적중 후 다음 공격 축복 | — |
| `FURNACE_HEART` | 용광로 심장 | 방어형 | fire | 대기 | 대기 후 인접 피격 시 화염막 | — |
| `SOUL_EATER` | 포식자의 핵 | 방어형 | mental | 대기 | 대기 시 의지 저항 +30 | — |

## 검증

`tests/attack_wait.gd`는 전체 효과 매핑과 부여→연쇄 순서, 면역, 벽·거리, 의도/강제 대기, 방어 준비, 재봉쇄, 마지막 적 처치·지속 피해 귀속, 치유 횟수, 소환·호위·집중, 봉인과 예측 순수성을 검사한다. 고정 보상은 실제 흡수·HP·공격력·프로필 전환·NPC 적용까지 확인하며 전하가 갱신되지 않은 전기 피해의 발동·기여·표시와 행동당 한도를 검사한다. `tests/attack_wait_ui.gd`는 프로필 선택·6칸·요약·흡수 전 보상·MP/기술 바 표시와 320×568 / 390×844 / 430×932 배치를 검사한다. 두 검사는 GitHub Actions에 포함한다.

2026-09-27 보상·발동 기록 수정 검증: 관련 12개 검사 묶음, 총 2,164항목 통과(신규 규칙 414항목·UI 19항목 포함). Web 내보내기, 배포 파일 단독 시작, 같은 배포 파일의 새 보상·매핑·3인 아레나·시간 진행을 확인했다. 사람의 모바일 플레이와 원정 누적 밸런스는 이 검사에 포함하지 않는다.

원인 행동/부모 이벤트/주체/규칙/대상 기록은 `session.aw_trace`, 비상 한도 발생은 `aw_overflows`, 기존 효과 기여 집계는 `battle_stats.members`에서 확인한다. 로그는 전투 결과 문장을 유지하며 발동 설명 팝업은 추가하지 않았다.
