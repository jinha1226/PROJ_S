# MVP 원정 수직 슬라이스 구현 가이드

## 1. 목표와 결정

`SHOWCASE_V1` 한 판을 다음 흐름으로 닫는다.

```text
입장 → 탐험 → 기존 단일 조우/전투 → 보상 토큰 자동 획득
→ 출구 개방 → 출구 도달 → 원정 완료 → 같은 seed/scenario로 다시 시작
```

이 단계에서는 canonical simulator 상태를 추가하지 않는다. 단일 조우의 승리는 이미
`party_encounter.safe_phase`, 이동 결과는 주인공 좌표, 재현 조건은
`world_seed/personality_seed/scenario_id`에 보존된다. 따라서 run 진행은 이 값과 고정
scenario manifest에서 매번 도출한다.

- core snapshot은 v6 그대로다.
- Party session wire는 v3 그대로다.
- 보상, 출구 개방, run 완료 bool을 snapshot/save/journal에 중복 저장하지 않는다.
- `REGRESSION_V1`과 기존 기본 생성자의 동작은 바꾸지 않는다.
- 적용 대상은 `SHOWCASE_V1` 하나다.

## 2. 비목표

선택형 loot/pickup, inventory, 장비, 문·상자 등 범용 feature interaction, 멀티층,
추가 조우, 절차 생성, 상점/경제, 퀘스트 프레임워크, 육체 simulation은 구현하지 않는다.
보상 토큰은 이 판의 완료 표식 하나이며 소비·선택·드롭되지 않는다.

## 3. 파일 경계

| 파일 | 변경 책임 |
|---|---|
| `playtest/party_visual_test_map.gd` | 고정 run manifest와 좌표 |
| `playtest/party_playtest_session.gd` | 순수 `run_progress()`, 입력 gate, restart |
| `playtest/ascii_visual_style.gd` | entry/exit feature draw spec |
| `playtest/party_grid_view.gd` | visible feature glyph draw |
| `playtest/party_encounter_sandbox.gd` | 목표·보상·완료 UI와 restart 연결 |
| `tests/test_party_mvp_run.gd` | facade 기반 수직 슬라이스 계약 |
| `tests/party_ui_layout_smoke.gd` | 360×640/450×800 UI·입력 smoke |

`sim/**`, combat 공식, `PartyEncounterState`, `WorldState`, snapshot serializer는 수정하지
않는다. UI와 renderer는 `session.sim/world`를 직접 읽지 않는다.

## 4. exact run manifest

`party_visual_test_map.gd`에 `SHOWCASE_V1` 전용 상수와 순수 함수를 둔다.

```gdscript
const RUN_MANIFEST_SCHEMA_VERSION := 1
const ENTRY_POSITION := Vector2i(2, 12) # 기존 HERO_POSITION과 동일
const EXIT_POSITION := Vector2i(13, 1)  # 통과 가능한 우상단 stone_floor

static func run_manifest(scenario_id: String) -> Dictionary
```

반환값은 deep-detached이며 exact shape은 다음과 같다.

```text
schema_version: 1
scenario_id: SHOWCASE_V1
objective_id: CLEAR_SINGLE_ENCOUNTER_AND_EXIT
entry:  { position:[2,12], feature_id:run_entry }
exit:   { position:[13,1], locked_feature_id:run_exit_locked,
          open_feature_id:run_exit_open }
reward: { reward_id:SHOWCASE_VICTORY_TOKEN, amount:1 }
```

`REGRESSION_V1`/unknown scenario에는 빈 Dictionary를 반환한다. manifest의 좌표는 in-bounds,
passable이고 서로·적 시작점·`OPEN_DOOR_POSITION`과 달라야 한다. 기존 `(7,6)`의
`open_door`는 두 방을 잇는 통로이지 run 출구가 아니다.

## 5. `run_progress()` DTO와 도출식

`PartyPlaytestSession`에 읽기 전용 API를 추가한다.

```gdscript
func run_progress() -> Dictionary
func restart_same_run() -> Dictionary
```

`run_progress()` exact top-level shape:

```text
schema_version, available, scenario_id, objective_id, run_state,
entry_position, exit_position, encounter_cleared, reward, exit,
complete, terminal
```

중첩 shape:

```text
reward: { reward_id, amount, granted }
exit:   { feature_id, open }
```

도출식은 고정한다.

```text
encounter_cleared = safe_phase in [REGROUP_READY, GROUPED_COMPLETE]
reward.granted    = encounter_cleared
reward.amount     = 1 if granted else 0
exit.open         = encounter_cleared
exit.feature_id   = run_exit_open if open else run_exit_locked
complete          = safe_phase == GROUPED_COMPLETE
                    and protagonist_position == EXIT_POSITION
terminal          = complete or safe_phase == PARTY_DEFEATED

run_state 우선순위:
PARTY_DEFEATED → DEFEATED
complete       → COMPLETE
exit.open      → EXIT_OPEN
CONTACT/ENGAGED/REGROUP_READY → ENCOUNTER
그 외          → EXPLORE
```

manifest가 없으면 `available=false`, `run_state=UNAVAILABLE`, 빈 ID/좌표와 false/0을
반환한다. 호출은 world, journal, draft, route, RNG, ID를 바꾸지 않고 모든 중첩값을
detach한다. 저장을 다시 읽어 만드는 cache도 두지 않는다.

## 6. 관찰 DTO와 feature

`observe_party_world()`는 기존 cell key를 유지한다. `SHOWCASE_V1`의 visible cell에서만
session이 `feature_id`를 다음 우선순위로 투영한다.

```text
EXIT_POSITION  → run_progress.exit.feature_id
ENTRY_POSITION → run_entry
그 외          → 기존 VisualTestMap feature_id
```

`UNSEEN`은 지금처럼 `feature_id=""`로 scrub한다. MEMORY가 생겨도 run 출구 상태와 actor를
누설하지 않는다. feature는 pathfinding/점유/FOV/LOS authority가 아니며 core terrain을
바꾸지 않는다.

`AsciiVisualStyle.feature_spec(feature_id)`의 고정 glyph:

| feature | glyph | 색 |
|---|---:|---|
| `run_entry` | `<` | `#65BFFF` |
| `run_exit_locked` | `X` | `#A36A73` |
| `run_exit_open` | `>` | `#75D7A0` |
| `open_door` | `+` | 기존 door 색 |

feature는 terrain 다음, hazard/route/actor 전에 그린다. reward는 자동 지급이므로 map
pickup glyph를 만들지 않는다.

## 7. 입력과 run-complete gate

session facade가 의미의 권위다. Grid가 잠금 여부를 임의 판단하지 않는다.

- 출구가 닫힌 동안 EXIT_POSITION을 goal/destination으로 삼는 direct MOVE와 route
  preview/start는 `exit_locked`로 거부한다. world/journal/draft/route는 무변경이다.
- 출구가 열리면 기존 MOVE/두 번 탭/한 hop route를 그대로 사용한다.
- 출구에 들어가는 최종 MOVE는 정상 commit되고 journal에 기존 `exploration` row 하나를
  남긴다. 그 결과부터 `complete=true`다.
- complete 뒤 `preview/commit_exploration`, route preview/start/continue,
  deployment, begin/replace/override/commit turn은 `run_complete`로 거부한다.
- complete를 만든 hop 뒤 active route와 전투/배치 draft 같은 session transient는
  지우며 simulator 시간이나 journal row를 추가하지 않는다.
- inspect, save/load, `run_progress`, restart는 terminal에서도 허용한다.

`restart_same_run()`은 COMPLETE/DEFEATED에서만 허용한다. 현재 세 값을 로컬에 동결한 뒤
`reset_party(world_seed, personality_seed, scenario_id)`를 호출한다. 성공 시 fresh initial
snapshot, step 0, 빈 journal/draft/route가 되고 실패는 기존 session 전체를 보존한다.
restart 자체는 journal command가 아니라 새 run 경계다.

## 8. save/load/replay와 tamper

run 진행이 canonical snapshot+고정 manifest의 완전한 함수이므로 wire bump는 하지 않는다.

- v3 top keys 여섯 개를 그대로 유지한다. `run_progress`, reward, exit key가 추가된 save는
  strict extra-key 검사로 거부한다.
- load는 기존처럼 seed/scenario로 fresh session을 만들고 journal을 replay한 뒤 final
  snapshot equality를 확인한다. 그 후 `run_progress()`가 자동 복원된다.
- 완료 run replay의 마지막 출구 MOVE는 replay 직전에는 complete가 아니므로 허용되고,
  replay 직후 gate가 닫힌다.
- unknown scenario, 비정규 seed, journal/snapshot 변조는 transactional no-op이다.
- 유효한 다른 scenario ID로 바꾼 tamper도 허용하지 않는다. journal이 비어 있는 initial
  save로 `SHOWCASE_V1 ↔ REGRESSION_V1`을 바꾼 테스트는 반드시
  `party_journal_snapshot_mismatch`가 되고 live session/snapshot/journal이 그대로여야 한다.
- derived field는 wire에 없으므로 보상량·출구·complete만 따로 위조할 표면이 없다.

## 9. 모바일 UI

기존 세로 레이아웃을 재배치하지 말고 phase banner 아래 한 줄 `RunObjectiveBar`를 둔다.
최소 18pt, 44px 이상이며 상태 문구는 다음과 같다.

```text
EXPLORE/ENCOUNTER : 목표 · 고블린을 쓰러뜨리세요
EXIT_OPEN         : 보상 +1 · 출구가 열렸습니다
COMPLETE          : 원정 완료 · 보상 1
DEFEATED          : 원정 실패
```

- reward는 persistent `$ 1` badge로 보여 준다. live combat commit에서 false→true가 된
  경우에만 짧은 획득 강조를 재생한다. load/refresh는 효과를 재생하지 않는다.
- visible locked exit tap은 고정 feedback에 `적을 쓰러뜨리면 출구가 열립니다.`를 남긴다.
  long press inspector에는 `출구 · 잠김/열림`을 추가한다. unseen input은 기존 FOV gate다.
- COMPLETE에서는 grid와 파티 정보는 보존하되 action/route overlay를 숨기고 최하단 고정
  `같은 원정 다시 시작` 버튼 하나만 활성화한다.
- restart 성공 시 pending auto token, pointer, modal, effect/log cursor를 초기화하고 같은
  Grid 인스턴스를 15×15 탐험 view로 되돌린 뒤 새 progress를 표시한다.

## 10. exact acceptance tests

`tests/test_party_mvp_run.gd`에 다음 테스트를 추가하고 public facade만 사용한다.

1. `test_run_manifest_and_progress_are_exact_pure_and_detached`
   - exact manifest/DTO key와 좌표, initial `EXPLORE`, reward 0, locked exit를 검증한다.
   - DTO 변조 뒤 재호출 값과 snapshot/journal이 동일해야 한다.
   - snapshot version 6, session version 3이며 snapshot에 run/reward/exit key가 없어야 한다.
2. `test_locked_exit_and_fov_feature_are_gated_without_mutation`
   - 처음에는 exit cell이 UNSEEN이고 feature가 빈 값이다.
   - visible fixture에서도 locked direct/route goal은 `exit_locked`; snapshot/journal/route가
     exact 동일하다. 테스트용 world 직접 이동으로 acceptance를 만들지 않는다.
3. `test_showcase_entry_combat_reward_exit_complete_e2e`
   - seed `44/20260828`, `SHOWCASE_V1`로 시작한다.
   - route facade로 `(9,6)`까지 한 hop씩 진행해 CONTACT, 첫 유효 대형
     `WEDGE→LINE→COLUMN`, 기존 public combat action/commit으로 32턴 이내 승리한다.
   - 첫 `GROUPED_COMPLETE`에서 reward 1/EXIT_OPEN을 확인하고 출구 `(13,1)`까지 기존 route를
     진행한다. 마지막 MOVE 하나만 journal되고 COMPLETE/terminal이 된다.
   - 이후 WAIT/MOVE/route/turn은 `run_complete`, snapshot/journal exact 무변경이다.
4. `test_exit_open_and_complete_save_load_replay_exactly`
   - EXIT_OPEN 시점과 COMPLETE 시점 각각 v3 save→fresh load를 수행한다.
   - snapshot, journal, `run_progress()`가 source와 exact 같고 reward 효과 event는 없어야 한다.
5. `test_run_wire_tamper_is_transactional`
   - extra `run_progress` key는 `invalid_party_session_wire`다.
   - 빈 journal initial save의 scenario를 다른 known ID로 바꾸면
     `party_journal_snapshot_mismatch`이며 대상 live state는 변하지 않는다.
6. `test_restart_reuses_exact_identity_and_resets_run`
   - COMPLETE 뒤 restart하여 seeds/scenario가 동일하고 snapshot이 동일 seed로 새로 만든
     initial session과 exact 같으며 journal은 빈 배열, progress는 initial EXPLORE다.

`party_ui_layout_smoke.gd`는 두 viewport에서 objective 글자 잘림/겹침 0, locked feedback,
reward badge, COMPLETE의 단일 restart 버튼, 버튼 뒤 같은 Grid instance와 15×15 mapping을
검증한다. `tests/run_tests.gd`, Party UI smoke, `git diff --check`가 모두 성공해야 한다.

## 11. 완료 기준

한 seed에서 입장부터 완료·restart까지 UI로 막힘 없이 한 번 플레이할 수 있고, 같은
seed/scenario와 journal은 같은 final snapshot/run progress를 만든다. 보상과 출구를 위해
core 상태나 별도 명령이 생기지 않으며, 완료 뒤 어떤 gameplay 입력도 세계시간·step·journal을
늘리지 않는다. 위 테스트가 모두 green이면 P0 MVP run 슬라이스를 닫는다.
