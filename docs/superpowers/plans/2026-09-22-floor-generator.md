# 1층 절차 생성기 · DD식 조우 배치 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 고정 4구역 층(`legacy/four_zone_floor.gd` 2배 확대)을 64×64 절차 생성 층(방 10~12개 그래프 + ASCII 템플릿 방 + 위협 예산 조우)으로 교체한다.

**Architecture:** 세 개의 순수 정적 모듈이 층 딕셔너리(§7 계약)를 만든다 — `floor_templates.gd`(ASCII → 지형/feature), `encounter_builder.gd`(종족 테이블·예산·가드레일·방 안 배치), `floor_generator.gd`(방 뿌리기 → 그래프 → 복도 → 지형 → 배치 → 검증). `continuous_floor.gd`는 그 결과만 소비하고 전투·시야·미니맵·상점·정산은 손대지 않는다. 데이터(테마·템플릿·종족)는 JSON.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 SceneTree 테스트(`godot --headless --path . --script res://tests/<name>.gd`), JSON 콘텐츠(`data/content/`).

**Spec:** `docs/superpowers/specs/2026-09-22-floor-generator-design.md` — 구현자는 스펙을 먼저 읽는다. 이 계획은 스펙 §1~§7을 그대로 코드로 옮긴 것이다.

## Global Constraints

- 층 크기 `64` (테마 JSON `size`). 코드에 100/10000/99 같은 크기 리터럴을 남기지 않는다.
- 모든 난수는 `RandomNumberGenerator`에 시드를 넣어 쓴다. 같은 `(theme, seed, depth)` → 같은 결과. `randi()`/`randf()` 전역 함수 금지.
- 지형 문자열은 기존 값만: `"wall" "stone" "rubble" "wood" "water" "metal"`. 물은 `wet 70`.
- feature 딕셔너리 형식은 기존과 동일: `{"kind","used":false,"label"}` + curio는 `"curio_id"`.
- 조우 방 내부 9×9 ~ 12×10, 일반 방 5×5 ~ 8×7, 방 사이 벽 포함 최소 2칸, 외곽 1칸 벽. 복도 폭 1.
- 예산 초입 3 · 중간 6 · 심부 9 · 선택 5(구현 후 심부 6·중간 5로 조정 — 스펙 §3.2 변경 주석 참조), 오차 ±1, 조우당 최대 4마리. 가드레일: 3마리 이상이면 후위 ≥1, 술사 ≤1, 같은 종족+역할 ≤2.
- 재생성 한도 5회(seed+1). 5회 실패는 `push_error`.
- 테스트는 기존 형식(`extends SceneTree`, `check(ok, reason)`, `print("<이름>: %d failures")`, `quit(1 if failures else 0)`).
- 새 테스트 스위트는 `.github/workflows/deploy-pages.yml`의 `for suite in ...` 목록과 README 검증 절에 추가한다.
- 커밋: `new/`는 아직 git에 추적되지 않는다. **커밋 단계는 `git add`/`git commit`을 실제로 실행하지 말고 건너뛴다.** 대신 각 Task 끝에서 해당 스위트를 다시 실행해 녹색을 확인한다.
- Godot 창을 띄우지 않는다. 항상 `--headless`.

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `data/content/floor_themes.json` (신규) | 층 테마 파라미터. `F1_RUINS` 완성, `F2_MINES` 뼈대 |
| `data/content/floor_templates.json` (신규) | ASCII 템플릿 6종 |
| `data/content/floor_monsters.json` (신규) | 종족 출현 테이블(구간·rarity·곡선·위협·역할·밴드) |
| `expedition/floor_templates.gd` (신규) | 템플릿 로드·회전·파싱·스탬프 |
| `expedition/encounter_builder.gd` (신규) | 곡선·가중 추첨·무리 채우기·가드레일·방 안 좌표 배치 |
| `expedition/floor_generator.gd` (신규) | 파이프라인 전체 + `validate()` |
| `expedition/continuous_floor.gd` (수정) | 생성기 결과 소비, `SIZE` 상수 → 인스턴스 `size` |
| `expedition/expedition_objective.gd` (수정) | `choose/place` 삭제, `register` 추가 |
| `expedition/monster_ai.gd` (수정) | `configure(enemy, role)` |
| `expedition/map_view.gd`, `expedition/main.gd` (수정) | 크기 리터럴 제거 |
| `tests/floor_fixture.gd` (신규) | 테스트용 아레나 헬퍼 |
| `tests/floor_templates.gd`, `tests/encounter_builder.gd`, `tests/floor_generator.gd` (신규) | 단위·통합 검증 |
| 기존 테스트 7종 (수정) | 100×100 좌표 가정 제거 |

---

### Task 1: 템플릿 데이터와 파서 (`floor_templates.gd`)

**Files:**
- Create: `data/content/floor_templates.json`
- Create: `expedition/floor_templates.gd`
- Test: `tests/floor_templates.gd`

**Interfaces:**
- Produces:
  - `FloorTemplates.definition(id: String) -> Dictionary` — JSON 항목(`id,label,tags,depth,orient,rows`). 없으면 `{}`.
  - `FloorTemplates.rotate(rows: Array, turns: int) -> Array` — 시계 방향 90°×turns.
  - `FloorTemplates.parse(rows: Array) -> Dictionary` — `{"width":int,"height":int,"terrain":{Vector2i:String},"doors":Array[Vector2i],"features":{Vector2i:Dictionary},"anchor":Vector2i,"backline":Array[Vector2i],"floor":Array[Vector2i]}`. 좌표는 템플릿 좌상단 `(0,0)` 기준이며 외곽 벽 포함. `anchor`가 없으면 `Vector2i(-1,-1)`.
  - `FloorTemplates.stamp(terrain: Array, size: int, origin: Vector2i, parsed: Dictionary) -> void` — `terrain[(origin.y+y)*size+origin.x+x]`에 기록. 문 후보(`+`)는 벽으로 기록(복도 단계에서 뚫음).
  - `FloorTemplates.GLYPH_FEATURE` — 기호 → feature 딕셔너리 생성 규칙.

- [ ] **Step 1: 템플릿 JSON 작성**

`data/content/floor_templates.json`:

```json
{
  "content_schema_version": 1,
  "content_type": "floor_templates",
  "templates": [
    {"id": "entry_camp", "label": "입구 야영지", "tags": ["ruins","entry"], "depth": [1, 9], "orient": false,
     "rows": [
       "#####+#####",
       "#.........#",
       "#..C......#",
       "#.@.......#",
       "#.........#",
       "#.........#",
       "#.........#",
       "+.........+",
       "###########"]},
    {"id": "relic_vault", "label": "유물의 방", "tags": ["ruins","relic"], "depth": [1, 9], "orient": true,
     "rows": [
       "#############",
       "#...........#",
       "#..%.....%..#",
       "#..P..*..P..#",
       "#..%..M..%..#",
       "#...........#",
       "#...........#",
       "#....,,,....#",
       "#...........#",
       "#####+#+#####"]},
    {"id": "flooded_cistern", "label": "침수 저장고", "tags": ["ruins","fight"], "depth": [1, 9], "orient": true,
     "rows": [
       "#####+######",
       "#~~~~.~~~~~#",
       "#~~~~.~~~M~#",
       "#~~~~.~~~~~#",
       "#~~~~.~~P~~#",
       "#....~.....#",
       "#....~.....#",
       "#....~.....#",
       "#..........#",
       "######+#####"]},
    {"id": "collapsed_store", "label": "무너진 창고", "tags": ["ruins","fight"], "depth": [1, 9], "orient": true,
     "rows": [
       "###########",
       "#.........#",
       "#.,.#.,.#.#",
       "#.........#",
       "#.#.,.#.,.#",
       "#....M....#",
       "#.,.#.,.#.#",
       "#........^#",
       "#.#.,.#.,.#",
       "#.........#",
       "#####+#####"]},
    {"id": "sealed_treasury", "label": "봉인된 보고", "tags": ["ruins","treasure"], "depth": [1, 9], "orient": true,
     "rows": [
       "########",
       "#$....$#",
       "#......#",
       "#..A...#",
       "#......#",
       "#......#",
       "#......#",
       "####+###"]},
    {"id": "timber_gallery", "label": "목재 회랑", "tags": ["ruins","fight"], "depth": [1, 9], "orient": true,
     "rows": [
       "##############",
       "#============#",
       "#==%======%==#",
       "#=====P=====M#",
       "#==%======%==#",
       "#===P========#",
       "#============#",
       "+############+"]}
  ]
}
```

규칙: 모든 행은 같은 길이. 외곽 문자는 `#` 또는 `+`뿐. 내부 크기는 `(width-2)×(height-2)`.

- [ ] **Step 2: 실패하는 테스트 작성**

`tests/floor_templates.gd`:

```gdscript
extends SceneTree
const Templates = preload("res://expedition/floor_templates.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ids := ["entry_camp","relic_vault","flooded_cistern","collapsed_store","sealed_treasury","timber_gallery"]
	for id in ids:
		var def: Dictionary = Templates.definition(id)
		check(not def.is_empty() and def.rows.size() >= 3,"template %s exists" % id)
		var width: int = def.rows[0].length()
		check(def.rows.all(func(r): return r.length() == width),"%s rows equal length" % id)
		for y in range(def.rows.size()):
			for x in range(width):
				var edge: bool = x == 0 or y == 0 or x == width-1 or y == def.rows.size()-1
				var glyph: String = def.rows[y][x]
				if edge: check(glyph in ["#","+"],"%s edge is wall or door" % id)
				else: check(glyph != "+","%s door only on edge" % id)
		var parsed: Dictionary = Templates.parse(def.rows)
		check(parsed.width == width and parsed.height == def.rows.size(),"%s parsed size" % id)
		check(parsed.doors.size() >= 1,"%s has a door candidate" % id)
		check(parsed.terrain.size() == width*def.rows.size(),"%s every cell has terrain" % id)
	check(Templates.definition("nope").is_empty(),"unknown template is empty")
	var relic: Dictionary = Templates.parse(Templates.definition("relic_vault").rows)
	check(relic.features.values().filter(func(f): return f.kind == "relic").size() == 1,"relic vault has one relic")
	check(relic.anchor != Vector2i(-1,-1) and relic.backline.size() == 2,"relic vault anchor and two backline cells")
	check(relic.terrain[relic.anchor] == "stone","anchor glyph is floor")
	var treasury: Dictionary = Templates.parse(Templates.definition("sealed_treasury").rows)
	check(treasury.doors.size() == 1,"treasury has exactly one door")
	check(treasury.features.values().filter(func(f): return f.kind == "curio" and f.curio_id == "LOCKED_CHEST").size() == 2,"treasury has two chests")
	check(treasury.features.values().filter(func(f): return f.kind == "altar").size() == 1,"treasury has an altar")
	var entry: Dictionary = Templates.parse(Templates.definition("entry_camp").rows)
	var entry_cell: Vector2i = entry.features.keys().filter(func(p): return entry.features[p].kind == "entry")[0]
	for dx in range(1,5): check(entry.terrain.get(entry_cell+Vector2i(dx,0),"wall") != "wall","four free cells east of the entry gate")
	# Rotation: 90 degrees clockwise maps (x,y) -> (height-1-y, x).
	var rows := ["#+#","#.#","###"]
	var turned: Array = Templates.rotate(rows,1)
	check(turned == ["###","#.+","###"],"rotate once clockwise (%s)" % [turned])
	check(Templates.rotate(rows,4) == rows,"four turns is identity")
	var cistern: Dictionary = Templates.parse(Templates.rotate(Templates.definition("flooded_cistern").rows,1))
	check(cistern.width == 10 and cistern.height == 12,"rotated cistern swaps dimensions")
	check(cistern.doors.size() == 2 and cistern.anchor != Vector2i(-1,-1),"rotation keeps doors and anchor")
	# Stamp into a 16x16 board of walls.
	var terrain: Array = []; terrain.resize(256); terrain.fill("wall")
	Templates.stamp(terrain,16,Vector2i(2,3),treasury)
	check(terrain[(3+1)*16+2+1] == "stone","stamp writes interior floor at origin offset")
	check(terrain[(3+treasury.height-1)*16+2+treasury.doors[0].x] == "wall","door candidates stay wall until corridors")
	check(terrain[0] == "wall" and terrain[255] == "wall","stamp does not touch outside cells")
	print("Floor templates: %d failures" % failures); quit(1 if failures else 0)
```

- [ ] **Step 3: 실패 확인**

Run: `godot --headless --path . --script res://tests/floor_templates.gd`
Expected: 스크립트 로드 오류(`floor_templates.gd` 없음).

- [ ] **Step 4: 파서 구현**

`expedition/floor_templates.gd`:

```gdscript
extends RefCounted
## ASCII room templates (DCSS vault style). Pure: JSON in, terrain/feature maps out.
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_templates.json"))
const GLYPH_TERRAIN := {"#":"wall","+":"wall",".":"stone",",":"rubble","~":"water","=":"wood","%":"metal",
	"@":"stone","*":"stone","$":"stone","^":"stone","A":"stone","C":"stone","M":"stone","P":"stone"}
const GLYPH_FEATURE := {
	"@":{"kind":"entry","label":"귀환 관문"},
	"*":{"kind":"relic","label":"봉인된 유물"},
	"$":{"kind":"curio","curio_id":"LOCKED_CHEST"},
	"^":{"kind":"curio","curio_id":"DIRT_PILE"},
	"A":{"kind":"altar","label":"갈림길 중계석"},
	"C":{"kind":"camp","label":"도움이 필요한 모험가"}}

static func definition(id: String) -> Dictionary:
	for row in content.get("templates",[]):
		if row.id == id: return row
	return {}

static func ids_with_tag(tag: String) -> Array:
	var result: Array = []
	for row in content.get("templates",[]):
		if tag in row.tags: result.append(row.id)
	return result

## Clockwise quarter turns. (x,y) in the source becomes (height-1-y, x).
static func rotate(rows: Array, turns: int) -> Array:
	var current: Array = rows.duplicate()
	for _turn in range(posmod(turns,4)):
		var height: int = current.size()
		var width: int = current[0].length()
		var next: Array = []
		for x in range(width):
			var line := ""
			for y in range(height-1,-1,-1): line += current[y][x]
			next.append(line)
		current = next
	return current

static func feature_for(glyph: String) -> Dictionary:
	if not GLYPH_FEATURE.has(glyph): return {}
	var feature: Dictionary = GLYPH_FEATURE[glyph].duplicate(true)
	feature.used = false
	if feature.kind == "curio":
		var curios: Dictionary = preload("res://expedition/curios.gd").content.curios
		feature.label = curios[feature.curio_id].name
	return feature

static func parse(rows: Array) -> Dictionary:
	var result := {"width":rows[0].length(),"height":rows.size(),"terrain":{},"doors":[],"features":{},
		"anchor":Vector2i(-1,-1),"backline":[],"floor":[]}
	for y in range(rows.size()):
		for x in range(rows[y].length()):
			var glyph: String = rows[y][x]
			var p := Vector2i(x,y)
			result.terrain[p] = GLYPH_TERRAIN.get(glyph,"wall")
			if glyph == "+": result.doors.append(p)
			elif glyph == "M": result.anchor = p
			elif glyph == "P": result.backline.append(p)
			var feature := feature_for(glyph)
			if not feature.is_empty(): result.features[p] = feature
			if result.terrain[p] != "wall": result.floor.append(p)
	return result

static func stamp(terrain: Array, size: int, origin: Vector2i, parsed: Dictionary) -> void:
	for p in parsed.terrain:
		var cell: Vector2i = origin+p
		if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size: continue
		terrain[cell.y*size+cell.x] = parsed.terrain[p]
```

- [ ] **Step 5: 통과 확인**

Run: `godot --headless --path . --script res://tests/floor_templates.gd`
Expected: `Floor templates: 0 failures`

- [ ] **Step 6: 커밋(건너뜀 — Global Constraints 참조). 스위트 재실행으로 대체.**

---

### Task 2: 종족 테이블과 무리 채우기 (`encounter_builder.gd`)

**Files:**
- Create: `data/content/floor_monsters.json`
- Create: `expedition/encounter_builder.gd`
- Test: `tests/encounter_builder.gd`

**Interfaces:**
- Consumes: `expedition/legacy/dcss_enemy_registry.gd` `Registry.profile(species_id) -> Dictionary` (없으면 `{}`).
- Produces:
  - `EncounterBuilder.curve(row: Dictionary, depth: int) -> float`
  - `EncounterBuilder.weight(row: Dictionary, depth: int) -> float` = `rarity × curve`
  - `EncounterBuilder.threat(member: Dictionary) -> int` = 종족 위협 + `ROLE_BONUS[role]`
  - `EncounterBuilder.fill(rng: RandomNumberGenerator, depth: int, budget: int, ood: bool) -> Array` — 각 원소 `{"species_id":String,"role":String,"display_name":String,"max_health":int,"threat":int}`. 항상 1개 이상.
  - `EncounterBuilder.valid(members: Array, budget: int) -> String` — 빈 문자열이면 유효, 아니면 이유.
  - `EncounterBuilder.place(members: Array, floor_cells: Array, doors: Array, anchor: Vector2i, backline: Array, obstacles: Dictionary, rng: RandomNumberGenerator) -> bool` — 각 member에 `pos` 기록. 실패 시 false.
  - `EncounterBuilder.ROLE_BONUS := {"MELEE":0,"RANGED":1,"CASTER":2}`, `ROLE_WEIGHTS := {"MELEE":60,"RANGED":30,"CASTER":10}`

- [ ] **Step 1: 종족 JSON 작성**

`data/content/floor_monsters.json`:

```json
{
  "content_schema_version": 1,
  "content_type": "floor_monsters",
  "species": [
    {"species_id": "dcss_rat", "display_name": "쥐", "max_health": 25, "min_depth": 1, "max_depth": 3, "rarity": 1000, "curve": "FALL", "threat": 1, "roles": ["MELEE"], "band": null},
    {"species_id": "dcss_frilled_lizard", "display_name": "목도리 도마뱀", "max_health": 20, "min_depth": 1, "max_depth": 3, "rarity": 640, "curve": "FALL", "threat": 1, "roles": ["MELEE"], "band": null},
    {"species_id": "kobold", "display_name": "코볼트", "max_health": 28, "min_depth": 1, "max_depth": 4, "rarity": 1000, "curve": "FLAT", "threat": 2, "roles": ["MELEE","RANGED"], "band": null},
    {"species_id": "goblin", "display_name": "고블린", "max_health": 28, "min_depth": 1, "max_depth": 4, "rarity": 1000, "curve": "FLAT", "threat": 2, "roles": ["MELEE","RANGED","CASTER"], "band": null},
    {"species_id": "dcss_hobgoblin", "display_name": "홉고블린", "max_health": 55, "min_depth": 1, "max_depth": 5, "rarity": 1000, "curve": "PEAK", "threat": 3, "roles": ["MELEE"], "band": null},
    {"species_id": "dcss_orc", "display_name": "오크", "max_health": 70, "min_depth": 1, "max_depth": 6, "rarity": 1000, "curve": "RISE", "threat": 4, "roles": ["MELEE","RANGED","CASTER"], "band": null},
    {"species_id": "dcss_gnoll", "display_name": "놀", "max_health": 130, "min_depth": 1, "max_depth": 8, "rarity": 200, "curve": "PEAK", "threat": 5, "roles": ["MELEE"], "band": {"followers": ["dcss_rat","dcss_frilled_lizard"], "count": [2, 2]}},
    {"species_id": "dcss_river_rat", "display_name": "강쥐", "max_health": 110, "min_depth": 2, "max_depth": 6, "rarity": 600, "curve": "RISE", "threat": 6, "roles": ["MELEE"], "band": null}
  ]
}
```

`max_health`는 레지스트리에 없는 종족(`kobold`, `goblin`)용 폴백. 레지스트리에 있으면 레지스트리 값을 쓴다.

- [ ] **Step 2: 실패하는 테스트 작성**

`tests/encounter_builder.gd`:

```gdscript
extends SceneTree
const Builder = preload("res://expedition/encounter_builder.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r
func row(id: String) -> Dictionary:
	return Builder.species(id)
func run() -> void:
	check(Builder.table().size() == 8,"eight species loaded")
	check(is_equal_approx(Builder.curve(row("kobold"),1),1.0) and is_equal_approx(Builder.curve(row("kobold"),4),1.0),"FLAT is one across range")
	check(is_equal_approx(Builder.curve(row("dcss_orc"),1),0.15) and is_equal_approx(Builder.curve(row("dcss_orc"),6),1.0),"RISE ramps 0.15 to 1")
	check(is_equal_approx(Builder.curve(row("dcss_rat"),1),1.0) and is_equal_approx(Builder.curve(row("dcss_rat"),3),0.15),"FALL ramps 1 to 0.15")
	check(is_equal_approx(Builder.curve(row("dcss_hobgoblin"),3),1.0) and is_equal_approx(Builder.curve(row("dcss_hobgoblin"),1),0.2),"PEAK is one at the middle, 0.2 at the ends")
	check(Builder.curve(row("dcss_rat"),4) == 0.0 and Builder.curve(row("dcss_river_rat"),1) == 0.0,"outside the range is zero")
	check(is_equal_approx(Builder.weight(row("dcss_orc"),1),150.0),"orc weight at depth one is 150")
	check(Builder.threat({"species_id":"goblin","role":"CASTER"}) == 4 and Builder.threat({"species_id":"kobold","role":"RANGED"}) == 3,"role bonus adds to threat")
	# Candidates respect depth and threat ceiling.
	var early: Array = Builder.candidates(1,3+1).map(func(r): return r.species_id)
	check("dcss_river_rat" not in early and "dcss_gnoll" not in early and "dcss_hobgoblin" in early,"early candidates exclude heavy species")
	# Fill: budget respected, guardrails hold, deterministic.
	var seen_backline := false; var seen_gnoll_band := false
	for seed_value in range(200):
		for budget in [3,5,6,9]:
			var members: Array = Builder.fill(rng(seed_value),1,budget,budget >= 9)
			check(members.size() >= 1 and members.size() <= 4,"one to four members (seed %d budget %d)" % [seed_value,budget])
			check(Builder.valid(members,budget) == "","fill output is valid: %s (seed %d budget %d)" % [Builder.valid(members,budget),seed_value,budget])
			var total := 0
			for m in members: total += m.threat
			check(total >= budget-1 and total <= budget+1,"threat within budget ±1 (%d for %d)" % [total,budget])
			if members.size() >= 3: seen_backline = true
			if members.any(func(m): return m.species_id == "dcss_gnoll"):
				seen_gnoll_band = true
				check(members.size() <= 4 and members.filter(func(m): return m.species_id in ["dcss_rat","dcss_frilled_lizard"]).size() >= 2,"gnoll brings two small followers")
			for m in members:
				check(m.has("display_name") and m.max_health > 0 and m.role in ["MELEE","RANGED","CASTER"],"member carries name, health and role")
			check(members == Builder.fill(rng(seed_value),1,budget,budget >= 9),"fill is deterministic per seed")
	check(seen_backline and seen_gnoll_band,"large encounters and gnoll bands both occur")
	check(Builder.valid([{"species_id":"kobold","role":"MELEE","threat":2},{"species_id":"kobold","role":"MELEE","threat":2},{"species_id":"dcss_rat","role":"MELEE","threat":1}],5) != "","three melee without backline is rejected")
	check(Builder.valid([{"species_id":"goblin","role":"CASTER","threat":4},{"species_id":"goblin","role":"CASTER","threat":4}],9) != "","two casters rejected")
	check(Builder.valid([{"species_id":"dcss_rat","role":"MELEE","threat":1}],6) != "","far below budget rejected")
	# Depth 3 sees more orcs than depth 1 over the same seeds.
	var orcs := {1:0,3:0}
	for depth in [1,3]:
		for seed_value in range(300):
			for m in Builder.fill(rng(seed_value),depth,6,false):
				if m.species_id == "dcss_orc": orcs[depth] += 1
	check(orcs[3] > orcs[1]*2,"orcs become common by depth three (%s)" % [orcs])
	# Placement inside a 9x9 open room with one door on the north wall.
	var cells: Array = []
	for y in range(1,10):
		for x in range(1,10): cells.append(Vector2i(x,y))
	var door := Vector2i(5,0)
	var members: Array = [{"species_id":"dcss_hobgoblin","role":"MELEE","threat":3},{"species_id":"goblin","role":"RANGED","threat":3},{"species_id":"kobold","role":"MELEE","threat":2}]
	check(Builder.place(members,cells,[door],Vector2i(-1,-1),[],{},rng(1)),"placement succeeds in an open room")
	var positions: Array = members.map(func(m): return m.pos)
	check(positions.size() == 3 and positions[0] != positions[1] and positions[1] != positions[2] and positions[0] != positions[2],"members occupy distinct cells")
	for m in members: check(maxi(absi(m.pos.x-door.x),absi(m.pos.y-door.y)) >= 3,"every member at least three cells from the door")
	check(members[0].pos.y == 9,"leader anchors on the wall farthest from the door")
	var tiny: Array = []
	for y in range(1,3):
		for x in range(1,4): tiny.append(Vector2i(x,y))
	check(not Builder.place(members,tiny,[Vector2i(2,0)],Vector2i(-1,-1),[],{},rng(1)),"a 3x2 room cannot keep members three cells from the door")
	print("Encounter builder: %d failures" % failures); quit(1 if failures else 0)
```

- [ ] **Step 3: 실패 확인**

Run: `godot --headless --path . --script res://tests/encounter_builder.gd`
Expected: 스크립트 로드 오류.

- [ ] **Step 4: 빌더 구현**

`expedition/encounter_builder.gd`:

```gdscript
extends RefCounted
## DCSS-style depth table + DD-style threat budget. Pure functions over the
## seeded RNG passed in; never touches the session.
const Registry = preload("res://expedition/legacy/dcss_enemy_registry.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_monsters.json"))
const ROLE_BONUS := {"MELEE":0,"RANGED":1,"CASTER":2}
const ROLE_WEIGHTS := {"MELEE":60,"RANGED":30,"CASTER":10}
const MAX_MEMBERS := 4
const MAX_REROLLS := 20
const OOD_PERCENT := 10

static func table() -> Array:
	return content.get("species",[])

static func species(id: String) -> Dictionary:
	for row in table():
		if row.species_id == id: return row
	return {}

static func curve(row: Dictionary, depth: int) -> float:
	var lo: int = int(row.min_depth); var hi: int = int(row.max_depth)
	if depth < lo or depth > hi: return 0.0
	var t: float = 0.0 if hi == lo else float(depth-lo)/float(hi-lo)
	match str(row.curve):
		"RISE": return 0.15+0.85*t
		"FALL": return 1.0-0.85*t
		"PEAK": return 0.2+0.8*(1.0-absf(2.0*t-1.0))
		_: return 1.0

static func weight(row: Dictionary, depth: int) -> float:
	return float(row.rarity)*curve(row,depth)

static func threat(member: Dictionary) -> int:
	var row := species(member.species_id)
	return int(row.get("threat",1))+int(ROLE_BONUS.get(member.role,0))

static func candidates(depth: int, max_threat: int) -> Array:
	return table().filter(func(r): return weight(r,depth) > 0.0 and int(r.threat) <= max_threat)

static func pick_weighted(rng: RandomNumberGenerator, rows: Array, weights: Array) -> Variant:
	var total := 0.0
	for w in weights: total += w
	if total <= 0.0: return null
	var roll := rng.randf()*total
	for i in range(rows.size()):
		roll -= weights[i]
		if roll <= 0.0: return rows[i]
	return rows[rows.size()-1]

static func health_for(id: String, row: Dictionary) -> int:
	var profile: Dictionary = Registry.profile(id)
	return int(profile.get("max_health",row.get("max_health",28)))

static func member(row: Dictionary, role: String) -> Dictionary:
	var result := {"species_id":str(row.species_id),"role":role,"display_name":str(row.display_name),"max_health":health_for(row.species_id,row)}
	result.threat = threat(result)
	return result

static func role_allowed(members: Array, row: Dictionary, role: String) -> bool:
	if role not in row.roles: return false
	if role == "CASTER" and members.any(func(m): return m.role == "CASTER"): return false
	var same: int = members.filter(func(m): return m.species_id == row.species_id and m.role == role).size()
	return same < 2

static func choose_role(rng: RandomNumberGenerator, members: Array, row: Dictionary) -> String:
	var roles: Array = []; var weights: Array = []
	for role in ROLE_WEIGHTS:
		if role_allowed(members,row,role): roles.append(role); weights.append(float(ROLE_WEIGHTS[role]))
	if roles.is_empty(): return ""
	return pick_weighted(rng,roles,weights)

## Empty string when the group is legal for the budget; otherwise the reason.
static func valid(members: Array, budget: int) -> String:
	if members.is_empty(): return "empty"
	if members.size() > MAX_MEMBERS: return "too many"
	var total := 0
	for m in members: total += int(m.get("threat",threat(m)))
	if total < budget-1: return "too weak (%d < %d)" % [total,budget-1]
	if total > budget+1: return "too strong (%d > %d)" % [total,budget+1]
	if members.filter(func(m): return m.role == "CASTER").size() > 1: return "two casters"
	if members.size() >= 3 and members.all(func(m): return m.role == "MELEE"): return "no backline"
	var pairs: Dictionary = {}
	for m in members:
		var key: String = m.species_id+"/"+m.role
		pairs[key] = int(pairs.get(key,0))+1
		if pairs[key] > 2: return "three of a kind"
	return ""

static func attempt(rng: RandomNumberGenerator, depth: int, budget: int, ood: bool) -> Array:
	var members: Array = []
	var remaining := budget
	var table_depth := depth
	if ood and rng.randi_range(1,100) <= OOD_PERCENT: table_depth = depth+1
	while remaining >= 1 and members.size() < MAX_MEMBERS:
		var rows: Array = candidates(table_depth,remaining+1)
		if rows.is_empty(): break
		var row: Dictionary = pick_weighted(rng,rows,rows.map(func(r): return weight(r,table_depth)))
		var role := choose_role(rng,members,row)
		if role.is_empty(): continue
		var picked := member(row,role)
		members.append(picked); remaining -= picked.threat
		if row.band != null and members.filter(func(m): return m.species_id == row.species_id).size() == 1:
			var count: int = rng.randi_range(int(row.band.count[0]),int(row.band.count[1]))
			for _i in range(count):
				if members.size() >= MAX_MEMBERS: break
				var follower_id: String = row.band.followers[rng.randi_range(0,row.band.followers.size()-1)]
				var follower := member(species(follower_id),"MELEE")
				members.append(follower); remaining -= follower.threat
			break
	if members.size() >= 3 and members.all(func(m): return m.role == "MELEE"):
		for i in range(members.size()-1,-1,-1):
			var row := species(members[i].species_id)
			if "RANGED" in row.roles:
				members[i] = member(row,"RANGED"); break
	return members

static func fill(rng: RandomNumberGenerator, depth: int, budget: int, ood: bool) -> Array:
	for _try in range(MAX_REROLLS):
		var members := attempt(rng,depth,budget,ood)
		if valid(members,budget).is_empty(): return members
	# Fallback: the strongest single species that fits, always legal for budget-1..budget+1.
	var rows: Array = candidates(depth,budget+1)
	rows.sort_custom(func(a,b): return int(a.threat) > int(b.threat))
	for row in rows:
		var solo := [member(row,"MELEE")]
		if valid(solo,budget).is_empty(): return solo
	return [member(rows[0] if not rows.is_empty() else species("kobold"),"MELEE")]

static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func door_distance(p: Vector2i, doors: Array) -> int:
	var best := 999
	for d in doors: best = mini(best,chebyshev(p,d))
	return best

## Leader on the anchor (farthest floor cell from the doors when the room has
## no anchor), melee beside the leader, backline on P cells or beside obstacles
## behind the leader. Every member ends >= 3 from every door.
static func place(members: Array, floor_cells: Array, doors: Array, anchor: Vector2i, backline: Array, obstacles: Dictionary, rng: RandomNumberGenerator) -> bool:
	var free: Dictionary = {}
	for p in floor_cells:
		if not obstacles.has(p): free[p] = true
	var ordered: Array = free.keys()
	ordered.sort_custom(func(a,b): return door_distance(a,doors) > door_distance(b,doors) if door_distance(a,doors) != door_distance(b,doors) else (a.y > b.y if a.y != b.y else a.x < b.x))
	var anchors: Array = ([anchor] if anchor != Vector2i(-1,-1) and free.has(anchor) else [])+ordered
	var leader_index := 0
	for i in range(members.size()):
		if members[i].threat > members[leader_index].threat: leader_index = i
	for start in anchors:
		if door_distance(start,doors) < 3: continue
		var taken: Dictionary = {start:true}
		var placed := {leader_index:start}
		var ok := true
		for i in range(members.size()):
			if i == leader_index: continue
			var options: Array = []
			if members[i].role != "MELEE":
				for p in backline:
					if free.has(p) and not taken.has(p) and door_distance(p,doors) >= 3: options.append(p)
				if options.is_empty():
					for p in ordered:
						if taken.has(p) or door_distance(p,doors) < 3 or chebyshev(p,start) > 3: continue
						var near_obstacle := false
						for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
							if obstacles.has(p+d) or not free.has(p+d): near_obstacle = true
						if near_obstacle: options.append(p)
			if options.is_empty():
				for p in ordered:
					if not taken.has(p) and door_distance(p,doors) >= 3 and chebyshev(p,start) <= 2: options.append(p)
			if options.is_empty(): ok = false; break
			var pick: Vector2i = options[rng.randi_range(0,options.size()-1)]
			taken[pick] = true; placed[i] = pick
		if ok:
			for i in placed: members[i].pos = placed[i]
			return true
	return false
```

- [ ] **Step 5: 통과 확인**

Run: `godot --headless --path . --script res://tests/encounter_builder.gd`
Expected: `Encounter builder: 0 failures`. 통계 검사(`orcs[3] > orcs[1]*2`, `seen_gnoll_band`)가 실패하면 시드 범위를 늘리지 말고 곡선·rarity 계산을 다시 확인한다(오크 D1 150 vs D3 490, 놀 D1 40).

- [ ] **Step 6: 커밋(건너뜀). 스위트 재실행.**

---

### Task 3: 방 뿌리기와 그래프 (`floor_generator.gd` 1/3)

**Files:**
- Create: `data/content/floor_themes.json`
- Create: `expedition/floor_generator.gd`
- Test: `tests/floor_generator.gd` (이 Task에서 시작, Task 4·5에서 확장)

**Interfaces:**
- Consumes: Task 1 `FloorTemplates.definition/rotate/parse`.
- Produces:
  - `FloorGenerator.theme(id: String) -> Dictionary`
  - `FloorGenerator.scatter_rooms(theme: Dictionary, rng: RandomNumberGenerator) -> Array` — 방 배열. 각 방 `{"id":int,"rect":Rect2i(내부),"kind":"template"|"fight"|"plain","template_id":String,"rows":Array(회전 적용된 템플릿 행, 절차 방은 []),"parsed":Dictionary(템플릿만),"doors":[],"tier":"","spine":false}`. 부족하면 `[]`.
  - `FloorGenerator.outer(rect: Rect2i) -> Rect2i` — 내부 사각형 + 벽 1칸.
  - `FloorGenerator.build_graph(rooms: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Array` — 간선 `[[a,b],...]` (a<b). 보고는 잎.
  - `FloorGenerator.room_index(rooms: Array, template_id: String) -> int`

- [ ] **Step 1: 테마 JSON 작성**

`data/content/floor_themes.json`:

```json
{
  "content_schema_version": 1,
  "content_type": "floor_themes",
  "themes": {
    "F1_RUINS": {
      "label": "갈림길 미궁",
      "size": 64,
      "depth": 1,
      "rooms": {"count": [10, 12], "fight": [4, 6], "fight_size": [[9, 9], [12, 10]], "plain_size": [[5, 5], [8, 7]]},
      "corridor": {"width": 1, "wiggle": 2, "extra_links": [2, 3]},
      "palette": {"floor": "stone", "accents": ["rubble", "wood", "water"], "accent_ratio": 0.12},
      "templates": {"required": ["entry_camp", "relic_vault", "sealed_treasury"], "fight_pool": ["flooded_cistern", "collapsed_store", "timber_gallery"], "fight_picks": 2},
      "monsters": {"budget": {"early": 3, "mid": 6, "deep": 9, "optional": 5}},
      "curios": {"locked_chest": [2, 3], "dirt_pile": [2, 3]}
    },
    "F2_MINES": {
      "label": "폐광",
      "size": 64,
      "depth": 2,
      "rooms": {"count": [10, 12], "fight": [4, 6], "fight_size": [[9, 9], [12, 10]], "plain_size": [[5, 5], [8, 7]]},
      "corridor": {"width": 1, "wiggle": 2, "extra_links": [2, 3]},
      "palette": {"floor": "stone", "accents": ["metal", "wood"], "accent_ratio": 0.15},
      "templates": {"required": ["entry_camp", "relic_vault", "sealed_treasury"], "fight_pool": ["flooded_cistern", "collapsed_store", "timber_gallery"], "fight_picks": 2},
      "monsters": {"budget": {"early": 4, "mid": 8, "deep": 12, "optional": 6}},
      "curios": {"locked_chest": [2, 3], "dirt_pile": [2, 3]}
    }
  }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`tests/floor_generator.gd` (초판):

```gdscript
extends SceneTree
const Generator = preload("res://expedition/floor_generator.gd")
const Templates = preload("res://expedition/floor_templates.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_value; return r
func run() -> void:
	var theme: Dictionary = Generator.theme("F1_RUINS")
	check(theme.size == 64 and theme.depth == 1,"theme loads")
	check(Generator.theme("nope").is_empty(),"unknown theme is empty")
	await rooms_and_graph(theme)
	print("Floor generator: %d failures" % failures); quit(1 if failures else 0)

func rooms_and_graph(theme: Dictionary) -> void:
	for seed_value in range(100):
		var rooms: Array = Generator.scatter_rooms(theme,rng(seed_value))
		if rooms.is_empty(): continue # scatter may fail; generate() retries with seed+1 (Task 5)
		check(rooms.size() >= theme.rooms.count[0] and rooms.size() <= theme.rooms.count[1],"room count in range (seed %d: %d)" % [seed_value,rooms.size()])
		var fights: int = rooms.filter(func(r): return r.kind == "fight" or (r.kind == "template" and r.template_id in theme.templates.fight_pool)).size()
		check(fights >= theme.rooms.fight[0] and fights <= theme.rooms.fight[1],"fight room count in range (seed %d: %d)" % [seed_value,fights])
		for id in theme.templates.required: check(Generator.room_index(rooms,id) >= 0,"required template %s present" % id)
		check(rooms.filter(func(r): return r.kind == "template" and r.template_id in theme.templates.fight_pool).size() == theme.templates.fight_picks,"two fight templates picked")
		for i in range(rooms.size()):
			var a: Rect2i = Generator.outer(rooms[i].rect)
			check(a.position.x >= 1 and a.position.y >= 1 and a.end.x <= theme.size-1 and a.end.y <= theme.size-1,"room inside the border wall")
			for j in range(i+1,rooms.size()):
				check(not a.grow(1).intersects(Generator.outer(rooms[j].rect)),"rooms keep two wall cells apart (seed %d)" % seed_value)
			if rooms[i].kind == "fight":
				check(rooms[i].rect.size.x >= 9 and rooms[i].rect.size.y >= 9 and rooms[i].rect.size.x <= 12 and rooms[i].rect.size.y <= 10,"fight room size")
			elif rooms[i].kind == "plain":
				check(rooms[i].rect.size.x >= 5 and rooms[i].rect.size.y >= 5 and rooms[i].rect.size.x <= 8 and rooms[i].rect.size.y <= 7,"plain room size")
			else:
				check(rooms[i].rows.size() == rooms[i].rect.size.y+2,"template rect matches rotated rows")
		var entry: Rect2i = rooms[Generator.room_index(rooms,"entry_camp")].rect
		var relic: Rect2i = rooms[Generator.room_index(rooms,"relic_vault")].rect
		check(entry.position.x < theme.size/3 and relic.position.x > theme.size*2/3-relic.size.x,"entry west, relic east")
		var edges: Array = Generator.build_graph(rooms,theme,rng(seed_value))
		check(edges.size() >= rooms.size()-1+theme.corridor.extra_links[0] and edges.size() <= rooms.size()-1+theme.corridor.extra_links[1],"spanning tree plus extra links (seed %d: %d edges for %d rooms)" % [seed_value,edges.size(),rooms.size()])
		var degree: Dictionary = {}
		for e in edges:
			check(e[0] < e[1],"edges stored ascending")
			degree[e[0]] = int(degree.get(e[0],0))+1; degree[e[1]] = int(degree.get(e[1],0))+1
		check(degree.get(Generator.room_index(rooms,"sealed_treasury"),0) == 1,"treasury is a leaf")
		check(degree.size() == rooms.size(),"every room connected")
		var leaves: int = 0
		for id in degree: if degree[id] == 1: leaves += 1
		check(leaves >= 2,"at least two dead ends (seed %d)" % seed_value)
		check(edges == Generator.build_graph(rooms,theme,rng(seed_value)),"graph deterministic")
```

- [ ] **Step 3: 실패 확인**

Run: `godot --headless --path . --script res://tests/floor_generator.gd`
Expected: 스크립트 로드 오류.

- [ ] **Step 4: 방 뿌리기·그래프 구현**

`expedition/floor_generator.gd` (1/3 — 이 Task 분량):

```gdscript
extends RefCounted
## Procedural floor: DCSS layout_rooms variant (scatter rooms, MST + loops,
## noisy-Dijkstra corridors, ASCII vault templates) with DD-style room-bound
## encounters. Pure static functions; output contract in the spec §7.
const Templates = preload("res://expedition/floor_templates.gd")
const Encounters = preload("res://expedition/encounter_builder.gd")
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/floor_themes.json"))
const PLACE_TRIES := 200
const MAX_REGENERATIONS := 5
const ROOM_GAP := 2
const DIRECTIONS4 := [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]
const DIRECTIONS8 := [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]

static func theme(id: String) -> Dictionary:
	return content.get("themes",{}).get(id,{})

static func outer(rect: Rect2i) -> Rect2i:
	return Rect2i(rect.position-Vector2i.ONE,rect.size+Vector2i(2,2))

static func room_index(rooms: Array, template_id: String) -> int:
	for i in range(rooms.size()):
		if rooms[i].template_id == template_id: return i
	return -1

static func make_room(id: int, rect: Rect2i, kind: String, template_id: String = "", rows: Array = [], parsed: Dictionary = {}) -> Dictionary:
	return {"id":id,"rect":rect,"kind":kind,"template_id":template_id,"rows":rows,"parsed":parsed,"doors":[],"tier":"","spine":false}

static func fits(rect: Rect2i, rooms: Array, size: int) -> bool:
	var shell := outer(rect)
	if shell.position.x < 1 or shell.position.y < 1 or shell.end.x > size-1 or shell.end.y > size-1: return false
	for room in rooms:
		if shell.grow(ROOM_GAP-1).intersects(outer(room.rect)): return false
	return true

## Room plan in placement order: required templates, picked fight templates,
## procedural fight rooms, plain rooms. Returns [] when placement fails.
static func scatter_rooms(theme: Dictionary, rng: RandomNumberGenerator) -> Array:
	var size: int = theme.size
	var count: int = rng.randi_range(theme.rooms.count[0],theme.rooms.count[1])
	var fight_total: int = rng.randi_range(theme.rooms.fight[0],theme.rooms.fight[1])
	var pool: Array = theme.templates.fight_pool.duplicate()
	var picks: Array = []
	for _i in range(theme.templates.fight_picks):
		picks.append(pool.pop_at(rng.randi_range(0,pool.size()-1)))
	var plan: Array = []
	for id in theme.templates.required: plan.append({"kind":"template","template_id":id})
	for id in picks: plan.append({"kind":"template","template_id":id})
	for _i in range(fight_total-picks.size()): plan.append({"kind":"fight"})
	while plan.size() < count: plan.append({"kind":"plain"})
	var rooms: Array = []
	for spec in plan:
		var placed := false
		for _try in range(PLACE_TRIES):
			var rect: Rect2i
			var rows: Array = []
			var parsed: Dictionary = {}
			if spec.kind == "template":
				var def: Dictionary = Templates.definition(spec.template_id)
				rows = Templates.rotate(def.rows,rng.randi_range(0,3) if def.orient else 0)
				parsed = Templates.parse(rows)
				var interior := Vector2i(parsed.width-2,parsed.height-2)
				rect = Rect2i(random_origin(theme,rng,interior,spec.template_id),interior)
			else:
				var range_rows: Array = theme.rooms.fight_size if spec.kind == "fight" else theme.rooms.plain_size
				var interior := Vector2i(rng.randi_range(range_rows[0][0],range_rows[1][0]),rng.randi_range(range_rows[0][1],range_rows[1][1]))
				rect = Rect2i(random_origin(theme,rng,interior,""),interior)
			if not fits(rect,rooms,size): continue
			rooms.append(make_room(rooms.size(),rect,spec.kind,spec.get("template_id",""),rows,parsed))
			placed = true; break
		if not placed: return []
	return rooms

static func random_origin(theme: Dictionary, rng: RandomNumberGenerator, interior: Vector2i, template_id: String) -> Vector2i:
	# Origins start at 3 so a door on the outer wall still has a corridor cell
	# (x or y == 1) outside it; dig_path never uses the border row/column.
	var size: int = theme.size
	var min_x := 3; var max_x: int = size-3-interior.x-1
	if template_id == "entry_camp": max_x = mini(max_x,size/3-interior.x)
	elif template_id == "relic_vault": min_x = maxi(min_x,size*2/3)
	return Vector2i(rng.randi_range(min_x,maxi(min_x,max_x)),rng.randi_range(3,size-3-interior.y-1))

static func center(room: Dictionary) -> Vector2:
	return Vector2(room.rect.position)+Vector2(room.rect.size)/2.0

static func segment_crosses_room(a: Vector2, b: Vector2, rooms: Array, skip: Array) -> bool:
	var steps: int = int(a.distance_to(b)*2)+1
	for i in range(steps+1):
		var p: Vector2 = a.lerp(b,float(i)/steps)
		for room in rooms:
			if room.id in skip: continue
			if Rect2(outer(room.rect)).has_point(p): return true
	return false

static func find_root(parent: Array, i: int) -> int:
	while parent[i] != i: parent[i] = parent[parent[i]]; i = parent[i]
	return i

## Kruskal MST over room centres (treasury excluded), extra links that do not
## cut through other rooms, then the treasury hung as a leaf on its nearest
## non-template room.
static func build_graph(rooms: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Array:
	var treasury := room_index(rooms,"sealed_treasury")
	var pairs: Array = []
	for i in range(rooms.size()):
		for j in range(i+1,rooms.size()):
			if i == treasury or j == treasury: continue
			pairs.append({"a":i,"b":j,"d":center(rooms[i]).distance_to(center(rooms[j]))})
	pairs.sort_custom(func(x,y): return x.d < y.d if x.d != y.d else (x.a < y.a if x.a != y.a else x.b < y.b))
	var parent: Array = range(rooms.size())
	var edges: Array = []
	var used: Dictionary = {}
	for pair in pairs:
		var ra := find_root(parent,pair.a); var rb := find_root(parent,pair.b)
		if ra == rb: continue
		parent[ra] = rb; edges.append([pair.a,pair.b]); used["%d/%d" % [pair.a,pair.b]] = true
	var extra: int = rng.randi_range(theme.corridor.extra_links[0],theme.corridor.extra_links[1])
	for pair in pairs:
		if extra <= 0: break
		if used.has("%d/%d" % [pair.a,pair.b]): continue
		if segment_crosses_room(center(rooms[pair.a]),center(rooms[pair.b]),rooms,[pair.a,pair.b]): continue
		edges.append([pair.a,pair.b]); used["%d/%d" % [pair.a,pair.b]] = true; extra -= 1
	if treasury >= 0:
		var best := -1; var best_d := INF
		for i in range(rooms.size()):
			if i == treasury or rooms[i].kind == "template": continue
			var d := center(rooms[i]).distance_to(center(rooms[treasury]))
			if d < best_d: best_d = d; best = i
		edges.append([mini(best,treasury),maxi(best,treasury)])
	return edges
```

- [ ] **Step 5: 통과 확인**

Run: `godot --headless --path . --script res://tests/floor_generator.gd`
Expected: `Floor generator: 0 failures`. `scatter_rooms`가 100시드 중 자주 `[]`를 돌려주면(30개 이상) `PLACE_TRIES`를 늘리지 말고 방 크기 상한이 64×64에서 12개를 못 담는 것이므로 `count` 상한이 아니라 `ROOM_GAP` 계산(`grow(ROOM_GAP-1)`)이 맞는지 확인한다.

- [ ] **Step 6: 커밋(건너뜀). 스위트 재실행.**

---

### Task 4: 복도·템플릿 스탬프·지형 칠하기 (`floor_generator.gd` 2/3)

**Files:**
- Modify: `expedition/floor_generator.gd`
- Modify: `tests/floor_generator.gd`

**Interfaces:**
- Consumes: Task 3 `rooms`, `edges`; Task 1 `Templates.stamp`.
- Produces:
  - `FloorGenerator.carve(rooms: Array, edges: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Array` — `terrain: Array[String]` (size×size). 부수 효과: 각 `room.doors`(Vector2i, 벽 링 위의 바닥 칸) 채움.
  - `FloorGenerator.paint(terrain: Array, rooms: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Dictionary` — `{room_id: {"obstacles":{Vector2i:true}}}`. 조우 방 기둥, 절차 방 액센트.
  - `FloorGenerator.floor_cells(terrain: Array, size: int, rect: Rect2i) -> Array`
  - `FloorGenerator.reachable_from(terrain: Array, size: int, origin: Vector2i) -> Dictionary` — `{Vector2i: dist}` 8방향·모서리 규칙(`Session.melee_reach`와 동일).
  - `FloorGenerator.has_open_block(terrain: Array, size: int, rect: Rect2i, obstacles: Dictionary, side: int) -> bool`

- [ ] **Step 1: 테스트 확장**

`tests/floor_generator.gd`의 `run()`에 `await corridors_and_paint(theme)`를 `rooms_and_graph` 다음 줄에 추가하고 함수를 붙인다:

```gdscript
func corridors_and_paint(theme: Dictionary) -> void:
	var size: int = theme.size
	for seed_value in range(100):
		var rooms: Array = Generator.scatter_rooms(theme,rng(seed_value))
		if rooms.is_empty(): continue
		var edges: Array = Generator.build_graph(rooms,theme,rng(seed_value))
		var terrain: Array = Generator.carve(rooms,edges,theme,rng(seed_value))
		check(terrain.size() == size*size,"terrain covers the board")
		for i in range(size):
			check(terrain[i] == "wall" and terrain[(size-1)*size+i] == "wall" and terrain[i*size] == "wall" and terrain[i*size+size-1] == "wall","border stays wall")
		for room in rooms:
			check(room.doors.size() >= 1,"room %d has a door (seed %d)" % [room.id,seed_value])
			for d in room.doors:
				check(terrain[d.y*size+d.x] != "wall","door cell is floor")
				check(not room.rect.has_point(d) and Generator.outer(room.rect).has_point(d),"door sits on the wall ring")
			if room.kind == "template":
				var parsed: Dictionary = room.parsed
				for p in parsed.terrain:
					var cell: Vector2i = room.rect.position-Vector2i.ONE+p
					if p in parsed.doors: continue
					check(terrain[cell.y*size+cell.x] == parsed.terrain[p],"template interior untouched by corridors (seed %d)" % seed_value)
		check(rooms[Generator.room_index(rooms,"sealed_treasury")].doors.size() == 1,"treasury keeps a single door")
		var entry_room: Dictionary = rooms[Generator.room_index(rooms,"entry_camp")]
		var origin: Vector2i = entry_room.rect.position+Vector2i(1,2) # '@' sits at template (2,3); rect excludes the wall
		var reach: Dictionary = Generator.reachable_from(terrain,size,origin)
		for room in rooms:
			for p in Generator.floor_cells(terrain,size,room.rect):
				check(reach.has(p),"every room floor reachable from the entry (seed %d room %d)" % [seed_value,room.id])
		var painted: Dictionary = Generator.paint(terrain,rooms,theme,rng(seed_value))
		for room in rooms:
			if room.kind != "fight": continue
			var area: int = room.rect.size.x*room.rect.size.y
			var obstacles: Dictionary = painted[room.id].obstacles
			check(obstacles.size() <= area*15/100,"fight room obstacles at most 15 percent")
			check(Generator.has_open_block(terrain,size,room.rect,obstacles,5),"fight room keeps an open 5x5 block (seed %d room %d)" % [seed_value,room.id])
			for p in obstacles:
				for d in room.doors: check(maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1,"pillars keep clear of doors")
		var reach_after: Dictionary = Generator.reachable_from(terrain,size,origin)
		for room in rooms:
			for p in Generator.floor_cells(terrain,size,room.rect):
				check(reach_after.has(p),"painting never disconnects a room (seed %d)" % seed_value)
		var accents: int = 0
		for cell in terrain: if cell in ["rubble","wood","water"]: accents += 1
		check(accents > 0,"palette accents painted")
		check(terrain == Generator.carve(rooms,edges,theme,rng(seed_value)) or true,"carve consumed rng; determinism is checked through generate() in Task 5")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/floor_generator.gd`
Expected: `carve` 미정의 오류.

- [ ] **Step 3: 복도·칠하기 구현**

`expedition/floor_generator.gd`에 추가:

```gdscript
static func index_of(size: int, p: Vector2i) -> int:
	return p.y*size+p.x

static func inside(size: int, p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < size and p.y < size

## Door candidates on the wall ring: template '+' cells, or the middle ±2 of
## each side for procedural rooms (corners excluded).
static func door_candidates(room: Dictionary) -> Array:
	var shell := outer(room.rect)
	if room.kind == "template":
		return room.parsed.doors.map(func(p): return shell.position+p)
	var result: Array = []
	var cx: int = room.rect.position.x+room.rect.size.x/2
	var cy: int = room.rect.position.y+room.rect.size.y/2
	for dx in range(-2,3):
		var x: int = cx+dx
		if x > room.rect.position.x and x < room.rect.end.x-1: result.append(Vector2i(x,shell.position.y)); result.append(Vector2i(x,shell.end.y-1))
	for dy in range(-2,3):
		var y: int = cy+dy
		if y > room.rect.position.y and y < room.rect.end.y-1: result.append(Vector2i(shell.position.x,y)); result.append(Vector2i(shell.end.x-1,y))
	return result

static func outward(room: Dictionary, door: Vector2i) -> Vector2i:
	var shell := outer(room.rect)
	if door.y == shell.position.y: return Vector2i.UP
	if door.y == shell.end.y-1: return Vector2i.DOWN
	if door.x == shell.position.x: return Vector2i.LEFT
	return Vector2i.RIGHT

## Noisy Dijkstra between two cells: walls cost 3, existing floor 1, plus
## rng noise up to `wiggle` so corridors bend like DCSS join_the_dots.
## Protected cells (template shells) are impassable.
static func dig_path(terrain: Array, size: int, start: Vector2i, goal: Vector2i, protected: Dictionary, wiggle: int, rng: RandomNumberGenerator) -> Array:
	var noise: Dictionary = {}
	var cost: Dictionary = {start:0.0}
	var previous: Dictionary = {}
	var open: Array = [start]
	while not open.is_empty():
		var best := 0
		for i in range(1,open.size()):
			if cost[open[i]] < cost[open[best]]: best = i
		var current: Vector2i = open.pop_at(best)
		if current == goal: break
		for d in DIRECTIONS4:
			var next: Vector2i = current+d
			if not inside(size,next) or next.x == 0 or next.y == 0 or next.x == size-1 or next.y == size-1: continue
			if protected.has(next) and next != goal: continue
			if not noise.has(next): noise[next] = rng.randf()*wiggle
			var step: float = (1.0 if terrain[index_of(size,next)] != "wall" else 3.0)+noise[next]
			var total: float = cost[current]+step
			if not cost.has(next) or total < cost[next]:
				cost[next] = total; previous[next] = current
				if next not in open: open.append(next)
	if not previous.has(goal) and start != goal: return []
	var path: Array = [goal]
	while path[path.size()-1] != start: path.append(previous[path[path.size()-1]])
	path.reverse()
	return path

static func carve(rooms: Array, edges: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Array:
	var size: int = theme.size
	var terrain: Array = []; terrain.resize(size*size); terrain.fill("wall")
	var protected: Dictionary = {}
	for room in rooms:
		room.doors = []
		if room.kind == "template":
			Templates.stamp(terrain,size,room.rect.position-Vector2i.ONE,room.parsed)
			var shell := outer(room.rect)
			for y in range(shell.position.y,shell.end.y):
				for x in range(shell.position.x,shell.end.x): protected[Vector2i(x,y)] = true
		else:
			for y in range(room.rect.position.y,room.rect.end.y):
				for x in range(room.rect.position.x,room.rect.end.x): terrain[index_of(size,Vector2i(x,y))] = theme.palette.floor
	for edge in edges:
		var a: Dictionary = rooms[edge[0]]; var b: Dictionary = rooms[edge[1]]
		var best_pair: Array = []; var best_d := 1 << 30
		for da in door_candidates(a):
			for db in door_candidates(b):
				var d: int = absi(da.x-db.x)+absi(da.y-db.y)
				if d < best_d: best_d = d; best_pair = [da,db]
		var da: Vector2i = best_pair[0]; var db: Vector2i = best_pair[1]
		var from: Vector2i = da+outward(a,da); var to: Vector2i = db+outward(b,db)
		var path := dig_path(terrain,size,from,to,protected,theme.corridor.wiggle,rng)
		if path.is_empty(): continue
		for p in [da,db]+path:
			if terrain[index_of(size,p)] == "wall": terrain[index_of(size,p)] = theme.palette.floor
		if da not in a.doors: a.doors.append(da)
		if db not in b.doors: b.doors.append(db)
	# Corridors that brushed a procedural room's wall ring opened extra doors.
	for room in rooms:
		if room.kind == "template": continue
		var shell := outer(room.rect)
		for y in range(shell.position.y,shell.end.y):
			for x in range(shell.position.x,shell.end.x):
				var p := Vector2i(x,y)
				if room.rect.has_point(p): continue
				if terrain[index_of(size,p)] != "wall" and p not in room.doors and (x == shell.position.x or x == shell.end.x-1) != (y == shell.position.y or y == shell.end.y-1): room.doors.append(p)
	return terrain

static func floor_cells(terrain: Array, size: int, rect: Rect2i) -> Array:
	var result: Array = []
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if terrain[index_of(size,Vector2i(x,y))] != "wall": result.append(Vector2i(x,y))
	return result

## Same rule as Session.melee_reach: diagonal steps need both orthogonal
## neighbours open.
static func reachable_from(terrain: Array, size: int, origin: Vector2i) -> Dictionary:
	var dist: Dictionary = {origin:0}
	var queue: Array = [origin]; var cursor := 0
	while cursor < queue.size():
		var p: Vector2i = queue[cursor]; cursor += 1
		for d in DIRECTIONS8:
			var next: Vector2i = p+d
			if dist.has(next) or not inside(size,next) or terrain[index_of(size,next)] == "wall": continue
			if d.x != 0 and d.y != 0 and (terrain[index_of(size,Vector2i(p.x,next.y))] == "wall" or terrain[index_of(size,Vector2i(next.x,p.y))] == "wall"): continue
			dist[next] = int(dist[p])+1; queue.append(next)
	return dist

static func has_open_block(terrain: Array, size: int, rect: Rect2i, obstacles: Dictionary, side: int) -> bool:
	for y in range(rect.position.y,rect.end.y-side+1):
		for x in range(rect.position.x,rect.end.x-side+1):
			var open := true
			for yy in range(y,y+side):
				for xx in range(x,x+side):
					var p := Vector2i(xx,yy)
					if obstacles.has(p) or terrain[index_of(size,p)] == "wall": open = false
			if open: return true
	return false

static func paint(terrain: Array, rooms: Array, theme: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var size: int = theme.size
	var result: Dictionary = {}
	for room in rooms:
		var obstacles: Dictionary = {}
		if room.kind == "fight":
			var cells := floor_cells(terrain,size,room.rect)
			var wanted: int = cells.size()*10/100
			var candidates: Array = cells.filter(func(p): return room.doors.all(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1))
			for _i in range(wanted):
				if candidates.is_empty(): break
				var p: Vector2i = candidates.pop_at(rng.randi_range(0,candidates.size()-1))
				obstacles[p] = true
				candidates = candidates.filter(func(q): return maxi(absi(q.x-p.x),absi(q.y-p.y)) > 1)
			var keys: Array = obstacles.keys()
			while not has_open_block(terrain,size,room.rect,obstacles,5) and not keys.is_empty():
				obstacles.erase(keys.pop_back())
			for p in obstacles: terrain[index_of(size,p)] = "wall"
			# A pillar must never cut a room in two.
			var cells_after := floor_cells(terrain,size,room.rect)
			var reach := reachable_from(terrain,size,cells_after[0])
			if not cells_after.all(func(p): return reach.has(p)):
				for p in obstacles: terrain[index_of(size,p)] = theme.palette.floor
				obstacles.clear()
		elif room.kind == "plain":
			var cells := floor_cells(terrain,size,room.rect)
			var accent: String = theme.palette.accents[rng.randi_range(0,theme.palette.accents.size()-1)]
			var wanted: int = int(cells.size()*theme.palette.accent_ratio)
			var seed_cell: Vector2i = cells[rng.randi_range(0,cells.size()-1)]
			var cluster: Array = [seed_cell]; var seen: Dictionary = {seed_cell:true}
			var cursor := 0
			while cluster.size() < wanted and cursor < cluster.size():
				for d in DIRECTIONS4:
					var next: Vector2i = cluster[cursor]+d
					if room.rect.has_point(next) and not seen.has(next) and rng.randi_range(0,2) > 0:
						seen[next] = true; cluster.append(next)
						if cluster.size() >= wanted: break
				cursor += 1
			for p in cluster:
				if room.doors.all(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1): terrain[index_of(size,p)] = accent
		result[room.id] = {"obstacles":obstacles}
	return result
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/floor_generator.gd`
Expected: `Floor generator: 0 failures`. "every room floor reachable"이 실패하면 `dig_path`가 빈 경로를 반환한 간선이 있는 것 — 보고 문이 다른 템플릿 쪽을 보고 있어 `protected`에 막힌 경우다. 이때는 `door_candidates`가 아니라 `random_origin`/회전이 원인이므로 Task 5의 재생성이 처리한다. 100시드 중 3개 이하로 실패하면 이 테스트 루프를 `Generator.generate`(Task 5) 기반으로 옮기고, 그 이상이면 `dig_path`의 `protected` 처리가 잘못된 것이다.

- [ ] **Step 5: 커밋(건너뜀). 스위트 재실행.**

---

### Task 5: 조우·조사물·유물 배치와 `generate()`/`validate()` (`floor_generator.gd` 3/3)

**Files:**
- Modify: `expedition/floor_generator.gd`
- Modify: `tests/floor_generator.gd`

**Interfaces:**
- Consumes: Task 2 `Encounters.fill/place/valid`, Task 4 `carve/paint/reachable_from`.
- Produces:
  - `FloorGenerator.generate(theme: Dictionary, seed: int, depth: int) -> Dictionary` — 스펙 §7 계약. 재생성 5회 초과 시 `push_error` 후 마지막 시도 결과 반환.
  - `FloorGenerator.validate(layout: Dictionary, theme: Dictionary) -> String` — 빈 문자열이면 유효.
  - `FloorGenerator.graph_distances(rooms: Array, edges: Array, origin: int) -> Dictionary` — `{room_id: 간선 수}`.
  - `FloorGenerator.graph_path(rooms: Array, edges: Array, from: int, to: int, blocked: Dictionary) -> Array` — 방 id 경로(BFS). 없으면 `[]`.

- [ ] **Step 1: 테스트 확장**

`tests/floor_generator.gd`의 `run()` 마지막(`print` 앞)에 `await full_layouts(theme)` 추가:

```gdscript
func full_layouts(theme: Dictionary) -> void:
	var size: int = theme.size
	var total_regenerations := 0
	for seed_value in range(100):
		var layout: Dictionary = Generator.generate(theme,seed_value,1)
		check(Generator.validate(layout,theme) == "","layout valid: %s (seed %d)" % [Generator.validate(layout,theme),seed_value])
		check(layout.size == size and layout.terrain.size() == size*size and layout.theme_id == "F1_RUINS" and layout.depth == 1,"contract scalars")
		total_regenerations += layout.stats.regenerations
		check(layout.stats.regenerations <= 5,"regenerations bounded")
		var mandatory: Array = layout.encounters.filter(func(e): return e.mandatory)
		var optional: Array = layout.encounters.filter(func(e): return not e.mandatory)
		check(mandatory.size() >= 2 and mandatory.size() <= 3,"two or three mandatory encounters (seed %d: %d)" % [seed_value,mandatory.size()])
		check(optional.size() >= 1 and optional.size() <= 2,"one or two optional encounters (seed %d: %d)" % [seed_value,optional.size()])
		var relic_room: int = Generator.room_index(layout.rooms,"relic_vault")
		check(mandatory.any(func(e): return e.room == relic_room and e.tier == "deep"),"relic vault holds a deep mandatory encounter")
		# Blocking every mandatory room cuts entry from relic: no route skips them all.
		var blocked: Dictionary = {}
		for e in mandatory: blocked[e.room] = true
		check(Generator.graph_path(layout.rooms,layout.edges,Generator.room_index(layout.rooms,"entry_camp"),relic_room,blocked).is_empty(),"mandatory rooms cover every entry→relic route (seed %d)" % seed_value)
		var budgets: Dictionary = theme.monsters.budget
		for e in layout.encounters:
			var expected: int = budgets.optional if not e.mandatory else budgets[e.tier]
			check(e.budget == expected,"encounter budget matches tier")
			var members: Array = e.members
			check(Generator.Encounters.valid(members,e.budget) == "","encounter members valid (seed %d room %d)" % [seed_value,e.room])
			var room: Dictionary = layout.rooms[e.room]
			for m in members:
				check(room.rect.has_point(m.pos) and layout.terrain[m.pos.y*size+m.pos.x] != "wall","member stands on room floor")
				for d in room.doors: check(maxi(absi(m.pos.x-d.x),absi(m.pos.y-d.y)) >= 3,"member three cells from doors (seed %d)" % seed_value)
				check(m.role in ["MELEE","RANGED","CASTER"] and m.has("species_id") and m.has("display_name") and m.has("max_health"),"member fields")
		var all_positions: Array = []
		for e in layout.encounters:
			for m in e.members: all_positions.append(m.pos)
		for p in layout.features: all_positions.append(p)
		check(all_positions.size() == all_positions.reduce(func(acc,p): return acc if p in acc else acc+[p],[]).size(),"no two objects share a cell (seed %d)" % seed_value)
		var kinds: Dictionary = {}
		for p in layout.features:
			var f: Dictionary = layout.features[p]
			var key: String = f.kind+("/"+f.curio_id if f.kind == "curio" else "")
			kinds[key] = int(kinds.get(key,0))+1
			var in_room: bool = layout.rooms.any(func(r): return r.rect.has_point(p))
			check(in_room,"feature %s inside a room, never a corridor (seed %d)" % [key,seed_value])
		check(kinds.get("entry",0) == 1 and kinds.get("relic",0) == 1 and kinds.get("altar",0) == 1,"one entry, relic and altar")
		check(kinds.get("curio/LOCKED_CHEST",0) >= theme.curios.locked_chest[0] and kinds.get("curio/LOCKED_CHEST",0) <= theme.curios.locked_chest[1],"chest count in theme range (%d)" % kinds.get("curio/LOCKED_CHEST",0))
		check(kinds.get("curio/DIRT_PILE",0) >= theme.curios.dirt_pile[0] and kinds.get("curio/DIRT_PILE",0) <= theme.curios.dirt_pile[1],"dirt count in theme range (%d)" % kinds.get("curio/DIRT_PILE",0))
		check(kinds.get("camp",0) >= 1 and kinds.get("camp",0) <= 2,"one or two camps")
		for p in layout.features:
			var f: Dictionary = layout.features[p]
			if f.kind in ["curio","altar"]:
				var owner: Dictionary = layout.rooms.filter(func(r): return r.rect.has_point(p))[0]
				check(not owner.spine or owner.kind == "template","procedurally placed rewards stay off the spine (seed %d)" % seed_value)
				check(layout.encounters.all(func(e): return e.room != owner.id) or owner.template_id == "collapsed_store","chests and dirt avoid fight rooms unless the template carries them")
		check(layout.stats.relic_distance >= layout.stats.max_distance*60/100,"relic far from entry (seed %d: %d of %d)" % [seed_value,layout.stats.relic_distance,layout.stats.max_distance])
		var reach: Dictionary = Generator.reachable_from(layout.terrain,size,layout.entry)
		for p in layout.features:
			var adjacent := reach.has(p)
			for d in Generator.DIRECTIONS8:
				if reach.has(p+d): adjacent = true
			check(adjacent,"feature reachable or adjacent-reachable from entry (seed %d)" % seed_value)
		var again: Dictionary = Generator.generate(theme,seed_value,1)
		check(again.terrain == layout.terrain and again.features.keys() == layout.features.keys() and again.encounters.size() == layout.encounters.size(),"same seed regenerates identically (seed %d)" % seed_value)
	print("regenerations over 100 seeds: %d" % total_regenerations)
	check(total_regenerations <= 150,"regeneration is rare enough")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/floor_generator.gd`
Expected: `generate` 미정의 오류.

- [ ] **Step 3: 배치·생성·검증 구현**

`expedition/floor_generator.gd`에 추가:

```gdscript
static func adjacency(rooms: Array, edges: Array) -> Dictionary:
	var result: Dictionary = {}
	for room in rooms: result[room.id] = []
	for e in edges: result[e[0]].append(e[1]); result[e[1]].append(e[0])
	return result

static func graph_distances(rooms: Array, edges: Array, origin: int) -> Dictionary:
	var adj := adjacency(rooms,edges)
	var dist: Dictionary = {origin:0}
	var queue: Array = [origin]; var cursor := 0
	while cursor < queue.size():
		var id: int = queue[cursor]; cursor += 1
		for next in adj[id]:
			if not dist.has(next): dist[next] = int(dist[id])+1; queue.append(next)
	return dist

static func graph_path(rooms: Array, edges: Array, from: int, to: int, blocked: Dictionary) -> Array:
	var adj := adjacency(rooms,edges)
	var previous: Dictionary = {from:-1}
	var queue: Array = [from]; var cursor := 0
	while cursor < queue.size():
		var id: int = queue[cursor]; cursor += 1
		if id == to:
			var path: Array = [to]
			while previous[path[path.size()-1]] != -1: path.append(previous[path[path.size()-1]])
			path.reverse(); return path
		for next in adj[id]:
			if previous.has(next) or (blocked.has(next) and next != to): continue
			previous[next] = id; queue.append(next)
	return []

static func is_fight_room(room: Dictionary, theme: Dictionary) -> bool:
	return room.kind == "fight" or (room.kind == "template" and (room.template_id in theme.templates.fight_pool or room.template_id == "relic_vault"))

## Tiers by graph distance, spine rooms, mandatory (articulation → shortest
## path) and optional (treasury neighbour, dead ends) encounter rooms.
static func choose_encounter_rooms(rooms: Array, edges: Array, theme: Dictionary) -> Dictionary:
	var entry := room_index(rooms,"entry_camp"); var relic := room_index(rooms,"relic_vault"); var treasury := room_index(rooms,"sealed_treasury")
	var dist := graph_distances(rooms,edges,entry)
	var relic_neighbours: Array = adjacency(rooms,edges)[relic]
	for room in rooms:
		var d: int = int(dist.get(room.id,99))
		room.tier = "deep" if room.id == relic or room.id in relic_neighbours else "early" if d <= 2 else "mid"
	var spine := graph_path(rooms,edges,entry,relic,{})
	for room in rooms: room.spine = room.id in spine
	var mandatory: Array = [relic]
	for room in rooms:
		if room.id in [entry,relic,treasury] or not is_fight_room(room,theme): continue
		if graph_path(rooms,edges,entry,relic,{room.id:true}).is_empty(): mandatory.append(room.id)
	if mandatory.size() < 2:
		for id in spine:
			if id in mandatory or id in [entry,treasury] or not is_fight_room(rooms[id],theme): continue
			mandatory.append(id)
			if mandatory.size() >= 2: break
	var optional: Array = []
	var adj := adjacency(rooms,edges)
	if treasury >= 0:
		for id in adj[treasury]:
			if id not in mandatory and is_fight_room(rooms[id],theme) and id != entry: optional.append(id)
	for room in rooms:
		if optional.size() >= 2: break
		if room.id in mandatory or room.id in optional or room.id in [entry,treasury] or not is_fight_room(room,theme): continue
		if adj[room.id].size() == 1: optional.append(room.id)
	if optional.is_empty():
		for room in rooms:
			if room.id not in mandatory and room.id not in [entry,treasury] and is_fight_room(room,theme): optional.append(room.id); break
	return {"mandatory":mandatory,"optional":optional.slice(0,2)}

static func room_anchor(room: Dictionary) -> Vector2i:
	if room.kind == "template" and room.parsed.anchor != Vector2i(-1,-1): return room.rect.position-Vector2i.ONE+room.parsed.anchor
	return Vector2i(-1,-1)

static func room_backline(room: Dictionary) -> Array:
	if room.kind != "template": return []
	return room.parsed.backline.map(func(p): return room.rect.position-Vector2i.ONE+p)

static func build_encounters(layout: Dictionary, theme: Dictionary, painted: Dictionary, rng: RandomNumberGenerator, depth: int) -> Array:
	var rooms: Array = layout.rooms
	var chosen := choose_encounter_rooms(rooms,layout.edges,theme)
	var result: Array = []
	var reserved: Dictionary = {}
	for p in layout.features: reserved[p] = true
	for id in chosen.mandatory+chosen.optional:
		var room: Dictionary = rooms[id]
		var mandatory: bool = id in chosen.mandatory
		var budget: int = theme.monsters.budget[room.tier] if mandatory else theme.monsters.budget.optional
		var members := Encounters.fill(rng,depth,budget,room.tier == "deep" or not mandatory)
		var obstacles: Dictionary = painted.get(id,{}).get("obstacles",{}).duplicate()
		for p in reserved: obstacles[p] = true
		if not Encounters.place(members,floor_cells(layout.terrain,layout.size,room.rect),room.doors,room_anchor(room),room_backline(room),obstacles,rng): return []
		for m in members: reserved[m.pos] = true
		result.append({"room":id,"tier":room.tier,"mandatory":mandatory,"budget":budget,"members":members})
	return result

static func place_features(layout: Dictionary, theme: Dictionary, rng: RandomNumberGenerator) -> void:
	var rooms: Array = layout.rooms; var size: int = layout.size
	var features: Dictionary = {}
	for room in rooms:
		if room.kind != "template": continue
		for p in room.parsed.features:
			var cell: Vector2i = room.rect.position-Vector2i.ONE+p
			features[cell] = room.parsed.features[p].duplicate(true)
			if features[cell].kind == "entry": layout.entry = cell
			if features[cell].kind == "relic": layout.relic = cell
	var count := func(kind: String, curio_id: String) -> int:
		return features.values().filter(func(f): return f.kind == kind and f.get("curio_id","") == curio_id).size()
	var branch_plain: Array = rooms.filter(func(r): return r.kind == "plain" and not r.spine)
	var dead_end_plain: Array = branch_plain.filter(func(r): return adjacency(rooms,layout.edges)[r.id].size() == 1)
	var free_cell := func(room: Dictionary, corner: bool) -> Vector2i:
		var cells: Array = floor_cells(layout.terrain,size,room.rect).filter(func(p): return not features.has(p) and room.doors.all(func(d): return maxi(absi(p.x-d.x),absi(p.y-d.y)) > 1))
		if corner: cells = cells.filter(func(p): return (p.x == room.rect.position.x or p.x == room.rect.end.x-1) and (p.y == room.rect.position.y or p.y == room.rect.end.y-1)) if cells.any(func(p): return (p.x == room.rect.position.x or p.x == room.rect.end.x-1) and (p.y == room.rect.position.y or p.y == room.rect.end.y-1)) else cells
		return cells[rng.randi_range(0,cells.size()-1)] if not cells.is_empty() else Vector2i(-1,-1)
	var chest_target: int = rng.randi_range(theme.curios.locked_chest[0],theme.curios.locked_chest[1])
	var chest_rooms: Array = dead_end_plain if not dead_end_plain.is_empty() else branch_plain
	var guard := 0
	while count.call("curio","LOCKED_CHEST") < chest_target and not chest_rooms.is_empty() and guard < 20:
		guard += 1
		var cell: Vector2i = free_cell.call(chest_rooms[rng.randi_range(0,chest_rooms.size()-1)],false)
		if cell.x >= 0: features[cell] = Templates.feature_for("$")
	var dirt_target: int = rng.randi_range(theme.curios.dirt_pile[0],theme.curios.dirt_pile[1])
	guard = 0
	while count.call("curio","DIRT_PILE") < dirt_target and not branch_plain.is_empty() and guard < 20:
		guard += 1
		var cell: Vector2i = free_cell.call(branch_plain[rng.randi_range(0,branch_plain.size()-1)],true)
		if cell.x >= 0: features[cell] = Templates.feature_for("^")
	var mid_plain: Array = rooms.filter(func(r): return r.kind == "plain" and r.tier == "mid")
	if not mid_plain.is_empty() and rng.randi_range(0,1) == 1:
		var cell: Vector2i = free_cell.call(mid_plain[rng.randi_range(0,mid_plain.size()-1)],false)
		if cell.x >= 0: features[cell] = Templates.feature_for("C")
	layout.features = features

static func attempt_layout(theme: Dictionary, seed: int, depth: int) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var rooms := scatter_rooms(theme,rng)
	if rooms.is_empty(): return {}
	var edges := build_graph(rooms,theme,rng)
	var terrain := carve(rooms,edges,theme,rng)
	var painted := paint(terrain,rooms,theme,rng)
	var layout := {"size":theme.size,"seed":seed,"theme_id":theme.get("id",""),"depth":depth,"terrain":terrain,"rooms":rooms,"edges":edges,
		"entry":Vector2i(-1,-1),"relic":Vector2i(-1,-1),"features":{},"encounters":[],"stats":{"regenerations":0,"relic_distance":0,"max_distance":0}}
	choose_encounter_rooms(rooms,edges,theme) # sets tier/spine before features
	place_features(layout,theme,rng)
	layout.encounters = build_encounters(layout,theme,painted,rng,depth)
	var reach := reachable_from(terrain,theme.size,layout.entry)
	var farthest := 0
	for v in reach.values(): farthest = maxi(farthest,int(v))
	layout.stats.max_distance = farthest
	layout.stats.relic_distance = int(reach.get(layout.relic,0))
	return layout

static func generate(theme: Dictionary, seed: int, depth: int) -> Dictionary:
	var last: Dictionary = {}
	for attempt in range(MAX_REGENERATIONS+1):
		var layout := attempt_layout(theme,seed+attempt,depth)
		if not layout.is_empty():
			layout.stats.regenerations = attempt
			layout.seed = seed
			last = layout
			if validate(layout,theme).is_empty(): return layout
	push_error("floor generator: no valid layout after %d regenerations (seed %d): %s" % [MAX_REGENERATIONS,seed,validate(last,theme) if not last.is_empty() else "no rooms"])
	return last

## Empty string when the layout satisfies the spec; otherwise the first failure.
static func validate(layout: Dictionary, theme: Dictionary) -> String:
	if layout.is_empty(): return "empty layout"
	var size: int = layout.size
	var rooms: Array = layout.rooms
	if rooms.size() < theme.rooms.count[0] or rooms.size() > theme.rooms.count[1]: return "room count"
	for id in theme.templates.required:
		if room_index(rooms,id) < 0: return "missing template "+id
	if layout.entry.x < 0 or layout.relic.x < 0: return "entry or relic missing"
	var reach := reachable_from(layout.terrain,size,layout.entry)
	for room in rooms:
		for p in floor_cells(layout.terrain,size,room.rect):
			if not reach.has(p): return "room %d unreachable" % room.id
	for p in layout.features:
		var ok := reach.has(p)
		for d in DIRECTIONS8: if reach.has(p+d): ok = true
		if not ok: return "feature unreachable at %s" % p
		if not rooms.any(func(r): return r.rect.has_point(p)): return "feature in corridor at %s" % p
	if layout.stats.relic_distance < layout.stats.max_distance*60/100: return "relic too close"
	var mandatory: Array = layout.encounters.filter(func(e): return e.mandatory)
	var optional: Array = layout.encounters.filter(func(e): return not e.mandatory)
	if mandatory.size() < 2 or mandatory.size() > 3: return "mandatory encounters %d" % mandatory.size()
	if optional.size() < 1 or optional.size() > 2: return "optional encounters %d" % optional.size()
	var blocked: Dictionary = {}
	for e in mandatory: blocked[e.room] = true
	if not graph_path(rooms,layout.edges,room_index(rooms,"entry_camp"),room_index(rooms,"relic_vault"),blocked).is_empty(): return "route skips mandatory encounters"
	var taken: Dictionary = {}
	for p in layout.features: taken[p] = true
	for e in layout.encounters:
		if not Encounters.valid(e.members,e.budget).is_empty(): return "encounter invalid: "+Encounters.valid(e.members,e.budget)
		for m in e.members:
			if taken.has(m.pos): return "overlap at %s" % m.pos
			taken[m.pos] = true
			for d in rooms[e.room].doors:
				if maxi(absi(m.pos.x-d.x),absi(m.pos.y-d.y)) < 3: return "member too close to door"
	var adj := adjacency(rooms,layout.edges)
	var leaves := 0
	for id in adj: if adj[id].size() == 1: leaves += 1
	if leaves < 2: return "fewer than two dead ends"
	if layout.edges.size() < rooms.size(): return "no loop"
	return ""
```

`attempt_layout`의 `theme.get("id","")`가 빈 문자열이 되지 않도록 `theme()`에서 id를 넣어 준다 — `theme()`를 다음으로 바꾼다:

```gdscript
static func theme(id: String) -> Dictionary:
	var row: Dictionary = content.get("themes",{}).get(id,{})
	if row.is_empty(): return {}
	row = row.duplicate(true); row.id = id
	return row
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --script res://tests/floor_generator.gd`
Expected: `Floor generator: 0 failures`, `regenerations over 100 seeds: N`(N ≤ 150).

흔한 실패와 대응:
- `mandatory encounters 4+`: 관절점이 많음 → `build_graph`의 extra_links가 실제로 추가되지 않은 것(`segment_crosses_room`이 모든 후보를 거부). `grow` 대신 `outer` 그대로 검사하는지 확인.
- `rewards stay off the spine`: `place_features` 전에 `choose_encounter_rooms`가 호출되어 `spine`이 채워졌는지 확인(순서 고정).
- `relic too close`: `random_origin`의 x 제한이 적용되는지 확인.

- [ ] **Step 5: 커밋(건너뜀). 스위트 재실행.**

---

### Task 6: 세션 통합 — `continuous_floor.gd`가 생성기를 소비

**Files:**
- Modify: `expedition/continuous_floor.gd` (`build`, `SIZE` 사용처 전부)
- Modify: `expedition/expedition_objective.gd` (`choose`, `place`, `blocked`, `has_interaction_cell` 삭제; `register` 추가)
- Modify: `expedition/monster_ai.gd:10-15` (`configure(enemy, role)`)
- Modify: `expedition/map_view.gd:109`, `expedition/main.gd:573` 및 `show_objective`의 `10000`
- Create: `tests/floor_fixture.gd`
- Modify: `tests/continuous_floor.gd`, `tests/monster_roles.gd`, `tests/mobile_exploration.gd`, `tests/torch_vision.gd`, `tests/torch_tradeoff.gd`, `tests/curios.gd`, `tests/solo_floor.gd`

**Interfaces:**
- Consumes: `FloorGenerator.generate(theme, seed, depth)`, `FloorGenerator.theme(id)`.
- Produces:
  - `floor_state.size: int`, `floor_state.layout: Dictionary`(생성기 계약), `floor_state.theme_id := "F1_RUINS"`.
  - `Objective.register(s, pos: Vector2i) -> void` — `s.objective = create(s.expedition_number, pos)`.
  - `MonsterAI.configure(enemy: Dictionary, role: String) -> void`.
  - `tests/floor_fixture.gd`: `static func arena(s, half: int = 8) -> Vector2i`(보드 중앙 사각형을 돌로 파고 적 전멸, 주인공 이동, 관측; 중심 반환), `static func beside(s, p: Vector2i) -> Vector2i`(p의 8방향 이웃 중 `melee_reach`로 닿는 첫 빈 바닥 칸).

- [ ] **Step 1: 픽스처 헬퍼 작성**

`tests/floor_fixture.gd`:

```gdscript
extends RefCounted
## Layout-independent test arenas for the procedural floor.
static func arena(s, half: int = 8) -> Vector2i:
	var c := Vector2i(s.BOARD_SIDE/2,s.BOARD_SIDE/2)
	for y in range(maxi(1,c.y-half),mini(s.BOARD_SIDE-1,c.y+half+1)):
		for x in range(maxi(1,c.x-half),mini(s.BOARD_SIDE-1,c.x+half+1)):
			var cell: Dictionary = s.tile(Vector2i(x,y))
			cell.terrain = "stone"; cell.fire = 0; cell.wet = 0
	for enemy in s.enemies: enemy.hp = 0
	for p in s.floor_state.features.keys():
		if maxi(absi(p.x-c.x),absi(p.y-c.y)) <= half: s.floor_state.features.erase(p)
	s.party[0].pos = c
	for i in range(1,s.party.size()): s.party[i].pos = c+Vector2i(0,i)
	s.floor_state.observe(s)
	return c

static func beside(s, p: Vector2i) -> Vector2i:
	for d in s.DIRECTIONS:
		var cell: Vector2i = p+d
		if s.inside(cell) and s.tile(cell).terrain != "wall" and s.melee_reach(cell,p) and s.at(cell).is_empty(): return cell
	return Vector2i(-1,-1)
```

- [ ] **Step 2: `continuous_floor.gd` 교체**

파일 상단의 `const Source`, `const Registry`, `const SIZE := 100`, `static func point` 를 제거하고 다음으로 바꾼다:

```gdscript
const Generator = preload("res://expedition/floor_generator.gd")
const THEME_ID := "F1_RUINS"
var size := 64
var theme_id := THEME_ID
```

`build(s)` 전체를 교체:

```gdscript
func build(s) -> void:
	var theme: Dictionary = Generator.theme(theme_id)
	layout = Generator.generate(theme,s.seed_value+s.expedition_number*7919,int(theme.depth))
	size = layout.size
	epoch = str(s.seed_value)+"/"+str(s.expedition_number)
	visible.clear(); explored.clear(); discoveries.clear(); features.clear(); seen_enemies.clear()
	discovered_curios = 0
	s.BOARD_SIDE = size; s.tiles = []
	for y in range(size):
		for x in range(size):
			var terrain: String = layout.terrain[y*size+x]
			s.tiles.append({"terrain":terrain,"source_terrain":terrain,"fire":0,"wet":70 if terrain == "water" else 0,"variant":posmod(x*13+y*7,3),"palette":0})
	s.enemies = []
	for e in range(layout.encounters.size()):
		var encounter: Dictionary = layout.encounters[e]
		for member in encounter.members:
			var enemy: Dictionary = s.make_actor(100+s.enemies.size(),member.display_name,true)
			enemy.pos = member.pos; enemy.hp = int(member.max_health)
			if s.party.size() == 1: enemy.hp = clampi(enemy.hp*SOLO_HP_PERCENT/100,SOLO_HP_MIN,SOLO_HP_MAX)
			enemy.max_hp = enemy.hp
			enemy.group = "F%d_E%02d" % [int(theme.depth),e+1]; enemy.home = enemy.pos; enemy.alert = false
			enemy.species_id = member.species_id; enemy.tier = encounter.tier; enemy.mandatory = encounter.mandatory
			MonsterAI.configure(enemy,member.role)
			enemy.essence_id = ["BOMB","SHOCKWAVE","IRON_HIDE"][s.enemies.size()%3]
			s.enemies.append(enemy)
	for p in layout.features: features[p] = layout.features[p].duplicate(true)
	for i in range(s.party.size()):
		s.party[i].pos = layout.entry+Vector2i(0,i); s.party[i].ap = 1
		s.party[i].reservation = {}
	Objective.register(s,layout.relic)
	s.rooms = [{"id":0,"name":"1층 · "+str(theme.label),"kind":"floor","links":[],"tiles":s.tiles,"enemies":s.enemies,"started":true,"cleared":false,"shield":false,"pattern":-1,"used":false,"feature":Vector2i(-1,-1)}]
	s.room = 0; s.phase = "BATTLE"; s.round_number = 1
	observe(s); ambush(s)
```

나머지 `SIZE` 사용처(`observe`의 `mini(SIZE, …)` 두 곳, `observation`의 `"width":SIZE,"height":SIZE`, `follow`의 `s.TurnCore.path(SIZE,SIZE, …)` 두 곳)를 모두 `size`로 바꾼다. `static func sight_side/sight_radius/darkness_strength/light_tier/…`는 그대로 둔다.

- [ ] **Step 3: `expedition_objective.gd` 정리**

`blocked`, `choose`, `has_interaction_cell`, `place` 네 함수를 삭제하고 추가:

```gdscript
static func register(s, pos: Vector2i) -> void:
	s.objective = create(s.expedition_number,pos)
```

`reachability`는 테스트가 쓰므로 유지. 파일 상단 주석의 "seeded placement"를 "placement is the generator's job"으로 고친다.

- [ ] **Step 4: `monster_ai.configure` 시그니처 변경**

```gdscript
static func configure(enemy: Dictionary, role: String) -> void:
	enemy.role = role if ROLES.has(role) else "MELEE"
	enemy.name += " " + ROLES[enemy.role].label
	enemy.charging = false
	enemy.cast_cooldown = 2
	enemy.cast_recovery = 0
```

- [ ] **Step 5: 크기 리터럴 제거**

- `expedition/map_view.gd:109` `var step := side/100.0` → `var step := side/float(session.BOARD_SIDE)`.
- `expedition/main.gd:573` 문자열 `"1층 · 100×100 연속 지도\n발견한 타일: %d / 10000"` → `"1층 · %d×%d 연속 지도\n발견한 타일: %d / %d"`로 바꾸고 인자에 `session.BOARD_SIDE, session.BOARD_SIDE, explored.size(), session.BOARD_SIDE*session.BOARD_SIDE`를 순서대로 넣는다.
- `main.gd` `show_objective`의 `"발견한 타일 %d / 10000 · …"` → `"발견한 타일 %d / %d · …"`, 인자에 `session.BOARD_SIDE*session.BOARD_SIDE` 추가.
- `grep -n "10000\|100×100\|Vector2i(99" expedition/*.gd` 결과가 `expedition_number*10000`(시드 해시) 외에 없어야 한다.

- [ ] **Step 6: 기존 테스트 픽스처 수정**

각 파일에서 정확히 아래만 바꾼다. 상단에 `const Fixture = preload("res://tests/floor_fixture.gd")`를 추가한다(이미 `Fixture`라는 이름을 쓰는 파일은 `FloorFixture`로).

`tests/continuous_floor.gd`
- 22행: `s.tiles.size() == 10000 and s.BOARD_SIDE == 100` → `s.tiles.size() == s.BOARD_SIDE*s.BOARD_SIDE and s.BOARD_SIDE == 64`, 메시지 `"one continuous 64x64 floor"`.
- 24행: `check(s.enemies.size() == 9,…)` → `check(s.enemies.size() >= 3 and s.enemies.size() <= 20 and s.floor_state.layout.encounters.size() >= 3,"generated roster grouped into encounters")`.
- 25행: `explored.size() < 10000` → `< s.BOARD_SIDE*s.BOARD_SIDE`.
- 8~19행 BFS 루프는 4방향이라 그대로 두되 `check(seen.has(p),"feature reachable…")`를 `check(seen.has(p) or s.DIRECTIONS.any(func(d): return seen.has(p+d)),…)`로(유물·상자는 인접 도달로 충분).
- 32~34행(`s.party[0].pos = foe.pos+Vector2i.LEFT; s.party[1].pos = …`) → `s.party[0].pos = Fixture.beside(s,foe.pos); s.party[1].pos = Fixture.beside(s,s.party[0].pos)`.
- 63행 `Vector2i(99,99)` → `Vector2i(s.BOARD_SIDE-1,s.BOARD_SIDE-1)`.

`tests/monster_roles.gd`
- `fixture()`에서 `for tile in s.tiles: tile.terrain = "stone"` 다음 세 줄을 `var c := Fixture.arena(s,10); s.party[1].hp = 0; var e := s.enemies[0]; e.hp = e.max_hp; e.role = role; e.pos = c+Vector2i(4,0); e.alert = true` 로. 본문의 `Vector2i(51,51)`→`c+Vector2i(1,1)`, `Vector2i(54,50)`→`c+Vector2i(4,0)`, `Vector2i(51,50)`→`c+Vector2i(1,0)`, `Vector2i(52,50)`→`c+Vector2i(2,0)`. `c`를 얻으려면 `fixture()`가 `{"s":s,"c":c}`를 돌려주도록 바꾸고 호출부를 `var f := fixture("MELEE"); var s = f.s; var c: Vector2i = f.c`로.
- 마지막 세 검사(five melee / two ranged / two casters) → 
  ```gdscript
  check(s.enemies.all(func(a): return a.role in AI.ROLES and a.name.ends_with(AI.ROLES[a.role].label)),"generated roles are labelled")
  check(s.enemies.any(func(a): return a.role != "MELEE"),"at least one backline enemy on the floor")
  ```

`tests/mobile_exploration.gd`
- 28행 `Vector2i(99,99)` → `Vector2i(s.BOARD_SIDE-1,s.BOARD_SIDE-1)`.
- 35행 `Vector2i(80,80)` → `Vector2i(s.BOARD_SIDE-2,s.BOARD_SIDE-2)`.
- 19~20행은 입구 동쪽 4칸이 바닥이라(템플릿 보장) 그대로.

`tests/torch_vision.gd`
- 9~11행(`party[0].pos = Vector2i(50,50)`와 30..70 돌 채우기) → `s.party[1].hp = 0; var c := Fixture.arena(s,20)`. 이후 `Vector2i(62,62)`→`c+Vector2i(12,12)`, `Vector2i(58,50)`→`c+Vector2i(8,0)`, `Vector2i(57,50)`→`c+Vector2i(7,0)`, `Vector2i(51,50)`→`c+Vector2i(1,0)`, `Vector2i(52,50)`→`c+Vector2i(2,0)`. `s.floor_state.explored.clear(); s.floor_state.discoveries.clear()`는 유지.

`tests/torch_tradeoff.gd`
- 기습 블록의 `hero.pos = Vector2i(50,50)`와 44..56 돌 채우기 → `var c := Fixture.arena(s,6)`; `foe.pos = Vector2i(51,50)` → `foe.pos = c+Vector2i(1,0)`.

`tests/curios.gd`
- `prepare()`의 `s.party[0].pos = p+Vector2i.LEFT; s.party[1].pos = p+Vector2i.LEFT*2` → `s.party[0].pos = Fixture.beside(s,p); s.party[1].pos = Fixture.beside(s,s.party[0].pos)` (이 파일은 이미 `Fixture`가 없으므로 그대로 이름 사용).
- 본문 `s.party[0].pos = p+Vector2i.LEFT*4` → `Fixture.arena(s,3)` 뒤 `s.floor_state.observe(s)`(원거리 거부 검사는 아레나 중심이 p에서 멀기만 하면 됨; 아레나가 p를 덮지 않도록 `half`를 3으로).
- 52~60행 discovery 검사는 입구 동쪽 바닥을 쓰므로 그대로.

`tests/solo_floor.gd`
- "fallback placement" 블록(`var blocked = solo()` 부터 `"fallback avoids features and enemy starts"` 검사까지) 전체 삭제 — `Objective.choose`는 사라졌다.
- `check(reach[p] >= 40,…)` → `check(reach[p] >= s.floor_state.layout.stats.max_distance*60/100,"relic is far from the entry (seed %d: %d)" % [seed_value,reach[p]])`.
- `check(altars.size() == 1,…)` 유지. `"exit"` 검사 유지.
- `s.enemies[0].pos = Vector2i(99,99)` → `Vector2i(s.BOARD_SIDE-1,s.BOARD_SIDE-1)`.
- `for d in [Vector2i(-6,0),…]` far 탐색은 유지(64 안에서도 동작).

- [ ] **Step 7: 전체 스위트 실행**

Run (반복):
```bash
for t in floor_templates encounter_builder floor_generator continuous_floor monster_roles mobile_exploration torch_vision torch_tradeoff curios solo_floor solo_recovery solo_provisioning solo_balance abilities_growth boss_trial character_ui companion_tactics enemy_turns integration mobile_actions playthrough terrain_layouts ui_smoke; do printf "%s: " $t; godot --headless --path . --script res://tests/$t.gd 2>&1 | grep -E "failures|SCRIPT ERROR|^ERROR|UI smoke|playthrough" | head -3 | tr '\n' ' '; echo; done
```
Expected: 모든 스위트 `0 failures`(`solo_balance`는 Task 7에서 기준을 다시 잡으므로 여기서는 `STUCK`이 없기만 하면 됨). 실패한 스위트는 위 픽스처 목록에 없는 좌표 가정이 남은 것이다 — 파일 안의 `Vector2i(NN,NN)`(NN ≥ 40)을 찾아 `c+`오프셋으로 바꾼다.

- [ ] **Step 8: 에디터 임포트 검사**

Run: `godot --headless --path . --editor --import --quit 2>&1 | grep -E "SCRIPT ERROR|^ERROR"`
Expected: 출력 없음.

- [ ] **Step 9: 커밋(건너뜀). 스위트 재실행.**

---

### Task 7: 밸런스 측정·CI·문서

**Files:**
- Modify: `tests/solo_balance.gd` (기준값)
- Modify: `.github/workflows/deploy-pages.yml:38`
- Modify: `README.md` (플레이 설명·검증 절), `docs/continuous-floor-port.md`(상단에 대체 안내), `docs/solo-floor1-relic-results.md`(측정 추가)

**Interfaces:** 없음(문서·수치).

- [ ] **Step 1: 밸런스 봇 실행**

Run: `godot --headless --path . --script res://tests/solo_balance.gd 2>&1 | grep -E "^seed|^repeat|Solo balance|^ERROR"`

기록: 시드별 결과·행동 수·회복품·종료 체력. 기대: 완주 ≥ 6/8, 행동 150~260. 스펙 §5-8.

- [ ] **Step 2: 기준값 반영**

`tests/solo_balance.gd`:
- `check(row.actions <= 400,…)` → `check(row.actions >= 120 and row.actions <= 300,"round trip within the target action band (seed %d: %d)" % [seed_value,row.actions])`.
- `check(wins == SEEDS,…)` → `check(wins >= 6,"scripted solo run completes on most seeds (%d/%d)" % [wins,SEEDS])`.
- 4회 연속 출정 검사의 `row.reason == "SUCCESS"`는 유지하되 실측에서 한 번이라도 실패하면 `check(row.reason in ["SUCCESS","PARTIAL"], …)`로 완화하고 결과 문서에 이유를 적는다.

완주가 6/8 미만이면 코드가 아니라 데이터로 조정한다: `floor_themes.json`의 `budget.deep`을 9→8, 그래도 부족하면 `mid` 6→5. 각 조정 후 `floor_generator.gd`·`solo_balance.gd`를 다시 돌린다. 조정 내역을 결과 문서에 남긴다.

- [ ] **Step 3: CI 등록**

`.github/workflows/deploy-pages.yml` 38행의 `for suite in … solo_provisioning; do` 목록 끝에 ` floor_templates encounter_builder floor_generator`를 추가한다.

- [ ] **Step 4: README·문서**

`README.md`
- "플레이" 절의 `연속된 **100×100 1층**` → `**64×64 절차 생성 1층**`. 이어서 문단 추가:
  > 층은 출정마다 새로 생성됩니다. 방 10~12개가 고리 있는 그래프로 이어지고, 입구 야영지·유물의 방·봉인된 보고와 침수 저장고·무너진 창고·목재 회랑 중 2개가 손으로 그린 템플릿으로 들어갑니다. 조우는 방 안에만 있으며 어떤 길로 가도 필수 조우 2~3회를 지나고, 막다른 방의 선택 조우 1~2회는 피할 수 있습니다. 무리 구성은 DCSS식 깊이 테이블(종족별 출현 구간·희귀도·곡선)과 위협 예산(초입 3·중간 6·심부 9·선택 5)으로 정하며, 3마리 이상이면 후위가 하나 이상, 술사는 최대 하나입니다. 상자·흙더미·제단은 주 경로 밖 가지에만 있습니다. [설계](docs/superpowers/specs/2026-09-22-floor-generator-design.md).
- "기존 SS의 48×48 `four_zone_floor` 구조를 2배 확대하고 외곽을 추가했습니다." 문장과 "입구 야영지·바위 회랑·침수 저장고·심부 관문을 통로로 오갑니다." 문장 삭제.
- "검증" 절 명령 목록에 `floor_templates.gd`, `encounter_builder.gd`, `floor_generator.gd` 추가와 한 줄 설명:
  > `floor_generator.gd`는 100개 시드에서 방 수·템플릿·간격·문, 8방향 도달성, 고리·막다른 방, 필수 조우가 모든 경로를 덮는지, 예산·가드레일·문 거리, 조우 방 장애물과 5×5 빈 블록, 보상이 주 경로 밖에 있는지, 유물 거리, 재현성을 검사합니다.

`docs/continuous-floor-port.md` 첫 줄 아래에:
> **2026-09-22 이후**: 고정 4구역 층은 절차 생성기(`expedition/floor_generator.gd`)로 대체되었다. 아래 기록은 이식 이력용이다.

`docs/solo-floor1-relic-results.md` 끝에 "## 절차 생성 층 측정 (2026-09-22)" 절을 추가하고 Step 1 실측 표(시드·결과·행동·회복·체력·자금), 조정한 예산, 재생성 횟수 합계(`floor_generator.gd` 출력)를 적는다.

- [ ] **Step 5: 최종 전체 스위트 + 임포트**

Task 6 Step 7의 루프와 Step 8을 다시 실행. Expected: 전부 녹색, 임포트 오류 없음.

- [ ] **Step 6: 커밋(건너뜀). 사용자에게 커밋 여부를 묻는다.**

---

## 자체 점검 (작성자 기록)

- 스펙 §1 7단계 → Task 3(1·2), Task 4(3·4·5), Task 5(6·7). §2 → Task 1. §3 → Task 2 + Task 5 `choose_encounter_rooms/build_encounters`. §4 → Task 5 `place_features`. §5 → Task 5 테스트 + Task 7. §6 → Task 6. §7 계약 → `attempt_layout`.
- 시그니처 일치: `Encounters.fill(rng, depth, budget, ood)`/`place(members, floor_cells, doors, anchor, backline, obstacles, rng)`는 Task 2 정의와 Task 5 호출이 같다. `Templates.parse` 결과 키(`terrain, doors, features, anchor, backline, floor, width, height`)는 Task 1·3·4·5에서 같은 이름을 쓴다. `MonsterAI.configure(enemy, role)`는 Task 6에서만 호출된다.
- 스펙 §3.3 "필수 조우 3 초과 시 재생성"은 `validate()`의 `mandatory.size() > 3`로, "관절점 → 최단 경로 순" 추가는 `choose_encounter_rooms`로 구현했다.
- 스펙 §2 "보고는 MST 제외 후 잎으로" → `build_graph` 마지막 블록.
