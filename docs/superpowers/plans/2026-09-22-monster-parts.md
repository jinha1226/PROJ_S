# 몬스터 시그니처 파츠 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 종족마다 패시브+액티브 한 쌍의 시그니처 "파츠"를 두고, 적은 예고 뒤 그것을 쓰며, 플레이어는 드롭·상점으로 얻은 파츠(밀치기·엄호 포함)를 마을에서 2슬롯에 장착해 쓴다.

**Architecture:** `abilities.gd`의 카탈로그 한 항목이 적 공격이자 플레이어 파츠다(접근법 A). 밀치기·엄호도 카탈로그 항목(effect `PUSH`/`GUARD`)이 되어 `session.act`의 스킬별 분기가 사라진다. 패시브는 `passives.gd`의 닫힌 종류 목록과 `damage()`/`end_round()`의 훅 네 개로만 구현한다. 적 AI는 술사 시전의 `charging` 상태를 `cast_id/cast_left`로 일반화해 파츠 예고에 재사용한다. 규칙 카탈로그(`Rules.SKILLS`)는 상수 대신 `Abilities.DEFINITIONS`에서 파생된다.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트(`godot --headless --path . --script res://tests/<name>.gd`), CI 스위트 목록 `.github/workflows/deploy-pages.yml`.

**Spec:** `docs/superpowers/specs/2026-09-22-monster-parts-design.md` — 충돌 시 스펙이 우선.

## Global Constraints

- **Godot 창을 절대 띄우지 않는다.** 모든 실행은 `--headless`. 에디터 임포트 검사도 `godot --headless --path . --editor --import --quit`.
- 커밋 작성자 `jinha1226 <jinha1226@gmail.com>` (`git -c user.name=jinha1226 -c user.email=jinha1226@gmail.com commit …`). 커밋 메시지 끝에 `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- 스킬별·종족별 분기 코드 0줄: `match def.effect`와 `match passive.kind` 외에 특정 id를 비교하는 분기를 새로 만들지 않는다. 남는 리터럴 id는 `STARTING_PARTS`, `BASIC_BADGES`(ATTACK/MOVE/WAIT), 상점 행, 테스트뿐이다.
- `tactic_rules.gd`는 `abilities.gd`를 `preload`하지 않는다(순환). `load()` + `static var` 캐시.
- 1층 힘 상한: 파츠 액티브 피해는 스펙 §3 표의 값 그대로(최대 14), 패시브 +1~+3. 수치는 6번 태스크의 게이트 결과로만 바꾼다.
- 한국어 UI 문자열은 스펙에 적힌 그대로 쓴다: 탭 "파츠", "파츠 슬롯 N / 2", "빈 슬롯", "가방에 파츠 없음", "시험 로드아웃 · 파츠 %d종 지급 — 파츠 탭에서 장착하세요.", 상점 "밀치기 요령"·"엄호 요령".
- 각 태스크 끝에 해당 스위트와 `abilities_growth protect companion_tactics skill_rule_conditions skill_archetypes solo_floor encounter_sim ui_smoke`가 통과해야 한다(태스크 본문에 명시된 예외 제외). 최종적으로 CI 목록 전체가 통과한다.
- 테스트 러너 규약: 각 스위트는 `extends SceneTree`, `_initialize()`에서 `call_deferred("run")`, 실패 수를 세어 `quit(1 if failures else 0)`, 마지막에 `print("<이름>: %d checks, %d failures")`.

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `expedition/abilities.gd` | 카탈로그(`DEFINITIONS`), 합법성·실행(`legal/execute/resolve/power`), `species_part`, `droppable`, `default_rule`, `badge` |
| `expedition/passives.gd` (신규) | 패시브 종류 목록 `KINDS`와 훅 `of/outgoing/incoming/after_hit/round_start` |
| `expedition/tactic_rules.gd` | 규칙 스키마·검증·조건 평가; `skill(id)`/`catalog()`가 카탈로그를 파생 |
| `expedition/monster_ai.gd` | 역할 행동 + 시그니처 준비/해결/끊기 |
| `expedition/session.gd` | `parts_bag`, 장착/해제, 드롭, 상점 `part:`, 스냅샷, `damage()`/`end_round()` 훅 |
| `expedition/tactical_action_selector.gd` | 후보 생성(밀치기·엄호는 장착 시에만) |
| `expedition/continuous_floor.gd`, `expedition/boss_trial.gd` | 적 `part_id` |
| `expedition/board.gd`, `expedition/main.gd`, `expedition/character_ui.gd` | 예고 배지, 파츠 탭, 가방, 상점, 결과 |
| `expedition/sim/encounter_runner.gd`, `data/content/reference_builds.json`, `data/content/balance_experiments.json` | 빌드·계측 |
| `tests/parts.gd` (신규), `tests/floor_fixture.gd`, `tests/map_fixture.gd`, 기존 스위트 | 검증 |

---

### Task 1: 밀치기·엄호를 카탈로그 파츠로 — `Abilities` 양측 공용화, `Rules` 파생

**Files:**
- Modify: `expedition/abilities.gd` (전면), `expedition/tactic_rules.gd`, `expedition/session.gd` (`make_actor`, `_init`, `act`, `reservation_choice`, `reset_rules`), `expedition/tactical_action_selector.gd`, `expedition/board.gd:272`, `expedition/main.gd:298,380,657,662,765`, `expedition/character_ui.gd:174-175,195`, `expedition/sim/encounter_runner.gd:84`
- Modify tests: `tests/floor_fixture.gd`, `tests/map_fixture.gd`, `tests/skill_rule_conditions.gd`, `tests/companion_tactics.gd`, `tests/skill_archetypes.gd`, `tests/protect.gd`, `tests/test_loadout.gd`, 그리고 `"PUSH"`/`"GUARD"`를 `act`하는 스위트(`enemy_turns mobile_actions integration monster_roles expedition_skills character_ui party_guard_probe`)
- Test: `tests/parts.gd` (신규, 이 태스크에서는 카탈로그·기본 파츠 검사만)

**Interfaces:**
- Produces: `Abilities.DEFINITIONS[id]` 필드 `species passive enemy allies_hit tile_wet`; `Abilities.resolve(s, actor, id, target) -> void`; `Abilities.power(s, actor, def) -> int`; `Abilities.species_part(species_id) -> String`; `Rules.skill(id) -> Dictionary`; `Rules.catalog() -> Dictionary`; `Rules.defaults() == []`; `Abilities.STARTERS` 삭제; `Abilities.equip` 삭제.
- Consumes: 없음 (첫 태스크).

- [ ] **Step 1: `tests/parts.gd` 골격과 카탈로그 검사(실패하는 테스트) 작성**

```gdscript
extends SceneTree
## Monster signature parts: catalog shape, basic parts (PUSH/GUARD) as catalog
## entries, passives, enemy telegraphs, town-only equipping, drops and snapshots.
const Session = preload("res://expedition/session.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	catalog()
	basic_parts()
	print("Parts: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Every definition carries the part fields and a rule the schema accepts.
func catalog() -> void:
	for id in Abilities.DEFINITIONS:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		for key in ["species","passive","enemy","allies_hit","tile_wet"]:
			check(def.has(key),"%s has field %s" % [id,key])
		check(def.effect in ["DAMAGE","SHIELD","HEAL","LUNGE","PUSH","GUARD"],"%s effect known" % id)
		check(def.target in ["ENEMY","SELF","ALLY"],"%s target known" % id)
		check(int(def.enemy.get("prep",-1)) >= 0 and int(def.enemy.get("prep",-1)) <= 2,"%s prep in 0..2" % id)
		check(Rules.catalog().has(id),"%s in the derived rule catalog" % id)
		check(Rules.valid(Abilities.default_rule(id)),"%s default rule valid" % id)
	check(not Abilities.DEFINITIONS.has("drop") and not "drop" in Abilities.DEFINITIONS.PUSH,"drop field removed")
	check(Rules.skill("GUARD").targets == ["ALLY"] and Rules.skill("GUARD").conditions == ["ALLY_LETHAL"],"guard advertises ally/lethal")
	check(Rules.skill("PUSH").targets == ["NEAREST","LOWEST_HP"] and "CHARGING" in Rules.skill("PUSH").conditions,"push advertises enemy targets")
	check(Rules.skill("IRON_HIDE").targets == ["SELF"] and Rules.skill("IRON_HIDE").conditions == ["ALWAYS","HP","STATUS","DANGER"],"self skills advertise self conditions")
	check(Rules.skill("NOPE").is_empty(),"unknown skill is empty")
	check(Rules.defaults().is_empty(),"no rules before equipping")
	check(Abilities.default_rule("GUARD").target == "ALLY" and Abilities.default_rule("GUARD").when == "ALLY_LETHAL","guard default rule")
	check(Abilities.default_rule("PUSH").target == "NEAREST" and Abilities.default_rule("PUSH").when == "CHARGING","push default rule")
	check(Abilities.badge("PUSH") == Abilities.DEFINITIONS.PUSH.short and Abilities.badge("ATTACK") == "공격","badges from catalog and basics")

## 밀치기·엄호 run through the catalog path and need a slot.
func basic_parts() -> void:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]; var ally: Dictionary = s.party[1]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0
	foe.pos = c+Vector2i(1,0); ally.pos = c+Vector2i(0,1)
	s.floor_state.observe(s); s.selected = 0
	# Companions keep no actions so their turns cannot disturb the case.
	for actor in s.party: actor.ap = 0
	hero.ap = 3
	check(hero.equipped_abilities == ["",""] and hero.rules.is_empty(),"floor party starts with empty slots and no rules")
	check(not s.act("PUSH",foe.pos),"push needs a slot")
	check(not s.act("GUARD",ally.pos),"guard needs a slot")
	check(not s.Tactics.choose(s,hero).kind in ["PUSH","GUARD"],"tactics offer no unequipped basics")
	hero.equipped_abilities = ["PUSH","GUARD"]
	hero.rules = [Abilities.default_rule("PUSH"),Abilities.default_rule("GUARD")]
	var before: Vector2i = foe.pos
	check(s.act("PUSH",foe.pos) and foe.pos == before+Vector2i(1,0) and hero.ap == 2,"push moves the foe one cell and costs an action")
	check(s.act("GUARD",ally.pos) and hero.guarded and ally.protected_by == hero.id,"guard covers the adjacent ally")
	check(not s.act("GUARD",foe.pos) and not s.act("GUARD",hero.pos),"guard rejects foes and self")
	var legacy = Session.new(731,true,true)
	check(legacy.party[0].equipped_abilities == ["PUSH","GUARD"] and legacy.party[0].rules.size() == 2,"non-floor modes start with the basics equipped")
```

- [ ] **Step 2: 실패 확인**

Run: `godot --headless --path . --script res://tests/parts.gd 2>&1 | tail -5`
Expected: 파싱 오류 또는 `has field species` 류 실패.

- [ ] **Step 3: `expedition/abilities.gd`를 아래로 교체**

```gdscript
extends RefCounted
## Parts catalog. One definition is both a monster's signature attack and the
## item the player equips: `passive` applies while equipped (or always, for the
## owning species), the active is executed by `resolve` for either side.
const DROP_PERCENT := 50
const NO_PASSIVE := {}
const IMMEDIATE := {"prep":0,"target":"NEAREST"}
const DEFINITIONS = {
	"PUSH":{"name":"밀치기","item":"밀치기 요령","description":"인접한 적을 한 칸 밀어냅니다. 밀 곳이 없으면 피해 8. 적의 예고 공격을 취소합니다.","target":"ENEMY","range":1,"radius":0,"damage":8,"cooldown":0,"effect":"PUSH","axis":"MELEE","rule_when":"CHARGING","short":"밀치기","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"GUARD":{"name":"엄호","item":"엄호 요령","description":"인접 아군이 받을 피해를 대신 받고 절반만 입습니다.","target":"ALLY","range":1,"radius":0,"damage":0,"cooldown":0,"effect":"GUARD","axis":"","rule_when":"ALLY_LETHAL","short":"엄호","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"SHOCKWAVE":{"name":"수렁 충격파","item":"수렁의 핵","description":"범위 2 · 피해 16 · 아군 피해 · 재사용 3턴","target":"SELF","range":0,"radius":2,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"충격파","shape":"CIRCLE","self_hit":false,"icon":4,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":true,"tile_wet":0},
	"BOMB":{"name":"폭탄 투척","item":"암살자의 화약낭","description":"사거리 4 · 범위 1 · 피해 16 · 아군 피해 · 재사용 3턴","target":"ENEMY","range":4,"radius":1,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"폭탄","shape":"SQUARE","self_hit":true,"icon":3,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":true,"tile_wet":0},
	"IRON_HIDE":{"name":"철갑 방어","item":"거인의 철갑핵","description":"받는 피해 -75% · 1턴 · 재사용 3턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":3,"effect":"SHIELD","axis":"","rule_when":"DANGER","short":"철갑","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"HEAVY_STRIKE":{"name":"시험 강타","item":"시험용 강타 문양","description":"인접 대상 · 피해 28 · 재사용 3턴","target":"ENEMY","range":1,"radius":0,"damage":28,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"강타","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"THROWING_KNIFE":{"name":"시험 투척","item":"시험용 투척 문양","description":"사거리 4 · 피해 10 · 재사용 1턴","target":"ENEMY","range":4,"radius":0,"damage":10,"cooldown":1,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"투척","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"FIELD_DRESSING":{"name":"시험 응급처치","item":"시험용 처치 문양","description":"자신 체력 +15 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"heal":15,"cooldown":4,"effect":"HEAL","axis":"","rule_when":"HP","short":"응급","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"LUNGE":{"name":"시험 돌진","item":"시험용 돌진 문양","description":"사거리 3 · 적 옆으로 이동 후 피해 12 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":12,"cooldown":3,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS","short":"돌진","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0}}
## Actions that are not catalog parts.
const BASIC_BADGES := {"ATTACK":"공격","MOVE":"이동","WAIT":"대기"}

## Part ids that a species drops, in DEFINITIONS insertion order.
static func droppable() -> Array:
	var result: Array = []
	for id in DEFINITIONS:
		if not str(DEFINITIONS[id].species).is_empty(): result.append(id)
	return result

## The signature part of `species_id`, or "" when the species has none.
static func species_part(species_id: String) -> String:
	for id in DEFINITIONS:
		if str(DEFINITIONS[id].species) == species_id: return id
	return ""

## Short badge text for any action kind, catalog part or basic action.
static func badge(kind: String) -> String:
	return str(DEFINITIONS[kind].short) if DEFINITIONS.has(kind) else str(BASIC_BADGES.get(kind,kind))

static func default_rule(id: String) -> Dictionary:
	var def: Dictionary = DEFINITIONS[id]
	var target: String = {"SELF":"SELF","ALLY":"ALLY"}.get(def.target,"NEAREST")
	return preload("res://expedition/tactic_rules.gd").make_rule(id,target,def.rule_when)

## Nearest free cell adjacent to the target that the actor can reach within the part's range.
static func lunge_cell(s, actor: Dictionary, id: String, target: Vector2i) -> Vector2i:
	var def: Dictionary = DEFINITIONS[id]
	var best := Vector2i(-1,-1)
	var best_len := 1 << 30
	for d in s.DIRECTIONS:
		var cell: Vector2i = target+d
		if not s.inside(cell) or not s.is_free(cell) or not s.melee_reach(cell,target): continue
		var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,[cell],func(a,b): return s.can_step(a,b),func(_p): return 100)
		if not route.found: continue
		var steps: int = route.path.size()-1
		if steps > int(def.range): continue
		if steps < best_len or (steps == best_len and str(cell) < str(best)): best = cell; best_len = steps
	return best

static func cells(s, actor: Dictionary, id: String, target: Vector2i) -> Array:
	var result: Array = []
	if not DEFINITIONS.has(id): return result
	var def: Dictionary = DEFINITIONS[id]
	var center: Vector2i = actor.pos if def.target == "SELF" else target
	for y in range(maxi(0,center.y-def.radius),mini(s.BOARD_SIDE,center.y+def.radius+1)):
		for x in range(maxi(0,center.x-def.radius),mini(s.BOARD_SIDE,center.x+def.radius+1)):
			var cell := Vector2i(x,y)
			var in_range: bool = s.distance(center,cell) <= def.radius if def.shape == "CIRCLE" else maxi(absi(center.x-x),absi(center.y-y)) <= def.radius
			if in_range and s.tile(cell).terrain != "wall" and s.TurnCore.Geometry.sees(center,cell,func(p): return s.tile(p).terrain == "wall"): result.append(cell)
	return result

## Party members grow; monsters hit for the listed damage plus the floor's darkness bonus.
static func power(s, actor: Dictionary, def: Dictionary) -> int:
	if actor.enemy: return int(def.damage)+(s.floor_state.enemy_bonus(s.light) if s.floor_mode else 0)
	return s.Growth.power(actor,def.axis,int(def.damage))

## Whether `actor` holds the part: a slot for party members, the species signature for monsters.
static func holds(actor: Dictionary, id: String) -> bool:
	return str(actor.get("part_id","")) == id if actor.enemy else id in actor.equipped_abilities

static func legal(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not DEFINITIONS.has(id) or not holds(actor,id) or actor.cooldowns.get(id,0) > 0: return false
	if s.phase != "BATTLE" or actor.hp <= 0 or not s.inside(target): return false
	if not actor.enemy and actor.ap <= 0: return false
	var def: Dictionary = DEFINITIONS[id]
	if def.target == "SELF":
		if def.effect == "HEAL" and actor.hp >= actor.max_hp: return false
		return target == actor.pos
	var victim: Dictionary = s.at(target)
	if victim.is_empty() or victim.hp <= 0: return false
	if def.target == "ALLY":
		return victim.enemy == actor.enemy and victim.id != actor.id and s.melee_reach(actor.pos,target)
	if victim.enemy == actor.enemy: return false
	# distance() is Manhattan, so a range-1 skill would miss the diagonals a
	# basic attack reaches; "adjacent" means melee_reach everywhere else.
	var in_range: bool = s.melee_reach(actor.pos,target) if int(def.range) == 1 else s.distance(actor.pos,target) <= int(def.range)
	if not in_range or not s.TurnCore.Geometry.sees(actor.pos,target,func(p): return s.tile(p).terrain == "wall"): return false
	if def.effect == "LUNGE": return lunge_cell(s,actor,id,target) != Vector2i(-1,-1)
	return true

static func execute(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not legal(s,actor,id,target): return false
	resolve(s,actor,id,target)
	return true

## Resolves the part on `target` without a legality check: a telegraphed
## monster part lands on the announced cell whoever stands there now.
static func resolve(s, actor: Dictionary, id: String, target: Vector2i) -> void:
	var def: Dictionary = DEFINITIONS[id]
	var victim: Dictionary = s.at(target)
	# The use is logged first so that a miss is the last line the log shows.
	if def.effect not in ["GUARD","PUSH"]: s.message(actor.name+" · "+def.name)
	match def.effect:
		"SHIELD": actor.iron_guard = true
		"HEAL":
			actor.hp = mini(int(actor.max_hp),int(actor.hp)+int(def.heal))
			s.Body.heal(actor)
		"GUARD":
			actor["guarded"] = true
			victim["protected_by"] = actor.id
			s.message("%s · 엄호 → %s" % [actor.name,victim.name])
		"PUSH":
			if victim.is_empty(): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else:
				var destination: Vector2i = target+(target-actor.pos)
				if s.can_step(target,destination): victim.pos = destination
				else: s.damage(victim,power(s,actor,def),actor.id,"IMPACT")
				s.intents = s.intents.filter(func(intent): return intent.id != victim.id)
				if s.floor_mode: s.Floor.MonsterAI.interrupt(s,victim)
				elif s.boss_trial and victim.get("charging",false):
					victim.charging = false; victim.fuse = 0; victim.cooldown = 6; victim.recovery = 1
				s.message("밀쳐내기 · 적의 예고 공격을 취소했습니다.")
		"LUNGE":
			var cell := lunge_cell(s,actor,id,target)
			if cell != Vector2i(-1,-1): actor.pos = cell
			if victim.is_empty() or cell == Vector2i(-1,-1): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else:
				s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":[target],"area":false,"amount":0,"form":"SLASH"})
				s.damage(victim,power(s,actor,def),actor.id,"SLASH")
		"DAMAGE":
			var affected := cells(s,actor,id,target)
			var amount: int = power(s,actor,def)
			s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":affected,"area":true,"amount":0,"form":"IMPACT"})
			var hit := 0
			for other in s.party+s.enemies:
				if other.hp <= 0 or other.id == actor.id or other.pos not in affected: continue
				if not def.allies_hit and other.enemy == actor.enemy: continue
				s.damage(other,amount,actor.id,"IMPACT"); hit += 1
			# Bombs can also hit the caster; self-centered shockwaves cannot.
			if def.self_hit and actor.pos in affected: s.damage(actor,amount,actor.id,"IMPACT"); hit += 1
			for cell in affected:
				if int(def.tile_wet) > 0: s.tile(cell).wet = maxi(int(s.tile(cell).wet),int(def.tile_wet))
			if hit == 0 and def.target != "SELF": s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
	if int(def.cooldown) > 0: actor.cooldowns[id] = int(def.cooldown)+1
	if actor.enemy: s.stats_enemy_skill[id] = int(s.stats_enemy_skill.get(id,0))+1
```

주의: `heal` 키는 FIELD_DRESSING에만 있다(기존과 동일). `tile.wet`이 `wet` 키로 저장되는 것은 `continuous_floor.apply`의 타일 생성과 같다.

- [ ] **Step 4: `expedition/tactic_rules.gd` 수정 — `SKILLS` 삭제, 파생 카탈로그**

파일 머리(`const SKILLS = {...}` 블록과 `BASIC_TARGETS`까지)를 다음으로 바꾼다. `TARGET_NAMES`부터 아래는 그대로 두되 `defaults()`와 `valid()`·`summary()`의 `SKILLS` 참조만 바꾼다.

```gdscript
extends RefCounted
## Shared rule schema: UI and AI use the same catalog and validation. The
## catalog itself is derived from the parts catalog so that no skill id is
## listed twice; abilities.gd preloads this file, so it is loaded lazily here.
const CONDITIONS_BY_TARGET := {
	"SELF":["ALWAYS","HP","STATUS","DANGER"],
	"ENEMY":["ALWAYS","HP","STATUS","CHARGING","DANGER"],
	"ALLY":["ALLY_LETHAL"]}
const TARGETS_BY_TARGET := {"SELF":["SELF"],"ENEMY":["NEAREST","LOWEST_HP"],"ALLY":["ALLY"]}
static var _catalog: Dictionary = {}
const BASIC_TARGETS = ["NEAREST","LOWEST_HP"]
const BASIC_TARGET_DEFAULT = "NEAREST"

## Rule catalog: {id: {name, description, targets, conditions}} for every part.
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var definitions: Dictionary = load("res://expedition/abilities.gd").DEFINITIONS
		for id in definitions:
			var def: Dictionary = definitions[id]
			_catalog[id] = {"name":str(def.name),"description":str(def.description),
				"targets":TARGETS_BY_TARGET[def.target].duplicate(),"conditions":CONDITIONS_BY_TARGET[def.target].duplicate()}
	return _catalog

static func skill(id: String) -> Dictionary:
	return catalog().get(id,{})
```

그리고:

```gdscript
static func defaults() -> Array:
	return []
```

`valid()`의 첫 두 줄:

```gdscript
	var def: Dictionary = skill(rule.get("skill",""))
	if def.is_empty(): return false
```

`summary()`는 변경 없음(`SKILLS` 미사용).

- [ ] **Step 5: `session.gd` — `make_actor`·`_init`·`act`·`reservation_choice`·`reset_rules`**

`make_actor`의 두 줄을 바꾼다:

```gdscript
		"rules":Rules.defaults(),
		...
		"equipped_abilities":["",""],"cooldowns":{},"iron_guard":false,
```
(`"learned_abilities":["PUSH","GUARD"],` 삭제.)

`_init` 끝(파티 생성 루프 뒤)에 추가:

```gdscript
	# Room and boss modes have no town to buy the basics in: start with them equipped.
	if not floor_mode:
		for actor in party:
			actor.equipped_abilities = ["PUSH","GUARD"]
			actor.rules = [Abilities.default_rule("PUSH"),Abilities.default_rule("GUARD")]
```

`act()`: `if companions and kind in Abilities.STARTERS and kind not in actor.equipped_abilities: return false` 줄 삭제. `match kind:`에서 `"GUARD":` 분기 전체와 `"ATTACK", "PUSH":` 분기의 PUSH 부분을 제거해 다음이 되게 한다:

```gdscript
		"ATTACK":
			if victim.is_empty() or not victim.enemy or not melee_reach(actor.pos,target): return false
			var hit := TurnCore.physical(Growth.power(actor,"MELEE",18) * actor.attack_factor / 100, 1000, 0, 2)
			damage(victim, int(hit.damage), actor.id, "SLASH")
```

`reservation_choice()`를 다음으로 바꾼다:

```gdscript
func reservation_choice(actor: Dictionary) -> Dictionary:
	var order: Dictionary = actor.reservation
	if order.is_empty() or actor.hp <= 0 or actor.ap <= 0 or phase != "BATTLE": return {}
	var cell: Vector2i = order.cell
	var def: Dictionary = Abilities.DEFINITIONS.get(order.kind,{})
	if order.kind == "ATTACK" or def.get("target","") == "ENEMY":
		var target: Dictionary = {}
		for enemy in enemies:
			if enemy.id == order.target_id and enemy.hp > 0: target = enemy; break
		if target.is_empty(): return {}
		if not def.is_empty():
			if not Abilities.legal(self,actor,order.kind,target.pos): return {}
		elif attack_preview(target.pos,actor.id).is_empty(): return {}
		cell = target.pos
	elif order.kind == "MOVE":
		if cell not in movement_cells(actor.id): return {}
	elif order.kind == "WAIT": cell = actor.pos
	elif not def.is_empty():
		if def.target == "SELF": cell = actor.pos
		if not Abilities.legal(self,actor,order.kind,cell): return {}
	else: return {}
	return {"kind":order.kind,"cell":cell,"reason":"직접 예약","reserved":true}
```

`reset_rules()`:

```gdscript
func reset_rules(index: int) -> void:
	var actor: Dictionary = party[index]
	actor.rules = Rules.defaults(); actor.basic_target = Rules.BASIC_TARGET_DEFAULT
	for id in actor.equipped_abilities:
		if Abilities.DEFINITIONS.has(id): actor.rules.append(Abilities.default_rule(id))
```

`var essences`, `roll_essence`, `consume_essence`, `equip_ability`, `grant_test_loadout`은 이 태스크에서 손대지 않는다(Task 2). 단 `grant_test_loadout`·`consume_essence`가 `learned_abilities`를 읽어 실행 시 오류가 나므로, 이 태스크에서는 두 함수 본문을 `return false`로 임시 축소하고 `tests/test_loadout.gd`·`tests/abilities_growth.gd`는 이 태스크의 통과 목록에서 제외한다(Task 2에서 복구). `session.gd` 상단 `var stats_redirects := 0` 아래에 `var stats_enemy_skill: Dictionary = {}`와 `var stats_interrupts := 0`을 추가한다(`resolve`가 쓴다).

- [ ] **Step 6: `tactical_action_selector.gd` — 장착 시에만 밀치기·엄호 후보**

`for enemy in s.combat_enemies():` 루프 안, `options.append({"kind":"ATTACK",…})` 다음 줄부터 `options.append({"kind":"PUSH",…})`까지의 밀치기 블록을 `if "PUSH" in actor.equipped_abilities:` 아래로 들여쓴다(계산은 그대로). 엄호 블록:

```gdscript
	# 엄호 has no self form: one candidate per adjacent living ally.
	if "GUARD" in actor.equipped_abilities:
		for mate in s.alive():
			if mate.id != actor.id and s.melee_reach(actor.pos,mate.pos):
				options.append({"kind":"GUARD","cell":mate.pos,"score":35,"reason":"엄호"})
```

카탈로그 후보 루프는 PUSH/GUARD를 두 번 넣지 않도록 `if not s.Abilities.DEFINITIONS.has(id) or s.Abilities.DEFINITIONS[id].effect in ["PUSH","GUARD"]: continue`. `ruled.kind == "GUARD"` 조기 반환은 `s.Abilities.DEFINITIONS.get(ruled.kind,{}).get("target","") == "ALLY"`로. `rule_choice`의 `s.Rules.SKILLS[rule.skill].name` → `s.Rules.skill(rule.skill).name`.

- [ ] **Step 7: `Rules.SKILLS` 참조 치환**

- `board.gd:272`: `preview.kind in session.Rules.SKILLS` → `session.Rules.catalog().has(preview.kind)`
- `main.gd:298`: `Session.Rules.SKILLS.get(skill_id,{}).get("name",skill_id)` → `Session.Rules.skill(skill_id).get("name","빈 슬롯" if skill_id.is_empty() else skill_id)`; 같은 루프에서 `if skill_id.is_empty(): skill.disabled = true`.
- `main.gd:380`: `notice = "엄호 · 인접 아군 선택" if mode == "GUARD" else …` → `notice = "%s · %s" % [Session.Rules.skill(mode).get("name",mode),"인접 아군 선택" if Session.Abilities.DEFINITIONS.get(mode,{}).get("target","") == "ALLY" else "대상 칸 선택"]`
- `main.gd:657,662`: `Session.Rules.SKILLS[rule.skill]` → `Session.Rules.skill(rule.skill)`
- `main.gd:765`: 같은 치환(Task 5에서 함수 전체가 바뀐다).
- `character_ui.gd:174-175,195`: `ui.Session.Rules.SKILLS[x]` → `ui.Session.Rules.skill(x)`; 175행의 설명 폴백은 `ui.Session.Rules.skill(rule.skill).get("description","")`.
- `main.gd:303-305` 엄호 버튼 비활성 조건: `if skill_id == "GUARD" and …` → `if Session.Abilities.DEFINITIONS.get(skill_id,{}).get("target","") == "ALLY" and …`.
- `encounter_runner.gd:84`: `if s.Abilities.DEFINITIONS.has(kind):` (리터럴 목록 제거).

- [ ] **Step 8: 테스트 픽스처와 기존 스위트**

`tests/floor_fixture.gd`와 `tests/map_fixture.gd` 각각에 추가:

```gdscript
## Equips the two basics on every member with their default rules, the
## pre-parts starting state most suites assume.
static func equip_basics(s) -> void:
	var abilities = load("res://expedition/abilities.gd")
	for actor in s.party:
		actor.equipped_abilities = ["PUSH","GUARD"]
		actor.rules = [abilities.default_rule("PUSH"),abilities.default_rule("GUARD")]
```

층 모드 세션(`Session.new(…, true, …)` 네 번째 인자 true)을 만들고 밀치기·엄호나 그 규칙에 의존하는 스위트마다 세션 생성 직후 `Fixture.equip_basics(s)`(층) 또는 `MapFixture.equip_basics(s)`를 호출한다: `protect`(`arena()`), `skill_rule_conditions`(`arena()`: `hero.learned_abilities = …` 줄 삭제, `equipped_abilities = [skill,"GUARD"]`는 유지하되 규칙은 `[Abilities.default_rule(skill),Abilities.default_rule("GUARD")]`), `skill_archetypes`(16행 `learned_abilities` 줄 삭제), `companion_tactics`, `party_guard_probe`, `encounter_sim`(빌드가 `equipped`를 직접 넣으므로 변경 없음 — 확인만), `solo_balance`·`solo_floor`·`solo_recovery`·`torch_tradeoff`·`test_loadout`(이 태스크 제외)·`mobile_hud`·`mobile_exploration`·`terrain_layouts`·`continuous_floor`·`expedition_settlement`·`enemy_turns`·`monster_roles`·`expedition_skills`(수동)·`character_ui`(56행 `learned_abilities.append` 삭제; 그 검사는 Task 5에서 다시 쓴다).

`tests/skill_rule_conditions.gd`: `configurable()`은 `Abilities.DEFINITIONS.keys()`; `Rules.SKILLS.has(id)` → `Rules.catalog().has(id)`, `Rules.SKILLS[id]` → `Rules.skill(id)`, 226행 → `Rules.skill("GUARD")`. `tests/companion_tactics.gd:68`: `not s.Rules.SKILLS.has("ATTACK")` → `not s.Rules.catalog().has("ATTACK")`. `tests/skill_archetypes.gd:26`: `Rules.catalog().has(id)`.

- [ ] **Step 9: 실행**

Run: `for t in parts protect companion_tactics skill_rule_conditions skill_archetypes solo_floor encounter_sim ui_smoke enemy_turns mobile_actions integration monster_roles boss_trial playthrough character_ui terrain_layouts continuous_floor mobile_exploration curios torch_vision solo_recovery solo_balance torch_tradeoff solo_provisioning expedition_settlement mobile_hud floor_templates encounter_builder floor_generator; do echo "== $t"; godot --headless --path . --script res://tests/$t.gd 2>&1 | tail -2; done`
Expected: `parts` 통과; 나머지 통과. `abilities_growth`·`test_loadout`은 제외(Task 2). `expedition_settlement`·`solo_floor`·`torch_tradeoff`·`mobile_hud`·`continuous_floor`·`terrain_layouts`는 `essences`·`essence_id`·`learned_abilities`를 아직 참조하므로 실패할 수 있다 — 실패 원인이 그 참조뿐이면 통과로 간주하고 보고서에 적는다(Task 2가 고친다). `godot --headless --path . --editor --import --quit 2>&1 | grep -E 'SCRIPT ERROR|^ERROR' ; true`에서 스크립트 오류 0.

- [ ] **Step 10: 커밋**

```bash
git add -A expedition tests
git -c user.name=jinha1226 -c user.email=jinha1226@gmail.com commit -m "feat(parts): push and guard become catalog parts; rules derived from the catalog

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: 파츠 가방 — 장착·해제·드롭·상점·스냅샷·시험 로드아웃

**Files:**
- Modify: `expedition/session.gd`, `expedition/continuous_floor.gd:73-78`, `expedition/boss_trial.gd:30-31`, `expedition/main.gd` (essences/learned 참조 최소 수정), `expedition/character_ui.gd:188-199`
- Modify tests: `tests/abilities_growth.gd`, `tests/expedition_settlement.gd`, `tests/solo_floor.gd`, `tests/torch_tradeoff.gd`, `tests/mobile_hud.gd`, `tests/continuous_floor.gd`, `tests/terrain_layouts.gd`, `tests/test_loadout.gd`, `tests/skill_archetypes.gd:72-73`, `tests/character_ui.gd`
- Test: `tests/parts.gd` (`bag()` 추가)

**Interfaces:**
- Produces: `session.parts_bag: Dictionary`, `STARTING_PARTS`, `equip_part(index, slot, id) -> bool`, `unequip_part(index, slot) -> bool`, `roll_part(enemy)`, `SHOP`에 `part:PUSH`/`part:GUARD`, `stock/add_stock`의 `part:` 지원, `take_snapshot().parts`, `result.parts`, `enemy.part_id`.
- Consumes: Task 1의 `Abilities.species_part`, `default_rule`, `droppable`.

- [ ] **Step 1: 실패하는 테스트 — `tests/parts.gd`에 `bag()` 추가, `run()`에서 호출**

```gdscript
## Parts are items: town-only slots, one bag for the party, snapshot rules.
func bag() -> void:
	var s = Session.new(731,true,true,true,3)
	check(s.parts_bag == {"PUSH":1,"GUARD":1},"floor session starts with the two basics in the bag")
	check(s.stock("part:PUSH") == 1 and s.price("part:GUARD") == 10,"basics are shop goods")
	var bank: int = s.bank
	check(s.buy("part:GUARD") and s.parts_bag.GUARD == 2 and s.bank == bank-10,"buying a basic adds to the bag")
	check(s.refund("part:GUARD") and s.parts_bag.GUARD == 1 and s.bank == bank,"refund returns it")
	check(not s.provision_stock().has("part:PUSH") and s.provision_sale_value() == 0,"parts are never liquidated")
	check(not s.equip_part(0,2,"PUSH") and not s.equip_part(0,0,"BOMB") and not s.equip_part(0,0,"NOPE"),"bad slot, empty bag and unknown id refused")
	check(s.equip_part(0,0,"PUSH") and s.party[0].equipped_abilities[0] == "PUSH" and s.parts_bag.PUSH == 0,"equip takes the part from the bag")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "PUSH","equip adds the default rule")
	check(not s.equip_part(0,1,"PUSH"),"same part twice on one member refused")
	check(not s.equip_part(1,0,"PUSH"),"bag empty for the second member")
	s.parts_bag.PUSH = 1
	check(s.equip_part(1,0,"PUSH"),"another member may hold the same part")
	check(s.equip_part(0,0,"GUARD") and s.parts_bag.PUSH == 1 and s.party[0].equipped_abilities[0] == "GUARD","replacing returns the old part")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "GUARD","replacing swaps the rule")
	check(s.unequip_part(0,0) and s.party[0].equipped_abilities[0] == "" and s.parts_bag.GUARD == 1 and s.party[0].rules.is_empty(),"unequip empties the slot and the rule")
	check(not s.unequip_part(0,0),"empty slot cannot be unequipped")
	check(s.equip_part(0,0,"PUSH") and s.equip_part(0,1,"GUARD"),"both slots")
	s.depart()
	check(not s.equip_part(0,0,"PUSH") and not s.unequip_part(0,1),"slots are locked outside town")
	# Drops and the snapshot rule.
	Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	check(foe.part_id == Abilities.species_part(foe.species_id) and not foe.part_id.is_empty(),"floor monsters carry their species part")
	var tries := 0; var got := false
	for enemy in s.enemies:
		enemy.hp = 0; s.roll_part(enemy); tries += 1
		if s.parts_bag.get(enemy.part_id,0) > 0: got = true
	check(got,"some monster in the roster drops its part (%d tried)" % tries)
	var carried: Dictionary = s.parts_bag.duplicate(true)
	s.loot = 10; s.objective.state = "CARRIED"
	for enemy in s.enemies: enemy.hp = 0
	s.floor_state.observe(s)
	check(s.abandon() and s.parts_bag == carried,"abandon keeps found parts")
	check(s.result.has("parts") and not s.result.has("essences"),"result reports parts")
	s.refit(); s.depart(); Fixture.arena(s,8)
	var kept: Dictionary = s.parts_bag.duplicate(true)
	s.parts_bag["HOB_CLUB"] = int(s.parts_bag.get("HOB_CLUB",0))+3
	s.damage(s.party[0],999,999,"IMPACT"); s.damage(s.party[1],999,999,"IMPACT"); s.damage(s.party[2],999,999,"IMPACT"); s.check_battle_end()
	check(s.result.reason == "DEFEAT" and s.parts_bag == kept,"defeat restores the bag snapshot")
	# Test loadout.
	var t = Session.new(731,false,false,true)
	check(t.grant_test_loadout() and t.log_lines[-1].begins_with("시험 로드아웃 · 파츠"),"test loadout grants parts")
	for id in Abilities.DEFINITIONS: check(t.parts_bag.get(id,0) >= 1,"loadout has "+id)
	var snapshot: Dictionary = t.parts_bag.duplicate(true)
	check(t.grant_test_loadout() and t.parts_bag == snapshot,"loadout is idempotent")
	t.depart(); check(not t.grant_test_loadout(),"loadout refused outside town")
```

`HOB_CLUB`은 Task 3에서 정의되므로 이 태스크에서는 그 줄을 `"BOMB"`으로 쓰고 Task 3에서 `HOB_CLUB`으로 바꾼다.

- [ ] **Step 2: 실패 확인** — `godot --headless --path . --script res://tests/parts.gd 2>&1 | tail -3`. Expected: `parts_bag` 미정의 오류.

- [ ] **Step 3: `session.gd` 구현**

상단: `var essences: Dictionary = {}` → `var parts_bag: Dictionary = {}`; `const STARTING_PARTS := {"PUSH":1,"GUARD":1}`. `SHOP` 끝에 두 행 추가: `{"id":"part:PUSH","name":"밀치기 요령","price":10},{"id":"part:GUARD","name":"엄호 요령","price":10}`.

`_init`의 `if floor_mode:` 블록 안에 `parts_bag = STARTING_PARTS.duplicate(true)` 추가.

`stock`/`add_stock`에 한 줄씩:

```gdscript
	if id.begins_with("part:"): return int(parts_bag.get(id.substr(5),0))
```
```gdscript
	elif id.begins_with("part:"): parts_bag[id.substr(5)] = int(parts_bag.get(id.substr(5),0))+delta
```

`provision_stock`·`provision_sale_value`의 `for row in SHOP:` 바로 아래에 `if str(row.id).begins_with("part:"): continue`.

`roll_essence` → `roll_part`:

```gdscript
func roll_part(enemy: Dictionary) -> void:
	if not enemy.enemy or enemy.hp > 0 or enemy.get("part_rolled",false): return
	enemy.part_rolled = true
	for actor in alive():
		if Growth.gain(actor,100 if boss_trial and not floor_mode else 25) > 0: message(actor.name+" · 레벨 %d" % actor.growth.level)
	var id: String = str(enemy.get("part_id",""))
	if not Abilities.DEFINITIONS.has(id): return
	var chance: int = Floor.drop_percent(light) if floor_mode else Abilities.DROP_PERCENT
	if Hexaco.sample(seed_value,expedition_number*10000+room*100+enemy.id,"essence",100) >= chance: return
	parts_bag[id] = int(parts_bag.get(id,0))+1
	message(Abilities.DEFINITIONS[id].item+" 획득")
```
(`damage()` 끝의 `roll_essence(target)` 호출을 `roll_part(target)`로. `"essence"` 샘플 키는 시드 재현성을 위해 그대로 둔다.)

`consume_essence`·`equip_ability` 삭제, 대신:

```gdscript
## Town only: a part leaves the bag for a slot; the slot's old part returns to the bag.
func equip_part(index: int, slot: int, id: String) -> bool:
	if phase != "TOWN" or index < 0 or index >= party.size() or slot < 0 or slot >= 2: return false
	var actor: Dictionary = party[index]
	if actor.hp <= 0 or not Abilities.DEFINITIONS.has(id) or int(parts_bag.get(id,0)) <= 0: return false
	if id in actor.equipped_abilities: return false
	var old: String = str(actor.equipped_abilities[slot])
	if not old.is_empty(): unequip_part(index,slot)
	parts_bag[id] -= 1
	actor.equipped_abilities[slot] = id
	actor.reservation = {}
	if not actor.rules.any(func(r): return r.skill == id): actor.rules.append(Abilities.default_rule(id))
	return true

func unequip_part(index: int, slot: int) -> bool:
	if phase != "TOWN" or index < 0 or index >= party.size() or slot < 0 or slot >= 2: return false
	var actor: Dictionary = party[index]
	var old: String = str(actor.equipped_abilities[slot])
	if actor.hp <= 0 or old.is_empty(): return false
	actor.equipped_abilities[slot] = ""
	parts_bag[old] = int(parts_bag.get(old,0))+1
	actor.rules = actor.rules.filter(func(r): return r.skill != old)
	actor.reservation = {}
	return true

## Playtest helper: one of every catalog part in the bag, so loadouts can be tried without farming.
func grant_test_loadout() -> bool:
	if not floor_mode or phase != "TOWN" or party.is_empty(): return false
	var added := 0
	for id in Abilities.DEFINITIONS:
		if int(parts_bag.get(id,0)) > 0: continue
		parts_bag[id] = 1; added += 1
	message("시험 로드아웃 · 이미 전부 보유" if added == 0 else "시험 로드아웃 · 파츠 %d종 지급 — 파츠 탭에서 장착하세요." % added)
	return true
```

`take_snapshot`: `"parts":parts_bag.duplicate(true)`; `restore_snapshot`: `parts_bag = snapshot.parts.duplicate(true)`. `finish_expedition`: summary의 `"essences":{},"abilities":[]` → `"parts":{}`; 계산 블록:

```gdscript
		for id in parts_bag:
			var gained: int = int(parts_bag[id])-int(snapshot.parts.get(id,0))
			if gained > 0: summary.parts[id] = gained
```
(`hero.learned_abilities` 루프 삭제.)

- [ ] **Step 4: `continuous_floor.gd`·`boss_trial.gd`**

`continuous_floor.apply`의 드롭 순환 4줄(주석 포함)을 `enemy.part_id = Abilities.species_part(member.species_id)`로. `boss_trial.spawn`: `boss.part_id = drops[row.pattern % drops.size()]` — `droppable()`이 비어 있으면(Task 3 전) `boss.part_id = ""`가 되도록 `var drops: Array = Abilities.droppable(); boss.part_id = drops[row.pattern % drops.size()] if not drops.is_empty() else ""`.

- [ ] **Step 5: UI 컴파일 유지 (`main.gd`, `character_ui.gd`)**

- `main.gd:581`: `for id in r.parts: items.append("%s ×%d" % [Session.Abilities.DEFINITIONS[id].item,r.parts[id]])`
- `main.gd:708-711` 인벤토리 행: `session.parts_bag`로, 카테고리 `"파츠"`, 설명 `def.description`. 720행 카테고리 목록의 `"이능"` → `"파츠"`. 743-745행 "먹이기" 블록 삭제(Task 5에서 장착 버튼으로 대체). `show_essences`·`confirm_essence` 삭제; `build_abilities`의 `button(list,"가방",show_essences)` 줄 삭제, `for id in actor.learned_abilities:` 루프를 `for id in actor.equipped_abilities: if id.is_empty(): continue`로 바꾸고 장착 버튼 줄 삭제(Task 5에서 재작성).
- `character_ui.gd` `replace()`: `for id in actor.learned_abilities:` → `for id in ui.session.parts_bag: if int(ui.session.parts_bag[id]) <= 0: continue`, `equip_ability` → `equip_part`, `can_invest(ui,actor)` → `ui.session.phase == "TOWN" and actor.hp > 0`.
- `character_ui.gd:56` 머리글: `"파츠 슬롯 %d / 2" % actor.equipped_abilities.filter(func(id): return not str(id).is_empty()).size() if tab == "파츠" else …`, 탭 목록의 `"이능"` → `"파츠"`, `main.gd:632,638`의 `"이능"` → `"파츠"`(`CharacterUI.abilities` 호출은 유지).

- [ ] **Step 6: 기존 스위트 갱신**

- `abilities_growth.gd`: `essences` → `parts_bag`; `roll_essence` → `roll_part`; 27-35행 먹이기 검사를 장착 검사로: 세션을 `s.phase = "TOWN"`으로 두고 `s.parts_bag = {"SHOCKWAVE":2,"BOMB":1,"IRON_HIDE":1}`; `check(s.equip_part(1,0,"SHOCKWAVE") and s.parts_bag.SHOCKWAVE == 1,…)`, `check(not s.equip_part(1,1,"SHOCKWAVE"),…)`, `check(not s.equip_part(0,0,"NOPE") and not s.equip_part(1,2,"SHOCKWAVE"),…)`, `check(s.equip_part(0,0,"BOMB"),…)`; `s.phase = "BATTLE"` 이후는 그대로. 52행 `consume_essence(1,"IRON_HIDE") and equip_ability(1,1,"IRON_HIDE")` → `s.phase = "TOWN"; check(s.equip_part(1,1,"IRON_HIDE"),…)`. 첫 루프의 드롭 검사(`essences.get("SHOCKWAVE")`)는 `s.enemies[0].part_id`의 드롭 수(`parts_bag.get(enemy.part_id,0)`)로 바꾼다 — 보스 시련 세션(`Session.new(seed,true,true)`)의 적은 `boss_trial.spawn`이 만들며, Task 3 전에는 `part_id == ""`이므로 이 루프는 `check(dropped >= 0,…)`로 완화하고 Task 3에서 `dropped > 0 and dropped < 30`을 되살린다. UI 부분: `scene.show_essences()`·`confirm_essence` 두 줄 삭제; `"이능"` 문자열은 `"파츠"`; `EquippedAbility*` 카드 수 검사는 유지.
- `expedition_settlement.gd`: `s.essences.BOMB = 1` → `s.parts_bag.BOMB = 1`, 이하 `essences` → `parts_bag`.
- `solo_floor.gd:171,179,194,195`: `essences` → `parts_bag`.
- `torch_tradeoff.gd:49-51`: `essences` → `parts_bag`, `roll_essence` → `roll_part`; 적에게 `enemy.part_id = "BOMB"`를 넣어 준다(Task 3 전 종족 파츠 없음).
- `mobile_hud.gd:42-44`: `drop.essence_id` → `drop.part_id`, `roll_essence` → `roll_part`.
- `continuous_floor.gd:26`: `check(s.enemies.all(func(e): return e.part_id == Session.Abilities.species_part(e.species_id)),"floor monsters carry their species part")`.
- `terrain_layouts.gd:31`: `learned_abilities.append` 줄 삭제.
- `skill_archetypes.gd:72-73`: `s2.phase = "TOWN"; s2.parts_bag["FIELD_DRESSING"] = 1; check(s2.equip_part(0,0,"FIELD_DRESSING") and s2.party[0].rules.back().when == "HP" and s2.party[0].rules.back().subject == "SELF","equip_part uses the default rule")`.
- `test_loadout.gd`: `session_layer()`를 `parts_bag` 기준으로 다시 쓴다(모든 id ≥ 1, 두 번째 호출 변화 없음, 메시지 `"시험 로드아웃 · 파츠"`/`"시험 로드아웃 · 이미 전부 보유"`, 장비 불변, 마을 밖 거부, 방 모드 거부). `scene_layer()`의 `learned_abilities` 검사 → `parts_bag`, `show_character(0,"파츠")`, 이후 카드·`replace` 검사는 Task 5에서 완성하므로 여기서는 `cards` 검사까지만 남기고 `replace` 이후 줄은 삭제.
- `character_ui.gd`(테스트) 56행: `scene.session.parts_bag["BOMB"] = 1`; 65-67행은 `scene.session.phase = "TOWN"` 상태에서 `replace` 경로로 BOMB를 0번 칸에 넣는 흐름으로 바꾼다(`scene.session.equip_part(1,0,"BOMB")` 직접 호출 뒤 UI 확인).

- [ ] **Step 7: 실행** — Task 1의 Step 9 명령에 `abilities_growth test_loadout`을 더해 전부 통과. 에디터 임포트 스크립트 오류 0.

- [ ] **Step 8: 커밋** — `feat(parts): parts bag, town-only slots, drops by species, shop basics`

---

### Task 3: 종족 파츠 8종과 패시브

**Files:**
- Create: `expedition/passives.gd`
- Modify: `expedition/abilities.gd` (DEFINITIONS 8항목), `expedition/session.gd` (`damage`, `end_round`, `actor_by_id`)
- Test: `tests/parts.gd` (`species()`, `passives()`), `tests/abilities_growth.gd`(드롭 검사 복원), `tests/parts.gd` bag의 `"BOMB"` → `"HOB_CLUB"`

**Interfaces:**
- Produces: `Passives.KINDS`, `Passives.of(actor)`, `outgoing(s, attacker, target, amount)`, `incoming(s, target, amount)`, `after_hit(s, target, attacker, form)`, `round_start(s, actor)`; `session.actor_by_id(id) -> Dictionary`.
- Consumes: Task 1의 카탈로그 필드, Task 2의 `part_id`.

- [ ] **Step 1: 실패하는 테스트 — `tests/parts.gd`에 추가, `run()`에서 호출**

```gdscript
const Passives = preload("res://expedition/passives.gd")
const Builder = preload("res://expedition/encounter_builder.gd")

## One part per species on the roster, every passive kind known.
func species() -> void:
	for row in Builder.rows():
		var id: String = Abilities.species_part(row.species_id)
		check(not id.is_empty(),"%s has a signature part" % row.species_id)
		if id.is_empty(): continue
		var owners: Array = Abilities.DEFINITIONS.keys().filter(func(k): return Abilities.DEFINITIONS[k].species == row.species_id)
		check(owners.size() == 1,"%s has exactly one part" % row.species_id)
		var def: Dictionary = Abilities.DEFINITIONS[id]
		check(def.passive.kind in Passives.KINDS,"%s passive kind known" % id)
		check(int(def.enemy.prep) == 1,"%s floor-1 prep is 1" % id)
		check(int(def.damage) <= 14,"%s damage within the floor-1 cap" % id)
		check(int(def.passive.value) >= 1 and int(def.passive.value) <= 3,"%s passive value 1..3" % id)

## Two-member floor arena: hero at c, ally at c+(0,1), foe at c+(1,0), all fresh.
func duel() -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	Fixture.equip_basics(s)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0
	foe.pos = c+Vector2i(1,0); foe.part_id = ""
	s.party[1].pos = c+Vector2i(0,1); s.party[2].pos = c+Vector2i(-3,-3)
	s.light = 90; s.floor_state.observe(s); s.selected = 0
	for actor in s.party: actor.ap = 0
	s.party[0].ap = 3
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"far":s.party[2],"foe":foe}

func passives() -> void:
	# PACK: +1 per adjacent living ally of the attacker.
	var d := duel(); var s = d.s
	d.foe.part_id = "RAT_GNAW"
	var second: Dictionary = s.enemies[1]; second.hp = 30; second.max_hp = 30; second.pos = d.c+Vector2i(2,0); second.alert = true
	var third: Dictionary = s.enemies[2]; third.hp = 30; third.max_hp = 30; third.pos = d.c+Vector2i(2,1); third.alert = true
	check(Passives.outgoing(s,d.foe,d.hero,7) == 9,"pack adds one per adjacent ally (two)")
	second.hp = 0
	check(Passives.outgoing(s,d.foe,d.hero,7) == 8,"dead allies do not count")
	# RETALIATE: adjacent attacker takes 2 after the hit; no chain.
	d = duel(); s = d.s
	d.hero.equipped_abilities = ["LIZARD_TAIL","GUARD"]
	var foe_hp: int = d.foe.hp
	s.damage(d.hero,5,d.foe.id,"IMPACT")
	check(d.foe.hp == foe_hp-2,"retaliate returns two to the adjacent attacker")
	d.foe.part_id = "LIZARD_TAIL"; foe_hp = d.foe.hp; var hero_hp: int = d.hero.hp
	s.damage(d.hero,5,d.foe.id,"IMPACT")
	check(d.foe.hp == foe_hp-2 and d.hero.hp < hero_hp,"retaliation itself is not retaliated")
	d.foe.pos = d.c+Vector2i(3,0); foe_hp = d.foe.hp
	s.damage(d.hero,5,d.foe.id,"IMPACT")
	check(d.foe.hp == foe_hp,"no retaliation at range")
	# DIRTY: +3 against targets under half health.
	d = duel(); s = d.s; d.foe.part_id = "KOBOLD_SLING"
	d.hero.hp = int(d.hero.max_hp/2)
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"dirty needs strictly under half")
	d.hero.hp -= 1
	check(Passives.outgoing(s,d.foe,d.hero,7) == 10,"dirty adds three under half")
	# AMBUSHER: +3 against a target with no adjacent living ally.
	d = duel(); s = d.s; d.foe.part_id = "GOBLIN_SHIV"
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"ally adjacent: no ambush bonus")
	check(Passives.outgoing(s,d.foe,d.far,7) == 10,"isolated target: ambush bonus")
	# THICK_HIDE: -1, never below 1.
	d = duel(); s = d.s; d.foe.part_id = "HOB_CLUB"
	check(Passives.incoming(s,d.foe,5) == 4 and Passives.incoming(s,d.foe,1) == 1,"thick hide subtracts one, floor one")
	# BLOODLUST: +3 when the attacker is under half.
	d = duel(); s = d.s; d.foe.part_id = "ORC_CLEAVER"
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"bloodlust off at full health")
	d.foe.hp = 14
	check(Passives.outgoing(s,d.foe,d.hero,7) == 10,"bloodlust on under half")
	# REGEN: +2 at round start, capped.
	d = duel(); s = d.s; d.foe.part_id = "GNOLL_SPEAR"; d.foe.hp = 20
	Passives.round_start(s,d.foe)
	check(d.foe.hp == 22,"regen heals two")
	d.foe.hp = 29; Passives.round_start(s,d.foe)
	check(d.foe.hp == 30,"regen never exceeds max")
	# AMPHIBIOUS: +3 on wet or water.
	d = duel(); s = d.s; d.foe.part_id = "RIVER_RAT_SPLASH"
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"dry: no bonus")
	s.tile(d.foe.pos).wet = 40
	check(Passives.outgoing(s,d.foe,d.hero,7) == 10,"wet: bonus")
	# Hooks are wired: an equipped part's passive changes a real hit, and round start regenerates.
	d = duel(); s = d.s; d.hero.equipped_abilities = ["HOB_CLUB","GUARD"]
	hero_hp = d.hero.hp
	s.damage(d.hero,6,d.foe.id,"IMPACT")
	check(d.hero.hp == hero_hp-5,"equipped thick hide applies inside damage()")
	d.foe.part_id = "GNOLL_SPEAR"; d.foe.hp = 20
	s.act("WAIT",d.hero.pos); s.act("WAIT",d.hero.pos); s.act("WAIT",d.hero.pos)
	check(d.foe.hp >= 22,"regen runs at round start for monsters")
```

`Builder.rows()`는 `encounter_builder.gd`의 종족 목록 함수명이다 — 실제 이름을 `encounter_builder.gd:12-14`에서 확인해 맞춘다(그 함수는 `content.get("species",[])`를 돌려준다).

- [ ] **Step 2: 실패 확인** — `passives.gd` 없음 오류.

- [ ] **Step 3: `expedition/passives.gd` 작성**

```gdscript
extends RefCounted
## Part passives. A closed list of kinds and four hooks; nothing else in the
## game reads a passive. Party members carry the passives of their equipped
## parts, monsters the passive of their species part.
const Abilities = preload("res://expedition/abilities.gd")
const KINDS := ["PACK","RETALIATE","DIRTY","AMBUSHER","THICK_HIDE","BLOODLUST","REGEN","AMPHIBIOUS"]

static func of(actor: Dictionary) -> Array:
	var ids: Array = [actor.get("part_id","")] if actor.enemy else actor.equipped_abilities
	var result: Array = []
	for id in ids:
		var def: Dictionary = Abilities.DEFINITIONS.get(id,{})
		if not def.is_empty() and not def.passive.is_empty(): result.append(def.passive)
	return result

static func adjacent_allies(s, actor: Dictionary) -> int:
	var count := 0
	for other in s.party+s.enemies:
		if other.id != actor.id and other.hp > 0 and other.enemy == actor.enemy and s.melee_reach(actor.pos,other.pos): count += 1
	return count

static func under_half(actor: Dictionary) -> bool:
	return int(actor.hp)*2 < int(actor.max_hp)

## Damage `attacker` is about to deal to `target`, before 엄호 redirects it.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	for passive in of(attacker):
		var value: int = int(passive.value)
		match passive.kind:
			"PACK": amount += value*adjacent_allies(s,attacker)
			"DIRTY": if under_half(target): amount += value
			"AMBUSHER": if adjacent_allies(s,target) == 0: amount += value
			"BLOODLUST": if under_half(attacker): amount += value
			"AMPHIBIOUS":
				var tile: Dictionary = s.tile(attacker.pos)
				if tile.terrain == "water" or int(tile.wet) > 0: amount += value
	return amount

## Damage `target` finally takes, after guards and defence.
static func incoming(s, target: Dictionary, amount: int) -> int:
	for passive in of(target):
		match passive.kind:
			"THICK_HIDE": amount = maxi(1,amount-int(passive.value))
	return amount

## After the hit landed. Retaliation is plain damage with its own form so it
## never triggers passives again.
static func after_hit(s, target: Dictionary, attacker: Dictionary, form: String) -> void:
	if form == "RETALIATE" or attacker.is_empty() or attacker.hp <= 0: return
	for passive in of(target):
		match passive.kind:
			"RETALIATE":
				if s.melee_reach(target.pos,attacker.pos):
					s.message("%s · 반격" % target.name)
					s.damage(attacker,int(passive.value),target.id,"RETALIATE")

static func round_start(s, actor: Dictionary) -> void:
	if actor.hp <= 0: return
	for passive in of(actor):
		match passive.kind:
			"REGEN":
				var before: int = actor.hp
				actor.hp = mini(int(actor.max_hp),int(actor.hp)+int(passive.value))
				if actor.hp > before: s.Body.heal(actor)
```

- [ ] **Step 4: `abilities.gd`에 8종 추가** (LUNGE 항목 뒤, 순서 그대로)

```gdscript
	"RAT_GNAW":{"name":"물어뜯기","item":"쥐 이빨","description":"무리: 인접 아군당 피해 +1 · 물어뜯기: 인접 대상 피해 9 · 재사용 2턴","target":"ENEMY","range":1,"radius":0,"damage":9,"cooldown":2,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"물기","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_rat","passive":{"kind":"PACK","value":1},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"LIZARD_TAIL":{"name":"꼬리치기","item":"도마뱀 꼬리","description":"반격: 인접한 공격자에게 피해 2 · 꼬리치기: 대상 주위 3×3 피해 6 · 재사용 3턴","target":"ENEMY","range":1,"radius":1,"damage":6,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"꼬리","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_frilled_lizard","passive":{"kind":"RETALIATE","value":2},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"KOBOLD_SLING":{"name":"투석","item":"코볼트 투석끈","description":"비열: 체력 절반 미만 대상에 피해 +3 · 투석: 사거리 4 피해 7 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":7,"cooldown":2,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"투석","shape":"SQUARE","self_hit":false,"icon":5,"species":"kobold","passive":{"kind":"DIRTY","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"GOBLIN_SHIV":{"name":"기습","item":"고블린 단검","description":"기습: 고립된 대상에 피해 +3 · 기습: 사거리 3 이동 후 피해 10 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":10,"cooldown":3,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS","short":"기습","shape":"SQUARE","self_hit":false,"icon":5,"species":"goblin","passive":{"kind":"AMBUSHER","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"HOB_CLUB":{"name":"내려치기","item":"홉고블린 곤봉","description":"두꺼운 가죽: 받는 피해 -1 · 내려치기: 인접 대상 피해 14 · 재사용 3턴","target":"ENEMY","range":1,"radius":0,"damage":14,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"곤봉","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_hobgoblin","passive":{"kind":"THICK_HIDE","value":1},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"ORC_CLEAVER":{"name":"휘두르기","item":"오크 도끼","description":"피의 갈망: 자신 체력 절반 미만이면 피해 +3 · 휘두르기: 대상 주위 3×3 피해 11 · 재사용 3턴","target":"ENEMY","range":1,"radius":1,"damage":11,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"도끼","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_orc","passive":{"kind":"BLOODLUST","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"GNOLL_SPEAR":{"name":"창 찌르기","item":"놀 창","description":"재생: 라운드마다 체력 +2 · 창 찌르기: 사거리 2 피해 12 · 재사용 3턴","target":"ENEMY","range":2,"radius":0,"damage":12,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"창","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_gnoll","passive":{"kind":"REGEN","value":2},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"RIVER_RAT_SPLASH":{"name":"물세례","item":"강쥐 가죽","description":"물갈퀴: 젖은 칸에서 피해 +3 · 물세례: 사거리 3 · 3×3 피해 5 · 칸을 적심 · 재사용 3턴","target":"ENEMY","range":3,"radius":1,"damage":5,"cooldown":3,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"물","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_river_rat","passive":{"kind":"AMPHIBIOUS","value":3},"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":70}}
```

- [ ] **Step 5: `session.gd` 훅**

`const Passives = preload("res://expedition/passives.gd")`를 `Growth` 아래에 추가. 헬퍼:

```gdscript
func actor_by_id(id: int) -> Dictionary:
	for actor in party+enemies:
		if actor.id == id: return actor
	return {}
```

`damage()`를 다음처럼 바꾼다(변경 줄만):

```gdscript
func damage(target: Dictionary, amount: int, source: int, form: String) -> void:
	if target.hp <= 0: return
	var attacker: Dictionary = actor_by_id(source)
	var passive_hit: bool = form != "RETALIATE"
	if passive_hit and not attacker.is_empty(): amount = Passives.outgoing(self,attacker,target,amount)
	# 엄호: … (기존 재지정 블록 그대로)
	…
	if not target.enemy: amount = Growth.incoming(target,amount)
	if passive_hit: amount = Passives.incoming(self,target,amount)
	# (기존: 솔로 스트레스 +1, serial, lost, effect, injury, hp 차감, interrupt, 기억/스트레스, 메시지)
	…
	message(…)
	if passive_hit: Passives.after_hit(self,target,attacker,form)
	if target.enemy and target.hp <= 0: roll_part(target)
```

`source_cell`/`source_name` 계산 루프는 `attacker`를 쓰도록 줄인다: `if not attacker.is_empty(): source_cell = attacker.pos; source_name = attacker.name`.

`end_round()`: `for actor in alive():` 블록(쿨다운 감소가 있는 곳) 바로 앞에

```gdscript
	for actor in alive()+enemies: Passives.round_start(self,actor)
```
(`Passives.round_start`가 `hp <= 0`을 거른다.)

- [ ] **Step 6: 테스트 마무리** — `tests/parts.gd` bag의 `"BOMB"` 3개 검사 → `"HOB_CLUB"`; `tests/abilities_growth.gd` 첫 루프의 드롭 검사를 `dropped > 0 and dropped < 30`으로 복원(보스 시련 `part_id`는 `droppable()[pattern%8]`이라 이제 비어 있지 않다; 세는 대상은 `s.enemies[0].part_id`).

- [ ] **Step 7: 실행** — `parts abilities_growth protect companion_tactics skill_rule_conditions skill_archetypes solo_floor encounter_sim ui_smoke solo_balance torch_tradeoff expedition_settlement` 통과. `solo_balance`가 3/8 미만이면 실패 원인을 보고서에 적되 수치는 바꾸지 않는다(Task 6의 게이트).

- [ ] **Step 8: 커밋** — `feat(parts): eight species parts and passive hooks`

---

### Task 4: 적 AI — 시그니처 준비·해결·끊기

**Files:**
- Modify: `expedition/monster_ai.gd` (전면), `expedition/board.gd:229-232`, `expedition/sim/encounter_runner.gd` (`run_one` 결과, `run_many` 평균)
- Test: `tests/parts.gd` (`telegraph()`), `tests/enemy_turns.gd`·`tests/monster_roles.gd` 회귀 확인

**Interfaces:**
- Produces: `enemy.cast_id/cast_left`, intent `kind`, `session.stats_interrupts`, `run_one().enemy_skill_uses/interrupts`, `run_many().enemy_skill_uses_mean/interrupts_mean`.
- Consumes: `Abilities.legal/execute/resolve`(Task 1), `part_id`(Task 2), 카탈로그 8종(Task 3).

- [ ] **Step 1: 실패하는 테스트 — `tests/parts.gd`에 추가**

```gdscript
const MonsterAI = preload("res://expedition/monster_ai.gd")

func telegraph() -> void:
	# Hobgoblin in contact: announces, resolves next round, cools down.
	var d := duel(); var s = d.s
	d.foe.part_id = "HOB_CLUB"; d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.foe.cast_id == "HOB_CLUB" and d.foe.cast_cell == d.hero.pos,"in contact the part is announced first")
	check(s.intents.size() == 1 and s.intents[0].kind == "HOB_CLUB" and int(s.intents[0].damage) == 14 and s.intents[0].cell == d.hero.pos,"intent carries the part and its damage")
	check(s.Rules.lethal_threat(s,d.hero) >= 14,"lethal threat reads the announced damage")
	var hp: int = d.hero.hp
	MonsterAI.turn(s,d.foe)
	check(not d.foe.charging and s.intents.is_empty(),"resolved on the next turn")
	check(d.hero.hp == hp-s.Growth.incoming(d.hero,14+s.floor_state.enemy_bonus(s.light)),"club lands for its damage plus the darkness bonus")
	check(int(d.foe.cooldowns.HOB_CLUB) == 4,"cooldown set (3 + 1)")
	check(int(s.stats_enemy_skill.get("HOB_CLUB",0)) == 1,"enemy skill use counted")
	MonsterAI.turn(s,d.foe)
	check(not d.foe.charging and int(d.foe.cooldowns.HOB_CLUB) == 3,"on cooldown the role attack runs and the cooldown ticks")
	# Interrupt by push: cooldown consumed, one round of recovery.
	d = duel(); s = d.s; d.foe.part_id = "HOB_CLUB"; d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	check(s.act("PUSH",d.foe.pos),"hero pushes the charging foe")
	check(not d.foe.charging and s.intents.is_empty() and d.foe.cast_recovery == 1 and int(d.foe.cooldowns.HOB_CLUB) == 3,"push cancels the part and burns its cooldown")
	check(s.stats_interrupts == 1,"interrupt counted")
	# Target steps away: a radius-0 part misses.
	d = duel(); s = d.s; d.foe.part_id = "HOB_CLUB"; d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	d.hero.pos = d.c+Vector2i(-1,0); hp = d.hero.hp
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp == hp and s.log_lines[-1].contains("빗나갔습니다"),"an empty announced cell is a miss")
	# Area part spares the caster's own side.
	d = duel(); s = d.s; d.foe.part_id = "ORC_CLEAVER"; d.foe.cooldowns = {}
	var mate: Dictionary = s.enemies[1]; mate.hp = 30; mate.max_hp = 30; mate.alert = true; mate.pos = d.c+Vector2i(1,1); mate.part_id = ""
	MonsterAI.turn(s,d.foe)
	var ally_hp: int = d.ally.hp; var mate_hp: int = mate.hp; hp = d.hero.hp
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp < hp and d.ally.hp < ally_hp and mate.hp == mate_hp,"cleave hits both members in the square and no fellow monster")
	# prep 0 fires at once; prep 2 waits two turns.
	var saved: Dictionary = Abilities.DEFINITIONS.HOB_CLUB.enemy
	d = duel(); s = d.s; d.foe.part_id = "HOB_CLUB"; d.foe.cooldowns = {}
	Abilities.DEFINITIONS.HOB_CLUB.enemy = {"prep":0,"target":"NEAREST"}
	hp = d.hero.hp; MonsterAI.turn(s,d.foe)
	check(d.hero.hp < hp and not d.foe.charging,"prep 0 resolves immediately")
	d = duel(); s = d.s; d.foe.part_id = "HOB_CLUB"; d.foe.cooldowns = {}
	Abilities.DEFINITIONS.HOB_CLUB.enemy = {"prep":2,"target":"NEAREST"}
	hp = d.hero.hp; MonsterAI.turn(s,d.foe); MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.hero.hp == hp and s.intents.size() == 1,"prep 2 still announced after two turns")
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp < hp,"prep 2 resolves on the third")
	Abilities.DEFINITIONS.HOB_CLUB.enemy = saved
	# Caster role keeps its spell when the part is on cooldown; the part goes first when both are ready.
	d = duel(); s = d.s; d.foe.part_id = "KOBOLD_SLING"; d.foe.cooldowns = {}; d.foe.role = "CASTER"; d.foe.cast_cooldown = 0
	d.foe.pos = d.c+Vector2i(3,0); s.floor_state.observe(s)
	MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.foe.cast_id == "KOBOLD_SLING","part before role spell")
	# Player use is immediate and grows with the melee axis.
	d = duel(); s = d.s; d.hero.equipped_abilities = ["HOB_CLUB","GUARD"]; d.hero.cooldowns = {}
	var foe_hp: int = d.foe.hp
	check(s.act("HOB_CLUB",d.foe.pos) and d.foe.hp == foe_hp-s.Growth.power(d.hero,"MELEE",14) and d.hero.ap == 2 and int(d.hero.cooldowns.HOB_CLUB) == 4,"player club is immediate, scaled and cooled")
```

`DEFINITIONS`는 `const` 딕셔너리이지만 GDScript에서 내부 값은 바꿀 수 있다(테스트에서 `prep`을 바꾸고 복원). `Fixture.equip_basics`가 `duel()`에 들어 있으므로 hero의 밀치기가 장착돼 있다.

- [ ] **Step 2: 실패 확인** — `cast_id` 미정의 등.

- [ ] **Step 3: `expedition/monster_ai.gd` 교체**

```gdscript
extends RefCounted
## Continuous-floor roles plus the species signature part. Firing-position
## search adapts ../sim/stage_enemy_rules.gd. A monster that can use its part
## announces it (`prep` rounds) and resolves it on the announced cell; the
## caster role's own spell uses the same charging state with an empty cast_id.
const Melee = preload("res://expedition/floor_tactics_adapter.gd")
const Abilities = preload("res://expedition/abilities.gd")
const ROLES := {
	"MELEE":{"label":"추격병","range":1,"damage":7},
	"RANGED":{"label":"궁수","range":5,"damage":6},
	"CASTER":{"label":"술사","range":4,"damage":4},
}
const SPELL_DAMAGE := 14

static func configure(enemy: Dictionary, role: String) -> void:
	enemy.role = role if ROLES.has(role) else "MELEE"
	enemy.name += " " + ROLES[enemy.role].label
	enemy.charging = false
	enemy.cast_id = ""
	enemy.cast_left = 0
	enemy.cast_cooldown = 2
	enemy.cast_recovery = 0

static func line(s, a: Vector2i, b: Vector2i, reach: int) -> bool:
	# Range uses eight-way tile distance; Geometry's circular cutoff must not trim diagonals.
	return distance(a,b) <= reach and s.TurnCore.Geometry.sees(a,b,func(p): return not s.inside(p) or s.tile(p).terrain == "wall",ceili(reach*sqrt(2.0)))

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

static func interrupt(s, enemy: Dictionary) -> void:
	if not enemy.get("charging",false): return
	var id: String = str(enemy.get("cast_id",""))
	enemy.charging = false
	enemy.cast_recovery = 1
	if id.is_empty(): enemy.cast_cooldown = 3
	else:
		enemy.cooldowns[id] = int(Abilities.DEFINITIONS[id].cooldown)
		s.stats_interrupts += 1
	enemy.cast_id = ""; enemy.cast_left = 0
	s.intents = s.intents.filter(func(i): return i.id != enemy.id)
	s.message(enemy.name+"의 시전이 끊겼습니다.")

static func plan(s) -> void:
	s.intents.clear()
	for enemy in s.enemies:
		if enemy.hp <= 0 or not enemy.get("charging",false): continue
		var id: String = str(enemy.get("cast_id",""))
		var amount: int = int(Abilities.DEFINITIONS[id].damage) if Abilities.DEFINITIONS.has(id) else SPELL_DAMAGE
		s.intents.append({"id":enemy.id,"cell":enemy.cast_cell,"damage":amount,"kind":id})

static func turn(s, enemy: Dictionary) -> void:
	var targets: Array = s.alive()
	if enemy.hp <= 0 or targets.is_empty(): return
	if targets.any(func(a): return line(s,enemy.pos,a.pos,9)): enemy.alert = true
	if not enemy.get("alert",false): return
	if targets.all(func(a): return distance(enemy.pos,a.pos) > 15):
		enemy.alert = false; enemy.charging = false; enemy.cast_id = ""; plan(s); return
	if enemy.get("cast_recovery",0) > 0:
		enemy.cast_recovery -= 1; return
	var part: String = str(enemy.get("part_id",""))
	if Abilities.DEFINITIONS.has(part): enemy.cooldowns[part] = maxi(0,int(enemy.cooldowns.get(part,0))-1)
	if enemy.get("charging",false):
		enemy.cast_left = int(enemy.get("cast_left",1))-1
		if enemy.cast_left > 0: plan(s); return
		var id: String = str(enemy.get("cast_id",""))
		var cell: Vector2i = enemy.cast_cell
		enemy.charging = false; enemy.cast_id = ""; plan(s)
		if id.is_empty(): resolve_spell(s,enemy,cell)
		else: Abilities.resolve(s,enemy,id,cell)
		return
	if Abilities.DEFINITIONS.has(part) and int(enemy.cooldowns.get(part,0)) <= 0:
		targets.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos))
		for target in targets:
			if not Abilities.legal(s,enemy,part,target.pos): continue
			var prep: int = int(Abilities.DEFINITIONS[part].enemy.prep)
			if prep <= 0: Abilities.execute(s,enemy,part,target.pos); return
			enemy.charging = true; enemy.cast_id = part; enemy.cast_cell = target.pos; enemy.cast_left = prep
			plan(s); s.message("%s · %s 준비" % [enemy.name,Abilities.DEFINITIONS[part].name])
			return
	role_turn(s,enemy,targets)

## The caster's own spell, cell-locked at SPELL_DAMAGE.
static func resolve_spell(s, enemy: Dictionary, cell: Vector2i) -> void:
	enemy.cast_cooldown = 3
	if not line(s,enemy.pos,cell,4): return
	s.enemy_attack_effect(enemy,[cell],true)
	var victim: Dictionary = s.at(cell)
	if not victim.is_empty() and not victim.enemy: s.damage(victim,SPELL_DAMAGE+s.floor_state.enemy_bonus(s.light),enemy.id,"ELECTRIC")
	s.message(enemy.name+"의 마법이 예고한 지점에 떨어졌습니다.")

static func role_turn(s, enemy: Dictionary, targets: Array) -> void:
	var role: String = enemy.get("role","MELEE")
	if role == "MELEE":
		var choice: Dictionary = Melee.new(s,enemy).choose(enemy)
		if choice.kind == "MOVE": enemy.pos = choice.cell
		elif choice.kind == "ATTACK": strike(s,enemy,s.at(choice.cell),7)
		return
	targets.sort_custom(func(a,b): return distance(enemy.pos,a.pos) < distance(enemy.pos,b.pos))
	var reach: int = ROLES[role].range
	var ready: bool = enemy.get("cast_cooldown",2) <= 0
	enemy.cast_cooldown = maxi(0,int(enemy.get("cast_cooldown",2))-1)
	for target in targets:
		if s.melee_reach(enemy.pos,target.pos):
			strike(s,enemy,target,4); return # No endless retreat loop.
	for target in targets:
		if not line(s,enemy.pos,target.pos,reach): continue
		if role == "CASTER" and ready:
			enemy.charging = true; enemy.cast_id = ""; enemy.cast_cell = target.pos; enemy.cast_left = 1; plan(s)
			s.message(enemy.name+" · 시전")
		else: strike(s,enemy,target,ROLES[role].damage)
		return
	# Search a bounded set of firing positions, then use the shared pathfinder.
	var goals: Array = []
	var target: Dictionary = targets[0]
	for y in range(maxi(0,target.pos.y-reach),mini(s.BOARD_SIDE,target.pos.y+reach+1)):
		for x in range(maxi(0,target.pos.x-reach),mini(s.BOARD_SIDE,target.pos.x+reach+1)):
			var p := Vector2i(x,y)
			if s.is_free(p) and distance(p,target.pos) >= 2 and line(s,p,target.pos,reach): goals.append(p)
	if goals.is_empty(): return
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,enemy.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100,100,20)
	if route.found and route.path.size() > 1: enemy.pos = route.path[1]

static func strike(s, enemy: Dictionary, target: Dictionary, amount: int) -> void:
	if target.is_empty() or target.enemy: return
	s.enemy_attack_effect(enemy,[target.pos])
	s.damage(target,amount+s.floor_state.enemy_bonus(s.light),enemy.id,"ELECTRIC" if enemy.get("role","") == "CASTER" else "IMPACT")
```

동작 보존 확인: 기존 술사 시전은 `cast_left = 1`로 한 라운드 뒤 해결(이전과 같음), `interrupt`의 `cast_cooldown = 3`·`cast_recovery = 1` 유지. `tests/enemy_turns.gd`·`tests/monster_roles.gd`가 회귀를 잡는다. 테스트 픽스처들이 `foe.charging = false`만 설정하고 `cast_id`를 설정하지 않으므로 코드 전체에서 `enemy.get("cast_id","")`를 쓴다.

- [ ] **Step 4: `board.gd` 예고 배지** — 229-232행의 `draw_string(…,"!",…)`을 `draw_string(ui_font,center+Vector2(-4,4),"!"+(session.Abilities.badge(intent.kind) if not str(intent.get("kind","")).is_empty() else ""),HORIZONTAL_ALIGNMENT_LEFT,-1,12 if not str(intent.get("kind","")).is_empty() else 18,Color.WHITE)`. (`board.gd`에 `session.Abilities` 접근이 가능한지 확인 — `session.Rules`를 이미 쓰므로 같은 방식.)

- [ ] **Step 5: `encounter_runner.gd` 계측** — `run_one` 반환 딕셔너리에 `"enemy_skill_uses":s.stats_enemy_skill.duplicate(),"interrupts":s.stats_interrupts`. `run_many`에서 `skill_uses_mean`을 만드는 코드와 같은 방식으로 `enemy_skill_uses_mean`과 `interrupts_mean`(float 평균)을 추가한다(`run_many` 본문 하단의 집계 블록을 읽고 같은 패턴으로).

- [ ] **Step 6: 실행** — `parts enemy_turns monster_roles protect skill_rule_conditions encounter_sim solo_floor solo_balance solo_recovery torch_tradeoff mobile_hud ui_smoke` 통과.

- [ ] **Step 7: 커밋** — `feat(parts): monsters announce and resolve their signature part`

---

### Task 5: 파츠 탭·가방·상점·결과 UI

**Files:**
- Modify: `expedition/character_ui.gd` (`abilities` → `parts`, `replace`), `expedition/main.gd` (`build_abilities` 삭제/치환, `show_item_detail` 파츠 분기, `build_inventory` 카테고리, 결과 화면), `tests/character_ui.gd`, `tests/test_loadout.gd`, `tests/abilities_growth.gd` UI 부분
- Test: `tests/parts.gd` (`ui()` — 씬 층)

**Interfaces:**
- Consumes: `equip_part/unequip_part/parts_bag`(Task 2), `Rules.skill`(Task 1).

- [ ] **Step 1: 실패하는 테스트 — `tests/parts.gd`에 `ui()` 추가(`await ui()`), `run()`을 `async` 흐름으로**

```gdscript
func ui() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(731,false,false,true)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(4): await process_frame
	scene.show_character(0,"파츠")
	for frame in range(4): await process_frame
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("파츠 슬롯"))
	check(not heading.is_empty() and heading[0].text == "파츠 슬롯 0 / 2","empty slots heading")
	var cards: Array = scene.modal_content.find_children("PartSlot*","PanelContainer",true,false)
	check(cards.size() == 2,"two slot cards")
	var buttons: Array = scene.modal_content.find_children("*","Button",true,false)
	check(buttons.filter(func(b): return b.text == "장착").size() == 2,"empty slots offer 장착")
	scene.CharacterUI.replace(scene,0)
	for frame in range(3): await process_frame
	var picks: Array = scene.item_detail.find_children("*","Button",true,false).map(func(b): return b.text)
	check("밀치기 ×1" in picks and "엄호 ×1" in picks,"chooser lists the bag with counts")
	scene.item_popup.hide()
	check(s.equip_part(0,0,"PUSH"),"equip through the session")
	scene.show_character(0,"파츠")
	for frame in range(4): await process_frame
	heading = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("파츠 슬롯"))
	check(heading[0].text == "파츠 슬롯 1 / 2","heading counts equipped parts")
	buttons = scene.modal_content.find_children("*","Button",true,false)
	check(buttons.any(func(b): return b.text == "해제") and buttons.any(func(b): return b.text == "교체"),"equipped slot offers 해제 and 교체")
	scene.details_popup.hide()
	# Battle buttons: an empty slot is a disabled "빈 슬롯".
	s.depart(); scene.refresh()
	for frame in range(3): await process_frame
	check(scene.skill_buttons.size() == 2 and scene.skill_buttons[1].disabled and scene.skill_buttons[1].tooltip_text == "빈 슬롯","empty second slot is disabled")
	check(not scene.skill_buttons[0].disabled or s.phase != "BATTLE","push button follows battle state")
	# Bag: the parts category exists and the detail offers per-member slot buttons only in town.
	scene.inventory_filter = "파츠"; scene.show_supplies()
	for frame in range(3): await process_frame
	check(scene.inventory_slots.all(func(slot): return slot.row.is_empty() or slot.row.category == "파츠"),"parts filter")
	scene.show_item_detail("GUARD"); await process_frame
	var detail: Array = scene.item_detail.find_children("*","Button",true,false)
	check(detail.any(func(b): return b.text.ends_with("1번 장착") and b.disabled),"equip buttons are disabled outside town")
	scene.item_popup.hide(); scene.details_popup.hide()
	scene.queue_free(); await process_frame
```

`run()`은 `await ui()`를 포함하도록 바꾼다(`skill_rule_conditions.gd`의 `await user_interface()` 패턴).

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `character_ui.gd` — `abilities()`를 `parts()`로 교체**

```gdscript
static func parts(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var town: bool = ui.session.phase == "TOWN" and actor.hp > 0
	for slot in range(2):
		var id: String = str(actor.equipped_abilities[slot])
		var box := card(list,""); box.get_parent().name = "PartSlot"+str(slot)
		box.get_parent().custom_minimum_size.y = 132
		var row := HBoxContainer.new(); box.add_child(row)
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
		var actions := VBoxContainer.new(); row.add_child(actions)
		if id.is_empty():
			text(info,"빈 슬롯",20)
			text(info,"마을에서 가방의 파츠를 장착합니다.",13)
			ui.button(actions,"장착",func(): replace(ui,slot),town)
			continue
		var def: Dictionary = ui.Session.Abilities.DEFINITIONS[id]
		text(info,str(def.name),20)
		text(info,str(def.description),13)
		ui.button(actions,"교체",func(): replace(ui,slot),town)
		ui.button(actions,"해제",func(): ui.session.unequip_part(ui.tactics_actor,slot); ui.refresh(); ui.show_character(ui.tactics_actor,"파츠"),town)
		var index: int = -1
		for i in range(actor.rules.size()):
			if actor.rules[i].skill == id: index = i
		if index < 0: continue
		var rule: Dictionary = actor.rules[index]
		var auto = ui.button(actions,"자동 ON" if rule.enabled else "자동 OFF",func(): ui.session.update_rule(ui.tactics_actor,index,"enabled",not rule.enabled); ui.refresh(); ui.show_tactics())
		auto.toggle_mode = true; auto.button_pressed = rule.enabled
		var policy = ui.button(box,"사용 방침 · "+ui.Session.Rules.summary(rule)+"  ›",func(): ui.open_rule(index))
		policy.add_theme_font_size_override("font_size",11)
		policy.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

static func replace(ui, slot: int) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); text(ui.item_detail,"파츠 장착",20)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(300,260); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; ui.item_detail.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var count := 0
	for id in ui.session.parts_bag:
		if int(ui.session.parts_bag[id]) <= 0 or id in actor.equipped_abilities: continue
		count += 1
		ui.button(list,"%s ×%d" % [ui.Session.Rules.skill(id).name,ui.session.parts_bag[id]],func():
			if ui.session.equip_part(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"파츠"),ui.session.phase == "TOWN" and actor.hp > 0)
	if count == 0: text(list,"가방에 파츠 없음")
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()
```

기존 `abilities()`의 `open_rule`·`show_tactics` 호출 방식은 파일 안의 다른 코드와 맞춘다(`ui.open_rule(index)`가 있는지 확인; 없으면 기존 `abilities()`가 쓰던 이름을 그대로).

- [ ] **Step 4: `main.gd`**

- `"파츠": CharacterUI.parts(self,list,actor)` (632행 근처), `show_tactics()`가 `"파츠"` 탭을 연다(638행).
- `build_abilities()` 삭제(참조가 남아 있으면 `CharacterUI.parts`로).
- 전투 버튼(297-305행): 빈 슬롯이면 `skill.disabled = true; skill.tooltip_text = "빈 슬롯"`. `icon_button`의 마지막 인자가 tooltip이면 그 자리에 `"빈 슬롯"`을 넣는다.
- `show_item_detail`: `if row.category == "파츠":` → 파티원마다 두 버튼 `"%s %d번 장착" % [name, slot+1]` → `session.equip_part(i,slot,id)`; 활성 조건 `session.phase == "TOWN" and session.party[i].hp > 0 and id not in session.party[i].equipped_abilities`; 눌리면 `item_popup.hide(); refresh(); show_supplies()`.
- 상점 목록은 `Session.SHOP` 순회라 자동으로 두 행이 보인다. 확인만.
- 결과 화면은 Task 2에서 `r.parts`로 바뀌어 있다.

- [ ] **Step 5: 기존 UI 테스트** — `tests/character_ui.gd`: `EquippedAbility*` → `PartSlot*`; `"이능"` → `"파츠"`; 교체 흐름은 `scene.session.phase == "TOWN"`에서 `replace` → 버튼 텍스트 `"폭탄 투척 ×1"` 클릭 → `equipped_abilities[0] == "BOMB"`. `tests/test_loadout.gd` `scene_layer()`: 로드아웃 뒤 `parts_bag` 검사, `show_character(0,"파츠")` 카드 2장, `replace(scene,0)` 목록에 모든 파츠 이름(`Rules.skill(id).name` + " ×1")이 있는지. `tests/abilities_growth.gd` UI 부분: `"이능"` 탭명 → `"파츠"`, 카드 수 검사 `PartSlot*` == 2, 인벤토리 필터 `"파츠"`.

- [ ] **Step 6: 실행** — `parts character_ui test_loadout abilities_growth ui_smoke mobile_hud mobile_actions mobile_exploration` 통과. 에디터 임포트 오류 0.

- [ ] **Step 7: 커밋** — `feat(parts): parts tab, bag and shop UI`

---

### Task 6: 시뮬 빌드·CI·밸런스 게이트

**Files:**
- Modify: `data/content/reference_builds.json`, `data/content/balance_experiments.json`, `.github/workflows/deploy-pages.yml` (스위트 목록에 `parts` 추가), `tests/encounter_sim.gd` (`enemy_skill_uses` 검사 1개), `docs/balance/skill-value.md`·`.json`, `docs/balance/action-economy.md`·`.json`, `docs/balance-method.ko.md` (§ 결과 요약 한 단락)
- Create: `docs/balance/parts-gates.md` (G1~G5 결과)

- [ ] **Step 1: 빌드 데이터**

`reference_builds.json`: 모든 빌드에서 `"learned": [...]` 키 삭제. 8개 추가(`b_iron` 뒤):

```json
 {"id": "p_rat", "label": "쥐 이빨형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["RAT_GNAW","GUARD"], "rules": [["RAT_GNAW","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]},
 {"id": "p_lizard", "label": "도마뱀 꼬리형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["LIZARD_TAIL","GUARD"], "rules": [["LIZARD_TAIL","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]},
 {"id": "p_kobold", "label": "코볼트 투석형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["KOBOLD_SLING","GUARD"], "rules": [["KOBOLD_SLING","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]},
 {"id": "p_goblin", "label": "고블린 단검형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["GOBLIN_SHIV","GUARD"], "rules": [["GOBLIN_SHIV","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]},
 {"id": "p_hob", "label": "홉고블린 곤봉형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["HOB_CLUB","GUARD"], "rules": [["HOB_CLUB","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]},
 {"id": "p_orc", "label": "오크 도끼형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["ORC_CLEAVER","GUARD"], "rules": [["ORC_CLEAVER","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]},
 {"id": "p_gnoll", "label": "놀 창형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["GNOLL_SPEAR","GUARD"], "rules": [["GNOLL_SPEAR","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]},
 {"id": "p_river", "label": "강쥐 가죽형", "ranks": {"MELEE": 1}, "stats": {}, "equipped": ["RIVER_RAT_SPLASH","GUARD"], "rules": [["RIVER_RAT_SPLASH","NEAREST","ALWAYS"],["GUARD","ALLY","ALLY_LETHAL"]]}
```

`balance_experiments.json`의 `skill_value.builds` 끝에 `"p_rat","p_lizard","p_kobold","p_goblin","p_hob","p_orc","p_gnoll","p_river"` 추가. `encounter_runner.apply_build`에서 `learned` 루프는 Task 1에서 제거됐는지 확인.

- [ ] **Step 2: CI 목록** — `deploy-pages.yml`의 `for suite in … protect; do` 목록 끝에 ` parts` 추가. `tests/encounter_sim.gd`에 검사 하나: `early_hob` 아레나 3인 `rules` 정책 20시드 `run_many`에서 `enemy_skill_uses_mean.get("HOB_CLUB",0) > 0`(적이 파츠를 실제로 씀).

- [ ] **Step 3: 게이트 실행과 기록** — 순서대로 실행하고 `docs/balance/parts-gates.md`에 표로 기록(커밋 해시·날짜·시드·"몬스터 파츠 도입 후 첫 측정"):

```
godot --headless --path . --script res://tests/solo_balance.gd        # G1: 승리 ≥ 3/8
godot --headless --path . --script res://tests/encounter_sim.gd       # G2 일부
godot --headless --path . --script res://tests/action_economy.gd      # G2: docs/balance/action-economy.md 재생성
godot --headless --path . --script res://tests/skill_value.gd         # G3: docs/balance/skill-value.md 재생성 (파츠 8종 포함)
godot --headless --path . --script res://tests/party_guard_probe.gd   # G5
```
G4는 `skill_value` 실행 결과의 `enemy_skill_uses_mean`을 아레나별로 표에 옮긴다(도구가 그 값을 출력하지 않으면 `tests/skill_value.gd`의 보고서 생성에 열 하나를 추가한다: 아레나 × 파츠 id 평균 사용 횟수).

게이트 미달 시: 스펙 §5.2의 조정 우선순위(액티브 damage → cooldown → 패시브 value)로 한 번에 한 값씩 바꾸고 재실행, 바꾼 값과 이유를 `parts-gates.md`에 적는다. 두 번 조정해도 미달이면 멈추고 보고한다(값을 더 바꾸지 말 것).

- [ ] **Step 4: 방법론 문서** — `docs/balance-method.ko.md` 결과 절에 "파츠 도입 후 측정" 단락(게이트 표 링크, 통과/미달 요약, 바꾼 수치) 추가.

- [ ] **Step 5: 전체 스위트** — CI 목록 전부(`parts` 포함) 통과, 에디터 임포트 오류 0. 수동 도구 `tests/expedition_skills.gd`·`party_guard_probe.gd`·`action_economy.gd`·`skill_value.gd`가 오류 없이 끝나는지 확인.

- [ ] **Step 6: 커밋** — `feat(parts): part builds, enemy-use metrics, balance gates`

---

## 자기 검토

- **스펙 커버리지**: §1.1 필드·`species_part`·`droppable`(T1) / §1.2 패시브·훅(T3) / §1.3 슬롯·가방·`part_id`(T1,T2) / §1.4 장착·해제·시험 로드아웃(T2) / §1.5 드롭(T2) / §1.6 기본 파츠 effect·Tactics 게이팅·`defaults []`(T1) / §1.7 시작 가방·상점·환전 제외·비층 모드 자동 장착(T1,T2) / §2 준비 상태·턴 순서·`resolve`·`power`·양측 `legal`·배지(T1,T4) / §3 8종 수치(T3) / §4.1 파생 카탈로그(T1) / §4.2 UI(T5) / §4.3 빌드·계측(T4,T6) / §5.1 테스트(T1–T5) / §5.2 게이트(T6).
- **자리표시자**: 없음. 코드가 없는 단계는 치환 지시가 행 번호와 함께 있다.
- **이름 일관성**: `equip_part/unequip_part/parts_bag/part_id/cast_id/cast_left/stats_enemy_skill/stats_interrupts/Rules.skill/Rules.catalog/Abilities.resolve/power/holds/species_part/Passives.of/outgoing/incoming/after_hit/round_start` — 태스크 간 동일.
