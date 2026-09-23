# 던전 NPC Implementation Plan (Plan B)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 층마다 3~5명의 NPC가 자기 감각으로 깨어나 우리 전투 AI로 싸우고, 성격에 따라 다가오거나 거리를 두며, 식량 나눔·제안·말 걸기로 파티에 합류한다. 2인 조는 함께 움직이고 함께(또는 갈라서서) 합류한다.

**Architecture:** NPC는 `make_actor`로 만든 아군 액터에 `npc: true`를 붙인 것이다. `s.npcs`에 살며 `s.at()`·보드·`s.friends()`가 본다. 전투 판정은 `Tactics.choose(s, npc)` 그대로 — 아군 목록을 `s.alive()`에서 `s.friends()`(파티 + 깨어 있는 NPC)로 바꾸는 한 번의 리팩터가 전부다. 비전투 행동은 `npc_modes.gd`의 작은 효용표(접근/거리 유지/휴식/탐색)가 고른다. 영입 상태는 NPC 자신의 기억(`AID_RECEIVED`, `DECLINED_*`)이 들고, 세션은 `aid/propose/offer/recruit` 네 함수만 노출한다.

**Tech Stack:** Godot 4.6 GDScript, headless tests, `Hexaco.sample`로 결정론.

**Spec:** `docs/superpowers/specs/2026-09-25-run-camp-npc-design.md` §5, §6(NPC 표시), §8(npc_* 스위트).

## Global Constraints

- Godot 창을 띄우지 않는다. 헤드리스만.
- 전투 AI의 **판단 로직**은 바꾸지 않는다: `stances.gd`·`utility.gd`·`lookahead.gd`·`parts_candidates.gd`·`tactical_action_selector.gd`에서 허용되는 편집은 `s.alive()` → `s.friends()` 치환뿐이다(Task 3). `tactics_profiles.json`의 기존 표는 불변, `npc_modes` 표만 추가.
- Plan A(`2026-09-25-descent-run.md`)와 병행된다. Plan A가 아직 없을 때를 위한 대체 경로를 `NpcRoster.depth(s)`·`NpcRoster.npc_rooms(layout)` 두 헬퍼에 가둔다(Task 1). 그 외에 Plan A의 삭제 대상(마을·횃불·빛·방 모드)을 건드리지 않는다. 마지막 Task에서 Plan A가 메인에 있으면 리베이스하고 두 헬퍼의 대체 경로를 지운다.
- `tests/stances.gd`(113)·`tests/utility.gd`(151)·`tests/autobattle.gd`(105)·`tests/parts.gd`(338)·`tests/protect.gd`(38)·`tests/skill_rule_conditions.gd`(962)의 검사 수를 줄이지 않는다.
- 파티 최대 3인. `party[0]`은 주인공.
- 커밋은 `jinha1226 <jinha1226@gmail.com>`, 트레일러 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `expedition/npc_roster.gd` (신규) | Run 명부 생성, 2인 조, 층 배치(상황·방), 재등장 HP 감소, Plan A 대체 헬퍼 |
| `data/content/npc_names.json` (신규) | 이름 20개 |
| `expedition/npc_ai.gd` (신규) | 감각(깨어남·잠듦·소음), 라운드 행동(전투 = `Tactics.choose`, 비전투 = 모드), 2인 조 인접, 활동 문구, 죽음 |
| `expedition/npc_modes.gd` (신규) | 모드 효용표 로드·입력·점수·설명·유지/전환 |
| `data/content/tactics_profiles.json` | `npc_modes` 표 추가 |
| `expedition/npc_recruit.gd` (신규) | 도움·제안·말 걸기·수락 확률·2인 조 규칙·기억 기록 |
| `expedition/session.gd` | `npcs`, `friends()`, `at()`·`noise` 훅, 라운드 훅, `aid/propose/offer/answer_offer/recruit` 위임, NPC 사망 |
| `sim/party_memory_state.gd` | `KINDS` 4종 추가 |
| AI 5개 파일 | `s.alive()` → `s.friends()` |
| `expedition/monster_ai.gd` | 표적 `s.friends()` |
| `expedition/board.gd`, `main.gd` | NPC 토큰·이름표, NPC 팝업, 제안 팝업, 결과 이력 |
| `tests/npc_roster.gd`, `npc_sense.gd`, `npc_behaviour.gd`, `recruit.gd` (신규) | §8 |

---

### Task 1: 명부·이름·층 배치

**Files:**
- Create: `expedition/npc_roster.gd`, `data/content/npc_names.json`, `tests/npc_roster.gd`
- Modify: `expedition/session.gd`(`npcs`, `roster`, `at()`, `depart()` 훅), `expedition/board.gd`(액터 목록에 `npcs`)

**Interfaces:**
- Produces: `NpcRoster.generate(s) -> Array`(10명, `s.roster`), `NpcRoster.place(s) -> void`(층 배치, `s.npcs`), `NpcRoster.depth(s) -> int`, `NpcRoster.npc_rooms(layout) -> Array`, `NpcRoster.situation(npc) -> String`. NPC 필드: `npc: true, awake: false, mode: "", mode_until: 0, hungry: bool, partner: int, bond: String, state: "UNMET"|"MET"|"PARTY"|"DEAD", floor_seen: int, activity: String, explains: [], noise_seen: int`.
- Consumes: `Session.make_actor`, `Hexaco.generated/sample`, `Stances.default_stance`, `Abilities.DEFINITIONS/default_rule/droppable`, `layout.rooms/encounters/entry`, `Generator.floor_cells`.

- [ ] **Step 1: 실패하는 테스트 — `tests/npc_roster.gd`**

```gdscript
extends SceneTree
## Run roster: ten NPCs, two duos, three to five placed per floor with a situation.
const Session = preload("res://expedition/session.gd")
const Roster = preload("res://expedition/npc_roster.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	roster(); placement(); reappearance()
	print("NPC roster: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func roster() -> void:
	var s = Session.new(41,false,false,true,1)
	var rows: Array = Roster.generate(s)
	check(rows.size() == 10 and s.roster == rows,"ten NPCs on the run roster")
	var names: Array = rows.map(func(n): return n.name)
	check(names.size() == names.reduce(func(acc,n): return acc if n in acc else acc+[n],[]).size(),"names are unique")
	check(rows.all(func(n): return n.npc and not n.enemy and n.id >= 100 and n.hp == 55 and n.max_hp == 55 and n.state == "UNMET" and not n.awake),"npc fields")
	check(rows.all(func(n): return n.stress >= 0 and n.stress <= 40),"stress 0-40")
	check(rows.all(func(n): return n.stance in ["CHARGER","SKIRMISHER","GUARDIAN"] and n.stance == s.Stances.default_stance(n.profile)),"stance is the personality's default")
	var with_part: int = rows.filter(func(n): return n.equipped_abilities[0] != "").size()
	check(with_part >= 1 and with_part <= 8 and rows.all(func(n): return n.equipped_abilities[1] == "" and (n.equipped_abilities[0] == "" or n.rules.size() == 1)),"some carry one part with its rule")
	var paired: Array = rows.filter(func(n): return n.partner >= 0)
	check(paired.size() == 4 and paired.all(func(n): return rows.filter(func(m): return m.id == n.partner)[0].partner == n.id),"two mutual duos")
	check(paired.all(func(n): return n.bond in ["close","strained"] and rows.filter(func(m): return m.id == n.partner)[0].bond == n.bond),"bond shared by the pair")
	check(rows.filter(func(n): return n.partner < 0).all(func(n): return n.bond == ""),"singles have no bond")
	var again: Array = Roster.generate(Session.new(41,false,false,true,1))
	check(again.map(func(n): return [n.name,n.partner,n.bond,n.stance]) == rows.map(func(n): return [n.name,n.partner,n.bond,n.stance]),"deterministic per seed")

func placement() -> void:
	var s = Session.new(42,false,false,true,1); s.depart()
	check(s.roster.size() == 10,"depart generates the roster")
	check(s.npcs.size() == 3,"floor 1 places three")
	check(s.npcs.all(func(n): return n.state == "MET" and n.floor_seen == Roster.depth(s) and n.hp > 0),"placed NPCs are met on this floor")
	for n in s.npcs:
		check(s.inside(n.pos) and s.tile(n.pos).terrain != "wall" and s.at(n.pos) == n,"npc stands on a floor cell and at() finds it")
		check(Roster.situation(n) in ["FIGHTING","WOUNDED","RESTING"],"situation set")
		if Roster.situation(n) == "WOUNDED": check(n.hp*100/n.max_hp >= 30 and n.hp*100/n.max_hp <= 50 and n.stress >= 30,"wounded hp 30-50%% (%s)" % n.name)
		if Roster.situation(n) == "FIGHTING":
			check(n.hp*100/n.max_hp >= 60 and n.hp*100/n.max_hp <= 80,"fighting hp 60-80%%")
			check(s.enemies.any(func(e): return e.hp > 0 and e.get("npc_pack",-1) == n.id and s.distance(e.pos,n.pos) <= 2),"a pack placed beside the fighting npc")
		if Roster.situation(n) == "RESTING": check(n.hp == n.max_hp,"resting at full")
	var rooms: Array = Roster.npc_rooms(s.floor_state.layout)
	check(rooms.size() >= 3 and rooms.size() <= 5,"three to five npc rooms")
	check(s.npcs.all(func(n): return rooms.any(func(r): return s.floor_state.layout.rooms[r].rect.has_point(n.pos))),"npcs stand in npc rooms")
	# Duos placed together when both are free.
	var duo_seen := false
	for seed in range(20):
		var t = Session.new(seed,false,false,true,1); t.depart()
		for n in t.npcs:
			if n.partner >= 0 and t.npcs.any(func(m): return m.id == n.partner):
				duo_seen = true
				var m: Dictionary = t.npcs.filter(func(x): return x.id == n.partner)[0]
				check(t.distance(n.pos,m.pos) <= 2,"duo placed together (seed %d)" % seed)
	check(duo_seen,"some seed places a duo")
	# Hungry flag: half of the wounded/fighting.
	var hungry := 0; var eligible := 0
	for seed in range(20):
		var t = Session.new(100+seed,false,false,true,1); t.depart()
		for n in t.npcs:
			if Roster.situation(n) != "RESTING": eligible += 1; hungry += 1 if n.hungry else 0
	check(hungry > 0 and hungry < eligible,"some, not all, are hungry (%d/%d)" % [hungry,eligible])

func reappearance() -> void:
	var s = Session.new(43,false,false,true,1); s.depart()
	var first: Array = s.npcs.map(func(n): return n.id)
	var met: Dictionary = s.npcs[0]; met.hp = 50
	Roster.place(s) # second floor placement on the same layout for the test
	check(s.npcs.size() >= 4 and s.npcs.size() <= 5,"later floors place four or five")
	var unmet_first: bool = s.npcs.filter(func(n): return n.id not in first).size() >= s.npcs.size()-first.size()
	check(unmet_first,"unmet NPCs are preferred")
	if s.npcs.any(func(n): return n.id == met.id):
		var back: Dictionary = s.npcs.filter(func(n): return n.id == met.id)[0]
		check(back.hp >= 35 and back.hp <= 45,"a met NPC returns 10-30%% worse off")
	met.state = "DEAD"; Roster.place(s)
	check(not s.npcs.any(func(n): return n.id == met.id),"the dead never return")
	s.roster[3].state = "PARTY"; Roster.place(s)
	check(not s.npcs.any(func(n): return n.id == s.roster[3].id),"party members are not placed")
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 데이터.** `data/content/npc_names.json`: `{"names": ["브란","에다","리오","카일","마렌","토빈","이셀","가렛","노라","페린","실바","오든","레아","하스","미라","조란","엘가","다인","베스","루카"]}`.

- [ ] **Step 4: `npc_roster.gd`.**

```gdscript
extends RefCounted
## The run's NPC roster and its placement on each floor.
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Stances = preload("res://expedition/stances.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Generator = preload("res://expedition/floor_generator.gd")
const Encounters = preload("res://expedition/encounter_builder.gd")
static var names: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/npc_names.json")).names
const COUNT := 10
const DUOS := 2
const SITUATIONS := ["FIGHTING","WOUNDED","RESTING"]

## Plan A shim: depth when the run has it, the expedition number before that.
static func depth(s) -> int:
	return int(s.depth) if s.get("depth") != null else int(s.expedition_number)

## Plan A shim: the generator's npc_rooms, else plain rooms without an encounter, farthest from the entry first.
static func npc_rooms(layout: Dictionary) -> Array:
	if layout.has("npc_rooms"): return layout.npc_rooms
	var busy: Dictionary = {}
	for e in layout.encounters:
		for r in layout.rooms:
			if e.members.any(func(m): return r.rect.has_point(m.pos)): busy[r.id] = true
	var plain: Array = layout.rooms.filter(func(r): return r.kind == "plain" and not busy.has(r.id))
	plain.sort_custom(func(a,b): return Generator.center(a).distance_to(Vector2(layout.entry)) > Generator.center(b).distance_to(Vector2(layout.entry)))
	return plain.slice(0,5).map(func(r): return r.id)

static func generate(s) -> Array:
	var rows: Array = []
	var pool: Array = names.duplicate()
	for i in range(COUNT):
		var id: int = 100+i
		var pick: int = Hexaco.sample(s.seed_value,id,"npc_name",pool.size())
		var actor: Dictionary = s.make_actor(id,pool.pop_at(pick),false)
		actor.profile = Hexaco.generated(s.seed_value,id)
		actor.stance = Stances.default_stance(actor.profile)
		actor.knobs = s.Knobs.defaults(actor.profile)
		actor.stress = Hexaco.sample(s.seed_value,id,"npc_stress",41)
		actor.equipped_abilities = ["",""]; actor.rules = []
		if Hexaco.sample(s.seed_value,id,"npc_part",100) < 40:
			var parts: Array = Abilities.droppable()
			var part: String = parts[Hexaco.sample(s.seed_value,id,"npc_part_id",parts.size())]
			actor.equipped_abilities[0] = part; actor.rules = [Abilities.default_rule(part)]
		actor.merge({"npc":true,"awake":false,"mode":"","mode_until":0,"hungry":false,"partner":-1,"bond":"",
			"state":"UNMET","floor_seen":0,"activity":"","explains":[],"noise_seen":-99,"declined_until":-99,"offered_until":-99})
		rows.append(actor)
	for d in range(DUOS):
		var a: Dictionary = rows[d*2]; var b: Dictionary = rows[d*2+1]
		a.partner = b.id; b.partner = a.id
		var bond: String = "close" if Hexaco.sample(s.seed_value,a.id,"npc_bond",100) < 60 else "strained"
		a.bond = bond; b.bond = bond
	s.roster = rows
	return rows

static func situation(npc: Dictionary) -> String:
	return str(npc.get("situation",""))

## Places three (floor 1) or four to five NPCs from the roster into the floor's npc rooms.
static func place(s) -> void:
	s.npcs = []
	var d: int = depth(s)
	var want: int = 3 if d <= 1 else 4+Hexaco.sample(s.seed_value,d,"npc_count",2)
	var rooms: Array = npc_rooms(s.floor_state.layout)
	if rooms.is_empty(): return
	var free: Array = s.roster.filter(func(n): return n.state in ["UNMET","MET"])
	free.sort_custom(func(a,b):
		if (a.state == "UNMET") != (b.state == "UNMET"): return a.state == "UNMET"
		return Hexaco.sample(s.seed_value,a.id,"npc_order",1000) < Hexaco.sample(s.seed_value,b.id,"npc_order",1000))
	var chosen: Array = []
	for n in free:
		if chosen.size() >= want: break
		if n in chosen: continue
		chosen.append(n)
		if n.partner >= 0:
			var mate: Array = free.filter(func(m): return m.id == n.partner)
			if not mate.is_empty() and chosen.size() < want and mate[0] not in chosen: chosen.append(mate[0])
	var room_i := 0
	var used: Dictionary = {}
	for n in chosen:
		var room: Dictionary = s.floor_state.layout.rooms[rooms[room_i % rooms.size()]]
		var partner_here: bool = n.partner >= 0 and chosen.any(func(m): return m.id == n.partner and used.has(m.id))
		if not partner_here: room_i += 1
		var cells: Array = Generator.floor_cells(s.floor_state.layout.terrain,s.floor_state.layout.size,room.rect).filter(func(p): return s.at(p).is_empty() and not s.floor_state.features.has(p))
		if partner_here:
			var mate_pos: Vector2i = chosen.filter(func(m): return m.id == n.partner)[0].pos
			cells = cells.filter(func(p): return s.distance(p,mate_pos) <= 2)
		if cells.is_empty(): continue
		n.pos = cells[Hexaco.sample(s.seed_value,d*1000+n.id,"npc_cell",cells.size())]
		var situ: String = SITUATIONS[Hexaco.sample(s.seed_value,d*1000+n.id,"npc_situation",3)] if not partner_here else situation(chosen.filter(func(m): return m.id == n.partner)[0])
		n.situation = situ
		if n.state == "MET": n.hp = maxi(1,n.hp-n.max_hp*(10+Hexaco.sample(s.seed_value,d*1000+n.id,"npc_wear",21))/100)
		match situ:
			"WOUNDED": n.hp = n.max_hp*(30+Hexaco.sample(s.seed_value,d*1000+n.id,"npc_hp",21))/100; s.stress(n,30)
			"FIGHTING":
				n.hp = n.max_hp*(60+Hexaco.sample(s.seed_value,d*1000+n.id,"npc_hp",21))/100
				if not partner_here: spawn_pack(s,n,room)
			"RESTING": pass
		n.hungry = situ != "RESTING" and Hexaco.sample(s.seed_value,d*1000+n.id,"npc_hungry",2) == 0
		n.state = "MET"; n.floor_seen = d; n.awake = false; n.mode = ""; n.ap = 1
		used[n.id] = true
		s.npcs.append(n)

## One small monster pack next to a fighting NPC, tagged with the NPC's id.
static func spawn_pack(s, npc: Dictionary, room: Dictionary) -> void:
	var theme: Dictionary = Generator.theme(str(s.floor_state.layout.get("theme_id","F1_RUINS")))
	var members: Array = Encounters.pack(theme,3,depth(s),s.seed_value+npc.id)
	var cells: Array = Generator.floor_cells(s.floor_state.layout.terrain,s.floor_state.layout.size,room.rect).filter(func(p): return s.at(p).is_empty() and s.distance(p,npc.pos) <= 2 and p != npc.pos)
	for i in range(mini(members.size(),cells.size())):
		var m: Dictionary = members[i]
		var enemy: Dictionary = s.make_actor(100+s.enemies.size(),m.display_name,true)
		enemy.pos = cells[i]; enemy.hp = int(m.max_health); enemy.max_hp = enemy.hp
		enemy.group = "NPC_%d" % npc.id; enemy.home = enemy.pos; enemy.alert = true
		enemy.species_id = m.species_id; enemy.tier = "early"; enemy.mandatory = false; enemy.npc_pack = npc.id
		s.Floor.MonsterAI.configure(enemy,m.role)
		enemy.part_id = Abilities.species_part(m.species_id)
		s.enemies.append(enemy)
```

`Encounters.pack(theme, budget, depth, seed) -> Array[{species_id, display_name, max_health, role}]`가 `encounter_builder.gd`에 없으면 그 파일의 무리 채우기 함수를 공개 static으로 감싸 추가한다(이름·시그니처는 위와 같이; 반환 형식은 `layout.encounters[].members`와 동일).

- [ ] **Step 5: 세션 훅.** `session.gd`: `var npcs: Array = []`, `var roster: Array = []`, `const NpcRoster = preload("res://expedition/npc_roster.gd")`. `depart()`에서 `floor_state.build(self)` 뒤: `if roster.is_empty(): NpcRoster.generate(self)`, `NpcRoster.place(self)`. (Plan A의 `descend()`가 있으면 거기에도 `NpcRoster.place(self)` — 리베이스 Task에서.) `at(point)`: `for actor in party+enemies+npcs`. `reset_battle_stats`는 파티만(변경 없음). `board.gd` 401행 액터 목록 `session.party+session.enemies+session.npcs`(그리기 색은 Task 6).

- [ ] **Step 6: 실행 → 통과.** `npc_roster`, `floor_generator`, `continuous_floor`, `autobattle`, `solo_floor`.

- [ ] **Step 7: 커밋.** `feat(npc): run roster of ten with two duos, placed three to five per floor in a situation`

---

### Task 2: 감각·깨어남·라운드 훅

**Files:**
- Create: `expedition/npc_ai.gd`, `tests/npc_sense.gd`
- Modify: `expedition/session.gd`(`noise`, 라운드 훅, `act_as` NPC 이동 허용)

**Interfaces:**
- Produces: `NpcAI.sense(s, npc) -> bool`(깨어 있는지 갱신·반환), `NpcAI.turn(s, npc) -> void`(이번 Task에서는 깨어 있으면 `activity = "지켜보는 중"`·WAIT만; 행동은 Task 3·4), `s.noise: Array[Vector2i]`(이번 라운드 전투 소음 칸; `damage()`가 BATTLE 중 채우고 `end_round` 끝에 비움), 상수 `NpcAI.NOISE_RADIUS := 10`, `SLEEP_AFTER := 5`. 훅: `end_round()`에서 적 차례 **앞**에 `for npc in npcs: if npc.hp > 0 and NpcAI.sense(self,npc): NpcAI.turn(self,npc)`.

- [ ] **Step 1: 실패하는 테스트 — `tests/npc_sense.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

## One npc from the roster parked at `offset` from the hero on a cleared arena.
func field(offset: Vector2i) -> Dictionary:
	var s = Session.new(51,true,true,true,3); s.depart(); var c := Fixture.arena(s,12)
	Fixture.equip_basics(s)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]; npc.pos = c+offset; npc.awake = false; npc.hp = npc.max_hp; npc.noise_seen = -99
	s.floor_state.observe(s)
	return {"s":s,"c":c,"npc":npc}

func run() -> void:
	sight(); noise(); sleep(); no_cost()
	print("NPC sense: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func sight() -> void:
	var f := field(Vector2i(9,0)); var s = f.s; var npc: Dictionary = f.npc
	check(not NpcAI.sense(s,npc) and not npc.awake,"nine tiles away, out of its sight: asleep")
	npc.pos = f.c+Vector2i(4,0)
	check(NpcAI.sense(s,npc) and npc.awake,"four tiles: sees the party and wakes")
	# A wall between them blocks sight.
	var g := field(Vector2i(3,0)); for y in range(-3,4): g.s.tile(g.c+Vector2i(2,y)).terrain = "wall"
	check(not NpcAI.sense(g.s,g.npc),"a wall blocks the npc's sight")

func noise() -> void:
	var f := field(Vector2i(8,0)); var s = f.s; var npc: Dictionary = f.npc
	check(not NpcAI.sense(s,npc),"eight tiles: cannot see")
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.pos = f.c+Vector2i(1,0); foe.alert = true; s.floor_state.observe(s)
	s.damage(foe,5,0,"SLASH")
	check(s.noise.size() == 1 and s.noise[0] == foe.pos,"a hit is noise on the victim's cell")
	check(NpcAI.sense(s,npc) and npc.awake,"combat within ten tiles wakes it")
	var far := field(Vector2i(12,0)); var foe2: Dictionary = far.s.enemies[0]; foe2.hp = 30; foe2.pos = far.c+Vector2i(1,0); far.s.floor_state.observe(far.s)
	far.s.damage(foe2,5,0,"SLASH")
	check(not NpcAI.sense(far.s,far.npc),"noise beyond ten tiles is not heard")
	s.end_round()
	check(s.noise.is_empty(),"noise clears at the end of the round")

func sleep() -> void:
	var f := field(Vector2i(4,0)); var s = f.s; var npc: Dictionary = f.npc
	NpcAI.sense(s,npc); check(npc.awake,"awake")
	npc.pos = f.c+Vector2i(9,0)
	for i in range(4): NpcAI.sense(s,npc); s.round_number += 1
	check(npc.awake,"still awake after four quiet rounds out of sight")
	NpcAI.sense(s,npc); s.round_number += 1; NpcAI.sense(s,npc)
	check(not npc.awake,"asleep after five")
	# Awake NPCs act even when the party cannot see them.
	npc.pos = f.c+Vector2i(4,0); NpcAI.sense(s,npc); npc.pos = f.c+Vector2i(7,0)
	check(NpcAI.sense(s,npc) and npc.awake and not s.floor_state.visible.has(npc.pos),"acts out of the party's sight while awake")

func no_cost() -> void:
	var f := field(Vector2i(9,0)); var s = f.s; var npc: Dictionary = f.npc
	var pos: Vector2i = npc.pos
	for i in range(3): s.end_round()
	check(npc.pos == pos and npc.activity == "","a sleeping npc neither moves nor gets an activity")
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `npc_ai.gd`** (Task 3·4가 채울 자리 포함):

```gdscript
extends RefCounted
## Dungeon NPCs: their senses, their round, and their manners toward the party.
const MonsterAI = preload("res://expedition/monster_ai.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const Stances = preload("res://expedition/stances.gd")
const Knobs = preload("res://expedition/knobs.gd")
const NOISE_RADIUS := 10
const SLEEP_AFTER := 5
const LABELS := {"FIGHT":"교전 중","APPROACH":"다가오는 중","HOLD":"거리를 두고 지켜보는 중","REST":"부상으로 대기 중","EXPLORE":"주변을 탐색 중","":""}

## Wakes on its own sight of the party or on nearby combat; sleeps after five quiet rounds unseen.
static func sense(s, npc: Dictionary) -> bool:
	var seen: int = MonsterAI.sight(s)
	var sees_party: bool = s.alive().any(func(a): return MonsterAI.line(s,npc.pos,a.pos,seen))
	var hears: bool = s.noise.any(func(p): return s.distance(p,npc.pos) <= NOISE_RADIUS)
	if sees_party or hears:
		npc.awake = true; npc.noise_seen = s.round_number
		return true
	if npc.awake and not s.floor_state.visible.has(npc.pos) and s.round_number-int(npc.noise_seen) >= SLEEP_AFTER:
		npc.awake = false; npc.mode = ""; npc.activity = ""
	if npc.awake and s.floor_state.visible.has(npc.pos): npc.noise_seen = s.round_number
	return npc.awake

static func turn(s, npc: Dictionary) -> void:
	npc.ap = 1
	npc.activity = LABELS.HOLD
```

- [ ] **Step 4: 세션.** `var noise: Array = []`; `damage()`에서 `if phase == "BATTLE": noise.append(target.pos)`(HP가 실제로 줄었을 때, 한 라운드에 같은 칸 중복 허용); `end_round()`: `world_time += 100` 바로 뒤에 `for npc in npcs: if npc.hp > 0 and NpcAI.sense(self,npc): NpcAI.turn(self,npc)`; 함수 끝(`plan_enemies()` 앞)에 `noise.clear()`. `act_as`: `var following: bool = (resolving_companions and kind == "MOVE") or bool(actor.get("npc",false))`; `movement_cells(party.find(actor))`는 NPC에 쓰지 않으므로 MOVE 분기를 `if bool(actor.get("npc",false)): if not can_step(actor.pos,target) or not is_free(target) or distance(actor.pos,target) > 1: return false else: if target not in movement_cells(party.find(actor)): return false`로.

- [ ] **Step 5: 실행 → 통과.** `npc_sense`, `npc_roster`, `autobattle`(라운드 훅이 파티 전투를 바꾸지 않아야 한다: NPC가 없는 픽스처는 무영향).

- [ ] **Step 6: 커밋.** `feat(npc): npcs wake on their own sight or nearby combat and sleep when the party is gone`

---

### Task 3: `friends()` 리팩터와 전투 행동

**Files:**
- Modify: `expedition/session.gd`(`friends()`, NPC 사망), `expedition/stances.gd`, `utility.gd`, `lookahead.gd`, `parts_candidates.gd`, `tactical_action_selector.gd`, `monster_ai.gd`, `passives.gd`, `abilities.gd`(161행 `s.party+s.enemies` → `s.party+s.npcs+s.enemies`), `expedition/npc_ai.gd`
- Create: `tests/npc_behaviour.gd`(전투 부분)

**Interfaces:**
- Produces: `s.friends() -> Array`(파티 생존자 + 깨어 있는 살아 있는 NPC), `NpcAI.turn`이 자기 시야에 적이 있으면 `Tactics.choose(s, npc)`로 행동·`activity = "교전 중"`, NPC 사망 → `state = "DEAD"`, 명부 유지.
- 치환 목록(정확히 이 줄들만): `stances.gd` 82·87·90(두 번)·93·104·107행, `utility.gd` 66행, `tactical_action_selector.gd` 106행, `parts_candidates.gd` 35·43·52·67행, `lookahead.gd` 15·66행, `monster_ai.gd` 70행(`var targets: Array = s.friends()`), `passives.gd` 22행과 `abilities.gd` 161행은 `s.party+s.enemies` → `s.party+s.npcs+s.enemies`. `Stances.party_target`의 `s.party[idx]`(protect 지정)와 `session.gd`의 `alive()` 자체는 그대로.

- [ ] **Step 1: 실패하는 테스트 — `tests/npc_behaviour.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
const Modes = preload("res://expedition/npc_modes.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func field(offset: Vector2i, stance: String = "CHARGER") -> Dictionary:
	var s = Session.new(61,true,true,true,3); s.depart(); var c := Fixture.arena(s,12)
	Fixture.equip_basics(s)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]; npc.pos = c+offset; npc.hp = npc.max_hp; npc.stress = 0; npc.stance = stance; npc.awake = true; npc.noise_seen = s.round_number
	npc.equipped_abilities = ["",""]; npc.rules = []; npc.mode = ""; npc.mode_until = 0
	s.mistake_override[npc.id] = false
	s.floor_state.observe(s)
	return {"s":s,"c":c,"npc":npc}

func foe_at(s, p: Vector2i, hp: int = 30) -> Dictionary:
	var foe: Dictionary = s.enemies.filter(func(e): return e.hp <= 0)[0]
	foe.hp = hp; foe.max_hp = hp; foe.pos = p; foe.alert = true; foe.role = "MELEE"; foe.charging = false; foe.cast_recovery = 0; foe.part_id = ""
	s.floor_state.observe(s); return foe

func run() -> void:
	friends(); fights(); targeted(); dies()
	modes_approach(); modes_hold(); modes_rest(); modes_explore(); commitment(); duo(); labels()
	print("NPC behaviour: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func friends() -> void:
	var f := field(Vector2i(3,0)); var s = f.s
	check(s.friends().size() == 4 and f.npc in s.friends(),"awake npc counts as a friend")
	f.npc.awake = false
	check(s.friends().size() == 3,"asleep: not a friend")
	f.npc.awake = true; f.npc.hp = 0
	check(s.friends().size() == 3 and s.alive().size() == 3,"dead npc is neither; alive() stays party-only")

func fights() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	var foe := foe_at(s,npc.pos+Vector2i(1,0))
	var hp: int = foe.hp
	NpcAI.turn(s,npc)
	check(foe.hp < hp and npc.activity == "교전 중","charger npc attacks the adjacent foe through Tactics.choose")
	# A guardian npc covers the wounded hero with 엄호 it carries.
	var g := field(Vector2i(1,0),"GUARDIAN"); var t = g.s; var n2: Dictionary = g.npc
	n2.equipped_abilities = ["GUARD",""]; n2.rules = [t.Abilities.default_rule("GUARD")]
	t.party[0].hp = 5; var foe2 := foe_at(t,t.party[0].pos+Vector2i(-1,0)); foe2.charging = true
	t.intents = [{"id":foe2.id,"cell":t.party[0].pos,"damage":9,"kind":""}]
	NpcAI.turn(t,n2)
	check(t.party[0].get("protected_by",-1) == n2.id,"guardian npc guards the lethal hero")

func targeted() -> void:
	var f := field(Vector2i(4,0)); var s = f.s; var npc: Dictionary = f.npc
	var foe := foe_at(s,npc.pos+Vector2i(1,0))
	for a in s.party: a.pos = f.c+Vector2i(-6,0)+Vector2i(0,s.party.find(a))
	s.floor_state.observe(s)
	var hp: int = npc.hp
	s.floor_state.enemy_turn(s,foe)
	check(npc.hp < hp,"monsters target an awake npc")

func dies() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	npc.hp = 3; var foe := foe_at(s,npc.pos+Vector2i(1,0))
	s.floor_state.enemy_turn(s,foe)
	check(npc.hp <= 0 and npc.state == "DEAD" and s.roster.any(func(r): return r.id == npc.id and r.state == "DEAD"),"a killed npc is DEAD on the roster")
	check(s.phase == "BATTLE","npc death does not end the party's battle")
```

(`modes_*`, `commitment`, `duo`, `labels`는 Task 4에서 추가한다 — 이 Task에서는 `run()`에 위 넷만 호출.)

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 구현.**
- `session.gd`: `func friends() -> Array: return alive()+npcs.filter(func(n): return n.hp > 0 and n.awake)`. `damage()`의 아군 분기(`not target.enemy`)에서 `if target.hp <= 0 and target.get("npc",false): target.state = "DEAD"; target.awake = false; message(target.name+"이(가) 쓰러졌습니다.")`; `member_stats` 호출은 파티가 아니면 `{}`라 그대로.
- 치환 목록 적용. `Stances.party_target` 안의 `s.alive()` 세 곳은 `s.friends()`로(파티 목표는 NPC의 접촉도 센다).
- `npc_ai.gd turn`:

```gdscript
static func turn(s, npc: Dictionary) -> void:
	npc.ap = 1
	var seen: int = MonsterAI.sight(s)
	var foes: Array = s.enemies.filter(func(e): return e.hp > 0 and MonsterAI.line(s,npc.pos,e.pos,seen))
	if not foes.is_empty():
		npc.activity = LABELS.FIGHT; npc.mode = ""
		var choice: Dictionary = Tactics.choose(s,npc)
		perform(s,npc,choice)
		return
	npc.activity = LABELS.HOLD  # Task 4 replaces this with the mode selector.

static func perform(s, npc: Dictionary, choice: Dictionary) -> void:
	var kind: String = str(choice.get("kind","WAIT"))
	var cell: Vector2i = choice.get("cell",npc.pos)
	if not s.act_as(npc,kind,cell,false): s.act_as(npc,"WAIT",npc.pos,false)
	npc.explains.append({"round":s.round_number,"kind":kind,"cell":cell,"explain":choice.get("explain",[])})
	if npc.explains.size() > 20: npc.explains.pop_front()
```

`Tactics.choose`가 `s.floor_state.threats(s)`(파티 시야의 적)만 적으로 보므로, NPC 시야의 적이 파티 시야 밖이면 후보가 없다. 규칙: `combat_enemies()`를 `floor_state.threats(self)`에서 "파티 시야 **또는** 깨어 있는 NPC 시야 안의 적"으로 넓힌다 — `continuous_floor.threats(s)`: `s.enemies.filter(func(e): return e.hp > 0 and (visible.has(e.pos) or s.npcs.any(func(n): return n.awake and n.hp > 0 and MonsterAI.line(s,n.pos,e.pos,MonsterAI.sight(s)))))`. 이는 `in_combat()`도 넓혀 파티가 NPC의 싸움을 "전투 중"으로 보게 한다(자동 진행이 멈추지 않도록 `auto_stop_reason`의 BATTLE_START는 파티 시야 기준 `visible`로 남긴다: `auto.prev_threats` 계산에 `floor_state.party_threats(s)`를 새로 두고 그것을 쓴다).

- [ ] **Step 4: 실행 → 통과.** `npc_behaviour`(넷), `stances`(113), `utility`(151), `autobattle`(105), `parts`, `protect`, `skill_rule_conditions`, `companion_tactics`, `encounter_sim`, `solo_balance`(≥ 3/8 — NPC 없는 시뮬은 무영향이어야 한다), `npc_sense`, `npc_roster`.

- [ ] **Step 5: 커밋.** `feat(npc): awake npcs are friends — they fight with the party's tactics and monsters target them`

---

### Task 4: 활동 모드 효용·2인 조·활동 문구

**Files:**
- Create: `expedition/npc_modes.gd`
- Modify: `data/content/tactics_profiles.json`(`npc_modes`), `expedition/npc_ai.gd`, `tests/npc_behaviour.gd`(모드 검사 추가)

**Interfaces:**
- Produces: `Modes.inputs(s, npc) -> Dictionary`, `Modes.choose(s, npc) -> Dictionary{mode, score, explain}`(유지 10라운드·80점 전환), `NpcAI.turn` 비전투 분기, 상수 `Modes.COMMIT_ROUNDS := 10`, `SWITCH_MARGIN := 80`.
- JSON `npc_modes`:

```json
"npc_modes": {
  "considerations": {"X":"외향 /1000","A":"온화 /1000","C":"신중 /1000","O":"개방 /1000","wounded":"HP<40%","hp_ratio":"HP/최대","party_room":"파티 인원/3","declined":"거절 기억","stress":"스트레스/200","party_seen":"파티가 시야에"},
  "APPROACH": {"X":120,"A":60,"wounded":80,"party_room":-90,"declined":-150,"base":40},
  "HOLD":     {"X":-60,"C":80,"declined":120,"base":60},
  "REST":     {"wounded":200,"stress":80,"base":0},
  "EXPLORE":  {"O":120,"hp_ratio":60,"party_seen":-120,"base":30}
}
```

- [ ] **Step 1: 실패하는 테스트 — `tests/npc_behaviour.gd`에 추가**

```gdscript
func bold(npc: Dictionary, facet: String, value: int) -> void:
	var v: Dictionary = npc.profile.values.duplicate(); v[facet] = value
	npc.profile = load("res://sim/dungeon_population/hexaco_profile.gd").new(v)

func modes_approach() -> void:
	var f := field(Vector2i(6,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"X",900); bold(npc,"O",100)
	var pick: Dictionary = Modes.choose(s,npc)
	check(pick.mode == "APPROACH" and pick.explain[0].id == "X","extravert approaches, X on top")
	var d: int = s.distance(npc.pos,s.party[0].pos)
	NpcAI.turn(s,npc)
	check(s.distance(npc.pos,s.party[0].pos) < d and npc.activity == "다가오는 중","steps toward the party")
	for i in range(8): NpcAI.turn(s,npc)
	check(s.party.any(func(a): return s.melee_reach(npc.pos,a.pos)),"arrives adjacent")
	check(s.pending_offer == npc.id,"adjacent extravert offers to join (Task 5 wires the answer)")

func modes_hold() -> void:
	var f := field(Vector2i(4,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"X",100); bold(npc,"C",800); bold(npc,"O",100)
	check(Modes.choose(s,npc).mode == "HOLD","introvert holds")
	for i in range(6): NpcAI.turn(s,npc)
	var d: int = s.distance(npc.pos,s.party[0].pos)
	check(d >= 3 and d <= 5 and npc.activity == "거리를 두고 지켜보는 중","keeps three to five tiles")

func modes_rest() -> void:
	var f := field(Vector2i(5,0)); var s = f.s; var npc: Dictionary = f.npc
	npc.hp = npc.max_hp/4; bold(npc,"X",900)
	check(Modes.choose(s,npc).mode == "REST","wounded rests even when extravert")
	var pos: Vector2i = npc.pos; NpcAI.turn(s,npc)
	check(npc.pos == pos and npc.activity == "부상으로 대기 중","stays put")

func modes_explore() -> void:
	var f := field(Vector2i(9,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"O",950); bold(npc,"X",300); npc.awake = true
	check(not s.floor_state.visible.has(npc.pos),"out of the party's sight")
	check(Modes.choose(s,npc).mode == "EXPLORE","open-minded npc explores when the party is not in view")
	var pos: Vector2i = npc.pos; NpcAI.turn(s,npc)
	check(npc.pos != pos and npc.activity == "주변을 탐색 중","walks toward a room centre")

func commitment() -> void:
	var f := field(Vector2i(6,0)); var s = f.s; var npc: Dictionary = f.npc
	bold(npc,"X",600); bold(npc,"C",600)
	var first: String = Modes.choose(s,npc).mode
	npc.mode = first; npc.mode_until = s.round_number+Modes.COMMIT_ROUNDS
	bold(npc,"X",520) # a small change must not flip the mode inside the commitment window
	check(Modes.choose(s,npc).mode == first,"committed mode holds against a small score change")
	npc.hp = npc.max_hp/5
	check(Modes.choose(s,npc).mode == "REST","an 80+ point swing switches at once")
	check(Modes.choose(s,npc) == Modes.choose(s,npc),"deterministic")

func duo() -> void:
	var f := field(Vector2i(5,0)); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	a.partner = b.id; b.partner = a.id; a.bond = "close"; b.bond = "close"
	b.pos = f.c+Vector2i(5,3); b.awake = true; b.hp = b.max_hp; b.noise_seen = s.round_number; s.npcs.append(b)
	bold(a,"X",900); bold(b,"X",900)
	s.floor_state.observe(s)
	NpcAI.turn(s,a); NpcAI.turn(s,b)
	check(s.distance(a.pos,b.pos) <= 1,"the one behind steps to its partner first")

func labels() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	foe_at(s,npc.pos+Vector2i(1,0)); NpcAI.turn(s,npc)
	check(npc.activity == "교전 중" and npc.explains.size() == 1 and npc.explains[0].has("explain"),"combat label and an explain row")
	for i in range(25): npc.explains.append({"round":i,"kind":"WAIT","cell":npc.pos,"explain":[]})
	NpcAI.turn(s,npc)
	check(npc.explains.size() == 20,"explains capped at twenty")
```

`run()`에 나머지 호출을 추가한다.

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `npc_modes.gd`.**

```gdscript
extends RefCounted
## What an awake NPC does when nothing is attacking it: a four-mode utility table.
const Utility = preload("res://expedition/utility.gd")
const MODES := ["APPROACH","HOLD","REST","EXPLORE"]
const COMMIT_ROUNDS := 10
const SWITCH_MARGIN := 80
static var _table: Dictionary = {}

static func table() -> Dictionary:
	if _table.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/tactics_profiles.json"))
		_table = parsed.npc_modes if parsed is Dictionary and parsed.has("npc_modes") else {}
		if _table.is_empty(): push_error("tactics_profiles.json has no npc_modes")
	return _table

static func inputs(s, npc: Dictionary) -> Dictionary:
	var seen: int = s.Floor.MonsterAI.sight(s)
	return {"X":npc.profile.value("X")/1000.0,"A":npc.profile.value("A")/1000.0,"C":npc.profile.value("C")/1000.0,"O":npc.profile.value("O")/1000.0,
		"wounded":1.0 if npc.hp*100 < npc.max_hp*40 else 0.0,"hp_ratio":float(npc.hp)/maxf(1.0,npc.max_hp),
		"party_room":float(s.alive().size())/3.0,"declined":1.0 if s.round_number < int(npc.get("declined_until",-99)) or npc.memory.salience_for_subject(1,["DECLINED_BY_PLAYER"]) > 0 else 0.0,
		"stress":clampf(npc.stress/200.0,0.0,1.0),"party_seen":1.0 if s.alive().any(func(a): return s.Floor.MonsterAI.line(s,npc.pos,a.pos,seen)) else 0.0}

static func score_of(mode: String, inp: Dictionary) -> Dictionary:
	var row: Dictionary = table()[mode]
	var total: float = float(row.get("base",0))
	var parts: Array = []
	var ids: Array = row.keys(); ids.sort()
	for id in ids:
		if id == "base": continue
		var contrib: float = float(row[id])*float(inp.get(id,0.0))
		total += contrib; parts.append({"id":id,"input":inp.get(id,0.0),"weight":row[id],"contrib":int(round(contrib))})
	parts.sort_custom(func(a,b): return a.contrib > b.contrib if a.contrib != b.contrib else a.id < b.id)
	return {"mode":mode,"score":int(round(total)),"explain":parts.slice(0,3)}

static func choose(s, npc: Dictionary) -> Dictionary:
	var inp := inputs(s,npc)
	var best: Dictionary = {}
	var current: Dictionary = {}
	for mode in MODES:
		var row := score_of(mode,inp)
		if mode == str(npc.get("mode","")): current = row
		if best.is_empty() or row.score > best.score: best = row
	if not current.is_empty() and s.round_number < int(npc.get("mode_until",0)) and best.score-current.score < SWITCH_MARGIN: return current
	return best
```

- [ ] **Step 4: `npc_ai.gd` 비전투 분기.**

```gdscript
	var pick: Dictionary = Modes.choose(s,npc)
	if pick.mode != str(npc.get("mode","")): npc.mode = pick.mode; npc.mode_until = s.round_number+Modes.COMMIT_ROUNDS
	npc.activity = LABELS[pick.mode]
	npc.explains.append({"round":s.round_number,"kind":pick.mode,"cell":npc.pos,"explain":pick.explain})
	if npc.explains.size() > 20: npc.explains.pop_front()
	# A duo keeps together before anything else.
	var mate: Dictionary = partner_of(s,npc)
	if not mate.is_empty() and s.distance(npc.pos,mate.pos) > 1 and mate.awake:
		var steps: Array = Stances.steps_toward(s,npc,Stances.adjacent_free(s,mate.pos))
		if not steps.is_empty(): s.act_as(npc,"MOVE",steps[0],false); return
	match pick.mode:
		"APPROACH":
			var near: Dictionary = nearest_member(s,npc)
			if s.melee_reach(npc.pos,near.pos):
				if s.round_number >= int(npc.get("offered_until",-99)) and s.pending_offer < 0: s.offer(npc)
				return
			var steps: Array = Stances.steps_toward(s,npc,Stances.adjacent_free(s,near.pos))
			if not steps.is_empty(): s.act_as(npc,"MOVE",steps[0],false)
		"HOLD":
			var near: Dictionary = nearest_member(s,npc)
			var d: int = s.distance(npc.pos,near.pos)
			if d < 3 or d > 5:
				var ring: Array = Stances.near_free(s,near.pos,4).filter(func(p): return s.distance(p,near.pos) >= 3 and s.distance(p,near.pos) <= 5)
				var steps: Array = Stances.steps_toward(s,npc,ring)
				if not steps.is_empty(): s.act_as(npc,"MOVE",steps[0],false)
		"REST": pass
		"EXPLORE":
			var goal: Vector2i = explore_goal(s,npc)
			var steps: Array = Stances.steps_toward(s,npc,[goal])
			if not steps.is_empty(): s.act_as(npc,"MOVE",steps[0],false)

static func partner_of(s, npc: Dictionary) -> Dictionary:
	if int(npc.get("partner",-1)) < 0: return {}
	for n in s.npcs:
		if n.id == npc.partner and n.hp > 0: return n
	return {}

static func nearest_member(s, npc: Dictionary) -> Dictionary:
	var best: Dictionary = s.alive()[0]
	for a in s.alive():
		if s.distance(npc.pos,a.pos) < s.distance(npc.pos,best.pos): best = a
	return best

## Room centres farthest from the entry first, cycling with the round so the walk never stalls on a reached goal.
static func explore_goal(s, npc: Dictionary) -> Vector2i:
	var layout: Dictionary = s.floor_state.layout
	var centres: Array = layout.rooms.map(func(r): return Vector2i(r.rect.get_center()))
	centres.sort_custom(func(a,b): return s.distance(a,layout.entry) > s.distance(b,layout.entry))
	var start: int = npc.id % maxi(1,centres.size())
	for i in range(centres.size()):
		var c: Vector2i = centres[(start+i) % centres.size()]
		if s.distance(c,npc.pos) > 2: return c
	return npc.pos
```

`s.pending_offer: int = -1`과 `s.offer(npc)`(이번 Task에서는 `pending_offer = npc.id; npc.offered_until = round_number+20`만; 답은 Task 5)를 `session.gd`에 추가. `Stances.near_free`/`adjacent_free`/`steps_toward` 시그니처는 `stances.gd` 140·191·200행 그대로.

- [ ] **Step 5: 실행 → 통과.** `npc_behaviour` 전부, Task 3 목록.

- [ ] **Step 6: 커밋.** `feat(npc): field modes — approach, hold, rest, explore — from a small utility table; duos keep together`

---

### Task 5: 영입 — 도움·제안·말 걸기·2인 조·기억

**Files:**
- Create: `expedition/npc_recruit.gd`, `tests/recruit.gd`
- Modify: `expedition/session.gd`(`aid/propose/offer/answer_offer/recruit` 위임, `pending_offer`), `sim/party_memory_state.gd`(`KINDS`)

**Interfaces:**
- Produces: `s.aid(npc) -> bool`, `s.propose(npc) -> Dictionary{accepted: bool, line: String}`, `s.offer(npc) -> bool`(NPC 발 제안 등록), `s.answer_offer(accept: bool) -> bool`, `s.recruit(npc) -> bool`(파티 편입, 2인 조 규칙), `Recruit.chance(s, npc) -> int`, `Recruit.can_aid(s, npc) -> String`, `Recruit.dialogue(s, npc) -> Dictionary{line, can_propose, can_aid, aided}`. `Memory.KINDS` += `RECRUITED`, `DECLINED_BY_PLAYER`, `DECLINED_PLAYER`, `LEFT_BY_PARTNER`.
- 주인공 id는 0이고 기억 subject/instigator는 `id+1` 규약(`remember_important` 호출처 참고): NPC 기억의 subject = `1`(주인공), 주인공 기억의 instigator = `npc.id+1`.

- [ ] **Step 1: 실패하는 테스트 — `tests/recruit.gd`**

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Recruit = preload("res://expedition/npc_recruit.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func solo(seed: int = 71, party_size: int = 1) -> Dictionary:
	var s = Session.new(seed,party_size > 1,party_size > 1,true,party_size); s.depart(); var c := Fixture.arena(s,12)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]; npc.pos = c+Vector2i(1,0); npc.awake = true; npc.hp = npc.max_hp; npc.hungry = false; npc.stress = 0; npc.partner = -1; npc.bond = ""
	s.floor_state.observe(s); s.food = 3
	return {"s":s,"c":c,"npc":npc}

func set_facets(npc: Dictionary, x: int, a: int) -> void:
	var v: Dictionary = npc.profile.values.duplicate(); v.X = x; v.A = a
	npc.profile = Hexaco.new(v)

func run() -> void:
	aid(); chance(); ask(); offer(); full_party(); duo_close(); duo_strained(); kinds()
	print("Recruit: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func aid() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	check(Recruit.can_aid(s,npc) == "도울 일이 없음","healthy, fed npc needs no aid")
	npc.hungry = true
	check(Recruit.can_aid(s,npc).is_empty() and s.aid(npc) and s.food == 2 and not npc.hungry,"food shared: -1 food, hunger gone")
	check(npc.memory.salience_for_subject(1,["AID_RECEIVED"]) == 500,"npc remembers the aid")
	check(not s.aid(npc),"no second helping")
	npc.hp = npc.max_hp/3; npc.hungry = false
	check(s.aid(npc) and npc.hp == npc.max_hp/3+10,"a wounded npc takes food as +10 hp")
	set_facets(npc,0,0) # would never accept on personality alone
	var answer: Dictionary = s.propose(npc)
	check(answer.accepted and npc.state == "PARTY" and s.party.size() == 2,"aided npc joins without a roll")
	# Aid works with a full party and the credit survives a floor.
	var g := solo(72,3); check(Recruit.can_aid(g.s,g.npc) == "도울 일이 없음" or g.s.party.size() == 3,"aid allowed at full party (only the join is blocked)")

func chance() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	set_facets(npc,500,500); check(Recruit.chance(s,npc) == 60,"base 60")
	set_facets(npc,1000,1000); check(Recruit.chance(s,npc) == 95,"capped at 95 (60+40)")
	set_facets(npc,0,0); check(Recruit.chance(s,npc) == 20,"60-40")
	npc.hp = npc.max_hp/3; check(Recruit.chance(s,npc) == 35,"+15 wounded")
	npc.hp = npc.max_hp; s.serial += 1; s.remember_important(npc,"DECLINED_BY_PLAYER",1,1,400)
	check(Recruit.chance(s,npc) == 0,"-25 after being declined, floored at 0")

func ask() -> void:
	var accepted := 0
	for seed in range(40):
		var f := solo(200+seed); var s = f.s; var npc: Dictionary = f.npc
		set_facets(npc,500,500)
		var answer: Dictionary = s.propose(npc)
		if answer.accepted: accepted += 1
		else:
			check(npc.memory.salience_for_subject(1,["DECLINED_PLAYER"]) == 300 and s.party[0].memory.salience_for_instigator(npc.id+1,["DECLINED_PLAYER"]) == 300,"both remember the refusal")
			check(not s.propose(npc).accepted and s.propose(npc).line == "지금은 아니야","cooldown: no re-ask for twenty rounds")
			s.round_number += 20
			check(Recruit.chance(s,npc) == 50,"re-ask after cooldown costs 10")
	check(accepted >= 14 and accepted <= 34,"about 60%% accept (%d/40)" % accepted)
	var same_a: Dictionary = solo(300); var same_b: Dictionary = solo(300)
	set_facets(same_a.npc,500,500); set_facets(same_b.npc,500,500)
	check(same_a.s.propose(same_a.npc).accepted == same_b.s.propose(same_b.npc).accepted,"deterministic per seed, round and npc")

func offer() -> void:
	var f := solo(); var s = f.s; var npc: Dictionary = f.npc
	set_facets(npc,900,500)
	check(s.offer(npc) and s.pending_offer == npc.id,"an npc can put an offer on the table")
	check(not s.offer(npc),"one offer at a time")
	check(s.answer_offer(false) and s.pending_offer < 0 and npc.state == "MET","declined offer clears")
	check(npc.memory.salience_for_subject(1,["DECLINED_BY_PLAYER"]) == 400 and s.round_number < npc.offered_until,"npc remembers, waits twenty rounds")
	check(not s.offer(npc),"no new offer inside the cooldown")
	s.round_number += 20
	check(s.offer(npc) and s.answer_offer(true) and npc.state == "PARTY" and s.party.size() == 2 and s.party[1] == npc and not (npc in s.npcs),"accepted offer recruits and leaves the npc list")
	check(npc.memory.salience_for_subject(1,["RECRUITED"]) == 500 and s.party[0].memory.salience_for_instigator(npc.id+1,["RECRUITED"]) == 500,"both remember the recruitment")
	check(s.formation.size() == 2 and s.formation[1] == 1,"joins the marching order last")

func full_party() -> void:
	var f := solo(73,3); var s = f.s; var npc: Dictionary = f.npc
	set_facets(npc,1000,1000)
	check(Recruit.dialogue(s,npc).line == "자리가 없군" and not Recruit.dialogue(s,npc).can_propose,"full party: no proposing")
	check(s.offer(npc) and not s.answer_offer(true) and s.party.size() == 3,"an offer to a full party cannot be accepted")

func duo_close() -> void:
	var f := solo(74); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	a.partner = b.id; b.partner = a.id; a.bond = "close"; b.bond = "close"
	b.pos = f.c+Vector2i(1,1); b.awake = true; b.hp = b.max_hp; s.npcs.append(b); s.floor_state.observe(s)
	set_facets(a,1000,1000)
	check(s.propose(a).accepted and s.party.size() == 3 and a.state == "PARTY" and b.state == "PARTY","a close pair joins together")
	var g := solo(75,2); var t = g.s; var c: Dictionary = g.npc
	var d: Dictionary = t.roster.filter(func(n): return n.id != c.id)[0]
	c.partner = d.id; d.partner = c.id; c.bond = "close"; d.bond = "close"
	d.pos = g.c+Vector2i(1,1); d.awake = true; d.hp = d.max_hp; t.npcs.append(d); t.floor_state.observe(t)
	set_facets(c,1000,1000)
	var answer: Dictionary = t.propose(c)
	check(not answer.accepted and answer.line == "얘를 두고는 못 가" and t.party.size() == 2,"one seat is not enough for a close pair")

func duo_strained() -> void:
	var f := solo(76); var s = f.s; var a: Dictionary = f.npc
	var b: Dictionary = s.roster.filter(func(n): return n.id != a.id)[0]
	a.partner = b.id; b.partner = a.id; a.bond = "strained"; b.bond = "strained"
	b.pos = f.c+Vector2i(1,1); b.awake = true; b.hp = b.max_hp; b.stress = 0; s.npcs.append(b); s.floor_state.observe(s)
	set_facets(a,1000,1000); var stress_a: int = a.stress
	check(s.propose(a).accepted and a.state == "PARTY" and b.state == "MET" and b in s.npcs,"a strained partner stays behind")
	check(b.memory.salience_for_subject(a.id+1,["LEFT_BY_PARTNER"]) == 600 and a.stress > stress_a,"the one left remembers; the leaver pays stress")

func kinds() -> void:
	var Memory = load("res://sim/party_memory_state.gd")
	for k in ["RECRUITED","DECLINED_BY_PLAYER","DECLINED_PLAYER","LEFT_BY_PARTNER"]: check(k in Memory.KINDS,"memory kind "+k)
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `npc_recruit.gd`.**

```gdscript
extends RefCounted
## Joining the party: aid is certain, the rest is personality.
const COOLDOWN := 20

static func can_aid(s, npc: Dictionary) -> String:
	if npc.hp <= 0 or npc.state != "MET": return "대상 아님"
	if not s.alive().any(func(a): return s.melee_reach(a.pos,npc.pos)): return "거리 초과"
	if not (bool(npc.get("hungry",false)) or npc.hp*100 < npc.max_hp*50): return "도울 일이 없음"
	if npc.memory.salience_for_subject(1,["AID_RECEIVED"]) > 0: return "이미 도왔음"
	if s.food < 1: return "식량 없음"
	return ""

static func aid(s, npc: Dictionary) -> bool:
	if not can_aid(s,npc).is_empty(): return false
	s.food -= 1
	if bool(npc.get("hungry",false)): npc.hungry = false
	else: npc.hp = mini(npc.max_hp,npc.hp+10)
	s.serial += 1; s.remember_important(npc,"AID_RECEIVED",1,1,500)
	s.message("%s에게 식량을 나눴습니다." % npc.name); return true

static func aided(npc: Dictionary) -> bool:
	return npc.memory.salience_for_subject(1,["AID_RECEIVED"]) > 0

static func chance(s, npc: Dictionary) -> int:
	var c: int = 60+(npc.profile.value("X")+npc.profile.value("A")-1000)/25
	if npc.hp*100 < npc.max_hp*50: c += 15
	if npc.memory.salience_for_subject(1,["DECLINED_BY_PLAYER"]) > 0: c -= 25
	if npc.memory.salience_for_subject(1,["DECLINED_PLAYER"]) > 0: c -= 10
	return clampi(c,0,95)

static func dialogue(s, npc: Dictionary) -> Dictionary:
	var full: bool = s.alive().size() >= 3
	var line: String = "자리가 없군" if full else ("고맙다. 같이 가지." if aided(npc) else "지금은 아니야" if s.round_number < int(npc.get("declined_until",-99)) else "무슨 일이지?")
	return {"line":line,"can_propose":not full and s.round_number >= int(npc.get("declined_until",-99)),"can_aid":can_aid(s,npc).is_empty(),"aided":aided(npc)}

static func propose(s, npc: Dictionary) -> Dictionary:
	var d := dialogue(s,npc)
	if not d.can_propose: return {"accepted":false,"line":d.line}
	if not aided(npc):
		var roll: int = s.Hexaco.sample(s.seed_value,s.NpcRoster.depth(s)*100000+s.round_number*100+npc.id,"recruit",100)
		if roll >= chance(s,npc):
			s.serial += 1
			s.remember_important(npc,"DECLINED_PLAYER",1,1,300)
			s.remember_important(s.party[0],"DECLINED_PLAYER",npc.id+1,npc.id+1,300)
			npc.declined_until = s.round_number+COOLDOWN
			return {"accepted":false,"line":"됐어."}
	return recruit(s,npc)

## The join itself, with the duo rules.
static func recruit(s, npc: Dictionary) -> Dictionary:
	if s.alive().size() >= 3 or npc.state != "MET": return {"accepted":false,"line":"자리가 없군"}
	var mate: Dictionary = {}
	for n in s.npcs:
		if n.id == int(npc.get("partner",-1)) and n.hp > 0: mate = n
	if not mate.is_empty() and npc.bond == "close":
		if s.alive().size() >= 2: return {"accepted":false,"line":"얘를 두고는 못 가"}
		join(s,npc); join(s,mate); return {"accepted":true,"line":"우리는 같이 간다."}
	if not mate.is_empty() and npc.bond == "strained":
		s.serial += 1; s.remember_important(mate,"LEFT_BY_PARTNER",npc.id+1,npc.id+1,600)
		s.stress(npc,10)
		s.message("%s이(가) %s을(를) 두고 떠납니다." % [npc.name,mate.name])
	join(s,npc); return {"accepted":true,"line":"좋아, 같이 가지."}

static func join(s, npc: Dictionary) -> void:
	s.npcs.erase(npc); npc.state = "PARTY"; npc.awake = false; npc.mode = ""; npc.activity = ""
	npc.ap = 0; npc.reservation = {}; npc.hit_and_run = false
	s.party.append(npc); s.formation.append(s.party.size()-1)
	s.serial += 1
	s.remember_important(npc,"RECRUITED",1,1,500)
	s.remember_important(s.party[0],"RECRUITED",npc.id+1,npc.id+1,500)
	s.battle_stats.members[npc.id] = {"dealt":0,"taken":0,"guards":0,"covers":0,"redirected":0,"parts":{},"healed":0,"downed":false,"conflict":false,"mistakes":0,"role_rounds":{"in_role":0,"total":0},"explains":[]}
	s.message("%s이(가) 동행합니다." % npc.name)
```

`session.gd`: `const Recruit = preload("res://expedition/npc_recruit.gd")`, `var pending_offer := -1`; `func aid(npc) -> bool: return Recruit.aid(self,npc)`; `func propose(npc) -> Dictionary: return Recruit.propose(self,npc)`; `func offer(npc) -> bool: if pending_offer >= 0 or npc.state != "MET" or round_number < int(npc.get("offered_until",-99)): return false; pending_offer = npc.id; return true`; `func answer_offer(accept: bool) -> bool: if pending_offer < 0: return false; var npc = npcs.filter(func(n): return n.id == pending_offer); pending_offer = -1; if npc.is_empty(): return false; var n = npc[0]; n.offered_until = round_number+Recruit.COOLDOWN; if not accept: serial += 1; remember_important(n,"DECLINED_BY_PLAYER",1,1,400); return true; return Recruit.recruit(self,n).accepted`; `func recruit(npc) -> bool: return Recruit.recruit(self,npc).accepted`. `party_memory_state.gd KINDS`에 4종 추가. 파티 인원이 늘면 `make_actor`의 이름 배열과 무관하므로 문제 없음; `formation`은 `range(count)` 기반이라 `append`로 확장. `member_stats`는 `battle_stats.members`에 행이 생겨야 집계된다(`join`이 넣는다).

- [ ] **Step 4: 실행 → 통과.** `recruit`, `npc_behaviour`, `autobattle`(파티 4명이 될 수 없음: `recruit`가 3 상한), `stances`.

- [ ] **Step 5: 커밋.** `feat(npc): recruitment — shared food is a promise, the rest is personality; duos join together or part`

---

### Task 6: UI·CI·리베이스·문서

**Files:**
- Modify: `expedition/board.gd`(NPC 토큰·이름표), `expedition/main.gd`(NPC 팝업, 제안 팝업, 결과 이력), `.github/workflows/deploy-pages.yml`(` npc_roster npc_sense npc_behaviour recruit`), `docs/superpowers/specs/2026-09-25-run-camp-npc-design.md`(상태), `docs/balance/utility-tuning.md`(NPC 모드 표 한 절)
- Test: `tests/recruit.gd`에 `scene()` 추가

**Interfaces:**
- Produces: 노드 `NpcPopup`(`ProposeButton`, `AidButton`, `CloseNpc`), `OfferPopup`(`OfferAccept`, `OfferDecline`), 보드 NPC 색 `Color("d8c98a")`와 이름표.

- [ ] **Step 1: 실패하는 테스트 — `tests/recruit.gd`에 추가**

```gdscript
func scene() -> void:
	var main = load("res://expedition/main.tscn").instantiate()
	root.add_child(main); await process_frame
	if main.session == null: main.new_run(); await process_frame   # Plan A start screen; before Plan A the session exists already
	var s = main.session; var c := Fixture.arena(s,12)
	var npc: Dictionary = s.npcs[0]; s.npcs = [npc]; npc.pos = c+Vector2i(1,0); npc.awake = true; npc.hungry = true; s.food = 2
	s.floor_state.observe(s); main.refresh(); await process_frame
	main.on_cell(npc.pos); await process_frame
	var names := func(node: Node) -> Array:
		var out: Array = []; var stack: Array = [node]
		while not stack.is_empty():
			var n: Node = stack.pop_back(); out.append(n.name)
			for ch in n.get_children(): stack.append(ch)
		return out
	var found: Array = names.call(main)
	check("NpcPopup" in found and "ProposeButton" in found and "AidButton" in found,"tapping an adjacent npc opens its popup with propose and aid")
	main.find_child("AidButton",true,false).pressed.emit(); await process_frame
	check(s.food == 1 and not npc.hungry,"aid button shares food")
	s.offer(npc); main.refresh(); await process_frame
	found = names.call(main)
	check("OfferPopup" in found and "OfferAccept" in found and "OfferDecline" in found,"a pending offer shows the offer popup")
	main.find_child("OfferAccept",true,false).pressed.emit(); await process_frame
	check(npc.state == "PARTY" and s.party.size() == 2,"accepting recruits")
	main.queue_free(); await process_frame
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 구현.**
- `board.gd`: 액터 루프에서 `actor.get("npc",false)`이면 스프라이트 `Art.ACTORS[actor.id % Art.ACTORS.size()]`, 테두리색 `Color("d8c98a")`, HP 바 색 `Color("d8c98a")`, 토큰 위에 이름 라벨(`actor.name`, 10pt)과 그 아래 활동 문구(`actor.activity`, 9pt, 비어 있으면 생략). 잠든 NPC(`awake == false`)는 시야 안에 있을 때만 그린다(파티 시야 `visible`); 깨어 있으면 시야 밖이어도 마지막 본 위치가 아니라 **현재 위치**를 흐리게(alpha 0.5) 그린다 — 설계 §5.3 "다가오는 장면".
- `main.gd on_cell`: 전투 중 아닐 때(`not session.in_combat()`), 탭한 칸에 `npc`가 있고 선택 멤버와 인접이면 `show_npc(npc)`; 비인접이면 카메라 초점만. `show_npc`: `NpcPopup`(details_popup 재사용, `modal_content.name = "NpcPopup"`은 불가하니 내부 VBox에 이름 부여) — 이름·성격 한 줄(`profile` STYLE_AXES의 high/low noun 두 개: X와 A)·활동 문구·HP·`Recruit.dialogue(session,npc).line`; 버튼 `ProposeButton`("동행 제안", `can_propose`) → `run_action(func(): var r = session.propose(npc); notice = r.line; return true)`; `AidButton`("식량 1 나누기 · 보유 %d", `can_aid`) → `run_action(func(): return session.aid(npc))`; `CloseNpc`.
- 제안 팝업: `refresh()`에서 `session.pending_offer >= 0`이면 `OfferPopup`(별도 `PopupPanel`, 이름 `OfferPopup`)을 띄운다: NPC 이름·대사(`dialogue.line`이 "자리가 없군"이면 그 문구)·`OfferAccept`("동행", 파티가 3명이면 비활성)·`OfferDecline`("거절"). 둘 다 `run_action(func(): return session.answer_offer(x))`. 제안 중에는 자동 진행을 멈춘다(`session.auto.running = false`, `stop_text = "%s이(가) 말을 겁니다" % name`).
- 결과 카드(Plan A `ResultCard`가 있으면 거기에, 없으면 `BattleReport`의 DEFEAT 카드에): 동료 이력 — `session.roster.filter(state in ["PARTY","DEAD"] and floor_seen > 0)` 각 "이름 · n층 합류 · 생존/전사".
- CI 목록에 ` npc_roster npc_sense npc_behaviour recruit`.

- [ ] **Step 4: 리베이스.** `git fetch origin main`. Plan A가 메인에 있으면(`expedition/npc_roster.gd`의 두 shim이 참조하는 `s.depth`·`layout.npc_rooms`가 존재하면) 리베이스 후 `NpcRoster.depth`는 `return int(s.depth)`, `npc_rooms`는 `return layout.npc_rooms`로 줄이고, `descend()`에 `NpcRoster.place(self)`를 넣고, 보스 층(`theme.boss`)이면 `place`가 빈 배열로 끝나는지 확인한다. Plan A가 아직 없으면 shim을 남기고 보고서에 적는다.

- [ ] **Step 5: 전체 CI 목록 + 임포트 검사.** `docs/balance/utility-tuning.md`에 "NPC 활동 모드" 절(표·유지·전환·검사 시드). 스펙 상태 줄을 "Plan B 구현됨"으로. 커밋 `feat(npc): npc tokens, dialogue and offer popups; companion history on the result`.

---

## 자기 검토

- 스펙 커버리지: §5.1 명부(T1) / §5.2 배치(T1) / §5.3 감각(T2) / §5.4 전투(T3)·활동 모드·2인 조·문구(T4) / §5.5 영입 세 갈래·2인 조 규칙·기억(T5) / §6 NPC 표시·팝업(T6) / §8 `npc_roster`·`npc_sense`·`npc_behaviour`·`recruit`(T1~T6).
- 이름 일관성: `s.npcs/roster/friends/noise/pending_offer/aid/propose/offer/answer_offer/recruit`, `NpcRoster.generate/place/depth/npc_rooms/situation/spawn_pack`, `NpcAI.sense/turn/perform/partner_of/nearest_member/explore_goal/LABELS/NOISE_RADIUS/SLEEP_AFTER`, `Modes.table/inputs/score_of/choose/COMMIT_ROUNDS/SWITCH_MARGIN`, `Recruit.can_aid/aid/aided/chance/dialogue/propose/recruit/join/COOLDOWN`, NPC 필드 `awake/mode/mode_until/hungry/partner/bond/state/floor_seen/activity/explains/noise_seen/declined_until/offered_until/situation`.
- 위험: (1) `friends()` 치환이 `stances.gd`의 후보 생성을 바꾸므로 113개 검사가 게이트다 — NPC가 없으면 `friends() == alive()`라 동치. (2) `combat_enemies()` 확장이 자동 정지·`in_combat`에 닿는다 — `party_threats`로 정지 이벤트를 파티 시야에 고정한다. (3) `Encounters.pack` 시그니처는 `encounter_builder.gd`를 읽고 맞춘다 — 없으면 만든다. (4) Plan A와의 병행: shim 두 개에 가둠.
