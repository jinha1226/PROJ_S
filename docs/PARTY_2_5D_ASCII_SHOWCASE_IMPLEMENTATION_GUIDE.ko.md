# Party 2.5D 컬러 ASCII 쇼케이스 구현 가이드

## 1. 목표와 고정 범위

현재 Party custom Canvas는 런타임 그림 asset에 의존하지 않는 코드 네이티브 ASCII 화면으로 표시한다. 선택형 2.5D는 Reddit 글의 첫 번째 영상인 ASCIIDENT를 시각 기준으로 삼아, 검은 바탕·고채도 제한 팔레트·여러 printable ASCII 문자로 조립한 지형과 배우·전후 문자층·문자 글로우로 깊이를 만든다. 평면 2D는 같은 글의 두 번째 영상처럼 현재 시야는 컬러, 한 번 보았지만 현재 시야 밖인 기억 영역은 흑백, 미탐험 영역은 비표시로 구분한다. 기존 좌표·입력·전투 crop은 유지한다. `docs/concepts/ascii_2_5d_visual_target.png`는 폐기 전 초기 방향을 기록한 문서 이미지이며 현재 구현 목표가 아니다.

동시에 exact `SHOWCASE_V1`을 추가하고 다음 UX를 적용한다.

- 전투 진입부터 동료 자동 제안을 먼저 보이고 주인공 행동 입력을 기다린다.
- 주인공 행동이 완결되면 최종 계획을 한 frame씩 두 단계로 노출한 뒤, UI가 별도 `턴 확정` 없이 정확히 한 번 commit한다.
- 대상/이동 선택이 미완료이거나 override 편집 중이면 명시적으로 기다린다.
- 탐험은 첫 목적지 탭 preview, 같은 목적지 두 번째 탭 route 시작, 이후 auto-walk를 그대로 유지한다.
- 탐험에는 턴 버튼이 없다.

신체·조직 simulation, 전투 공식 변경, 실제 3D, 새 런타임 asset은 범위 밖이다.

## 2. 현재 코드 경계와 불변식

- `playtest/party_grid_view.gd`: Party renderer와 world↔pixel mapping, hit test의 권위다.
- `playtest/party_encounter_sandbox.gd`: 입력, combat dock, route 자동 진행의 권위다.
- `playtest/party_playtest_session.gd`: 관찰 DTO, draft/preview/commit, save/replay facade다.
- `playtest/party_exploration_route.gd`: route hash, stale 검사, 한 칸 진행, member risk의 권위다.
- `playtest/playtest_grid_view.gd`: Phase 3 회귀 표면이므로 수정하지 않는다.

비타협 불변식은 다음과 같다.

- `PartyPlaytestSession.new()` 기본 시나리오는 `REGRESSION_V1`이다.
- 실제 Party sandbox만 `SHOWCASE_V1`을 명시한다.
- core snapshot은 v6을 유지하고 scenario는 Party session wire가 소유한다.
- renderer/preview/suggestion은 world, journal, draft, scheduler, RNG를 바꾸지 않는다.
- `set_actor_action()`에서 자동 commit하지 않는다. 자동 commit은 UI-only 정책이다.
- `grid_rect`, `cell_size_px`, `world_cell_rect`, `world_to_pixel_center`, `pixel_to_world_cell`, `mapping_signature`, `actor_hit_rect` 의미를 유지한다.
- 실시간 Timer, global RNG, 실제 3D camera/shader를 도입하지 않는다.

## 3. 구현 파일

추가된 파일:

- `playtest/ascii_visual_style.gd`: 순수 glyph/palette/pose/FOV draw-spec registry
- `playtest/ascii_actor_portrait.gd`: Grid와 카드가 공유하는 절차적 ASCII actor renderer
- `playtest/party_visual_test_map.gd`: scenario ID, exact 15×15 manifest, radius-6 LOS/FOV, bootstrap helper
- `tests/test_party_ascii_visual.gd`, `tests/test_party_showcase_scenario.gd`, `tests/test_party_auto_flow.gd`: 시각·scenario·자동 흐름 회귀

수정 파일:

- `playtest/party_grid_view.gd`: atlas 배우를 Canvas primitive ASCII 배우로 교체
- `playtest/party_playtest_session.gd`: scenario 선택, session v3, FOV/follower DTO, 순수 자동 계획
- `playtest/party_encounter_sandbox.gd`: `SHOWCASE_V1`, 자동 배치/전투 commit, 수동 fallback, normal `TurnConfirm` 제거
- Party 관련 tests와 UI smoke

README, NEXT, Phase 3 renderer, combat/status core 규칙은 건드리지 않는다.

## 4. ASCII 시각 계약

### 4.1 순수 style registry

`ascii_visual_style.gd`는 다음 순수 projection을 제공한다.

```gdscript
static func terrain_spec(cell: Dictionary) -> Dictionary
static func actor_spec(actor: Dictionary, ghost: bool = false) -> Dictionary
static func hazard_spec(cell: Dictionary) -> Dictionary
static func visibility_spec(cell_or_state: Variant) -> Dictionary
static func follower_spec(actor: Dictionary) -> Dictionary
```

반환값은 숫자·색·glyph만 가진 deep-detached Dictionary다. Node, Resource, WorldState, entity 참조를 보관하지 않는다.
고정 glyph는 다음과 같다.

| ID/role | glyph |
|---|---:|
| `floor` | `.` |
| `stone_floor` | `:` |
| `wood_floor` | `=` |
| `metal` | `+` |
| `rubble` | `,` |
| `shallow_water` | `~` |
| `wall` | `#` |
| protagonist | `@` |
| human companion | `&` |
| goblin companion | `g` |
| goblin hostile | `G` |
| dead | `x` |
| fallback | `?` |

`OPEN_DOOR`는 현재 `feature_id=open_door` DTO이며 그 타일의 core terrain/지형 glyph는 `stone_floor`/`:`를 유지한다. 주요 actor 색은 hero `#FFD447`, human companion `#65BFFF`, goblin companion `#91D657`, hostile `#FF675C`다. hazard cue는 fire `*`/`#FF7A3D`, wetness `~`/`#62C8FF`, conductivity `+`/`#8DDCE8`을 쓴다.

### 4.2 타일과 actor

2.5D 타일은 단일 glyph 대신 재질별 3문자 전경 cluster와 더 어두운 후경 cluster를 겹쳐 그린다. 벽은 `###` 전경과 `|#|` 후경, 물은 `~~~`, 나무 바닥은 `===`처럼 모두 ASCII 32–126 범위로 조립한다. 글로우도 같은 문자를 낮은 알파로 여러 번 찍는 text-only pass다. actor는 ` o ` / `/@\` / `/ \`의 3행 조립을 기본으로 하며, 갑옷은 가운데 행의 `[` `]`, 무기는 별도 ASCII 한 글자로 표현한다.

actor 안정 정렬은 `(world_y, world_x, entity_id)`다. `ACTIVE`는 3행, `DOWNED`와 `DEAD`는 눕힌 1행 문자열이다. 이는 표현이며 body simulation이 아니다. 평면 2D는 빠른 판독을 위해 기존의 셀당 한 glyph actor를 유지한다.

draw layer는 고정한다.

1. background
2. terrain extrusion/top/glyph
3. visibility tint
4. hazard
5. route
6. actor shadow/body
7. companion suggestion
8. selection/intent
9. 기존 combat effects
10. border

fire는 `*`, wetness는 `~`, conductivity는 작은 `+` cue로 표시한다. 지속 전기 charge를 암시하지 않는다.

### 4.3 radius-6 LOS/FOV와 표시 seam

`SHOWCASE_V1`은 주인공을 원점으로 Chebyshev radius 6과 벽 차단 Bresenham LOS를 함께 적용한다. 생산 cell DTO는 `VISIBLE|UNSEEN`을 내보내며 renderer 규약은 미래 저장형 시야를 위한 `MEMORY`도 이해한다.

- `VISIBLE`만 actor/hazard를 그리고 actor·tile gesture를 허용한다.
- `UNSEEN`은 `terrain_id=unknown`, 빈 feature/actor, hazard 0으로 scrub하며 route와 intent overlay도 그리지 않는다.
- `MEMORY`는 흐린 terrain-only renderer seam이며 생산 session은 아직 memory를 만들거나 저장하지 않는다.
- FOV는 presentation에만 적용된다. contact/AI/pathfinding authority와 minimap은 이 단계에서 바꾸지 않는다.

## 5. exact `SHOWCASE_V1`

상수 ID는 `REGRESSION_V1`, `SHOWCASE_V1`이다. 알 수 없는 ID는 fallback 없이 실패한다.

원점은 왼쪽 위이며 각 행은 `y=0..14`, 문자는 `x=0..14`다.

```text
###############
#......#......#
#......#......#
#......#....E.#
#......#......#
#......#......#
#..rr..+......#
#......#......#
#.www..#..rr..#
#.www..#..rr..#
#.mmm..#......#
#......#......#
#.@.ff.#......#
#......#......#
###############
```

문자 의미:

- `# wall`, `. stone_floor`, `r rubble`, `w shallow_water`, `m metal`, `f wood_floor`
- `+`는 core `stone_floor`이며 presentation feature만 `OPEN_DOOR`
- `@`는 hero/party anchor `(2,12)`, `E`는 enemy `(12,3)`

exact 좌표:

- divider wall: `x=7`, `y=1..5`와 `y=7..13`
- open doorway: `(7,6)`
- rubble: `(3,6)`, `(4,6)`, `(10,8)`, `(11,8)`, `(10,9)`, `(11,9)`
- water: `x=2..4`, `y=8..9`
- metal: `x=2..4`, `y=10`
- wood: `(4,12)`, `(5,12)`
- companions는 simulation에서 `GROUPED`이며 logical position/occupancy는 anchor를 유지한다. 관찰 DTO만 진행 방향의 trail cell과 고정 인접 fallback에서 서로 다른 `display_position`을 골라 `display_role=FOLLOWER`로 투영한다.

party/enemy detection radius는 모두 3이다. hero `(8,6)`은 contact 전, `(9,6)`은 enemy `(12,3)`과 Chebyshev 3 contact이며 facing은 `UP`이다.

각 formation 자체의 배치 cell은 다음과 같다. 자동 배치는 `WEDGE → LINE → COLUMN` 순서로 preview를 시도해 첫 accepted draft를 사용하며, 전부 거부되거나 preview가 입력/modal/stale 상태로 무효화되면 수동 대형 선택으로 fallback한다.

| formation | companion cells |
|---|---|
| `WEDGE` | `(8,7)`, `(10,7)` |
| `LINE` | `(8,6)`, `(10,6)` |
| `COLUMN` | `(9,7)`, `(9,8)` |

### 5.1 bootstrap provenance

local candidate Simulator에서 다음 순서를 지킨다.

1. 225 terrain을 `(y,x)` 행 우선으로 설정
2. passable cell에 entity 추가
3. party state/member/slot/relation 설정
4. `(3,10)` wetness 80
5. `(4,12)` wetness 60
6. `(5,12)` fire 80
7. `world_state_error()` 검사
8. snapshot serialize→restore equality 검사
9. 성공한 candidate만 session에 publish

tile scalar를 직접 쓰지 않고 canonical bootstrap API/source event를 사용한다. event type, position, magnitude, 순서를 exact 검증한다. `OPEN_DOOR`는 scenario ID와 좌표로 투영하며 새 core terrain/state가 아니다.

## 6. DTO와 serialization

`observe_party_world()` top-level의 현재 key는 다음과 같다.

```text
cells, grid_mapping, height, phase, visibility, width
```

cell row key:

```text
actors, effective_conductivity, feature_id, fire_intensity,
position, terrain_id, visibility_state, wetness
```

actor row key:

```text
display_name, display_position, display_role, entity_id, faction_id,
facing, guarded, health, is_enemy, is_protagonist, kind,
life_state, logical_position, max_health, presence, roster_slot,
species_id, sprite_frame, status_ids
```

cells는 행 우선이며 actor는 roster slot 뒤 entity ID, status IDs는 문자열 오름차순이다. 전체 DTO는 deep-detached다. `sprite_frame`은 기존 카드 호환 필드이고 Grid actor는 ASCII draw spec으로 렌더한다.

첫 route preview의 grouped companion follow plan은 top-level `path`, `completed_steps`, `next_position`, `companion_rows`를 가진다. 각 companion row의 현재 핵심 key는 다음과 같다.

```text
entity_id, roster_slot, source=SUGGESTED, mode=FOLLOW_ROUTE,
from_position, next_position, goal, path,
component_maxima, max_total_risk
```

Grid는 같은 path에 roster별 offset 점선, next cue, risk badge를 그린다. 이는 non-hit-testable presentation이며 독립 companion 이동이나 occupancy가 아니다.

Party session wire를 v3으로 올리고 top-level key를 exact하게 고정한다.

```text
journal, personality_seed, scenario_id,
session_format_version, snapshot, world_seed
```

load는 같은 scenario로 깨끗한 session을 만든 뒤 journal을 replay하고 final snapshot equality를 검증한다. unknown scenario, key tamper, scenario swap은 transactional no-op 실패다. v2는 기본 scenario를 추측하지 않고 명시적으로 거부한다. core snapshot은 v6 그대로다.

draw spec, follower display position, selection, pending auto token, suggestion cache, FOV memory는 저장하지 않는다.

## 7. 전투 자동 흐름

CONTACT 자동 배치가 끝나 ENGAGED가 되면 session의 `prepare_auto_combat_plan()`이 동료 제안과 주인공 placeholder를 준비한다. `auto_combat_planning_state()`는 이를 순수 DTO로 노출하고, 플레이어가 주인공 행동을 완결하면 `replace_auto_combat_protagonist_action()`이 placeholder를 canonical action으로 교체한다. 이 preview 계열은 world/journal/RNG를 바꾸지 않는다.

UI orchestration은 다음 상태 필드로 표현한다.

```text
auto_phase
auto_deployment_pending / auto_deployment_render_stage / auto_deployment_fallback
auto_combat_pending / auto_combat_render_stage / auto_combat_fallback
auto_override_edit / auto_generation
```

normal combat 처리:

1. 동료 제안과 주인공 placeholder를 먼저 표시한다.
2. 주인공 HOLD/MOVE/MELEE 선택이 완결되면 canonical plan과 `plan_hash`를 만든다.
3. stage 0에서 최종 intent overlay를 한 frame 표시한다.
4. stage 1에서 한 frame을 더 보장한 뒤 commit callback으로 넘어간다.
5. callback에서 generation/hash/step, ENGAGED nonterminal, 입력·modal·edit 없음과 `commit_ready`를 재검사한다.
6. token당 정확히 한 번 `commit_turn()`을 호출하고 token을 폐기한다.

Timer는 쓰지 않는다. invalid/rejected/stale/phase change/new input/modal은 token을 취소하고 commit 0회를 보장한다.

동료 override와 수동 fallback은 다음과 같다.

- 동료를 선택해 HOLD/MOVE/MELEE를 지정하면 `auto_override_edit`가 켜지고 override를 보존한 채 주인공 선택을 기다린다.
- 주인공 행동이 완결되면 override가 포함된 최종 plan을 같은 2-stage 자동 commit으로 실행한다.
- 자동 계획 준비/검증/commit이 거부되거나 pointer·modal·phase 변화로 취소되면 `auto_combat_fallback`으로 전환한다.
- fallback 또는 아직 완결되지 않은 override 문맥에서는 `지금 실행`, `자동 제안 복원`, 직접 행동 controls를 노출한다.

auto-orchestration UI의 상시 `TurnConfirm`은 제거한다. legacy/manual headless 경로와 session API의 preview/commit 분리는 유지한다.

## 8. 탐험 UX

기존 의미를 그대로 고정한다.

1. 첫 탭은 순수 route preview
2. 같은 목적지 두 번째 탭은 route 시작과 exactly one hop
3. 이후 process frame마다 continuation
4. contact/stale/blocker/risk/phase 전환 시 기존 규칙대로 중단

첫 preview부터 hero route와 hazard를 표시하고, grouped companion은 같은 path의 roster-offset 점선·next cue·기존 member risk ceiling badge로 표시한다. 탐험 턴 버튼을 추가하지 않는다. `UNSEEN` cell은 tap/long press/nearby actor signal을 내지 않으며 route/follow/intent overlay도 새지 않는다.

## 9. RED 우선 테스트

### Scenario/session

- 기본 `REGRESSION_V1`이 기존 fixture와 exact 동일
- exact 225-cell manifest, entity/detection radius/relation, hazard source event 순서
- radius-6 LOS FOV, 벽 차단, UNSEEN scrub, presentation-only follower 위치
- 같은 seed+scenario의 snapshot/wire equality
- v3 replay equality, unknown/swap/missing/extra/v2 rejection
- `(8,6)` no-contact, `(9,6)` contact, 세 formation no-fallback

### Renderer/DTO

- top/cell/actor exact key와 deep detachment
- terrain/actor/life/hazard exact glyph와 palette
- shadow/torso/head/limb가 360×640, 450×800 타일 안에 있음
- terrain→hazard→route→actor→intent→effect layer 순서
- SHOWCASE의 `VISIBLE|UNSEEN` 분할과 actor/hazard/route/intent leak 0
- 기존 mapping signature/hit test/touch slop/long press 동일
- `CHARACTER_ATLAS` 호환 상수와 무관하게 actor drawing path의 texture draw 0

### Combat UX

- hero 선택 전 companion suggestion과 protagonist placeholder가 보이고 pure함
- normal HOLD/MELEE/MOVE가 accepted overlay 뒤 exactly one commit
- stage 0/1에서 final plan을 각각 한 frame 보이고, 중복 callback도 one commit; rejected/stale/modal/new input은 zero commit
- normal tree에 `TurnConfirm` 없음
- companion override는 hero 선택 전 commit 0, hero 선택 후 override를 보존한 auto commit 1
- 자동 실패/취소 시 manual fallback controls와 contextual 실행 노출
- headless `set_actor_action()`만으로 commit 0

### Exploration/integration

- 첫 탭 world/journal 불변 preview와 companion FOLLOW/risk 표시
- 같은 목적지 두 번째 탭 exactly one hop, 이후 기존 auto-walk
- `(9,6)` exact contact, `WEDGE→LINE→COLUMN` 첫 accepted 자동 배치와 9×9 crop 전환
- 탐험 turn button 0, 360×640/450×800 UI smoke 통과

## 10. 수용 기준과 검증

완료 조건:

- Party actor drawing path는 atlas texture를 소비하지 않고 glyph+procedural limbs+shadow/extrusion을 표시한다.
- exact `SHOWCASE_V1`이 main sandbox에서 재현되고 기본 tests는 `REGRESSION_V1`을 유지한다.
- SHOWCASE radius-6 LOS/FOV와 follower display projection이 simulation occupancy를 바꾸지 않는다.
- session v3 replay/tamper 검증이 결정론적이며 core snapshot v6은 변하지 않는다.
- CONTACT에서 첫 accepted formation의 ghost를 한 frame 이상 보인 뒤 자동 배치하고, 실패하면 수동 선택으로 돌아간다.
- 전투 전 동료 제안이 보이고 주인공 선택이 끝나면 최종 plan을 2-stage로 표시한 뒤 별도 버튼 없이 exactly one commit한다.
- 대상/이동 선택 중에는 기다리고, 자동 흐름이 취소되거나 거부되면 수동 fallback을 제공한다.
- 탐험 double-tap/auto-walk와 입력 mapping이 유지된다.
- Phase 3/4/5/full 및 Party UI smoke가 전부 통과한다.

최종 명령:

```bash
git diff --check
godot --headless --path . --script res://tests/run_phase3_tests.gd
godot --headless --path . --script res://tests/run_phase4_tests.gd
godot --headless --path . --script res://tests/run_phase5_tests.gd
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/party_ui_layout_smoke.gd
rg -n "CHARACTER_ATLAS|draw_texture" playtest/party_grid_view.gd
rg -n "TurnConfirm|턴 확정" playtest tests
```

runner 이름은 현재 `tests/`의 실제 파일명을 우선한다. UI smoke가 배포 workflow에 포함되지 않았다면 Web export 전 별도 gate로 실행한다.

## 11. 비범위

- body/tissue/절단/자세 물리 simulation
- 실제 3D, shader, 외부 sprite/font
- explored memory 저장, minimap, FOV 기반 AI/contact/pathfinding 변경
- 독립 companion 탐험, party split
- 새 terrain/hazard/combat/status/lifecycle 규칙
- 실제 door 상태, persistent electricity, poison
- loot/inventory/multiple encounter
- Phase 3 renderer 통합

이 milestone은 presentation과 Party session/UI 경계만 바꾼다. radius-6 FOV, follower display position, follow plan과 자동 commit 상태는 simulation authority 또는 replay 입력으로 역류하지 않아야 한다.
