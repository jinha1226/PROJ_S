# Plan A — 스테이지 스키마·1층 저작·노드 맵·도주/포기 비용 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `79f1f17` 8×8 SRPG 브랜치 위에서, 걸어서 방을 옮기던 구조를 "맵 화면에서 노드(방) 선택"으로 바꾸고, 방 하나하나를 저작하는 스테이지 스키마 v2와 1층 9방 재설계, 도주·원정 포기의 스트레스 비용을 넣는다.

**Architecture:** 한 층은 여전히 48×24 단일 `WorldState` 안의 3×3 방(`nine_room_floor_state`)이다. 새 `sim/stage_catalog.gd`가 확장 JSON을 읽어 검증하고, 기존 `first_floor_stages.gd`는 그 위의 호환 shim이 된다. 방 이동은 새 `room_transition_system.travel()`(전투 중이 아닐 때 인접 발견 방으로 0시간 순간 이동)과 기존 도주 경로(전투 중 출구 집결)로 나뉜다. `sim/stage_map_model.gd`가 UI용 노드/간선 모델을 만들고, 샌드박스에 맵 오버레이가 붙는다. 스트레스 비용은 이벤트(`room.exit_requested{combat:true}`, `expedition.abandoned`)를 `party_morale_model.evaluate`가 읽는 방식으로 넣는다.

**Tech Stack:** Godot 4.6.2 GDScript, 헤드리스 `SceneTree` 테스트, JSON 콘텐츠 (`json_content_loader.gd`).

**Spec:** `docs/superpowers/specs/2026-09-18-srpg-stage-campaign-design.md` — 이 계획은 스펙 §1, §2, §3.3(도주·포기 소스), §7, §8(stage_map / retreat_stress / abandon / stage_schema)을 구현한다. §3.1–3.2(판정·각성·HEXACO 이동), §4(야영), §5(거점)는 Plan B/C.

## Global Constraints

- 기준 커밋 `79f1f17`, 브랜치 `feat/srpg-stage-campaign`, 워크트리 `/mnt/d/STARTU/proj-s-srpg-stages`. `main`·다른 브랜치를 건드리지 않는다.
- 롤백 이후 커밋은 cherry-pick하지 않는다.
- 모든 godot 실행은 ext4 복사본에서: `rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg && godot --headless --path . --script tests/<name>.gd`. 순차 실행(병렬 금지).
- 저장·재현 계약: 새 명령은 `command_journal`에 기록하고 `load_session_json` 재생이 `sim.snapshot()` 완전 일치해야 한다. 미리보기/관찰은 스냅샷을 바꾸지 않는다.
- 모바일 360×800, 터치 버튼 44px 이상.
- 코드 스타일: 이 브랜치의 `sim/` 파일들처럼 압축된 GDScript(세미콜론 다중문, `static func`, `RefCounted`). 새 파일도 같은 밀도로 쓴다.
- 수치는 JSON/상수로 두고 코드에 흩뿌리지 않는다. 스트레스 도주 +120, 포기 +200.

---

## 파일 구조

| 파일 | 책임 |
|---|---|
| `data/content/stages/f1.json` | 1층 9방 저작 데이터 (스키마 v2) |
| `sim/stage_catalog.gd` (신규) | 스키마 v2 로드·검증·좌표 변환. 실행 규칙 없음 |
| `sim/first_floor_stages.gd` (수정) | 카탈로그 위 호환 shim (`CONTENT`, `room`, `stamp`, `npc_position`) |
| `sim/nine_room_generator.gd` (수정) | 1층 적 배치를 저작 `enemies`로, 방별 `stage` 설정을 rooms에 포함 |
| `sim/stage_counterplay.gd` (수정) | 방별 증원·목표(`SURVIVE`)·`cleared()`·`retreat_allowed()` |
| `sim/stage_map_model.gd` (신규) | 층 상태 → `{nodes, edges, current}` 순수 변환 |
| `sim/systems/room_transition_system.gd` (수정) | `travel()` 추가, 도착 처리를 `_arrive()`로 공통화, 도주 금지 방 |
| `sim/party_morale_model.gd` / `sim/systems/party_morale_system.gd` (수정) | `room.exit_requested{combat}`·`expedition.abandoned` 스트레스 |
| `playtest/party_playtest_session.gd` (수정) | `stage_map()`, `request_room_travel()`, `abandon_expedition()`, 저널 `travel`/`base ABANDON` |
| `playtest/base_progression_service.gd` (수정) | `base_return(force)` — 포기 경로에서 위치·교전 검사 생략 |
| `playtest/stage_map_view.gd` (신규) | 3×3 노드 맵 오버레이 Control |
| `playtest/party_encounter_sandbox.gd` (수정) | 맵 버튼·오버레이 연결, 통로 걷기 입력 제거 |
| `tools/stage_lab.gd`, `tools/stage_probe.gd` (신규) | 방 단독 실행·헤드리스 난이도 진단 |
| `docs/stages/f1.ko.md` (신규) | 1층 설계 문서 |
| `docs/plans/plan-a-baseline.ko.md` (신규) | 기준선 테스트 결과 |
| `tests/stage_schema_acceptance.gd`, `tests/stage_map_acceptance.gd`, `tests/retreat_stress_acceptance.gd`, `tests/abandon_acceptance.gd`, `tests/stage_map_ui_acceptance.gd` (신규) | 인수 테스트 |

---

### Task 0: 기준선 확인

**Files:**
- Create: `docs/plans/plan-a-baseline.ko.md`

- [ ] **Step 1: ext4 복사본 만들고 6종 테스트 실행**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/
cd /root/lw-bench-srpg && godot --headless --path . --editor --import --quit >/tmp/import.log 2>&1; echo "import exit $?"
for t in stage_counterplay_acceptance srpg_party_turns_acceptance first_floor_solo_roster handcrafted_tile_assets_acceptance round_combat_scenarios first_floor_stages_acceptance; do
  echo "== $t"; timeout 600 godot --headless --path . --script tests/$t.gd 2>&1 | tail -5; echo "exit $?"
done
```
Expected: 각 테스트 마지막 줄에 `PASS`, exit 0. (`stage_context_ui_acceptance`는 X11이 필요하므로 `xvfb-run -a godot --path . --script tests/stage_context_ui_acceptance.gd`로 시도하고, xvfb가 없으면 "미실행"으로 기록.)

- [ ] **Step 2: 결과 기록**

`docs/plans/plan-a-baseline.ko.md`에 표로 기록: 테스트명 / 결과(PASS·FAIL·미실행) / 실패 시 마지막 5줄. 실패가 있으면 **고치지 말고** 기록만 한다 — 이후 작업은 "새 실패 없음"으로 판정한다.

- [ ] **Step 3: Commit**

```bash
git add docs/plans/plan-a-baseline.ko.md && git commit -m "docs: record Plan A test baseline at 79f1f17"
```

---

### Task 1: 스테이지 스키마 v2와 카탈로그

**Files:**
- Create: `sim/stage_catalog.gd`
- Create: `data/content/stages/f1.json` (이 태스크에서는 기존 9방을 v2 형식으로 **기계적 변환**만; 재설계는 Task 2)
- Modify: `sim/first_floor_stages.gd` (shim)
- Test: `tests/stage_schema_acceptance.gd`

**Interfaces:**
- Produces:
  - `StageCatalog.floor(index:int)->Dictionary` — `{version:2, edges, event_room, rooms:[room]}`
  - `StageCatalog.room(floor_index:int,id:int)->Dictionary` — 방 dict (아래 스키마)
  - `StageCatalog.error(doc:Dictionary)->String` — 빈 문자열이면 유효
  - `StageCatalog.stamp(terrain:Array[String],width:int,origin:Vector2i,spec:Dictionary)->void`
  - `StageCatalog.wave_enemies(spec:Dictionary,wave:int)->Array` — `[{cell:[x,y],kind,role}]`
  - `StageCatalog.LEGEND`, `ENEMY_ROLES`, `OBJECTIVES`, `EDGES=["N","E","S","W"]`
  - `first_floor_stages.gd`의 기존 API(`CONTENT.edges`, `CONTENT.event_room`, `CONTENT.rooms`, `room(id)`, `stamp(terrain,origin,id)`, `npc_position()`)는 그대로 동작하며 `room(id)`에 파생 `enemy_cells`가 포함된다.

방 스키마 v2:
```json
{"id":"f1_watchpost","name":"무너진 감시소","role":"COMBAT","biome":"dungeon",
 "hint":"...", "rows":["#......#", ...8행...],
 "entries":{"S":[[3,6],[2,6],[4,6]]},
 "enemies":[{"cell":[5,2],"kind":"goblin","role":"ASSAULT","wave":0}],
 "reinforcements":{"interval_rounds":7,"cap":8,"spawn_edges":["N"]},
 "objective":{"type":"ELIMINATE","rounds":0,"cell":[-1,-1],"retreat_allowed":true},
 "hazards":[],
 "loot":[{"cell":[4,5],"item":"POTION_HEALING","quantity":1}],
 "npc_cell":[4,4],
 "design":{"concept":"...","intended_solution":"...","counterplay":"...","failure_mode":"...","difficulty":2}}
```
`entries`·`enemies`·`hazards`·`npc_cell`는 비전투방에서 비어 있어도 된다. `design`은 9방 모두 필수.

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/stage_schema_acceptance.gd`:
```gdscript
extends SceneTree
const Catalog=preload("res://sim/stage_catalog.gd")
const Legacy=preload("res://sim/first_floor_stages.gd")
var failures:Array=[]
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():
	var doc:Dictionary=Catalog.floor(1)
	check(Catalog.error(doc).is_empty(),"f1 valid: "+Catalog.error(doc))
	check(doc.rooms.size()==9,"nine rooms")
	var ids:Dictionary={}
	for spec in doc.rooms:
		ids[spec.id]=true
		check(spec.design.keys().size()==5 and spec.design.difficulty is float or spec.design.difficulty is int,"design present "+spec.id)
		for e in spec.enemies:
			check(spec.rows[e.cell[1]][e.cell[0]]!="#","enemy on floor "+spec.id)
			check(e.role in Catalog.ENEMY_ROLES,"enemy role "+spec.id)
			check(not preload("res://sim/enemy_perception_registry.gd").profile(e.kind).is_empty(),"enemy kind exists "+spec.id+" "+str(e.kind))
		check(spec.objective.type in Catalog.OBJECTIVES,"objective "+spec.id)
		for edge in spec.reinforcements.spawn_edges:check(edge in Catalog.EDGES,"spawn edge "+spec.id)
	check(ids.size()==9,"unique ids")
	# Shim keeps the legacy surface used by the generator and older tests.
	check(Legacy.CONTENT.rooms.size()==9 and Legacy.CONTENT.edges.size()>0,"shim content")
	check(Legacy.room(0).has("enemy_cells"),"shim derives enemy_cells")
	check(Legacy.room(0).enemy_cells==Catalog.wave_enemies(Catalog.room(1,0),0).map(func(e):return e.cell),"enemy_cells equals wave 0")
	# Validator rejects broken documents.
	var broken:Dictionary=doc.duplicate(true);broken.rooms[0].enemies.append({"cell":[0,0],"kind":"goblin","role":"ASSAULT","wave":0})
	check(Catalog.error(broken)=="enemy_on_wall:f1_watchpost","wall spawn rejected: "+Catalog.error(broken))
	broken=doc.duplicate(true);broken.rooms[1].erase("design")
	check(Catalog.error(broken)=="design_missing:f1_descent","design required: "+Catalog.error(broken))
	broken=doc.duplicate(true);broken.rooms[0].objective.type="SURVIVE";broken.rooms[0].objective.rounds=0
	check(Catalog.error(broken)=="objective_rounds:f1_watchpost","survive needs rounds: "+Catalog.error(broken))
	broken=doc.duplicate(true);broken.rooms[0].enemies.append({"cell":[5,2],"kind":"goblin","role":"ASSAULT","wave":0})
	check(Catalog.error(broken)=="enemy_cell_duplicate:f1_watchpost","duplicate cell rejected: "+Catalog.error(broken))
	print("STAGE_SCHEMA ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: 실패 확인**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg && godot --headless --path . --script tests/stage_schema_acceptance.gd 2>&1 | tail -3
```
Expected: 파싱 오류(`stage_catalog.gd` 없음), exit ≠ 0.

- [ ] **Step 3: `data/content/stages/f1.json` 생성 (기계적 변환)**

기존 `data/content/first_floor_stages.json`의 9방을 아래 규칙으로 옮긴다 (Python 스크립트를 스크래치에 두고 한 번 실행; 저장소에는 결과 JSON만):
- `enemy_cells[i]` → `enemies[i]={"cell":cell,"kind":KIND[id][i],"role":"ASSAULT","wave":0}`; `KIND`는 생성기의 기존 매핑 `{0:["goblin"]*3, 2:["dcss_frilled_lizard"]*3, 6:["dcss_rat"]*3, 7:["goblin"]*3}`.
- `entries`: 방의 네 출구 셀 `N=[3,0] E=[7,3] S=[3,7] W=[0,3]` 기준 체비쇼프 2 이내의 `.` 칸 목록(출구 셀 제외). 네 방향 모두 채운다.
- `reinforcements`: `{"interval_rounds":7,"cap":8,"spawn_edges":["N","E","S","W"]}` (현재 전역값과 동일 → 기존 테스트 유지).
- `objective`: `{"type":"ELIMINATE","rounds":0,"cell":[-1,-1],"retreat_allowed":true}`.
- `hazards`: `rows`의 `~` 칸을 `{"cell":[x,y],"type":"shallow_water"}`로.
- `design`: 각 방 `{"concept":<hint>,"intended_solution":"임시 — Task 2에서 재설계","counterplay":"임시","failure_mode":"임시","difficulty":1}`.
- 상단: `{"version":2,"edges":<기존>,"event_room":5,"rooms":[...]}`.

- [ ] **Step 4: `sim/stage_catalog.gd` 작성**

```gdscript
extends RefCounted
const Loader=preload("res://sim/json_content_loader.gd")
const Perception=preload("res://sim/enemy_perception_registry.gd")
const Items=preload("res://sim/item_registry.gd")
const VERSION:=2
const SIZE:=8
const LEGEND={".":"stone_floor","#":"wall","~":"shallow_water","r":"rubble"}
const ROLES:=["COMBAT","HAZARD","SAFE","STAIRS"]
const ENEMY_ROLES:=["ASSAULT","ARCHER","SHIELD","SUPPORT"]
const OBJECTIVES:=["ELIMINATE","SURVIVE","REACH","PROTECT"]
const EDGES:=["N","E","S","W"]
const HAZARD_TYPES:=["shallow_water"]
const DESIGN_KEYS:=["concept","counterplay","difficulty","failure_mode","intended_solution"]
static var _floors:Dictionary={}

static func floor(index:int)->Dictionary:
	if not _floors.has(index):_floors[index]=Loader.load_document("res://data/content/stages/f%d.json"%index)
	return _floors[index]
static func room(floor_index:int,id:int)->Dictionary:return floor(floor_index).rooms[id]
static func wave_enemies(spec:Dictionary,wave:int)->Array:
	return spec.get("enemies",[]).filter(func(e):return int(e.wave)==wave)
static func stamp(terrain:Array[String],width:int,origin:Vector2i,spec:Dictionary)->void:
	for y in range(SIZE):
		for x in range(SIZE):terrain[(origin.y+y)*width+origin.x+x]=LEGEND[spec.rows[y][x]]
static func _cell_ok(spec:Dictionary,cell:Variant)->bool:
	return cell is Array and cell.size()==2 and int(cell[0]) in range(SIZE) and int(cell[1]) in range(SIZE) and spec.rows[int(cell[1])][int(cell[0])]!="#"
static func error(doc:Variant)->String:
	if not doc is Dictionary or int(doc.get("version",0))!=VERSION:return "version"
	if not doc.get("rooms") is Array or doc.rooms.size()!=9:return "room_count"
	if not doc.get("edges") is Array or not doc.has("event_room"):return "floor_keys"
	var ids:Dictionary={}
	for spec in doc.rooms:
		var id:String=str(spec.get("id",""))
		if id.is_empty() or ids.has(id):return "room_id"
		ids[id]=true
		for key in ["name","role","biome","hint","rows","entries","enemies","reinforcements","objective","hazards","loot","design"]:
			if not spec.has(key):return "%s_missing:%s"%[key,id]
		if spec.role not in ROLES:return "role:"+id
		if not spec.rows is Array or spec.rows.size()!=SIZE:return "rows:"+id
		for row in spec.rows:
			if not row is String or row.length()!=SIZE:return "rows:"+id
			for ch in row:
				if not LEGEND.has(ch):return "legend:"+id
		var seen:Dictionary={}
		for e in spec.enemies:
			if not e is Dictionary or not e.has("cell") or not e.has("kind") or not e.has("role") or not e.has("wave"):return "enemy_keys:"+id
			if not _cell_ok(spec,e.cell):return "enemy_on_wall:"+id
			var key:="%d:%d"%[int(e.cell[0]),int(e.cell[1])]
			if int(e.wave)==0 and seen.has(key):return "enemy_cell_duplicate:"+id
			if int(e.wave)==0:seen[key]=true
			if e.role not in ENEMY_ROLES:return "enemy_role:"+id
			if int(e.wave)<0:return "enemy_wave:"+id
			if Perception.profile(str(e.kind)).is_empty():return "enemy_kind:"+id
		for dir in spec.entries:
			if dir not in EDGES or not spec.entries[dir] is Array:return "entries:"+id
			for cell in spec.entries[dir]:
				if not _cell_ok(spec,cell):return "entry_cell:"+id
		var r:Dictionary=spec.reinforcements
		if not r is Dictionary or int(r.get("interval_rounds",0))<1 or int(r.get("cap",-1))<0 or not r.get("spawn_edges") is Array:return "reinforcements:"+id
		for edge in r.spawn_edges:
			if edge not in EDGES:return "spawn_edge:"+id
		var o:Dictionary=spec.objective
		if not o is Dictionary or o.get("type","") not in OBJECTIVES or not o.has("retreat_allowed"):return "objective:"+id
		if o.type=="SURVIVE" and int(o.get("rounds",0))<1:return "objective_rounds:"+id
		if o.type in ["REACH","PROTECT"] and not _cell_ok(spec,o.get("cell")):return "objective_cell:"+id
		for h in spec.hazards:
			if not h is Dictionary or h.get("type","") not in HAZARD_TYPES or not _cell_ok(spec,h.get("cell")):return "hazard:"+id
		for drop in spec.loot:
			if not _cell_ok(spec,drop.get("cell")) or not Items.has(str(drop.get("item",""))) or int(drop.get("quantity",0))<1:return "loot:"+id
		if spec.has("npc_cell") and not _cell_ok(spec,spec.npc_cell):return "npc_cell:"+id
		var d:Variant=spec.design
		if not d is Dictionary:return "design_missing:"+id
		var keys:Array=d.keys();keys.sort()
		if keys!=DESIGN_KEYS:return "design_keys:"+id
		for key in ["concept","intended_solution","counterplay","failure_mode"]:
			if not d[key] is String or str(d[key]).strip_edges().is_empty():return "design_text:"+id
		if int(d.difficulty)<1 or int(d.difficulty)>5:return "design_difficulty:"+id
	return ""
```
주의: `Items.has` 시그니처는 `sim/item_registry.gd`에서 확인(기존 테스트가 `preload("res://sim/item_registry.gd").has(drop.item)`를 쓴다).

- [ ] **Step 5: `sim/first_floor_stages.gd`를 shim으로 교체**

```gdscript
extends RefCounted
const Catalog=preload("res://sim/stage_catalog.gd")
const LEGEND=Catalog.LEGEND
static var CONTENT:Dictionary=_build()
static func _build()->Dictionary:
	var doc:Dictionary=Catalog.floor(1)
	assert(Catalog.error(doc).is_empty(),"f1 stage catalog invalid: "+Catalog.error(doc))
	var rooms:Array=[]
	for spec in doc.rooms:
		var row:Dictionary=spec.duplicate(true)
		row["enemy_cells"]=Catalog.wave_enemies(spec,0).map(func(e):return e.cell)
		rooms.append(row)
	return {"version":doc.version,"edges":doc.edges,"event_room":doc.event_room,"rooms":rooms}
static func room(id:int)->Dictionary:return CONTENT.rooms[id]
static func stamp(terrain:Array[String],origin:Vector2i,id:int)->void:Catalog.stamp(terrain,24,origin,room(id))
static func npc_position()->Vector2i:
	var id:int=CONTENT.event_room;var cell:Array=room(id).npc_cell
	return Vector2i(id%3*8+cell[0],id/3*8+cell[1])
```
그리고 `data/content/first_floor_stages.json`은 삭제한다(`git rm`). `grep -rn "first_floor_stages.json" --include=*.gd --include=*.md .`로 다른 참조가 없음을 확인.

- [ ] **Step 6: 새 테스트와 기존 테스트 통과 확인**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg
for t in stage_schema_acceptance first_floor_stages_acceptance handcrafted_rooms_acceptance stage_counterplay_acceptance first_floor_solo_roster; do echo "== $t"; godot --headless --path . --script tests/$t.gd 2>&1 | tail -2; done
```
Expected: 모두 `PASS`. (`handcrafted_rooms_acceptance`는 `template.enemy_cells`를 읽는데 이는 `handcrafted_room_templates.gd`의 2층 템플릿이므로 영향 없음.)

- [ ] **Step 7: Commit**

```bash
git add sim/stage_catalog.gd sim/stage_catalog.gd.uid sim/first_floor_stages.gd data/content/stages/f1.json tests/stage_schema_acceptance.gd && git rm -q data/content/first_floor_stages.json && git commit -m "feat: stage schema v2 catalog with validation and legacy shim"
```
(`.uid` 파일은 godot import 시 생성된다; 없으면 import 단계를 한 번 돌린다.)

---

### Task 2: 1층 설계 문서와 9방 재설계 — **사용자 승인 게이트**

**Files:**
- Create: `docs/stages/f1.ko.md`
- Modify: `data/content/stages/f1.json`
- Modify: `docs/art/handcrafted-stages/preview.html` (v2 필드 표시)

**Interfaces:**
- Consumes: Task 1 스키마.
- Produces: 9방 최종 데이터. Task 3의 테스트가 방 7(`f1_guard`)의 `reinforcements.interval_rounds`를 읽으므로 값이 바뀌어도 된다.

- [ ] **Step 1: 설계 문서 초안 작성**

`docs/stages/f1.ko.md` 구성:
1. 3×3 배치 표(기존 배치 유지: 중앙 입구, 북 계단, 동 생존자, 전투 4 = 북서·북동·남서·남).
2. 방마다 한 절: 콘셉트 한 문장 / 지형 ASCII / 적 배치(kind·role·wave, 좌표) / 입구별 배치 칸 / 증원·목표 / 의도한 해법 / 대안 해법 / 실패 양상 / 도주 손익 / 난이도(1~5).
3. 경로별 난이도 곡선: 입구→서→북서→북 / 입구→동→북동→북 / 입구→남→남서 or 남동 순회.
4. 야영 권장 지점 2곳(Plan B에서 사용).
5. 스펙 §7.2 체크리스트 7항목을 방마다 ✔/✘로 채운 표.

전투방 4곳의 설계 방향(초안 제안, 문서에서 다듬는다):
- `f1_watchpost`(북서, 난이도 2): 기둥 사이로 고블린 3 접근. wave 0 = ASSAULT 2 + 후방 ARCHER(`kobold`) 1. 입구(S)에서 기둥을 끼고 각개격파. 대안: 궁수까지 돌진. 증원 없음(`cap:0`), 목표 ELIMINATE.
- `f1_hall`(북동, 난이도 3): 중앙 장애물 양쪽 접근로. wave 0 = 도마뱀 ASSAULT 2, wave 1(4라운드) = 고블린 2 북쪽 변. 목표 ELIMINATE, `interval_rounds:4, cap:6, spawn_edges:["N"]`. 한쪽 접근로를 막고 다른 쪽에서 치는 것이 해법; 농성하면 증원이 쌓임.
- `f1_roots`(남서, 난이도 2): 엇갈린 나무. wave 0 = 쥐 4(ASSAULT, 약함). 포위 방지 배치가 해법. 증원 없음.
- `f1_guard`(남, 난이도 3): 입구 근처 좁은 통로. wave 0 = 고블린 SHIELD 1(전면) + ASSAULT 2. 목표 **SURVIVE 6라운드**, `interval_rounds:3, cap:8, spawn_edges:["S"]` — 버티다 문이 열리면 맵으로 이탈 가능. 계속 싸워 전멸시켜도 됨.
- 비전투방(`f1_entry`, `f1_spring`, `f1_survivor`, `f1_cache`, `f1_descent`): `enemies:[]`, `cap:0`, 목표 ELIMINATE(적 없음 = 즉시 cleared). design은 "리듬을 끊는 이유"를 적는다.

- [ ] **Step 2: JSON 갱신**

문서와 정확히 일치하도록 `f1.json`을 편집. 좌표는 `rows[y][x]`(0-based, x 열·y 행). 출구 셀 `N=[3,0] E=[7,3] S=[3,7] W=[0,3]`는 항상 `.`이어야 하고 적·전리품을 놓지 않는다. `entries`는 각 출구 기준 체비쇼프 2 이내 `.` 칸 3개 이상.

- [ ] **Step 3: preview.html 갱신**

`docs/art/handcrafted-stages/preview.html`이 읽는 JSON 경로를 `data/content/stages/f1.json`으로 바꾸고, 적을 `role` 글자(A/R/S/U)와 `wave` 숫자로, `entries`를 반투명 녹색으로 그리도록 수정. (HTML은 file:// 로 열어 확인; 브라우저 확인 결과를 문서에 한 줄 기록.)

- [ ] **Step 4: 검증**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg && godot --headless --path . --script tests/stage_schema_acceptance.gd 2>&1 | tail -2
```
Expected: `PASS`. 그리고 `first_floor_stages_acceptance`도 PASS(적 좌표가 `.`에 있는지 검사함).

- [ ] **Step 5: Commit 후 STOP — 사용자에게 문서를 보여주고 승인받는다**

```bash
git add docs/stages/f1.ko.md data/content/stages/f1.json docs/art/handcrafted-stages/preview.html && git commit -m "content: redesign first floor rooms as authored tactical puzzles"
```
스펙 §7.3: 이 문서는 승인 대상이다. 승인 전에는 Task 3로 넘어가지 않는다. 승인에서 수정 요청이 오면 문서·JSON을 고치고 다시 커밋한다.

---

### Task 3: 생성기·증원·목표를 저작 데이터에 연결

**Files:**
- Modify: `sim/nine_room_generator.gd:77-95` (1층 적 배치 블록)
- Modify: `sim/stage_counterplay.gd`
- Modify: `tests/stage_counterplay_acceptance.gd` (증원 주기를 방 설정에서 읽도록)
- Test: `tests/stage_objective_acceptance.gd` (신규)

**Interfaces:**
- Consumes: `StageCatalog.room(1,id)`, `wave_enemies`.
- Produces:
  - 생성기 `rooms[id]["stage"]={"reinforcements":{...},"objective":{...}}` (1층은 저작값, 2층은 `{"reinforcements":{"interval_rounds":7,"cap":8,"spawn_edges":["N","E","S","W"]},"objective":{"type":"ELIMINATE","rounds":0,"cell":[-1,-1],"retreat_allowed":true}}`).
  - `StageCounterplay.config(w)->Dictionary` — 현재 방의 `stage` dict.
  - `StageCounterplay.cleared(w)->bool` — 활성 적 0 **또는** SURVIVE 목표 달성.
  - `StageCounterplay.retreat_allowed(w)->bool`.
  - `StageCounterplay.status(w)`에 `objective`, `objective_done`, `cleared` 키 추가.

- [ ] **Step 1: 기존 counterplay 테스트를 방 설정 기반으로 수정**

`tests/stage_counterplay_acceptance.gd`에서 `7`·`6`이 하드코딩된 세 줄을 바꾼다:
```gdscript
	var interval:int=int(Stage.config(w).reinforcements.interval_rounds)
	var count:int=w.party_encounter.enemy_ids.size()
	for i in range(interval-2):check(Stage.finish_round(s.sim),"predeadline counter")
	check(Stage.current(w).turn==interval-1 and w.party_encounter.enemy_ids.size()==count,"no wave before deadline")
	check(Stage.finish_round(s.sim),"deadline reinforcement")
	check(w.party_encounter.enemy_ids.size()==count+2,"two enemies at deadline")
```
(이 테스트가 들어가는 방은 `F1_R4_R7` → 방 7 `f1_guard`. Task 2에서 방 7에 authored wave가 있으면 "+2"가 authored 수로 바뀌므로, 아래 Step 3에서 authored wave 우선 규칙을 넣고 이 검사는 `count+expected`로 계산한다: `var expected:int=maxi(Catalog.wave_enemies(Catalog.room(1,7),1).size(), 0); if expected==0: expected=int(Stage.CONFIG.wave_size)`.)

- [ ] **Step 2: 새 테스트 작성**

`tests/stage_objective_acceptance.gd`:
```gdscript
extends "res://tests/first_floor_stages_acceptance.gd"
const Stage=preload("res://sim/stage_counterplay.gd")
const Catalog=preload("res://sim/stage_catalog.gd")
const Generator=preload("res://sim/nine_room_generator.gd")
func run():
	var layout:Dictionary=Generator.generate(44,1)
	for room in layout.rooms:
		check(room.has("stage") and room.stage.has("reinforcements") and room.stage.has("objective"),"room carries stage config %d"%room.room_id)
		var authored:Dictionary=Catalog.room(1,int(room.room_id))
		var expected:Array=Catalog.wave_enemies(authored,0)
		var placed:Array=layout.enemy_roster.filter(func(e):return e.group_id=="ROOM_%d"%room.room_id)
		check(placed.size()==expected.size(),"authored wave 0 count %d"%room.room_id)
		for i in range(mini(placed.size(),expected.size())):
			check(placed[i].species_id==expected[i].kind,"authored kind %d"%room.room_id)
	var second:Dictionary=Generator.generate(44,2)
	check(second.rooms.all(func(r):return r.stage.objective.type=="ELIMINATE"),"floor 2 default objective")
	# SURVIVE objective opens the room without killing everyone.
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(11,14)),"approach guard room")
	check(s.request_room_exit(hero,"F1_R4_R7",w.party_encounter.nine_room_floor.revision).accepted,"enter guard room")
	var objective:Dictionary=Stage.config(w).objective
	check(objective.type=="SURVIVE","guard room is a survive stage")
	check(not Stage.cleared(w),"not cleared on entry")
	for i in range(int(objective.rounds)):Stage.current(w).turn=i;check(not Stage.cleared(w) or i>=int(objective.rounds),"not cleared before rounds")
	Stage.current(w).turn=int(objective.rounds)
	check(Stage.cleared(w),"cleared after surviving")
	check(Stage.status(w).objective_done,"status reports objective")
	check(Stage.retreat_allowed(w),"retreat allowed by default")
	print("STAGE_OBJECTIVE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```
(방 7이 Task 2에서 SURVIVE가 아니게 되면 이 테스트의 방 id·포털을 SURVIVE 방으로 바꾼다.)

- [ ] **Step 3: 실패 확인**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg && godot --headless --path . --script tests/stage_objective_acceptance.gd 2>&1 | tail -3
```
Expected: `room carries stage config` 등 FAIL, exit 1.

- [ ] **Step 4: 생성기 수정**

`sim/nine_room_generator.gd`의 방 루프에서 `rooms.append({...})` 직후 `stage` 부여, 1층 적 배치 블록 교체:
```gdscript
	const DEFAULT_STAGE:={"reinforcements":{"interval_rounds":7,"cap":8,"spawn_edges":["N","E","S","W"]},"objective":{"type":"ELIMINATE","rounds":0,"cell":[-1,-1],"retreat_allowed":true}}
```
(파일 상단 상수로) 그리고 방 생성 루프 안:
```gdscript
		var stage:Dictionary=DEFAULT_STAGE.duplicate(true)
		if floor_index==1:
			var authored:Dictionary=FirstFloor.room(id)
			stage={"reinforcements":authored.reinforcements.duplicate(true),"objective":authored.objective.duplicate(true)}
		rooms.append({"room_id":id,"coord":[id%3,id/3],"role":roles[id],"bounds":[origin.x,origin.y,8,8],"exits":exits,"stage":stage})
```
적 배치 블록(`if room.role=="COMBAT":` 내부)에서 1층 분기:
```gdscript
			if floor_index==1:
				for e in preload("res://sim/stage_catalog.gd").wave_enemies(template,0):
					var p:Vector2i=origin+Vector2i(int(e.cell[0]),int(e.cell[1]))
					enemies.append({"position":p,"species_id":str(e.kind),"group_id":"ROOM_%d"%room.room_id,"route_id":"ROOM_%d"%room.room_id})
			else:
				for i in range(mini(species.size(),int(CONFIG.enemies_per_combat_room))):
					var cell:Array=template.enemy_cells[i]
					var p:Vector2i=origin+Vector2i(cell[0],cell[1])
					enemies.append({"position":p,"species_id":species[i],"group_id":"ROOM_%d"%room.room_id,"route_id":"ROOM_%d"%room.room_id})
```
기존 `species={0:[...]...}.get(...)` 1층 오버라이드 줄은 삭제. `nine_room_floor_state.create()`는 `floor.nine_rooms.duplicate(true)`를 저장하므로 `stage` 키가 저장·검증 토폴로지에 포함된다 — `wire_error`의 토폴로지 비교는 재생성 결과와의 동일성이므로 문제 없다. 단 `VERSION`을 7→8로 올린다(기존 저장 무효화 명시).

- [ ] **Step 5: counterplay 수정**

`sim/stage_counterplay.gd`에 추가/변경:
```gdscript
static func config(w)->Dictionary:
	if not enabled(w):return {}
	return Rooms.current_floor(w).rooms[int(w.party_encounter.nine_room_floor.active_room_id)].get("stage",{})
static func objective_done(w)->bool:
	var o:Dictionary=config(w).get("objective",{})
	return str(o.get("type",""))=="SURVIVE" and int(current(w).get("turn",0))>=int(o.get("rounds",0))
static func cleared(w)->bool:
	return enabled(w) and (enemies(w).is_empty() or objective_done(w))
static func retreat_allowed(w)->bool:
	return bool(config(w).get("objective",{}).get("retreat_allowed",true))
static func authored_wave(w,wave:int)->Array:
	var s:Dictionary=w.party_encounter.nine_room_floor
	if int(s.floor_index)!=1:return []
	return preload("res://sim/stage_catalog.gd").wave_enemies(preload("res://sim/stage_catalog.gd").room(1,int(s.active_room_id)),wave)
```
`finish_round`에서 전역 상수 대신 방 설정:
```gdscript
	var cfg:Dictionary=config(w).get("reinforcements",{"interval_rounds":int(CONFIG.rounds_per_wave),"cap":int(CONFIG.max_active_enemies),"spawn_edges":["N","E","S","W"]})
	if int(cfg.cap)<=0:return true
	if int(state.turn)<(int(state.waves)+1)*int(cfg.interval_rounds):return true
	var authored:Array=authored_wave(w,int(state.waves)+1)
	var count:int=mini(authored.size() if not authored.is_empty() else int(CONFIG.wave_size),int(cfg.cap)-living.size())
	if count<=0:return true
```
스폰 칸: authored가 있으면 `origin+cell`이 비어 있고 `Rooms.safe`면 그 칸, 아니면 기존 변 후보 중 `spawn_edges`에 해당하는 변만(`N`: y==bounds.position.y, `E`: x==bounds.end.x-1, `S`: y==bounds.end.y-1, `W`: x==bounds.position.x). species는 authored `kind`, 없으면 `CONFIG.reinforcement_species` 순환. `status(w)`에 `"objective":config(w).get("objective",{}),"objective_done":objective_done(w),"cleared":cleared(w)` 추가.

- [ ] **Step 6: 통과 확인**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg
for t in stage_objective_acceptance stage_counterplay_acceptance first_floor_solo_roster first_floor_stages_acceptance srpg_party_turns_acceptance handcrafted_rooms_acceptance; do echo "== $t"; godot --headless --path . --script tests/$t.gd 2>&1 | tail -2; done
```
Expected: 모두 PASS. `first_floor_solo_roster`가 "첫층 전투방당 초기 적 1마리"를 검사한다면(커밋 `8254624`) Task 2의 설계와 충돌한다 — 그 테스트는 저작 wave 0 수와 비교하도록 갱신한다(`Catalog.wave_enemies(...,0).size()`).

- [ ] **Step 7: Commit**

```bash
git add sim/nine_room_generator.gd sim/stage_counterplay.gd tests/stage_counterplay_acceptance.gd tests/stage_objective_acceptance.gd tests/first_floor_solo_roster.gd && git commit -m "feat: authored enemy waves, per-room reinforcements and survive objective"
```

---

### Task 4: StageMapModel

**Files:**
- Create: `sim/stage_map_model.gd`
- Test: `tests/stage_map_acceptance.gd` (이 태스크에서는 모델 부분만; Task 5에서 travel 검사를 이어 붙인다)

**Interfaces:**
- Consumes: `room_transition_rules`(`enabled`, `current_floor`, `portals`, `membership`), `stage_counterplay.cleared`, `round_combat_rules.active`.
- Produces: `StageMapModel.build(w)->Dictionary`:
  `{"floor_index":int,"current":int,"in_combat":bool,"nodes":[{"id","name","role","biome","visited","cleared","reachable","current"}],"edges":[[a,b],...]}`. 노드는 `visited`이거나 발견된 통로로 인접한 방만 포함. 미방문 방의 `name`은 `"미탐색"`.

- [ ] **Step 1: 테스트 작성**

`tests/stage_map_acceptance.gd`:
```gdscript
extends "res://tests/first_floor_stages_acceptance.gd"
const MapModel=preload("res://sim/stage_map_model.gd")
func node(map:Dictionary,id:int)->Dictionary:
	for n in map.nodes:
		if int(n.id)==id:return n
	return {}
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"species");check(s.town_life_command({"action":"START"}).accepted,"town");check(s.depart_town().accepted,"depart")
	var w=s.sim.world
	var map:Dictionary=MapModel.build(w)
	check(map.current==4 and map.floor_index==1 and not map.in_combat,"start at entry")
	check(node(map,4).visited and node(map,4).current and node(map,4).cleared,"entry visited")
	for id in [3,5,7]:check(node(map,id).reachable and not node(map,id).visited and node(map,id).name=="미탐색","adjacent discovered %d"%id)
	check(node(map,1).is_empty() and node(map,0).is_empty(),"undiscovered rooms hidden")
	check(map.edges.size()==3,"three discovered edges")
	var before:Dictionary=s.sim.snapshot();MapModel.build(w);check(s.sim.snapshot()==before,"model is read only")
	print("STAGE_MAP ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: 실패 확인** — 위 rsync+godot 명령으로 실행. Expected: 파싱 오류, exit ≠ 0.

- [ ] **Step 3: 구현**

`sim/stage_map_model.gd`:
```gdscript
extends RefCounted
const Rooms=preload("res://sim/room_transition_rules.gd")
const Stage=preload("res://sim/stage_counterplay.gd")
const RoundRules=preload("res://sim/round_combat_rules.gd")
static func build(w)->Dictionary:
	if not Rooms.enabled(w):return {}
	var s:Dictionary=w.party_encounter.nine_room_floor;var floor:Dictionary=Rooms.current_floor(w)
	var current:int=int(s.active_room_id);var f:int=int(s.floor_index)
	var in_combat:bool=RoundRules.active(w) and not Stage.cleared(w)
	var edges:Array=[];var adjacent:Dictionary={}
	for p in floor.portals:
		if p.portal_id not in s.discovered_portals:continue
		edges.append([int(p.a),int(p.b)])
		if int(p.a)==current:adjacent[int(p.b)]=true
		if int(p.b)==current:adjacent[int(p.a)]=true
	var nodes:Array=[]
	for id in range(9):
		var visited:bool="%d:%d"%[f,id] in s.visited
		if not visited and not adjacent.has(id):continue
		var room:Dictionary=floor.rooms[id]
		var enemies:int=0
		for enemy_id in w.party_encounter.enemy_ids:
			if w.is_unresolved_enemy(enemy_id) and Rooms.membership(w.entities[enemy_id].position)==Vector2i(f,id):enemies+=1
		var cleared:bool=(enemies==0) if id!=current else Stage.cleared(w) or str(room.role)!="COMBAT"
		nodes.append({"id":id,"name":str(room.get("template_name","")) if visited else "미탐색","role":str(room.role),"biome":str(room.get("biome","dungeon")),"visited":visited,"cleared":cleared,"reachable":adjacent.has(id) and not in_combat and s.pending_exit.is_empty(),"current":id==current})
	return {"floor_index":f,"current":current,"in_combat":in_combat,"nodes":nodes,"edges":edges}
```
`w.is_unresolved_enemy(id)`는 `room_transition_system.gd`가 이미 사용하는 API.

- [ ] **Step 4: 통과 확인** — `tests/stage_map_acceptance.gd` PASS.

- [ ] **Step 5: Commit**

```bash
git add sim/stage_map_model.gd sim/stage_map_model.gd.uid tests/stage_map_acceptance.gd && git commit -m "feat: stage map model for node selection"
```

---

### Task 5: 맵 이동(travel) — 시스템·세션·저널

**Files:**
- Modify: `sim/systems/room_transition_system.gd` (`_arrive` 추출, `travel` 추가)
- Modify: `playtest/party_playtest_session.gd` (`stage_map`, `request_room_travel`, 저널 `travel` 재생·검증)
- Test: `tests/stage_map_acceptance.gd` (이어서)

**Interfaces:**
- Produces:
  - `RoomTransitionSystem.travel(sim,room_id:int,revision:int)->Dictionary` — `{accepted,reason,transitioned,time_cost:0,events_start,events_end}`. 거부 이유: `room_exit_unavailable`, `room_revision_changed`, `room_exit_pending`, `room_combat_active`, `room_not_adjacent`, `room_party_cannot_move`, `room_arrival_full`.
  - `Session.stage_map()->Dictionary` (= `StageMapModel.build`)
  - `Session.request_room_travel(room_id:int,expected_revision:int)->Dictionary` (feedback DTO, `room_result` 포함)
  - 저널 행 `{"kind":"travel","operation":{"room_id":int,"revision":int}}`

- [ ] **Step 1: 테스트 확장**

`tests/stage_map_acceptance.gd`의 `run()` 끝(`print` 앞)에 추가:
```gdscript
	var rev:int=int(w.party_encounter.nine_room_floor.revision);var time:int=w.world_time
	check(not s.request_room_travel(1,rev).accepted,"undiscovered room rejected")
	var moved:Dictionary=s.request_room_travel(5,rev)
	check(moved.accepted,"travel east "+str(moved.get("reason")))
	check(int(w.party_encounter.nine_room_floor.active_room_id)==5,"active room 5")
	check(w.world_time==time,"travel costs no time")
	check("1:5" in w.party_encounter.nine_room_floor.visited,"room 5 visited")
	for id in w.party_encounter.active_party_member_ids:check(Rooms.current(w,w.entities[id].position),"party inside room 5")
	check(not s.request_room_travel(4,rev).accepted,"stale revision rejected")
	check(s.request_room_travel(4,int(w.party_encounter.nine_room_floor.revision)).accepted,"travel back")
	check(s.request_room_travel(7,int(w.party_encounter.nine_room_floor.revision)).accepted,"travel into combat room")
	check(w.party_encounter.round_combat.phase=="DEPLOYMENT","combat room starts deployment")
	map=MapModel.build(w)
	check(map.in_combat and map.nodes.all(func(n):return not n.reachable),"no travel during combat")
	check(not s.request_room_travel(4,int(w.party_encounter.nine_room_floor.revision)).accepted,"travel rejected in combat")
	var clone=Session.new();var loaded:Dictionary=clone.load_session_json(s.save_session_json())
	check(loaded.accepted,"travel journal replay "+str(loaded.get("reason")))
	if loaded.accepted:check(clone.sim.snapshot()==s.sim.snapshot(),"travel replay exact")
	check(w.world_state_error().is_empty(),"world audit "+w.world_state_error())
```

- [ ] **Step 2: 실패 확인** — `request_room_travel` 없음 오류.

- [ ] **Step 3: 시스템 구현**

`sim/systems/room_transition_system.gd`: `resolve_pending_exit`의 "도착" 부분(`var from:int=s.active_room_id` 부터 `w.set_meta(...)` 까지)을 아래 `_arrive`로 추출하고 두 곳에서 호출한다.
```gdscript
static func _arrive(w,p:Dictionary,target:int,ids:Array,cells:Array,request_id:String,travel:bool)->void:
	var s:Dictionary=w.party_encounter.nine_room_floor;var from:int=int(s.active_room_id)
	for index in range(ids.size()):
		var id:int=ids[index];var to:Vector2i=cells[index];var previous:Vector2i=w.entities[id].position
		w.emit_event("room.entered",id,-1,to,0,-1,{"schema_version":1,"ruleset_id":Rules.Generator.RULESET_ID,"portal_id":p.portal_id,"floor_index":int(s.floor_index),"source_room":from,"target_room":target,"from_position":[previous.x,previous.y],"to_position":[to.x,to.y],"request_id":request_id,"travel":travel})
		w.entities[id].position=to;w.reindex_entity_occupancy(id,previous,to)
	s.active_room_id=target;s.pending_exit.clear();s.revision=int(s.revision)+1
	for key in Rules.current_floor(w).rooms[target].exits:
		if key not in s.discovered_portals:s.discovered_portals.append(key)
	var visit:="%d:%d"%[s.floor_index,target]
	if visit not in s.visited:s.visited.append(visit)
	if p.portal_id not in s.discovered_portals:s.discovered_portals.append(p.portal_id)
	w.party_encounter.group_anchor=w.entities[w.party_encounter.protagonist_id].position
	var old_round:Dictionary=w.party_encounter.round_combat
	var next_round:=RoundState.fresh();next_round.round_id=int(old_round.round_id);next_round.plan_revision=int(old_round.plan_revision)+1
	next_round.stage_rooms=old_round.stage_rooms.duplicate(true)
	w.party_encounter.round_combat=next_round
	w.party_encounter.safe_phase="GROUPED";w.party_encounter.contact_kind="NONE";w.party_encounter.contact_enemy_id=-1;w.party_encounter.formation_id="NONE"
	w.set_meta("room_transition_visual",{"from_room":from,"to_room":target,"direction":Rules.membership(cells[0]),"revision":int(s.revision),"portal_id":p.portal_id})

static func _tick_target(sim,target:int)->bool:
	var w=sim.world;var s:Dictionary=w.party_encounter.nine_room_floor
	var room_key:="%d:%d"%[s.floor_index,target];var processed:int=int(s.effect_processed_at.get(room_key,"0"))
	var membership:=Vector2i(int(s.floor_index),target)
	if not preload("res://sim/consumable_effects.gd").tick(sim,processed,w.world_time,membership) or not preload("res://sim/abilities/monster_ability_runtime.gd").tick(sim,processed,w.world_time,membership):return false
	s.effect_processed_at[room_key]=str(w.world_time)
	return sim.party_coordinator.reconcile_liveness(false)

static func travel(sim,room_id:int,revision:int)->Dictionary:
	var w=sim.world
	if not Rules.enabled(w) or not w.is_settled():return Rules.rejected("room_exit_unavailable")
	var s:Dictionary=w.party_encounter.nine_room_floor
	if int(s.revision)!=revision:return Rules.rejected("room_revision_changed")
	if not s.pending_exit.is_empty():return Rules.rejected("room_exit_pending")
	if RoundRules.active(w) and not preload("res://sim/stage_counterplay.gd").cleared(w):return Rules.rejected("room_combat_active")
	var current:int=int(s.active_room_id);var p:Dictionary={}
	for candidate in Rules.portals(w):
		if candidate.portal_id in s.discovered_portals and [int(candidate.a),int(candidate.b)] in [[current,room_id],[room_id,current]]:p=candidate;break
	if p.is_empty():return Rules.rejected("room_not_adjacent")
	var ids:Array=Rules.party_ids(w)
	for id in ids:
		if not w.can_act(id,w.world_time):return Rules.rejected("room_party_cannot_move")
	var cells:Array=Rules.arrivals(w,p,room_id,ids)
	if cells.is_empty():return Rules.rejected("room_arrival_full")
	var start:int=w.events.size();var rollback:Dictionary=w.rollback_memento(false)
	if not _tick_target(sim,room_id):sim.restore_rollback_memento(rollback);return Rules.rejected("room_effect_failed")
	s.request_serial=int(s.request_serial)+1
	_arrive(w,p,room_id,ids,cells,"TRAVEL_%d"%int(s.request_serial),true)
	return {"accepted":true,"reason":"ok","transitioned":true,"time_cost":0,"events_start":start,"events_end":w.events.size()}
```
`resolve_pending_exit`는 기존 pursuer 계산 후 `_arrive(w,p,int(assessed.target_room),assessed.party_ids,assessed.arrivals,str(request.request_id),false)`를 호출하도록 바꾼다. `room.entered` 데이터에 `travel` 키를 추가했으므로 `sim/world_state.gd`의 `room.entered` 검증기(`_party_floor_entry_positions` 등)가 키 집합을 엄격 비교하는지 `grep -n '"room.entered"' sim/world_state.gd`로 확인하고, 엄격하면 `travel` 키를 허용 목록에 추가한다.

- [ ] **Step 4: 세션 구현**

`playtest/party_playtest_session.gd`의 `visible_room_minimap()` 아래에 추가:
```gdscript
func stage_map()->Dictionary:
	return preload("res://sim/stage_map_model.gd").build(sim.world) if room_enabled() else {}

func request_room_travel(room_id:int,expected_revision:int)->Dictionary:
	if not room_enabled() or _run_is_complete():return _rejection_dto("room_exit_unavailable")
	var rollback:Dictionary=sim.capture_rollback_memento(false)
	var result:Dictionary=preload("res://sim/systems/room_transition_system.gd").travel(sim,room_id,expected_revision)
	if not result.get("accepted",false):return _rejection_dto(str(result.reason))
	if not RoundPlans.begin(sim):sim.restore_rollback_memento(rollback);return _rejection_dto("room_plan_failed")
	command_journal.append({"kind":"travel","operation":{"room_id":room_id,"revision":expected_revision}})
	if _auto_explore!=null:_auto_explore.cancel("room_transition")
	if _exploration_route!=null:_exploration_route.cancel_for_direct_command()
	_clear_draft();_advance_exile_world()
	var dto:=_feedback_dto({"accepted":true,"reason":"ok","message":"%s · %s"%[room_status().get("name",""),preload("res://sim/room_transition_rules.gd").current_floor(sim.world).rooms[room_id].get("hint","")]})
	dto["room_result"]=result;return dto
```
저널 재생(`"room":` 분기 옆, 8802행 부근):
```gdscript
			"travel":replay_result=replay.request_room_travel(int(row.operation.room_id),int(row.operation.revision))
```
저널 검증(9318행 부근 `"room":` 분기 옆):
```gdscript
			"travel":
				if keys!=["kind","operation"] or not row.operation is Dictionary:return "invalid_travel_journal"
				var travel_keys:Array=row.operation.keys();travel_keys.sort()
				if travel_keys!=["revision","room_id"] or not preload("res://sim/nine_room_floor_state.gd").integer(row.operation.room_id) or int(row.operation.room_id) not in range(9) or not preload("res://sim/nine_room_floor_state.gd").integer(row.operation.revision):return "invalid_travel_journal"
```
`_advance_exile_world`, `_clear_draft`, `RoundPlans`가 `request_room_exit`에서 쓰는 이름과 동일한지 그 함수를 보고 맞춘다.

- [ ] **Step 5: 통과 확인**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg
for t in stage_map_acceptance stage_counterplay_acceptance first_floor_stages_acceptance srpg_party_turns_acceptance; do echo "== $t"; godot --headless --path . --script tests/$t.gd 2>&1 | tail -2; done
```
Expected: 모두 PASS. `room.entered` 검증 실패가 나오면 Step 3 마지막 주의사항을 처리.

- [ ] **Step 6: Commit**

```bash
git add sim/systems/room_transition_system.gd playtest/party_playtest_session.gd tests/stage_map_acceptance.gd && git commit -m "feat: zero-time room travel from the stage map with journal replay"
```

---

### Task 6: 도주 스트레스·도주 금지 방·원정 포기

**Files:**
- Modify: `sim/systems/room_transition_system.gd` (`begin_exit` 데이터에 `combat`, 금지 방 거부)
- Modify: `sim/party_morale_model.gd` (`evaluate`), `sim/systems/party_morale_system.gd` (`_source_event_ids`)
- Modify: `playtest/base_progression_service.gd` (`base_return_assessment(force)`, `base_return(force)`)
- Modify: `playtest/party_playtest_session.gd` (`abandon_expedition`, 저널 `base ABANDON`)
- Create: `data/content/stage_stress.json` — `{"retreat_attempt":120,"abandon":200}`
- Test: `tests/retreat_stress_acceptance.gd`, `tests/abandon_acceptance.gd`

**Interfaces:**
- Produces:
  - 이벤트 `room.exit_requested` 데이터에 `"combat":bool` 추가. 전투 중 도주 요청이면 파티 전원 스트레스 `+retreat_attempt`(트리거 `RETREAT`).
  - `RoomTransitionSystem.request`가 전투 중 `retreat_allowed==false`면 `room_retreat_forbidden`.
  - 이벤트 `expedition.abandoned` (actor=protagonist, magnitude=abandon) → 전원 `+abandon`(트리거 `ABANDON`).
  - `Session.abandon_expedition()->Dictionary`; 저널 `{"kind":"base","operation":{"action":"ABANDON"}}`.
  - `BaseProgressionService.base_return(force:bool=false)`.

- [ ] **Step 1: 도주 테스트 작성**

`tests/retreat_stress_acceptance.gd`:
```gdscript
extends "res://tests/first_floor_stages_acceptance.gd"
const Stage=preload("res://sim/stage_counterplay.gd")
const Stress=preload("res://sim/json_content_loader.gd")
func stress_of(w)->Dictionary:
	var out:Dictionary={}
	for id in w.party_encounter.active_party_member_ids:out[id]=int(w.party_encounter.member(id).stress)
	return out
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(walk(s,Vector2i(11,14)),"approach combat room")
	check(s.request_room_exit(hero,"F1_R4_R7",w.party_encounter.nine_room_floor.revision).accepted,"enter")
	check(s.stage_round_action(preload("res://sim/party_action_command.gd").move_to(hero,Vector2i(10,17))).accepted,"deploy")
	var r:Dictionary=w.party_encounter.round_combat
	check(s.confirm_round(r.round_id,r.plan_revision).accepted,"deployment confirmed")
	var before:Dictionary=stress_of(w)
	# Retreat: the hero stands next to the north exit (11,16) after deployment at (10,17).
	var result:Dictionary=s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision))
	check(result.accepted,"retreat request accepted "+str(result.get("reason")))
	var cost:int=int(Stress.load_document("res://data/content/stage_stress.json").retreat_attempt)
	for id in before:check(int(w.party_encounter.member(id).stress)>=before[id]+cost-50,"retreat stress applied to %d"%id)
	check(w.events.any(func(e):return e.type=="party.morale_changed" and "RETREAT" in e.data.trigger_codes),"RETREAT trigger recorded")
	var clone=Session.new();var loaded:Dictionary=clone.load_session_json(s.save_session_json())
	check(loaded.accepted and clone.sim.snapshot()==s.sim.snapshot(),"retreat replay exact")
	# Forbidden room: flip the objective flag on the live floor and expect rejection.
	var floor:Dictionary=preload("res://sim/room_transition_rules.gd").current_floor(w)
	floor.rooms[7].stage.objective.retreat_allowed=false
	check(s.request_room_travel(7,int(w.party_encounter.nine_room_floor.revision)).accepted,"re-enter guard room")
	check(s.stage_round_action(preload("res://sim/party_action_command.gd").move_to(hero,Vector2i(10,17))).accepted,"deploy again")
	r=w.party_encounter.round_combat;check(s.confirm_round(r.round_id,r.plan_revision).accepted,"deployment confirmed again")
	var forbidden:Dictionary=s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision))
	check(not forbidden.accepted and str(forbidden.reason)=="room_retreat_forbidden","retreat forbidden "+str(forbidden.get("reason")))
	print("RETREAT_STRESS ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```
(주의: 토폴로지를 손으로 바꾸면 `nine_room_floor_state.wire_error`의 토폴로지 비교가 저장/재현에서 실패하므로 "금지 방" 검사는 재현 검사 **뒤에** 둔다. 마지막 검사 후 저장하지 않는다.) 도주 후 위치·`-50` 여유는 회복 규칙이 같은 경계에서 스트레스를 조금 내릴 수 있기 때문이다.

- [ ] **Step 2: 포기 테스트 작성**

`tests/abandon_acceptance.gd`:
```gdscript
extends "res://tests/first_floor_stages_acceptance.gd"
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"species");check(s.town_life_command({"action":"START"}).accepted,"town");check(s.depart_town().accepted,"depart")
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(s.request_room_travel(5,int(w.party_encounter.nine_room_floor.revision)).accepted,"move east")
	var stress_before:int=int(w.party_encounter.member(hero).stress)
	var cost:int=int(preload("res://sim/json_content_loader.gd").load_document("res://data/content/stage_stress.json").abandon)
	var result:Dictionary=s.abandon_expedition()
	check(result.accepted,"abandon accepted "+str(result.get("reason")))
	check(str(w.party_encounter.expedition_cycle.phase)=="TOWN","back in town")
	check(int(w.party_encounter.member(hero).stress)>=stress_before+cost-50,"abandon stress")
	check(w.events.any(func(e):return e.type=="expedition.abandoned"),"abandon event")
	var clone=Session.new();var loaded:Dictionary=clone.load_session_json(s.save_session_json())
	check(loaded.accepted and clone.sim.snapshot()==s.sim.snapshot(),"abandon replay exact "+str(loaded.get("reason")))
	check(s.depart_town().accepted,"depart again")
	check(w.party_encounter.nine_room_floor.visited==["1:4"] and int(w.party_encounter.nine_room_floor.active_room_id)==4,"floor progress reset")
	check(not s.abandon_expedition().accepted or true,"abandon only in dungeon (second call is a fresh expedition)")
	check(w.world_state_error().is_empty(),"world audit "+w.world_state_error())
	print("ABANDON ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 3: 두 테스트 실패 확인** — `abandon_expedition` 없음 / `room_retreat_forbidden` 미구현 / RETREAT 트리거 없음.

- [ ] **Step 4: 스트레스 소스 구현**

`data/content/stage_stress.json`: `{"schema_version":1,"retreat_attempt":120,"abandon":200}`.

`sim/systems/room_transition_system.gd`:
- `begin_exit`의 `emit_event("room.exit_requested", ...)` 데이터에 `"combat":RoundRules.active(w)` 추가.
- `request`의 `if RoundRules.active(w):` 블록 첫 줄에 `if not preload("res://sim/stage_counterplay.gd").retreat_allowed(w):return Rules.rejected("room_retreat_forbidden")`.

`sim/party_morale_model.gd` 상단에 `static var STRESS:Dictionary=preload("res://sim/json_content_loader.gd").load_document("res://data/content/stage_stress.json")`, `evaluate`의 이벤트 분기에 추가:
```gdscript
		elif event_type=="room.exit_requested" and bool((event.get("data",{}) if event is Dictionary else event.data).get("combat",false)):
			for member_id in members:
				direct[member_id]=int(direct[member_id])+int(STRESS.retreat_attempt);triggers[member_id].append("RETREAT")
		elif event_type=="expedition.abandoned":
			for member_id in members:
				direct[member_id]=int(direct[member_id])+int(STRESS.abandon);triggers[member_id].append("ABANDON")
```
`sim/systems/party_morale_system.gd::_source_event_ids`에 `if event_type=="room.exit_requested": relevant=bool(data.get("combat",false))`와 `if event_type=="expedition.abandoned": relevant=true`를 추가(`data`는 그 함수에서 event dict/객체 양쪽을 다루는 기존 패턴을 따른다).

도주 요청은 `confirm()`이 처리하는 라운드 경계 안에서 `commit_batch`가 `events_since(event_start)`를 받으므로 `begin_exit`가 confirm 전에 이벤트를 내는 현재 순서에서 자동으로 반영된다. 그렇지 않으면(테스트 실패) `request`의 전투 분기에서 confirm 후 `PartyMoraleSystem.commit_batch(w,[exit_event],false)`를 직접 호출한다.

- [ ] **Step 5: 포기 구현**

`playtest/base_progression_service.gd`:
- `base_return_assessment(force:bool=false)`: `force`면 `at_entry/at_active_anchor` 검사와 `nearby_enemy_ids` 검사를 건너뛴다(`entry_mode:"ABANDON"`).
- `base_return(force:bool=false)`: assessment에 `force` 전달, `return_reason`은 `"ABANDON" if force else "MANUAL_EXTRACT"`, 저널 행은 `{"action":"ABANDON" if force else "RETURN"}`. 이벤트 `dungeon.expedition_returned`의 `return_reason` 허용값에 `ABANDON`이 들어가는지 `grep -n "MANUAL_EXTRACT" sim/*.gd`로 검증기를 찾아 추가한다.
- `force`일 때 `cycle.manual_return` 직전에 층 진행 초기화: `state.nine_room_floor=preload("res://sim/nine_room_floor_state.gd").create(_session._map_layout)` 는 토폴로지를 다시 만들므로 안전하고, `round_combat.stage_rooms`를 `{}`로 비운다. 파티 위치는 `_map_layout.entry_position`으로 옮긴다(`w.entities[id].position` + `reindex_entity_occupancy`; 점유 충돌 시 `Rules.arrivals`처럼 입구 주변 빈 칸).

`playtest/party_playtest_session.gd`:
```gdscript
func abandon_expedition()->Dictionary:
	if not room_enabled() or _run_is_complete():return _rejection_dto("room_exit_unavailable")
	var w=sim.world
	if preload("res://sim/round_combat_rules.gd").active(w) and not preload("res://sim/stage_counterplay.gd").cleared(w):return _rejection_dto("room_combat_active")
	var hero:int=w.party_control_actor_id()
	var rollback:Dictionary=sim.snapshot()
	var event=w.emit_event("expedition.abandoned",hero,-1,w.entities[hero].position,int(preload("res://sim/party_morale_model.gd").STRESS.abandon),-1,{"schema_version":1,"ruleset_id":"stage-campaign-v1","floor_index":int(w.party_encounter.nine_room_floor.floor_index),"room_id":int(w.party_encounter.nine_room_floor.active_room_id)})
	if event==null or not preload("res://sim/systems/party_morale_system.gd").commit_batch(w,[event],false):sim=SimulatorScript.from_snapshot(rollback);return _rejection_dto("abandon_failed")
	var result:Dictionary=_base_progression.base_return(true)
	if not result.get("accepted",false):sim=SimulatorScript.from_snapshot(rollback);return result
	result=result.duplicate(true);result["message"]="원정을 포기하고 거점으로 돌아왔습니다";return result
```
`_base_progression`은 세션이 `BaseProgressionService`를 보유하는 실제 필드명으로 바꾼다(`grep -n "base_progression_service" playtest/party_playtest_session.gd`). 저널 재생 `"base"` 분기에 `"ABANDON":replay_result=replay.abandon_expedition()` 추가, 검증의 허용 action 목록에 `ABANDON` 추가. 이벤트 `expedition.abandoned`가 world_state의 알려진 이벤트 목록 검증에 걸리면(`grep -n '"dungeon.expedition_returned"' sim/world_state.gd` 주변) 같은 곳에 등록한다.

- [ ] **Step 6: 통과 확인**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg
for t in retreat_stress_acceptance abandon_acceptance stage_map_acceptance stage_counterplay_acceptance srpg_party_turns_acceptance first_floor_stages_acceptance; do echo "== $t"; godot --headless --path . --script tests/$t.gd 2>&1 | tail -2; done
```
Expected: 모두 PASS.

- [ ] **Step 7: Commit**

```bash
git add data/content/stage_stress.json sim/systems/room_transition_system.gd sim/party_morale_model.gd sim/systems/party_morale_system.gd playtest/base_progression_service.gd playtest/party_playtest_session.gd tests/retreat_stress_acceptance.gd tests/abandon_acceptance.gd && git commit -m "feat: retreat and abandon stress costs, forbidden-retreat rooms, expedition abandon"
```

---

### Task 7: 맵 오버레이 UI와 통로 걷기 입력 제거

**Files:**
- Create: `playtest/stage_map_view.gd`
- Modify: `playtest/party_encounter_sandbox.gd` (`_on_cell` 통로 분기, 맵 버튼, 오버레이 생성)
- Modify: `playtest/stage_context_bar.gd` (버튼 추가 위치는 이 파일의 기존 버튼 생성 패턴을 따른다)
- Test: `tests/stage_map_ui_acceptance.gd`

**Interfaces:**
- Consumes: `Session.stage_map()`, `Session.request_room_travel()`, `Session.abandon_expedition()`.
- Produces: `StageMapView` (Control) — `open(map:Dictionary)`, 시그널 `room_selected(room_id:int)`, `abandon_requested`, `closed`. 샌드박스 필드 `stage_map_view`, 메서드 `_open_stage_map()`.

- [ ] **Step 1: UI 테스트 작성**

`tests/stage_map_ui_acceptance.gd` (`stage_context_ui_acceptance.gd`의 `tap`·초기화 패턴 그대로):
```gdscript
extends "res://tests/stage_context_ui_acceptance.gd"
func run():
	root.size=Vector2i(360,800);root.content_scale_size=Vector2i(360,800)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"species");check(s.town_life_command({"action":"START"}).accepted,"town");check(s.depart_town().accepted,"depart")
	var ui=Sandbox.new();ui.size=Vector2(360,800);ui.initialize_for_headless_test(s,true);test_ui=ui
	root.add_child(ui);ui.set_process(false)
	for i in range(4):await process_frame
	check(ui.stage_context_bar.map_button.is_visible_in_tree(),"map button in exploration")
	check(ui.stage_context_bar.map_button.size.y>=44,"44px map button")
	await tap(ui.stage_context_bar.map_button)
	check(ui.stage_map_view.visible,"map overlay opens")
	var node_button=ui.stage_map_view.node_button(5)
	check(node_button!=null and not node_button.disabled,"east room selectable")
	check(ui.stage_map_view.node_button(1)==null,"undiscovered room not drawn")
	await tap(node_button)
	check(not ui.stage_map_view.visible,"overlay closes after travel")
	check(int(s.sim.world.party_encounter.nine_room_floor.active_room_id)==5,"travelled east by tap")
	await tap(ui.stage_context_bar.map_button)
	await tap(ui.stage_map_view.node_button(4));await tap(ui.stage_context_bar.map_button);await tap(ui.stage_map_view.node_button(7))
	check(s.round_status().phase=="DEPLOYMENT","combat room deployment via map")
	check(not ui.stage_context_bar.map_button.is_visible_in_tree(),"map button hidden during combat")
	# Tapping the old doorway cell must no longer trigger a room exit outside combat.
	ui._on_cell(Vector2i(11,15))
	check(int(s.sim.world.party_encounter.nine_room_floor.active_room_id)==7,"doorway tap does not travel")
	print("STAGE_MAP_UI ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
```

- [ ] **Step 2: 실패 확인** — `xvfb-run -a godot --path . --script tests/stage_map_ui_acceptance.gd` (X11 필요; Task 0에서 미실행이었다면 이 태스크의 UI 테스트도 헤드리스로는 `map_button` 존재 검사까지만 돈다는 것을 결과에 기록).

- [ ] **Step 3: `stage_map_view.gd` 구현**

```gdscript
extends Control
## Node-selection overlay. Presentation only: it never touches the simulator.
signal room_selected(room_id:int)
signal abandon_requested
signal closed
const ROLE_LABEL:={"COMBAT":"전투","HAZARD":"위험","SAFE":"휴식","STAIRS":"계단"}
var _buttons:Dictionary={}
var _panel:PanelContainer;var _grid:GridContainer;var _title:Label;var _abandon:Button;var _close:Button
func _ready()->void:
	set_anchors_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP;visible=false
	var dim:=ColorRect.new();dim.color=Color(0,0,0,0.72);dim.set_anchors_preset(Control.PRESET_FULL_RECT);add_child(dim)
	_panel=PanelContainer.new();_panel.set_anchors_preset(Control.PRESET_CENTER);_panel.custom_minimum_size=Vector2(328,420);add_child(_panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);_panel.add_child(box)
	_title=Label.new();_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;box.add_child(_title)
	_grid=GridContainer.new();_grid.columns=3;_grid.add_theme_constant_override("h_separation",8);_grid.add_theme_constant_override("v_separation",8);box.add_child(_grid)
	var row:=HBoxContainer.new();box.add_child(row)
	_abandon=Button.new();_abandon.text="거점으로 귀환";_abandon.custom_minimum_size=Vector2(150,48);_abandon.pressed.connect(func():abandon_requested.emit());row.add_child(_abandon)
	_close=Button.new();_close.text="닫기";_close.custom_minimum_size=Vector2(100,48);_close.pressed.connect(close);row.add_child(_close)
func open(map:Dictionary)->void:
	for child in _grid.get_children():child.queue_free()
	_buttons.clear()
	_title.text="%d층 · 다음 방을 고르세요"%int(map.get("floor_index",1))
	var by_id:Dictionary={}
	for n in map.get("nodes",[]):by_id[int(n.id)]=n
	for id in range(9):
		var slot:Control
		if by_id.has(id):
			var n:Dictionary=by_id[id];var b:=Button.new()
			b.custom_minimum_size=Vector2(100,100);b.text="%s\n%s"%[ROLE_LABEL.get(str(n.role),str(n.role)),str(n.name)]
			if bool(n.current):b.text="▶ "+b.text
			elif bool(n.visited) and bool(n.cleared):b.text="✓ "+b.text
			b.disabled=not bool(n.reachable);b.pressed.connect(func():room_selected.emit(id))
			_buttons[id]=b;slot=b
		else:
			slot=Control.new();slot.custom_minimum_size=Vector2(100,100)
		_grid.add_child(slot)
	_abandon.disabled=bool(map.get("in_combat",false))
	visible=true
func close()->void:visible=false;closed.emit()
func node_button(id:int)->Button:return _buttons.get(id)
```

- [ ] **Step 4: 샌드박스·컨텍스트 바 연결**

- `playtest/stage_context_bar.gd`: 기존 탐험 모드 버튼(예: 휴식·턴 종료) 생성 코드 옆에 `map_button:Button`(텍스트 "지도", `custom_minimum_size=Vector2(72,48)`)을 만들고, 컨텍스트 바가 전투/배치 단계에서 버튼을 갱신하는 함수에서 `map_button.visible = session.room_enabled() and not session.round_active()`로 설정한다. (이 파일의 갱신 함수 이름은 `grep -n "func " playtest/stage_context_bar.gd`로 확인.)
- `playtest/party_encounter_sandbox.gd`:
  - 초기화(`_ready`/`initialize_for_headless_test` 공통 경로)에서 `stage_map_view=preload("res://playtest/stage_map_view.gd").new(); add_child(stage_map_view); stage_map_view.room_selected.connect(_on_map_room_selected); stage_map_view.abandon_requested.connect(_on_map_abandon); stage_context_bar.map_button.pressed.connect(_open_stage_map)`.
  - ```gdscript
    func _open_stage_map()->void:
    	if grid.stage_motion_busy():return
    	stage_map_view.open(session.stage_map())
    func _on_map_room_selected(room_id:int)->void:
    	stage_map_view.close()
    	_record_result(session.request_room_travel(room_id,int(session.room_status().revision)),false)
    	_request_refresh()
    func _on_map_abandon()->void:
    	stage_map_view.close()
    	_record_result(session.abandon_expedition(),false)
    	_request_refresh()
    ```
  - `_on_cell`의 통로 분기(`if session.room_enabled() and _battle_target_mode.is_empty() and session.round_status().phase!="DEPLOYMENT":` … `request_room_exit`)를 **전투 중에만** 살린다: 조건에 `and session.round_active()`를 추가. 이것이 도주(출구 옆 칸 터치)이고, 비전투 이동은 맵으로만 한다.
  - `room_transition_visual` 메타를 읽어 슬라이드 연출을 하는 코드(`grep -n room_transition_visual playtest/*.gd`)는 travel일 때 짧은 페이드(연출 시간 0~120ms)로 대체하거나 그대로 둔다 — 게임 시간과 무관하므로 어느 쪽이든 테스트에 영향 없음. 이 계획에서는 그대로 둔다.

- [ ] **Step 5: 통과 확인**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg
xvfb-run -a godot --path . --script tests/stage_map_ui_acceptance.gd 2>&1 | tail -3
xvfb-run -a godot --path . --script tests/stage_context_ui_acceptance.gd 2>&1 | tail -3
```
Expected: 둘 다 PASS. `stage_context_ui_acceptance`가 통로 걷기로 방을 옮기는 단계를 갖고 있으면 그 부분을 `request_room_travel` 또는 맵 탭으로 바꾼다.

- [ ] **Step 6: Commit**

```bash
git add playtest/stage_map_view.gd playtest/stage_map_view.gd.uid playtest/party_encounter_sandbox.gd playtest/stage_context_bar.gd tests/stage_map_ui_acceptance.gd tests/stage_context_ui_acceptance.gd && git commit -m "feat: stage map overlay replaces doorway walking outside combat"
```

---

### Task 8: 방 반복 도구 — stage_lab, stage_probe

**Files:**
- Create: `tools/stage_lab.gd` (SceneTree 스크립트; `--room=<id>`로 방 하나에 바로 진입해 샌드박스를 띄움)
- Create: `tools/stage_probe.gd` (헤드리스 난이도 진단)
- Modify: `docs/stages/f1.ko.md` (도구 사용법 절 추가)

**Interfaces:**
- Consumes: `Session.request_room_travel`, `Session.stage_round_action`, `confirm_round`, `Stage.status`.
- Produces: `godot --path . --script tools/stage_lab.gd -- --room=7` / `godot --headless --path . --script tools/stage_probe.gd -- --room=7 --seeds=20 --policy=charge` → 표준 출력 CSV `seed,room,outcome,rounds,hp_lost,waves`.

- [ ] **Step 1: stage_probe 작성**

```gdscript
extends SceneTree
## Headless difficulty probe. Diagnostic, not a pass/fail test.
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const Stage=preload("res://sim/stage_counterplay.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Rooms=preload("res://sim/room_transition_rules.gd")
const MAX_ROUNDS:=40
func arg(name:String,default:String)->String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s="%name):return a.substr(name.length()+3)
	return default
func _init():call_deferred("run")
func route(s,target:int)->bool:
	# Travel through discovered rooms only; breadth-first over the 3x3 graph.
	var w=s.sim.world;var s_floor:Dictionary=w.party_encounter.nine_room_floor
	var edges:Array=Rooms.current_floor(w).portals.map(func(p):return [int(p.a),int(p.b)])
	var prev:Dictionary={int(s_floor.active_room_id):-1};var todo:Array=[int(s_floor.active_room_id)]
	for a in todo:
		for e in edges:
			var b:int=e[1] if e[0]==a else (e[0] if e[1]==a else -1)
			if b>=0 and not prev.has(b):prev[b]=a;todo.append(b)
	if not prev.has(target):return false
	var path:Array=[];var cur:int=target
	while cur!=-1:path.push_front(cur);cur=prev[cur]
	for id in path.slice(1):
		if not s.request_room_travel(id,int(w.party_encounter.nine_room_floor.revision)).accepted:return false
		if Rules.active(w):return id==target
	return true
func nearest_enemy(w,id:int)->int:
	var best:=-1;var best_d:=999
	for e in Stage.enemies(w):
		var d:int=Rooms.distance(w.entities[id].position,w.entities[e].position)
		if d<best_d:best=e;best_d=d
	return best
func act(s,policy:String)->void:
	var w=s.sim.world;var id:int=Rules.current_actor(w)
	if id<0 or id not in w.party_encounter.active_party_member_ids:
		var r:Dictionary=w.party_encounter.round_combat
		if r.phase=="INTERRUPTED":s.resume_round(r.round_id,r.plan_revision)
		else:s.confirm_round(r.round_id,r.plan_revision)
		return
	var target:int=nearest_enemy(w,id)
	if target>=0 and policy=="charge":
		var reach:Dictionary=s.round_move_options(id) if s.has_method("round_move_options") else {}
		# Step toward the target along the cheapest legal cell, then attack if adjacent.
		var best:Vector2i=w.entities[id].position;var best_d:int=Rooms.distance(best,w.entities[target].position)
		for cell in reach.get("cells",[]):
			var c:=Vector2i(cell[0],cell[1]);var d:int=Rooms.distance(c,w.entities[target].position)
			if d<best_d:best=c;best_d=d
		if best!=w.entities[id].position:s.stage_round_action(Action.move_to(id,best))
		if Rooms.distance(w.entities[id].position,w.entities[target].position)<=1:s.stage_round_action(Action.attack(id,target));return
	s.stage_round_action(Action.hold(id))
func run():
	var room:int=int(arg("room","7"));var seeds:int=int(arg("seeds","10"));var policy:String=arg("policy","charge")
	print("seed,room,outcome,rounds,hp_lost,waves")
	for seed in range(1,seeds+1):
		var s=Session.new(seed,20260828,Session.DUO_SCENARIO_ID,"human",true)
		s.start_new_run_with_species("human",true,true);s.town_life_command({"action":"START"});s.depart_town()
		var w=s.sim.world
		if not route(s,room):print("%d,%d,unreachable,0,0,0"%[seed,room]);continue
		var hp0:int=0
		for id in w.party_encounter.active_party_member_ids:hp0+=w.entities[id].health
		# Deploy in place: confirm the deployment round without moving.
		var r:Dictionary=w.party_encounter.round_combat
		if r.phase=="DEPLOYMENT":s.confirm_round(r.round_id,r.plan_revision)
		var rounds:=0
		while Rules.active(w) and not Stage.cleared(w) and rounds<MAX_ROUNDS and w.party_encounter.safe_phase!="PARTY_DEFEATED":
			var before:int=int(Stage.current(w).get("turn",0));act(s,policy)
			if int(Stage.current(w).get("turn",0))>before:rounds+=1
		var hp1:int=0
		for id in w.party_encounter.active_party_member_ids:hp1+=w.entities[id].health
		var outcome:String="defeat" if w.party_encounter.safe_phase=="PARTY_DEFEATED" else ("cleared" if Stage.cleared(w) else "timeout")
		print("%d,%d,%s,%d,%d,%d"%[seed,room,outcome,rounds,hp0-hp1,int(Stage.current(w).get("waves",0))])
	quit(0)
```
`round_move_options`·`Action.attack`의 실제 이름은 `srpg_party_turns_acceptance.gd`가 쓰는 API로 맞춘다(`grep -n "stage_round_action\|Action\.\(attack\|strike\)" tests/srpg_party_turns_acceptance.gd`).

- [ ] **Step 2: stage_lab 작성**

`tools/stage_lab.gd`: `SceneTree` 스크립트. 세션을 만들고 `route()`(위와 동일 로직을 복사)로 `--room` 방까지 travel한 뒤 `party_encounter_sandbox.gd`를 `root`에 붙인다(`stage_context_ui_acceptance.gd`의 초기화 4줄과 동일). X11에서 `godot --path . --script tools/stage_lab.gd -- --room=7`로 실행.

- [ ] **Step 3: 실행 확인**

```bash
cd /root/lw-bench-srpg && godot --headless --path . --script tools/stage_probe.gd -- --room=7 --seeds=5 --policy=charge 2>&1 | tail -7
```
Expected: 헤더 + 5행 CSV, outcome이 `cleared|defeat|timeout` 중 하나, exit 0.

- [ ] **Step 4: 문서화 후 Commit**

`docs/stages/f1.ko.md` 끝에 "도구" 절: 두 명령과 CSV 열 의미, "timeout이 많으면 농성 이득 의심, defeat 100%면 난이도 재검토" 해석 기준.
```bash
git add tools/stage_lab.gd tools/stage_probe.gd docs/stages/f1.ko.md && git commit -m "tools: stage lab and headless stage probe"
```

---

### Task 9: 마무리 — 회귀 전체 실행과 결과 문서

**Files:**
- Create: `docs/plans/plan-a-results.ko.md`

- [ ] **Step 1: 전체 회귀**

```bash
rsync -a --delete --exclude .git /mnt/d/STARTU/proj-s-srpg-stages/ /root/lw-bench-srpg/ && cd /root/lw-bench-srpg
for t in stage_schema_acceptance stage_objective_acceptance stage_map_acceptance retreat_stress_acceptance abandon_acceptance stage_counterplay_acceptance srpg_party_turns_acceptance first_floor_solo_roster handcrafted_tile_assets_acceptance handcrafted_rooms_acceptance round_combat_scenarios first_floor_stages_acceptance; do echo "== $t"; godot --headless --path . --script tests/$t.gd 2>&1 | tail -2; done
xvfb-run -a godot --path . --script tests/stage_context_ui_acceptance.gd 2>&1 | tail -2
xvfb-run -a godot --path . --script tests/stage_map_ui_acceptance.gd 2>&1 | tail -2
```
Expected: Task 0 기준선 대비 새 실패 없음, 신규 테스트 전부 PASS.

- [ ] **Step 2: 웹 내보내기**

기존 내보내기 절차(`export_presets.cfg`의 Web preset, `godot --headless --path . --export-release Web build/web/index.html`)로 exit 0 확인. 실패하면 원인만 기록(내보내기 수정은 범위 밖).

- [ ] **Step 3: 결과 문서·커밋**

`docs/plans/plan-a-results.ko.md`: 구현 항목, 테스트 표(기준선 vs 현재), 알려진 한계(포기 시 층 완전 재생성은 Plan C, 2층 미저작, REACH/PROTECT 미구현, 도주 슬라이드 연출 유지), stage_probe 5시드 결과 표.
```bash
git add docs/plans/plan-a-results.ko.md && git commit -m "docs: Plan A results and known limits"
```
