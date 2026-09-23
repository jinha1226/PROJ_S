# 오토배틀 전환 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 층 모드 전투를 규칙 엔진이 자동으로 굴리고(정지 이벤트에서 멈춤), 플레이어는 명령·아이템·진형으로만 개입하며, 성격에서 나온 성향 노브와 전투 결과 화면으로 "왜 졌는지 → 무엇을 바꿀지"를 잇는다.

**Architecture:** `session.auto_step()` 한 함수가 한 라운드(파티 전원 규칙 행동 → `end_round`)를 진행하고, 게임 UI 타이머와 시뮬 봇이 **같은 함수**를 호출한다. 정지 이벤트는 `session.auto_stop_reason()`이 라운드 시작 시점에 판정한다. 성향 노브는 `Tactics.choose`의 후보 점수를 조정하고, 기본값·편안 범위는 새 파일 `knobs.gd`가 HEXACO에서 계산한다. 계측은 `session.battle_stats` 하나로 모아 결과 카드와 시뮬 러너가 같이 읽는다. 구 방 모드·보스 시련의 수동 조작은 손대지 않는다.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트, CI 목록 `.github/workflows/deploy-pages.yml`.

**Spec:** `docs/superpowers/specs/2026-09-23-autobattle-design.md` — 충돌 시 스펙 우선.

## Global Constraints

- **Godot 창을 절대 띄우지 않는다.** 모든 실행은 `--headless`. 임포트 검사 `godot --headless --path . --editor --import --quit`.
- 커밋: `git -c user.name=jinha1226 -c user.email=jinha1226@gmail.com commit -m "…"`, 메시지 끝에 빈 줄 + `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. 떠돌이 `.import`/`.uid` 파일을 커밋하지 않는다.
- 게임과 시뮬은 같은 `auto_step`을 쓴다. 시뮬 전용 전투 로직을 새로 만들지 않는다.
- 스킬별·종족별 분기 0줄 원칙 유지. 노브·명령은 후보 점수와 `party_command` 분기로만 작동한다.
- 수치(스펙 §1.2 정지 규칙, §1.3 타이머, §3.2 점수, §3.3 공식)는 스펙 그대로. 조정은 Task 6 게이트 결과로만.
- 층 모드에서는 전투 중 `phase == "BATTLE"`이 탐색과 전투에 공통이다. "전투 중"은 `not floor_state.safe(self)`이다.
- 각 태스크 끝에 해당 스위트 + `parts protect companion_tactics skill_rule_conditions solo_floor encounter_sim ui_smoke mobile_actions`가 통과해야 한다(본문에 명시된 예외 제외). 최종적으로 CI 목록 전체 통과.
- 테스트 러너 규약: `extends SceneTree`, `_initialize()`에서 `call_deferred("run")`, 실패 수를 세어 `quit(1 if failures else 0)`, 마지막 줄 `print("<이름>: %d checks, %d failures")`.

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `expedition/session.gd` | `act_as`, `auto`, `auto_step`, `auto_stop_reason`, `command_choice`, `battle_stats`, 갈등 판정 호출, 진형 교환 |
| `expedition/knobs.gd` (신규) | 노브 기본값·편안 범위·갈등 판정·유효 노브(불안/붕괴 대체) |
| `expedition/tactical_action_selector.gd` | `KNOB` 상수, 노브 점수, 후퇴선 |
| `expedition/continuous_floor.gd` | 행군 순서 기반 `follow` |
| `expedition/sim/bot_policy.gd`, `sim/encounter_runner.gd`, `data/content/reference_builds.json` | `auto_step` 통합, `knobs` 빌드 |
| `expedition/main.gd`, `character_ui.gd`, `board.gd` | 전투 HUD, 성향 탭, 결과 카드, 옵션 |
| `tests/autobattle.gd` (신규), 기존 스위트, CI 목록 | 검증 |
| `docs/balance/autobattle-gates.md` | G1~G6 |

---

### Task 1: `auto_step` · 정지 이벤트 · 전원 명령

**Files:**
- Modify: `expedition/session.gd` (`act`, `finish_player_action`, `companion_choice` → `command_choice`, 새 `auto` 상태·`auto_step`·`auto_stop_reason`·`act_as`), `expedition/tactical_action_selector.gd`(변경 없음 확인)
- Test: `tests/autobattle.gd` (신규)

**Interfaces:**
- Produces: `session.act_as(actor, kind, cell, chain := true) -> bool`; `session.auto_step() -> bool`; `session.auto: Dictionary`; `session.AUTO_STOPS`; `session.auto_stop_reason() -> String`; `session.command_choice(actor) -> Dictionary`; `session.in_combat() -> bool`.
- Consumes: 기존 `Tactics.choose`, `party_command`, `floor_state.safe/follow`, `end_round`.

- [ ] **Step 1: 실패하는 테스트 — `tests/autobattle.gd` 골격 + `auto()` + `stops()` + `commands()`**

```gdscript
extends SceneTree
## Autobattle: one rules-driven round per auto_step, stop events, party-wide
## commands, knobs from personality, battle stats and the marching order.
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	auto()
	stops()
	commands()
	print("Autobattle: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Three members with the basics equipped, one revived melee foe next to the hero.
func skirmish(foes: int = 1) -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	Fixture.equip_basics(s)
	var revived: Array = []
	for i in range(foes):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false
		foe.cast_recovery = 0; foe.part_id = ""; foe.pos = c+Vector2i(2+i,0)
		revived.append(foe)
	s.party[1].pos = c+Vector2i(0,1); s.party[2].pos = c+Vector2i(0,2)
	s.floor_state.observe(s); s.selected = 0
	for actor in s.party: actor.ap = 1
	return {"s":s,"c":c,"hero":s.party[0],"foes":revived}

func auto() -> void:
	var d := skirmish(); var s = d.s
	check(s.in_combat(),"a visible foe means combat")
	var round_before: int = s.round_number
	var log_before: int = s.log_lines.size()
	check(s.auto_step(),"auto_step runs")
	check(s.round_number == round_before+1,"one round per auto_step")
	check(s.party.all(func(a): return a.ap == s.action_budget(a)),"everyone acted and the round reset AP")
	check(s.party.all(func(a): return a.last_action != "대기" or true),"last_action recorded")
	check(s.log_lines.size() > log_before,"actions were logged")
	# The hero is rule-driven like everyone else: adjacent foe → basic attack.
	d = skirmish(); s = d.s
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	var hp: int = d.foes[0].hp
	s.auto_step()
	check(d.foes[0].hp < hp,"the hero attacked through the rules")
	# Outside combat auto_step does nothing.
	d = skirmish(0); s = d.s
	check(not s.in_combat() and not s.auto_step(),"no auto round while safe")
	# Solo: one action, one round.
	var solo = Session.new(731,true,false,true,1); solo.depart()
	var c := Fixture.arena(solo,8); Fixture.equip_basics(solo)
	var foe: Dictionary = solo.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = c+Vector2i(1,0)
	solo.floor_state.observe(solo); solo.party[0].ap = 1
	hp = foe.hp; round_before = solo.round_number
	check(solo.auto_step() and foe.hp < hp and solo.round_number == round_before+1,"solo hero acts once per round")
	# Non-floor modes are untouched: auto_step refuses.
	var legacy = Session.new(731,true,true)
	check(not legacy.auto_step(),"auto_step is floor-mode only")

func stops() -> void:
	var d := skirmish(0); var s = d.s
	check(s.auto.stops.BATTLE_START and s.auto.stops.BATTLE_END and s.auto.hp_low == 30,"defaults")
	check(s.auto_stop_reason() == "","nothing to stop for while safe")
	d.foes = [s.enemies[0]]; var foe: Dictionary = d.foes[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = d.c+Vector2i(3,0)
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START","first visible foe stops for battle start")
	s.auto_step()
	check(s.auto_stop_reason() != "BATTLE_START","battle start fires once")
	# Lethal threat on an ally.
	foe.pos = d.c+Vector2i(0,3); s.party[2].hp = 5; s.floor_state.observe(s)
	check(s.auto_stop_reason() == "ALLY_LETHAL","a member who would die this round stops the run")
	s.auto_step()
	s.party[2].hp = 5
	check(s.auto_stop_reason() != "ALLY_LETHAL","same reason is suppressed for three rounds")
	# HP low fires when a member newly crosses the line.
	d = skirmish(); s = d.s
	s.auto_step()
	s.party[1].hp = int(s.party[1].max_hp*0.3)
	check(s.auto_stop_reason() == "HP_LOW","member at 30% stops")
	s.auto.stops.HP_LOW = false
	check(s.auto_stop_reason() != "HP_LOW","disabled stop is ignored")
	s.auto.stops.HP_LOW = true
	# Death and battle end.
	d = skirmish(); s = d.s; s.auto_step()
	s.party[2].hp = 1; d.foes[0].pos = d.c+Vector2i(1,2); s.floor_state.observe(s)
	s.auto_step()
	check(s.party[2].hp <= 0 and s.auto_stop_reason() == "DEATH","a downed member stops the run")
	s.auto_step()
	d.foes[0].hp = 0; s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_END","no foes left stops for battle end")
	check(s.auto.stops_log.back() == "BATTLE_END","stops are logged for the battle report")

func commands() -> void:
	var d := skirmish(); var s = d.s
	d.foes[0].pos = d.c+Vector2i(3,0); s.floor_state.observe(s)
	s.party_command = "HOLD_POSITION"
	var pos: Vector2i = d.hero.pos
	s.auto_step()
	check(d.hero.pos == pos and s.party.all(func(a): return a.pos.x <= d.c.x),"hold position keeps the hero and the others in place")
	s.party_command = "RETREAT"
	s.auto_step()
	check(d.hero.pos.x < pos.x or d.hero.pos == pos,"retreat moves the hero away from the foe")
	s.party_command = "ATTACK_TARGET"; s.command_target = d.foes[0].id
	d.foes[0].pos = d.hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	var hp: int = d.foes[0].hp
	s.auto_step()
	check(d.foes[0].hp < hp,"attack target makes the hero hit the marked foe")
	s.party_command = "FOLLOW"
	check(not s.reserve_action(1,"WAIT",s.party[1].pos),"reservations are gone in floor mode")
```

- [ ] **Step 2: 실패 확인** — `godot --headless --path . --script res://tests/autobattle.gd 2>&1 | tail -3`. Expected: `in_combat`/`auto_step` 미정의.

- [ ] **Step 3: `session.gd` 구현**

상단 변수 근처:

```gdscript
const AUTO_STOPS := ["BATTLE_START","ALLY_LETHAL","HP_LOW","DEATH","BATTLE_END"]
## Auto-battle state: whether the UI is advancing rounds, which events stop it,
## and what the previous round looked like so that "newly" can be judged.
var auto := {"running":false,"stops":{"BATTLE_START":true,"ALLY_LETHAL":true,"HP_LOW":true,"DEATH":true,"BATTLE_END":true},
	"hp_low":30,"speed":1,"prev_threats":0,"prev_low":[],"prev_alive":0,"last_stop":{"reason":"","round":-99},"stops_log":[]}

func in_combat() -> bool:
	return floor_mode and phase == "BATTLE" and not floor_state.safe(self)
```

`act()`를 껍데기로:

```gdscript
func act(kind: String, target: Vector2i) -> bool:
	return act_as(party[selected],kind,target,true)

## One action by `actor`. `chain` runs the legacy follow-up (companions acting
## after the hero, round end on empty AP); auto_step passes false and drives
## the round itself.
func act_as(actor: Dictionary, kind: String, target: Vector2i, chain: bool = true) -> bool:
	if phase != "BATTLE" or not inside(target): return false
	if floor_mode and not floor_state.visible.has(target): return false
	if boss_trial and kind == "PYLON":
		if not BossTrial.disable_pylon(self,target): return false
		if chain: finish_player_action()
		return true
	if actor.hp <= 0 or actor.ap <= 0: return false
	if Abilities.DEFINITIONS.has(kind):
		if not Abilities.execute(self,actor,kind,target): return false
		actor.ap -= 1; check_battle_end()
		if chain: finish_player_action()
		return true
	var victim := at(target)
	match kind:
		… (기존 WAIT/MOVE/ATTACK/FIRE/WATER/ELECTRIC 분기 그대로, `movement_cells()` 호출은 `movement_cells(party.find(actor))`로)
		_: return false
	actor.ap -= 1
	check_battle_end()
	if chain: finish_player_action()
	return true
```

`companion_choice`에서 명령 처리를 떼어 `command_choice`로(전원 적용, `companions` 조건 제거):

```gdscript
## The party command's answer for `actor`, or {} when the rules decide.
func command_choice(actor: Dictionary) -> Dictionary:
	if party_command == "HOLD_POSITION":
		if combat_enemies().any(func(e): return melee_reach(actor.pos,e.pos)): return {}
		return {"kind":"WAIT","cell":actor.pos,"reason":"자리 지키기"}
	if party_command == "STOP_ATTACK": return floor_state.follow(self,actor) if floor_mode else {"kind":"WAIT","cell":actor.pos,"reason":"공격 중지"}
	if party_command == "RETREAT":
		… (기존 후퇴 계산 그대로)
	if party_command == "ATTACK_TARGET":
		… (기존 집중 공격 계산 그대로)
	return {}

func companion_choice(actor: Dictionary) -> Dictionary:
	var reserved := reservation_choice(actor)
	if not reserved.is_empty(): return reserved
	if companions:
		var ordered := command_choice(actor)
		if not ordered.is_empty(): return ordered
	if floor_mode and floor_state.safe(self): return floor_state.follow(self,actor)
	return Tactics.choose(self,actor)
```

`reserve_action` 첫 줄에 `if floor_mode: return false`.

`auto_step`·`auto_stop_reason`:

```gdscript
## One rules-driven round: every living member spends its AP through the
## command or the rules, then the round ends. Game UI and simulator both call this.
func auto_step() -> bool:
	if not in_combat() or alive().is_empty(): return false
	for actor in party:
		var guard := 0
		while actor.hp > 0 and actor.ap > 0 and phase == "BATTLE" and guard < 4:
			guard += 1
			var choice: Dictionary = command_choice(actor)
			if choice.is_empty(): choice = Tactics.choose(self,actor)
			if not act_as(actor,choice.kind,choice.cell,false):
				if not act_as(actor,"WAIT",actor.pos,false): break
			actor.last_action = choice.reason
	if phase == "BATTLE": end_round()
	remember_round()
	return true

## Snapshot of what auto_stop_reason compares against next round.
func remember_round() -> void:
	auto.prev_threats = combat_enemies().size()
	auto.prev_low = alive().filter(func(a): return a.hp*100/a.max_hp <= int(auto.hp_low)).map(func(a): return a.id)
	auto.prev_alive = alive().size()

## First stop event that applies at the start of this round, or "".
func auto_stop_reason() -> String:
	if not floor_mode or phase != "BATTLE": return ""
	var threats: int = combat_enemies().size()
	var reason := ""
	if threats > 0 and int(auto.prev_threats) == 0: reason = "BATTLE_START"
	elif threats == 0 and int(auto.prev_threats) > 0: reason = "BATTLE_END"
	elif alive().size() < int(auto.prev_alive): reason = "DEATH"
	elif alive().any(func(a): return Rules.lethal_threat(self,a) >= a.hp): reason = "ALLY_LETHAL"
	elif alive().any(func(a): return a.hp*100/a.max_hp <= int(auto.hp_low) and a.id not in auto.prev_low): reason = "HP_LOW"
	if reason.is_empty() or not bool(auto.stops.get(reason,false)):
		if reason in ["BATTLE_START","BATTLE_END","DEATH"]: remember_round()
		return ""
	# Repeated alerts are suppressed for three rounds; the hard events never are.
	if reason in ["ALLY_LETHAL","HP_LOW"] and auto.last_stop.reason == reason and round_number-int(auto.last_stop.round) < 3:
		return ""
	auto.last_stop = {"reason":reason,"round":round_number}
	auto.stops_log.append(reason)
	remember_round()
	return reason
```

주의: `auto_stop_reason`는 부작용(`last_stop`·`stops_log`·`remember_round`)이 있으므로 UI 루프에서 라운드마다 정확히 한 번만 부른다. 테스트에서 "fires once"는 그 다음 호출이 같은 이유를 내지 않는 것으로 확인한다. `depart()`에서 `auto.prev_threats = 0; prev_low = []; prev_alive = party.size(); stops_log = []; last_stop = {…-99}`로 초기화한다.

- [ ] **Step 4: 실행** — `autobattle parts protect companion_tactics skill_rule_conditions solo_floor encounter_sim ui_smoke mobile_actions boss_trial integration playthrough` 통과. `companion_tactics`가 `companions` 조건 제거로 깨지면 그 스위트는 층 모드가 아니므로 `command_choice` 분기가 그대로 적용되는지 확인하고 기대값을 맞춘다(동작 변화 없음이 목표).

- [ ] **Step 5: 커밋** — `feat(auto): rules-driven auto_step, stop events, party-wide commands`

---

### Task 2: 성향 노브와 성격

**Files:**
- Create: `expedition/knobs.gd`
- Modify: `expedition/tactical_action_selector.gd`, `expedition/session.gd` (`make_actor` `knobs`, `auto_step`/`auto_stop_reason` 갈등 훅, `set_knob`), `expedition/sim/encounter_runner.gd` (`apply_build` `knobs`), `data/content/reference_builds.json` (문서화만: 생략 시 기본)
- Test: `tests/autobattle.gd` (`knobs()`)

**Interfaces:**
- Produces: `Knobs.DEFAULT`, `Knobs.defaults(profile) -> Dictionary`, `Knobs.comfort(profile) -> Dictionary {posture:[lo,hi], cohesion:[lo,hi], retreat_hp:[lo,hi]}`, `Knobs.conflicted(actor) -> bool`, `Knobs.effective(actor) -> Dictionary` (불안·붕괴 대체 적용), `Tactics.KNOB`, `session.set_knob(index, key, value) -> bool`.
- Consumes: `actor.profile.value(F)`, `actor.stress`, `actor.condition`.

- [ ] **Step 1: 실패하는 테스트 — `tests/autobattle.gd`에 `knobs()` 추가, `run()`에서 호출**

```gdscript
const Knobs = preload("res://expedition/knobs.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")

func profile(values: Dictionary):
	return Hexaco.new({"H":500,"E":500,"X":500,"A":500,"C":500,"O":500}.merged(values,true))

func knobs() -> void:
	# Formulas from spec §3.3 on fixed profiles.
	var bold := profile({"X":900,"E":100,"A":900,"C":1000})
	var timid := profile({"X":100,"E":900,"A":100,"C":0})
	check(Knobs.defaults(bold) == {"posture":80,"cohesion":80,"retreat_hp":14},"bold defaults")
	check(Knobs.defaults(timid) == {"posture":-80,"cohesion":-80,"retreat_hp":46},"timid defaults")
	check(Knobs.comfort(bold).posture == [10,150] and Knobs.comfort(timid).posture == [-100,-60],"comfort half-width grows with C (70 vs 20)")
	check(Knobs.comfort(timid).retreat_hp == [36,56],"retreat comfort half-width 10 at C 0")
	var d := skirmish(); var s = d.s
	var hero: Dictionary = d.hero
	check(hero.knobs == Knobs.defaults(hero.profile),"new actors start at their personality defaults")
	check(not s.set_knob(0,"posture",120) and not s.set_knob(0,"nope",1),"range and key validated")
	s.phase = "TOWN"
	check(s.set_knob(0,"posture",-100) and hero.knobs.posture == -100,"knobs change in town")
	s.phase = "BATTLE"
	check(not s.set_knob(0,"posture",0),"not while fighting")
	# Conflict: forced far outside the comfort band.
	hero.profile = bold; hero.knobs = Knobs.defaults(bold); hero.knobs.posture = -100
	check(Knobs.conflicted(hero),"posture -100 conflicts with a bold profile")
	var stress: int = hero.stress; var memories: int = hero.memory.records.size()
	d.foes[0].pos = d.c+Vector2i(3,0); s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START","battle starts")
	check(hero.stress > stress and hero.memory.records.size() == memories+1,"conflict costs stress and a COMMAND_CONFLICT memory at battle start")
	check(hero.memory.records.back().kind == "COMMAND_CONFLICT","memory kind")
	hero.stress = 120; s.stress(hero,0)
	check(hero.condition == "불안" and Knobs.effective(hero).posture == 80,"an anxious member falls back to personality")
	hero.stress = 160; s.stress(hero,0)
	check(Knobs.effective(hero).posture == 100,"a collapsed bold member goes all-in")
	hero.stress = 0; s.stress(hero,0); hero.knobs.posture = 60
	check(not Knobs.conflicted(hero) and Knobs.effective(hero).posture == 60,"inside the band the knob is used as set")
	# Tactics: posture +100 ignores fire-only danger, -100 flees it.
	d = skirmish(); s = d.s; hero = d.hero
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	s.tile(hero.pos).fire = 40
	hero.knobs = {"posture":100,"cohesion":0,"retreat_hp":0}
	check(s.Tactics.choose(s,hero).kind == "ATTACK","aggressive: fire underfoot does not stop the attack")
	hero.knobs.posture = -100
	check(s.Tactics.choose(s,hero).kind == "MOVE","cautious: leaves the fire")
	s.tile(hero.pos).fire = 0
	# Cohesion +100 avoids moving away from allies; retreat line prefers distance.
	hero.knobs = {"posture":0,"cohesion":100,"retreat_hp":0}
	d.foes[0].pos = d.c+Vector2i(4,0); s.floor_state.observe(s)
	var choice: Dictionary = s.Tactics.choose(s,hero)
	check(choice.kind != "MOVE" or s.alive().any(func(a): return a.id != hero.id and s.melee_reach(choice.cell,a.pos)),"cohesive hero does not step out of contact with allies")
	hero.knobs = {"posture":0,"cohesion":0,"retreat_hp":50}; hero.hp = int(hero.max_hp*0.4)
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	choice = s.Tactics.choose(s,hero)
	check(choice.kind == "MOVE" and s.distance(choice.cell,d.foes[0].pos) > 1,"below the retreat line the hero opens distance")
```

`Hexaco.new(values)`는 `_init(p_values)`를 받는다(`hexaco_profile.gd:22`). `merged(values,true)`는 Godot 4 `Dictionary.merged(overwrite)`.

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `expedition/knobs.gd`**

```gdscript
extends RefCounted
## Behaviour knobs and where personality puts them. A knob outside its comfort
## band is a standing order the member dislikes: it costs stress at every
## battle start, and an anxious member ignores it.
const DEFAULT := {"posture":0,"cohesion":0,"retreat_hp":25}
const RANGE := {"posture":[-100,100],"cohesion":[-100,100],"retreat_hp":[0,60]}

static func defaults(profile) -> Dictionary:
	return {"posture":clampi((profile.value("X")-profile.value("E"))/10,-100,100),
		"cohesion":clampi((profile.value("A")-500)/5,-100,100),
		"retreat_hp":clampi(10+profile.value("E")/25,0,50)}

## [low, high] per knob; wider for the conscientious.
static func comfort(profile) -> Dictionary:
	var base := defaults(profile)
	var wide: int = 20+profile.value("C")/20
	var narrow: int = 10+profile.value("C")/50
	return {"posture":[base.posture-wide,base.posture+wide],
		"cohesion":[base.cohesion-wide,base.cohesion+wide],
		"retreat_hp":[base.retreat_hp-narrow,base.retreat_hp+narrow]}

static func conflicted(actor: Dictionary) -> bool:
	var band := comfort(actor.profile)
	for key in DEFAULT:
		var value: int = int(actor.knobs.get(key,DEFAULT[key]))
		if value < int(band[key][0]) or value > int(band[key][1]): return true
	return false

## The knobs the member actually fights with: as set while calm, personality
## defaults when anxious, an extreme posture when collapsed.
static func effective(actor: Dictionary) -> Dictionary:
	var set: Dictionary = actor.get("knobs",DEFAULT).duplicate()
	if int(actor.stress) < 100: return set
	var own := defaults(actor.profile)
	if int(actor.stress) >= 150: own.posture = -100 if actor.profile.value("E") >= 500 else 100
	return own
```

- [ ] **Step 4: `tactical_action_selector.gd`**

상단에 `const Knobs = preload("res://expedition/knobs.gd")`와

```gdscript
const KNOB := {"attack":15,"escape":30,"guard":20,"cohesion":10,"retreat_score":150,"retreat_attack":-20}
```

`choose()` 시작에서 `var knobs: Dictionary = Knobs.effective(actor)`, `var low: bool = actor.hp*100/actor.max_hp <= int(knobs.retreat_hp)`. 조정:

- 회피 MOVE 후보 생성: 공격적(`posture > 0`)이고 현재 칸의 위험이 불뿐(`s.intents`에 `actor.pos`가 없음)이면 후보를 만들지 않는다. 신중이면 `score += (-knobs.posture)*KNOB.escape/100`.
- ATTACK·피해 파츠(`def.effect in ["DAMAGE","LUNGE"]`) 후보: `score += knobs.posture*KNOB.attack/100`; `low`면 `+ KNOB.retreat_attack`.
- GUARD 후보: `score += knobs.cohesion*KNOB.guard/100`.
- 모든 MOVE 후보(회피·접근): `var delta := adjacent_allies(s,actor,cell) - adjacent_allies(s,actor,actor.pos)`; `score += sign(delta)*knobs.cohesion*KNOB.cohesion/100` (cohesion 음수면 자연히 부호 반대). 헬퍼 `static func adjacent_allies(s, actor, cell) -> int`.
- 후퇴선: `low`이면 `rule_choice`를 건너뛰고, 적과의 최소 거리를 늘리는 이동 후보(현행 `command_choice` RETREAT 계산을 `Tactics.retreat_cell(s, actor) -> Vector2i`로 옮겨 공용화)를 점수 `KNOB.retreat_score`로 넣는다; 회복 파츠(`effect == "HEAL"`) 후보는 `+ KNOB.retreat_score`. `command_choice`의 RETREAT는 `Tactics.retreat_cell`을 쓴다.
- 파일 머리 주석에 스펙 §3.2 표를 요약해 둔다.

- [ ] **Step 5: `session.gd`**

- `make_actor`: `"knobs":Knobs.defaults(profile)` (profile 생성 뒤에 넣도록 순서 조정), `"conflicted":false`.
- `set_knob(index, key, value)`: `safe_management()`이고 `not in_combat()`, key ∈ `Knobs.RANGE`, 범위 안이면 설정. 갈등은 판정 시점에 계산하므로 저장하지 않는다.
- `auto_stop_reason`가 `BATTLE_START`를 확정하는 지점에서: `for a in alive(): if Knobs.conflicted(a): stress(a,8); remember_important(a,"COMMAND_CONFLICT",a.id+1,0,600); a.conflicted = true; message(a.name+" · 명령과 갈등")`; 그 외 시점에는 `a.conflicted = Knobs.conflicted(a)` 갱신. `remember_important`의 중복 억제 키가 `expedition/kind/subject`이므로 원정마다 한 번만 기억이 남는다 — 스트레스는 전투마다 붙는다(스펙 그대로).
- `auto_step`가 불안 상태 멤버를 처음 굴릴 때 로그 "<이름> · 자기 방식대로 움직입니다"(라운드마다가 아니라 `a.ignoring` 플래그로 전투당 1회).
- `encounter_runner.apply_build`: `if row.has("knobs"): actor.knobs = row.knobs.duplicate()`; 없으면 액터 기본(성격)이 아니라 `Knobs.DEFAULT`를 넣는다(빌드 비교가 성격에 흔들리지 않게). `reference_builds.json` 머리 주석 대신 `docs/balance-method.ko.md`에 한 줄.

- [ ] **Step 6: 실행** — `autobattle parts protect companion_tactics skill_rule_conditions solo_floor encounter_sim solo_balance` 통과. `solo_balance` 승수를 보고서에 적는다(변경 금지).

- [ ] **Step 7: 커밋** — `feat(auto): behaviour knobs from personality, conflict and retreat line`

---

### Task 3: `battle_stats` · 시뮬 통합

**Files:**
- Modify: `expedition/session.gd` (`battle_stats`, `stats_*` 흡수), `expedition/abilities.gd`·`monster_ai.gd`·`passives.gd` (카운터 대상 변경), `expedition/sim/bot_policy.gd`, `expedition/sim/encounter_runner.gd`, `tests/solo_balance.gd`·`tests/solo_floor.gd`·`tests/solo_recovery.gd`·`tests/torch_tradeoff.gd`·`tests/solo_provisioning.gd`(원정 봇 전투 부분), `tests/encounter_sim.gd`, `tests/parts.gd`·`tests/protect.gd`(`stats_*` 참조)
- Test: `tests/autobattle.gd` (`stats()`, `sim()`)

**Interfaces:**
- Produces: `session.battle_stats: Dictionary` (스펙 §5.1 구조), `session.reset_battle_stats()`, `session.member_stats(id) -> Dictionary`; `bot_policy.step(s,"rules")`가 `"AUTO"`를 돌려줌; `run_one` 키 유지.
- Consumes: Task 1의 `auto_step`.

- [ ] **Step 1: 실패하는 테스트**

```gdscript
const Runner = preload("res://expedition/sim/encounter_runner.gd")
const Policy = preload("res://expedition/sim/bot_policy.gd")

func stats() -> void:
	var d := skirmish(); var s = d.s
	d.foes[0].pos = d.c+Vector2i(1,0); s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START" and s.battle_stats.rounds == 0 and s.battle_stats.enemies == 1,"battle start resets the stats")
	s.auto_step()
	var m: Dictionary = s.member_stats(d.hero.id)
	check(s.battle_stats.rounds == 1 and m.dealt > 0,"hero damage is tallied")
	check(s.battle_stats.members.has(s.party[1].id),"every member has a row")
	d.foes[0].hp = 30
	s.party[1].pos = d.c+Vector2i(0,1); d.hero.ap = 1
	s.act_as(d.hero,"GUARD",s.party[1].pos,false)
	d.foes[0].pos = d.c+Vector2i(1,1); s.floor_state.observe(s)
	s.damage(s.party[1],6,d.foes[0].id,"IMPACT")
	m = s.member_stats(d.hero.id)
	check(m.guards == 1 and m.redirected == 3,"guard count and redirected damage")
	d.foes[0].hp = 0; s.damage(d.foes[0],0,d.hero.id,"SLASH")
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_END" and s.battle_stats.kills >= 1 and s.battle_stats.stops == ["BATTLE_START","BATTLE_END"],"kills and stops recorded at battle end")
	check(not s.has_method("stats_redirects") and not s.get("stats_redirects"),"old counters are gone")

func sim() -> void:
	var hob := [{"species_id":"dcss_hobgoblin","role":"MELEE","display_name":"홉고블린","max_health":55}]
	var arena: Dictionary = Runner.Arena.DEFAULT_SPEC.duplicate(true)
	var config := {"party_size":3,"build":"melee_1","policy":"rules","rules":Session.DEFAULT_RULES,"supplies":[0,0,0,0,0,0],"arena":arena,"max_rounds":40}
	arena.members = hob
	var one: Dictionary = Runner.run_one(config,11)
	check(one.result in ["WIN","DEFEAT","TIMEOUT"] and one.rounds >= 1,"rules policy runs through auto_step")
	check(one == Runner.run_one(config,11),"still deterministic")
	check(one.has("skill_uses") and one.has("guards_used") and one.has("enemy_skill_uses") and one.has("interrupts"),"metric keys unchanged")
	var s = Session.new(11,true,true,true,3)
	s.rules_config = Session.DEFAULT_RULES.duplicate()
	check(Policy.step(s,"rules") == "" ,"no step before depart")
```

`Runner.Arena`·`DEFAULT_SPEC`·`config` 형식은 `tests/encounter_sim.gd`의 `config()` 헬퍼를 그대로 따른다(정확한 키는 그 파일에서 복사).

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `battle_stats`**

`session.gd`:

```gdscript
var battle_stats: Dictionary = {}

func reset_battle_stats() -> void:
	battle_stats = {"rounds":0,"enemies":combat_enemies().size(),"kills":0,"members":{},"interrupts":0,"enemy_parts":{},"drops":{},"stops":[]}
	for a in party: battle_stats.members[a.id] = {"dealt":0,"taken":0,"guards":0,"redirected":0,"parts":{},"healed":0,"downed":false,"conflict":bool(a.get("conflicted",false))}

func member_stats(id: int) -> Dictionary:
	if not battle_stats.has("members"): reset_battle_stats()
	return battle_stats.members.get(id,{})
```

- `_init`/`depart`에서 `reset_battle_stats()`. `auto_stop_reason`: `BATTLE_START`이면 `reset_battle_stats()` 후 `stops.append`, 다른 정지는 `stops.append`만. `auto_step`: `battle_stats.rounds += 1` (전투 중일 때).
- `damage()`: 실제 손실 `lost`를 공격자가 파티원이면 `members[source].dealt += lost`, 피해자가 파티원이면 `members[target.id].taken += lost`; 엄호 재지정 시 `members[recipient.id].redirected += lost`(현 `stats_redirects += 1` 자리 — 횟수는 `guards`가 아니라 `redirects`로 두려면 `redirected`는 피해량, 횟수는 별도 `covers`; 스펙은 "횟수/대신 받은 피해" 둘 다이므로 `covers`와 `redirected` 두 필드). 적 사망 시 `kills += 1`. 파티원 사망 시 `downed = true`.
- `Abilities.resolve`: 파티원 사용은 `members[id].parts[part] += 1`, `HEAL`이면 `healed += 회복량`; 적 사용은 `battle_stats.enemy_parts[part] += 1` (기존 `stats_enemy_skill` 대체). GUARD 실행은 `guards += 1`.
- `MonsterAI.interrupt`: `s.battle_stats.interrupts += 1` (기존 `stats_interrupts` 대체).
- `roll_part`: `battle_stats.drops[id] += 1`.
- `stats_redirects`·`stats_enemy_skill`·`stats_interrupts` 변수 삭제; 참조하는 테스트(`parts`, `protect`, `encounter_sim`, `party_guard_probe`)를 `battle_stats`로 바꾼다. 전투 밖(방 모드·보스 시련)에서도 `battle_stats`는 존재하되 `BATTLE_START`가 없으므로 `_init` 초기값에 누적된다 — 시뮬 러너는 아레나 시작 직후 `reset_battle_stats()`를 부른다.

- [ ] **Step 4: 시뮬 통합**

`bot_policy.step`:

```gdscript
	if policy == "rules":
		# The hero and the party read the same rule list the game runs; one call
		# is one round, so the runner's tallies come from battle_stats.
		return "AUTO" if s.auto_step() else ""
```

`encounter_runner.run_one`: `kind == "AUTO"`일 때 `actions += 1`; `skill_uses`·`guards`·`heals`는 루프 집계 대신 끝에서 `battle_stats`에서 합산(`members[*].parts` 합 → `skill_uses`, `members[*].guards` 합 → `guards_used`, `healed > 0`인 멤버 수가 아니라 회복 파츠 사용 수 → `heals_used`), `protect_redirects` → `members[*].covers` 합, `enemy_skill_uses` → `enemy_parts`, `interrupts` → `interrupts`. `simple`/`tactical` 정책은 `act` 기반 그대로이며 `battle_stats`도 채워지므로 같은 합산을 쓴다. 아레나 배치 직후 `s.reset_battle_stats()`.

원정 봇(`tests/solo_balance.gd play`, `solo_floor`, `solo_recovery`, `torch_tradeoff`, `solo_provisioning`의 전투 블록): `if not s.combat_enemies().is_empty():` 안의 `auto_attack()/WAIT`를 `s.auto_step()`으로 바꾼다(물약 사용 분기는 그대로 앞에). 공용 헬퍼 `tests/floor_fixture.gd`에 `static func fight_round(s) -> bool: return s.auto_step()`을 두고 쓴다.

- [ ] **Step 5: 실행** — `autobattle encounter_sim parts protect solo_balance solo_floor solo_recovery torch_tradeoff solo_provisioning skill_archetypes` 통과, `solo_balance` 승수 기록. `tests/skill_value.gd`·`action_economy.gd`·`party_guard_probe.gd`가 오류 없이 끝나는지(보고서 재생성은 Task 6).

- [ ] **Step 6: 커밋** — `feat(auto): battle_stats and the simulator on auto_step`

---

### Task 4: 진형 = 행군 순서 · 전투 시작 교환

**Files:**
- Modify: `expedition/session.gd` (`formation` 의미 변경, `swap_formation`), `expedition/continuous_floor.gd` (`follow`가 순서를 씀)
- Test: `tests/autobattle.gd` (`formation()`), `tests/mobile_exploration.gd`·`tests/companion_tactics.gd`(대형 참조 시 수정)

**Interfaces:**
- Produces: `session.formation: Array[int]` (파티 인덱스 순서, 기본 `[0,1,2]`), `session.leader() -> Dictionary`, `session.swap_formation(a: int, b: int) -> bool`, `session.rally_point() -> Vector2i`.
- Consumes: Task 1의 `auto_stop_reason`(전투 시작 판정), `floor_state.follow`.

- [ ] **Step 1: 실패하는 테스트**

```gdscript
func formation() -> void:
	var d := skirmish(0); var s = d.s
	check(s.formation == [0,1,2] and s.leader().id == 0,"marching order defaults to party order")
	check(not s.swap_formation(0,1),"no swap while safe — only at battle start")
	d.foes = [s.enemies[0]]; var foe: Dictionary = d.foes[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = d.c+Vector2i(3,0)
	s.floor_state.observe(s)
	check(s.auto_stop_reason() == "BATTLE_START","battle start")
	var a: Vector2i = s.party[0].pos; var b: Vector2i = s.party[1].pos
	check(s.swap_formation(0,1) and s.party[0].pos == b and s.party[1].pos == a and s.formation == [1,0,2],"swap exchanges cells and order")
	check(not s.swap_formation(1,2),"one swap per battle")
	check(s.leader().id == 1 and s.rally_point() == s.party[1].pos,"leader and rally point follow the order")
	s.auto_step()
	check(not s.swap_formation(0,1),"not after the first round")
	# Follow uses the order: the rear member trails the leader when safe.
	d = skirmish(0); s = d.s
	s.formation = [2,1,0]
	s.party[2].pos = d.c+Vector2i(4,4); s.party[0].pos = d.c; s.party[1].pos = d.c+Vector2i(0,1)
	var step: Dictionary = s.floor_state.follow(s,s.party[0])
	check(step.kind == "MOVE" and s.distance(step.cell,s.party[2].pos) < s.distance(s.party[0].pos,s.party[2].pos),"followers walk toward the leader, not toward selected")
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 구현**

`session.gd`: `var formation: Array = [0,1,2]`(파티 크기에 맞게 `_init`에서 `range(count)`), 기존 `"NONE"/"COLUMN"/…` 문자열 사용처(`main.gd:514-515`, `continuous_floor.follow`)를 제거한다.

```gdscript
func leader() -> Dictionary:
	for index in formation:
		if index < party.size() and party[index].hp > 0: return party[index]
	return party[0]

func rally_point() -> Vector2i:
	return leader().pos

## Two members trade cells and places in the marching order. Only while the
## run is stopped for a battle start, once per battle.
func swap_formation(a: int, b: int) -> bool:
	if not in_combat() or auto.last_stop.reason != "BATTLE_START" or auto.last_stop.round != round_number or auto.get("swapped_round",-1) == round_number: return false
	if a == b or a < 0 or b < 0 or a >= party.size() or b >= party.size() or party[a].hp <= 0 or party[b].hp <= 0: return false
	var pa: Vector2i = party[a].pos; party[a].pos = party[b].pos; party[b].pos = pa
	var ia: int = formation.find(a); var ib: int = formation.find(b)
	formation[ia] = b; formation[ib] = a
	auto.swapped_round = round_number
	floor_state.observe(self)
	message("%s ↔ %s 자리 교환" % [party[a].name,party[b].name])
	return true
```

`continuous_floor.follow(s, actor)`: 선두는 `s.leader()`; `rank`는 `s.formation`에서 액터 인덱스의 순위(선두 제외); 대형 종류 분기(`COLUMN/LINE/WEDGE`)는 삭제하고 "선두 뒤 한 칸씩 종대"만 남긴다(기존 `COLUMN` 계산). 선두 자신이 `follow`를 요청하면 WAIT. `command_choice`의 `STOP_ATTACK`은 `rally_point()`로 이동.

`tests/mobile_exploration.gd`·`companion_tactics.gd`에서 `formation = "COLUMN"` 등을 쓰면 `[0,1,2]`로 바꾼다.

- [ ] **Step 4: 실행** — `autobattle mobile_exploration companion_tactics solo_floor continuous_floor protect` 통과.

- [ ] **Step 5: 커밋** — `feat(auto): marching order formation with a battle-start swap`

---

### Task 5: 전투 HUD · 성향 탭 · 결과 카드 · 옵션

**Files:**
- Modify: `expedition/main.gd` (전투 HUD 교체, 자동 진행 타이머, 배너, 옵션 팝업, 결과 카드), `expedition/character_ui.gd` (`personality` 탭 확장 → 성향 슬라이더), `expedition/board.gd` (미리보기 화살표는 선택 사항 — 생략 가능)
- Test: `tests/autobattle.gd` (`ui()`), `tests/ui_smoke.gd`(방 모드 검사 유지 확인), `tests/mobile_hud.gd`·`tests/mobile_actions.gd`·`tests/character_ui.gd`·`tests/parts.gd ui()`(층 모드 버튼 검사 수정)

**Interfaces:**
- Consumes: Task 1~4의 세션 API 전부.
- Produces: `main.gd` 노드 이름 — `AutoToggle`(▶/⏸), `SpeedToggle`, `CommandBar`(버튼 5), `FormationButton`, `StopBanner`, `BattleReport`(PanelContainer), `AutoOptions`(옵션 팝업 콘텐츠); `CharacterUI.personality`가 슬라이더 `Knob_posture/Knob_cohesion/Knob_retreat_hp`를 만든다.

- [ ] **Step 1: 실패하는 테스트 — `ui()` (씬 층; `await`)**

```gdscript
func ui() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(731,true,true,true,3)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(3): await process_frame
	s.depart(); var c := Fixture.arena(s,8); Fixture.equip_basics(s)
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = c+Vector2i(3,0)
	s.floor_state.observe(s); scene.refresh()
	for frame in range(3): await process_frame
	check(scene.skill_buttons.is_empty() and scene.end_turn_button == null,"floor battle has no skill buttons and no end-turn button")
	var toggle: Button = scene.find_child("AutoToggle",true,false)
	var bar = scene.find_child("CommandBar",true,false)
	check(toggle != null and bar != null and bar.get_child_count() == 5,"auto toggle and five commands")
	check(scene.find_child("StopBanner",true,false).text.begins_with("전투 시작"),"banner names the stop")
	check(not s.auto.running and bar.get_children().all(func(b): return not b.disabled),"stopped: commands enabled")
	toggle.pressed.emit(); await process_frame
	check(s.auto.running and bar.get_children().all(func(b): return b.disabled),"running: commands disabled")
	scene.auto_tick()  # one timer tick = one auto_step when running
	await process_frame
	check(s.round_number == 2,"a tick advanced one round")
	toggle.pressed.emit(); await process_frame
	check(not s.auto.running,"toggle stops")
	# Speed toggle changes the interval.
	var speed: Button = scene.find_child("SpeedToggle",true,false)
	speed.pressed.emit(); await process_frame
	check(s.auto.speed == 2 and scene.auto_interval() < 0.5,"2x halves the interval")
	# Battle end shows the report.
	foe.hp = 0; s.floor_state.observe(s); s.auto.running = true; scene.auto_tick()
	for frame in range(3): await process_frame
	var report = scene.find_child("BattleReport",true,false)
	check(report != null and report.visible,"battle report card on battle end")
	var labels: Array = report.find_children("*","Label",true,false).map(func(l): return l.text)
	check(labels.any(func(t): return t.begins_with("전투 종료")),"report header")
	check(report.find_children("*","Button",true,false).any(func(b): return b.text == "파츠·규칙 보기"),"report links to parts and rules")
	# Personality tab has knob sliders with comfort bands.
	scene.show_character(0,"성격")
	for frame in range(3): await process_frame
	var slider = scene.modal_content.find_child("Knob_posture",true,false)
	check(slider != null and slider.min_value == -100 and slider.max_value == 100,"posture slider")
	check(slider.editable == false or s.phase != "TOWN","slider locked outside town")
	scene.details_popup.hide()
	# Options popup lists the five stops and the HP threshold.
	scene.show_auto_options()
	for frame in range(3): await process_frame
	var options = scene.find_child("AutoOptions",true,false)
	check(options != null and options.find_children("*","CheckButton",true,false).size() == 5,"five stop toggles")
	scene.details_popup.hide(); scene.queue_free(); await process_frame
```

`run()`은 `await ui()`를 포함한다.

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `main.gd` 전투 HUD (층 모드 한정: `session.floor_mode`)**

- 파티 열: 스킬 버튼 루프 대신 멤버 카드만(이름·HP·스트레스·상태·`last_action` 한 줄, 갈등이면 "⚠ 갈등"). `skill_buttons`는 층 모드에서 비워 둔다. `end_turn_button = null` 유지(만들지 않음). 대상 선택 모드(`mode`), `pending_attack`, `reservation_actor`, `choose_skill`, `show_orders` 진입점은 층 모드에서 호출되지 않게 한다(버튼을 만들지 않는다).
- 보드 아래 한 줄: `AutoToggle`(텍스트 "▶ 재개"/"⏸ 정지"), `SpeedToggle`("1×"/"2×"), `FormationButton`("진형 교환" — `swap_formation` 가능할 때만 활성, 누르면 두 멤버 선택 팝업), 가방, 횃불, 옵션(⚙ → `show_auto_options`).
- `CommandBar`(HBox, 이름 `CommandBar`): 버튼 5개 `["FOLLOW","따라와"],["HOLD_POSITION","자리 지켜"],["STOP_ATTACK","공격 중지"],["RETREAT","후퇴"],["ATTACK_TARGET","집중 공격"]`; 현재 명령은 toggle pressed; `auto.running`이면 전부 비활성; `ATTACK_TARGET`은 기존 `command_targeting` 흐름(적 탭)으로.
- `StopBanner`(Label): 마지막 정지 이유의 한국어 문장 — `{"BATTLE_START":"전투 시작 · 적 %d","ALLY_LETHAL":"%s 치명 위기","HP_LOW":"%s 체력 %d%% 이하","DEATH":"%s 쓰러짐","BATTLE_END":"전투 종료"}`; 이유가 없으면 빈 문자열.
- 자동 루프: `var auto_clock := 0.0`; `_process`에서 `if session.floor_mode and session.auto.running and not popup_open(): auto_clock += delta; if auto_clock >= auto_interval(): auto_clock = 0; auto_tick()`. `func auto_interval() -> float: return 0.7/float(session.auto.speed)`. `func auto_tick()`: `var reason := session.auto_stop_reason(); if not reason.is_empty(): session.auto.running = false; banner = …; if reason == "BATTLE_END": show_battle_report(); refresh(); return`; 아니면 `run_action(session.auto_step)`. `run_action` 안의 "모두 AP 0이면 end_round" 자동 처리는 층 모드에서 건너뛴다(`auto_step`이 라운드를 닫는다).
- 전투 시작 시점: `floor_state.observe` 뒤 `refresh()`에서 `auto_stop_reason()`을 한 번 평가해 `BATTLE_START` 배너를 띄운다 — 단 `auto_stop_reason`는 부작용이 있으므로 `refresh()`가 아니라 `run_action` 끝(수동 이동으로 적을 발견한 직후)과 `auto_tick`에서만 부른다.
- 가방·아이템 사용 버튼은 `auto.running`이면 비활성.

- [ ] **Step 4: 결과 카드 `show_battle_report()`**

`BattleReport` PanelContainer를 `details_popup` 콘텐츠로: 머리 "전투 종료 · %d라운드 · 적 %d 처치 · 아군 사망 %d"; 멤버별 한 줄 "이름 · 입힘 %d · 받음 %d · 엄호 %d회/%d · 파츠 %s · 갈등" (`member_stats`); "적 파츠: %s · 끊김 %d"; "획득: %s"; 버튼 "파츠·규칙 보기"(`show_character(0,"파츠")`), "닫기". 사망자 행은 색 강조 + 마지막 3줄 로그.

- [ ] **Step 5: 성향 탭 (`character_ui.personality`)**

HEXACO 게이지 아래에 노브 3개: 각각 `HSlider`(이름 `Knob_<key>`, 범위 `Knobs.RANGE`, 값 `actor.knobs[key]`, `editable = ui.session.phase == "TOWN" or (ui.session.floor_mode and ui.session.safe_management() and not ui.session.in_combat())`), 라벨 "태세 신중 ↔ 공격적 / 협동 독자 ↔ 밀집 / 후퇴선 %d%%", 편안 범위 띠(`ColorRect` 두 개로 슬라이더 위에 `[lo,hi]` 구간을 연한 색으로), 범위 밖이면 "⚠ 이 설정은 성격과 맞지 않습니다 — 전투마다 스트레스" 텍스트. `value_changed` → `ui.session.set_knob(index,key,int(value))`.

- [ ] **Step 6: 옵션 팝업 `show_auto_options()`** — `AutoOptions` VBox: `CheckButton` 5개(`AUTO_STOPS` 순서, 한국어 이름) → `session.auto.stops[id]`; HP 임계값 `OptionButton` 20/30/40/50 → `auto.hp_low`; 닫기.

- [ ] **Step 7: 기존 UI 테스트 갱신** — `tests/parts.gd ui()`의 "빈 슬롯 버튼" 검사는 층 모드 전투 버튼이 사라졌으므로 삭제하고, 대신 파츠 탭 카드 검사만 남긴다. `tests/mobile_actions.gd`·`mobile_hud.gd`에서 층 모드 스킬 버튼·턴 종료를 전제하는 검사는 `AutoToggle`/`CommandBar` 존재 검사로 바꾼다. `ui_smoke.gd`는 방 모드 세션(`Session.new()` 기본)이라 그대로.

- [ ] **Step 8: 실행** — `autobattle ui_smoke mobile_hud mobile_actions mobile_exploration character_ui parts test_loadout abilities_growth integration playthrough` 통과. 임포트 오류 0.

- [ ] **Step 9: 커밋** — `feat(auto): battle HUD, personality knobs tab, battle report, stop options`

---

### Task 6: CI · 밸런스 게이트 G1~G6

**Files:**
- Modify: `.github/workflows/deploy-pages.yml` (`autobattle` 추가), `data/content/balance_experiments.json` (`knob_grid` 실험), `tests/knob_grid.gd` (신규 수동 도구), `docs/balance/skill-value.md/.json`·`action-economy.md/.json` 재생성, `docs/balance/parts-gates.md` 갱신 아님(새 파일) → `docs/balance/autobattle-gates.md`, `docs/balance-method.ko.md` 한 단락

- [ ] **Step 1: CI** — 스위트 목록 끝에 ` autobattle`.

- [ ] **Step 2: `knob_grid` 실험** — `balance_experiments.json`에

```json
"knob_grid": {"seed_set": {"id": "S3", "start": 7000, "count": 40}, "party_sizes": [3], "build": "melee_1", "policies": ["rules"],
  "postures": [-60, 0, 60], "cohesions": [-60, 0, 60], "retreat_hp": 25, "supplies": [0,0,0,0,0,0], "arenas": "<action_economy와 동일 6개>"}
```

`tests/knob_grid.gd`: 9조합 × 6아레나 × 40시드, `apply_build` 뒤 `actor.knobs`를 조합으로 덮어씀. 표: 조합 × 아레나 승률[CI], 평균 피해; **지배 판정**: 어떤 조합이 다른 8조합 전부에 대해 6아레나 중 ≥4에서 Δ승률 ≥ +20pp이면 지배 후보. `docs/balance/autobattle-gates.md`에 표와 판정.

- [ ] **Step 3: 게이트 실행** (순서대로, 헤드리스, 타임아웃 넉넉히)

| 게이트 | 도구 | 기준 |
| --- | --- | --- |
| G1 | `solo_balance` | 승리 ≥ 3/8 |
| G2 | `skill_value` 표 1 · `encounter_sim` | 3인 `rules` 6아레나 ≥ 0.90; 솔로 `early_*` ≥ 0.50 |
| G3 | `skill_value` | 파츠 지배 후보 0, 봇이 못 씀 0 |
| G4 | `skill_value` 표 3 | 8종 파츠 사용 ≥ 0.5/전투 |
| G5 | `party_guard_probe` | 엄호 있음 사망 < 없음 |
| G6 | `knob_grid` | 노브 지배 후보 0 |

미달 시: G1~G4는 스펙 §3.2 점수 상수(`Tactics.KNOB`)를 한 번에 하나씩 조정(파츠 수치는 손대지 않음), G6은 지배 조합의 관련 상수만. 두 번 조정 후에도 미달이면 멈추고 보고. 모든 실행·수치를 `autobattle-gates.md`에 기록(커밋·날짜·시드·"오토배틀 전환 후 첫 측정").

- [ ] **Step 4: 문서** — `docs/balance-method.ko.md`에 "오토배틀 전환 후 측정" 단락(게이트 표 링크, 통과/미달, 바꾼 상수). `skill-value.md`·`action-economy.md` 머리말 갱신.

- [ ] **Step 5: 전체 스위트** — CI 목록 전부 통과, 임포트 오류 0, 수동 도구 4+1개 오류 없음.

- [ ] **Step 6: 커밋** — `feat(auto): knob grid gate, reports after the autobattle switch`

---

## 자기 검토

- **스펙 커버리지**: §1.1 `auto_step`·`act_as`(T1) / §1.2 정지 이벤트·억제·로그(T1) / §1.3 UI 루프·배너·속도·옵션(T5) / §2 명령 전원 적용·멈춘 동안만·아이템 비용(T1, T5) / §3.1~3.4 노브·점수·성격 공식·갈등·빌드(T2) / §4 규칙 편집 위치(기존 UI, T5에서 `safe_management` 확인) / §5.1 계측·§5.2 카드(T3, T5) / §6 진형(T4) / §7 HUD(T5) / §8 시뮬 통합·게이트(T3, T6) / §9 테스트(T1~T5) / §10 파일(전부).
- **자리표시자**: 없음. 코드 없는 단계는 대상 함수·노드 이름·문자열이 있다.
- **이름 일관성**: `auto_step / act_as / auto_stop_reason / command_choice / in_combat / battle_stats / member_stats / reset_battle_stats / swap_formation / leader / rally_point / set_knob / Knobs.defaults/comfort/conflicted/effective / Tactics.KNOB / Tactics.retreat_cell / AutoToggle / SpeedToggle / CommandBar / StopBanner / BattleReport / AutoOptions / Knob_<key>` — 태스크 간 동일.
- **알려진 위험**: `auto_stop_reason`의 부작용(호출 횟수에 의존) — T1 테스트가 "한 번만" 규칙을 고정하고, T5는 호출 지점을 두 곳으로 제한한다. `companions == false`(솔로)에서 `command_choice`가 전원 적용되는 것이 기존 솔로 봇 테스트에 영향을 줄 수 있다 — 솔로에서는 기본 명령 `FOLLOW`라 `{}`이므로 영향 없음.
