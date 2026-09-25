# 빌드 세 축과 원소 반응 구현 계획 (3/4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 속성 세트가 모든 명중에 속성을 싣고, 출혈을 여섯 번째 속성 태그로 더하고, 역할 세트 3단계를 "~할 때" 발동 효과로 바꾸고, 기존 불·젖음·방전 위에 칸 반응 넷과 상태이상 반응 다섯을 얹는다.

**Architecture:** 새 정적 모듈 `expedition/combat/reactions.gd`가 피해 형태(명중, 덧붙는 피해, 반응, 반격), 행동 경계와 라운드 경계의 중복 방지, 칸 반응, 상태이상 반응, 반응 알림을 맡는다. 모든 피해는 이미 `CombatRules.damage` 한 곳을 지나므로, 여기에 "피해 형태" 인자를 더하고 명중과 덧붙는 피해 뒤에 `Reactions.on_hit`을 부른다. 역할 세트의 발동 효과는 `tag_sets.gd`에 두고, 회피·막기·처치·반응이 일어나는 자리에서 부른다.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트(`godot --headless --path . --script res://tests/<suite>.gd`).

**Spec:** `docs/superpowers/specs/2026-09-25-zones-bosses-reactions-design.md` (§0.6, §0.8, §5, §6)

**연계 계획:** 1/4 구역(`2026-09-25-zones.md`, 위험 칸 필드 `lava`, `deep_water`, `bog`, `gas`, `collapse`, `fog`), 2/4 도감(`2026-09-25-bestiary.md`, 계열 패시브 `Families`, 도발 액티브가 `taunt` 상태를 건다, `Abilities.reduction`), 4/4 보스(`2026-09-25-bosses.md`). 이 계획은 1·2보다 먼저 실행해도 동작한다. 위험 칸 필드와 `taunt`는 `.get(...)`로 읽는다.

## Global Constraints

- 테스트 실행 전 임포트: `godot --headless --path . --editor --import --quit`. 새 `.gd` 파일을 만든 뒤에도 한 번 더 돌린다.
- 모든 스위트는 `push_error`가 없고 종료 코드 0이어야 통과. 로그에 `SCRIPT ERROR:`나 `^ERROR:` 줄이 있으면 실패.
- 결정성: 무작위는 `CombatRules.roll(...)` 또는 `Hexaco.sample(...)`만 쓴다. `randi()` 금지.
- 메시지·라벨은 한국어.
- 속성 id: `"fire","ice","air","poison","will","bleed"`. 역할 id: `"PACK","BERSERK","AMBUSH","GUARD","ARCHER","CASTER"`.
- 피해 형태: `"HIT"`(명중), `"EXTRA"`(속성 세트의 덧붙는 피해, 무기 속성 부여의 덧붙는 피해), `"REACTION"`(반응 피해), `"COUNTER"`(수호 3단계 반격), 기존 `"RETALIATE"`. 명중이 아닌 형태는 패시브, 속성 세트의 덧붙는 피해와 상태이상 확률, 역할 발동을 부르지 않는다. `"EXTRA"`만 칸 반응과 상태이상 반응을 부른다.
- 반응 판정 순서: 피해 적용 → 칸 반응 → 상태이상 반응 → (명중이면) 속성 3단계 상태이상 확률 → (명중이면) 속성 2단계 덧붙는 피해. 확률로 건 상태는 그 자리에서 `STATUS` 형태로 상태이상 반응을 한 번 더 판정한다(독 폭발, 끓는 피, 배신). 같은 명중이 방금 건 빙결을 스스로 파쇄하지 않도록 파쇄는 명중 형태에서만, 확률보다 먼저 판정한다. 역할 발동은 회피·막기·처치·반응이 일어난 자리에서 부른다.
- 한 행동에서 같은 인물의 같은 발동 조건은 한 번(`Reactions.once`). 같은 대상의 같은 반응은 라운드(`s.time / 100`)마다 한 번(`Reactions.fresh_reaction`). 칸 반응도 칸마다 라운드에 한 번.
- 수치: 덧붙는 피해 3, 증기 상쇄 기준 20, 증기 2라운드(200틱), 증기 피해 2, 젖음 기준 20, 마르기 2라운드, 방전 시작 힘 = 그 전기 피해의 30%, 독 폭발 피해 8, 파쇄 +50%, 끓는 피 = 남은 출혈 라운드 × 2, 감전 1라운드, 속성 3단계 확률 화상·중독·출혈 15%, 빙결·혼란 10%, 전기 3단계 젖은 대상 +30%, 출혈 2단계 +20%, 역할 3단계 무리 +20%·기습 ×1.5·수호 무기 피해 절반·광폭 HP 5와 재사용 대기 −1·사수 +20%·술사 반응 피해 +30%.
- 커밋 메시지 끝에 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. 커밋은 `git commit -m ... -- <이 작업의 파일들>`처럼 경로를 명시한다. 다른 세션의 미커밋 변경을 건드리지 않는다.
- 검사 수를 줄이지 않는다. 지운 옛 3단계 검사보다 새 검사가 많아야 한다.

---

## File Structure

| 파일 | 역할 |
|---|---|
| `expedition/combat/reactions.gd` (신규) | 피해 형태, 행동·라운드 중복 방지, 젖음, 칸 반응, 상태이상 반응, 속성 세트의 확률·덧붙는 피해, 반응 알림, 칸 틱 |
| `expedition/combat/combat_rules.gd` | `damage`에 피해 형태 인자와 `Reactions.on_hit` 호출, `attack`의 회피·막기 발동, 무기 속성 부여를 덧붙는 피해로, 얼음 칸 이동 |
| `expedition/combat/statuses.gd` | `stun`, `apply`의 출처 인자와 상태이상 반응 호출 |
| `expedition/progression/tag_sets.gd` | 출혈 태그, 세트 설명, 스탯 보너스, 새 `outgoing`, 역할 3단계 발동(`on_dodge`, `on_block`, `on_kill`, `on_reaction`), 옛 3단계 삭제 |
| `expedition/progression/essences.gd` | `ELEMENTS`에 출혈, 출혈 변종은 저항을 얹지 않음 |
| `expedition/progression/stat_sheet.gd` | 옛 수호 3단계(인접 아군 방어) 줄 삭제 |
| `expedition/run/session.gd` | `Reactions` 상수, `action_serial`, `damage`의 형태 전달, `after_damage`의 패시브 제외, `discharge` 힘 인자와 반응 형태, `conductive` 확장, 행동 경계 |
| `expedition/run/autobattle.gd`, `expedition/time/scheduler.gd`, `expedition/spells/spells.gd` | 행동 경계, 환경 틱의 칸 반응, 젖음 갱신 |
| `expedition/level/continuous_floor.gd`, `expedition/actors/monster_ai.gd` | 증기가 시야를 막음 |
| `expedition/ui/board.gd` | 반응 이름 띄우기, 증기·얼음·독 웅덩이 칸 그리기 |
| `tests/reactions.gd` (신규), `tests/build_axes.gd` (신규) | 새 규칙 검사 |
| `tests/tag_sets.gd`, `tests/essences.gd` | 옛 3단계 검사를 새 규칙으로 |

---

### Task 1: 피해 형태와 행동 경계

**Files:**
- Create: `expedition/combat/reactions.gd`
- Modify: `expedition/combat/combat_rules.gd` (`damage`)
- Modify: `expedition/combat/statuses.gd` (`blocks`)
- Modify: `expedition/run/session.gd` (상수, 변수, `damage`, `after_damage`, `act_as`)
- Modify: `expedition/run/autobattle.gd` (`enemy_attack_turn`), `expedition/time/scheduler.gd` (`act`), `expedition/spells/spells.gd` (`cast`)
- Test: `tests/reactions.gd` (신규)

**Interfaces:**
- Consumes: 기존 `CombatRules.damage(s, source, target, raw, element, penetration)`, `Session.after_damage(target, amount, source, form)`, `Session.damage(target, amount, source, form)`
- Produces:
  - `Reactions.HIT_FORM := "HIT"`, `EXTRA_FORM := "EXTRA"`, `REACTION_FORM := "REACTION"`, `COUNTER_FORM := "COUNTER"`, `SECONDARY := ["EXTRA","REACTION","COUNTER","RETALIATE"]`
  - `Reactions.begin_action(s)`, `once(s, actor, key) -> bool`, `fresh_reaction(s, target, name) -> bool`, `round_of(s) -> int`, `element_of(form) -> String`, `water_level(cell) -> int`, `wet_ground(s, point) -> bool`, `is_wet(s, actor) -> bool`, `refresh_wet(s)`, `on_hit(s, source, target, element, amount, form)`(이 작업에서는 대상의 `last_hit`만 적는다)
  - `CombatRules.damage(s, source, target, raw, element, penetration := 0, hit_form := "HIT") -> int`
  - `Session.Reactions`, `Session.action_serial: int`
  - 상태 `stun`: 모든 행동을 막는다. 상태 `wet`: 젖은 칸에 서 있으면 붙고, 나오면 2라운드 뒤 마른다.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/reactions.gd`:

```gdscript
extends SceneTree
## Element reactions: the forms damage takes, the guards against loops, the
## ground reactions, the status reactions and what the board shows.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Scheduler = preload("res://expedition/time/scheduler.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	forms()
	print("Reactions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Hero at c, ally at c+(0,1), a fresh foe at c+(1,0) and a second foe at
## c+(2,0), both with no part, no resistance, no armour.
func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	var other: Dictionary = s.enemies[1]
	for enemy in [foe,other]:
		enemy.hp = 40; enemy.max_hp = 40; enemy.part_id = ""; enemy.species_id = ""
		enemy.res = {}; enemy.statuses = {}; enemy.sh = 0; enemy.ev = 0; enemy.ac = 0
	foe.pos = c+Vector2i(1,0); other.pos = c+Vector2i(2,0)
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe,"other":other}

func forms() -> void:
	var d := duo(); var s = d.s
	check(Reactions.element_of("ELECTRIC") == "air" and Reactions.element_of("FIRE") == "fire" and Reactions.element_of("SLASH") == "physical" and Reactions.element_of("bleed") == "bleed","damage forms map to elements")
	var before: int = d.foe.hp
	Rules.damage(s,d.hero,d.foe,5,"poison",0,Reactions.REACTION_FORM)
	check(int(d.foe.hp) == before-5,"reaction damage lands as it is")
	check(int(d.foe.get("last_hit",-1)) == -1,"reaction damage is not a hit")
	Rules.damage(s,d.hero,d.foe,4,"physical")
	check(int(d.foe.last_hit) == 4,"a hit leaves its amount on the target")
	s.effects.clear()
	s.damage(d.foe,3,int(d.hero.id),"REACTION")
	check(s.effects.any(func(e): return str(e.get("form","")) == "REACTION"),"the session keeps the form of a secondary hit")
	Reactions.begin_action(s)
	check(Reactions.once(s,d.hero,"GUARD") and not Reactions.once(s,d.hero,"GUARD"),"a trigger fires once in an action")
	check(Reactions.once(s,d.ally,"GUARD"),"another member keeps their own")
	Reactions.begin_action(s)
	check(Reactions.once(s,d.hero,"GUARD"),"the next action fires it again")
	check(Reactions.fresh_reaction(s,d.foe,"shatter") and not Reactions.fresh_reaction(s,d.foe,"shatter"),"a reaction once a round on a target")
	s.time += 100
	check(Reactions.fresh_reaction(s,d.foe,"shatter"),"and again the next round")
	var serial: int = s.action_serial
	s.act_as(d.hero,"WAIT",d.hero.pos,false)
	check(int(s.action_serial) > serial,"every action opens a new action")
	d.foe.statuses["stun"] = s.time+100
	check(Statuses.blocks(d.foe,"MOVE") and Statuses.blocks(d.foe,"ATTACK") and Statuses.blocks(d.foe,"CAST"),"a stun stops everything")
	s.tile(d.hero.pos).wet = 50
	check(Reactions.wet_ground(s,d.hero.pos) and Reactions.is_wet(s,d.hero),"standing in water is wet")
	Reactions.refresh_wet(s)
	check(int(d.hero.statuses.get("wet",0)) == int(s.time)+Reactions.DRY_TICKS,"the wet status dries two rounds after leaving")
	s.tile(d.hero.pos).wet = 0
	check(Reactions.is_wet(s,d.hero),"still wet just after stepping out")
	s.tile(d.ally.pos)["deep_water"] = true
	check(Reactions.wet_ground(s,d.ally.pos),"deep water counts as wet ground")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --editor --import --quit; godot --headless --path . --script res://tests/reactions.gd`
Expected: FAIL — `reactions.gd`를 불러올 수 없음.

- [ ] **Step 3: `reactions.gd`의 기초 쓰기**

`expedition/combat/reactions.gd`:

```gdscript
extends RefCounted
## Element reactions. A hit of one element reacts with the ground it lands on
## and with the statuses its target already wears. The ground and the
## statuses belong to the fight, not to whoever put them there, so a
## companion's frost and the hero's blade react just as two monsters would.
## Damage a reaction deals never reacts again.
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const HIT_FORM := "HIT"
const EXTRA_FORM := "EXTRA"
const REACTION_FORM := "REACTION"
const COUNTER_FORM := "COUNTER"
## Forms that run no passive, no set extra, no set proc and no trigger.
const SECONDARY := ["EXTRA","REACTION","COUNTER","RETALIATE"]
const WET_LEVEL := 20
const DRY_TICKS := 200
const ELEMENT_OF := {"fire":"fire","FIRE":"fire","ice":"ice","air":"air","ELECTRIC":"air","poison":"poison","POISON":"poison","will":"will","bleed":"bleed"}

static func element_of(form: String) -> String:
	return str(ELEMENT_OF.get(form,"physical"))

static func round_of(s) -> int:
	return int(s.time)/100

## Every action opens a new window for the once-per-action triggers.
static func begin_action(s) -> void:
	s.action_serial += 1

## True the first time `key` fires for `actor` in this action.
static func once(s, actor: Dictionary, key: String) -> bool:
	var fired: Dictionary = actor.get_or_add("triggers",{})
	if int(fired.get(key,-1)) == int(s.action_serial): return false
	fired[key] = int(s.action_serial)
	return true

## True the first time `name` reacts on `target` this round.
static func fresh_reaction(s, target: Dictionary, name: String) -> bool:
	var seen: Dictionary = target.get_or_add("reactions",{})
	if int(seen.get(name,-1)) == round_of(s): return false
	seen[name] = round_of(s)
	return true

## How much water a cell holds: standing water, deep water and bog are full.
static func water_level(cell: Dictionary) -> int:
	if str(cell.get("terrain","")) in ["water","deep_water","bog"]: return 100
	if bool(cell.get("deep_water",false)) or bool(cell.get("bog",false)): return 100
	return int(cell.get("wet",0))

static func wet_ground(s, point: Vector2i) -> bool:
	return s.inside(point) and water_level(s.tile(point)) >= WET_LEVEL

static func is_wet(s, actor: Dictionary) -> bool:
	if actor.get("statuses",{}).has("wet"): return true
	return actor.has("pos") and wet_ground(s,actor.pos)

## Whoever stands on wet ground is wet, and stays wet two rounds after leaving.
static func refresh_wet(s) -> void:
	for actor in s.party+s.npcs+s.enemies:
		if int(actor.hp) > 0 and wet_ground(s,actor.pos): actor.statuses["wet"] = int(s.time)+DRY_TICKS

## A landed hit (`HIT`) or a set's extra hit (`EXTRA`). Later tasks add the
## ground, the procs, the status reactions and the extras.
static func on_hit(s, source: Dictionary, target: Dictionary, element: String, amount: int, form: String) -> void:
	if source.is_empty() or form not in [HIT_FORM,EXTRA_FORM]: return
	target["last_hit"] = amount
```

- [ ] **Step 4: 피해 한 곳에 형태를 더하기**

`expedition/combat/combat_rules.gd` 머리에 넣는다.

```gdscript
const Reactions = preload("res://expedition/combat/reactions.gd")
```

`damage`를 통째로 바꾼다.

```gdscript
## Every damage in the game. `hit_form` says what kind of blow this is: a
## landed hit, a set's extra, a reaction or a counter. Only hits and extras
## react; the secondary forms reach `after_damage` under their own name so
## passives stay out of them.
static func damage(s, source: Dictionary, target: Dictionary, raw: int, element: String, penetration: int = 0, hit_form: String = "HIT") -> int:
	if target.hp <= 0 or raw <= 0: return 0
	var amount: int = TagSets.element_damage(source,element,raw)
	if element not in ["physical", "SLASH", "IMPACT", "RETALIATE", "REACTION", "COUNTER", "EXTRA"]:
		var listed: int = int(Stats.stats(s,target).res.get(element.to_lower(),0))
		var resistance: int = listed if listed <= 0 else maxi(0,listed-penetration)
		amount = maxi(0, amount * (100 - resistance) / 100)
	# 취약화 is read after resistance: everything that still lands lands harder.
	if target.get("statuses", {}).has("vulnerable"): amount = amount * 13 / 10
	var form: String = element if hit_form == Reactions.HIT_FORM else hit_form
	var lost: int = s.after_damage(target, amount, int(source.get("id", 999)), form)
	if hit_form in [Reactions.HIT_FORM, Reactions.EXTRA_FORM]: Reactions.on_hit(s, source, target, element, lost, hit_form)
	return lost
```

- [ ] **Step 5: 세션 연결**

`expedition/run/session.gd`:
- 상수 목록(`const TagSets = ...` 아래)에 `const Reactions = preload("res://expedition/combat/reactions.gd")`를 넣는다.
- `var roll_serial := 0` 아래에 넣는다.

```gdscript
## One number per action: the once-per-action triggers compare against it.
var action_serial := 0
```

- `damage`를 바꾼다.

```gdscript
func damage(target: Dictionary, amount: int, source: int, form: String) -> int:
	var hit_form: String = form if form in Reactions.SECONDARY else Reactions.HIT_FORM
	return CombatRules.damage(self,actor_by_id(source),target,amount,form,0,hit_form)
```

- `after_damage`의 `var passive_hit: bool = form != "RETALIATE"`를 `var passive_hit: bool = form not in Reactions.SECONDARY`로 바꾸고, 그 위 주석을 "Secondary blows — a retaliation, a set's extra, a reaction, a counter — never trigger passives again."으로 바꾼다.
- `act_as`의 첫 줄 `if not on_floor() or not inside(target): return false` 바로 위에 `Reactions.begin_action(self)`를 넣는다.

`expedition/run/autobattle.gd`의 `enemy_attack_turn` 첫 줄 `_enemy_attack_turn(s,enemy)` 위에 `s.Reactions.begin_action(s)`를 넣는다.

`expedition/time/scheduler.gd`의 `act`에서 `if actor.is_empty() or actor.hp <= 0: return` 바로 아래에 `s.Reactions.begin_action(s)`를 넣는다.

`expedition/spells/spells.gd`의 `cast`에서 `if not can_cast(s,caster,id,target): return false` 바로 아래에 `s.Reactions.begin_action(s)`를 넣는다.

- [ ] **Step 6: 감전은 모든 행동을 막는다**

`expedition/combat/statuses.gd`의 `blocks`를 바꾼다.

```gdscript
## 감전 stops everything; 빙결 and 속박 stop the feet; only 빙결 also stops the arms.
static func blocks(actor: Dictionary, kind: String) -> bool:
	var statuses: Dictionary = actor.get("statuses",{})
	if statuses.has("stun"): return true
	if kind == "MOVE": return statuses.has("freeze") or statuses.has("bind")
	if kind == "ATTACK": return statuses.has("freeze")
	return false
```

- [ ] **Step 7: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in reactions combat_basics model_b_combat parts tag_sets essences stats_resist enemy_turns; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: 모두 0 failures. 기존 스위트가 반격(`RETALIATE`) 로그나 효과의 `form` 값을 검사해 깨지면, 기대값이 그대로여야 한다. `RETALIATE`는 이름이 바뀌지 않았다.

- [ ] **Step 8: 커밋**

```bash
git add expedition/combat/reactions.gd tests/reactions.gd
git commit -m "Give every damage a form and every action a boundary for reactions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/combat/reactions.gd expedition/combat/combat_rules.gd expedition/combat/statuses.gd expedition/run/session.gd expedition/run/autobattle.gd expedition/time/scheduler.gd expedition/spells/spells.gd tests/reactions.gd
```

---

### Task 2: 칸 반응

**Files:**
- Modify: `expedition/combat/reactions.gd` (칸 반응, 알림, 칸 틱)
- Modify: `expedition/run/session.gd` (`discharge`, `conductive`)
- Modify: `expedition/time/scheduler.gd`, `expedition/run/autobattle.gd` (환경 틱)
- Modify: `expedition/combat/combat_rules.gd` (`move_time`)
- Modify: `expedition/level/continuous_floor.gd` (`observe`), `expedition/actors/monster_ai.gd` (`line`)
- Test: `tests/reactions.gd` (함수 추가)

**Interfaces:**
- Consumes: Task 1
- Produces:
  - `Reactions.tile_react(s, cell: Vector2i, element: String, amount: int, source: Dictionary)`
  - `Reactions.tile_tick(s, point: Vector2i, cell: Dictionary, suppression: int)`, `Reactions.steam(s, cell, source)`, `Reactions.blocks_sight(s, point) -> bool`, `Reactions.conductive(s, point) -> bool`, `Reactions.announce(s, cell, key, source)`, `Reactions.hang(s, victim, status, ticks)`, `Reactions.reaction_damage(source, amount) -> int`, `Reactions.react_damage(s, source, target, amount, element) -> int`, `Reactions.NAMES`
  - 칸 필드 `steam_until: int`, `ice: bool`, `poison_pool: bool`, `reactions: {name: round}`
  - `Session.discharge(origin, source, power := 18)`: 반응 형태로 피해를 준다.
  - 알림: `s.effects`에 `{"kind":"REACTION","from":cell,"cell":cell,"text":이름}`, `s.events`에 `{"kind":"REACTION","name":이름,"cell":cell}`, 로그 `"<이름> 반응"`.

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/reactions.gd`의 `run()`에서 `forms()` 다음 줄에 `ground()`를 넣고 파일 끝에 붙인다.

```gdscript
func ground() -> void:
	# Fire on wet ground: steam over the cell and its four neighbours.
	var d := duo(); var s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"fire",10,d.hero)
	check(int(s.tile(d.foe.pos).get("steam_until",0)) == int(s.time)+Reactions.STEAM_TICKS,"fire on wet ground raises steam")
	check(int(s.tile(d.foe.pos+Vector2i(0,1)).get("steam_until",0)) > int(s.time),"the steam spreads to the neighbours")
	check(int(s.tile(d.foe.pos).wet) == 20,"the fire boils thirty of the water away")
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION" and e.text == "증기"),"the board shows the steam")
	check(s.events.any(func(e): return e.get("kind","") == "REACTION" and e.name == "증기"),"the event queue carries it")
	check(Reactions.blocks_sight(s,d.foe.pos) and not MonsterAI.line(s,d.c,d.c+Vector2i(4,0),6),"steam blocks sight")
	var hp: int = d.foe.hp
	Scheduler.environment_tick(s)
	check(int(d.foe.hp) == hp-Reactions.STEAM_DAMAGE,"standing in steam scalds")
	s.time += Reactions.STEAM_TICKS+1
	Scheduler.environment_tick(s)
	check(not s.tile(d.foe.pos).has("steam_until") and MonsterAI.line(s,d.c,d.c+Vector2i(4,0),6),"the steam clears")
	# Burning wet ground boils on its own.
	d = duo(); s = d.s
	s.tile(d.other.pos).fire = 40; s.tile(d.other.pos).wet = 40
	Scheduler.environment_tick(s)
	check(int(s.tile(d.other.pos).get("steam_until",0)) > int(s.time),"fire meeting water in the tick raises steam")
	# Frost on wet ground: ice, and whoever stands on it freezes.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"ice",5,d.hero)
	check(bool(s.tile(d.foe.pos).get("ice",false)) and int(s.tile(d.foe.pos).wet) == 0,"frost turns the water to ice")
	check(d.foe.statuses.has("freeze"),"whoever stands on it freezes")
	var dry: int = Rules.move_time(s,d.hero,d.hero.pos+Vector2i(0,-1))
	s.tile(d.hero.pos+Vector2i(0,-1))["ice"] = true
	check(Rules.move_time(s,d.hero,d.hero.pos+Vector2i(0,-1)) == dry*3/2,"ice is slow to cross")
	Reactions.tile_react(s,d.foe.pos,"fire",5,d.hero)
	check(not bool(s.tile(d.foe.pos).ice) and int(s.tile(d.foe.pos).wet) == 50,"fire melts it back to water")
	s.tile(d.other.pos).wet = 0
	Reactions.tile_react(s,d.other.pos,"ice",5,d.hero)
	check(not bool(s.tile(d.other.pos).get("ice",false)),"dry ground does not freeze")
	# Lightning on conductive ground discharges at thirty percent.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50; s.tile(d.other.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"air",30,d.hero)
	check(int(d.foe.hp) == 40-9 and int(d.other.hp) == 40-3,"a discharge starts at thirty percent and weakens by six a cell")
	check(int(d.hero.hp) == int(d.hero.max_hp),"dry ground does not carry it")
	Reactions.tile_react(s,d.foe.pos,"air",30,d.hero)
	check(int(d.foe.hp) == 40-9,"the same cell discharges once a round")
	# Poison on wet ground: a pool that poisons until it dries.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"poison",5,d.hero)
	check(bool(s.tile(d.foe.pos).get("poison_pool",false)),"poison on water makes a pool")
	Scheduler.environment_tick(s)
	check(d.foe.statuses.has("poison"),"the pool poisons who stands in it")
	s.tile(d.foe.pos).wet = 0
	Scheduler.environment_tick(s)
	check(not bool(s.tile(d.foe.pos).poison_pool),"a dry pool is gone")
	# A landed hit reacts with the ground under its target.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Rules.damage(s,d.hero,d.foe,5,"ice")
	check(bool(s.tile(d.foe.pos).get("ice",false)),"an ice hit freezes the target's wet ground")
	s.tile(d.other.pos).wet = 50
	Rules.damage(s,d.hero,d.other,5,"ice",0,Reactions.REACTION_FORM)
	check(not bool(s.tile(d.other.pos).get("ice",false)),"reaction damage never reacts")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/reactions.gd`
Expected: FAIL — `tile_react` 없음.

- [ ] **Step 3: 칸 반응 쓰기**

`expedition/combat/reactions.gd`의 상수 목록 끝(`const ELEMENT_OF ...` 아래)에 넣는다.

```gdscript
const FIRE_MEETS_WATER := 30
const STEAM_SUPPRESSION := 20
const STEAM_TICKS := 200
const STEAM_DAMAGE := 2
const DISCHARGE_PERCENT := 30
const POOL_POISON_TICKS := 300
const NAMES := {"steam":"증기","ice":"얼음","discharge":"방전","poison_pool":"독 웅덩이",
	"poison_blast":"독 폭발!","shatter":"파쇄!","boiling":"끓는 피!","electrocute":"감전!","betrayal":"배신!"}
```

`on_hit`를 다음으로 바꾼다.

```gdscript
static func on_hit(s, source: Dictionary, target: Dictionary, element: String, amount: int, form: String) -> void:
	if source.is_empty() or form not in [HIT_FORM,EXTRA_FORM]: return
	target["last_hit"] = amount
	if target.has("pos"): tile_react(s,target.pos,element,amount,source)
```

파일 끝에 붙인다.

```gdscript
## The same ground reaction on the same cell: once a round.
static func fresh_cell(s, cell: Dictionary, name: String) -> bool:
	var seen: Dictionary = cell.get_or_add("reactions",{})
	if int(seen.get(name,-1)) == round_of(s): return false
	seen[name] = round_of(s)
	return true

static func conductive(s, point: Vector2i) -> bool:
	return s.conductive(point)

static func blocks_sight(s, point: Vector2i) -> bool:
	return s.inside(point) and int(s.tile(point).get("steam_until",0)) > int(s.time)

## What an element does to the ground it lands on.
static func tile_react(s, cell: Vector2i, element: String, amount: int, source: Dictionary) -> void:
	if not s.inside(cell): return
	var ground: Dictionary = s.tile(cell)
	if str(ground.get("terrain","")) == "wall": return
	match element_of(element):
		"fire":
			if bool(ground.get("ice",false)):
				ground.ice = false; ground.wet = maxi(int(ground.wet),50)
				return
			var suppression: int = mini(FIRE_MEETS_WATER,water_level(ground))
			if suppression < STEAM_SUPPRESSION or not fresh_cell(s,ground,"steam"): return
			if water_level(ground) < 100: ground.wet = maxi(0,int(ground.wet)-suppression)
			steam(s,cell,source)
		"ice":
			if bool(ground.get("ice",false)) or water_level(ground) < WET_LEVEL: return
			ground.ice = true; ground.wet = 0
			var standing: Dictionary = s.at(cell)
			if not standing.is_empty(): s.Statuses.apply(s,standing,"freeze",100,source)
			announce(s,cell,"ice",source)
		"air":
			if amount <= 0 or not conductive(s,cell) or not fresh_cell(s,ground,"discharge"): return
			announce(s,cell,"discharge",source)
			s.discharge(cell,int(source.get("id",999)),maxi(1,reaction_damage(source,amount*DISCHARGE_PERCENT/100)))
		"poison":
			if bool(ground.get("poison_pool",false)) or water_level(ground) < WET_LEVEL: return
			ground.poison_pool = true
			announce(s,cell,"poison_pool",source)

## Steam on the cell and its four neighbours for two rounds.
static func steam(s, cell: Vector2i, source: Dictionary) -> void:
	for point in [cell,cell+Vector2i.LEFT,cell+Vector2i.RIGHT,cell+Vector2i.UP,cell+Vector2i.DOWN]:
		if s.inside(point) and str(s.tile(point).terrain) != "wall": s.tile(point).steam_until = int(s.time)+STEAM_TICKS
	announce(s,cell,"steam",source)

## One environment tick of the reaction ground on one cell. `suppression` is
## how much fire and water just cancelled there.
static func tile_tick(s, point: Vector2i, cell: Dictionary, suppression: int) -> void:
	if suppression >= STEAM_SUPPRESSION and fresh_cell(s,cell,"steam"): steam(s,point,{})
	if int(cell.get("steam_until",0)) > 0:
		if int(cell.steam_until) <= int(s.time): cell.erase("steam_until")
		else:
			var scalded: Dictionary = s.at(point)
			if not scalded.is_empty(): s.CombatRules.damage(s,{},scalded,STEAM_DAMAGE,"fire",0,REACTION_FORM)
	if bool(cell.get("ice",false)) and int(cell.get("fire",0)) > 0: cell.ice = false; cell.wet = maxi(int(cell.wet),50)
	if bool(cell.get("poison_pool",false)):
		if water_level(cell) <= 0: cell.poison_pool = false
		else:
			var soaked: Dictionary = s.at(point)
			if not soaked.is_empty(): hang(s,soaked,"poison",POOL_POISON_TICKS)

## A status a reaction hangs: resisted like any other, but it sets off no
## further reaction of its own.
static func hang(s, victim: Dictionary, status: String, ticks: int) -> void:
	ticks = s.Statuses.resisted_ticks(s,victim,status,ticks)
	if ticks <= 0: return
	victim.statuses[status] = int(s.time)+ticks
	if status == "burn": victim.get_or_add("status_power",{})["burn"] = s.Statuses.BURN_DAMAGE

## A caster's step-three set makes every reaction it starts bite harder.
static func reaction_damage(source: Dictionary, amount: int) -> int:
	if not source.is_empty() and TagSets.level(source,"CASTER") >= 3: return amount*13/10
	return amount

static func react_damage(s, source: Dictionary, target: Dictionary, amount: int, element: String) -> int:
	return s.CombatRules.damage(s,source,target,reaction_damage(source,amount),element,0,REACTION_FORM)

## The reaction's name, big over the cell, in the log and in the event queue.
static func announce(s, cell: Vector2i, key: String, source: Dictionary) -> void:
	var name: String = str(NAMES[key])
	s.effects.append({"kind":"REACTION","from":cell,"cell":cell,"text":name})
	s.message("%s 반응" % name.trim_suffix("!"))
	s.push_event({"kind":"REACTION","name":name,"cell":cell})
```

(`Statuses.apply`의 다섯째 인자 `source`는 Task 3에서 생긴다. 이 작업에서는 `s.Statuses.apply(s,standing,"freeze",100,source)` 대신 `s.Statuses.apply(s,standing,"freeze",100)`로 두고, Task 3 Step 3에서 인자를 더한다.)

- [ ] **Step 4: 방전과 전도 칸**

`expedition/run/session.gd`의 `discharge`와 `conductive`를 바꾼다.

```gdscript
## Lightning running along wet and metal ground, six weaker each cell. It is a
## reaction: it never sets off another.
func discharge(origin: Vector2i, source: int, power: int = 18) -> void:
	var queue: Array = [{"pos":origin, "power":power}]
	var seen: Array = [origin]
	var owner: Dictionary = actor_by_id(source)
	while not queue.is_empty():
		var row: Dictionary = queue.pop_front()
		var victim := at(row.pos)
		if not victim.is_empty(): CombatRules.damage(self,owner,victim,int(row.power),"air",0,Reactions.REACTION_FORM)
		if row.power <= 6 or not conductive(row.pos): continue
		for direction in CARDINALS:
			var next: Vector2i = row.pos + direction
			if inside(next) and next not in seen and conductive(next):
				seen.append(next); queue.append({"pos":next, "power":row.power - 6})
	message("방전")

func conductive(point: Vector2i) -> bool:
	var ground: Dictionary = tile(point)
	return ground.terrain in ["metal", "water", "deep_water", "bog"] or int(ground.wet) >= 25 or bool(ground.get("deep_water",false)) or bool(ground.get("bog",false))
```

- [ ] **Step 5: 환경 틱에 칸 반응과 젖음**

`expedition/time/scheduler.gd`의 `environment_tick`에서

```gdscript
			if cell.fire <= 0 and cell.wet <= 0: continue
			var result: Dictionary = ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, s.time)
			cell.fire = result.fire_after_decay
			cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
			if result.known_damage > 0:
				var victim: Dictionary = s.at(point)
				if not victim.is_empty(): s.damage(victim, result.known_damage, 999, "FIRE")
```

를 다음으로 바꾼다.

```gdscript
			var suppression := 0
			if cell.fire > 0 or cell.wet > 0:
				var result: Dictionary = ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, s.time)
				cell.fire = result.fire_after_decay
				cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
				suppression = int(result.suppression)
				if result.known_damage > 0:
					var victim: Dictionary = s.at(point)
					if not victim.is_empty(): s.damage(victim, result.known_damage, 999, "FIRE")
			if suppression > 0 or cell.has("steam_until") or bool(cell.get("ice",false)) or bool(cell.get("poison_pool",false)):
				s.Reactions.tile_tick(s, point, cell, suppression)
```

같은 함수에서 `Statuses.tick(s)` 줄 바로 위에 `s.Reactions.refresh_wet(s)`를 넣는다.

`expedition/run/autobattle.gd`의 옛 오토배틀 틱에서

```gdscript
			if cell.fire <= 0 and cell.wet <= 0: continue
			var result := ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, s.world_time)
			cell.fire = result.fire_after_decay
			cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
			if result.known_damage <= 0: continue
			var victim: Dictionary = s.at(point)
			if not victim.is_empty() and result.known_damage > 0: s.damage(victim, result.known_damage, 999, "FIRE")
```

를 다음으로 바꾼다.

```gdscript
			var suppression := 0
			if cell.fire > 0 or cell.wet > 0:
				var result := ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, s.world_time)
				cell.fire = result.fire_after_decay
				cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
				suppression = int(result.suppression)
				var victim: Dictionary = s.at(point)
				if not victim.is_empty() and result.known_damage > 0: s.damage(victim, result.known_damage, 999, "FIRE")
			if suppression > 0 or cell.has("steam_until") or bool(cell.get("ice",false)) or bool(cell.get("poison_pool",false)):
				s.Reactions.tile_tick(s, point, cell, suppression)
```

그 이중 루프가 끝난 바로 다음 줄에 `s.Reactions.refresh_wet(s)`를 넣는다.

- [ ] **Step 6: 얼음 칸 이동과 증기 시야**

`expedition/combat/combat_rules.gd`의 `move_time`에서 `var statuses: Dictionary = actor.get("statuses", {})` 바로 위에 넣는다.

```gdscript
	if bool(s.tile(cell).get("ice", false)): value = value * 3 / 2
```

`expedition/level/continuous_floor.gd`의 `observe` 안 시야 판정

```gdscript
					func(c): return s.tile(c).terrain == "wall" and not bool(s.tile(c).get("pillar",false)),before): continue
```

를 다음으로 바꾼다.

```gdscript
					func(c): return (s.tile(c).terrain == "wall" and not bool(s.tile(c).get("pillar",false))) or int(s.tile(c).get("steam_until",0)) > int(s.time),before): continue
```

`expedition/actors/monster_ai.gd`의 `line`을 바꾼다.

```gdscript
static func line(s, a: Vector2i, b: Vector2i, reach: int) -> bool:
	# Range uses eight-way tile distance; Geometry's circular cutoff must not trim diagonals.
	# Walls and steam both stop the eye.
	return distance(a,b) <= reach and s.TurnCore.Geometry.sees(a,b,func(p): return not s.inside(p) or s.tile(p).terrain == "wall" or int(s.tile(p).get("steam_until",0)) > int(s.time),ceili(reach*sqrt(2.0)))
```

- [ ] **Step 7: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in reactions combat_basics model_b_combat enemy_turns continuous_floor mobile_exploration autobattle; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: 모두 0 failures.

- [ ] **Step 8: 커밋**

```bash
git commit -m "React fire, frost, lightning and poison with the ground they land on

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/combat/reactions.gd expedition/run/session.gd expedition/time/scheduler.gd expedition/run/autobattle.gd expedition/combat/combat_rules.gd expedition/level/continuous_floor.gd expedition/actors/monster_ai.gd tests/reactions.gd
```

---

### Task 3: 상태이상 반응

**Files:**
- Modify: `expedition/combat/reactions.gd` (`status_react`, `betray`)
- Modify: `expedition/combat/statuses.gd` (`apply`)
- Test: `tests/reactions.gd` (함수 추가)

**Interfaces:**
- Consumes: Task 1~2
- Produces: `Reactions.status_react(s, target, source, element, form)`, `Reactions.betray(s, target, source) -> bool`, `Reactions.BLAST_DAMAGE := 8`, `Reactions.BLAST_POISON_TICKS := 300`. `Statuses.apply(s, victim, status, ticks, source: Dictionary = {})`는 상태를 건 뒤 `Reactions.status_react(s, victim, source, "", "STATUS")`를 부른다.

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/reactions.gd`의 `run()`에 `statuses()`를 더하고 파일 끝에 붙인다.

```gdscript
func statuses() -> void:
	# 화상 + 중독: a blast around the target, both statuses spent.
	var d := duo(); var s = d.s
	d.foe.statuses = {"burn":s.time+300,"poison":s.time+300}
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(not d.foe.statuses.has("burn") and not d.foe.statuses.has("poison"),"the blast spends both statuses")
	check(int(d.foe.hp) == 40-Reactions.BLAST_DAMAGE and int(d.other.hp) == 40-Reactions.BLAST_DAMAGE,"the blast hits the target and its neighbour")
	check(d.other.statuses.has("poison"),"and poisons the neighbour")
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION" and e.text == "독 폭발!"),"the blast is named")
	d.foe.statuses = {"burn":s.time+300,"poison":s.time+300}
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(d.foe.statuses.has("burn") and int(d.foe.hp) == 40-Reactions.BLAST_DAMAGE,"one blast a round on the same target")
	s.time += 100
	d.foe.statuses = {"burn":s.time+300,"poison":s.time+300}
	Statuses.apply(s,d.foe,"poison",300,d.hero)
	check(not d.foe.statuses.has("burn"),"hanging the second status sets the blast off too")
	# 빙결 + 물리 피해: the ice breaks for half again.
	d = duo(); s = d.s
	d.foe.statuses = {"freeze":s.time+100}
	Rules.damage(s,d.hero,d.foe,10,"physical")
	check(not d.foe.statuses.has("freeze") and int(d.foe.hp) == 40-10-5,"a physical hit shatters the ice for fifty percent more")
	d.other.statuses = {"freeze":s.time+100}
	Rules.damage(s,d.hero,d.other,10,"fire")
	check(d.other.statuses.has("freeze"),"a fire hit does not shatter")
	# 출혈 + 화상: the bleeding still to come lands at once, as fire.
	d = duo(); s = d.s
	d.foe.statuses = {"bleed":s.time+300,"burn":s.time+300}
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(not d.foe.statuses.has("bleed") and int(d.foe.hp) == 40-4*2,"the blood boils: four rounds of bleeding at once")
	# 젖음 + 전기: stunned.
	d = duo(); s = d.s
	s.tile(d.foe.pos).wet = 50
	Reactions.status_react(s,d.foe,d.hero,"air","HIT")
	check(d.foe.statuses.has("stun") and Statuses.blocks(d.foe,"ATTACK"),"lightning on a wet target stuns it")
	Reactions.status_react(s,d.other,d.hero,"air","HIT")
	check(not d.other.statuses.has("stun"),"a dry one is not")
	# 혼란 + 도발: the confused one turns on its own side.
	d = duo(); s = d.s
	d.foe.statuses = {"confuse":s.time+200,"taunt":s.time+200}
	d.foe.get_or_add("status_power",{})["taunt"] = int(d.hero.id)
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION" and e.text == "배신!"),"the taunted, confused foe betrays its side")
	d.other.pos = d.c+Vector2i(6,6)
	d.foe.statuses = {"confuse":s.time+200,"taunt":s.time+200}
	s.time += 100; s.effects.clear()
	Reactions.status_react(s,d.foe,d.hero,"physical","HIT")
	check(not s.effects.any(func(e): return e.get("kind","") == "REACTION"),"with nobody of its own side beside it, nothing happens")
	# Reaction damage is not a hit: it neither reacts nor chains.
	d = duo(); s = d.s
	d.other.statuses = {"freeze":s.time+100}
	Reactions.react_damage(s,d.hero,d.other,5,"physical")
	check(d.other.statuses.has("freeze"),"reaction damage never shatters")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/reactions.gd`
Expected: FAIL — `status_react` 없음.

- [ ] **Step 3: 상태이상 반응 쓰기**

`expedition/combat/reactions.gd`의 상수 목록에 넣는다.

```gdscript
const BLAST_DAMAGE := 8
const BLAST_POISON_TICKS := 300
const STUN_TICKS := 100
```

`on_hit`의 마지막 줄 아래에 넣는다.

```gdscript
	if int(target.hp) <= 0: return
	status_react(s,target,source,element,form)
```

파일 끝에 붙인다.

```gdscript
## What the statuses a target already wears do with each other and with the
## element that just struck it. `form` is "HIT", "EXTRA" or "STATUS" (a status
## was just hung).
static func status_react(s, target: Dictionary, source: Dictionary, element: String, form: String) -> void:
	if int(target.get("hp",0)) <= 0 or not target.has("pos"): return
	element = element_of(element)
	var worn: Dictionary = target.get("statuses",{})
	if worn.has("burn") and worn.has("poison") and fresh_reaction(s,target,"poison_blast"):
		worn.erase("burn"); worn.erase("poison")
		announce(s,target.pos,"poison_blast",source)
		var centre: Vector2i = target.pos
		for other in s.party+s.npcs+s.enemies:
			if int(other.hp) <= 0 or maxi(absi(other.pos.x-centre.x),absi(other.pos.y-centre.y)) > 1: continue
			react_damage(s,source,other,BLAST_DAMAGE,"poison")
			if int(other.hp) > 0: hang(s,other,"poison",BLAST_POISON_TICKS)
	if int(target.hp) <= 0: return
	if element == "physical" and form == HIT_FORM and worn.has("freeze") and fresh_reaction(s,target,"shatter"):
		worn.erase("freeze")
		announce(s,target.pos,"shatter",source)
		react_damage(s,source,target,maxi(1,int(target.get("last_hit",0))/2),"physical")
	if int(target.hp) <= 0: return
	if worn.has("bleed") and worn.has("burn") and fresh_reaction(s,target,"boiling"):
		# The ticks still to come, this boundary included: `Statuses.tick` bites
		# at every boundary up to and including the status's last one.
		var rounds: int = maxi(1,(int(worn.bleed)-int(s.time))/100+1)
		worn.erase("bleed")
		announce(s,target.pos,"boiling",source)
		react_damage(s,source,target,rounds*2,"fire")
	if int(target.hp) <= 0: return
	if element == "air" and is_wet(s,target) and fresh_reaction(s,target,"electrocute"):
		hang(s,target,"stun",STUN_TICKS)
		announce(s,target.pos,"electrocute",source)
	if worn.has("confuse") and worn.has("taunt") and fresh_reaction(s,target,"betrayal"): betray(s,target,source)

## 혼란 + 도발: the confused one strikes the nearest of its own side beside it
## instead of whoever taunted it. Nothing happens with nobody beside it.
static func betray(s, target: Dictionary, source: Dictionary) -> bool:
	var victims: Array = (s.party+s.npcs+s.enemies).filter(func(o): return int(o.hp) > 0 and int(o.id) != int(target.id) and s.side_of(o) == s.side_of(target) and s.melee_reach(target.pos,o.pos))
	if victims.is_empty(): return false
	victims.sort_custom(func(a,b): return int(a.id) < int(b.id))
	announce(s,target.pos,"betrayal",source)
	s.CombatRules.attack(s,target,victims[0])
	return true
```

`tile_react`의 `"ice"` 분기에 있는 `s.Statuses.apply(s,standing,"freeze",100)`를 `s.Statuses.apply(s,standing,"freeze",100,source)`로 바꾼다.

`expedition/combat/statuses.gd` 머리에 `const Reactions = preload("res://expedition/combat/reactions.gd")`를 넣고 `apply`를 바꾼다.

```gdscript
## `source` is whoever hung it, when known: a reaction it sets off is theirs.
static func apply(s, victim: Dictionary, status: String, ticks: int, source: Dictionary = {}) -> void:
	ticks = resisted_ticks(s,victim,status,ticks)
	if ticks <= 0: return
	victim.statuses[status] = s.time+ticks
	if status == "burn": victim.get_or_add("status_power",{})["burn"] = BURN_DAMAGE
	Reactions.status_react(s,victim,source,"","STATUS")
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in reactions spellbooks model_b_spells combat_basics model_b_combat tag_sets; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: 모두 0 failures. 주문 스위트가 화상과 중독을 같은 대상에 차례로 거는 시나리오에서 독 폭발 때문에 HP 기대값이 달라지면, 그 검사 앞에 대상의 다른 상태를 비우는 줄을 넣어 원래 의도(주문 하나의 효과)를 지킨다. 검사를 지우지 않는다.

- [ ] **Step 5: 커밋**

```bash
git commit -m "React statuses with each other: poison blast, shatter, boiling blood, electrocute, betrayal

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/combat/reactions.gd expedition/combat/statuses.gd tests/reactions.gd
```

---

### Task 4: 속성 세트와 출혈 태그

**Files:**
- Modify: `expedition/progression/essences.gd` (`ELEMENTS`, `row`)
- Modify: `expedition/progression/tag_sets.gd` (`TEXT`, `stat_bonus`, 옛 `on_hit`·`ELEMENT_STATUS` 삭제)
- Modify: `expedition/combat/reactions.gd` (`procs`, `extras`)
- Modify: `expedition/combat/combat_rules.gd` (`attack`의 옛 `TagSets.on_hit` 삭제, 무기 속성 부여를 덧붙는 피해로)
- Modify (기존 테스트): `tests/tag_sets.gd` (`elements`)
- Test: `tests/build_axes.gd` (신규)

**Interfaces:**
- Consumes: Task 1~3
- Produces: `Essences.ELEMENTS`에 `"bleed":"출혈"`. `Reactions.PROCS`, `Reactions.EXTRA_ELEMENTS := ["fire","ice","air","poison"]`, `Reactions.EXTRA_DAMAGE := 3`, `Reactions.procs(s, source, target)`, `Reactions.extras(s, source, target)`. `TagSets.TEXT`의 속성 여섯 줄. `TagSets.stat_bonus`의 저항은 출혈을 뺀 다섯 속성.

- [ ] **Step 1: 실패하는 테스트 쓰기**

`tests/build_axes.gd`:

```gdscript
extends SceneTree
## The three build axes: weapon × role set × element set. Element sets ride on
## every hit, bleeding is an element tag, and step three of a role set is a
## trigger.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Reactions = preload("res://expedition/combat/reactions.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Spells = preload("res://expedition/spells/spells.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	bleed_tag(); extras(); procs()
	print("Build axes: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.ev = 0; foe.ac = 0
	s.floor_state.observe(s)
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func bleed_tag() -> void:
	check(Essences.ELEMENTS.has("bleed") and Essences.ELEMENTS.bleed == "출혈","bleeding is the sixth element tag")
	check(Essences.has("GOBLIN_SHIV@bleed") and Essences.element("GOBLIN_SHIV@bleed") == "bleed","a bleed variant is an essence")
	check(not (Essences.row("GOBLIN_SHIV@bleed").stats as Dictionary).keys().any(func(k): return str(k).begins_with("res_")),"bleeding has no resistance to add")
	check(TagSets.TEXT.has("bleed") and TagSets.TEXT.bleed.has(2) and TagSets.TEXT.bleed.has(3),"the bleed set is described")
	var bleeder := {"level":2,"essences":{},"equipped_abilities":["GOBLIN_SHIV@bleed","RAT_GNAW@bleed"]}
	check(TagSets.level(bleeder,"bleed") == 2 and not TagSets.stat_bonus(bleeder).keys().any(func(k): return str(k).begins_with("res_")),"a bleed set grants no resistance")
	for element in ["fire","ice","air","poison","will"]:
		var pair := {"level":2,"essences":{},"equipped_abilities":["GOBLIN_SHIV@"+element,"RAT_GNAW@"+element]}
		check(int(TagSets.stat_bonus(pair).get("res_"+element,0)) == 20,"%s 2 gives twenty resistance" % element)
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_SHIV@bleed","RAT_GNAW@bleed"])
	d.foe.hp = 30
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"출혈 2 needs a bleeding target")
	d.foe.statuses["bleed"] = s.time+200
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 12,"출혈 2: a bleeding target takes a fifth more")

func extras() -> void:
	# 화염 2 puts three more fire on every hit: a sword, an active, a spell.
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL@fire","HOB_CLUB@fire"])
	var landed := false
	for attempt in range(30):
		d.foe.hp = 40; d.foe.statuses = {}
		Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.hero,d.foe)
		if not bool(out.hit): continue
		landed = true
		check(40-int(d.foe.hp) == int(out.damage)+Reactions.EXTRA_DAMAGE,"a sword blow carries three fire")
		break
	check(landed,"the sword lands within thirty tries")
	d.foe.hp = 40
	s.damage(d.foe,10,int(d.hero.id),"IMPACT")
	check(int(d.foe.hp) == 40-10-3,"an active's blow carries it")
	d.foe.hp = 40
	Spells.strike(s,d.hero,d.foe,{"school":"ice","element":"ice"},10,0,0)
	check(int(d.foe.hp) == 40-10-3,"an ice spell carries three fire too")
	d.foe.hp = 40
	Rules.damage(s,d.hero,d.foe,10,"fire")
	check(int(d.foe.hp) == 40-12-3,"a fire hit is a fifth stronger and still carries three")
	d.foe.hp = 40; d.foe.statuses = {"burn":s.time+100}; d.foe.get_or_add("status_power",{})["burn"] = 4
	Statuses.tick(s)
	check(int(d.foe.hp) == 36,"a burn ticking carries nothing: it is no hit")
	d.foe.hp = 40
	Reactions.react_damage(s,d.hero,d.foe,5,"poison")
	check(int(d.foe.hp) == 35,"reaction damage carries nothing")
	d.foe.hp = 40; d.foe.res = {"fire":50}
	Rules.damage(s,d.hero,d.foe,10,"physical")
	check(int(d.foe.hp) == 40-10-1,"the extra fire meets the target's fire resistance")
	d.foe.res = {}
	slot(d.hero,["GOBLIN_HEXER","GNOLL_SUMMONER"])
	d.foe.hp = 40
	Rules.damage(s,d.hero,d.foe,10,"physical")
	check(int(d.foe.hp) == 30,"의지 2 carries no extra damage")

func procs() -> void:
	var table := {"fire":["burn",["LIZARD_TAIL@fire","HOB_CLUB@fire","RAT_GNAW@fire"]],
		"ice":["freeze",["LIZARD_TAIL@ice","HOB_CLUB@ice","RAT_GNAW@ice"]],
		"poison":["poison",["LIZARD_TAIL@poison","HOB_CLUB@poison","RAT_GNAW@poison"]],
		"will":["confuse",["GOBLIN_HEXER","GNOLL_SUMMONER","RAT_GNAW@will"]],
		"bleed":["bleed",["GOBLIN_SHIV@bleed","RAT_GNAW@bleed","HOB_CLUB@bleed"]]}
	for element in table:
		var d := duo(); var s = d.s
		slot(d.hero,table[element][1])
		var status: String = table[element][0]
		var landed := 0
		for i in range(120):
			d.foe.hp = 40; d.foe.statuses = {}
			Reactions.begin_action(s)
			Reactions.on_hit(s,d.hero,d.foe,"physical",5,"HIT")
			if d.foe.statuses.has(status): landed += 1
		check(landed > 0 and landed < 60,"%s 3: some hits hang %s (%d of 120)" % [element,status,landed])
		var from_extras := 0
		for i in range(60):
			d.foe.hp = 40; d.foe.statuses = {}
			Reactions.begin_action(s)
			Reactions.on_hit(s,d.hero,d.foe,"physical",5,"EXTRA")
			if d.foe.statuses.has(status): from_extras += 1
		check(from_extras == 0,"%s 3: an extra hit carries no proc" % element)
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL@air","HOB_CLUB@air","RAT_GNAW@air"])
	d.foe.hp = 39
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"전기 3 needs a wet target")
	d.foe.statuses["wet"] = s.time+200
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 13,"전기 3: a wet target takes thirty percent more")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --editor --import --quit; godot --headless --path . --script res://tests/build_axes.gd`
Expected: FAIL — `ELEMENTS`에 `bleed` 없음.

- [ ] **Step 3: 출혈 태그**

`expedition/progression/essences.gd`:
- `const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지"}`를 `const ELEMENTS := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지","bleed":"출혈"}`로 바꾼다.
- `row`의 변종 분기를 바꾼다.

```gdscript
	var element := variant_element(id)
	if not element.is_empty():
		result.element = element
		# Bleeding has no resistance: a bleed variant adds none.
		if element != "bleed":
			var key := "res_"+element
			result.stats[key] = int(result.stats.get(key,0))+10
```

- [ ] **Step 4: 세트 설명과 스탯 보너스**

`expedition/progression/tag_sets.gd`의 `TEXT`를 통째로 바꾼다(역할 3단계 설명은 Task 5가 쓰는 효과다).

```gdscript
const TEXT := {
	"PACK":{2:"인접 아군당 피해 +1",3:"반응이 터지면 반경 3 아군의 다음 공격 피해 +20%"},
	"BERSERK":{2:"체력 절반 미만이면 공격 지연 −15",3:"처치할 때 HP 5 회복, 액티브 재사용 대기 −1"},
	"AMBUSH":{2:"첫 공격 피해 +30%",3:"피할 때 다음 공격 확정 치명(×1.5)"},
	"GUARD":{2:"방어 +2, 막기 +5",3:"막을 때 공격자에게 반격(무기 피해 절반, 속성 포함)"},
	"ARCHER":{2:"원거리 사거리 +1",3:"원거리 공격 지연 −15, 상태이상 대상에게 원거리 피해 +20%"},
	"CASTER":{2:"최대 MP +5",3:"주문 실패율 −10, 반응 피해 +30%"},
	"fire":{2:"화염 저항 +20, 모든 명중에 화염 피해 +3, 화염 피해 +20%",3:"모든 명중 15% 화상"},
	"ice":{2:"냉기 저항 +20, 모든 명중에 냉기 피해 +3, 냉기 피해 +20%",3:"모든 명중 10% 빙결"},
	"air":{2:"전기 저항 +20, 모든 명중에 전기 피해 +3, 전기 피해 +20%",3:"젖은 대상에게 피해 +30%"},
	"poison":{2:"독 저항 +20, 모든 명중에 독 피해 +3, 독 피해 +20%",3:"모든 명중 15% 중독"},
	"will":{2:"의지 저항 +20, 상태이상 지속 +30%",3:"모든 명중 10% 혼란"},
	"bleed":{2:"출혈 중인 대상에게 피해 +20%",3:"모든 명중 15% 출혈"}}
## The elements a set lends resistance to: every one but bleeding.
const RESISTED := ["fire","ice","air","poison","will"]
```

`stat_bonus`의 속성 루프를 바꾼다.

```gdscript
	for element in RESISTED:
		if level(actor,element) >= 2: result["res_"+element] = 20
```

`const ELEMENT_STATUS := ...` 줄과 옛 `on_hit` 함수(`## Element step three: a landed blow may hang the element's own status.`부터 함수 끝까지)를 지운다.

`outgoing`을 다음으로 바꾼다(역할 3단계 소비는 Task 5에서 더한다).

```gdscript
## What a set adds to a blow `attacker` is about to land. Monsters wear no
## essences, so this is a party member's (or a fallen adventurer's) business.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	if target.is_empty(): return amount
	if level(attacker,"PACK") >= 2: amount += adjacent_allies(s,attacker)
	if level(attacker,"AMBUSH") >= 2 and fresh(target): amount = amount*13/10
	if level(attacker,"bleed") >= 2 and target.get("statuses",{}).has("bleed"): amount = amount*12/10
	if level(attacker,"air") >= 3 and s.Reactions.is_wet(s,target): amount = amount*13/10
	return amount

static func adjacent_allies(s, actor: Dictionary) -> int:
	var count := 0
	for other in s.party+s.npcs+s.enemies:
		if int(other.id) != int(actor.id) and int(other.hp) > 0 and s.side_of(other) == s.side_of(actor) and s.melee_reach(actor.pos,other.pos): count += 1
	return count
```

- [ ] **Step 5: 확률과 덧붙는 피해**

`expedition/combat/reactions.gd`의 상수 목록에 넣는다.

```gdscript
const EXTRA_DAMAGE := 3
const EXTRA_ELEMENTS := ["fire","ice","air","poison"]
## Element step three: the status, its chance in a hundred and its ticks.
const PROCS := {"fire":["burn",15,300],"ice":["freeze",10,100],"poison":["poison",15,300],"will":["confuse",10,200],"bleed":["bleed",15,300]}
```

`on_hit`을 최종 형태로 바꾼다.

```gdscript
## Everything a landed blow sets off, in order: the ground under the target,
## the target's statuses, the attacker's element procs, then the attacker's
## element extras. The statuses react before the procs so a blow never
## shatters the ice its own proc just laid; a proc's status reacts on its own
## as it is hung. An extra hit reacts with the ground and the statuses but
## carries no proc and no extra of its own.
static func on_hit(s, source: Dictionary, target: Dictionary, element: String, amount: int, form: String) -> void:
	if source.is_empty() or form not in [HIT_FORM,EXTRA_FORM]: return
	target["last_hit"] = amount
	if target.has("pos"): tile_react(s,target.pos,element,amount,source)
	if int(target.hp) <= 0: return
	status_react(s,target,source,element,form)
	if int(target.hp) <= 0: return
	if form == HIT_FORM: procs(s,source,target)
	if form == HIT_FORM: extras(s,source,target)
```

파일 끝에 붙인다.

```gdscript
static func procs(s, source: Dictionary, target: Dictionary) -> void:
	for element in PROCS:
		if int(target.hp) <= 0 or TagSets.level(source,element) < 3: continue
		var row: Array = PROCS[element]
		if s.CombatRules.roll(s,source,target,"set_"+element,100) < int(row[1]):
			s.Statuses.apply(s,target,str(row[0]),int(row[2]),source)

## Element step two: three more of each element the attacker's sets carry,
## each its own hit against its own resistance.
static func extras(s, source: Dictionary, target: Dictionary) -> void:
	for element in EXTRA_ELEMENTS:
		if int(target.hp) <= 0: return
		if TagSets.level(source,element) >= 2: s.CombatRules.damage(s,source,target,EXTRA_DAMAGE,element,0,EXTRA_FORM)
```

- [ ] **Step 6: 전투 규칙 정리**

`expedition/combat/combat_rules.gd`의 `attack`에서
- `TagSets.on_hit(s,source,target)` 줄을 지운다(명중 뒤 처리는 `damage`가 부르는 `Reactions.on_hit`이 맡는다).
- `"fire", "ice": out.damage += damage(s, source, target, 4, str(offense.brand))`를 `"fire", "ice": out.damage += damage(s, source, target, 4, str(offense.brand), 0, Reactions.EXTRA_FORM)`로 바꾼다.

- [ ] **Step 7: 옛 테스트 고치기**

`tests/tag_sets.gd`의 `elements()`에서
- `check(int(d.foe.hp) == 28,"화염 2: fire hits a fifth harder")` → `check(int(d.foe.hp) == 40-12-3,"화염 2: fire hits a fifth harder and carries three more")`
- `check(int(d.foe.hp) == 30,"and only fire")` → `check(int(d.foe.hp) == 40-10-3,"an ice hit is not stronger, but still carries three fire")`
- 화상 루프

```gdscript
	var burns := 0
	for i in range(80):
		d.foe.hp = 40; d.foe.statuses = {}
		TagSets.on_hit(s,d.hero,d.foe)
		if d.foe.statuses.has("burn"): burns += 1
```

를 다음으로 바꾼다.

```gdscript
	var burns := 0
	for i in range(80):
		d.foe.hp = 40; d.foe.statuses = {}
		s.Reactions.begin_action(s)
		s.Reactions.on_hit(s,d.hero,d.foe,"physical",5,"HIT")
		if d.foe.statuses.has("burn"): burns += 1
```

- 전기 3 두 검사는 젖은 칸으로 판단하므로 그대로 통과한다(`is_wet`이 칸도 읽는다).

- [ ] **Step 8: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in build_axes tag_sets reactions essences stats_resist combat_basics model_b_combat spellbooks; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: 모두 0 failures.

- [ ] **Step 9: 커밋**

```bash
git add tests/build_axes.gd
git commit -m "Element sets ride on every hit; bleeding becomes the sixth element tag

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/progression/essences.gd expedition/progression/tag_sets.gd expedition/combat/reactions.gd expedition/combat/combat_rules.gd tests/build_axes.gd tests/tag_sets.gd
```

---

### Task 5: 역할 세트 3단계 발동

**Files:**
- Modify: `expedition/progression/tag_sets.gd` (`on_dodge`, `on_block`, `on_kill`, `on_reaction`, `outgoing`의 소비와 사수 3단계, `incoming`, 옛 `sure_hit`·`ally_guard` 삭제)
- Modify: `expedition/progression/stat_sheet.gd` (옛 수호 3단계 줄 삭제)
- Modify: `expedition/combat/combat_rules.gd` (`attack`의 회피·막기 발동, `sure` 삭제)
- Modify: `expedition/combat/reactions.gd` (`announce`가 무리 발동을 부름)
- Modify (기존 테스트): `tests/tag_sets.gd` (`pack`, `ambush`, `guard`, `berserk`), `tests/essences.gd` (`sets`)
- Test: `tests/build_axes.gd` (함수 추가)

**Interfaces:**
- Consumes: Task 1~4
- Produces: `TagSets.on_dodge(s, defender, attacker)`, `TagSets.on_block(s, defender, attacker)`, `TagSets.on_kill(s, killer)`, `TagSets.on_reaction(s, source)`, `TagSets.ranged(s, actor) -> bool`, `TagSets.statused(target) -> bool`. 상태 `poised`(다음 공격 ×1.5), `rally`(다음 공격 +20%).

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/build_axes.gd`의 `run()`에 `roles()`를 더하고 파일 끝에 붙인다.

```gdscript
func roles() -> void:
	# 기습 3: a dodge makes the next blow a sure critical.
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"])
	check(not TagSets.stat_bonus(d.hero).has("ev"),"기습 3 lends no evasion any more")
	Reactions.begin_action(s)
	TagSets.on_dodge(s,d.hero,d.foe)
	check(d.hero.statuses.has("poised"),"a dodge readies a critical")
	d.foe.hp = 30
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 15 and not d.hero.statuses.has("poised"),"the next blow is half again and spends it")
	var dodged := false
	for attempt in range(80):
		d.hero.hp = int(d.hero.max_hp); d.hero.statuses = {}
		Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.foe,d.hero)
		if bool(out.evaded): dodged = d.hero.statuses.has("poised"); break
	check(dodged,"a real dodge readies it too")
	# 수호 3: a block strikes back with half the weapon and the element extras.
	d = duo(); s = d.s
	slot(d.hero,["HOB_CLUB","HOB_CLUB@fire","HOB_CLUB@ice"])
	var counter: int = maxi(1,int(Stats.stats(s,d.hero).damage)/2)
	Reactions.begin_action(s)
	TagSets.on_block(s,d.hero,d.foe)
	check(int(d.foe.hp) == 40-counter,"a block strikes back for half the weapon")
	TagSets.on_block(s,d.hero,d.foe)
	check(int(d.foe.hp) == 40-counter,"once in an action")
	check(StatSheet.sheet(s,d.ally).ac.parts.all(func(p): return p.from != "수호 세트"),"수호 3 no longer lends the ally armour")
	slot(d.hero,["HOB_CLUB","HOB_CLUB@fire","HOB_CLUB@ice","LIZARD_TAIL@fire"])
	d.foe.hp = 40
	Reactions.begin_action(s)
	TagSets.on_block(s,d.hero,d.foe)
	check(int(d.foe.hp) == 40-counter-3,"the counter carries the fire set's extra")
	d.hero.gear.shield = {"type":"shield"}
	d.foe.hp = 40
	var blocked := false
	for attempt in range(80):
		d.hero.hp = int(d.hero.max_hp)
		Reactions.begin_action(s)
		var out: Dictionary = Rules.attack(s,d.foe,d.hero)
		if bool(out.blocked): blocked = int(d.foe.hp) < 40; break
	check(blocked,"a real block strikes back")
	# 광폭 3: a kill heals five and takes a round off every cooldown.
	d = duo(); s = d.s
	slot(d.hero,["ORC_CLEAVER","GNOLL_SPEAR","ORC_CLEAVER@fire"])
	d.hero.hp = 20; d.hero.cooldowns = {"X":3}; d.foe.hp = 1
	s.damage(d.foe,5,int(d.hero.id),"SLASH")
	check(int(d.hero.hp) == 25 and int(d.hero.cooldowns.X) == 2,"광폭 3: a kill heals five and shortens cooldowns")
	# 사수 3: a statused target takes a fifth more from range.
	d = duo(); s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	slot(d.hero,["KOBOLD_SLING","KOBOLD_SLING@ice","KOBOLD_SLING@fire"])
	d.foe.pos = d.c+Vector2i(3,0); d.foe.hp = 30
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"사수 3 needs a status on the target")
	d.foe.statuses["wet"] = s.time+200
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"being wet is no status for it")
	d.foe.statuses["slow"] = s.time+200
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 12,"사수 3: a slowed target takes a fifth more from range")
	d.foe.pos = d.c+Vector2i(1,0)
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"but not point-blank")
	# 술사 3: reactions bite harder.
	d = duo(); s = d.s
	slot(d.hero,["GOBLIN_HEXER","GNOLL_SUMMONER","FIRE_CALLER"])
	check(Reactions.reaction_damage(d.hero,10) == 13 and Reactions.reaction_damage(d.ally,10) == 10,"술사 3: reaction damage +30%")
	# 무리 3: a reaction rallies the allies around.
	d = duo(); s = d.s
	slot(d.hero,["RAT_GNAW","RIVER_RAT_SPLASH","RAT_GNAW@ice"])
	check(TagSets.incoming(s,d.hero,5) == 5,"무리 3 no longer takes one less")
	s.tile(d.foe.pos).wet = 50
	Reactions.begin_action(s)
	Reactions.tile_react(s,d.foe.pos,"ice",5,d.hero)
	check(d.ally.statuses.has("rally") and not d.hero.statuses.has("rally"),"a reaction rallies the allies around, not the wearer")
	d.foe.hp = 30
	check(TagSets.outgoing(s,d.ally,d.foe,10) == 12 and not d.ally.statuses.has("rally"),"the rallied blow is a fifth stronger, once")
	var source: String = FileAccess.get_file_as_string("res://expedition/progression/tag_sets.gd")
	check(not source.contains("func sure_hit") and not source.contains("func ally_guard"),"the old step-three effects are gone")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/build_axes.gd`
Expected: FAIL — `TagSets.on_dodge` 없음.

- [ ] **Step 3: 발동 효과 쓰기**

`expedition/progression/tag_sets.gd`:
- `sure_hit`, `ally_guard` 두 함수를 지운다.
- `incoming`을 바꾼다.

```gdscript
## Kept for the passive hook: no set lowers damage taken any more.
static func incoming(_s, _target: Dictionary, amount: int) -> int:
	return amount
```

- `outgoing`의 `return amount` 바로 위에 넣는다.

```gdscript
	if level(attacker,"ARCHER") >= 3 and ranged(s,attacker) and s.distance(attacker.pos,target.pos) > 1 and statused(target): amount = amount*12/10
	var worn: Dictionary = attacker.get("statuses",{})
	if worn.has("poised"):
		worn.erase("poised"); amount = amount*3/2
		s.message("%s 치명타" % str(attacker.get("name","")))
	if worn.has("rally"):
		worn.erase("rally"); amount = amount*12/10
```

- `on_kill`을 바꾸고, 파일 끝에 나머지 발동을 붙인다.

```gdscript
## 광폭 3: a kill heals five and takes a round off every cooldown.
static func on_kill(s, killer: Dictionary) -> void:
	if int(killer.get("hp",0)) <= 0 or level(killer,"BERSERK") < 3 or not s.Reactions.once(s,killer,"BERSERK"): return
	killer.hp = mini(int(killer.max_hp),int(killer.hp)+5)
	for id in killer.get("cooldowns",{}): killer.cooldowns[id] = maxi(0,int(killer.cooldowns[id])-1)

static func ranged(s, actor: Dictionary) -> bool:
	return str(s.CombatStats.stats(s,actor).trait) == "ranged"

## A status that counts as one for 사수 3: anything but being wet or a set's own mark.
static func statused(target: Dictionary) -> bool:
	return target.get("statuses",{}).keys().any(func(k): return str(k) not in ["wet","poised","rally"])

## 기습 3: a dodge readies the next blow as a sure critical.
static func on_dodge(s, defender: Dictionary, _attacker: Dictionary) -> void:
	if int(defender.get("hp",0)) <= 0 or level(defender,"AMBUSH") < 3 or not s.Reactions.once(s,defender,"AMBUSH"): return
	defender.statuses["poised"] = int(s.time)+300
	s.message("%s · 기습 태세" % str(defender.get("name","")))

## 수호 3: a block strikes back once, for half the weapon, with the element
## sets' extras riding on it.
static func on_block(s, defender: Dictionary, attacker: Dictionary) -> void:
	if int(defender.get("hp",0)) <= 0 or int(attacker.get("hp",0)) <= 0 or level(defender,"GUARD") < 3: return
	if not s.melee_reach(defender.pos,attacker.pos) or not s.Reactions.once(s,defender,"GUARD"): return
	var amount: int = maxi(1,int(s.CombatStats.stats(s,defender).damage)/2)
	s.message("%s · 반격" % str(defender.get("name","")))
	s.CombatRules.damage(s,defender,attacker,amount,"physical",0,s.Reactions.COUNTER_FORM)
	s.Reactions.extras(s,defender,attacker)

## 무리 3: a reaction this member set off rallies every ally within three.
static func on_reaction(s, source: Dictionary) -> void:
	if int(source.get("hp",0)) <= 0 or level(source,"PACK") < 3 or not s.Reactions.once(s,source,"PACK"): return
	for ally in s.party+s.npcs+s.enemies:
		if int(ally.id) == int(source.id) or int(ally.hp) <= 0 or s.side_of(ally) != s.side_of(source): continue
		if maxi(absi(ally.pos.x-source.pos.x),absi(ally.pos.y-source.pos.y)) <= 3: ally.statuses["rally"] = int(s.time)+300
```

- [ ] **Step 4: 연결**

`expedition/combat/reactions.gd`의 `announce` 끝에 넣는다.

```gdscript
	if not source.is_empty(): TagSets.on_reaction(s,source)
```

`expedition/combat/combat_rules.gd`의 `attack`에서
- `var sure: bool = TagSets.sure_hit(source,target)` 줄을 지운다.
- `if not sure and roll(s, source, target, "dodge", 100) < dodge:`를 `if roll(s, source, target, "dodge", 100) < dodge:`로, `if not sure and roll(s, source, target, "block", 100) < int(defense.sh):`를 `if roll(s, source, target, "block", 100) < int(defense.sh):`로 바꾼다.
- 회피 분기의 `return out` 바로 위에 `TagSets.on_dodge(s,target,source)`를, 막기 분기의 `return out` 바로 위에 `TagSets.on_block(s,target,source)`를 넣는다.

`expedition/progression/stat_sheet.gd`의 `add(result,"ac","수호 세트",TagSets.ally_guard(s,actor))` 줄을 지운다.

- [ ] **Step 5: 옛 테스트 고치기**

`tests/tag_sets.gd`:
- `pack()`의 세 줄을 바꾼다.
  - `check(TagSets.outgoing(s,d.hero,d.foe,10) == 12,"무리 3: two more per adjacent ally")` → `check(TagSets.outgoing(s,d.hero,d.foe,10) == 11,"무리 3 keeps step two's one per ally")`
  - `check(Passives.outgoing(s,d.hero,d.foe,10) == 13,"the passives run the set too (rat passive +1, set +2)")` → `check(TagSets.level(d.hero,"PACK") == 3,"three rats make step three")`
  - `check(TagSets.incoming(s,d.hero,5) == 4 and Passives.incoming(s,d.hero,5) == 4,"무리 3: one less taken")` → `check(TagSets.incoming(s,d.hero,5) == 5,"무리 3 no longer takes one less")`
- `ambush()`의 `check(not TagSets.sure_hit(d.hero,d.foe),"기습 2 is no sure hit")`부터 함수 끝(`check(clean,"기습 3: the first blow on a fresh foe always lands")`)까지를 다음으로 바꾼다.

```gdscript
	check(not d.hero.statuses.has("poised"),"기습 2 readies nothing")
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire","GOBLIN_SHIV@ice"])
	check(StatSheet.sheet(s,d.hero).ev.parts.all(func(p): return p.from != "세트"),"기습 3 lends no evasion any more")
	s.Reactions.begin_action(s)
	TagSets.on_dodge(s,d.hero,d.foe)
	check(d.hero.statuses.has("poised"),"기습 3: a dodge readies a critical")
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 15,"the critical is half again")
	check(TagSets.outgoing(s,d.hero,d.foe,10) == 10,"and spent")
```

- `berserk()`의 `check(int(d.foe.hp) <= 0 and int(d.hero.hp) == 25,"광폭 3: a kill heals five")`는 그대로 둔다.
- `guard()`를 통째로 바꾼다.

```gdscript
func guard() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["HOB_CLUB","HOB_CLUB@fire","HOB_CLUB@ice"])
	check(not StatSheet.sheet(s,d.ally).ac.parts.any(func(p): return p.from == "수호 세트"),"수호 3 lends the ally no armour any more")
	var counter: int = maxi(1,int(Stats.stats(s,d.hero).damage)/2)
	s.Reactions.begin_action(s)
	TagSets.on_block(s,d.hero,d.foe)
	check(int(d.foe.hp) == 40-counter,"수호 3: a block strikes back for half the weapon")
	d.foe.pos = d.c+Vector2i(3,0)
	s.Reactions.begin_action(s)
	TagSets.on_block(s,d.hero,d.foe)
	check(int(d.foe.hp) == 40-counter,"only at arm's length")
```

`tests/essences.gd`의 `sets()`에서 `check(int(TagSets.stat_bonus(ambush).ev) == 5,"기습 3 gives evasion")`를 `check(not TagSets.stat_bonus(ambush).has("ev"),"기습 3 lends no evasion any more")`로 바꾼다.

- [ ] **Step 6: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; for t in build_axes tag_sets essences reactions stats_resist combat_basics model_b_combat parts companion_tactics; do godot --headless --path . --script "res://tests/$t.gd" 2>&1 | tail -1; done`
Expected: 모두 0 failures.

- [ ] **Step 7: 커밋**

```bash
git commit -m "Turn step three of every role set into a trigger

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/progression/tag_sets.gd expedition/progression/stat_sheet.gd expedition/combat/combat_rules.gd expedition/combat/reactions.gd tests/build_axes.gd tests/tag_sets.gd tests/essences.gd
```

---

### Task 6: 반응 화면과 전체 스위트

**Files:**
- Modify: `expedition/ui/board.gd` (반응 이름, 증기·얼음·독 웅덩이 칸)
- Test: `tests/reactions.gd` (함수 추가), 전체 스위트

**Interfaces:**
- Consumes: Task 2의 알림 모양 `{"kind":"REACTION","from":cell,"cell":cell,"text":이름}`과 칸 필드
- Produces: `Board.draw_reaction(effect, canvas)`

- [ ] **Step 1: 실패하는 테스트 추가**

`tests/reactions.gd`의 `run()`에 `await board()`를 더하고(`print` 줄 앞, `run`이 `await`를 쓰므로 `func run() -> void:`는 그대로 둔다), 파일 끝에 붙인다.

```gdscript
func board() -> void:
	var source: String = FileAccess.get_file_as_string("res://expedition/ui/board.gd")
	check(source.contains("func draw_reaction") and source.contains("kind == \"REACTION\": draw_reaction"),"the board draws reaction names")
	check(source.contains("steam_until") and source.contains("poison_pool") and source.contains("\"ice\""),"the board draws steam, ice and poison pools")
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var d := duo(); var s = d.s
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	s.tile(d.foe.pos).wet = 50
	Reactions.tile_react(s,d.foe.pos,"fire",10,d.hero)
	Reactions.tile_react(s,d.other.pos,"ice",5,d.hero)
	scene.refresh()
	for frame in range(3): await process_frame
	check(s.effects.any(func(e): return e.get("kind","") == "REACTION"),"a reaction reaches the board without an error")
	scene.queue_free()
```

`run()`은 이렇게 된다.

```gdscript
func run() -> void:
	forms()
	ground()
	statuses()
	await board()
	print("Reactions: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/reactions.gd`
Expected: FAIL — `the board draws reaction names`.

- [ ] **Step 3: 그리기**

`expedition/ui/board.gd`:
- 효과 루프

```gdscript
		elif kind == "MISS": draw_miss(effect,canvas)
		elif effect.has("amount"): draw_hit(effect,canvas)
```

를 다음으로 바꾼다.

```gdscript
		elif kind == "MISS": draw_miss(effect,canvas)
		elif kind == "REACTION": draw_reaction(effect,canvas)
		elif effect.has("amount"): draw_hit(effect,canvas)
```

- `draw_miss` 함수 바로 아래에 붙인다.

```gdscript
## A reaction's name, bigger and warmer than a miss, rising over its cell.
func draw_reaction(effect: Dictionary, canvas: Node2D) -> void:
	var t := clock_of(effect)
	if t < 0 or t >= 1.1: return
	var center := cell_center(effect.cell)-Vector2(0,half_width*(1.6+t*0.9))
	var grow := 1.0+0.6*maxf(0,1.0-t/0.12)
	draw_outlined(canvas,center,str(effect.get("text","")),int(24*grow),Color(1.0,0.86,0.35,clampf((1.1-t)/0.35,0,1)))
```

- 칸 그리기에서 `if cell.wet > 0 and cell.terrain != "water": outline(polygon,Color(0.3,0.6,0.8,0.6))` 줄 바로 아래에 넣는다.

```gdscript
			if bool(cell.get("ice",false)):
				draw_colored_polygon(polygon,Color(0.78,0.92,1.0,0.55)); outline(polygon,Color("e8f7ff"),2)
			if bool(cell.get("poison_pool",false)):
				draw_colored_polygon(polygon,Color(0.35,0.75,0.2,0.4))
			if int(cell.get("steam_until",0)) > int(session.time):
				draw_colored_polygon(polygon,Color(0.9,0.9,0.92,0.55))
```

- [ ] **Step 4: 통과 확인**

Run: `godot --headless --path . --editor --import --quit; godot --headless --path . --script res://tests/reactions.gd`
Expected: 0 failures.

- [ ] **Step 5: 전체 스위트**

```bash
godot --headless --path . --editor --import --quit
fails=0; for f in tests/*.gd; do n=$(basename $f .gd); case $n in floor_fixture|model_b_runner|difficulty_gate) continue;; esac; out=$(timeout 600 godot --headless --path . --script "res://tests/$n.gd" 2>&1); code=$?; if [ $code -ne 0 ] || echo "$out" | grep -q "SCRIPT ERROR\|^ERROR:"; then echo "FAIL $n"; fails=$((fails+1)); fi; done; echo "failing suites: $fails"
```

Expected: `failing suites: 0`. 이 계획 전부터 깨져 있던 스위트가 있으면, 깨끗한 작업 트리(`git worktree add /tmp/base HEAD~6`)에서 같은 실패가 나는지 확인하고 보고에 적는다. 반응 때문에 HP 기대값이 달라진 옛 검사는 반응이 일어나지 않게 상황을 정리해(젖은 칸을 말리거나 상태를 비워) 원래 의도를 지킨다. 검사를 지우지 않는다.

- [ ] **Step 6: 검사 수 확인**

Run: `for f in reactions build_axes; do grep -c "check(" tests/$f.gd; done`
Expected: 두 스위트 합계가 지운 옛 3단계 검사(무리 −1, 기습 확정 명중과 회피, 수호 인접 방어 3줄, 에센스 기습 회피 1줄) 7개보다 훨씬 많다.

- [ ] **Step 7: 커밋**

```bash
git commit -m "Show reactions on the board: names over their cells, steam, ice and poison pools

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/ui/board.gd tests/reactions.gd
```

---

## 스펙 대응표

| 스펙 | 작업 |
|---|---|
| §0.6 빌드 세 축, 출혈 태그 | Task 4 |
| §0.8 원소 반응과 발동 조건 | Task 1~3, 5 |
| §5.1 속성 태그 여섯, 2단계 덧붙는 피해와 저항, 3단계 모든 명중 확률, 출혈 2·3단계 | Task 4 |
| §5.1 "모든 명중"의 범위(무기, 액티브, 주문; 반응·반사·반격 제외) | Task 1(형태), Task 4(검사) |
| §5.2 역할 3단계 발동, 옛 3단계 삭제 | Task 5 |
| §6 기존 시뮬레이션 위에 얹기, `reactions.gd` | Task 1~3 |
| §6.1 칸 반응 넷, 칸 필드, 얼음 이동, 증기 시야 | Task 2 |
| §6.2 상태이상 반응 다섯, 젖음, 반응 형태, 반응 피해 주인 | Task 1, 3 |
| §6.3 안전장치, 판정 순서, 표시 | Task 1(중복 방지), Task 4(순서), Task 2·6(표시) |
| §4 방어 액티브, 감소 효과 비겹치기, 도발 | 계획 2/4. 이 계획은 `taunt` 상태를 읽기만 한다 |
| §1 위험 칸(깊은 물·독 늪이 젖음·전도 칸) | 계획 1/4가 필드를 만든다. 이 계획은 `deep_water`, `bog`를 칸 필드와 지형 이름 둘 다로 읽는다 |
