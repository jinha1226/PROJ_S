# 스킬 효과 유형 4종 · 규칙 봇 · 스킬 상대 가치 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 시험용 스킬 4종(강타·투척·응급처치·돌진)을 추가하고, 주인공 봇이 동료 규칙 엔진으로 모든 스킬을 쓰게 한 뒤, 스킬 하나씩 장착한 빌드로 아레나 상대 가치 표를 생성한다.

**Architecture:** `abilities.gd`에 `effect/axis/rule_when` 필드와 실행 분기(HEAL·LUNGE)를 추가하고 `default_rule()`로 기본 규칙을 데이터화한다. 봇 정책 `rules`는 `Tactics.choose`를 그대로 호출한다. 실험 도구는 기존 `encounter_runner`를 재사용하며 `skill_uses`만 집계에 더한다.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트, JSON 콘텐츠.

**Spec:** `docs/superpowers/specs/2026-09-22-skill-archetypes-design.md` — 구현자는 스펙을 먼저 읽는다. 수치는 스펙 표 그대로.

## Global Constraints

- 헤드리스만. `godot` 창을 띄우지 않는다.
- 기존 3스킬(BOMB·SHOCKWAVE·IRON_HIDE)의 동작·수치는 변하지 않는다. 기존 스위트(알려진 사전 실패 2개 제외) 전부 녹색.
- 시험 스킬은 게임 내 드롭·습득 경로에 넣지 않는다(`continuous_floor.build`의 `essence_id` 목록 불변).
- `Tactics.choose`는 스펙 §2의 한 줄(`def.damage > 0` → `def.effect == "DAMAGE"`) 외에 바꾸지 않는다.
- 밸런스 데이터(`floor_themes.json`, `SOLO_HP_*`, 실험 물자)를 바꾸지 않는다. 판정 규칙은 스펙 §5 그대로.
- 커밋: 로컬만, 작성자 `jinha1226 <jinha1226@gmail.com>`, Co-Authored-By 줄 포함. 작업 트리는 컨트롤러가 지정한 깨끗한 worktree.
- 테스트 형식은 기존과 동일.

---

## 파일 구조

| 파일 | 책임 |
| --- | --- |
| `expedition/abilities.gd` (수정) | 필드 3개, 시험 스킬 4개, `default_rule`, `legal`/`execute`의 HEAL·LUNGE 분기, `lunge_cell` |
| `expedition/tactic_rules.gd` (수정) | `SKILLS` 4개 추가, `make_rule` subject 기본값 |
| `expedition/tactical_action_selector.gd` (수정) | 피해 스킬 검사 조건 한 줄 |
| `expedition/session.gd` (수정) | `reset_rules`/`consume_essence` → `Abilities.default_rule` |
| `expedition/board.gd` (수정) | 예약 배지 이름 4개 |
| `tests/skill_archetypes.gd` (신규) | 스킬 동작·기본 규칙·후보 생성 |
| `expedition/sim/bot_policy.gd`, `expedition/sim/encounter_runner.gd` (수정) | `rules` 정책, `skill_uses` |
| `data/content/reference_builds.json` (수정) | 빌드 7개 추가, `rules` |
| `tests/encounter_sim.gd` (수정) | `rules` 정책 검사 |
| `data/content/balance_experiments.json` (수정), `tests/skill_value.gd` (신규), `docs/balance/skill-value.{md,json}` (생성) | 실험·보고서 |
| `docs/balance-method.ko.md`, `README.md` (수정) | 결과 링크, 도구 안내 |

---

### Task 1: 스킬 정의·실행·기본 규칙

**Files:**
- Modify: `expedition/abilities.gd`, `expedition/tactic_rules.gd`, `expedition/tactical_action_selector.gd`, `expedition/session.gd`(두 곳), `expedition/board.gd`(배지 사전)
- Test: `tests/skill_archetypes.gd`

**Interfaces:**
- Produces: `Abilities.DEFINITIONS[id]` 에 `effect`, `axis`, `rule_when`; 새 id `HEAVY_STRIKE`, `THROWING_KNIFE`, `FIELD_DRESSING`, `LUNGE`(`heal` 필드는 FIELD_DRESSING만); `Abilities.default_rule(id) -> Dictionary`; `Abilities.lunge_cell(s, actor, target) -> Vector2i`((-1,-1) = 없음); `Rules.SKILLS` 4개 추가.

- [ ] **Step 1: 실패하는 테스트** — `tests/skill_archetypes.gd`

```gdscript
extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func arena(skill: String) -> Dictionary:
	var s = Session.new(731,true,false,true,1); s.depart()
	var c := Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.learned_abilities = ["PUSH","GUARD",skill]; hero.equipped_abilities = [skill,"GUARD"]; hero.cooldowns = {}
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true
	foe.pos = c+Vector2i(1,0); s.floor_state.observe(s)
	hero.ap = 1
	return {"s":s,"hero":hero,"foe":foe,"c":c}

func run() -> void:
	for id in ["HEAVY_STRIKE","THROWING_KNIFE","FIELD_DRESSING","LUNGE","BOMB","SHOCKWAVE","IRON_HIDE"]:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		check(def.has("effect") and def.has("axis") and def.has("rule_when"),"%s carries effect/axis/rule_when" % id)
		check(Rules.SKILLS.has(id) and Rules.valid(Abilities.default_rule(id)),"%s has a valid default rule" % id)
	check(Abilities.DEFINITIONS.BOMB.axis == "RANGED" and Abilities.DEFINITIONS.SHOCKWAVE.axis == "MAGIC" and Abilities.DEFINITIONS.IRON_HIDE.rule_when == "DANGER","legacy skills keep their axis and rule")
	check(Abilities.default_rule("FIELD_DRESSING").when == "HP" and Abilities.default_rule("FIELD_DRESSING").subject == "SELF","dressing rule is self HP")
	# Heavy strike: adjacent only, 28 base, cooldown 3.
	var f := arena("HEAVY_STRIKE"); var s = f.s
	var hp: int = f.foe.hp
	check(s.act("HEAVY_STRIKE",f.foe.pos),"heavy strike on an adjacent foe")
	check(hp-f.foe.hp >= 28 and f.hero.cooldowns.HEAVY_STRIKE == 4,"heavy strike deals at least 28 and cools down 3 rounds")
	f = arena("HEAVY_STRIKE"); s = f.s; f.foe.pos = f.c+Vector2i(2,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"HEAVY_STRIKE",f.foe.pos),"heavy strike needs adjacency")
	# Throwing knife: range 4, line of sight, cooldown 1.
	f = arena("THROWING_KNIFE"); s = f.s; f.foe.pos = f.c+Vector2i(4,0); s.floor_state.observe(s)
	hp = f.foe.hp
	check(s.act("THROWING_KNIFE",f.foe.pos) and f.foe.hp < hp and f.hero.cooldowns.THROWING_KNIFE == 2,"knife hits at range four")
	f = arena("THROWING_KNIFE"); s = f.s; f.foe.pos = f.c+Vector2i(5,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"THROWING_KNIFE",f.foe.pos),"knife range is four")
	f = arena("THROWING_KNIFE"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.tile(f.c+Vector2i(2,0)).terrain = "wall"; s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"THROWING_KNIFE",f.foe.pos),"knife needs line of sight")
	# Field dressing: self only, not at full health, +15, cooldown 4.
	f = arena("FIELD_DRESSING"); s = f.s
	check(not Abilities.legal(s,f.hero,"FIELD_DRESSING",f.hero.pos),"dressing refused at full health")
	f.hero.hp = 20
	check(s.act("FIELD_DRESSING",f.hero.pos) and f.hero.hp == 35 and f.hero.cooldowns.FIELD_DRESSING == 5,"dressing heals fifteen")
	f = arena("FIELD_DRESSING"); s = f.s; f.hero.hp = f.hero.max_hp-5
	check(s.act("FIELD_DRESSING",f.hero.pos) and f.hero.hp == f.hero.max_hp,"dressing never overheals")
	# Lunge: move beside a foe within three, then strike.
	f = arena("LUNGE"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.floor_state.observe(s)
	var start: Vector2i = f.hero.pos; hp = f.foe.hp
	check(Abilities.lunge_cell(s,f.hero,f.foe.pos) == f.c+Vector2i(2,0),"lunge picks the nearest adjacent cell")
	check(s.act("LUNGE",f.foe.pos),"lunge accepted at range three")
	check(f.hero.pos != start and s.melee_reach(f.hero.pos,f.foe.pos) and f.foe.hp < hp and f.hero.cooldowns.LUNGE == 4,"lunge moves adjacent and strikes")
	f = arena("LUNGE"); s = f.s; f.foe.pos = f.c+Vector2i(4,0); s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"LUNGE",f.foe.pos),"lunge range is three")
	f = arena("LUNGE"); s = f.s; f.foe.pos = f.c+Vector2i(3,0)
	for d in s.DIRECTIONS: s.tile(f.foe.pos+d).terrain = "wall"
	s.tile(f.foe.pos).terrain = "stone"; s.floor_state.observe(s)
	check(not Abilities.legal(s,f.hero,"LUNGE",f.foe.pos),"lunge needs a free adjacent cell")
	# Legacy skills unchanged.
	f = arena("BOMB"); s = f.s; f.foe.pos = f.c+Vector2i(3,0); s.floor_state.observe(s); hp = f.foe.hp
	check(s.act("BOMB",f.foe.pos) and hp-f.foe.hp >= 16,"bomb still deals sixteen at range")
	f = arena("IRON_HIDE"); s = f.s
	check(s.act("IRON_HIDE",f.hero.pos) and f.hero.iron_guard,"iron hide still guards")
	# Default rules through the session paths.
	var s2 = Session.new(5,true,false,true,1); s2.depart()
	s2.essences["FIELD_DRESSING"] = 1
	check(s2.consume_essence(0,"FIELD_DRESSING") and s2.party[0].rules.back().when == "HP" and s2.party[0].rules.back().subject == "SELF","consume_essence uses the default rule")
	s2.reset_rules(0)
	check(s2.party[0].rules.any(func(r): return r.skill == "FIELD_DRESSING" and r.when == "HP"),"reset_rules uses the default rule")
	# Tactics offers every equipped skill as a candidate when legal.
	for id in ["HEAVY_STRIKE","THROWING_KNIFE","LUNGE","BOMB"]:
		f = arena(id); s = f.s; f.foe.pos = f.c+Vector2i(1,0); s.floor_state.observe(s)
		f.hero.rules = [Rules.make_rule(id,"NEAREST","ALWAYS")]
		check(Tactics.choose(s,f.hero).kind == id,"rule engine picks %s when its rule is first" % id)
	f = arena("FIELD_DRESSING"); s = f.s; f.hero.hp = 10; f.hero.rules = [Abilities.default_rule("FIELD_DRESSING")]
	check(Tactics.choose(s,f.hero).kind == "FIELD_DRESSING","rule engine heals below half health")
	f.hero.hp = f.hero.max_hp
	check(Tactics.choose(s,f.hero).kind != "FIELD_DRESSING","rule engine does not heal at full health")
	print("Skill archetypes: %d failures" % failures); quit(1 if failures else 0)
```

- [ ] **Step 2: 실패 확인** — `godot --headless --path . --script res://tests/skill_archetypes.gd` → `HEAVY_STRIKE` 키 없음.

- [ ] **Step 3: 구현**

`expedition/abilities.gd`:
```gdscript
const DEFINITIONS = {
	"SHOCKWAVE":{...기존..., "effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS"},
	"BOMB":{...기존..., "effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS"},
	"IRON_HIDE":{...기존..., "effect":"SHIELD","axis":"","rule_when":"DANGER"},
	"HEAVY_STRIKE":{"name":"시험 강타","item":"시험용 강타 문양","description":"인접 대상 · 피해 28 · 재사용 3턴","target":"ENEMY","range":1,"radius":0,"damage":28,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS"},
	"THROWING_KNIFE":{"name":"시험 투척","item":"시험용 투척 문양","description":"사거리 4 · 피해 10 · 재사용 1턴","target":"ENEMY","range":4,"radius":0,"damage":10,"cooldown":1,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS"},
	"FIELD_DRESSING":{"name":"시험 응급처치","item":"시험용 처치 문양","description":"자신 체력 +15 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"heal":15,"cooldown":4,"effect":"HEAL","axis":"","rule_when":"HP"},
	"LUNGE":{"name":"시험 돌진","item":"시험용 돌진 문양","description":"사거리 3 · 적 옆으로 이동 후 피해 12 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":12,"cooldown":3,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS"}}

static func default_rule(id: String) -> Dictionary:
	var def: Dictionary = DEFINITIONS[id]
	return preload("res://expedition/tactic_rules.gd").make_rule(id,"SELF" if def.target == "SELF" else "NEAREST",def.rule_when)

static func lunge_cell(s, actor: Dictionary, target: Vector2i) -> Vector2i:
	var def: Dictionary = DEFINITIONS.LUNGE
	var best := Vector2i(-1,-1); var best_len := 1 << 30
	for d in s.DIRECTIONS:
		var cell: Vector2i = target+d
		if not s.is_free(cell) or not s.melee_reach(cell,target): continue
		var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,[cell],func(a,b): return s.can_step(a,b),func(_p): return 100)
		if not route.found: continue
		var steps: int = route.path.size()-1
		if steps > def.range: continue
		if steps < best_len or (steps == best_len and str(cell) < str(best)): best = cell; best_len = steps
	return best
```
`legal()`: SELF 분기에 `if def.effect == "HEAL" and actor.hp >= actor.max_hp: return false` 추가. ENEMY 분기 끝에 `if def.effect == "LUNGE": return lunge_cell(s,actor,target) != Vector2i(-1,-1)` (사거리·시선 검사 뒤).
`execute()`: `match def.effect:` — `"SHIELD"`: `actor.iron_guard = true`; `"HEAL"`: `actor.hp = mini(actor.max_hp,actor.hp+int(def.heal)); s.Body.heal(actor)`; `"LUNGE"`: `var cell := lunge_cell(...); actor.pos = cell; var victim := s.at(target); s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":[target],"area":false,"amount":0,"form":"SLASH"}); s.damage(victim,s.Growth.power(actor,"MELEE",def.damage),actor.id,"SLASH")`; `"DAMAGE"`: 기존 본문(`power`는 `s.Growth.power(actor,def.axis,def.damage)`).

`expedition/tactic_rules.gd`: `SKILLS`에 4개(스펙 §2). `make_rule`의 `"subject": "SELF" if target == "SELF" else "TARGET"`.
`expedition/tactical_action_selector.gd`: `if def.damage > 0:` → `if def.effect == "DAMAGE":`.
`expedition/session.gd`: 두 하드코딩 줄을 `actor.rules.append(Abilities.default_rule(id))`로.
`expedition/board.gd`: 배지 사전에 `"HEAVY_STRIKE":"강타","THROWING_KNIFE":"투척","FIELD_DRESSING":"처치","LUNGE":"돌진"`.

- [ ] **Step 4: 통과 확인** — 위 스위트 + `tests/abilities_growth.gd`, `tests/companion_tactics.gd`, `tests/character_ui.gd`, `tests/mobile_hud.gd`, `tests/boss_trial.gd`, `tests/encounter_sim.gd`.
- [ ] **Step 5: 커밋** — `feat: skill archetypes with data-driven effects and default rules`

---

### Task 2: `rules` 봇 정책, `skill_uses`, 기준 빌드

**Files:**
- Modify: `expedition/sim/bot_policy.gd`, `expedition/sim/encounter_runner.gd`, `data/content/reference_builds.json`, `tests/encounter_sim.gd`

**Interfaces:**
- Produces: `BotPolicy.step(s, "rules") -> String`(kind); `run_one().skill_uses: Dictionary`; `run_many().skill_uses_mean: Dictionary`; `Runner.apply_build` applies `rules`.

- [ ] **Step 1: 테스트 추가** — `tests/encounter_sim.gd` `run()`에 `await rules_policy()` 추가:

```gdscript
func rules_policy() -> void:
	var hob := [{"species_id":"dcss_hobgoblin","role":"MELEE"}]
	var cfg: Dictionary = config(hob,1,"rules",Session.DEFAULT_RULES); cfg.build = "b_strike"; cfg.supplies = [0,0,0,0,0,0]
	var one: Dictionary = Runner.run_one(cfg,11)
	check(one.result == "WIN" and one.skill_uses.get("HEAVY_STRIKE",0) >= 1,"rules policy uses the equipped strike (%s)" % [one.skill_uses])
	check(one == Runner.run_one(cfg,11),"rules policy deterministic")
	cfg.build = "b_dressing"
	var mixed := [{"species_id":"dcss_hobgoblin","role":"MELEE"},{"species_id":"goblin","role":"RANGED"},{"species_id":"kobold","role":"MELEE"}]
	var cfg2: Dictionary = config(mixed,1,"rules",Session.DEFAULT_RULES); cfg2.build = "b_dressing"; cfg2.supplies = [0,0,0,0,0,0]
	var two: Dictionary = Runner.run_one(cfg2,11)
	check(two.skill_uses.get("FIELD_DRESSING",0) >= 1,"dressing build heals at least once in a long fight (%s)" % [two.skill_uses])
	var many: Dictionary = Runner.run_many(cfg,range(1,11))
	check(many.skill_uses_mean.has("HEAVY_STRIKE") and many.skill_uses_mean.HEAVY_STRIKE >= 1.0,"run_many averages skill uses")
	for id in ["b_knife","b_lunge","b_bomb","b_shockwave","b_iron","melee_1"]:
		cfg.build = id
		check(Runner.run_one(cfg,3).result != "TIMEOUT","%s finishes a solo fight" % id)
```

- [ ] **Step 2: 실패 확인** — `b_strike` 빌드 없음.

- [ ] **Step 3: 구현**

`bot_policy.gd`: `step()`에 `if policy == "rules":` 분기 — 접근 단계(적 미가시) 뒤, `var choice: Dictionary = s.Tactics.choose(s,hero)`; `if s.act(choice.kind,choice.cell): return choice.kind`; 실패 시 `s.act("WAIT",hero.pos)` 후 `"WAIT"`. 물약·붕대 없음.
`encounter_runner.gd`: `run_one` 루프에서 `kind`가 `s.Abilities.DEFINITIONS.has(kind) or kind in ["PUSH","GUARD"]`이면 `skill_uses[kind] += 1`; 결과에 `skill_uses`. `run_many`: 모든 run의 키를 모아 평균 → `skill_uses_mean`. `apply_build`: `if row.has("rules"): actor.rules = row.rules.map(func(r): return Rules.make_rule(r[0],r[1],r[2]))`(`Rules` preload 추가).
`reference_builds.json`: 스펙 §4의 7개 + `melee_1`의 `rules`.

- [ ] **Step 4: 통과 확인** — `tests/encounter_sim.gd`(시간 출력), `tests/skill_archetypes.gd`.
- [ ] **Step 5: 커밋** — `feat: rules bot policy, skill usage counters and skill builds`

---

### Task 3: `skill_value` 실험·보고서·문서

**Files:**
- Modify: `data/content/balance_experiments.json`, `docs/balance-method.ko.md`(§5 아래 결과 링크 한 줄), `README.md`(검증 절 한 줄)
- Create: `tests/skill_value.gd`, `docs/balance/skill-value.md`, `docs/balance/skill-value.json`

- [ ] **Step 1: 실험 데이터** — 스펙 §5 블록을 `experiments.skill_value`로 추가(아레나 6개는 `action_economy`와 동일 내용 복사).

- [ ] **Step 2: 도구** — `tests/skill_value.gd`: `tests/action_economy.gd`의 구조(행렬 실행, `--quick`, 머리말, `commit_hash()`)를 따르되 다음이 다르다:
  - 축: builds × party_sizes × arenas, 규칙은 `current` 하나.
  - 표 1: 빌드·인원·아레나·승률[CI]·평균 피해·평균 라운드·장착 스킬 사용 평균(`skill_uses_mean[첫 장착 스킬]`)·GUARD 사용 평균·distinct.
  - 표 2: `baseline_build` 대비 Δ승률(pp)·Δ피해(같은 인원·아레나), 빌드별 요약(Δ승률 평균, 우세/열세 아레나 수).
  - 후보 판정: 스펙 §5-4 규칙. 사용 평균 < 0.2인 빌드는 `diagnose()`로 "합법 라운드 수"를 추정: 같은 config·시드 3개에서 `run_one`을 돌리며 매 라운드 `Abilities.legal(s, hero, id, 각 후보 대상)`을 검사하도록 `Runner.run_one`에 선택적 `probe: Callable` 훅(라운드마다 호출, 기본 빈 Callable)을 추가해 센다. 결과 문구: `합법 라운드 N/M — 규칙이 고르지 않음` 또는 `합법인 라운드 없음 — 사거리/조건 확인`.
  - "후보는 확정이 아니다" 문장, 결정론 문장, 물자 0 문장.
- [ ] **Step 3: `--quick`(시드 10)로 형식 확인 → 전체 실행(60시드) → 실행 시간 기록.**
- [ ] **Step 4: 문서** — `docs/balance-method.ko.md` §5 끝에 `실행 결과: docs/balance/skill-value.md (2026-09-22)`; README 검증 절에 `tests/skill_value.gd -- [--quick]` 한 줄. CI 목록에 `skill_archetypes` 추가(`skill_value`는 제외).
- [ ] **Step 5: 전체 스위트 + 임포트 검사.**
- [ ] **Step 6: 커밋** — 코드·문서 먼저, 보고서 재생성 후 두 번째 커밋(머리말 커밋이 코드 커밋과 일치하도록).

## 자체 점검
- 스펙 §1 → Task 1, §2 → Task 1, §3·§4 → Task 2, §5·§6 → Task 3.
- `Abilities.default_rule` 시그니처는 Task 1 정의·Task 1 테스트·session 호출이 같다. `run_one().skill_uses` 키 이름은 Task 2 테스트·Task 3 표에서 같다. `apply_build`의 `rules` 형식 `[[skill,target,when]]`은 JSON과 일치.
- LUNGE의 `lunge_cell`이 `path.size()-1 ≤ range`를 쓰므로 Task 1 테스트의 "사거리 3에서 (c+2,0)" 기대(경로 2칸)와 "4는 불법"이 성립한다.
