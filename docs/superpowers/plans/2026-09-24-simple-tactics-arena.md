# 전술 단순화 · 전투 시험 모드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 성격이 기본 전술이 되고 강제 태세는 실수 확률로만 드러나게 엔진을 바꾸고, 플레이어 UI를 태세 3버튼 + 적 탭 + 후퇴로 줄이며, 마을에서 탐험 없이 바로 들어가는 전투 시험 모드(파츠·태세 자유 설정)를 만든다.

**Architecture:** `Stances.mistake_chance/mistake_kind`가 성격·강제·스트레스에서 결정론 실수를 계산하고, `Tactics.choose`가 명령 뒤·후퇴선 앞에서 그것을 적용한다. 갈등 스트레스는 사라진다. UI는 걷어내기만 한다(세션 API 유지). 전투 시험은 `Session.arena_test()`가 시뮬 러너와 같은 경로(`Arena.layout` + `Floor.apply`)로 별도 세션을 만들고, 새 `arena_setup.gd`가 설정 화면을 그린다.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트, CI 목록 `.github/workflows/deploy-pages.yml`.

**Spec:** `docs/superpowers/specs/2026-09-24-simple-tactics-arena-design.md` — 충돌 시 스펙 우선.

## Global Constraints

- **Godot 창을 절대 띄우지 않는다.** `--headless`만. 임포트 검사 `godot --headless --path . --editor --import --quit`.
- 커밋 `git -c user.name=jinha1226 -c user.email=jinha1226@gmail.com commit -m "…"` + 빈 줄 + `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. 떠돌이 `.import` 금지.
- 엔진 API(`set_knob/set_protect/swap_formation/update_rule/reset_rules`)는 남긴다. UI만 걷어낸다. 세션 층 테스트는 그대로 통과.
- 실수 판정은 결정론(`Hexaco.sample`)이며 시뮬 경로(`auto_step`)에서도 같은 코드가 돈다.
- 파츠 수치 불변. `solo_balance` ≥ 3/8 유지(미달이면 `mistake_chance`의 `base` 상수만, 한 번).
- 전투 시험 세션은 본 세션의 가방·자금·파티를 절대 건드리지 않는다.
- 테스트 러너 규약: `extends SceneTree`, `_initialize()`→`call_deferred("run")`, `quit(1 if failures else 0)`, 마지막 줄 `print("<이름>: %d checks, %d failures")`.

---

### Task 1: 실수 확률 · 갈등 제거 · 기본값 자동

**Files:**
- Modify: `expedition/stances.gd` (`mistake_chance`, `mistake_kind`, `effective` 단순화), `expedition/knobs.gd` (`effective` 단순화), `expedition/tactical_action_selector.gd` (실수 단계), `expedition/session.gd` (`open_battle_conflicts` 축소, `battle_stats.members[].mistakes`, `auto.stops` 기본값), `tests/stances.gd` (`mistakes()`), `tests/autobattle.gd` (갈등·불안 검사 조정)

**Interfaces:**
- Produces: `Stances.mistake_chance(actor) -> int`, `Stances.mistake_kind(actor) -> String` (`"REVERT"|"HESITATE"|"RECKLESS"`), `Stances.mistaken(s, actor) -> bool` (시드 판정), `Tactics.choose` 실수 분기, `battle_stats.members[id].mistakes`, `AUTO_STOP_DEFAULTS`.

- [ ] **Step 1: 실패하는 테스트 — `tests/stances.gd`에 `mistakes()` 추가**

```gdscript
func mistakes() -> void:
	var s = Session.new(731,true,true,true,3)
	var hero: Dictionary = s.party[0]
	# Base chance from conscientiousness; forcing adds up to 20; stress multiplies; cap 40.
	hero.profile = profile({"C":1000,"X":900,"E":100}); hero.stance = "CHARGER"; hero.stress = 0
	check(Stances.mistake_chance(hero) == 4,"C 1000 charger at ease: 4%")
	hero.profile = profile({"C":0,"X":900,"E":100})
	check(Stances.mistake_chance(hero) == 20,"C 0: 20%")
	hero.stance = "GUARDIAN"   # aptitude 800 vs 0 → gap 800 → +20
	check(Stances.mistake_chance(hero) == 40 and Stances.mistake_kind(hero) == "REVERT","forced far outside: +20, reverts to its own stance")
	hero.stance = "CHARGER"; hero.stress = 120
	check(Stances.mistake_chance(hero) == 30,"anxious: x1.5")
	hero.stress = 160
	check(Stances.mistake_chance(hero) == 40,"collapsed: x2 capped at 40")
	hero.stress = 0
	check(Stances.mistake_kind(hero) == "RECKLESS","bold at ease: reckless mistakes")
	hero.profile = profile({"C":500,"X":100,"E":900}); hero.stance = "SKIRMISHER"
	check(Stances.mistake_kind(hero) == "HESITATE","timid at ease: hesitation")
	# Deterministic per seed/round/member.
	s.depart()
	var a := Stances.mistaken(s,hero); var b := Stances.mistaken(s,hero)
	check(a == b,"same round, same answer")
	# Behaviour: a hesitating member WAITs on a mistake round; retreat line still wins.
	var f := field(["SKIRMISHER","CHARGER","CHARGER"]); var t = f.s; var h: Dictionary = t.party[0]
	h.profile = profile({"C":0,"X":100,"E":900}); h.knobs = Knobs.defaults(h.profile); h.knobs.retreat_hp = 0
	t.mistake_override = {h.id: true}   # test hook: force the roll
	check(t.Tactics.choose(t,h).kind == "WAIT","hesitation is a WAIT")
	h.hp = 5; h.knobs.retreat_hp = 50
	check(t.Tactics.choose(t,h).kind == "MOVE","below the retreat line the mistake never overrides retreating")
	h.hp = h.max_hp; h.knobs.retreat_hp = 0
	h.profile = profile({"C":0,"X":900,"E":100}); h.knobs = Knobs.defaults(h.profile); h.knobs.retreat_hp = 0
	f.foes[0].pos = h.pos+Vector2i(1,0); t.intents = [{"id":f.foes[0].id,"cell":h.pos,"damage":9,"kind":""}]; f.foes[0].charging = true
	t.floor_state.observe(t)
	check(t.Tactics.choose(t,h).kind == "ATTACK","reckless: attacks from the telegraphed cell even as a skirmisher")
	h.stance = "GUARDIAN"  # far outside → REVERT to CHARGER
	t.intents = []; f.foes[0].charging = false
	check(t.Tactics.choose(t,h).reason.begins_with("돌격"),"revert: acts on its own stance")
	t.mistake_override = {}
	# No conflict stress any more.
	var d := skirmish_for_conflict()
	check(d.hero.stress == d.before and d.hero.memory.records.size() == d.memories,"forcing a stance costs no stress and leaves no memory")
	check(d.s.battle_stats.members[d.hero.id].has("mistakes"),"battle stats count mistakes")
	check(d.s.auto.stops == {"BATTLE_START":true,"ALLY_LETHAL":false,"HP_LOW":false,"DEATH":true,"BATTLE_END":true},"fixed stop defaults")

func skirmish_for_conflict() -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8); Fixture.equip_basics(s)
	var hero: Dictionary = s.party[0]
	hero.profile = profile({"X":900,"E":100,"C":1000}); hero.knobs = Knobs.defaults(hero.profile); hero.stance = "GUARDIAN"; hero.stress = 0
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = c+Vector2i(3,0)
	s.floor_state.observe(s); s.auto.prev_threats = 0
	var before: int = hero.stress; var memories: int = hero.memory.records.size()
	s.auto_stop_reason()
	return {"s":s,"hero":hero,"before":before,"memories":memories}
```

`t.mistake_override`는 세션의 테스트 훅(`var mistake_override: Dictionary = {}` — `{actor_id: bool}`이 있으면 시드 대신 그 값). 시뮬은 비워 둔다.

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `stances.gd`**

```gdscript
const MISTAKE_CAP := 40

static func mistake_chance(actor: Dictionary) -> int:
	var profile = actor.profile
	var chance: int = 4+(1000-profile.value("C"))/60
	var chosen: String = str(actor.get("stance",default_stance(profile)))
	if not comfortable(profile,chosen):
		var apt := aptitude(profile)
		chance += mini(20,(int(apt[default_stance(profile)])-int(apt[chosen]))/40)
	if int(actor.stress) >= 150: chance = chance*2
	elif int(actor.stress) >= 100: chance = chance*3/2
	return mini(MISTAKE_CAP,chance)

## What a mistake looks like: a forced member falls back to its own stance;
## otherwise the timid hesitate and the bold overreach.
static func mistake_kind(actor: Dictionary) -> String:
	var profile = actor.profile
	if not comfortable(profile,str(actor.get("stance",default_stance(profile)))): return "REVERT"
	return "HESITATE" if profile.value("E") >= profile.value("X") else "RECKLESS"

## Deterministic roll: one answer per expedition, round and member.
static func mistaken(s, actor: Dictionary) -> bool:
	if s.mistake_override.has(actor.id): return bool(s.mistake_override[actor.id])
	if not s.floor_mode: return false
	return s.Hexaco.sample(s.seed_value,s.expedition_number*100000+s.round_number*100+actor.id,"mistake",100) < mistake_chance(actor)

static func effective(actor: Dictionary) -> String:
	return str(actor.get("stance",default_stance(actor.profile)))
```

`Knobs.effective(actor)`는 `actor.knobs`를 그대로 돌려준다(불안 대체 삭제).

- [ ] **Step 4: `Tactics.choose` 삽입** — 명령 처리는 호출자(`auto_step`)가 하므로 `choose` 시작, `low` 계산 뒤:

```gdscript
	if not low and Stances.mistaken(s,actor):
		s.note_mistake(actor)
		match Stances.mistake_kind(actor):
			"HESITATE": return {"kind":"WAIT","cell":actor.pos,"reason":"머뭇거림"}
			"RECKLESS":
				var bold := knobs.duplicate(); bold.posture = 100
				var reckless := Stances.candidates(s,actor,"CHARGER",bold)
				if not reckless.is_empty(): reckless.sort_custom(rank); var pick: Dictionary = reckless[0]; pick.reason = "무모함 · "+str(pick.reason); return pick
			"REVERT": stance = Stances.default_stance(actor.profile)
```
(REVERT는 아래 태세 단계로 이어진다.) `session.note_mistake(actor)`: `battle_stats.members[id].mistakes += 1`, 로그 "%s · %s" (머뭇거림/무모함/자기 방식대로), 전투당 첫 실수만 로그.

- [ ] **Step 5: `session.gd`** — `var mistake_override: Dictionary = {}`; `reset_battle_stats` 멤버 행에 `"mistakes":0`; `open_battle_conflicts`는 `actor.conflicted = Knobs.conflicted(actor)`만 남기고 스트레스·기억·메시지 삭제(함수 이름 유지); `auto.stops` 기본 `{"BATTLE_START":true,"ALLY_LETHAL":false,"HP_LOW":false,"DEATH":true,"BATTLE_END":true}`; `Knobs.effective`/`Stances.effective` 호출부는 그대로.
- `tests/autobattle.gd`: "conflict costs stress" 계열 검사와 "anxious member falls back" 검사를 새 규칙(스트레스 없음, 불안은 실수 배수)으로 바꾼다; `stops()`의 ALLY_LETHAL/HP_LOW 검사는 해당 스톱을 켠 뒤 수행. `tests/stances.gd data()`의 갈등 스트레스 검사도 제거(`mistakes()`가 대체).

- [ ] **Step 6: 실행** — `stances autobattle protect companion_tactics encounter_sim parts solo_balance skill_rule_conditions mobile_hud ui_smoke` 통과(`solo_balance` ≥ 3/8; 미달이면 `base` 상수 한 번 조정 후 보고).

- [ ] **Step 7: 커밋** — `feat(tactics): personality-driven mistakes replace conflict stress`

---

### Task 2: UI 다이어트

**Files:**
- Modify: `expedition/character_ui.gd` (성격 탭·파츠 탭), `expedition/main.gd` (전투 HUD), `expedition/battle_hud.gd` (결과 카드), `tests/autobattle.gd ui()`, `tests/stances.gd ui()`, `tests/parts.gd ui()`, `tests/character_ui.gd`, `tests/mobile_hud.gd`, `tests/mobile_actions.gd`

- [ ] **Step 1: 실패하는 테스트 — `tests/stances.gd ui()`를 새 UI에 맞게 재작성(제거 위젯이 없음을 단언)**

```gdscript
	# Diet: no knob sliders, no protect picker, no aptitude bars; three stance buttons and the mistake line remain.
	check(scene.modal_content.find_children("Knob_*","HSlider",true,false).is_empty() and scene.modal_content.find_child("ProtectPick",true,false) == null and scene.modal_content.find_children("Aptitude_*","Control",true,false).is_empty(),"knob sliders, protect picker and aptitude bars are gone")
	check(scene.modal_content.find_children("Stance_*","Button",true,false).size() == 3,"three stance buttons")
	var mistake: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("실수 확률"))
	check(mistake.size() == 1,"mistake chance line")
	# Battle HUD: no command bar, formation or options; retreat toggle present.
	check(scene.find_child("CommandBar",true,false) == null and scene.find_child("FormationButton",true,false) == null and scene.find_child("AutoOptions",true,false) == null,"command bar, formation and options are gone")
	var retreat: Button = scene.find_child("RetreatToggle",true,false)
	check(retreat != null,"retreat toggle")
	retreat.pressed.emit(); await process_frame
	check(s.party_command == "RETREAT","retreat toggle sets the command")
	retreat.pressed.emit(); await process_frame
	check(s.party_command == "FOLLOW","pressing again returns to follow")
```
`tests/parts.gd ui()`의 규칙 방침 버튼 검사, `tests/autobattle.gd ui()`의 `CommandBar`/`AutoOptions`/`Knob_*` 검사, `tests/character_ui.gd`·`mobile_hud`·`mobile_actions`의 해당 검사는 삭제하거나 새 위젯으로 바꾼다. 세션 층 검사(`set_knob` 등)는 유지.

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 구현** — 스펙 §2 표 그대로. 성격 탭: `knobs()` 호출 제거(함수는 삭제), `stances()`에서 적성 막대·`ProtectPick` 제거, 태세 버튼 툴팁 "실수 확률 n%", 카드 끝에 "실수 확률 n% · <가장 큰 원인>"(성실 낮음/태세 강제/불안). 파츠 탭: 규칙 방침 버튼·자동 토글 제거. 전투 HUD: `CommandBar`·`FormationButton`·⚙ 제거, `RetreatToggle`("후퇴"/"후퇴 해제") 추가 — `party_command = "RETREAT"` ↔ `"FOLLOW"`, 진행 중에도 누를 수 있게(명령은 즉시 반영). 결과 카드: "갈등" → "실수 %d".

- [ ] **Step 4: 실행** — `stances autobattle parts character_ui mobile_hud mobile_actions mobile_exploration test_loadout abilities_growth ui_smoke integration playthrough` 통과. 임포트 오류 0.

- [ ] **Step 5: 커밋** — `feat(ui): accessibility diet — stances, retreat and the report only`

---

### Task 3: 전투 시험 모드

**Files:**
- Create: `expedition/arena_setup.gd`, `tests/arena_mode.gd`
- Modify: `expedition/session.gd` (`arena_test`), `expedition/settlement_hub.gd` (`TownArena`), `expedition/main.gd` (모드 전환·결과 카드 버튼), `expedition/battle_hud.gd` (결과 카드 "설정으로/다시"), `.github/workflows/deploy-pages.yml` (`arena_mode`)

**Interfaces:**
- Produces: `Session.arena_test(seed: int, party_size: int, arena: Dictionary, members: Array) -> Session` (static; `arena = {"members": [[species, role], …], "light": 90}`), `Session.ARENA_PRESETS` (balance_experiments의 6개 + `custom`), `main.arena_config`, `main.show_arena_setup()`, `main.start_arena()`, `main.leave_arena()`; 노드 `TownArena`, `ArenaSetup`, `ArenaPick`, `ArenaSeed`, `ArenaSize`, `ArenaMember%d`, `ArenaStance_%d_<ID>`, `ArenaPart_%d_%d`, `ArenaFoe%d`, `ArenaStart`, `ArenaBack`.

- [ ] **Step 1: 실패하는 테스트 — `tests/arena_mode.gd`**

```gdscript
extends SceneTree
## Battle test mode: a throwaway session dropped straight into an arena with
## freely chosen parts and stances; the town session is never touched.
const Session = preload("res://expedition/session.gd")
const Abilities = preload("res://expedition/abilities.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	session()
	await scene()
	print("Arena mode: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func session() -> void:
	check(Session.ARENA_PRESETS.size() == 7 and Session.ARENA_PRESETS.has("early_hob") and Session.ARENA_PRESETS.has("custom"),"six presets plus custom")
	var members := [{"stance":"CHARGER","parts":["HOB_CLUB","GUARD"]},{"stance":"SKIRMISHER","parts":["KOBOLD_SLING",""]},{"stance":"GUARDIAN","parts":["PUSH","GUARD"]}]
	var t = Session.arena_test(42,3,Session.ARENA_PRESETS.opt_archers,members)
	check(t.floor_mode and t.phase == "BATTLE" and t.party.size() == 3 and t.in_combat(),"arena session is a floor battle")
	check(t.enemies.size() == 3 and t.enemies.all(func(e): return e.hp > 0),"opt_archers roster spawned")
	check(t.party[0].stance == "CHARGER" and t.party[0].equipped_abilities == ["HOB_CLUB","GUARD"] and t.party[0].rules.any(func(r): return r.skill == "HOB_CLUB"),"member setup applied with default rules")
	check(t.party[1].equipped_abilities == ["KOBOLD_SLING",""],"empty slot allowed")
	check(t.party.all(func(a): return a.hp == a.max_hp),"full health")
	check(t.auto_stop_reason() == "BATTLE_START","starts stopped at battle start")
	var rounds := 0
	while t.in_combat() and rounds < 60: t.auto_step(); rounds += 1
	check(rounds > 0 and rounds < 60,"the fight resolves")
	var custom := {"members":[["dcss_rat","MELEE"],["goblin","CASTER"]],"light":40}
	var c = Session.arena_test(7,1,custom,[{"stance":"CHARGER","parts":["PUSH",""]}])
	check(c.enemies.size() == 2 and c.light == 40 and c.party.size() == 1,"custom roster, light and party size")
	check(Session.arena_test(42,3,Session.ARENA_PRESETS.opt_archers,members).enemies[0].pos == t.enemies[0].pos,"same seed, same layout")
	# Solo guardian is coerced to charger.
	var g = Session.arena_test(1,1,Session.ARENA_PRESETS.early_hob,[{"stance":"GUARDIAN","parts":["",""]}])
	check(g.party[0].stance == "CHARGER","solo cannot test as a guardian")

func scene() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var town = Session.new(731,true,true,true,3)
	scene.session = town; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(3): await process_frame
	var bag: Dictionary = town.parts_bag.duplicate(true); var bank: int = town.bank
	var button: Button = scene.find_child("TownArena",true,false)
	check(button != null and button.text == "전투 시험","town offers the battle test")
	button.pressed.emit()
	for frame in range(3): await process_frame
	var setup = scene.find_child("ArenaSetup",true,false)
	check(setup != null,"setup screen")
	check(scene.find_child("ArenaPick",true,false).item_count == 7 and scene.find_child("ArenaSize",true,false) != null,"arena picker and party size")
	check(scene.find_children("ArenaMember*","Control",true,false).size() == 3,"three member cards")
	var part0 = scene.find_child("ArenaPart_0_0",true,false)
	check(part0 != null and part0.item_count == Abilities.DEFINITIONS.size()+1,"part picker lists every catalog part plus empty")
	scene.find_child("ArenaStance_0_SKIRMISHER",true,false).pressed.emit(); await process_frame
	check(scene.arena_config.members[0].stance == "SKIRMISHER","stance choice recorded")
	scene.find_child("ArenaStart",true,false).pressed.emit()
	for frame in range(4): await process_frame
	check(scene.session != town and scene.session.floor_mode and scene.session.in_combat(),"start swaps in an arena session")
	check(scene.find_child("AutoToggle",true,false) != null and scene.find_child("StopBanner",true,false).text.begins_with("전투 시작"),"battle HUD with the start banner")
	scene.session.auto.running = true
	var guard := 0
	while scene.session.in_combat() and guard < 80: scene.auto_tick(); guard += 1
	for frame in range(4): await process_frame
	var report = scene.find_child("BattleReport",true,false)
	check(report != null and report.visible,"report at the end")
	var buttons: Array = report.find_children("*","Button",true,false).map(func(b): return b.text)
	check("설정으로" in buttons and "다시" in buttons,"report offers setup and retry")
	scene.leave_arena()
	for frame in range(3): await process_frame
	check(scene.session == town and town.parts_bag == bag and town.bank == bank and town.phase == "TOWN","town session untouched")
	scene.queue_free(); await process_frame
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `Session.arena_test`**

```gdscript
static var ARENA_PRESETS: Dictionary = load_arena_presets()

static func load_arena_presets() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/balance_experiments.json"))
	var result: Dictionary = {}
	for id in data.experiments.action_economy.arenas:
		var row: Dictionary = data.experiments.action_economy.arenas[id]
		result[id] = {"members":row.members.duplicate(true),"light":int(row.get("light",90)),"label":id}
	result["custom"] = {"members":[],"light":90,"label":"직접 구성"}
	return result

## A throwaway floor battle: full health, every part available, the members'
## stances and slots set as asked, dropped into an arena the simulator also
## uses. The town session is never involved.
static func arena_test(p_seed: int, party_size: int, arena: Dictionary, members: Array):
	var s = new(p_seed,true,party_size > 1,true,party_size)
	s.grant_test_loadout()
	for i in range(s.party.size()):
		var actor: Dictionary = s.party[i]
		var setup: Dictionary = members[i] if i < members.size() else {}
		var stance: String = str(setup.get("stance",actor.stance))
		if stance == "GUARDIAN" and party_size == 1: stance = "CHARGER"
		if stance in Stances.IDS: actor.stance = stance
		actor.equipped_abilities = ["",""]; actor.rules = []
		var parts: Array = setup.get("parts",["",""])
		for slot in range(2):
			var id: String = str(parts[slot]) if slot < parts.size() else ""
			if Abilities.DEFINITIONS.has(id) and id not in actor.equipped_abilities:
				actor.equipped_abilities[slot] = id; actor.rules.append(Abilities.default_rule(id))
	var spec: Dictionary = preload("res://expedition/sim/encounter_arena.gd").DEFAULT_SPEC.duplicate(true)
	spec.members = arena.members.map(func(m): return {"species_id":m[0],"role":m[1]})
	spec.light = int(arena.get("light",90))
	var theme: Dictionary = preload("res://expedition/floor_generator.gd").theme("F1_RUINS")
	s.light = spec.light
	Floor.apply(s,theme,preload("res://expedition/sim/encounter_arena.gd").layout(spec,theme,p_seed))
	s.reset_battle_stats()
	s.auto.prev_threats = 0
	return s
```
(시뮬 러너 `run_one`의 아레나 배치 코드와 같은 순서. `Floor.apply`가 `phase = "BATTLE"`·파티 배치를 한다. `encounter_arena`/`floor_generator`의 정확한 preload 경로·`theme()` 이름은 `encounter_runner.gd`에서 복사.)

- [ ] **Step 4: 설정 화면 `expedition/arena_setup.gd`** (`static func build(ui) -> Control`, `main.gd`의 `root_layout`에 붙임; 위 노드 이름 그대로). 멤버 카드는 `ui.arena_config.members[i]`를 읽고 쓴다(`{"stance","parts"}`), 아레나 `ArenaPick` 선택 → `arena_config.arena`, `ArenaSeed`(SpinBox) · "고정" CheckButton(`arena_config.fixed_seed`), `ArenaSize`(OptionButton 1~3 → 카드 수 갱신). `custom`이면 `ArenaFoe0..2`(OptionButton "없음" + 종족×역할 24개). `ArenaStart` → `ui.start_arena()`, `ArenaBack` → `ui.leave_arena()`.
- `main.gd`: `var town_session = null; var arena_config := {"arena":"early_hob","seed":0,"fixed_seed":false,"size":3,"members":[…3개 기본],"custom":[["","" ],…]}`; `show_arena_setup()` (마을 화면 대신 `ArenaSetup` 그리기, `mode_arena_setup = true`), `start_arena()` (`town_session = session`(처음 한 번), `session = Session.arena_test(...)`, `refresh()`, `check_stop()`로 배너), `leave_arena()` (`session = town_session; town_session = null; refresh()`), 결과 카드 버튼 "설정으로"(`show_arena_setup()`)·"다시"(`start_arena()` 새 시드 — `fixed_seed`면 같은 시드). 시험 세션에서 전멸(DEFEAT)해도 결과 카드로 끝나고 `refresh`가 마을을 그리지 않게 `session != town_session`이면 마을 분기를 막는다.
- `settlement_hub.gd`: `TownArena` 버튼 "전투 시험" (시험 로드아웃 옆, 같은 디버그 그룹).

- [ ] **Step 5: 실행** — `arena_mode stances autobattle test_loadout mobile_hud ui_smoke integration playthrough parts` 통과. CI 목록에 ` arena_mode`. 임포트 오류 0.

- [ ] **Step 6: 커밋** — `feat(arena): battle test mode from town with free parts and stances`

---

## 자기 검토

- 스펙 커버리지: §1.1~1.4(T1) / §2(T2) / §3.1~3.3(T3) / §4(T1·T3 테스트, 게이트 미재측정 명시).
- 이름 일관성: `mistake_chance/mistake_kind/mistaken/mistake_override/note_mistake/mistakes`, `RetreatToggle`, `arena_test/ARENA_PRESETS/arena_config/show_arena_setup/start_arena/leave_arena`, `TownArena/ArenaSetup/ArenaPick/ArenaSeed/ArenaSize/ArenaMember%d/ArenaStance_%d_<ID>/ArenaPart_%d_%d/ArenaFoe%d/ArenaStart/ArenaBack`.
- 위험: T1이 `Knobs.effective`/`Stances.effective`의 불안 대체를 없애므로 기존 `autobattle.gd knobs()`의 "anxious member falls back" 검사를 바꿔야 한다(계획에 명시).
