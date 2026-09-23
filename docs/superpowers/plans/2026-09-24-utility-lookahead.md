# Utility 선택기 + 예고 룩어헤드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 동료 AI의 4단계(태세 후보 점수)를 데이터 정의 Utility 선택기로 바꾸고, 파츠를 같은 풀에서 경쟁시키며, 공개된 예고를 읽는 룩어헤드 예측기와 commitment를 고려 사항으로 넣고, 모든 선택에 설명을 남긴다. 행동 계약 테스트·게이트·전투 시험 모드가 회귀망이다.

**Architecture:** `utility.gd`(곡선·프로필·입력·점수·설명), `lookahead.gd`(공개 정보 예측기), `parts_candidates.gd`(파츠 후보), 태그만 남긴 `stances.gd`, 파이프라인만 남긴 `tactical_action_selector.gd`. 명령·불 탈출·후퇴선·실수는 효용 이전 단계로 유지. 점수는 정수·결정론. UI 불변.

**Tech Stack:** Godot 4.6 GDScript, 헤드리스 테스트, CI 목록 `.github/workflows/deploy-pages.yml`.

**Spec:** `docs/superpowers/specs/2026-09-24-utility-lookahead-design.md` — 충돌 시 스펙 우선.

## Global Constraints

- **Godot 창을 절대 띄우지 않는다.** `--headless`만. 임포트 검사 `godot --headless --path . --editor --import --quit`.
- 커밋 `git -c user.name=jinha1226 -c user.email=jinha1226@gmail.com commit -m "…"` + 빈 줄 + `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. 떠돌이 `.import` 금지(새 `.gd`의 `.uid`는 추적).
- 파이프라인 순서(명령 → 불 탈출 → 후퇴선 → 실수 → 효용)와 즉시 반환 규칙은 불변. 파츠 수치·몬스터 AI·UI 불변. `session.gd`는 스펙 §8에 적힌 필드만.
- 결정론: 같은 시드 같은 선택. 점수 정수. 프로필 JSON은 `static var`로 한 번 로드.
- **행동 계약**: 기존 계약 테스트를 지우지 않는다. 의도가 바뀌면 검사를 다시 쓰고 커밋 메시지에 "왜"를 적는다. 어떤 태스크도 `tests/stances.gd`의 검사 수를 줄이지 않는다(대체는 가능).
- 가중치 조정은 `data/content/tactics_profiles.json`에서만, 변경은 `docs/balance/utility-tuning.md`에 기록. 코드 상수 부활 금지.
- 각 태스크 끝에 `utility stances autobattle protect skill_rule_conditions companion_tactics encounter_sim parts solo_balance` 통과(본문 예외 제외). 최종 CI 목록 전체 + 게이트.
- 테스트 러너 규약: `extends SceneTree`, `_initialize()`→`call_deferred("run")`, `quit(1 if failures else 0)`, 마지막 줄 `print("<이름>: %d checks, %d failures")`.
- 병렬 작업 경계: 이 계획은 `expedition/tactical_action_selector.gd`·`stances.gd`·새 파일 3개·`session.gd`(명시 필드)·`data/content/tactics_profiles.json`·테스트만 만진다. `main.gd`·`character_ui.gd`·`battle_hud.gd`·`arena_setup.gd`는 만지지 않는다.

---

### Task 1: Utility 핵심 — 곡선·프로필·입력·점수·설명, 태세 후보에 적용

**Files:**
- Create: `expedition/utility.gd`, `data/content/tactics_profiles.json`, `tests/utility.gd`
- Modify: `expedition/stances.gd` (후보 태그화·점수 제거), `expedition/tactical_action_selector.gd` (4단계에서 `Utility.score`; 파츠 선점은 이 태스크에서는 그대로 유지), `expedition/session.gd` (`last_action_kind`, `last_action_dir` 기록)

**Interfaces:**
- Produces: `Utility.profiles() -> Dictionary`, `Utility.curve(name, x) -> float`, `Utility.context(s, actor) -> Dictionary`, `Utility.inputs(s, actor, action, ctx) -> Dictionary`, `Utility.score(s, actor, action, ctx, stance, knobs) -> Dictionary {score:int, explain:Array}`, `Utility.tag(action) -> String`; 후보 딕셔너리 필드 `tag`, `dir`(MOVE), `damage`(예상 피해), `target_id`.
- Consumes: `Stances.party_target/protectee/threats_to/steps_between/ranged_part`, `Rules.lethal_threat`, `s.attack_preview`, `Tactics.danger`.

- [ ] **Step 1: 실패하는 테스트 — `tests/utility.gd`**

```gdscript
extends SceneTree
## Utility selector: curves, profiles, inputs, scoring and explanations.
const Session = preload("res://expedition/session.gd")
const Utility = preload("res://expedition/utility.gd")
const Stances = preload("res://expedition/stances.gd")
const Knobs = preload("res://expedition/knobs.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	curves()
	profiles()
	inputs_and_score()
	print("Utility: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func curves() -> void:
	check(Utility.curve("linear",0.25) == 0.25 and Utility.curve("inverse",0.25) == 0.75,"linear and inverse")
	check(Utility.curve("step",0.99) == 0.0 and Utility.curve("step",1.0) == 1.0,"step at 1")
	check(absf(Utility.curve("quad",0.5)-0.25) < 0.001 and absf(Utility.curve("sqrt",0.25)-0.5) < 0.001,"quad and sqrt")
	check(Utility.curve("linear",1.7) == 1.0 and Utility.curve("linear",-1.0) == 0.0,"inputs are clamped")
	check(Utility.curve("nope",0.5) == 0.5,"unknown curve is linear")

func profiles() -> void:
	var p: Dictionary = Utility.profiles()
	check(p.has("considerations") and p.has("profiles") and p.has("personality"),"profile file shape")
	for stance in Stances.IDS: check(p.profiles.has(stance),"profile for "+stance)
	for stance in p.profiles:
		for tag in p.profiles[stance]:
			for cid in p.profiles[stance][tag]:
				check(p.considerations.has(cid),"%s/%s uses a known consideration %s" % [stance,tag,cid])
	for cid in p.personality: check(p.considerations.has(cid) and p.personality[cid].knob in Knobs.RANGE,"personality entry valid: "+cid)
	check(Utility.tag({"kind":"MOVE","tag":"MOVE:approach"}) == "MOVE:approach" and Utility.tag({"kind":"HOB_CLUB"}) == "PART" and Utility.tag({"kind":"ATTACK"}) == "ATTACK","tags: explicit, part, default kind")

## Three members with basics, one foe two cells right of the hero.
func field(stances: Array, foes: int = 1) -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,9); Fixture.equip_basics(s)
	for i in range(3):
		s.party[i].stance = stances[i]; s.party[i].knobs = Knobs.DEFAULT.duplicate(); s.party[i].stress = 0
		s.party[i].pos = c+Vector2i(0,i); s.mistake_override[s.party[i].id] = false
	var revived: Array = []
	for i in range(foes):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0; foe.part_id = ""
		foe.pos = c+Vector2i(2+i,0); revived.append(foe)
	s.floor_state.observe(s); s.selected = 0
	for a in s.party: a.ap = 1
	return {"s":s,"c":c,"foes":revived}

func inputs_and_score() -> void:
	var f := field(["CHARGER","SKIRMISHER","GUARDIAN"]); var s = f.s; var hero: Dictionary = s.party[0]
	var ctx: Dictionary = Utility.context(s,hero)
	check(ctx.target.id == f.foes[0].id and ctx.has("hp_ratio") and ctx.has("threats"),"context carries the shared target")
	var step := {"kind":"MOVE","cell":hero.pos+Vector2i(1,0),"tag":"MOVE:approach","dir":Vector2i(1,0)}
	var inp: Dictionary = Utility.inputs(s,hero,step,ctx)
	check(inp.closes_distance == 0.5 and inp.target_adjacent == 1.0 and inp.cell_danger == 1.0,"approach step: closes half a band, lands adjacent, safe cell")
	s.intents = [{"id":f.foes[0].id,"cell":step.cell,"damage":10,"kind":""}]
	inp = Utility.inputs(s,hero,step,ctx)
	check(inp.cell_danger == 0.5,"telegraphed cell: danger 10/20 → 0.5")
	s.intents = []
	# Score: weights × curves, integer, deterministic, explained.
	var scored: Dictionary = Utility.score(s,hero,step,ctx,"CHARGER",Knobs.DEFAULT)
	check(scored.score is int and scored.score > 0 and scored.explain.size() <= 3 and scored.explain[0].contrib >= scored.explain.back().contrib,"score is an integer with a ranked explanation")
	check(scored == Utility.score(s,hero,step,ctx,"CHARGER",Knobs.DEFAULT),"deterministic")
	# Personality multiplier: posture +100 adds 15 to an adjacent attack's damage weight (40 → 55).
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s); ctx = Utility.context(s,hero)
	var atk := {"kind":"ATTACK","cell":f.foes[0].pos,"tag":"ATTACK","damage":18}
	var calm: int = Utility.score(s,hero,atk,ctx,"CHARGER",Knobs.DEFAULT).score
	var bold: Dictionary = Knobs.DEFAULT.duplicate(); bold.posture = 100
	var boldly: int = Utility.score(s,hero,atk,ctx,"CHARGER",bold).score
	check(boldly-calm == int(round(15*Utility.curve("linear",18.0/40.0))),"posture scales the damage weight by +15")
	# Stance profiles differ: the same disengage step scores higher for a skirmisher than a charger.
	var away := {"kind":"MOVE","cell":hero.pos+Vector2i(-1,0),"tag":"MOVE:disengage","dir":Vector2i(-1,0)}
	check(Utility.score(s,hero,away,ctx,"SKIRMISHER",Knobs.DEFAULT).score > Utility.score(s,hero,away,ctx,"CHARGER",Knobs.DEFAULT).score,"profiles differ per stance")
	# Candidates now carry tags and no scores; choose still picks the contract behaviour.
	var options: Array = Stances.candidates(s,hero,"CHARGER",Knobs.DEFAULT)
	check(not options.is_empty() and options.all(func(o): return o.has("tag") and not o.has("score")),"candidates are tagged and unscored")
	check(s.Tactics.choose(s,hero).kind == "ATTACK","adjacent foe: charger attacks")
```

- [ ] **Step 2: 실패 확인** — `timeout 120 godot --headless --path . --script res://tests/utility.gd 2>&1 | tail -3`.

- [ ] **Step 3: `expedition/utility.gd`**

```gdscript
extends RefCounted
## Utility selector: every candidate action is scored as Σ weight × curve(input)
## over a closed catalogue of considerations; the stance picks the weights,
## personality knobs shift them, and the top three terms explain the choice.
const Stances = preload("res://expedition/stances.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Abilities = preload("res://expedition/abilities.gd")
static var _profiles: Dictionary = {}

static func profiles() -> Dictionary:
	if _profiles.is_empty():
		_profiles = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/tactics_profiles.json"))
	return _profiles

static func curve(name: String, x: float) -> float:
	x = clampf(x,0.0,1.0)
	match name:
		"inverse": return 1.0-x
		"step": return 1.0 if x >= 1.0 else 0.0
		"quad": return x*x
		"sqrt": return sqrt(x)
		_: return x

static func tag(action: Dictionary) -> String:
	if action.has("tag"): return str(action.tag)
	return "PART" if Abilities.DEFINITIONS.has(str(action.kind)) else str(action.kind)

## Per-actor facts every candidate shares.
static func context(s, actor: Dictionary) -> Dictionary:
	var target := Stances.party_target(s)
	var protectee := Stances.protectee(s,actor)
	return {"target":target,"protectee":protectee,"threats":(Stances.threats_to(s,protectee) if not protectee.is_empty() else []),
		"hp_ratio":float(actor.hp)/float(actor.max_hp),"ranged":Stances.ranged_part(actor),
		"here_danger":float(s.Tactics.danger(s,actor.pos)),"last_kind":str(actor.get("last_action_kind","")),"last_dir":actor.get("last_action_dir",Vector2i.ZERO)}

static func inputs(s, actor: Dictionary, action: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind: String = str(action.kind)
	var dest: Vector2i = action.cell if kind == "MOVE" else actor.pos
	var target: Dictionary = ctx.target
	var d_now: int = Stances.steps_between(actor.pos,target.pos) if not target.is_empty() else 0
	var d_then: int = Stances.steps_between(dest,target.pos) if not target.is_empty() else 0
	var damage: float = float(action.get("damage",0))
	var victim: Dictionary = s.at(action.cell) if kind != "MOVE" else {}
	var result := {
		"target_adjacent": 1.0 if not target.is_empty() and s.melee_reach(dest,target.pos) else 0.0,
		"any_foe_adjacent": 1.0 if s.combat_enemies().any(func(e): return s.melee_reach(dest,e.pos)) else 0.0,
		"damage": damage/40.0,
		"kill": 1.0 if not victim.is_empty() and victim.get("enemy",false) and damage >= float(victim.hp) else 0.0,
		"closes_distance": maxf(0.0,float(d_now-d_then))/2.0,
		"opens_distance": maxf(0.0,float(d_then-d_now))/2.0,
		"in_band": 0.0, "cell_danger": 1.0-minf(1.0,float(s.Tactics.danger(s,dest))/20.0),
		"ally_delta": (float(s.Tactics.adjacent_allies(s,actor,dest)-s.Tactics.adjacent_allies(s,actor,actor.pos))+1.0)/2.0,
		"protectee_near": 0.0, "protectee_gap": 0.0, "protectee_lethal": 0.0,
		"rule_ready": 0.0, "contact_penalty": 0.0,
		"same_as_last": 1.0 if kind == ctx.last_kind and (kind != "MOVE" or action.get("dir",Vector2i.ZERO) == ctx.last_dir) else 0.0,
		"la_self_hit": 1.0, "la_ally_hit": 1.0, "la_enemy_hit": damage/40.0, "la_lethal_saved": 0.0}
	if not str(ctx.ranged).is_empty() and not target.is_empty():
		var reach: int = int(Abilities.DEFINITIONS[ctx.ranged].range)
		result.in_band = 1.0 if d_then >= 2 and d_then <= reach else 0.0
	var p: Dictionary = ctx.protectee
	if not p.is_empty():
		result.protectee_near = 1.0 if Stances.steps_between(dest,p.pos) <= 1 else 0.0
		result.protectee_lethal = 1.0 if Rules.lethal_threat(s,p) >= p.hp else 0.0
		if not ctx.threats.is_empty():
			var t: Dictionary = ctx.threats[0]
			var gap: Vector2i = p.pos+Vector2i(signi(t.pos.x-p.pos.x),signi(t.pos.y-p.pos.y))
			result.protectee_gap = 1.0 if dest == gap else 0.0
	if Abilities.DEFINITIONS.has(kind):
		var def: Dictionary = Abilities.DEFINITIONS[kind]
		for rule in actor.rules:
			if rule.skill == kind and Rules.matches(s,actor,action,rule): result.rule_ready = 1.0
		if int(def.range) >= 3 and s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos)): result.contact_penalty = 1.0
	return result

static func score(s, actor: Dictionary, action: Dictionary, ctx: Dictionary, stance: String, knobs: Dictionary) -> Dictionary:
	var data := profiles()
	var weights: Dictionary = data.profiles.get(stance,{}).get(tag(action),{})
	var inp := inputs(s,actor,action,ctx)
	var total := 0.0
	var terms: Array = []
	var ids: Array = weights.keys(); ids.sort()
	for cid in ids:
		var weight: float = float(weights[cid])
		var personal: Dictionary = data.personality.get(cid,{})
		if not personal.is_empty(): weight += float(knobs.get(personal.knob,0))*float(personal.scale)
		var value: float = curve(str(data.considerations[cid].curve),float(inp.get(cid,0.0)))
		var contrib: float = weight*value
		total += contrib
		terms.append({"id":cid,"input":inp.get(cid,0.0),"weight":weight,"contrib":int(round(contrib))})
	terms.sort_custom(func(a,b): return a.contrib > b.contrib if a.contrib != b.contrib else a.id < b.id)
	return {"score":int(round(total)),"explain":terms.slice(0,3)}
```

`la_*`는 이 태스크에서는 중립값(1.0/0.0)으로 두고 Task 3에서 예측기로 채운다. 프로필 JSON은 스펙 §4를 그대로 옮긴다(단 Task 1에서는 `PART` 항이 아직 쓰이지 않는다).

- [ ] **Step 4: `stances.gd` 태그화** — 각 `options.append({"kind":…,"cell":…,"score":N,"reason":…})`에서 `score`를 빼고 `tag`(스펙 §4 태그)와 MOVE의 `dir`(첫 걸음 방향 부호 `Vector2i(signi(dx),signi(dy))`), ATTACK의 `damage`(미리보기 피해), `target_id`를 넣는다. `approach()`의 점수 인자 삭제. 즉시 반환 두 개(불 탈출·posture ≤ −60 예고 회피)는 그대로(§0.8) — 단 불 탈출은 `Tactics.choose` 1단계로 옮겨 모든 태세에 적용.

- [ ] **Step 5: `tactical_action_selector.gd`** — `choose` 4단계: `var ctx := Utility.context(s,actor)`; 후보마다 `var r := Utility.score(s,actor,o,ctx,stance,knobs); o.score = r.score; o.explain = r.explain`; `rank`로 선택. `cohesion_shift`·`attack_shift`·`KNOB.attack/escape/guard/cohesion` 삭제(후퇴선의 150/−20은 `RETREAT` 상수로 남김). 파츠 선점(`rule_candidates`+`rule_choice`)은 **이 태스크에서는 유지**(Task 2가 옮긴다). `session.act_as` 성공 뒤 `actor.last_action_kind = kind`, `actor.last_action_dir = (target - actor_pos_before)` 부호(MOVE만; 아니면 `Vector2i.ZERO`).

- [ ] **Step 6: 계약 테스트 맞추기** — `stances`·`autobattle`·`protect`·`companion_tactics` 실행. 실패하는 검사는 "행동이 왜 달라졌나"를 판단: 프로필 가중치로 기존 의도를 되살릴 수 있으면 가중치를 조정(기록), 의도가 바뀌어야 맞으면 검사를 다시 쓰고 커밋 메시지에 이유. `tests/stances.gd` 검사 수 ≥ 109 유지.

- [ ] **Step 7: 실행** — `utility stances autobattle protect skill_rule_conditions companion_tactics encounter_sim parts solo_balance` 통과(`solo_balance` ≥ 3/8), 임포트 오류 0. `docs/balance/utility-tuning.md` 시작(변경한 가중치·이유).

- [ ] **Step 8: 커밋** — `feat(ai): utility selector with stance weight profiles and explanations`

---

### Task 2: 파츠를 같은 풀에서 — `parts_candidates.gd`, `rule_ready`, `contact_penalty`

**Files:**
- Create: `expedition/parts_candidates.gd`
- Modify: `expedition/tactical_action_selector.gd` (`rule_candidates`/`rule_choice` 삭제, 4단계 풀 합치기), `tests/utility.gd` (`parts()`), `tests/skill_rule_conditions.gd`·`tests/parts.gd`·`tests/protect.gd`(계약 재작성: "규칙 조건이 참이면 그 파츠가 최고 점수")

**Interfaces:**
- Produces: `PartsCandidates.candidates(s, actor) -> Array` (kind = 파츠 id, tag `PART`, `cell`, `damage`, `target_id`, `reason` = 파츠 이름; PUSH는 밀 수 있는 후보만·아군 사거리 이탈 검사 유지; GUARD는 인접 아군마다; 범위 파츠는 아군 오사 후보 제외).
- Consumes: Task 1 `Utility.score`(`rule_ready`, `contact_penalty`, `la_*` 중립).

- [ ] **Step 1: 실패하는 테스트 — `tests/utility.gd parts()`**

```gdscript
const Parts = preload("res://expedition/parts_candidates.gd")
func parts() -> void:
	var f := field(["CHARGER","CHARGER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	var pool: Array = Parts.candidates(s,hero)
	check(pool.any(func(o): return o.kind == "PUSH" and o.tag == "PART") and pool.any(func(o): return o.kind == "GUARD" and o.cell == s.party[1].pos),"push and guard are part candidates")
	# Rule condition drives the part: a charging foe makes PUSH outscore the basic attack.
	s.intents = [{"id":f.foes[0].id,"cell":hero.pos,"damage":9,"kind":""}]; f.foes[0].charging = true
	check(s.Tactics.choose(s,hero).kind == "PUSH","charging foe: push (rule_ready) wins")
	s.intents = []; f.foes[0].charging = false
	check(s.Tactics.choose(s,hero).kind == "ATTACK","no telegraph: basic attack wins over an idle push")
	# Guard when an ally would die.
	s.party[1].hp = 3; f.foes[0].pos = s.party[1].pos+Vector2i(1,0); s.floor_state.observe(s)
	s.intents = [{"id":f.foes[0].id,"cell":s.party[1].pos,"damage":9,"kind":""}]; f.foes[0].charging = true
	var pick: Dictionary = s.Tactics.choose(s,hero)
	check(pick.kind == "GUARD" and pick.cell == s.party[1].pos,"ally lethal: guard wins")
	s.intents = []; f.foes[0].charging = false; s.party[1].hp = s.party[1].max_hp
	# A skirmisher in contact never fires a ranged part.
	var g := field(["SKIRMISHER","CHARGER","CHARGER"]); var t = g.s; var h: Dictionary = t.party[0]
	h.equipped_abilities = ["KOBOLD_SLING","GUARD"]; h.rules = [t.Abilities.default_rule("KOBOLD_SLING"),t.Abilities.default_rule("GUARD")]; h.cooldowns = {}
	g.foes[0].pos = h.pos+Vector2i(1,1); t.floor_state.observe(t)
	check(t.Tactics.choose(t,h).kind != "KOBOLD_SLING","contact: the sling is penalised out")
	g.foes[0].pos = h.pos+Vector2i(3,0); t.floor_state.observe(t)
	check(t.Tactics.choose(t,h).kind == "KOBOLD_SLING","at range: fires")
	# The part choice carries an explanation naming rule_ready.
	check(t.Tactics.choose(t,h).explain.any(func(e): return e.id == "rule_ready"),"explanation names the rule")
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: 구현** — `rule_candidates`의 본문을 `parts_candidates.gd`로 옮기되 점수 없이 태그·`damage`(파츠 정의 피해 또는 밀치기 8)·`target_id`만 남긴다. `choose` 4단계: `options = Stances.candidates(...) + Parts.candidates(s,actor)`; `rule_choice` 삭제; 거리형 접촉 필터 삭제(`contact_penalty` −1000이 대신). `Utility.inputs`의 `rule_ready`는 `Rules.matches(s, actor, action, rule)` — 후보 딕셔너리가 `Rules.matches`가 기대하는 `kind/cell` 형태임을 확인.
- 계약 재작성: `skill_rule_conditions.gd`의 "매칭 규칙 → 그 파츠 선택" 검사는 그대로 통과해야 한다(rule_ready 120~150이 다른 항을 압도). 통과하지 않는 조건이 있으면 그 조건에 한해 가중치 조정 후 기록.

- [ ] **Step 4: 실행** — Task 1 목록 + `parts protect skill_rule_conditions` 통과. `solo_balance` ≥ 3/8.

- [ ] **Step 5: 커밋** — `feat(ai): parts compete in the utility pool; rule conditions become considerations`

---

### Task 3: 룩어헤드 예측기 + commitment

**Files:**
- Create: `expedition/lookahead.gd`
- Modify: `expedition/utility.gd` (`la_*` 입력 채우기), `expedition/session.gd` (`lookahead_enabled := true`), `tests/utility.gd` (`lookahead()`, `oscillation()`), `data/content/tactics_profiles.json` (가중치 조정 기록)

**Interfaces:**
- Produces: `Lookahead.predict(s, actor, action) -> {"self": int, "allies": int, "enemies": int, "lethal_saved": int}`; `s.lookahead_enabled`.

- [ ] **Step 1: 실패하는 테스트**

```gdscript
const Lookahead = preload("res://expedition/lookahead.gd")
func lookahead() -> void:
	var f := field(["CHARGER","CHARGER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	# Stepping onto a telegraphed cell is predicted as damage to self.
	var cell: Vector2i = hero.pos+Vector2i(1,0)
	s.intents = [{"id":f.foes[0].id,"cell":cell,"damage":10,"kind":""}]; f.foes[0].charging = true
	var stay := Lookahead.predict(s,hero,{"kind":"WAIT","cell":hero.pos})
	var into := Lookahead.predict(s,hero,{"kind":"MOVE","cell":cell})
	check(stay.self == 0 and into.self >= 10,"moving into the telegraph costs at least the announced damage")
	# Guarding a lethal ally saves it.
	s.intents = [{"id":f.foes[0].id,"cell":s.party[1].pos,"damage":9,"kind":""}]; s.party[1].hp = 5
	var guard := Lookahead.predict(s,hero,{"kind":"GUARD","cell":s.party[1].pos})
	check(guard.lethal_saved == 1,"guard saves a lethal ally")
	# Pushing the caster cancels its intent.
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	var push := Lookahead.predict(s,hero,{"kind":"PUSH","cell":f.foes[0].pos,"damage":8})
	check(push.lethal_saved == 1 and push.allies == 0,"push cancels the telegraph")
	s.intents = []; f.foes[0].charging = false; s.party[1].hp = s.party[1].max_hp
	# Killing blow is predicted as enemy damage and removes that foe's threat.
	f.foes[0].hp = 5
	var kill := Lookahead.predict(s,hero,{"kind":"ATTACK","cell":f.foes[0].pos,"damage":18})
	check(kill.enemies >= 5 and kill.self == 0,"a kill removes the foe's threat")
	# Inputs are wired: la_self_hit lower for the telegraphed step.
	f.foes[0].hp = 30; s.intents = [{"id":f.foes[0].id,"cell":cell,"damage":10,"kind":""}]; f.foes[0].charging = true
	var ctx: Dictionary = Utility.context(s,hero)
	check(Utility.inputs(s,hero,{"kind":"MOVE","cell":cell,"tag":"MOVE:approach"},ctx).la_self_hit < Utility.inputs(s,hero,{"kind":"WAIT","cell":hero.pos,"tag":"WAIT"},ctx).la_self_hit,"la_self_hit reads the predictor")
	s.lookahead_enabled = false
	check(Utility.inputs(s,hero,{"kind":"MOVE","cell":cell,"tag":"MOVE:approach"},ctx).la_self_hit == 1.0,"disabled: neutral")
	s.lookahead_enabled = true

func oscillation() -> void:
	# A skirmisher with a ranged part facing a stationary foe must not alternate A-B-A-B.
	var f := field(["SKIRMISHER","CHARGER","CHARGER"]); var s = f.s; var h: Dictionary = s.party[0]
	h.equipped_abilities = ["KOBOLD_SLING","GUARD"]; h.rules = [s.Abilities.default_rule("KOBOLD_SLING"),s.Abilities.default_rule("GUARD")]; h.cooldowns = {}
	f.foes[0].pos = h.pos+Vector2i(5,0); f.foes[0].alert = false; s.floor_state.observe(s)
	var kinds: Array = []
	for round in range(4):
		h.ap = 1
		var pick: Dictionary = s.Tactics.choose(s,h)
		kinds.append(pick.kind+str(pick.get("dir",Vector2i.ZERO)))
		s.act_as(h,pick.kind,pick.cell,false)
	check(not (kinds[0] == kinds[2] and kinds[1] == kinds[3] and kinds[0] != kinds[1]),"no A-B-A-B: %s" % [kinds])
```

- [ ] **Step 2: 실패 확인.**

- [ ] **Step 3: `expedition/lookahead.gd`**

```gdscript
extends RefCounted
## One-round lookahead from public information only: apply the action's
## immediate effect to a scratch view of positions/HP/intents, then estimate
## what every party member would take this round the way lethal_threat does.
const Rules = preload("res://expedition/tactic_rules.gd")
const Abilities = preload("res://expedition/abilities.gd")

static func predict(s, actor: Dictionary, action: Dictionary) -> Dictionary:
	var kind: String = str(action.kind)
	var damage: int = int(action.get("damage",0))
	var pos_override: Dictionary = {}      # actor id -> Vector2i
	var hp_override: Dictionary = {}       # actor id -> int
	var protected: Dictionary = {}         # ally id -> guardian id
	var intents: Array = s.intents.duplicate(true)
	var enemies_hit := 0
	var victim: Dictionary = s.at(action.cell) if kind != "MOVE" and kind != "WAIT" else {}
	match kind:
		"MOVE": pos_override[actor.id] = action.cell
		"ATTACK":
			if not victim.is_empty(): hp_override[victim.id] = int(victim.hp)-damage; enemies_hit += mini(damage,int(victim.hp))
		"GUARD":
			if not victim.is_empty(): protected[victim.id] = actor.id
		_:
			if Abilities.DEFINITIONS.has(kind):
				var def: Dictionary = Abilities.DEFINITIONS[kind]
				if def.effect == "PUSH" and not victim.is_empty():
					var landing: Vector2i = action.cell+(action.cell-actor.pos)
					if s.can_step(action.cell,landing): pos_override[victim.id] = landing
					else: hp_override[victim.id] = int(victim.hp)-damage; enemies_hit += mini(damage,int(victim.hp))
					intents = intents.filter(func(i): return i.id != victim.id)
				elif def.effect == "GUARD" and not victim.is_empty(): protected[victim.id] = actor.id
				elif def.effect in ["DAMAGE","LUNGE"]:
					var cells: Array = Abilities.cells(s,actor,kind,action.cell) if def.effect == "DAMAGE" else [action.cell]
					for other in s.enemies:
						if other.hp > 0 and other.pos in cells:
							hp_override[other.id] = int(other.hp)-damage; enemies_hit += mini(damage,int(other.hp))
					if def.effect == "LUNGE": pos_override[actor.id] = Abilities.lunge_cell(s,actor,kind,action.cell)
	var before_lethal := 0; var after_lethal := 0
	var self_hit := 0; var ally_hit := 0
	for member in s.alive():
		var was: int = Rules.lethal_threat(s,member)
		if was >= member.hp: before_lethal += 1
		var now: int = threat_after(s,member,pos_override,hp_override,protected,intents)
		if now >= member.hp: after_lethal += 1
		if member.id == actor.id: self_hit = now
		else: ally_hit += now
	return {"self":self_hit,"allies":ally_hit,"enemies":enemies_hit,"lethal_saved":maxi(0,before_lethal-after_lethal)}

## lethal_threat over the scratch view: dead foes vanish, moved actors are
## read at their new cells, a guarded member takes half.
static func threat_after(s, member: Dictionary, pos_override: Dictionary, hp_override: Dictionary, protected: Dictionary, intents: Array) -> int:
	var pos: Vector2i = pos_override.get(member.id,member.pos)
	var worst := 0
	var bonus: int = s.Floor.enemy_bonus(s.light)
	for intent in intents:
		if intent.cell == pos: worst = maxi(worst,int(intent.damage)+(bonus if s.floor_mode else 0))
	var roles: Dictionary = s.Floor.MonsterAI.ROLES
	for e in s.combat_enemies():
		if int(hp_override.get(e.id,e.hp)) <= 0 or int(e.get("cast_recovery",0)) > 0: continue
		var epos: Vector2i = pos_override.get(e.id,e.pos)
		var role: String = e.get("role","MELEE")
		if not roles.has(role): role = "MELEE"
		var hit := 0
		if s.melee_reach(epos,pos): hit = int(roles[role].damage) if role == "MELEE" else 4
		elif role != "MELEE" and s.Floor.MonsterAI.line(s,epos,pos,int(roles[role].range)): hit = int(roles[role].damage)
		if hit > 0: worst = maxi(worst,hit+bonus)
	if protected.has(member.id): worst = maxi(1,worst/2) if worst > 0 else 0
	return worst
```

`Rules.lethal_threat`의 시야 조건(`alert or line ≤ 9`)과 같은 조건을 `threat_after`에도 넣는다(현행 `lethal_threat` 코드를 그대로 복사해 `pos_override/hp_override`만 끼워 넣는 것이 안전). 룩어헤드가 꺼져 있으면 `Utility.inputs`는 `la_self_hit = la_ally_hit = 1.0`, `la_lethal_saved = 0`, `la_enemy_hit = damage/40`.

- [ ] **Step 4: `Utility.inputs` 연결** — `if s.lookahead_enabled: var la := Lookahead.predict(s,actor,action); la_self_hit = 1 − min(1, la.self / max(1, actor.hp)); la_ally_hit = 1 − min(1, la.allies / max(1, 아군 HP 합)); la_enemy_hit = min(1, la.enemies/40); la_lethal_saved = min(1, la.lethal_saved/3.0)`. 예측기는 후보마다 한 번(캐시 없음).

- [ ] **Step 5: commitment 확인** — `same_as_last` 가중치(10)로 `oscillation()`이 통과하는지; 통과하지 않으면 15까지 조정(기록). 태세 계약 테스트가 깨지면 프로필로 복구.

- [ ] **Step 6: 실행** — Task 2 목록 통과, `solo_balance` ≥ 3/8, `tests/ranged_probe.gd` 2인 결과 ≥ 이전(0.73/0.90/1.00). 임포트 오류 0.

- [ ] **Step 7: 커밋** — `feat(ai): telegraph lookahead and commitment considerations`

---

### Task 4: 설명 계측 · 게이트 · 문서

**Files:**
- Modify: `expedition/session.gd` (`battle_stats.members[].explains` 최근 20), `expedition/sim/encounter_runner.gd` (`explains` 수집), `tests/stance_gate.gd`·`tests/skill_value.gd` (`--explain` 옵션: 아레나별 상위 고려 사항 빈도 표), `.github/workflows/deploy-pages.yml` (` utility`), `docs/balance/utility-tuning.md`, `docs/balance-method.ko.md`, `docs/superpowers/specs/2026-09-24-utility-ai-refactor-design.md` 머리에 "v2로 대체됨" 한 줄

- [ ] **Step 1: 계측** — `auto_step`이 `choice.explain`을 `battle_stats.members[id].explains.append({"round","kind","cell","explain"})`(최대 20, 앞에서 버림). `tests/utility.gd`에 검사 2개(기록됨·20 상한).
- [ ] **Step 2: 게이트** — `stance_gate`(혼합 ≥ 0.85 전 아레나 목표, 단일 4/6 ≥ 0.6), `solo_balance ≥ 3/8`, `ranged_probe`. 미달 시 프로필 가중치만 두 번까지 조정, 전부 `utility-tuning.md`에 기록; 그래도 미달이면 멈추고 보고.
- [ ] **Step 3: `--explain` 표** — 각 아레나에서 각 태세 멤버의 선택을 상위 고려 사항 id로 집계(빈도 %)해 `utility-tuning.md`에 표로. "돌격형은 target_adjacent/damage, 거리형은 in_band/cell_danger, 호위형은 protectee_*가 상위"인지 확인 — 태세가 구분되는가의 정량 증거.
- [ ] **Step 4: 눈 체크리스트** — `utility-tuning.md`에 전투 시험 모드 확인 항목(아레나 3 × 태세 3): "돌격형이 붙는가 / 거리형이 거리를 두는가 / 호위형이 곁을 지키는가 / 예고 칸을 태세대로 다루는가 / 파츠가 제때 나가는가" — 사용자 확인용.
- [ ] **Step 5: 전체 스위트 + 임포트** 통과. 커밋 `feat(ai): explanation stats, gates and tuning record`.

---

## 자기 검토

- 스펙 커버리지: §1 파이프라인(T1·T2) / §2 고려 사항(T1, la_* T3) / §3 예측기(T3) / §4 프로필(T1) / §5 후보 생성기·파츠(T1·T2) / §6 설명·계측(T1 choice, T4 stats) / §7 검증(T1~T4) / §8 파일(전부).
- 이름 일관성: `Utility.profiles/curve/tag/context/inputs/score`, `Lookahead.predict/threat_after`, `PartsCandidates.candidates`, 후보 필드 `tag/dir/damage/target_id/explain`, 액터 `last_action_kind/last_action_dir`, `s.lookahead_enabled`, `battle_stats.members[].explains`.
- 위험: T1에서 계약 테스트가 얼마나 깨질지는 가중치 출발값에 달렸다 — Step 6이 그 조정 루프이고, 검사 수 유지 규칙이 "지워서 통과"를 막는다. T3 예측기는 `lethal_threat`와 같은 시야 조건을 복사해야 어긋나지 않는다.
