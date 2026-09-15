# 동시 제공 이능 전환 + 1층 부위 이능 7종 — 설계 (단계 1/3)

- 작성일: 2026-09-15
- 상위 문서: [ABILITY_CONTENT_CREATION_HANDOFF.ko.md](../../ABILITY_CONTENT_CREATION_HANDOFF.ko.md)
- 후속 단계: 2) 동료 AI 액티브 자동 사용, 3) 소환(일정 시간 존재하는 동료 NPC형) — 각각 별도 spec.
- 상태: 사용자 승인된 설계. 구현 계획은 `docs/superpowers/plans/`에 별도 작성.

## 1. 목표

1. 결속 슬롯 하나에 넣은 이능이 패시브와 액티브를 **동시에** 제공한다. 모드 선택 UI·이벤트·런타임 경로를 신규 플레이에서 제거한다.
2. 1층에 실제 등장하는 종(`goblin`, `kobold`, `dcss_rat`, `dcss_frilled_lizard`, `dcss_hobgoblin`, `dcss_orc`; `sim/dcss_enemy_registry.gd:37-49`)의 **부위** 기반 신규 이능 7종을 현재 지원되는 공통 효과만으로 추가한다.
3. 적 사기(도주)를 이능 효과로 연결한다. 기존 소비재 `FEAR` 상태와 `forecast_enemy_action`의 `fear_retreat` 동작을 재사용한다.
4. 옛 저장(모드 이벤트 포함)의 저널 재생을 깨뜨리지 않는다.

비목표: 드롭 확률 정책 변경, 정수 16종의 부위 아이템 교체, 제거·재결속 정책, 숙련 체계 변경, 동료 AI 자동 사용(단계 2), 소환(단계 3).

## 2. 결속 계약 v2와 저장 이전 정책

### 2.1 계약

- `AbilityBindingRules.RULESET_ID`는 `ability-binding-v1`을 유지한다(결속 이벤트 형식은 불변). 동시 제공 여부는 party state의 `legacy_ability_modes` 플래그로 결정한다.
- `PartyEncounterState`에 `legacy_ability_modes: bool` 필드 추가. 신규 세션은 `false`. `SCHEMA_VERSION`을 26(`DUAL_EFFECT_SCHEMA_VERSION`)으로 올리고 v26 키 목록에 `legacy_ability_modes`를 포함한다. 로드 시 v25 이하 저장은 `true`로 이전한다(`legacy_contact_rule` 패턴, `party_encounter_state.gd:95,162,170,312,356`, `party_playtest_session.gd:8341,8561`).
- `legacy_ability_modes == false`일 때:
  - `PartyMemberState.active_skill_ids()`는 결속 이능 전부를 반환한다.
  - `monster_ability_runtime.passive(world,id,ability)`는 `ability in member.bound_ability_ids`(canonical)만 본다.
  - `set_ability_mode`는 `ability_mode_retired`로 거부하고 이벤트를 만들지 않는다.
  - `world_state_error`는 `party.ability_mode_changed` 이벤트가 있으면 `ability_mode_event_retired`를 반환한다. `monster_ability_wrong_mode`, `ability_mode_projection_mismatch` 검사는 수행하지 않는다.
  - `monster_passive_service.event_error`의 historical 검사는 `party.ability_bound`만 요구한다.
  - `accuracy_bonus(before)`의 과거 재구성은 `party.ability_bound` 이벤트로 판단한다.
  - `passive_ability_ids`는 항상 비어 있어야 하며 `to_dict`에 쓰지 않는다.
- `legacy_ability_modes == true`일 때: 현재 코드의 모드 동작을 그대로 유지한다(저널 `MODE` 재생 포함). 이 경로는 삭제하지 않되 새 기능을 추가하지 않는다. 신규 7종 이능은 v1 저장에서도 결속·사용 가능하지만 모드 규칙을 따른다(신규 콘텐츠를 옛 저장에서 막지 않는 최소 정책).

### 2.2 UI

- `ability_binding_rows`의 `mode` 키는 v2에서 제거한다. 각 행은 `passive`, `active` 설명을 병기한다.
- `ability_loadout_mockup.gd`의 모드 토글 버튼을 제거하고 두 효과 설명을 함께 표시한다. `dual_mode` 키 이름은 `dual_effect`로 바꾼다(`effect_preview` 포함).
- `monster_abilities.json`의 `effect_status`는 `IMPLEMENTED_DUAL_EFFECT`로 바꾼다. `monster_ability_catalog` 및 드롭 테스트가 문자열을 검사하면 함께 갱신한다.

### 2.3 밸런스 원칙

- 기존 16종의 수치는 이번에 바꾸지 않는다. 동시 제공으로 총효용이 올라가는 것은 인지하되, 측정 없이 수치를 조정하지 않는다(후속 밸런스 항목).
- 액티브 자신의 적중은 어떤 적중 패시브도 발동시키지 않는다. 근거: `reactions()`가 `action.melee_attack`만 원인으로 인정하므로 `ability.cast` 피해는 패시브를 발동하지 않는다. 이 현재 동작을 유지하고 UI 설명에 명시한다.

## 3. 신규 이능 7종

공통: `axis`는 숙련 배율 축. 시간 단위는 필드 시계(100 ≈ 이동 1회). 모든 액티브는 `assess()` 거절 시 MP·HP·상태를 소모하지 않는다. 상태 `until`은 발생 시각 +300 이하(`event_error` 제약).

| ID | 라벨 | 종·부위 | 획득물 ID | axis | MP | 사거리 | 대상 |
|---|---|---|---|---|---|---|---|
| `RODENT_INCISORS` | 설치류 앞니 | dcss_rat · 앞니 | `PART_RAT_INCISORS` | MELEE | 2 | 1 | ENEMY |
| `FLIGHT_INSTINCT` | 도주 본능 | dcss_rat · 뒷발 | `PART_RAT_HINDLEG` | DEFENSE | 2 | 1 | SELF |
| `FRILL_DISPLAY` | 위협 과시 | dcss_frilled_lizard · 목도리 | `PART_LIZARD_FRILL` | DEFENSE | 3 | 1 | SELF |
| `HEAVY_ARM` | 육중한 팔 | dcss_hobgoblin · 곤봉팔 | `PART_HOBGOBLIN_ARM` | MELEE | 3 | 1 | ENEMY |
| `BERSERKER_BLOOD` | 광전사의 피 | dcss_orc · 심장 | `PART_ORC_HEART` | MELEE | 2 | 1 | ENEMY |
| `WAR_ROAR` | 포효 | dcss_orc · 성대 | `PART_ORC_THROAT` | MAGIC | 3 | 1 | SELF |
| `NIGHT_EYE` | 야간 안구 | goblin · 눈 | `PART_GOBLIN_EYE` | MAGIC | 2 | 1 | SELF |

### 3.1 RODENT_INCISORS 설치류 앞니
- 패시브: 근접 적중 시, 같은 actor가 같은 target에게 가한 직전 `combat.physical_damage`(원인 `action.melee_attack`)가 150시간 이내에 있으면 물리 +3(숙련 배율). 원인 = 해당 hit 이벤트. 이력은 projection에 `last_melee_hit[actor:target] = event`로 추적.
- 액티브 `물어뜯기` effect `BITE`: 물리 14 → `impact()` 후 `poison(w,actor,target,1,cast.id)`. 독은 `VENOM_FANG`의 POISON 상태를 공유(3중첩 상한, 300시간). `add_status`의 `ability_id`는 `RODENT_INCISORS`, `allowed` 표에 `RODENT_INCISORS: ["POISON"]` 추가. `tick()`의 독 피해 발생 `ability_id`는 상태를 만든 이능 ID를 그대로 쓴다.
- 조합: 독니·도약과 한 대상 집중. 제약: 대상 처치 시 추가 피해 없음(`alive` 검사).

### 3.2 FLIGHT_INSTINCT 도주 본능
- 패시브: `move_delay(world,id)`에서 actor가 이 이능을 결속했고 1칸 내 `is_autonomous_target` 적이 없으면 SLOW·FROST_ZONE 지연을 0으로 반환. 상태 자체는 지우지 않는다(적이 붙으면 다시 적용).
- 액티브 `후퇴 도약` effect `RETREAT_LEAP`: 가장 가까운 살아 있는 적(시야 무관, 거리 기준)에서의 체비셰프 거리가 현재보다 커지는, 2칸 이내·통과 가능·비점유·시선 통과 빈칸 중 거리 증가량 최대(동률이면 y, x 오름차순) 칸으로 `commit_preflighted_move`. 후보가 없거나 적이 없으면 거절(`도약할 빈칸이 없습니다.`). 행동 시간 100.
- 조합: 서리실·밀치기로 거리 유지, 원거리 빌드.

### 3.3 FRILL_DISPLAY 위협 과시
- 패시브: `armor()`에서 `health*2 <= max_health`이면 +2.
- 액티브 `과시` effect `FRILL`: 자신에게 상태 `FRILL`(magnitude 4, 200시간; `armor()`가 HIDE/SHELL/STONE과 같이 합산) + 1칸 내 시야 통과 적 전원에 상태 `FEAR`(magnitude 1, 200시간). 적이 하나도 없어도 사용 가능(방어 버프만).
- 조합: 탱커가 붙잡는 동안 동료 이탈, 서리실 지대와 중첩.

### 3.4 HEAVY_ARM 육중한 팔
- 패시브: 근접 적중 시 대상에 `SLOW`(magnitude 50, 200시간, ability_id `HEAVY_ARM`). `move_delay`는 SLOW magnitude를 그대로 지연으로 쓴다.
- 액티브 `강타 밀치기` effect `SMASH`: 물리 16 → 대상 생존 시 밀침. 착지 칸 = 대상 위치 + `sign(delta)`; `ActiveEffectModel` SHOVE 규칙(경계·통과 가능·비점유·모서리 통과 금지)으로 판정. 대상이 `STONE_SKELETON` 패시브이거나 `anchored`이면 피해만 주고 밀치지 않는다(거절 아님). 착지 불가여도 피해만 준다. 이동은 `sim.movement.commit_preflighted_move(target, landing, terrain, 1, cast.id)`(폭발 넉백과 같은 이벤트 형식). 적 밀림 후 `enemy_busy_rows` 변경 없음.
- 조합: 후퇴 본능·서리 지대로 밀어넣기; 갑각/암석에 무효.

### 3.5 BERSERKER_BLOOD 광전사의 피
- 패시브: 근접 적중 시 actor의 `health*2 <= max_health`이면 물리 +4(숙련 배율).
- 액티브 `피의 일격` effect `BLOOD_STRIKE`: assess에서 `health <= 5`면 거절(`HP가 6 이상 필요합니다.`). commit: 자신에게 물리 5(`impact`, ACID 패턴) → 대상에 물리 26.
- 조합: 흡혈·재생과 상쇄, 질긴 가죽으로 위험 관리.

### 3.6 WAR_ROAR 포효
- 패시브: `reactions()`에서 `entity.died` 이벤트를 보고, 그 사망의 원인 사슬에서 최초 행위자가 이 이능을 결속한 파티원이면(`world.event_by_id` 역추적, 깊이 ≤ 8) 3칸 내 시야 통과 적 전원에 `FEAR`(magnitude 1, 100시간, 원인 = died 이벤트). 처치 사건당 1회. 파생 피해(독 틱, 반격)로 죽은 경우도 최초 행위자가 결속자면 발동.
- 액티브 `포효` effect `ROAR`: 3칸 내 시야 통과 적 전원 `FEAR` 200시간. 적이 없으면 거절(`범위 안에 적이 없습니다.`).
- 위협 과시와의 구분: 범위 3 vs 인접, 방어 버프 없음, 처치 반응.

### 3.7 NIGHT_EYE 야간 안구
- 패시브: `markers()`에서 actor의 위치 조도(`vision_rules.illumination`, ambient 0)가 300 미만이면 반경 3 생명체 마커(ECHO_SENSE 패시브와 같은 `LIFE` 마커). 조도 300 이상이면 없음.
- 액티브 `어둠 응시` effect `GAZE`: 자신에게 상태 `DEEP`과 같은 방향성 탐지(반경 6, 300시간). 별도 상태 키 `GAZE`를 두고 `markers()`가 `DEEP`과 동일하게 처리(위험 타일 감지는 제외, 생명체만).
- 조합: 그림자막 상대 카운터, 고블린 2부위(신경·눈) 분리 사례.

### 3.8 상태 키·검증 표 추가

`event_error`의 상태 허용 목록에 추가: `FEAR`, `FRILL`, `GAZE`. `allowed` 표:
`RODENT_INCISORS:["POISON"]`, `HEAVY_ARM:["SLOW"]`, `FRILL_DISPLAY:["FRILL","FEAR"]`, `WAR_ROAR:["FEAR"]`, `NIGHT_EYE:["GAZE"]`. `ability.impact` 발생 이능에 신규 ID 허용. `ability.reaction`의 `trigger` 허용 타입에 `entity.died` 추가(WAR_ROAR 전용). `ability.status` source 허용 타입에 `entity.died` 추가.

### 3.9 FEAR 연결

- `party_encounter_coordinator.forecast_enemy_action`: 소비재 FEAR 또는 `monster_ability_runtime.status(world,enemy,"FEAR")`가 있으면 `fear_retreat`. 두 경로 모두 같은 이동 선택을 쓴다.
- FEAR 적은 `_enemy_batch`에서 공격하지 않는다(현재 동작 그대로).
- `markers()`에 `FEAR` 위치 마커 추가(UI 피드백).

### 3.10 획득물과 드롭

- `items.json`: 부위 7종, `category: MATERIAL`, `stack_limit: 1`, `use_kind: NONE`, 라벨 예 `쥐 앞니`, `오크 심장`.
- `monster_abilities.json`: 7행 추가(`essence_id`에 부위 ID; 필드명은 registry 호환을 위해 유지, 주석으로 부위 획득물임을 표기).
- `species_drop_tables.json`: 각 종에 `chance_per_1000: 200` 롤. 쥐·오크는 부위마다 독립 롤 2개. 기존 정수·마석·식량·돈 롤은 유지.
- UI 보상 분류: 기존 정수와 같은 "몬스터 이능" 분류를 재사용.

## 4. 변경 파일

| 파일 | 변경 |
|---|---|
| `sim/party_encounter_state.gd` | `legacy_ability_modes`, v26 키, 로드 이전 |
| `sim/party_member_state.gd` | `active_skill_ids()` 플래그 분기(월드 접근이 없으므로 `passive_ability_ids`가 비어 있으면 전부 반환 — v2에서는 항상 비어 있음) |
| `sim/abilities/monster_ability_definitions.gd` | 7종 정의 |
| `sim/abilities/monster_ability_runtime.gd` | `passive()`, 신규 effect assess/commit, 패시브 반응 4종, `move_delay`, `armor`, `markers`, `event_error`, `accuracy_bonus` |
| `sim/abilities/monster_passive_service.gd` | historical 검사 플래그 분기 |
| `sim/abilities/ability_binding_rules.gd` | `dual_effect`, preview 문구 |
| `sim/world_state.gd` | 모드 이벤트 검사 플래그 분기 |
| `sim/systems/party_encounter_coordinator.gd` | 이능 FEAR |
| `playtest/party_playtest_session.gd` | `set_ability_mode` 거부, 행 DTO, 로드 이전 |
| `playtest/ability_loadout_mockup.gd` | 모드 버튼 제거 |
| `data/content/monster_abilities.json`, `items.json`, `species_drop_tables.json` | 콘텐츠 |
| `docs/MONSTER_ABILITY_CONTENT_CATALOG.ko.md` | 7종 추가 |

## 5. 검증

1. 기준선: 변경 전 HEAD에서 `tests/monster_dual_mode_acceptance.gd`, `monster_all_abilities_acceptance.gd`, `test_ability_binding.gd`(`run_ability_binding_tests.gd`), `portrait_skills_acceptance.gd`, `ability_binding_gameplay_acceptance.gd`, `starting_ability_drop_acceptance.gd`, `monster_ability_drops_acceptance.gd`, `fireball_environment_acceptance.gd`를 순차 실행해 결과를 기록.
2. `monster_dual_mode_acceptance.gd` → `monster_dual_effect_acceptance.gd`로 교체: 결속 한 번에 (a) `active_skill_ids`에 포함, (b) 근접 적중으로 패시브 발동, (c) 슬롯 1칸, (d) `set_ability_mode` 거부, (e) 모드 UI 노드 없음, (f) 저장→재생 스냅샷 일치.
3. `monster_all_abilities_acceptance.gd`: 모드 주입 제거, 신규 7종을 같은 fixture로 검사(액티브 사용 + 거절 시 무소비 + 패시브 발동 1회 이상).
4. 신규 `floor1_part_abilities_acceptance.gd`: FEAR 적이 `forecast_enemy_action`에서 `fear_retreat`, 밀치기의 정박 대상 처리, 후퇴 도약 착지 규칙, 포효 처치 반응 1회, 야간 안구 조도 조건, 부위 드롭 7종 재현성, v1 저장 fixture(모드 이벤트 포함 저널)가 계속 로드되고 스냅샷이 일치.
5. 완료 판정: 신규 실패 0, 위 항목 전부 통과, 결과를 `docs/ABILITY_DUAL_EFFECT_RESULTS.ko.md`에 기록하고 커밋. 푸시·배포는 하지 않는다.
