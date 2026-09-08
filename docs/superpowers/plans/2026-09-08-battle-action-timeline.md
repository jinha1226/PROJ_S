# 상단 양방향 행동 타임라인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 전투(ENGAGED, DUO 자동전투) 중 상단 HUD 아래에 48px 양방향 "행동 준비/실행 타임라인"을 추가한다 — 아군은 왼쪽, 적은 오른쪽에서 중앙(행동 시점)으로 모이는 초상화. 코어 전투 규칙은 바꾸지 않는다.

**Architecture:** 순수 프레젠터(`battle_timeline_presenter.gd`)가 세션이 넘긴 값 딕셔너리를 `BattleTimelineState` DTO로 바꾼다. 세션은 읽기 전용 창구 `battle_timeline_state()`로 코어의 `busy_until`/`enemy_busy_rows`/awareness/최근 행동 이벤트를 모아 프레젠터에 넘긴다. 그리기·보간·겹침 그룹·탭은 `battle_timeline_bar.gd`(Control)가 맡고, 샌드박스는 표시/숨김·높이 예산·입력 보류·맵 강조만 연결한다. 타임라인은 저장하지 않는다.

**Tech Stack:** Godot 4.6 GDScript, headless 테스트(`godot --headless --path . --script res://tests/<file>.gd`), 기존 픽셀 스킨(`playtest/dark_pixel_ui_skin.gd`), 초상화 텍스처(`playtest/fixed_front_topdown_assets.gd`).

**Spec:** `docs/concepts/BATTLE_ACTION_TIMELINE_HANDOFF.ko.md` (구속력 있는 설계. 이 계획은 그 문서의 §3~§9를 태스크로 나눈 것이다.)

## Global Constraints

- **코어 무변경**: `sim/` 아래 파일은 수정하지 않는다. 조회는 RNG·이벤트·세계시간·기력·저널·준비 명령을 바꾸지 않는다(스펙 §7). `prepare_autonomous_party_turn()`을 그리기용으로 반복 호출하지 않는다.
- **준비 vs 실행 구분**: `ready_at`(코어의 `busy_until`), `eligible_at`(현재 배치/틱 규칙까지 고려한 가장 이른 실행 후보, 유도 불가면 null), `acted_at`(실제 커밋 이벤트 시각). 없는 값을 0으로 바꾸지 않는다.
- **적 표시 상한 3명 + `+N`**; 미발견 적·비참여 NPC는 숫자에도 포함하지 않는다. 아군은 번호(①②…), 적은 A/B/C 표식. 영구 entity id는 사용자에게 노출하지 않는다.
- **레이아웃**: 전투 중에만 높이 `48` 논리 px 한 줄, 기존 상단 HUD 아래·맵 위. 맵 위에 덮지 않고 실제 높이를 반영(`_current_grid_view_dimensions()` 포함). 초상화 24~28px, 중앙 표시 20~24px, 글씨 11~12px, 터치 영역 최소 48×48.
- **시간→위치**: `H=300` 세계시간(UI 설정값 한 곳), `remaining=max(0,ready_at-world_time)`, `ratio=clamp(remaining/H,0,1)`, 아군 `x=left_center_edge-ratio*left_rail`, 적 `x=right_center_edge+ratio*right_rail`. 개인별 비용 정규화 금지. `remaining=0`이면 중앙 `준비`. `remaining>H`면 최외곽 + 범위 밖 표식.
- **애니메이션**: 확정 상태 사이 위치 보간 최대 0.10초; 타임라인이 `commit_turn()`/기술 API를 호출하지 않는다; `autonomous_battle_clock.remaining`을 게이지로 쓰지 않는다; 정지·기술 대상 선택·드래그·모달 중 보간 정지(공용 presentation-blocked 상태 하나).
- **상단 터치**: 정보 확인만(대상 변경·시전·이동·자원 소비 없음), 맵으로 관통 금지, 누르는 동안 자동전투 보류 후 놓으면 원래 정지 상태 유지, 스킬 대상 선택 중 상단 탭 비활성, 그룹 목록은 모달(자동전투 보류).
- **저장**: 타임라인을 저장하지 않는다. 불러오기 시 코어에서 재구성, 과거 행동 플래시 재생 금지.
- **성능**: DTO 갱신은 커밋/관측/전투 상태 변화 시에만. 프레임마다 하는 일은 위치 보간뿐. 프레임당 전체 과거 로그를 훑지 않는다(이벤트 커서 유지).
- **테스트 환경**: 같은 디렉터리에서 `godot --headless` 두 개를 동시에 돌리지 않는다. 기존 `tests/battleheart_mvp_acceptance.gd`, `tests/battle_mobile_loot_acceptance.gd`, `tests/duo_autobattle_smoke.gd`는 계속 통과해야 한다.
- **커밋 트레일러**(두 줄): `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` / `Claude-Session: https://claude.ai/code/session_01RX9uXnpSFzBcMhdCE8MPBo`. 푸시·GitHub Actions 변경 금지.
- 워크트리: `/mnt/d/STARTU/living-world-sim-timeline` (브랜치 `feat/battle-action-timeline`, 베이스 `1e474bb` = HEAD 35ec549 + 미커밋 배틀 UI carry).

---

## File Structure

| 파일 | 책임 |
|---|---|
| `playtest/battle_timeline_presenter.gd` (new) | 순수 정적: 입력 딕셔너리 → `BattleTimelineState` DTO (진영·공개·준비 시각·eligible·그룹·다음 후보·최근 행동·hidden count) |
| `playtest/battle_timeline_bar.gd` (new) | 48px Control: 순수 `layout_spec(state,width)`, 그리기, 0.10s 보간, 겹침 그룹, 탭/홀드/그룹 신호, 입력 흡수 |
| `playtest/party_playtest_session.gd` (modify) | `battle_timeline_state()` 읽기 전용 창구 + 이벤트 커서 |
| `playtest/party_encounter_sandbox.gd` (modify) | 표시/숨김·루트 순서·높이 예산·`_battle_presentation_blocked()` 공용화·갱신 훅·맵/초상화 강조·그룹 목록 |
| `playtest/party_grid_view.gd` (modify, 소폭) | `set_actor_emphasis(entity_id, duration_msec)` 링 표시 |
| `tests/test_battle_timeline_presenter.gd` + `tests/run_battle_timeline_presenter_tests.gd` (new) | 프레젠터 단위 테스트 (경계 표 포함) |
| `tests/battle_timeline_acceptance.gd` (new) | 세션 창구 순수성, 실제 DUO 전투 대조, 바 레이아웃·입력·예산·성능 |
| `docs/concepts/BATTLE_ACTION_TIMELINE_REPORT.ko.md` (new, Task 6) | 예상/확정 구분, 묶음 한계 관찰, §10 제안 |

---

### Task 1: 프레젠터 (순수 DTO) + 경계 표 단위 테스트

**Files:**
- Create: `playtest/battle_timeline_presenter.gd`
- Create: `tests/test_battle_timeline_presenter.gd`, `tests/run_battle_timeline_presenter_tests.gd`

**Interfaces:**
- Produces: `BattleTimelinePresenter.build(input:Dictionary) -> Dictionary` (DTO 아래), `BattleTimelinePresenter.HORIZON_WORLD_TIME := 300`, `MAX_VISIBLE_ENEMIES := 3`, `ACTION_ROOT_TYPES := ["action.skill","action.move","action.melee_attack","action.hold","action.wait"]`.
- 입력 계약 (세션이 Task 2에서 만든다; 전부 값):
```text
input
  world_time:int, actor_interval:int (=100), phase:String (safe_phase), engaged:bool
  allies[]  entity_id, display_name, species_id, roster_slot, busy_until:int, alive:bool, can_act:bool
  enemies[] entity_id, display_name, species_id, busy_until:int, alive:bool, can_act:bool,
            visible:bool, aware:bool (awareness_state in ALERT/HUNTING)
  recent_events[] event_id, step_index, world_time, type, actor_id
```
- 출력 DTO (스펙 §7):
```text
{ revision:int, world_time:int, phase:String, visible:bool,
  entries:[ {entity_id, side:"ALLY"|"ENEMY", display_name, portrait_key:species_id,
             marker:"①"/"②"/…/"A"/"B"/"C", ready_at:int|null, eligible_at:int|null,
             status:"RECOVERING"|"READY"|"UNAVAILABLE",
             group_key:String, timing_confidence:"READINESS_ONLY"|"EXPECTED",
             is_next_candidate:bool} ],
  hidden_visible_enemy_count:int,
  recent_actions:[ {event_id, actor_id, acted_at, action_kind, batch_key} ] }
```

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/run_battle_timeline_presenter_tests.gd`는 `tests/run_expedition_cycle_tests.gd`를 그대로 복사해 `TEST_FILE := "test_battle_timeline_presenter.gd"`, 요약 문구를 `"Battle timeline presenter: %d tests, %d failed"`로 바꾼다.

`tests/test_battle_timeline_presenter.gd`:

```gdscript
extends "res://tests/test_case.gd"

const Presenter = preload("res://playtest/battle_timeline_presenter.gd")


func _ally(id: int, name: String, slot: int, busy: int, alive := true, can_act := true) -> Dictionary:
	return {"entity_id": id, "display_name": name, "species_id": "human", "roster_slot": slot,
		"busy_until": busy, "alive": alive, "can_act": can_act}


func _enemy(id: int, name: String, busy: int, visible := true, aware := true, alive := true) -> Dictionary:
	return {"entity_id": id, "display_name": name, "species_id": "goblin", "busy_until": busy,
		"alive": alive, "can_act": alive, "visible": visible, "aware": aware}


func _input(world_time: int, allies: Array, enemies: Array, events: Array = []) -> Dictionary:
	return {"world_time": world_time, "actor_interval": 100, "phase": "ENGAGED", "engaged": true,
		"allies": allies, "enemies": enemies, "recent_events": events}


func test_batch_boundary_allies_ready_together_are_one_group_at_center() -> bool:
	# Costs 80/120 in one party batch: the batch settled at 120, so both are READY now.
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 80), _ally(2, "B", 1, 120)], [_enemy(9, "g", 0)]))
	var a: Dictionary = state.entries[0]; var b: Dictionary = state.entries[1]
	check_eq(str(a.status), "READY", "ally ready before settle time is READY, not a fake new cooldown")
	check_eq(str(b.status), "READY", "ally ready exactly at settle time is READY")
	check_eq(int(a.ready_at), 80, "ready_at is the raw busy_until")
	check_eq(str(a.group_key), str(b.group_key), "same-time allies share one group key")
	check_eq(str(a.marker), "①", "allies carry roster numbers")
	check_eq(str(b.marker), "②", "second ally is ②")
	return finish()


func test_enemy_eligible_at_rounds_up_to_the_next_actor_tick() -> bool:
	# busy_until 170 but actor ticks run every 100: the earliest real chance is 200.
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 120)], [_enemy(9, "g", 170)]))
	var enemy: Dictionary = state.entries[1]
	check_eq(int(enemy.ready_at), 170, "enemy ready_at is the raw busy row")
	check_eq(int(enemy.eligible_at), 200, "enemy eligible_at is the next actor tick at or after ready_at")
	check_eq(str(enemy.timing_confidence), "EXPECTED", "tick-rounded enemy timing is an expectation, not a confirmation")
	check_eq(str(enemy.status), "RECOVERING", "future ready is RECOVERING")
	return finish()


func test_ready_ally_is_the_next_candidate_before_a_later_enemy() -> bool:
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 80)], [_enemy(9, "g", 170)]))
	check(bool(state.entries[0].is_next_candidate), "the earliest eligible entry is next")
	check(not bool(state.entries[1].is_next_candidate), "later entries are not next")
	check_eq(str(state.entries[0].timing_confidence), "READINESS_ONLY", "ally readiness is not a confirmed order")
	return finish()


func test_unaware_or_hidden_enemies_and_dead_actors_are_excluded() -> bool:
	var enemies := [_enemy(9, "g", 0), _enemy(10, "h", 0, false), _enemy(11, "u", 0, true, false), _enemy(12, "d", 0, true, true, false)]
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 120), _ally(2, "B", 1, 120, false)], enemies))
	var ids: Array = []
	for entry in state.entries: ids.append(int(entry.entity_id))
	check_eq(ids, [1, 9], "dead ally, hidden enemy, unaware enemy and dead enemy are all absent")
	check_eq(int(state.hidden_visible_enemy_count), 0, "hidden/unaware enemies never count toward +N")
	return finish()


func test_enemy_cap_three_earliest_and_hidden_count() -> bool:
	var enemies := [_enemy(9, "a", 300), _enemy(10, "b", 100), _enemy(11, "c", 200), _enemy(12, "d", 250), _enemy(13, "e", 150)]
	var state: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 120)], enemies))
	var enemy_ids: Array = []; var markers: Array = []
	for entry in state.entries:
		if str(entry.side) == "ENEMY": enemy_ids.append(int(entry.entity_id)); markers.append(str(entry.marker))
	check_eq(enemy_ids, [10, 13, 11], "only the three earliest visible participating enemies are shown, in time order")
	check_eq(markers, ["A", "B", "C"], "shown enemies carry A/B/C markers")
	check_eq(int(state.hidden_visible_enemy_count), 2, "the rest of the observed participants are counted as +N")
	return finish()


func test_next_candidate_moves_when_the_earliest_dies() -> bool:
	var alive: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 200)], [_enemy(9, "g", 100), _enemy(10, "h", 150)]))
	check_eq(int(_next(alive).entity_id), 9, "earliest live enemy is next")
	var dead: Dictionary = Presenter.build(_input(120, [_ally(1, "A", 0, 200)], [_enemy(9, "g", 100, true, true, false), _enemy(10, "h", 150)]))
	check_eq(int(_next(dead).entity_id), 10, "next candidate moves immediately when the earliest dies")
	return finish()


func test_recent_actions_use_root_events_only_and_batch_by_step() -> bool:
	var events := [
		{"event_id": 40, "step_index": 7, "world_time": 100, "type": "action.melee_attack", "actor_id": 1},
		{"event_id": 41, "step_index": 7, "world_time": 100, "type": "combat.physical_damage", "actor_id": -1},
		{"event_id": 42, "step_index": 7, "world_time": 100, "type": "action.hold", "actor_id": 2},
		{"event_id": 43, "step_index": 7, "world_time": 100, "type": "action.move", "actor_id": 9},
		{"event_id": 44, "step_index": 8, "world_time": 200, "type": "action.skill", "actor_id": 1},
	]
	var state: Dictionary = Presenter.build(_input(200, [_ally(1, "A", 0, 200), _ally(2, "B", 1, 200)], [_enemy(9, "g", 300)], events))
	check_eq(state.recent_actions.size(), 4, "derived damage events are not actions")
	check_eq(str(state.recent_actions[0].batch_key), str(state.recent_actions[2].batch_key), "same step shares a batch key")
	check(str(state.recent_actions[3].batch_key) != str(state.recent_actions[0].batch_key), "a new step is a new batch")
	check_eq(str(state.recent_actions[3].action_kind), "SKILL", "action kinds are derived from the root event type")
	return finish()


func test_not_engaged_is_invisible_and_pure() -> bool:
	var input := _input(120, [_ally(1, "A", 0, 120)], [_enemy(9, "g", 0)])
	input["engaged"] = false
	var frozen := JSON.stringify(input)
	var state: Dictionary = Presenter.build(input)
	check(not bool(state.visible), "timeline is hidden outside ENGAGED")
	check_eq(JSON.stringify(input), frozen, "build does not mutate its input")
	return finish()


func _next(state: Dictionary) -> Dictionary:
	for entry in state.entries:
		if bool(entry.is_next_candidate): return entry
	return {}
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_battle_timeline_presenter_tests.gd`
Expected: 스크립트 로드 실패(프레젠터 없음).

- [ ] **Step 3: 프레젠터 구현**

`playtest/battle_timeline_presenter.gd`:

```gdscript
class_name BattleTimelinePresenter
extends RefCounted

## Pure projection of core readiness into the top action timeline DTO.
## Reads only the value dictionary it is given; never touches world, RNG or time.
## Spec: docs/concepts/BATTLE_ACTION_TIMELINE_HANDOFF.ko.md §4, §7.

const HORIZON_WORLD_TIME := 300
const MAX_VISIBLE_ENEMIES := 3
const ACTION_ROOT_TYPES := ["action.skill", "action.move", "action.melee_attack", "action.hold", "action.wait"]
const ALLY_MARKERS := ["①", "②", "③", "④", "⑤", "⑥"]
const ENEMY_MARKERS := ["A", "B", "C"]


static func build(input: Dictionary) -> Dictionary:
	var world_time := int(input.get("world_time", 0))
	var interval := maxi(1, int(input.get("actor_interval", 100)))
	var engaged := bool(input.get("engaged", false))
	var entries: Array = []
	var allies: Array = input.get("allies", [])
	var ally_rows: Array = []
	for raw in allies:
		if not raw is Dictionary or not bool(raw.get("alive", false)): continue
		ally_rows.append(raw)
	ally_rows.sort_custom(func(a, b): return int(a.roster_slot) < int(b.roster_slot) \
		if int(a.roster_slot) != int(b.roster_slot) else int(a.entity_id) < int(b.entity_id))
	for index in range(ally_rows.size()):
		var row: Dictionary = ally_rows[index]
		var ready_at := int(row.busy_until)
		entries.append(_entry(row, "ALLY", ALLY_MARKERS[mini(index, ALLY_MARKERS.size() - 1)],
			ready_at, null, world_time, bool(row.get("can_act", true)), "READINESS_ONLY"))
	var enemy_rows: Array = []
	for raw in input.get("enemies", []):
		if not raw is Dictionary or not bool(raw.get("alive", false)) \
				or not bool(raw.get("visible", false)) or not bool(raw.get("aware", false)): continue
		enemy_rows.append(raw)
	enemy_rows.sort_custom(func(a, b): return int(a.busy_until) < int(b.busy_until) \
		if int(a.busy_until) != int(b.busy_until) else int(a.entity_id) < int(b.entity_id))
	var hidden := maxi(0, enemy_rows.size() - MAX_VISIBLE_ENEMIES)
	for index in range(mini(MAX_VISIBLE_ENEMIES, enemy_rows.size())):
		var row: Dictionary = enemy_rows[index]
		var ready_at := int(row.busy_until)
		# Enemies act only on actor ticks: the earliest real chance is the first tick
		# at or after max(ready_at, now). This is an expectation, not a confirmation.
		var eligible_at := _ceil_to_interval(maxi(ready_at, world_time), interval)
		entries.append(_entry(row, "ENEMY", ENEMY_MARKERS[index], ready_at, eligible_at, world_time,
			bool(row.get("can_act", true)), "EXPECTED"))
	_assign_groups(entries)
	_mark_next(entries)
	return {"revision": 0, "world_time": world_time, "phase": str(input.get("phase", "")),
		"visible": engaged and not entries.is_empty(), "entries": entries,
		"hidden_visible_enemy_count": hidden,
		"recent_actions": _recent_actions(input.get("recent_events", []))}


static func _entry(row: Dictionary, side: String, marker: String, ready_at: int, eligible_at,
		world_time: int, can_act: bool, confidence: String) -> Dictionary:
	var status := "UNAVAILABLE"
	if can_act: status = "READY" if ready_at <= world_time else "RECOVERING"
	return {"entity_id": int(row.entity_id), "side": side, "display_name": str(row.get("display_name", "")),
		"portrait_key": str(row.get("species_id", "")), "marker": marker,
		"ready_at": ready_at, "eligible_at": eligible_at, "status": status,
		"group_key": "", "timing_confidence": confidence, "is_next_candidate": false}


static func _ceil_to_interval(value: int, interval: int) -> int:
	return int(ceil(float(value) / float(interval))) * interval


static func _assign_groups(entries: Array) -> void:
	# Same side + same effective time = same group. Readiness (ready_at) groups allies;
	# expected tick (eligible_at) groups enemies. Groups never mix sides.
	for entry in entries:
		var moment = entry.eligible_at if entry.eligible_at != null else entry.ready_at
		entry["group_key"] = "%s@%d" % [str(entry.side), int(moment)]


static func _mark_next(entries: Array) -> void:
	var best_time := -1; var best_key := ""
	for entry in entries:
		if str(entry.status) == "UNAVAILABLE": continue
		var moment := int(entry.eligible_at if entry.eligible_at != null else entry.ready_at)
		if best_key.is_empty() or moment < best_time:
			best_time = moment; best_key = str(entry.group_key)
	for entry in entries:
		entry["is_next_candidate"] = not best_key.is_empty() and str(entry.group_key) == best_key


static func _recent_actions(events: Array) -> Array:
	var rows: Array = []
	for raw in events:
		if not raw is Dictionary: continue
		var type := str(raw.get("type", ""))
		if type not in ACTION_ROOT_TYPES: continue
		rows.append({"event_id": int(raw.get("event_id", -1)), "actor_id": int(raw.get("actor_id", -1)),
			"acted_at": int(raw.get("world_time", 0)),
			"action_kind": type.trim_prefix("action.").to_upper().replace("MELEE_ATTACK", "ATTACK"),
			"batch_key": "step:%d" % int(raw.get("step_index", -1))})
	rows.sort_custom(func(a, b): return int(a.event_id) < int(b.event_id))
	return rows
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/run_battle_timeline_presenter_tests.gd`
Expected: 8 tests, 0 failed. (`_next` 헬퍼는 테스트 파일 안의 일반 함수라 `test_` 접두사 없이 안전하다.)

- [ ] **Step 5: 커밋**

```bash
git add playtest/battle_timeline_presenter.gd playtest/battle_timeline_presenter.gd.uid tests/test_battle_timeline_presenter.gd tests/test_battle_timeline_presenter.gd.uid tests/run_battle_timeline_presenter_tests.gd tests/run_battle_timeline_presenter_tests.gd.uid
git commit -m "feat(timeline): add the pure battle action timeline presenter with boundary tests"
```

---

### Task 2: 세션 읽기 전용 창구 `battle_timeline_state()`

**Files:**
- Modify: `playtest/party_playtest_session.gd` (`is_duo_autobattle()` 근처 ~520행에 새 함수 추가; preload 블록에 프레젠터)
- Create: `tests/battle_timeline_acceptance.gd` (SceneTree 스크립트, `tests/battleheart_mvp_acceptance.gd`의 `_check`/`_check_eq`/`_case`/`_new_engaged_duo` 패턴을 그대로 복사해 독립 파일로 둔다 — 상속하지 않는다)

**Interfaces:**
- Consumes: `BattleTimelinePresenter.build(input)`; 코어 읽기: `sim.world.world_time`, `sim.world.party_encounter.active_party_member_ids`, `member(id).busy_until`, `enemy_busy_rows`, `enemy_awareness(id).awareness_state`, `sim.world.can_act(id, now)`, `sim.world.occupies_tile(id)`, `sim.world.entities[id]`(display_name, species_id), `party_status().visible_enemy_ids`, `sim.world.events` (마지막 `TIMELINE_EVENT_WINDOW := 64`개만), `WorldState.ACTOR_INTERVAL`.
- Produces: `func battle_timeline_state() -> Dictionary` (DTO, `duplicate(true)`), 내부 캐시 `_timeline_cache:Dictionary`와 키 `(step_index, world_time, revision, events.size())`; 캐시가 맞으면 같은 DTO 복사본을 돌려준다.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/battle_timeline_acceptance.gd` (핵심 케이스만; Task 3~5에서 케이스를 덧붙인다):

```gdscript
extends SceneTree

const Session = preload("res://playtest/party_playtest_session.gd")
const Presenter = preload("res://playtest/battle_timeline_presenter.gd")
const WORLD_SEED := 44
const PERSONALITY_SEED := 20260828
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")

func _run() -> void:
	_case("timeline_query_is_pure_and_matches_core", _timeline_query_is_pure_and_matches_core)
	_case("timeline_hides_outside_engaged_and_survives_reload", _timeline_hides_outside_engaged_and_survives_reload)
	if failures.is_empty(): print("PASS battle timeline acceptance")
	else:
		for failure in failures: printerr("FAIL ", failure)
		print("FAIL battle timeline acceptance: ", failures.size(), " failures")
	quit(1 if not failures.is_empty() else 0)

# _case/_check/_check_eq/_new_engaged_duo: copy verbatim from tests/battleheart_mvp_acceptance.gd

func _timeline_query_is_pure_and_matches_core() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	var world = session.sim.world
	var before_hash := JSON.stringify(world.snapshot()).sha256_text()
	var journal_before: int = session.command_journal.size()
	var events_before: int = world.events.size()
	var state: Dictionary = session.battle_timeline_state()
	var again: Dictionary = session.battle_timeline_state()
	_check_eq(JSON.stringify(world.snapshot()).sha256_text(), before_hash, "timeline query leaves the snapshot untouched")
	_check_eq(session.command_journal.size(), journal_before, "timeline query writes no journal row")
	_check_eq(world.events.size(), events_before, "timeline query emits no event")
	_check_eq(JSON.stringify(state), JSON.stringify(again), "repeated query is identical (cached)")
	_check(bool(state.visible), "engaged duo battle shows the timeline")
	var party = world.party_encounter
	for entry in state.entries:
		var id := int(entry.entity_id)
		if str(entry.side) == "ALLY":
			_check_eq(int(entry.ready_at), int(party.member(id).busy_until), "ally ready_at mirrors busy_until")
		else:
			_check_eq(int(entry.ready_at), int(party.enemy_busy_rows.get(id, 0)), "enemy ready_at mirrors the busy row")
			_check(id in session.party_status().visible_enemy_ids, "shown enemies are visible participants")
	# One autonomous commit: recent actions must cite real root events of that step.
	var planning: Dictionary = session.prepare_autonomous_party_turn()
	_check(bool(planning.get("commit_ready", false)), "autonomous plan is committable")
	var result: Dictionary = session.commit_turn()
	_check(bool(result.get("accepted", false)), "autonomous commit accepted")
	var after: Dictionary = session.battle_timeline_state()
	_check(after.recent_actions.size() >= 1, "committed turn yields recent root actions")
	var step := int(world.step_index)
	for action in after.recent_actions:
		var event = world.event_by_id(int(action.event_id))
		_check(event != null and str(event.type) in Presenter.ACTION_ROOT_TYPES, "recent action cites a real root event")
		_check_eq(int(action.acted_at), int(event.world_time), "acted_at is the event world time")
	_check(JSON.stringify(after) != JSON.stringify(state), "state revision changes after a commit")
	return true

func _timeline_hides_outside_engaged_and_survives_reload() -> bool:
	var fresh = Session.new(WORLD_SEED, PERSONALITY_SEED, Session.DUO_SCENARIO_ID)
	_check(not bool(fresh.battle_timeline_state().visible), "exploration shows no timeline")
	var session = _new_engaged_duo()
	if session == null: return false
	var saved: String = session.save_session_json()
	var reloaded = Session.new(WORLD_SEED, PERSONALITY_SEED, Session.DUO_SCENARIO_ID)
	_check(bool(reloaded.load_session_json(saved).get("accepted", false)), "engaged save reloads")
	var rebuilt: Dictionary = reloaded.battle_timeline_state()
	_check(bool(rebuilt.visible), "reloaded engaged battle rebuilds the timeline from core state")
	_check(rebuilt.recent_actions.is_empty() or int(rebuilt.recent_actions.back().acted_at) <= int(reloaded.sim.world.world_time), "reload never replays future actions")
	return true
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/battle_timeline_acceptance.gd`
Expected: `battle_timeline_state` 없음 에러.

- [ ] **Step 3: 세션 창구 구현**

`playtest/party_playtest_session.gd` — preload 블록에 `const BattleTimelinePresenterScript=preload("res://playtest/battle_timeline_presenter.gd")`, 상수 `const TIMELINE_EVENT_WINDOW := 64`, 변수 `var _timeline_cache:Dictionary={}`, 그리고 `is_duo_autobattle()` 아래에:

```gdscript
func battle_timeline_state()->Dictionary:
	# Read-only presentation query. Never touches RNG, events, world time, energy,
	# journal or staged plans; a cache keyed on authoritative counters makes
	# repeated UI reads free.
	if sim==null or sim.world==null or sim.world.party_encounter==null:
		return BattleTimelinePresenterScript.build({"engaged":false,"allies":[],"enemies":[]})
	var world=sim.world;var state=world.party_encounter
	var key:="%d|%d|%d|%d"%[int(world.step_index),int(world.world_time),int(state.revision),world.events.size()]
	if str(_timeline_cache.get("key",""))==key:return _timeline_cache.dto.duplicate(true)
	var status:Dictionary=party_status()
	var allies:Array=[]
	for member_id_value in state.active_party_member_ids:
		var member_id:=int(member_id_value);var member=state.member(member_id)
		var entity=world.entities.get(member_id)
		if member==null or entity==null:continue
		allies.append({"entity_id":member_id,"display_name":str(entity.display_name),
			"species_id":str(entity.species_id),"roster_slot":int(member.roster_slot),
			"busy_until":int(member.busy_until),"alive":world.occupies_tile(member_id),
			"can_act":world.can_act(member_id,int(world.world_time))})
	var visible_ids:Array=status.get("visible_enemy_ids",[])
	var enemies:Array=[]
	for enemy_id_value in state.enemy_ids:
		var enemy_id:=int(enemy_id_value);var entity=world.entities.get(enemy_id)
		if entity==null:continue
		var awareness=state.enemy_awareness(enemy_id)
		enemies.append({"entity_id":enemy_id,"display_name":str(entity.display_name),
			"species_id":str(entity.species_id),"busy_until":int(state.enemy_busy_rows.get(enemy_id,0)),
			"alive":world.occupies_tile(enemy_id),"can_act":world.can_act(enemy_id,int(world.world_time)),
			"visible":enemy_id in visible_ids,
			"aware":awareness!=null and str(awareness.awareness_state) in ["ALERT","HUNTING"]})
	var recent:Array=[]
	var start:=maxi(0,world.events.size()-TIMELINE_EVENT_WINDOW)
	for index in range(start,world.events.size()):
		var event=world.events[index]
		recent.append({"event_id":int(event.id),"step_index":int(event.step_index),
			"world_time":int(event.world_time),"type":str(event.type),"actor_id":int(event.actor_id)})
	var dto:Dictionary=BattleTimelinePresenterScript.build({"world_time":int(world.world_time),
		"actor_interval":int(world.ACTOR_INTERVAL),"phase":str(state.safe_phase),
		"engaged":str(state.safe_phase)=="ENGAGED" and str(status.get("view_mode",""))=="COMBAT",
		"allies":allies,"enemies":enemies,"recent_events":recent})
	dto["revision"]=int(state.revision)
	_timeline_cache={"key":key,"dto":dto.duplicate(true)}
	return dto.duplicate(true)
```

`WorldState.ACTOR_INTERVAL`이 `const`라 인스턴스로 접근이 안 되면 `WorldStateScript.ACTOR_INTERVAL`(세션의 기존 preload 이름을 확인)로 바꾼다. `party_status()`가 `visible_enemy_ids`를 COMBAT 밖에서 비우는 점은 그대로 둔다(탐험 중 타임라인은 어차피 숨김).

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/battle_timeline_acceptance.gd`
Expected: `PASS battle timeline acceptance`.
Run: `godot --headless --path . --script res://tests/battleheart_mvp_acceptance.gd` → `PASS battleheart MVP acceptance: 7 bounded cases` (변화 없어야 함).

- [ ] **Step 5: 커밋**

```bash
git add playtest/party_playtest_session.gd tests/battle_timeline_acceptance.gd tests/battle_timeline_acceptance.gd.uid
git commit -m "feat(timeline): expose a read-only battle_timeline_state session query"
```

---

### Task 3: 48px 타임라인 바 컨트롤 (순수 레이아웃 + 그리기 + 보간)

**Files:**
- Create: `playtest/battle_timeline_bar.gd`
- Modify: `tests/battle_timeline_acceptance.gd` (레이아웃 케이스 추가)

**Interfaces:**
- Produces: `class_name BattleTimelineBar extends Control`:
  - `static func layout_spec(state:Dictionary, width:float, height:float=48.0) -> Dictionary` — 순수. 반환 `{"center":Rect2, "left_rail":Rect2, "right_rail":Rect2, "items":[{entity_ids:[..], side, x, marker, portrait_key, status, is_next, out_of_range, group_label:""|"근접한 차례"|"같은 행동 묶음", touch:Rect2}], "hidden_label":"+N"|"" }`. 겹침 규칙: 같은 진영에서 터치 사각형(48×48, x 중심)이 겹치면 한 항목으로 합친다(대표=가장 이른 것, `entity_ids` 전부). 같은 `group_key`면 `같은 행동 묶음`, 다른 group_key인데 겹치면 `근접한 차례`.
  - `func set_state(state:Dictionary) -> void` — DTO 저장 후 목표 위치 계산, 0.10초 보간 시작(이전 보간은 최신으로 대체).
  - `func set_presentation_blocked(blocked:bool) -> void` — 보간 정지/재개(재개 시 밀린 시간을 몰아 처리하지 않음: 남은 보간만 이어감).
  - `func flash_actor(entity_id:int) -> void` — 중앙 강조 0.8초(그림만).
  - 신호: `entry_tapped(entity_ids:Array)`, `pointer_held(held:bool)`.
  - 입력: `_gui_input`에서 ScreenTouch/MouseButton을 모두 `accept_event()`로 흡수(맵 관통 금지). `mouse_filter = MOUSE_FILTER_STOP`. 스킬 대상 선택 등으로 비활성일 때(`set_taps_enabled(false)`) 탭 신호를 내지 않되 입력은 여전히 흡수.
- 그리기: 초상화는 `fixed_front_topdown_assets.body_texture(species)` / `monster_texture(species)`를 24~28px 사각형에 `draw_texture_rect_region(tex, rect, Rect2(48,16,160,160))`(compact_party_portrait와 동일 크롭). 아군 파란 계열 테두리+왼쪽 화살표 방향, 적 붉은 계열 테두리+오른쪽 — 색만이 아니라 좌우와 표식으로 구분. 중앙 20~24px `행동` 영역, `준비` 글자 11px. `다음`/`예상` 라벨은 그룹 아래 11px. `+N`은 오른쪽 끝 보조 글자(버튼 아님). 범위 밖 항목엔 `…` 표식.

- [ ] **Step 1: 실패하는 테스트 추가** (`tests/battle_timeline_acceptance.gd`)

```gdscript
const Bar = preload("res://playtest/battle_timeline_bar.gd")

func _bar_layout_places_sides_center_groups_and_cap() -> bool:
	var entries := [
		{"entity_id":1,"side":"ALLY","display_name":"A","portrait_key":"human","marker":"①","ready_at":80,"eligible_at":null,"status":"READY","group_key":"ALLY@80","timing_confidence":"READINESS_ONLY","is_next_candidate":true},
		{"entity_id":2,"side":"ALLY","display_name":"B","portrait_key":"human","marker":"②","ready_at":80,"eligible_at":null,"status":"READY","group_key":"ALLY@80","timing_confidence":"READINESS_ONLY","is_next_candidate":true},
		{"entity_id":9,"side":"ENEMY","display_name":"g","portrait_key":"goblin","marker":"A","ready_at":170,"eligible_at":200,"status":"RECOVERING","group_key":"ENEMY@200","timing_confidence":"EXPECTED","is_next_candidate":false},
		{"entity_id":10,"side":"ENEMY","display_name":"h","portrait_key":"goblin","marker":"B","ready_at":700,"eligible_at":700,"status":"RECOVERING","group_key":"ENEMY@700","timing_confidence":"EXPECTED","is_next_candidate":false},
	]
	var state := {"revision":1,"world_time":120,"phase":"ENGAGED","visible":true,"entries":entries,"hidden_visible_enemy_count":2,"recent_actions":[]}
	for width in [360.0, 390.0]:
		var spec: Dictionary = Bar.layout_spec(state, width)
		var ally_items: Array = []; var enemy_items: Array = []
		for item in spec.items:
			if str(item.side) == "ALLY": ally_items.append(item) else: enemy_items.append(item)
		_check_eq(ally_items.size(), 1, "%d: two allies at the same moment collapse into one group item" % int(width))
		_check_eq(ally_items[0].entity_ids, [1, 2], "%d: group item lists both allies" % int(width))
		_check_eq(str(ally_items[0].group_label), "같은 행동 묶음", "%d: same group key is labelled as one batch" % int(width))
		_check(float(ally_items[0].x) < spec.center.position.x + 0.5 and float(ally_items[0].x) >= spec.center.position.x - 1.0, "%d: ready allies sit at the left edge of the center zone" % int(width))
		_check_eq(enemy_items.size(), 2, "%d: enemies at different times stay separate" % int(width))
		var near: Dictionary = enemy_items[0]; var far: Dictionary = enemy_items[1]
		_check(float(near.x) > spec.center.end.x - 0.5 and float(near.x) < float(far.x), "%d: nearer enemy is closer to center on the right" % int(width))
		_check(bool(far.out_of_range) and float(far.x) >= spec.right_rail.end.x - 24.0, "%d: beyond-horizon enemy is pinned at the outer end with a marker" % int(width))
		_check_eq(str(spec.hidden_label), "+2", "%d: hidden participants show as +N" % int(width))
		for item in spec.items:
			var touch: Rect2 = item.touch
			_check(touch.size.x >= 47.9 and touch.size.y >= 47.9, "%d: every touch target is at least 48px" % int(width))
			_check(touch.position.x >= -0.1 and touch.end.x <= width + 0.1, "%d: touch targets stay inside the bar" % int(width))
	return true
```
`_run()`의 `_case` 목록에 `_case("bar_layout_places_sides_center_groups_and_cap", _bar_layout_places_sides_center_groups_and_cap)` 추가.

- [ ] **Step 2: 실패 확인** — Run the acceptance script; expected: preload 실패.

- [ ] **Step 3: 바 구현**

`playtest/battle_timeline_bar.gd` 골격(그리기 세부는 구현자가 채우되 아래 상수·함수·규칙은 그대로):

```gdscript
class_name BattleTimelineBar
extends Control

## Top bidirectional action timeline (allies left, enemies right, center = act).
## Presentation only: never calls commit/skill APIs; interpolates ≤ 0.10 s between
## committed states. Spec: docs/concepts/BATTLE_ACTION_TIMELINE_HANDOFF.ko.md §3–§6.

signal entry_tapped(entity_ids: Array)
signal pointer_held(held: bool)

const Presenter = preload("res://playtest/battle_timeline_presenter.gd")
const Assets = preload("res://playtest/fixed_front_topdown_assets.gd")
const Skin = preload("res://playtest/dark_pixel_ui_skin.gd")
const BAR_HEIGHT := 48.0
const CENTER_WIDTH := 24.0
const PORTRAIT_SIZE := 26.0
const TOUCH_SIZE := 48.0
const LERP_DURATION_MSEC := 100
const FLASH_DURATION_MSEC := 800
const PORTRAIT_CROP := Rect2(48, 16, 160, 160)

var _state: Dictionary = {}
var _target_x: Dictionary = {}     # item key -> target x
var _shown_x: Dictionary = {}      # item key -> currently drawn x
var _lerp_started_msec := -1
var _blocked := false
var _taps_enabled := true
var _flash_until := {}             # entity_id -> msec
var _held_index := -1


static func layout_spec(state: Dictionary, width: float, height: float = BAR_HEIGHT) -> Dictionary:
	var center := Rect2((width - CENTER_WIDTH) * 0.5, 0.0, CENTER_WIDTH, height)
	var left_rail := Rect2(TOUCH_SIZE * 0.5, 0.0, center.position.x - TOUCH_SIZE * 0.5, height)
	var right_rail := Rect2(center.end.x, 0.0, width - center.end.x - TOUCH_SIZE * 0.5, height)
	var world_time := int(state.get("world_time", 0))
	var raw_items: Array = []
	for entry in state.get("entries", []):
		var remaining := maxi(0, int(entry.ready_at) - world_time) if entry.get("ready_at") != null else 0
		var moment = entry.eligible_at if entry.get("eligible_at") != null else entry.get("ready_at")
		if moment != null: remaining = maxi(0, int(moment) - world_time)
		var ratio := clampf(float(remaining) / float(Presenter.HORIZON_WORLD_TIME), 0.0, 1.0)
		var out_of_range := remaining > Presenter.HORIZON_WORLD_TIME
		var x := center.position.x - ratio * left_rail.size.x if str(entry.side) == "ALLY" \
			else center.end.x + ratio * right_rail.size.x
		raw_items.append({"entity_ids": [int(entry.entity_id)], "side": str(entry.side), "x": x,
			"marker": str(entry.marker), "portrait_key": str(entry.portrait_key), "status": str(entry.status),
			"is_next": bool(entry.is_next_candidate), "out_of_range": out_of_range,
			"group_keys": [str(entry.group_key)], "group_label": "", "remaining": remaining,
			"touch": Rect2(x - TOUCH_SIZE * 0.5, 0.0, TOUCH_SIZE, height)})
	raw_items.sort_custom(func(a, b): return float(a.x) < float(b.x))
	var items: Array = []
	for item in raw_items:
		if not items.is_empty() and str(items.back().side) == str(item.side) \
				and items.back().touch.intersects(item.touch):
			var merged: Dictionary = items.back()
			merged.entity_ids.append_array(item.entity_ids)
			merged.group_keys.append_array(item.group_keys)
			merged["is_next"] = bool(merged.is_next) or bool(item.is_next)
			var same_batch := merged.group_keys.all(func(k): return k == merged.group_keys[0])
			merged["group_label"] = "같은 행동 묶음" if same_batch else "근접한 차례"
			continue
		items.append(item)
	for item in items:
		item["touch"] = Rect2(clampf(float(item.touch.position.x), 0.0, width - TOUCH_SIZE), 0.0, TOUCH_SIZE, height)
	var hidden := int(state.get("hidden_visible_enemy_count", 0))
	return {"center": center, "left_rail": left_rail, "right_rail": right_rail, "items": items,
		"hidden_label": "+%d" % hidden if hidden > 0 else ""}
```
규칙: 대표 초상화는 그룹의 첫 항목(가장 이른 것; 정렬 순서상 아군은 center에 가까운 쪽이 먼저 오도록 `x` 정렬 후 아군 그룹은 `remaining` 오름차순으로 대표를 고른다). `set_state()`는 `layout_spec`을 호출해 `_target_x[key]`를 갱신하고 `_lerp_started_msec`를 지금으로 리셋(이전 보간 대체). `_process`는 `_blocked`가 아니면 `_shown_x`를 `_target_x`로 0.10초 선형 보간하고 `queue_redraw()`. 새 항목은 보간 없이 목표 위치에서 시작. `_draw()`는 레일(어두운 선), 중앙 영역(`Skin.BRASS` 테두리, `행동` 11px), 항목(초상화 26px + 표식 + 인원수 배지 + `준비`/`다음`/`예상`/범위밖 `…`), `hidden_label`을 오른쪽 끝에 그린다. 아군 테두리 `Color("#508cb0")`+왼쪽 삼각 화살표, 적 `Skin.BLOOD`+오른쪽 삼각 화살표. `_gui_input`: 누르면 `_held_index`를 잡고 `pointer_held.emit(true)`, `accept_event()`; 놓으면 같은 항목 위면 `entry_tapped.emit(entity_ids)`(단 `_taps_enabled`일 때), `pointer_held.emit(false)`, `accept_event()`. 모바일 중복 마우스(`event.device == InputEvent.DEVICE_ID_EMULATION`)는 무시.

- [ ] **Step 4: 통과 확인** — acceptance PASS (레이아웃 케이스 포함).

- [ ] **Step 5: 커밋**

```bash
git add playtest/battle_timeline_bar.gd playtest/battle_timeline_bar.gd.uid tests/battle_timeline_acceptance.gd
git commit -m "feat(timeline): add the 48px bidirectional timeline bar with pure layout"
```

---

### Task 4: 샌드박스 통합 — 표시/숨김, 높이 예산, 공용 presentation-blocked, 갱신 훅

**Files:**
- Modify: `playtest/party_encounter_sandbox.gd`
  - `_build_ui()` (~750행, `phase_panel` 생성 직후) — 바 생성
  - `_apply_product_root_order()` (~1954행) — product 순서: `phase_panel, battle_timeline_bar, grid, event_surface, cards, …`
  - `_apply_screen_budget()` (~6377행) / `_current_grid_view_dimensions()` (~6114행) — 바가 보일 때 48 차감
  - `_tick_autonomous_battle()` (~2313행) — blocked 계산을 `_battle_presentation_blocked() -> bool`로 추출해 양쪽이 공유
  - `_refresh()`와 `_record_result()` 뒤 — `battle_timeline_bar.set_state(session.battle_timeline_state())`; `_maybe_open_battle_loot` 열림·`safe_phase != ENGAGED`·`not is_duo_autobattle()`이면 `visible=false`
  - `_process()` — 매 프레임 `battle_timeline_bar.set_presentation_blocked(_battle_presentation_blocked() or autonomous_battle_clock.paused)`
- Modify: `tests/battle_timeline_acceptance.gd` (통합 케이스)

**Interfaces:**
- Produces: `var battle_timeline_bar` (노드 이름 `BattleTimelineBar`), `func _battle_presentation_blocked() -> bool`, `func _timeline_visible() -> bool` (= `_portrait_battle_controls_visible() and battle_loot_panel not visible`).

- [ ] **Step 1: 실패하는 테스트 추가**

```gdscript
const Sandbox = preload("res://playtest/party_encounter_sandbox.gd")

func _sandbox_shows_timeline_only_in_engaged_duo_and_keeps_budget() -> bool:
	for width in [360.0, 390.0]:
		var session = _new_engaged_duo()
		if session == null: return false
		var ui = Sandbox.new(); ui.size = Vector2(width, 800)
		ui.initialize_for_headless_test(session, true)
		ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); ui.size = Vector2(width, 800)
		root.add_child(ui); ui.set_process(false)
		await process_frame; await process_frame
		var bar: Control = ui.battle_timeline_bar
		_check(bar != null and bar.is_visible_in_tree(), "%d: timeline visible in engaged duo battle" % int(width))
		_check(absf(bar.size.y - 48.0) < 0.5, "%d: timeline occupies exactly 48px" % int(width))
		_check(bar.get_global_rect().position.y >= ui.phase_panel.get_global_rect().end.y - 0.5 \
			and bar.get_global_rect().end.y <= ui.grid.get_global_rect().position.y + 0.5,
			"%d: timeline sits between the top HUD and the map without overlap" % int(width))
		var siblings: Array = []
		for child in ui.root_layout.get_children():
			if child is Control and child.is_visible_in_tree(): siblings.append(child)
		var prior_end := -1.0
		for child in siblings:
			_check(child.get_global_rect().position.y + 0.5 >= prior_end, "%d: root children never overlap (%s)" % [int(width), child.name])
			prior_end = maxf(prior_end, child.get_global_rect().end.y)
		_check(ui.grid.get_global_rect().end.y <= 800.5 and ui.cards.get_global_rect().end.y <= 800.5, "%d: map and party stay inside the viewport" % int(width))
		# Autonomous clock and the bar share one blocked predicate.
		ui._battle_target_mode = "SKILL"
		_check(ui._battle_presentation_blocked(), "%d: skill targeting blocks presentation" % int(width))
		ui._battle_target_mode = ""
		_check(not ui._battle_presentation_blocked(), "%d: idle battle is not blocked" % int(width))
		# Leaving ENGAGED hides the bar and returns its height.
		ui.battle_loot_panel.show(); ui._refresh(); await process_frame
		_check(not bar.visible, "%d: loot window hides the timeline" % int(width))
		ui.battle_loot_panel.hide()
		ui.queue_free(); await process_frame
	return true
```
(`_new_engaged_duo()`가 엔진 트리에 노드를 붙이지 않는지 확인; 붙인다면 그 노드를 재사용한다.)

- [ ] **Step 2: 실패 확인** — `battle_timeline_bar` 속성 없음.

- [ ] **Step 3: 구현**

1. `_build_ui()`: `phase_panel`을 `root_layout`에 붙인 직후
```gdscript
	battle_timeline_bar=BattleTimelineBarScript.new();battle_timeline_bar.name="BattleTimelineBar"
	battle_timeline_bar.custom_minimum_size.y=BattleTimelineBarScript.BAR_HEIGHT
	battle_timeline_bar.visible=false;root_layout.add_child(battle_timeline_bar)
	battle_timeline_bar.entry_tapped.connect(_on_timeline_entry_tapped)
	battle_timeline_bar.pointer_held.connect(_on_timeline_pointer_held)
```
(preload `const BattleTimelineBarScript=preload("res://playtest/battle_timeline_bar.gd")`; 핸들러 두 개는 Task 5에서 채우므로 여기서는 빈 함수로 둔다.)
2. `_apply_product_root_order(product_hud)`: product 분기 첫 줄을 `root_layout.move_child(phase_panel,0);root_layout.move_child(battle_timeline_bar,1);root_layout.move_child(grid,2);root_layout.move_child(event_surface,3);root_layout.move_child(cards,4)`로.
3. `_timeline_visible()`: `_portrait_battle_controls_visible() and (battle_loot_panel==null or not battle_loot_panel.visible)`.
4. `_current_grid_view_dimensions()`의 `map_extent` 높이 식에 `-(BattleTimelineBarScript.BAR_HEIGHT if _timeline_visible() else 0)` 추가; `_apply_screen_budget()`의 product 분기에서 같은 조건으로 `battle_timeline_bar.custom_minimum_size.y`를 48/0으로 두고 `battle_timeline_bar.visible=_timeline_visible()`.
5. `_battle_presentation_blocked()`: `_tick_autonomous_battle`의 `blocked` 계산(모달·터치·표적·드래그·제스처·메뉴 팝업·오더 에디터)을 그대로 옮기고, `_tick_autonomous_battle`은 `var blocked:=_battle_presentation_blocked()`만 쓴다. Task 5에서 `_timeline_group_list_open`과 `_timeline_pointer_held`를 여기에 추가한다.
6. 갱신: `_refresh()` 끝(`_flush_pending_visual_effects()` 앞)과 `_refresh_direct_solo_combat_surface()`/`_refresh_continuous_exploration_surface()` 끝에 `_sync_battle_timeline()`:
```gdscript
func _sync_battle_timeline()->void:
	if battle_timeline_bar==null:return
	var show:=_timeline_visible()
	battle_timeline_bar.visible=show
	if show:battle_timeline_bar.set_state(session.battle_timeline_state())
```
`_record_result()`는 이미 `_request_refresh()` 경로로 이어지는지 확인하고, 이어지지 않는 커밋 경로(자동전투 tick의 `_record_result` 뒤 `_request_refresh()`)는 그대로 두면 된다 — 갱신은 refresh에서만.
7. `_process()`의 `_tick_autonomous_battle(_delta)` 바로 앞에 `if battle_timeline_bar!=null and battle_timeline_bar.visible:battle_timeline_bar.set_presentation_blocked(_battle_presentation_blocked() or autonomous_battle_clock.paused)`.

- [ ] **Step 4: 통과 확인**

Run sequentially: `battle_timeline_acceptance.gd` (PASS), `duo_autobattle_smoke.gd`, `battleheart_mvp_acceptance.gd`, `battle_mobile_loot_acceptance.gd` (전부 기존과 동일 PASS), 그리고 `party_ui_layout_smoke.gd`/`party_ui_visual_style_smoke.gd`는 **베이스(1e474bb) 대비 FAIL 목록이 동일**해야 한다(두 스모크는 이 브랜치와 무관한 사유로 이미 빨간 줄이 있을 수 있다 — 먼저 베이스에서 한 번 돌려 목록을 저장한다).

- [ ] **Step 5: 커밋**

```bash
git add playtest/party_encounter_sandbox.gd tests/battle_timeline_acceptance.gd
git commit -m "feat(timeline): mount the battle timeline between the HUD and the map with shared presentation blocking"
```

---

### Task 5: 상단 터치 — 탭 강조, 홀드 보류, 그룹 목록, 맵 관통 금지

**Files:**
- Modify: `playtest/party_encounter_sandbox.gd` (`_on_timeline_entry_tapped`, `_on_timeline_pointer_held`, 그룹 목록 팝업, `_battle_presentation_blocked` 확장)
- Modify: `playtest/party_grid_view.gd` — `func set_actor_emphasis(entity_id:int, duration_msec:int) -> void` + `_draw()`에서 해당 액터 셀에 `Skin.BRASS` 링(두께 2) 표시, 만료 시 자동 제거(`_draw_actor_selection_overlays()` 옆에 그린다)
- Modify: `playtest/compact_party_portrait.gd` — `var emphasized_until_msec:=-1`; `_draw()`에서 유효하면 `selected` 테두리와 같은 방식의 `Skin.BRASS` 2px 테두리
- Modify: `tests/battle_timeline_acceptance.gd`

**Interfaces:**
- `_on_timeline_entry_tapped(entity_ids:Array)`: 1명 → `grid.set_actor_emphasis(id, 800)` + 해당 `MemberCard<id>`(아군)의 초상화 `emphasized_until_msec=now+800` + `event_label.text = "<이름> · 준비"/"회복 중 (남은 N)"`; 2명 이상 → 그룹 목록 팝업(`PopupPanel`, 각 행 Button 높이 48, 이름+표식+상태), 선택 시 위 단일 동작, 바깥 터치/닫기/뒤로 가기로 닫힘. 팝업 열림 = 모달 → `_battle_presentation_blocked()` true, `grid.modal_open=true` 처리와 동일하게 자동전투 보류.
- `_on_timeline_pointer_held(held)`: `_timeline_pointer_held=held` → `_battle_presentation_blocked()`에 포함(놓으면 원래 `autonomous_battle_clock.paused`는 그대로).
- 스킬 대상 선택 중(`not _battle_target_mode.is_empty()`)에는 `battle_timeline_bar.set_taps_enabled(false)`; 해제 시 true. `_refresh`에서 동기화.

- [ ] **Step 1: 실패하는 테스트 추가** (실제 Input 경로)

```gdscript
func _timeline_touch_highlights_and_never_reaches_the_map() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	var ui = Sandbox.new(); ui.size = Vector2(390, 800)
	ui.initialize_for_headless_test(session, true)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); ui.size = Vector2(390, 800)
	root.add_child(ui); ui.set_process(false)
	await process_frame; await process_frame
	var bar = ui.battle_timeline_bar
	var spec: Dictionary = bar.layout_spec(session.battle_timeline_state(), bar.size.x)
	_check(not spec.items.is_empty(), "layout has at least one item")
	var item: Dictionary = spec.items[0]
	var point: Vector2 = bar.get_global_rect().position + item.touch.get_center()
	var snapshot_before := JSON.stringify(session.sim.world.snapshot()).sha256_text()
	var journal_before: int = session.command_journal.size()
	var press := InputEventScreenTouch.new(); press.index = 61; press.pressed = true; press.position = point
	root.push_input(press, true); await process_frame
	_check(ui._battle_presentation_blocked(), "holding the timeline blocks autonomous battle")
	var release := InputEventScreenTouch.new(); release.index = 61; release.pressed = false; release.position = point
	root.push_input(release, true); await process_frame; await process_frame
	_check(not ui._battle_presentation_blocked() or ui.find_child("TimelineGroupList", true, false) != null, "release restores the prior pause state (or opened a group list)")
	_check_eq(JSON.stringify(session.sim.world.snapshot()).sha256_text(), snapshot_before, "timeline tap changes no authoritative state")
	_check_eq(session.command_journal.size(), journal_before, "timeline tap writes no journal row")
	if item.entity_ids.size() == 1:
		var id := int(item.entity_ids[0])
		_check(ui.grid.actor_emphasis_active(id), "single tap emphasizes the actor on the map")
	else:
		var list = ui.find_child("TimelineGroupList", true, false)
		_check(list != null and list.visible, "group tap opens the member list as a modal")
		_check(ui._battle_presentation_blocked(), "open group list blocks autonomous battle")
		var first_row: Button = null
		for child in list.find_children("*", "Button", true, false):
			first_row = child; break
		_check(first_row != null and first_row.size.y >= 47.9, "group rows are at least 48px tall")
		if first_row != null: first_row.pressed.emit(); await process_frame
		_check(list == null or not list.visible, "choosing a member closes the list")
	# Skill targeting disables timeline taps but still swallows the touch.
	ui._battle_target_mode = "SKILL"; ui._refresh(); await process_frame
	var hero_position: Vector2i = session.sim.world.entities[int(session.sim.world.party_encounter.protagonist_id)].position
	var step_before: int = session.sim.world.step_index
	root.push_input(press, true); root.push_input(release, true); await process_frame; await process_frame
	_check_eq(int(session.sim.world.step_index), step_before, "timeline touch during targeting is inert and does not move the hero")
	ui._battle_target_mode = ""
	ui.queue_free(); await process_frame
	return true
```
`grid.actor_emphasis_active(id) -> bool`를 `party_grid_view.gd`에 함께 추가한다(테스트 전용이 아니라 강조 상태 질의).

- [ ] **Step 2: 실패 확인** — `set_actor_emphasis` 없음 / 강조 미동작.

- [ ] **Step 3: 구현** (위 인터페이스대로). 그룹 목록 `PopupPanel` 이름 `TimelineGroupList`, `popup_hide` 신호에서 `_timeline_group_list_open=false`. `_battle_presentation_blocked()`에 `or _timeline_pointer_held or _timeline_group_list_open` 추가. `grid.modal_open`는 건드리지 않는다(맵 제스처는 바가 흡수하므로 불필요).

- [ ] **Step 4: 통과 확인** — `battle_timeline_acceptance.gd` PASS; `duo_autobattle_smoke.gd`, `battleheart_mvp_acceptance.gd`, `battle_mobile_loot_acceptance.gd` PASS.

- [ ] **Step 5: 커밋**

```bash
git add playtest/party_encounter_sandbox.gd playtest/party_grid_view.gd playtest/compact_party_portrait.gd tests/battle_timeline_acceptance.gd
git commit -m "feat(timeline): timeline taps highlight actors, hold pauses autobattle, groups open a modal list"
```

---

### Task 6: 인수 검사, 성능 측정, 보고서

**Files:**
- Modify: `tests/battle_timeline_acceptance.gd` (성능 케이스)
- Create: `docs/concepts/BATTLE_ACTION_TIMELINE_REPORT.ko.md`

- [ ] **Step 1: 성능 케이스 추가**

```gdscript
func _timeline_query_and_layout_cost_is_bounded() -> bool:
	var session = _new_engaged_duo()
	if session == null: return false
	# Grow the ledger: many autonomous commits, then measure a cold and a cached query.
	for i in range(40):
		if session.sim.world.party_encounter.safe_phase != "ENGAGED": break
		if not bool(session.prepare_autonomous_party_turn().get("commit_ready", false)): break
		if not bool(session.commit_turn().get("accepted", false)): break
	var t0 := Time.get_ticks_usec(); var state: Dictionary = session.battle_timeline_state(); var cold := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec(); session.battle_timeline_state(); var cached := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec(); Bar.layout_spec(state, 390.0); var layout := Time.get_ticks_usec() - t0
	print("timeline cost usec: cold=%d cached=%d layout=%d events=%d" % [cold, cached, layout, session.sim.world.events.size()])
	_check(cached < cold or cached < 500, "cached query is cheaper than a cold one")
	_check(layout < 2000, "layout of a few items stays well under a frame")
	return true
```

- [ ] **Step 2: 전체 검사** (순서대로, 동시 실행 금지)

```bash
godot --headless --path . --script res://tests/run_battle_timeline_presenter_tests.gd
godot --headless --path . --script res://tests/battle_timeline_acceptance.gd
godot --headless --path . --script res://tests/duo_autobattle_smoke.gd
godot --headless --path . --script res://tests/battleheart_mvp_acceptance.gd
godot --headless --path . --script res://tests/battle_mobile_loot_acceptance.gd
godot --headless --path . --script res://tests/run_product_tests.gd
godot --headless --path . --script res://tests/party_ui_layout_smoke.gd
godot --headless --path . --script res://tests/party_ui_visual_style_smoke.gd
godot --headless --path . --export-release Web /tmp/timeline-web/index.html
```
Expected: 새 스크립트 PASS, 기존 스크립트 베이스와 동일 결과(FAIL 목록 diff 비어야 함), Web export 성공. 소스 폴더 밖 PCK 시작은 README의 배포 절차대로 한 번 시도하고 결과를 보고서에 적는다(실패해도 원인만 기록).

- [ ] **Step 3: 보고서 작성** `docs/concepts/BATTLE_ACTION_TIMELINE_REPORT.ko.md`
- 고정 시드(44/20260828 DUO) 전투의 실제 표: 시작 시각, 아군 `busy_until`, 적 busy/tick, 행동 이벤트 5~10줄 (Task 2 테스트 실행 중 print로 뽑아 붙인다).
- `예상`(eligible_at, 적 틱 반올림)과 `확정`(acted_at, 실제 이벤트)의 구분 설명.
- 묶음 한계 관찰: 아군이 중앙에 함께 대기하는 빈도(40턴 샘플 중 비율)와 그것이 스펙 §2대로 정직한 표시라는 점.
- 알려진 한계와 §10(개인별 게이지 = 스케줄러 변경) 별도 제안 요약.
- 실행한 검사 명령과 결과(성능 usec 포함), 휴대폰 실기 가독성은 미검증임을 명시.

- [ ] **Step 4: 커밋**

```bash
git add tests/battle_timeline_acceptance.gd docs/concepts/BATTLE_ACTION_TIMELINE_REPORT.ko.md
git commit -m "test(timeline): bound query/layout cost and record the batch-behaviour report"
```
