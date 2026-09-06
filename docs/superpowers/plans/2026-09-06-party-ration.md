# 파티 식량(배고픔) 시스템 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 파티 단위 식량 게이지 하나로 픽셀던전식 생존 압박(감소 → 자동 식사 → 굶주림 피해·스트레스)을 결정론적 시뮬레이션과 product HUD에 추가한다.

**Architecture:** 권위 데이터는 `PartyEncounterState`의 `ration_milli`/`ration_processed_at` 두 정수(스키마 22). 정적 시스템 `sim/systems/party_ration_system.gd`가 `party_encounter_coordinator.process_tick`에서 월드 시간 경과분만큼 감소·자동식사·굶주림 피해를 처리하고 `party.ration_*` 이벤트를 발행한다. 수치는 `data/content/hunger_rules.json`, 식량 아이템·드롭·시장은 기존 JSON/카탈로그 데이터로만 추가한다. 피해는 `damage_system.apply_damage`, 스트레스는 `party_morale_model`, 대사는 `party_emotion_model`이 새 이벤트를 소비한다.

**Tech Stack:** Godot 4.6 GDScript, headless 테스트(`godot --headless --path . --script res://tests/<file>.gd`), `tests/test_case.gd` 기반 테스트(`check`, `check_eq`, `finish`).

**Spec:** `docs/superpowers/specs/2026-09-06-party-ration-design.md`

## Global Constraints

- 시스템은 RNG·프레임 시간·UI를 읽지 않는다. 입력은 `world.world_time`, 활성 파티원 수, 주인공 인벤토리뿐이다.
- 코드에 밸런스 숫자를 쓰지 않는다. 전부 `data/content/hunger_rules.json`에서 읽는다.
- `PartyEncounterState` 스키마는 22로 올리고, 구세이브(schema < 22)는 만복으로 로드한다.
- 이벤트 이름: `party.ration_changed`, `party.ration_eaten`, `party.ration_missing`, `party.ration_starve_tick`, 피해는 `combat.starvation_damage` (damage_type `"starvation"`).
- 식량 아이템 ID `FOOD_RATION`, `category:"CONSUMABLE"`, `use_kind:"EAT"`. 수동 사용 UI는 없다.
- 절대 두 개의 `godot --headless` 프로세스를 같은 프로젝트 디렉터리에서 동시에 돌리지 않는다(전역 클래스 캐시가 깨져 무관한 파싱 에러가 난다).
- 콘텐츠 JSON을 고치면 같은 파일의 `content_version`을 올리고 `jq empty data/content/*.json` + `godot --headless --path . --script res://tests/run_json_content_database_tests.gd`를 돌린다.
- 커밋 메시지 끝: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` 와 `Claude-Session: https://claude.ai/code/session_01RX9uXnpSFzBcMhdCE8MPBo`.
- `tests/test_party_enemy_awareness.gd`의 LOS 테스트 2개는 이 작업 전(fca3877)부터 실패한다. 회귀 신호가 아니다.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `data/content/hunger_rules.json` (new) | 식량 규칙 수치 단일 원본 |
| `sim/party_ration_rules.gd` (new) | 규칙 JSON 로드·검증, 상수 접근, band 계산 (순수 정적) |
| `sim/party_encounter_state.gd` (modify) | `ration_milli`, `ration_processed_at` 필드·스키마 22·wire 검증 |
| `sim/systems/party_ration_system.gd` (new) | 감소·자동식사·굶주림 피해·이벤트 발행 (정적, coordinator에서 호출) |
| `sim/systems/party_encounter_coordinator.gd` (modify) | `process_tick`에서 ration 시스템 호출 |
| `sim/simulator.gd` (modify) | 마을 자동 귀환 시 게이지 리셋 |
| `sim/world_state.gd` (modify) | `combat.starvation_damage` / starvation 사망 이벤트 검증 허용 |
| `sim/party_morale_model.gd`, `sim/party_emotion_model.gd` (modify) | `party.ration_*` 이벤트 → 스트레스·감정 |
| `sim/species_drop_registry.gd` (modify) | 드롭 테이블에 CONSUMABLE 허용 |
| `data/content/items.json`, `data/content/species_drop_tables.json` (modify) | 식량 아이템·고블린 드롭 |
| `playtest/party_playtest_session.gd` (modify) | 시장 카탈로그·시작 인벤토리·출발 리셋·층 바닥 식량·DTO·로그 문구 |
| `playtest/party_encounter_sandbox.gd` (modify) | 상단 rail 식량 게이지 |
| `tests/test_party_ration.gd`, `tests/run_party_ration_tests.gd` (new) | 단위 테스트 |
| `tests/run_ration_balance_sim.gd` (new) | 밸런스 시뮬 |
| `tests/party_ui_visual_style_smoke.gd` (modify) | rail 게이지 계약 |

---

### Task 1: 규칙 콘텐츠와 로더

**Files:**
- Create: `data/content/hunger_rules.json`
- Create: `sim/party_ration_rules.gd`
- Create: `tests/test_party_ration.gd`
- Create: `tests/run_party_ration_tests.gd`

**Interfaces:**
- Produces: `PartyRationRules` (class_name) with
  - `static func rules() -> Dictionary` — 검증된 규칙 딕셔너리(정수 값)
  - `static func registry_error() -> String` — 빈 문자열이면 유효
  - `static func ration_max_milli() -> int`
  - `static func band(ration_milli:int) -> String` — `"FED" | "HUNGRY" | "STARVING"`
  - `static func drain_per_interval_milli(active_count:int) -> int`

- [ ] **Step 1: 규칙 JSON 작성**

`data/content/hunger_rules.json`:

```json
{
  "content_schema_version": 1,
  "content_version": "hunger-2026-09-06",
  "content_type": "HUNGER_RULES",
  "ruleset_id": "party-ration-v1",
  "ration_max": 300,
  "hungry_below": 100,
  "drain_interval": 100,
  "drain_per_interval_milli": 1000,
  "drain_extra_member_milli": 500,
  "starve_interval": 100,
  "starve_damage": 1,
  "starve_stress": 4,
  "food_definition_id": "FOOD_RATION",
  "food_nutrition": 300
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`tests/run_party_ration_tests.gd` (기존 `run_expedition_cycle_tests.gd`와 동일 구조):

```gdscript
extends SceneTree

const TEST_FILE := "test_party_ration.gd"


func _init() -> void:
	var total := 0
	var failed := 0
	var script = load("res://tests/" + TEST_FILE)
	if script == null or not script.can_instantiate():
		printerr("FAIL %s :: script failed to load" % TEST_FILE)
		quit(1)
		return
	var probe = script.new()
	for method in probe.get_method_list():
		if not method.name.begins_with("test_"): continue
		total += 1
		var test_case = script.new()
		var completed = test_case.call(method.name)
		if completed != true and test_case.errors.is_empty():
			test_case.errors.append("test did not return explicit true completion")
		if test_case.errors.is_empty():
			print("PASS %s :: %s" % [TEST_FILE, method.name])
		else:
			failed += 1
			for error in test_case.errors:
				print("FAIL %s :: %s -- %s" % [TEST_FILE, method.name, error])
	print("---- Party ration: %d tests, %d failed ----" % [total, failed])
	quit(1 if failed > 0 else 0)
```

`tests/test_party_ration.gd`:

```gdscript
extends "res://tests/test_case.gd"

const Rules = preload("res://sim/party_ration_rules.gd")


func test_rules_load_and_bands_are_derived_from_content() -> bool:
	check_eq(Rules.registry_error(), "", "hunger_rules.json validates")
	var rules: Dictionary = Rules.rules()
	check_eq(int(rules.ration_max), 300, "ration_max read from content")
	check_eq(Rules.ration_max_milli(), 300000, "max is stored in milli")
	check_eq(Rules.band(300000), "FED", "full gauge is FED")
	check_eq(Rules.band(100000), "FED", "exactly hungry_below is still FED")
	check_eq(Rules.band(99999), "HUNGRY", "below hungry_below is HUNGRY")
	check_eq(Rules.band(0), "STARVING", "zero is STARVING")
	check_eq(Rules.drain_per_interval_milli(1), 1000, "solo drains base rate")
	check_eq(Rules.drain_per_interval_milli(3), 2000, "each extra member adds 500 milli")
	check_eq(Rules.drain_per_interval_milli(0), 1000, "zero members clamps to one")
	return finish()
```

- [ ] **Step 3: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `FAIL ... script failed to load` 또는 파싱 에러(`party_ration_rules.gd` 없음).

- [ ] **Step 4: 로더 구현**

`sim/party_ration_rules.gd`:

```gdscript
class_name PartyRationRules
extends RefCounted

## Single authority for party ration numbers. Reads data/content/hunger_rules.json
## once; every consumer asks this script instead of holding its own constants.

const CONTENT_PATH := "res://data/content/hunger_rules.json"
const CONTENT_TYPE := "HUNGER_RULES"
const RULESET_ID := "party-ration-v1"
const ContentLoaderScript = preload("res://sim/json_content_loader.gd")
const EXPECTED_KEYS := ["content_schema_version", "content_version", "content_type",
	"ruleset_id", "ration_max", "hungry_below", "drain_interval",
	"drain_per_interval_milli", "drain_extra_member_milli", "starve_interval",
	"starve_damage", "starve_stress", "food_definition_id", "food_nutrition"]
const INTEGER_KEYS := ["ration_max", "hungry_below", "drain_interval",
	"drain_per_interval_milli", "drain_extra_member_milli", "starve_interval",
	"starve_damage", "starve_stress", "food_nutrition"]

static var _CONTENT: Dictionary = ContentLoaderScript.load_document(CONTENT_PATH)


static func rules() -> Dictionary:
	return _CONTENT.duplicate(true)


static func registry_error() -> String:
	var document_error := ContentLoaderScript.document_error(_CONTENT, CONTENT_TYPE, EXPECTED_KEYS)
	if not document_error.is_empty(): return document_error
	if str(_CONTENT.get("ruleset_id", "")) != RULESET_ID: return "hunger_ruleset_mismatch"
	for key in INTEGER_KEYS:
		if not _CONTENT.get(key) is int or int(_CONTENT[key]) < 1:
			return "hunger_rule_not_positive_integer:%s" % key
	if int(_CONTENT.hungry_below) >= int(_CONTENT.ration_max): return "hunger_threshold_above_max"
	if int(_CONTENT.food_nutrition) > int(_CONTENT.ration_max): return "hunger_nutrition_above_max"
	if not _CONTENT.get("food_definition_id") is String \
			or str(_CONTENT.food_definition_id).is_empty():
		return "hunger_food_definition_invalid"
	return ""


static func ration_max_milli() -> int:
	return int(_CONTENT.get("ration_max", 0)) * 1000


static func hungry_below_milli() -> int:
	return int(_CONTENT.get("hungry_below", 0)) * 1000


static func food_nutrition_milli() -> int:
	return int(_CONTENT.get("food_nutrition", 0)) * 1000


static func band(ration_milli: int) -> String:
	if ration_milli <= 0: return "STARVING"
	if ration_milli < hungry_below_milli(): return "HUNGRY"
	return "FED"


static func drain_per_interval_milli(active_count: int) -> int:
	var extra := maxi(0, active_count - 1)
	return int(_CONTENT.get("drain_per_interval_milli", 0)) \
		+ int(_CONTENT.get("drain_extra_member_milli", 0)) * extra
```

- [ ] **Step 5: 통과 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `PASS test_party_ration.gd :: test_rules_load_and_bands_are_derived_from_content`, `0 failed`.

Run: `jq empty data/content/*.json && godot --headless --path . --script res://tests/run_json_content_database_tests.gd`
Expected: 기존과 동일하게 통과 (새 파일은 그 테스트가 읽지 않는다).

- [ ] **Step 6: 커밋**

```bash
git add data/content/hunger_rules.json sim/party_ration_rules.gd tests/test_party_ration.gd tests/run_party_ration_tests.gd
git commit -m "feat(ration): add party ration rules content and loader"
```

---

### Task 2: 파티 상태 필드와 스키마 22

**Files:**
- Modify: `sim/party_encounter_state.gd` (상단 상수 블록, `var` 블록 ~85행, `to_dict` ~134행, `from_dict` ~195행, `wire_error` 키 목록 ~276행과 체인 ~299행, 값 검증 ~471행)
- Test: `tests/test_party_ration.gd`

**Interfaces:**
- Consumes: `PartyRationRules.ration_max_milli()`
- Produces: `PartyEncounterState.ration_milli:int`, `PartyEncounterState.ration_processed_at:int`, `PartyEncounterState.RATION_SCHEMA_VERSION := 22`, `func reset_ration(now:int) -> void`

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/test_party_ration.gd`에 추가:

```gdscript
const Session = preload("res://playtest/party_playtest_session.gd")
const PartyState = preload("res://sim/party_encounter_state.gd")


func test_state_persists_ration_and_legacy_saves_load_full() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	check_eq(int(state.schema_version), 22, "fresh state uses ration schema")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "fresh run starts full")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"fresh run anchors the drain clock at creation time")
	state.ration_milli = 123456
	var wire: Dictionary = state.to_dict()
	check(wire.has("ration_milli") and wire.has("ration_processed_at"),
		"v22 wire carries both ration keys")
	check_eq(PartyState.wire_error(wire, session.sim.world.width, session.sim.world.height), "",
		"v22 wire validates")
	var restored = PartyState.from_dict(wire)
	check_eq(int(restored.ration_milli), 123456, "round trip keeps the gauge")
	check_eq(int(restored.ration_processed_at), int(state.ration_processed_at),
		"round trip keeps the drain clock")
	var legacy: Dictionary = wire.duplicate(true)
	legacy.erase("ration_milli"); legacy.erase("ration_processed_at")
	legacy["schema_version"] = 21
	check_eq(PartyState.wire_error(legacy, session.sim.world.width, session.sim.world.height), "",
		"v21 wire without ration keys still validates")
	var migrated = PartyState.from_dict(legacy)
	check_eq(int(migrated.ration_milli), Rules.ration_max_milli(), "legacy save loads full")
	check_eq(int(migrated.schema_version), 22, "legacy save upgrades to v22")
	var broken: Dictionary = wire.duplicate(true)
	broken["ration_milli"] = Rules.ration_max_milli() + 1
	check(not PartyState.wire_error(broken, session.sim.world.width, session.sim.world.height).is_empty(),
		"gauge above max is rejected")
	var negative: Dictionary = wire.duplicate(true)
	negative["ration_milli"] = -1
	check(not PartyState.wire_error(negative, session.sim.world.width, session.sim.world.height).is_empty(),
		"negative gauge is rejected")
	var missing: Dictionary = wire.duplicate(true)
	missing.erase("ration_milli")
	check(not PartyState.wire_error(missing, session.sim.world.width, session.sim.world.height).is_empty(),
		"v22 wire without ration keys is rejected")
	check_eq(session.sim.world.world_state_error(), "", "world with ration state stays canonical")
	return finish()
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `FAIL ... fresh state uses ration schema` (21 != 22) 등.

- [ ] **Step 3: 상태 구현**

`sim/party_encounter_state.gd`:

1. 상수 블록 끝(`MEMORY_STATE_SCHEMA_VERSION := 21` 아래)에:
```gdscript
# v22 persists the shared party ration gauge and its drain clock.
const RATION_SCHEMA_VERSION := 22
```
그리고 `const SCHEMA_VERSION := 21` → `const SCHEMA_VERSION := 22`.

2. preload 블록(`ExpeditionCycleScript` 옆)에:
```gdscript
const RationRulesScript = preload("res://sim/party_ration_rules.gd")
```

3. `var activated_anchor_portal_floors:Array[int]=[]` 아래에:
```gdscript
var ration_milli: int = RationRulesScript.ration_max_milli()
var ration_processed_at: int = 0


func reset_ration(now: int) -> void:
	ration_milli = RationRulesScript.ration_max_milli()
	ration_processed_at = now
```

4. `to_dict()`의 `if schema_version >= ANCHOR_PORTAL_SCHEMA_VERSION:` 블록 뒤에:
```gdscript
	if schema_version >= RATION_SCHEMA_VERSION:
		wire["ration_milli"] = ration_milli
		wire["ration_processed_at"] = str(ration_processed_at)
```

5. `from_dict()`의 `activated_anchor_portal_floors` 루프 뒤, `return state` 앞에:
```gdscript
	if int(row.get("schema_version", 1)) >= RATION_SCHEMA_VERSION:
		state.ration_milli = int(row.ration_milli)
		state.ration_processed_at = Int64CodecScript.parse(row.ration_processed_at, "ration clock")
	else:
		state.ration_milli = RationRulesScript.ration_max_milli()
		state.ration_processed_at = 0
```

6. `wire_error()` 키 목록: `v19_keys` 정의 아래에
```gdscript
	var v22_keys:Array=v19_keys.duplicate();v22_keys.append_array(["ration_milli","ration_processed_at"]);v22_keys.sort()
```
체인의 마지막 두 줄을 다음으로 바꾼다:
```gdscript
		or (parsed_schema_version == EMOTION_STATE_SCHEMA_VERSION and keys != v19_keys) \
		or (parsed_schema_version == MEMORY_STATE_SCHEMA_VERSION and keys != v19_keys) \
		or (parsed_schema_version == SCHEMA_VERSION and keys != v22_keys):
```

7. `wire_error()`의 `if parsed_schema_version>=ANCHOR_PORTAL_SCHEMA_VERSION:` 블록 뒤에:
```gdscript
	if parsed_schema_version>=RATION_SCHEMA_VERSION:
		if not _integer(row.get("ration_milli")) or int(row.ration_milli)<0 \
				or int(row.ration_milli)>RationRulesScript.ration_max_milli():
			return "invalid_ration_milli"
		if not Int64CodecScript.is_canonical(row.get("ration_processed_at")) \
				or Int64CodecScript.parse(row.ration_processed_at,"ration clock")<0:
			return "invalid_ration_processed_at"
```

8. 세션이 새 런을 만들 때 시각을 고정한다. `playtest/party_playtest_session.gd` 424행 부근 `state.expedition_cycle=ExpeditionCycleScript.active(1,candidate.world.world_time, ...)` 바로 뒤:
```gdscript
	state.reset_ration(int(candidate.world.world_time))
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: 2 tests, 0 failed.

Run: `godot --headless --path . --script res://tests/run_expedition_cycle_tests.gd`
Expected: 기존과 동일 통과 (save/load/replay가 v22 키를 받아들임).

- [ ] **Step 5: 커밋**

```bash
git add sim/party_encounter_state.gd playtest/party_playtest_session.gd tests/test_party_ration.gd
git commit -m "feat(ration): persist party ration gauge in encounter state v22"
```

---

### Task 3: 식량 아이템, 드롭, 시장, 시작 인벤토리

**Files:**
- Modify: `data/content/items.json` (definitions 배열, `content_version`)
- Modify: `data/content/species_drop_tables.json`
- Modify: `sim/species_drop_registry.gd:86-87` (카테고리 허용)
- Modify: `playtest/party_playtest_session.gd` (`TOWN_MARKET_CATALOG` ~96행, 시작 인벤토리 ~415행, 아이템 DTO `usable` ~1173행)
- Test: `tests/test_party_ration.gd`

**Interfaces:**
- Produces: 아이템 정의 `FOOD_RATION`; 시작 인벤토리 인스턴스 `START_RATION_001` (수량 2); 시장 행 `{"definition_id":"FOOD_RATION","price":6,"stock":6}`; 드롭 roll `GOBLIN_RATION`.

- [ ] **Step 1: 실패하는 테스트 추가**

```gdscript
const ItemRegistry = preload("res://sim/item_registry.gd")
const DropRegistry = preload("res://sim/species_drop_registry.gd")


func test_food_ration_content_market_and_start_bag() -> bool:
	var definition = ItemRegistry.definition("FOOD_RATION")
	check(definition != null and str(definition.category) == "CONSUMABLE" \
		and str(definition.use_kind) == "EAT" and int(definition.stack_limit) == 10,
		"FOOD_RATION is a stackable EAT consumable")
	check_eq(DropRegistry.registry_error(), "", "drop tables accept a consumable ration roll")
	var dropped := false
	for death_event_id in range(1, 200):
		for roll in DropRegistry.rolls_for(44, death_event_id, "goblin"):
			if str(roll.definition_id) == "FOOD_RATION": dropped = true
	check(dropped, "goblins can drop a ration within 200 deterministic rolls")
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	var start_ration = session.sim.world.inventory_of(hero_id).item("START_RATION_001")
	check(start_ration != null and str(start_ration.definition_id) == "FOOD_RATION" \
		and int(start_ration.quantity) == 2, "hero starts with two rations")
	var catalog_ids: Array = []
	for row in Session.TOWN_MARKET_CATALOG: catalog_ids.append(str(row.definition_id))
	check("FOOD_RATION" in catalog_ids, "town market sells rations")
	var manual: Dictionary = session.use_inventory_item("START_RATION_001")
	check(not bool(manual.get("accepted", false)), "rations are never used by hand")
	check_eq(int(session.sim.world.inventory_of(hero_id).item("START_RATION_001").quantity), 2,
		"rejected manual use consumes nothing")
	return finish()
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `FAIL ... FOOD_RATION is a stackable EAT consumable`.

- [ ] **Step 3: 콘텐츠·코드 수정**

`data/content/items.json`: `content_version`을 `"items-2026-09-06"`으로 올리고 `definitions` 배열에 `POTION_HEALING` 행 바로 뒤 추가:
```json
{"definition_id": "FOOD_RATION", "label": "배급 식량", "category": "CONSUMABLE", "stack_limit": 10, "equip_slots": [], "weapon_id": "", "requirements": {"STR": 0, "DEX": 0, "INT": 0}, "bonuses": {"armor_flat": 0, "parry_milli": 0, "dodge_milli": 0, "stealth": 0}, "use_kind": "EAT", "placeholder": false}
```
(파일의 기존 행 포맷/들여쓰기를 그대로 따른다.)

`data/content/species_drop_tables.json`: `content_version` → `"2026-09-06"`, goblin `rolls`에 추가. roll_id는 정렬 순서를 지켜야 하므로 `GOBLIN_EAR` **앞**이 아니라 뒤에 온다 (`"GOBLIN_EAR" < "GOBLIN_RATION"`):
```json
{"roll_id": "GOBLIN_RATION", "definition_id": "FOOD_RATION", "chance_per_1000": 300, "min_quantity": 1, "max_quantity": 1}
```

`sim/species_drop_registry.gd` `_table_error`:
```gdscript
		if definition == null or str(definition.category) not in ["MATERIAL", "CONSUMABLE"]:
			return "invalid_species_drop_definition"
```

`playtest/party_playtest_session.gd`:
- `TOWN_MARKET_CATALOG` 첫 행 앞에 `{"definition_id":"FOOD_RATION","price":6,"stock":6},`
- 시작 인벤토리 배열에서 `ItemScript.new("START_POTION_001","POTION_HEALING",3)],` → 
```gdscript
		ItemScript.new("START_POTION_001","POTION_HEALING",3),
		ItemScript.new("START_RATION_001","FOOD_RATION",2)],
```
- ~1173행 `"usable":str(definition.use_kind)!="NONE",` → `"usable":str(definition.use_kind)=="HEALING",`

- [ ] **Step 4: 통과 확인**

Run: `jq empty data/content/*.json && godot --headless --path . --script res://tests/run_json_content_database_tests.gd`
Expected: 통과.

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: 3 tests, 0 failed.

Run: `godot --headless --path . --script res://tests/run_weapon_vertical_slice_tests.gd` 와 `res://tests/run_corpse_drop_materialization_tests.gd`
Expected: 기존과 동일 통과. (시작 인벤토리 슬롯 수·드롭 개수를 고정한 테스트가 깨지면, 그 테스트의 기대값을 식량 1스택 추가에 맞게 갱신한다 — 예: 가방 항목 수 +1.)

- [ ] **Step 5: 커밋**

```bash
git add data/content/items.json data/content/species_drop_tables.json sim/species_drop_registry.gd playtest/party_playtest_session.gd tests/test_party_ration.gd
git commit -m "feat(ration): add FOOD_RATION content, goblin drop, market row and start bag"
```

---

### Task 4: 감소·구간 이벤트·마을 리셋

**Files:**
- Create: `sim/systems/party_ration_system.gd`
- Modify: `sim/systems/party_encounter_coordinator.gd:47-64` (`process_tick`)
- Modify: `sim/simulator.gd:794-801` (`_reconcile_expedition_cycle`)
- Modify: `playtest/party_playtest_session.gd` ~1941행 (`state.expedition_cycle=next_cycle` 출발 경로)
- Test: `tests/test_party_ration.gd`

**Interfaces:**
- Consumes: `PartyRationRules`, `PartyEncounterState.ration_milli/ration_processed_at/reset_ration`, `world.emit_event(type, actor, target, position, magnitude, cause_id, data)`, `world.has_event_id_headroom(n)`
- Produces: `PartyRationSystem.process_tick(world, damage, processed_step_index:int) -> bool` (false = 롤백 요청), `PartyRationSystem.band(world) -> String`. 이번 태스크는 drain + `party.ration_changed`만; auto_eat/starve는 Task 5·6에서 같은 함수 안에 채운다.

- [ ] **Step 1: 실패하는 테스트 추가**

```gdscript
const Command = preload("res://sim/sim_command.gd")


func _wait(session) -> void:
	var hero_id := int(session.sim.world.party_encounter.protagonist_id)
	check(bool(session.commit_exploration(Command.wait(hero_id)).accepted), "wait fixture commits")


func _events_of(session, type: String) -> Array:
	var rows: Array = []
	for event in session.sim.world.events:
		if str(event.type) == type: rows.append(event)
	return rows


func test_gauge_drains_by_world_time_and_party_size() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var full := Rules.ration_max_milli()
	_wait(session)
	check_eq(int(state.ration_milli), full - 1000, "one 100-time wait drains 1000 milli for a solo party")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"drain clock follows world time")
	# Simulate 19,900 more elapsed time without 199 real steps: rewind the clock.
	state.ration_processed_at = int(session.sim.world.world_time) - 19900
	_wait(session)
	check_eq(int(state.ration_milli), full - 21000, "elapsed intervals are applied in one tick")
	check_eq(Rules.band(int(state.ration_milli)), "HUNGRY", "21,000 time crosses hungry_below")
	var changed := _events_of(session, "party.ration_changed")
	check_eq(changed.size(), 1, "band change emits exactly one event")
	if changed.size() == 1:
		check_eq(str(changed[0].data.get("after", "")), "HUNGRY", "event names the new band")
		check_eq(str(changed[0].data.get("before", "")), "FED", "event names the old band")
	_wait(session)
	check_eq(_events_of(session, "party.ration_changed").size(), 1,
		"staying in the same band emits nothing")
	check_eq(session.sim.world.world_state_error(), "", "drain keeps canonical state")
	# Party of three drains twice as fast.
	var trio = Session.new(44, 20260828, "SHOWCASE_V1")
	var trio_state = trio.sim.world.party_encounter
	check(trio_state.active_party_member_ids.size() >= 3, "showcase fixture has three active members")
	var trio_full := int(trio_state.ration_milli)
	_wait(trio)
	check_eq(int(trio_state.ration_milli), trio_full - Rules.drain_per_interval_milli(
		trio_state.active_party_member_ids.size()), "three members drain 2000 milli per interval")
	return finish()


func test_town_phase_freezes_and_departure_resets_the_gauge() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var Cycle = preload("res://sim/expedition_cycle_state.gd")
	state.ration_milli = 50000
	state.expedition_cycle = Cycle.active(1, session.sim.world.world_time, 100, 1)
	_wait(session)
	check_eq(str(session.expedition_cycle_status().phase), "TOWN", "deadline returns the party to town")
	check_eq(int(state.ration_milli), Rules.ration_max_milli(), "returning to town refills the gauge")
	var before := int(state.ration_milli)
	_wait(session)
	check_eq(int(state.ration_milli), before, "town phase does not drain")
	check_eq(int(state.ration_processed_at), int(session.sim.world.world_time),
		"town keeps the clock current so departure starts fresh")
	check_eq(session.sim.world.world_state_error(), "", "town reset keeps canonical state")
	return finish()
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `FAIL ... one 100-time wait drains 1000 milli` (게이지가 안 변함).

- [ ] **Step 3: 시스템 구현**

`sim/systems/party_ration_system.gd`:

```gdscript
class_name PartyRationSystem
extends RefCounted

## Party-wide ration gauge: drains with world time and party size, auto-eats from
## the protagonist bag, and starves the active party when empty. Pure function of
## world time, active member count and the hero inventory; no RNG.

const RulesScript = preload("res://sim/party_ration_rules.gd")
const WorldItemOperationsScript = preload("res://sim/world_item_operations.gd")


static func band(world) -> String:
	if world == null or world.party_encounter == null: return "FED"
	return RulesScript.band(int(world.party_encounter.ration_milli))


static func active_member_count(world) -> int:
	var count := 0
	for member_id in world.party_encounter.active_party_member_ids:
		var combatant = world.combatant_states.get(int(member_id))
		if combatant != null and str(combatant.life_state) == "ACTIVE": count += 1
	return maxi(1, count)


static func process_tick(world, damage, processed_step_index: int) -> bool:
	if world == null or world.party_encounter == null: return true
	var state = world.party_encounter
	if state.expedition_cycle == null or str(state.expedition_cycle.phase) != "DUNGEON":
		# Town never drains; keep the clock current so departure starts fresh.
		state.ration_processed_at = int(world.world_time)
		return true
	var rules := RulesScript.rules()
	var interval := int(rules.drain_interval)
	var elapsed := int(world.world_time) - int(state.ration_processed_at)
	var intervals := elapsed / interval
	if intervals <= 0: return true
	var before_band := RulesScript.band(int(state.ration_milli))
	var drain := intervals * RulesScript.drain_per_interval_milli(active_member_count(world))
	state.ration_milli = maxi(0, int(state.ration_milli) - drain)
	state.ration_processed_at = int(state.ration_processed_at) + intervals * interval
	var after_band := RulesScript.band(int(state.ration_milli))
	if after_band != before_band:
		if not _emit_band_change(world, before_band, after_band): return false
	state.revision += 1
	return true


static func _hero_position(world) -> Vector2i:
	var hero = world.entities.get(int(world.party_encounter.protagonist_id))
	return hero.position if hero != null else Vector2i(-1, -1)


static func _emit_band_change(world, before_band: String, after_band: String) -> bool:
	if not world.has_event_id_headroom(1): return false
	var state = world.party_encounter
	var event = world.emit_event("party.ration_changed", int(state.protagonist_id), -1,
		_hero_position(world), 0, -1, {"schema_version": 1,
			"ruleset_id": RulesScript.RULESET_ID, "before": before_band, "after": after_band,
			"ration_milli": int(state.ration_milli)})
	return event != null
```

`sim/systems/party_encounter_coordinator.gd`:
- preload 블록에 `const RationSystemScript = preload("res://sim/systems/party_ration_system.gd")`
- `process_tick`에서 `if not reconcile_liveness(allow_victory): return false` 바로 뒤에:
```gdscript
	if not RationSystemScript.process_tick(world, damage, processed_step_index): return false
```

`sim/simulator.gd` `_reconcile_expedition_cycle`:
```gdscript
	if world.party_encounter.expedition_cycle.auto_return_if_due(world.world_time):
		world.party_encounter.reset_ration(int(world.world_time))
		world.party_encounter.revision += 1
```

`playtest/party_playtest_session.gd` 출발 경로, `state.expedition_cycle=next_cycle` 바로 뒤:
```gdscript
	state.reset_ration(int(sim.world.world_time))
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: 5 tests, 0 failed. 만약 `SHOWCASE_V1`에 활성 멤버가 3명 미만이면 `_engaged_session` 대신 `tests/party_ui_layout_smoke.gd:1026`의 `_engaged_session([1,2],"WEDGE")` 패턴을 참고해 3인 세션을 만든다.

Run: `godot --headless --path . --script res://tests/run_expedition_cycle_tests.gd`
Expected: 통과.

- [ ] **Step 5: 커밋**

```bash
git add sim/systems/party_ration_system.gd sim/systems/party_encounter_coordinator.gd sim/simulator.gd playtest/party_playtest_session.gd tests/test_party_ration.gd
git commit -m "feat(ration): drain the party gauge with world time and reset it in town"
```

---

### Task 5: 자동 식사

**Files:**
- Modify: `sim/systems/party_ration_system.gd`
- Test: `tests/test_party_ration.gd`

**Interfaces:**
- Consumes: `WorldItemOperations.commit_use_without_event(world, entity_id, instance_id) -> Dictionary` (accepted, definition_id …), `world.inventory_of(entity_id)` → `InventoryState` (`sim/inventory_state.gd`; `backpack:Array` of `ItemScript` with `instance_id`, `definition_id`, `quantity`)
- Produces: `party.ration_eaten`, `party.ration_missing` 이벤트; `PartyRationSystem.auto_eat(world) -> bool`

- [ ] **Step 1: 실패하는 테스트 추가**

```gdscript
func test_hungry_party_eats_one_ration_automatically() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	state.ration_milli = Rules.hungry_below_milli() + 500
	_wait(session)
	check_eq(Rules.band(int(state.ration_milli)), "FED",
		"one more interval leaves 99,500: eaten and refilled")
	check_eq(int(state.ration_milli), mini(Rules.ration_max_milli(),
		Rules.hungry_below_milli() + 500 - 1000 + Rules.food_nutrition_milli()),
		"eating adds food_nutrition capped at max")
	check_eq(int(session.sim.world.inventory_of(hero_id).item("START_RATION_001").quantity), 1,
		"one ration was consumed from the hero bag")
	var eaten := _events_of(session, "party.ration_eaten")
	check_eq(eaten.size(), 1, "one meal event")
	if eaten.size() == 1:
		check_eq(str(eaten[0].data.get("definition_id", "")), "FOOD_RATION", "meal names the food")
	check_eq(_events_of(session, "party.ration_missing").size(), 0, "no missing event while fed")
	check_eq(session.sim.world.world_state_error(), "", "auto meal keeps canonical state")
	var saved := session.save_session_json()
	var replay = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(bool(replay.load_session_json(saved).get("accepted", false)), "session save/load round trip")
	check_eq(int(replay.sim.world.party_encounter.ration_milli), int(state.ration_milli),
		"loaded gauge matches")
	return finish()


func test_missing_food_reports_once_per_band_entry() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"fixture discards the starting rations")
	state.ration_milli = Rules.hungry_below_milli() + 500
	_wait(session)
	check_eq(Rules.band(int(state.ration_milli)), "HUNGRY", "no food leaves the party hungry")
	check_eq(_events_of(session, "party.ration_missing").size(), 1, "entering HUNGRY without food reports once")
	_wait(session); _wait(session)
	check_eq(_events_of(session, "party.ration_missing").size(), 1, "later hungry ticks stay silent")
	check_eq(session.sim.world.world_state_error(), "", "missing food keeps canonical state")
	return finish()
```

`discard_inventory_item`은 시간을 소비하므로 fixture에서 게이지를 설정하는 순서(폐기 → 게이지 설정 → wait)를 지킨다.

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `FAIL ... eaten and refilled`.

- [ ] **Step 3: auto_eat 구현**

`sim/systems/party_ration_system.gd`에 추가하고 `process_tick`을 확장:

```gdscript
static func _first_food_instance_id(world) -> String:
	var inventory = world.inventory_of(int(world.party_encounter.protagonist_id))
	if inventory == null: return ""
	var food_id := str(RulesScript.rules().food_definition_id)
	var ids: Array = []
	for item in inventory.backpack:
		if str(item.definition_id) == food_id and int(item.quantity) > 0:
			ids.append(str(item.instance_id))
	ids.sort()
	return "" if ids.is_empty() else str(ids[0])


static func auto_eat(world) -> bool:
	var state = world.party_encounter
	if RulesScript.band(int(state.ration_milli)) == "FED": return true
	var instance_id := _first_food_instance_id(world)
	if instance_id.is_empty(): return true
	if not world.has_event_id_headroom(2): return false
	var used: Dictionary = WorldItemOperationsScript.commit_use_without_event(world,
		int(state.protagonist_id), instance_id)
	if not bool(used.get("accepted", false)): return true
	var before_band := RulesScript.band(int(state.ration_milli))
	state.ration_milli = mini(RulesScript.ration_max_milli(),
		int(state.ration_milli) + RulesScript.food_nutrition_milli())
	var event = world.emit_event("party.ration_eaten", int(state.protagonist_id), -1,
		_hero_position(world), 0, -1, {"schema_version": 1,
			"ruleset_id": RulesScript.RULESET_ID, "definition_id": str(used.get("definition_id", "")),
			"instance_id": instance_id, "ration_milli": int(state.ration_milli)})
	if event == null: return false
	var after_band := RulesScript.band(int(state.ration_milli))
	if after_band != before_band and not _emit_band_change(world, before_band, after_band):
		return false
	return true


static func _emit_missing(world) -> bool:
	if not world.has_event_id_headroom(1): return false
	var state = world.party_encounter
	return world.emit_event("party.ration_missing", int(state.protagonist_id), -1,
		_hero_position(world), 0, -1, {"schema_version": 1,
			"ruleset_id": RulesScript.RULESET_ID, "ration_milli": int(state.ration_milli)}) != null
```

`process_tick`에서 band 변경 처리 뒤(`state.revision += 1` 앞)에:
```gdscript
	if after_band != "FED":
		var had_food := not _first_food_instance_id(world).is_empty()
		if not auto_eat(world): return false
		if not had_food and after_band != before_band and not _emit_missing(world): return false
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: 7 tests, 0 failed.

- [ ] **Step 5: 커밋**

```bash
git add sim/systems/party_ration_system.gd tests/test_party_ration.gd
git commit -m "feat(ration): auto-eat from the hero bag when the party turns hungry"
```

---

### Task 6: 굶주림 피해, 검증 허용, 스트레스·감정

**Files:**
- Modify: `sim/systems/party_ration_system.gd`
- Modify: `sim/world_state.gd` (damage chain 루프 ~2272행 `if event.type in ["combat.fire_damage", "combat.electric_damage"]:` 근처, `_legacy_death_event_error` ~3489행, `_lifecycle_history_error` downed driver 목록)
- Modify: `sim/party_morale_model.gd:16-50` (`evaluate`)
- Modify: `sim/party_emotion_model.gd:40-110` (`_appraise_event`)
- Test: `tests/test_party_ration.gd`

**Interfaces:**
- Consumes: `damage.apply_damage(entity, amount:int, damage_type:String, cause_id:int, event_position:Vector2i, processed_step_index:int) -> int` — `combat.<type>_damage` + (0 HP 시) `entity.died {damage_type}` 발행
- Produces: `party.ration_starve_tick {schema_version, ruleset_id, member_ids:[str], damage:int, stress:int}` 이벤트 1개/interval, 그 뒤 멤버별 `combat.starvation_damage`(cause = starve_tick id)

- [ ] **Step 1: 실패하는 테스트 추가**

```gdscript
func test_starving_party_takes_damage_and_stress_each_interval() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"fixture discards the starting rations")
	state.ration_milli = 0
	var hero = session.sim.world.entities[hero_id]
	var health_before := int(hero.health)
	var stress_before := int(state.member(hero_id).stress)
	_wait(session)
	check_eq(int(hero.health), health_before - 1, "one starving interval costs starve_damage HP")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), 1, "one starve tick event")
	check_eq(_events_of(session, "combat.starvation_damage").size(), 1, "one starvation damage event")
	var damage_event = _events_of(session, "combat.starvation_damage")[0]
	var tick_event = _events_of(session, "party.ration_starve_tick")[0]
	check_eq(int(damage_event.cause_id), int(tick_event.id), "damage is caused by the starve tick")
	check(int(state.member(hero_id).stress) >= stress_before + 4, "starving raises stress by starve_stress")
	check_eq(session.sim.world.world_state_error(), "", "starvation damage passes ledger validation")
	# Three elapsed intervals apply three separate ticks in one step.
	state.ration_processed_at = int(session.sim.world.world_time) - 200
	_wait(session)
	check_eq(int(hero.health), health_before - 4, "three intervals in one tick apply three damages")
	check_eq(_events_of(session, "party.ration_starve_tick").size(), 4, "each interval has its own tick event")
	check_eq(session.sim.world.world_state_error(), "", "batched starvation stays canonical")
	var saved := session.save_session_json()
	var replay = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check(bool(replay.load_session_json(saved).get("accepted", false)), "starved session reloads")
	check_eq(replay.sim.world.world_state_error(), "", "reloaded starvation history validates")
	return finish()


func test_starvation_can_kill_and_the_death_validates() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var state = session.sim.world.party_encounter
	var hero_id := int(state.protagonist_id)
	check(bool(session.discard_inventory_item("START_RATION_001").get("accepted", false)),
		"fixture discards the starting rations")
	state.ration_milli = 0
	session.sim.world.entities[hero_id].health = 1
	_wait(session)
	check_eq(str(session.sim.world.combatant_states[hero_id].life_state), "DEAD", "starvation kills at 0 HP")
	check_eq(_events_of(session, "entity.died").size(), 1, "one death event")
	check_eq(str(_events_of(session, "entity.died")[0].data.get("damage_type", "")), "starvation",
		"death records the starvation damage type")
	check_eq(session.sim.world.world_state_error(), "", "starvation death passes ledger validation")
	return finish()
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `FAIL ... one starving interval costs starve_damage HP`.

- [ ] **Step 3: 굶주림 피해 구현**

`sim/systems/party_ration_system.gd` `process_tick`: drain 직후 `after_band` 계산 뒤, auto_eat 블록 **뒤**에 (식량을 먹었으면 굶지 않는다):

```gdscript
	if RulesScript.band(int(state.ration_milli)) == "STARVING":
		var starve_interval := int(rules.starve_interval)
		var starve_ticks := (intervals * interval) / starve_interval
		for _tick in range(starve_ticks):
			if not _starve_once(world, damage, processed_step_index, rules): return false
```

그리고:

```gdscript
static func _starve_once(world, damage, processed_step_index: int, rules: Dictionary) -> bool:
	var state = world.party_encounter
	var victims: Array[int] = []
	for member_id in state.active_party_member_ids:
		var combatant = world.combatant_states.get(int(member_id))
		if combatant != null and str(combatant.life_state) == "ACTIVE":
			victims.append(int(member_id))
	victims.sort()
	if victims.is_empty(): return true
	# One tick event plus, per victim, a damage event and a possible death event.
	if not world.has_event_id_headroom(1 + victims.size() * 2): return false
	var member_wire: Array = []
	for member_id in victims: member_wire.append(str(member_id))
	var tick = world.emit_event("party.ration_starve_tick", int(state.protagonist_id), -1,
		_hero_position(world), int(rules.starve_damage), -1, {"schema_version": 1,
			"ruleset_id": RulesScript.RULESET_ID, "member_ids": member_wire,
			"damage": int(rules.starve_damage), "stress": int(rules.starve_stress)})
	if tick == null: return false
	for member_id in victims:
		var entity = world.entities.get(member_id)
		if entity == null: continue
		damage.apply_damage(entity, int(rules.starve_damage), "starvation", int(tick.id),
			entity.position, processed_step_index)
	return true
```

`sim/world_state.gd` 검증 허용:

1. damage chain 루프에서 `if event.type in ["combat.fire_damage", "combat.electric_damage"]:` 블록 뒤에 추가:
```gdscript
		if event.type == "combat.starvation_damage":
			var starvation_error := _starvation_damage_event_error(event)
			if not starvation_error.is_empty(): return starvation_error
```

2. `_legacy_death_event_error` 바로 앞에 새 함수:
```gdscript
func _starvation_damage_event_error(event) -> String:
	if event.actor_id != -1 or event.target_id <= 0 or not entities.has(event.target_id) \
			or event.magnitude <= 0 or event.data != {"damage_type": "starvation"} \
			or party_encounter == null or event.target_id not in party_encounter.party_member_ids:
		return "starvation_damage_envelope_invalid"
	var tick = event_by_id(event.cause_id)
	if tick == null or tick.type != "party.ration_starve_tick" \
			or tick.step_index != event.step_index or tick.world_time != event.world_time \
			or not tick.data.get("member_ids") is Array \
			or str(event.target_id) not in tick.data.member_ids \
			or event.magnitude > int(tick.data.get("damage", 0)):
		return "starvation_damage_source_invalid"
	return ""
```

3. `_legacy_death_event_error`의 `if damage_type not in ["physical", "fire", "electric"]:` → `["physical", "fire", "electric", "starvation"]`.

4. `_lifecycle_history_error`의 `damage_driver.type not in ["combat.physical_damage", "combat.fire_damage", "combat.electric_damage"]` 목록에 `"combat.starvation_damage"` 추가 (downed 드라이버 검사; 굶주림은 `apply_damage` 경로라 downed를 만들지 않지만 목록을 일관되게 유지).

`sim/party_morale_model.gd` `evaluate` 이벤트 루프의 `elif event_type == "entity.died":` 블록 뒤에:
```gdscript
		elif event_type == "party.ration_starve_tick":
			var data: Dictionary = event.get("data", {}) if event is Dictionary else event.data
			var stress_delta := maxi(0, int(data.get("stress", 0)))
			for member_id in members:
				direct[member_id] = int(direct[member_id]) + stress_delta
				triggers[member_id].append("STARVING")
```

`sim/party_emotion_model.gd` `_appraise_event`의 `elif event_type == "town.shrine_service"` 블록 앞에:
```gdscript
	elif event_type == "party.ration_starve_tick" and observer_id in party_ids:
		_add(state, "FEAR", _fear_delta(profile, 40), -1, source_id, "STARVING")
		_append_trigger(triggers, "STARVING")
	elif event_type == "party.ration_missing" and observer_id in party_ids:
		_add(state, "FEAR", _fear_delta(profile, 25), -1, source_id, "RATION_MISSING")
		_append_trigger(triggers, "RATION_MISSING")
```
(`_add`의 `target_id` 인자에 `-1`이 허용되는지 `sim/party_emotion_state.gd`의 channel target 검증을 확인한다. 허용되지 않으면 `int(world.party_encounter.protagonist_id)`를 넣는다.)

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: 9 tests, 0 failed. `world_state_error`가 비어 있지 않으면 반환된 에러 문자열(예: `starvation_damage_source_invalid`, `legacy_death_damage_type_invalid`)로 어느 검증이 걸렸는지 찾아 그 함수만 수정한다.

Run: `godot --headless --path . --script res://tests/run_phase4_tests.gd`
Expected: 기존과 동일 통과 (morale/emotion 회귀 없음).

- [ ] **Step 5: 커밋**

```bash
git add sim/systems/party_ration_system.gd sim/world_state.gd sim/party_morale_model.gd sim/party_emotion_model.gd tests/test_party_ration.gd
git commit -m "feat(ration): starve the active party with validated damage, stress and fear"
```

---

### Task 7: 층 바닥 식량, 관찰 DTO, 로그 문구

**Files:**
- Modify: `playtest/party_playtest_session.gd` (`_initial_ground_item_rows` ~472행, `_enter_campaign_floor` ~2036행, `party_status` ~1393행, `_is_important_log_event` ~6047행, `_event_message` ~7539행)
- Test: `tests/test_party_ration.gd`

**Interfaces:**
- Consumes: `GroundItemScript.new(rows)` (rows = `{"position":[x,y],"item":ItemScript.to_dict()}`), `sim.world.item_state.ground_items.rows`
- Produces: `party_status()` 키 `ration`, `ration_max`, `ration_band`; 바닥 인스턴스 `GROUND_FLOOR<N>_RATION`; 로그 문구.

- [ ] **Step 1: 실패하는 테스트 추가**

```gdscript
func test_floor_ration_dto_and_log_copy() -> bool:
	var session = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var ground = session.sim.world.item_state.ground_items
	var floor_ration = ground.item("GROUND_FLOOR1_RATION")
	check(floor_ration != null and str(floor_ration.definition_id) == "FOOD_RATION",
		"floor one places one ration on the ground")
	var replay = Session.new(44, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	check_eq(replay.sim.world.item_state.ground_items.position_of("GROUND_FLOOR1_RATION"),
		ground.position_of("GROUND_FLOOR1_RATION"), "floor ration position is seed-fixed")
	var status: Dictionary = session.party_status()
	check_eq(int(status.get("ration", -1)), 300, "status exposes the whole-unit gauge")
	check_eq(int(status.get("ration_max", -1)), 300, "status exposes the max")
	check_eq(str(status.get("ration_band", "")), "FED", "status exposes the band")
	var state = session.sim.world.party_encounter
	state.ration_milli = Rules.hungry_below_milli() + 500
	_wait(session)
	var log: Dictionary = session.combat_log(8, 80)
	var messages: Array[String] = []
	for group in log.get("groups", []):
		for row in group.get("rows", []): messages.append(str(row.get("message", "")))
	check("배급 식량을 먹었다." in messages, "meal reaches the important log with Korean copy")
	return finish()
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: `FAIL ... floor one places one ration on the ground`.

- [ ] **Step 3: 세션 구현**

`_initial_ground_item_rows`: 반환 직전 `if candidates.size()<2:return []` 뒤를 다음으로 바꾼다 (후보는 이미 주인공 거리순 정렬이므로 마지막 원소가 가장 멀다):
```gdscript
	if candidates.size()<2:return []
	var rows:Array=[{"position":[candidates[0].x,candidates[0].y],
		"item":ItemScript.new("GROUND_START_SHIELD","SHIELD_WOOD").to_dict()},
		{"position":[candidates[1].x,candidates[1].y],
		"item":ItemScript.new("GROUND_START_PADDED","ARMOR_PADDED").to_dict()}]
	var ration_cell:Vector2i=candidates[candidates.size()-1]
	if candidates.size()>=3:
		rows.append({"position":[ration_cell.x,ration_cell.y],
			"item":ItemScript.new("GROUND_FLOOR1_RATION","FOOD_RATION").to_dict()})
	return rows
```

`_enter_campaign_floor`: 파티 위치를 `entry_position`으로 옮긴 직후(모든 `sim.world.entities[member_id].position=entry_position` 루프 뒤)에 새 층 식량을 놓는다:
```gdscript
	_place_floor_ration(floor_index,entry_position,target_layout)
```
새 함수:
```gdscript
func _place_floor_ration(floor_index:int,entry_position:Vector2i,layout:Dictionary)->void:
	var instance_id:="GROUND_FLOOR%d_RATION"%floor_index
	if sim.world.item_state.ground_items.item(instance_id)!=null:return
	var blocked:Array=layout.get("door_positions",[]).duplicate()
	blocked.append(layout.get("entry_position",Vector2i(-1,-1)))
	blocked.append(layout.get("exit_position",Vector2i(-1,-1)))
	var best:=Vector2i(-1,-1);var best_distance:=-1
	for y in range(maxi(0,entry_position.y-5),mini(sim.world.height,entry_position.y+6)):
		for x in range(maxi(0,entry_position.x-5),mini(sim.world.width,entry_position.x+6)):
			var position:=Vector2i(x,y)
			var distance:=maxi(absi(position.x-entry_position.x),absi(position.y-entry_position.y))
			if distance<2 or position in blocked \
					or not sim.world.occupying_entities_at(position).is_empty():continue
			var tile=sim.world.tile_at(position)
			var terrain:=TerrainRegistryScript.definition(str(tile.terrain))
			if terrain.is_empty() or not bool(terrain.get("passable",false)) \
					or int(tile.fire)>0 or int(tile.wetness)>0:continue
			# Farthest cell wins; ties resolve by row then column for determinism.
			if distance>best_distance or (distance==best_distance \
					and (position.y<best.y or (position.y==best.y and position.x<best.x))):
				best=position;best_distance=distance
	if best_distance<0:return
	var rows:Array=[]
	for row in sim.world.item_state.ground_items.rows:
		rows.append({"position":[row.position.x,row.position.y],"item":row.item.to_dict()})
	rows.append({"position":[best.x,best.y],
		"item":ItemScript.new(instance_id,"FOOD_RATION").to_dict()})
	sim.world.item_state.ground_items=GroundItemScript.new(rows)
```

`party_status()` 반환 딕셔너리에 키 3개 추가 (`"terminal": ...` 뒤 아무 위치):
```gdscript
		"ration":int(state.ration_milli/1000),"ration_max":int(RationRulesScript.rules().ration_max),
		"ration_band":RationRulesScript.band(int(state.ration_milli)),
```
세션 preload 블록에 `const RationRulesScript=preload("res://sim/party_ration_rules.gd")`.

`_is_important_log_event` 목록에 `"party.ration_eaten","party.ration_missing","party.ration_changed","party.ration_starve_tick",` 추가 (`"health.restored",` 뒤).

`_event_message`의 `match` 에 추가:
```gdscript
		"party.ration_eaten":return "배급 식량을 먹었다."
		"party.ration_missing":return "식량이 떨어졌다."
		"party.ration_changed":
			match str(event.data.get("after","")):
				"HUNGRY":return "배가 고프다."
				"STARVING":return "굶주리기 시작했다."
				_:return "허기가 가셨다."
		"party.ration_starve_tick":return "굶주림 · 전원 −%d"%int(event.data.get("damage",0))
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/run_party_ration_tests.gd`
Expected: 10 tests, 0 failed.

Run: `godot --headless --path . --script res://tests/run_product_tests.gd`
Expected: 기존과 동일 통과. 바닥 아이템 수를 2개로 고정한 테스트(예: `test_weapon_vertical_slice.gd`, `party_ui_layout_smoke.gd`의 ground item 카운트)가 있으면 3개로 갱신한다.

- [ ] **Step 5: 커밋**

```bash
git add playtest/party_playtest_session.gd tests/test_party_ration.gd
git commit -m "feat(ration): seed one floor ration per floor and expose ration DTO and log copy"
```

---

### Task 8: product HUD 식량 게이지

**Files:**
- Modify: `playtest/party_encounter_sandbox.gd` (`expedition_hud_spec` ~5436행, `_update_expedition_hud` 바로 아래, `_build_ui` `return_timer_label` 생성부)
- Modify: `tests/party_ui_visual_style_smoke.gd` (~61행 top rail 검사 뒤)

**Interfaces:**
- Consumes: `session.party_status()`의 `ration`, `ration_max`, `ration_band`
- Produces: `expedition_hud_spec()` 키 `ration_text`, `ration_band`, `ration_tone_hex`; 새 라벨 `ration_label:Label` (이름 `RationGauge`)

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/party_ui_visual_style_smoke.gd`의 top rail `_check(... "product top rail order is not minimap / floor+timer / menu above the map")` 뒤에:
```gdscript
	var ration_spec:Dictionary=sandbox.expedition_hud_spec()
	_check(sandbox.ration_label!=null and sandbox.ration_label.is_visible_in_tree() \
		and sandbox.ration_label.text=="식량 ▮▮▮▮" and str(ration_spec.get("ration_band",""))=="FED" \
		and _inside_rect(sandbox.phase_panel,sandbox.ration_label) \
		and sandbox.ration_label.get_theme_font_size("font_size")>=11,
		"%s top rail lacks the four-cell ration gauge"%viewport_size)
	sandbox.session.sim.world.party_encounter.ration_milli=0
	sandbox._refresh();await process_frame
	_check(sandbox.ration_label.text=="굶주림" \
		and sandbox.ration_label.get_theme_color("font_color")==AsciiUIFrame.DANGER,
		"%s starving rail copy is not red 굶주림"%viewport_size)
	sandbox.session.sim.world.party_encounter.ration_milli=300000
	sandbox._refresh();await process_frame
```
(`AsciiUIFrame` 상수 이름은 이 파일 상단 preload 이름을 따른다. `DANGER`가 없으면 `AsciiUIFrame.RED`.)

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/party_ui_visual_style_smoke.gd`
Expected: `ration_label` 속성 없음 에러 또는 `FAIL ... four-cell ration gauge`.

- [ ] **Step 3: HUD 구현**

`playtest/party_encounter_sandbox.gd`:

1. `var return_timer_label:Label` 아래에 `var ration_label:Label`.
2. `_build_ui`에서 `return_timer_label`을 `situation_stack`에 추가하는 대신, 타이머와 게이지를 한 줄에 놓는다. `situation_stack.add_child(return_timer_label)` 를 다음으로 교체:
```gdscript
	var clock_row:=HBoxContainer.new();clock_row.name="ClockRow"
	clock_row.add_theme_constant_override("separation",8);situation_stack.add_child(clock_row)
	return_timer_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;clock_row.add_child(return_timer_label)
	ration_label=Label.new();ration_label.name="RationGauge"
	ration_label.add_theme_font_size_override("font_size",FONT_AUX)
	ration_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	ration_label.add_theme_font_override("font",AsciiFrameScript.CodingFontBold)
	ration_label.visible=false;clock_row.add_child(ration_label)
```
3. `expedition_hud_spec()` 반환 전에:
```gdscript
	var status:Dictionary=session.party_status() if session!=null else {}
	var ration_band:=str(status.get("ration_band","FED"))
	var ration_max:=maxi(1,int(status.get("ration_max",1)))
	var filled:=clampi(int(ceil(float(int(status.get("ration",0)))*4.0/float(ration_max))),0,4)
	var ration_text:="굶주림" if ration_band=="STARVING" else "식량 "+"▮".repeat(filled)+"▯".repeat(4-filled)
	var ration_tone:Color=AsciiFrameScript.INK
	if ration_band=="STARVING":ration_tone=AsciiFrameScript.DANGER
	elif ration_band=="HUNGRY":ration_tone=AsciiFrameScript.BRASS
```
반환 딕셔너리에 `"ration_text":ration_text,"ration_band":ration_band,"ration_tone_hex":ration_tone.to_html(false)` 추가.

4. `_update_expedition_hud`: 끝에
```gdscript
	if ration_label!=null:
		var ration_text:=str(spec.get("ration_text",""))
		ration_label.text=ration_text
		ration_label.visible=product_hud and not ration_text.is_empty() and str(spec.get("phase",""))=="DUNGEON"
		ration_label.add_theme_color_override("font_color",Color(str(spec.get("ration_tone_hex","c7c2b3"))))
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/party_ui_visual_style_smoke.gd`
Expected: `PASS fixed-cell DOS UI smoke: 360x640, 450x800`.

Run: `godot --headless --path . --script res://tests/party_ui_layout_smoke.gd`
Expected: `0 failed` (rail 높이 70 안에서 두 줄이 유지되는지 — 넘치면 `ration_label`/`return_timer_label` 폰트를 `FONT_MICRO`(11)로 낮춘다).

- [ ] **Step 5: 커밋**

```bash
git add playtest/party_encounter_sandbox.gd tests/party_ui_visual_style_smoke.gd
git commit -m "feat(ration): show the party ration gauge beside the return timer"
```

---

### Task 9: 밸런스 시뮬과 수치 확정

**Files:**
- Create: `tests/run_ration_balance_sim.gd`
- Modify (필요 시): `data/content/hunger_rules.json`

**Interfaces:**
- Consumes: `Session.start_auto_explore()`, `Session.continue_auto_explore()`, `Session.auto_explore_state()`, `Session.expedition_cycle_status()`, `Session.party_status()`, `session.sim.world.events`

- [ ] **Step 1: 시뮬 스크립트 작성**

`tests/run_ration_balance_sim.gd`:

```gdscript
extends SceneTree

## Headless balance probe: runs seeded solo expeditions on AUTO until the party
## returns to town, dies, or the step budget ends, and prints ration outcomes.
## Not a pass/fail test; read the table and tune data/content/hunger_rules.json.

const Session = preload("res://playtest/party_playtest_session.gd")
const Rules = preload("res://sim/party_ration_rules.gd")
const Command = preload("res://sim/sim_command.gd")
const SEEDS := [44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
const STEP_BUDGET := 1500


func _init() -> void:
	print("seed | steps | outcome | min_band | starve_ticks | starve_damage | rations_eaten | rations_found | left")
	var starved := 0
	for seed in SEEDS:
		var row := _run(seed)
		if int(row.starve_ticks) > 0: starved += 1
		print("%d | %d | %s | %s | %d | %d | %d | %d | %d" % [seed, row.steps, row.outcome,
			row.min_band, row.starve_ticks, row.starve_damage, row.eaten, row.found, row.left])
	print("---- starving runs: %d / %d (target solo <= 20%%) ----" % [starved, SEEDS.size()])
	quit(0)


func _run(seed: int) -> Dictionary:
	var session = Session.new(seed, 20260828, Session.SOLO_COMBAT_SCENARIO_ID)
	var steps := 0
	var min_band := "FED"
	var outcome := "BUDGET"
	session.start_auto_explore()
	while steps < STEP_BUDGET:
		var status: Dictionary = session.party_status()
		if bool(status.get("terminal", false)): outcome = "DEAD"; break
		if str(status.get("view_mode", "")) == "TOWN": outcome = "RETURNED"; break
		var band := str(status.get("ration_band", "FED"))
		if band == "STARVING": min_band = "STARVING"
		elif band == "HUNGRY" and min_band == "FED": min_band = "HUNGRY"
		if not bool(session.auto_explore_state().get("running", false)):
			session.start_auto_explore()
			if not bool(session.auto_explore_state().get("running", false)):
				# AUTO refuses to start (no safe discovery target, enemy adjacent, …):
				# spend one WAIT so the world still advances and hunger keeps ticking.
				var hero_id := int(session.sim.world.party_encounter.protagonist_id)
				if not bool(session.commit_exploration(Command.wait(hero_id)).accepted):
					outcome = "STUCK"; break
				steps += 1
				continue
		session.continue_auto_explore()
		steps += 1
	var starve_ticks := 0; var starve_damage := 0; var eaten := 0; var found := 0
	for event in session.sim.world.events:
		match str(event.type):
			"party.ration_starve_tick": starve_ticks += 1
			"combat.starvation_damage": starve_damage += int(event.magnitude)
			"party.ration_eaten": eaten += 1
			"item.picked_up":
				if str(event.data.get("definition_id", "")) == "FOOD_RATION": found += 1
	return {"steps": steps, "outcome": outcome, "min_band": min_band,
		"starve_ticks": starve_ticks, "starve_damage": starve_damage, "eaten": eaten,
		"found": found, "left": int(session.sim.world.party_encounter.ration_milli / 1000)}
```

`auto_explore_state()`는 `playtest/party_auto_explore.gd`의 `_state()` 딕셔너리(`running:bool` 포함)를 돌려준다. `continue_auto_explore()`는 한 번에 한 hop을 커밋한다. 루프가 `STUCK`으로만 끝나면 `party_auto_explore.gd`의 정지 사유(`reason`)를 출력해 fixture를 조정한다.

- [ ] **Step 2: 실행**

Run: `godot --headless --path . --script res://tests/run_ration_balance_sim.gd`
Expected: 20행 표와 `starving runs: N / 20`.

- [ ] **Step 3: 수치 조정**

- `starving runs` 가 20%(4/20) 초과면 `hunger_rules.json`의 `ration_max`를 50 단위로 올리거나 `drain_per_interval_milli`를 낮춘다. 시장·바닥·드롭은 그대로 둔다.
- 0/20이고 `min_band`가 전부 `FED`면 압박이 없는 것이다: `ration_max`를 50 단위로 내린다.
- 바꿀 때마다 `content_version`을 올리고 Step 2를 다시 돌린다. 스펙 §7 목표 밴드(솔로 ≤ 20%)에 들어오면 멈춘다.

- [ ] **Step 4: 전체 회귀**

순서대로 하나씩(동시 실행 금지):
```bash
godot --headless --path . --script res://tests/run_party_ration_tests.gd
godot --headless --path . --script res://tests/run_json_content_database_tests.gd
godot --headless --path . --script res://tests/run_product_tests.gd
godot --headless --path . --script res://tests/party_ui_layout_smoke.gd
godot --headless --path . --script res://tests/party_ui_visual_style_smoke.gd
godot --headless --path . --script res://tests/run_expedition_cycle_tests.gd
godot --headless --path . --script res://tests/run_phase4_tests.gd
```
Expected: 전부 통과 (`test_party_enemy_awareness`의 LOS 2건 제외).

- [ ] **Step 5: 커밋**

```bash
git add tests/run_ration_balance_sim.gd data/content/hunger_rules.json
git commit -m "feat(ration): add ration balance probe and tune initial numbers"
```
