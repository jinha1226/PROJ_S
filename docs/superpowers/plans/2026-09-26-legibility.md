# 읽히게 만들기(최소판) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 전투 리포트에 영혼석이 한 일을 한 줄로, 키워드 칩을 누르면 뜻을, 상태창에 끼운 영혼석이 어떻게 맞물리는지(거는 쪽 → 쓰는 쪽)를 보여 준다. 그 밖의 안내 장치는 만들지 않는다.

**Architecture:** 효과 엔진이 규칙을 실행하는 동안 세션에 `s.effect_source = {"owner","effect"}`를 걸어 두고, 피해(`Session.after_damage`)와 회복(`StoneEffects.heal`)이 그것을 보고 `EffectReport`에 기록한다. 키워드는 새 데이터 `keywords.json`과 팝업 모듈 하나. 연계 설명은 끼운 효과의 `keywords`와 새 `roles`(거는 쪽·쓰는 쪽)로 묶고 순서를 정하는 순수 함수.

**Tech Stack:** Godot 4 GDScript, `extends SceneTree` 테스트(`godot --headless --path . --script res://tests/<name>.gd`).

**Spec:** `docs/superpowers/specs/2026-09-26-legibility-design.md`
**선행:** 도감 계획(`docs/superpowers/plans/2026-09-26-codex.md`) — 도감 화면에 칩을 붙이는 한 곳만 의존한다. 도감이 아직 없으면 그 한 곳은 건너뛴다.

## Global Constraints

- 기록 행: `battle_stats.members[id].effects[효과 id] = {"procs":int,"damage":int,"heal":int}`. 파티 멤버만.
- 상시 % 효과는 기록하지 않는다(몫 나누기 없음).
- 리포트 문구: `"<효과 이름> ×<procs> · 피해 <n> · 회복 <n>"`에서 0인 부분은 뺀다. 최대 5개, (피해+회복) 큰 순, 같으면 procs, 같으면 id.
- 연계 설명의 무기 형태 키워드: `SLASH`→`"출혈"`, `IMPACT`→`"골절"`, `PIERCE`→`"급소 노출"`. 효과 데이터의 키워드 표기가 다르면(예: `"급소"`) 효과 데이터 표기를 따른다.
- 커밋은 각 Task 파일만 `git add <경로>`. 남의 변경이 섞였으면 `git add -p`. 판단이 어려우면 멈추고 묻는다.

## Review Focus

- **중첩된 효과**: 효과 A 실행 중에 효과 B가 실행되면 B 동안의 피해는 B의 몫이고, B가 끝나면 다시 A. Task 1 테스트.
- **몬스터·파티 밖 NPC 효과**: 기록하지 않고 오류도 없다. Task 1 테스트.
- **영혼석이 없는 인물**: 연계 카드가 "연계 없음"이고 오류 없다. Task 3 테스트.

---

### Task 1: 효과 기록과 리포트 한 줄

**Files:**
- Create: `expedition/progression/effect_report.gd`
- Modify: `expedition/run/session.gd` (`effect_source`, `after_damage`, 상수)
- Modify: `expedition/progression/effect_engine.gd` (`fire`)
- Modify: `expedition/progression/stone_effects.gd` (`heal`)
- Modify: `expedition/run/run_result.gd` (멤버 행 `effects`)
- Modify: `expedition/ui/battle_hud.gd` (`report`)
- Test: `tests/effect_report.gd`

**Interfaces:**
- Produces: `Session.effect_source: Dictionary`, `EffectReport.note(s, owner_id: int, effect: String, field: String, amount: int)`, `EffectReport.top(rows: Dictionary, n: int) -> Array`, `EffectReport.line(entry: Dictionary) -> String`, 노드 `ReportEffects_<멤버 id>`

- [ ] **Step 1: 실패하는 테스트** — `tests/effect_report.gd`

```gdscript
extends SceneTree
## Effect report (legibility spec §1): procs, damage and healing per stone,
## the inner effect owning nested damage, party members only.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Report = preload("res://expedition/progression/effect_report.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Forms = preload("res://expedition/combat/forms.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	StoneEffects.force = 99; Forms.force = 99
	notes(); reflection(); nesting(); outsiders(); words()
	StoneEffects.force = -1; Forms.force = -1
	print("Effect report: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0
	s.party[1].pos = c+Vector2i(0,1)
	s.reset_battle_stats()
	return {"s":s,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func row(s, actor: Dictionary, effect: String) -> Dictionary:
	return s.member_stats(actor.id).get("effects",{}).get(effect,{})

func notes() -> void:
	var d := duo()
	Report.note(d.s,int(d.hero.id),"GHOUL_CLAW","procs",1)
	Report.note(d.s,int(d.hero.id),"GHOUL_CLAW","heal",12)
	check(int(row(d.s,d.hero,"GHOUL_CLAW").procs) == 1 and int(row(d.s,d.hero,"GHOUL_CLAW").heal) == 12,"a note lands on the member's row")

func reflection() -> void:
	var d := duo()
	slot(d.ally,["THORN_ARMOUR"])
	d.s.Reactions.begin_action(d.s)
	var before: int = int(d.foe.hp)
	d.s.damage(d.ally,20,int(d.foe.id),"physical")
	check(int(row(d.s,d.ally,"THORN_ARMOUR").damage) == before-int(d.foe.hp) and before > int(d.foe.hp),"a reflection is the thorn armour's damage")
	check(int(row(d.s,d.ally,"THORN_ARMOUR").procs) >= 1,"and a proc")

func nesting() -> void:
	var d := duo()
	d.s.effect_source = {"owner":int(d.hero.id),"effect":"OUTER"}
	var was: Dictionary = d.s.effect_source
	d.s.effect_source = {"owner":int(d.hero.id),"effect":"INNER"}
	d.s.damage(d.foe,5,int(d.hero.id),"REACTION")
	d.s.effect_source = was
	d.s.damage(d.foe,3,int(d.hero.id),"REACTION")
	d.s.effect_source = {}
	check(int(row(d.s,d.hero,"INNER").damage) == 5 and int(row(d.s,d.hero,"OUTER").damage) == 3,"the inner effect owns the inner damage")

func outsiders() -> void:
	var d := duo()
	Report.note(d.s,int(d.foe.id),"X","procs",1)
	check(d.s.member_stats(d.foe.id).is_empty(),"a monster keeps no report")

func words() -> void:
	check(Report.line({"effect":"THORN_ARMOUR","procs":3,"damage":18,"heal":0}).ends_with("×3 · 피해 18"),"a proc and damage line")
	check(Report.line({"effect":"GHOUL_CLAW","procs":2,"damage":0,"heal":30}).ends_with("×2 · 회복 30"),"a heal line")
	var top: Array = Report.top({"A":{"procs":1,"damage":10,"heal":0},"B":{"procs":5,"damage":2,"heal":0},"C":{"procs":0,"damage":0,"heal":0}},5)
	check(top.size() == 2 and top[0].effect == "A","top sorts by contribution and drops idle rows")
```

- [ ] **Step 2: 실패 확인** → `effect_report.gd` 없음.

- [ ] **Step 3: `effect_report.gd`**

```gdscript
extends RefCounted
## What each stone did in a fight (legibility spec §1): procs, the damage and
## healing done while it ran. Party members only; percent modifiers are not
## credited.
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")

static func note(s, owner_id: int, effect: String, field: String, amount: int) -> void:
	if effect.is_empty() or amount == 0: return
	var member: Dictionary = s.member_stats(owner_id)
	if member.is_empty(): return
	var row: Dictionary = member.get_or_add("effects",{}).get_or_add(effect,{"procs":0,"damage":0,"heal":0})
	row[field] = int(row.get(field,0))+amount

static func top(rows: Dictionary, n: int) -> Array:
	var list: Array = []
	for effect in rows:
		var r: Dictionary = rows[effect]
		if int(r.get("procs",0)) == 0 and int(r.get("damage",0)) == 0 and int(r.get("heal",0)) == 0: continue
		list.append({"effect":str(effect),"procs":int(r.get("procs",0)),"damage":int(r.get("damage",0)),"heal":int(r.get("heal",0))})
	list.sort_custom(func(a,b):
		var x: int = a.damage+a.heal; var y: int = b.damage+b.heal
		if x != y: return x > y
		if a.procs != b.procs: return a.procs > b.procs
		return a.effect < b.effect)
	return list.slice(0,n)

static func line(entry: Dictionary) -> String:
	var name: String = str(EffectEngine.content.effects.get(str(entry.effect),{}).get("name",entry.effect))
	var bits: Array = [name+(" ×%d" % int(entry.procs) if int(entry.procs) > 0 else "")]
	if int(entry.get("damage",0)) > 0: bits.append("피해 %d" % int(entry.damage))
	if int(entry.get("heal",0)) > 0: bits.append("회복 %d" % int(entry.heal))
	return " · ".join(bits)
```

- [ ] **Step 4: 걸기**

`session.gd` 상수에 `const EffectReport = preload("res://expedition/progression/effect_report.gd")`, 변수:

```gdscript
## The stone effect now running (EffectEngine.fire): damage and healing done
## meanwhile are credited to it in the battle report.
var effect_source: Dictionary = {}
```

`session.gd` `after_damage`의 `target.hp -= lost` 바로 뒤:

```gdscript
	if not effect_source.is_empty() and lost > 0 and int(effect_source.owner) == source:
		EffectReport.note(self,source,str(effect_source.effect),"damage",lost)
```

`effect_engine.gd` `fire`의 규칙 실행 부분:

```gdscript
			ctx.effect_id = str(effect)
			var was: Dictionary = s.effect_source
			s.effect_source = {"owner":int(owner.get("id",-1)),"effect":str(effect)}
			s.EffectReport.note(s,int(owner.get("id",-1)),str(effect),"procs",1)
			for rule in eligible:
				if rule.has("code"): Code.run(s,str(rule.code),owner,rule,ctx)
				else: Actions.run(s,owner,rule.get("do",[]),ctx)
			s.effect_source = was
```

`stone_effects.gd` `heal`의 `gained > 0` 분기 안:

```gdscript
		if not s.effect_source.is_empty(): s.EffectReport.note(s,int(s.effect_source.owner),str(s.effect_source.effect),"heal",gained)
```

`run_result.gd` `reset_battle_stats`의 멤버 행에 `"effects":{}`.

반사·반격처럼 엔진 밖 코드 처리기가 `s.damage`를 부르는 경우도 `fire` 안에서 실행되므로 같은 `effect_source`가 걸려 있다. 반사 피해가 `fire` 밖(예: `Passives.after_hit`의 가시 상태)에서 나면 기록되지 않는데, 그것은 영혼석 효과가 아니므로 그대로 둔다.

- [ ] **Step 5: 리포트 화면** — `battle_hud.gd` `report`의 멤버 줄(`var entry := line(ui,list,text,13)`) 다음:

```gdscript
		var worked: Array = s.EffectReport.top(row.get("effects",{}),5)
		if not worked.is_empty():
			var fx := line(ui,list,"  "+"   ".join(worked.map(func(e): return s.EffectReport.line(e))),12)
			fx.name = "ReportEffects_%d" % int(actor.id); fx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
```

- [ ] **Step 6: 확인** — `effect_report`, `effect_engine`, `effect_data`, `stone_effects`, `battle_presentation`, `reactions`가 `0 failures`.

- [ ] **Step 7: Commit**

```bash
git add expedition/progression/effect_report.gd expedition/run/session.gd expedition/progression/effect_engine.gd expedition/progression/stone_effects.gd expedition/run/run_result.gd expedition/ui/battle_hud.gd tests/effect_report.gd
git commit -m "Show which soul stones fired, and their damage and healing, in the battle report"
```

---

### Task 2: 키워드 팝업

**Files:**
- Create: `data/content/keywords.json`, `expedition/ui/screens/keyword_popup.gd`
- Modify: `expedition/ui/screens/essence_tab.gd`, `expedition/ui/screens/codex_screen.gd`(있으면), 장비 카드(`popups.gd`의 장비 효과 설명 자리)
- Test: `tests/keywords.gd`

**Interfaces:**
- Produces: `KeywordPopup.words: Dictionary`, `KeywordPopup.chips(ui, parent: Node, keywords: Array) -> HFlowContainer`, `KeywordPopup.show(ui, keyword: String)`, 노드 `KeywordChip_<키워드>`, `KeywordPopup`

- [ ] **Step 1: `keywords.json`** — 모든 효과 키워드의 뜻 한두 줄. 형식:

```json
{"version":1,"keywords":{
  "출혈":"300 tick 동안 틱마다 피해 2. 베기 명중이 걸 수 있고, 피부가 무른 적일수록 잘 걸립니다.",
  "골절":"300 tick 동안 모든 행동이 25% 느려집니다. 타격 명중이 걸 수 있고, 뼈가 약한 적일수록 잘 걸립니다."
}}
```

모자란 키워드 찾기(빈 목록이 될 때까지 채운다):

```bash
python3 -c "import json;e=json.load(open('data/content/stone_effects.json'))['effects'];k=json.load(open('data/content/keywords.json'))['keywords'];print(sorted({w for v in e.values() for w in v.get('keywords',[])}-set(k)))"
```

뜻은 ② 키워드 사전과 ① 규칙 수치를 그대로 옮긴다.

- [ ] **Step 2: 실패하는 테스트** — `tests/keywords.gd`

```gdscript
extends SceneTree
## Keyword chips (legibility spec §2): every keyword has a meaning, and a chip
## opens it.
const Session = preload("res://expedition/run/session.gd")
const KeywordPopup = preload("res://expedition/ui/screens/keyword_popup.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).effects
	for id in effects:
		for word in effects[id].get("keywords",[]):
			check(KeywordPopup.words.has(word) and not str(KeywordPopup.words[word]).is_empty(),"%s has a meaning (%s)" % [word,id])
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = Session.new_run(731); root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(3): await process_frame
	var holder := VBoxContainer.new(); scene.modal_content.add_child(holder)
	KeywordPopup.chips(scene,holder,["출혈"])
	var chip: Button = holder.find_child("KeywordChip_출혈",true,false)
	check(chip != null,"a chip is made")
	chip.pressed.emit()
	for _i in range(3): await process_frame
	check(scene.details_popup.visible and scene.modal_content.find_child("KeywordPopup",true,false) != null,"pressing it opens the meaning")
	print("Keywords: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 3: `keyword_popup.gd`**

```gdscript
extends RefCounted
## A keyword chip opens its meaning (legibility spec §2).
static var words: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/keywords.json")).get("keywords",{})

static func chips(ui, parent: Node, keywords: Array) -> HFlowContainer:
	var row := HFlowContainer.new(); parent.add_child(row)
	for word in keywords:
		var chip = ui.button(row,str(word),func(): show(ui,str(word))); chip.name = "KeywordChip_"+str(word)
		chip.add_theme_font_size_override("font_size",11)
	return row

static func show(ui, keyword: String) -> void:
	ui.clear(ui.modal_content)
	var box := VBoxContainer.new(); box.name = "KeywordPopup"; ui.modal_content.add_child(box)
	ui.label(box,keyword,18)
	var text = ui.label(box,str(words.get(keyword,"")),13)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; text.custom_minimum_size.x = ui.popup_width()
	ui.button(box,"닫기",func(): ui.details_popup.hide())
	ui.details_popup.popup_centered()
```

- [ ] **Step 4: 칩 붙이기** — `essence_tab.gd`의 영혼석 카드 효과 문구 아래, `codex_screen.gd`의 모은 영혼석 항목(빌드군 이름 줄 자리), 장비 카드의 효과 문구 아래에 `KeywordPopup.chips(ui, <부모>, <그 효과의 keywords>)`.

- [ ] **Step 5: 확인·Commit** — `keywords`, `essence_ui`, `codex_ui`(있으면), `character_ui`가 `0 failures`.

```bash
git add data/content/keywords.json expedition/ui/screens/keyword_popup.gd expedition/ui/screens/essence_tab.gd expedition/ui/screens/codex_screen.gd expedition/ui/screens/popups.gd tests/keywords.gd
git commit -m "Open a keyword's meaning from its chip"
```

---

### Task 3: 상태창 연계 설명

**Files:**
- Create: `tools/fill_effect_roles.py`, `expedition/progression/effect_links.gd`
- Modify: `data/content/stone_effects.json` (효과마다 `roles`)
- Modify: `expedition/ui/screens/character_folio.gd` (상태 탭)
- Modify: `.github/workflows/deploy-pages.yml`
- Test: `tests/effect_links.gd`

**Interfaces:**
- Consumes: `EffectEngine.effects(actor)`(슬롯 순서), `EffectEngine.content.effects[id].{name,text,keywords,roles}`, `Equipment.worn(actor)`, `Equipment.definition(item)`, `Equipment.title(item)`, `Forms.form_name(form)`, `KeywordPopup.chips`(Task 2)
- Produces: `EffectLinks.groups(actor: Dictionary) -> Array` = `[{"keyword": String, "lines": [{"side": "setup"|"both"|"payoff"|"with", "name": String, "text": String}]}]`(줄 둘 이상인 키워드만, 줄 수 많은 순, 같으면 키워드 순), `EffectLinks.SIDE_NAMES`, 노드 `EffectLinks`

- [ ] **Step 1: `roles` 채우기 도구** — `tools/fill_effect_roles.py`

`stone_effects.json`을 읽어 `roles`가 없는 효과에만 초안을 넣고, 바꾼 효과 id와 결과를 찍는다(이미 있는 `roles`는 건드리지 않는다).

- 상태 키워드 표(효과 데이터의 키워드 표기에 맞춘다): `bleed`→`출혈`, `fracture`→`골절`, `stun`→`기절`, `freeze`→`빙결`, `exposed`→`급소 노출`, `burn`→`화상`, `poison`→`중독`, `bind`→`속박`, `weak`→`약화`, `marked`→`표식`, `confuse`→`혼란`.
- setup: `do`의 `apply_status`/`spread_status`가 그 상태, 또는 `mod`에 `wound_chance.SLASH`(출혈)·`wound_chance.IMPACT`(골절)·`wound_chance.PIERCE`(급소 노출), 또는 `code` 처리기가 그 상태를 건다고 `effect_code.gd` 주석에 적힌 것.
- payoff: `if`의 `target_has`·`victim_had`·`status_is`가 그 상태, `target_harmful_at_least`는 `"해로운 상태"` 키워드의 payoff.
- 둘 다면 `both`. 키워드가 효과의 `keywords`에 없으면 추가하지 않는다(키워드는 사람이 정한 것).

```bash
python3 tools/fill_effect_roles.py data/content/stone_effects.json
```

찍힌 목록을 [③ 빌드군 문서](../specs/2026-09-26-build-families-part-effects-design.md) §3 표의 효과 설명과 대조해 틀린 것은 손으로 고친다. 구분이 없는 키워드(소환, 지원, 수호 등)는 `roles`를 두지 않는다.

- [ ] **Step 2: 실패하는 테스트** — `tests/effect_links.gd`

```gdscript
extends SceneTree
## Links on the status tab (legibility spec §3): equipped effects grouped by a
## shared keyword and told in order — who applies it, who uses it.
const Links = preload("res://expedition/progression/effect_links.gd")
const Engine = preload("res://expedition/progression/effect_engine.gd")
const Essences = preload("res://expedition/progression/essences.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func member(weapon: String, ids: Array) -> Dictionary:
	var actor := {"enemy":false,"level":10,"gear":{"weapon":{"type":weapon,"enchant":0}},"equipped_abilities":ids.duplicate(),"essences":{}}
	for id in ids: actor.essences[id] = 1
	return actor

## A stone whose effect plays `side` for `word`.
func stone(word: String, side: String) -> String:
	for id in Essences.catalog():
		var effect: Dictionary = Engine.content.effects.get(str(Essences.row(str(id)).get("effect","")),{})
		if str(effect.get("roles",{}).get(word,"")) == side: return str(id)
	return ""

func group(groups: Array, word: String) -> Dictionary:
	for g in groups:
		if g.keyword == word: return g
	return {}

func run() -> void:
	check(Links.groups(member("mace",[])).is_empty(),"no stones, no links")
	var setup := stone("출혈","setup"); var payoff := stone("출혈","payoff")
	check(not setup.is_empty() and not payoff.is_empty(),"the catalogue has a bleed setup and payoff")
	var g := group(Links.groups(member("mace",[payoff,setup])),"출혈")
	check(g.lines.size() == 2 and g.lines[0].side == "setup" and g.lines[1].side == "payoff","setup is told before payoff, whatever the slot order")
	check(not str(g.lines[0].text).is_empty(),"each line carries the effect's text")
	var sword := group(Links.groups(member("sword",[payoff])),"출혈")
	check(sword.lines.size() == 2 and sword.lines[0].name.contains("베기") and sword.lines[0].side == "setup","a slashing weapon applies bleed first")
	check(group(Links.groups(member("mace",[payoff])),"출혈").is_empty(),"a lone keyword makes no group")
	# Every effect naming a status keyword says which side it plays.
	for id in Engine.content.effects:
		var e: Dictionary = Engine.content.effects[id]
		for word in e.get("keywords",[]):
			if word in Links.STATUS_WORDS: check(e.get("roles",{}).has(word),"%s says its side for %s" % [id,word])
	print("Effect links: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

(키워드 표기가 `"출혈"`이 아니면 테스트·코드 모두 데이터 표기를 쓴다. `Essences.catalog()`가 부위 id 목록이 아니면 ④에서 만든 같은 역할 함수를 쓴다.)

- [ ] **Step 3: `effect_links.gd`**

```gdscript
extends RefCounted
## The status tab's link card (legibility spec §3): the member's effects, and
## its weapon's form, grouped by a shared keyword and told in order — what
## applies it, then what uses it.
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const FORM_WORD := {"SLASH":"출혈","IMPACT":"골절","PIERCE":"급소 노출"}
const FORM_TEXT := {"SLASH":"명중하면 출혈 (피부가 무를수록 잘 걸림)","IMPACT":"명중하면 골절 (뼈가 약할수록 잘 걸림)","PIERCE":"명중하면 급소 노출"}
const SIDE_ORDER := {"setup":0,"both":1,"payoff":2,"with":3}
const SIDE_NAMES := {"setup":"거는 쪽","both":"둘 다","payoff":"쓰는 쪽","with":"함께"}
const STATUS_WORDS := ["출혈","골절","기절","빙결","급소 노출","화상","중독","속박","약화","표식","혼란"]

static func groups(actor: Dictionary) -> Array:
	var by_word: Dictionary = {}
	var order := 0
	for item in [Equipment.worn(actor).get("weapon",{}),Equipment.worn(actor).get("offhand",{})]:
		if item.is_empty(): continue
		var form: String = str(Equipment.definition(item).get("form",""))
		if not FORM_WORD.has(form): continue
		by_word.get_or_add(str(FORM_WORD[form]),[]).append({"side":"setup","name":"%s(%s)" % [Equipment.title(item),Forms.form_name(form)],"text":str(FORM_TEXT[form]),"order":order})
		order += 1
	for id in EffectEngine.effects(actor):
		var effect: Dictionary = EffectEngine.content.effects.get(id,{})
		for word in effect.get("keywords",[]):
			var side: String = str(effect.get("roles",{}).get(str(word),"with"))
			var lines: Array = by_word.get_or_add(str(word),[])
			if lines.any(func(l): return l.name == str(effect.get("name",id))): continue
			lines.append({"side":side,"name":str(effect.get("name",id)),"text":str(effect.get("text","")),"order":order})
		order += 1
	var result: Array = []
	for word in by_word:
		var lines: Array = by_word[word]
		if lines.size() < 2: continue
		lines.sort_custom(func(a,b): return int(SIDE_ORDER[a.side]) < int(SIDE_ORDER[b.side]) if a.side != b.side else int(a.order) < int(b.order))
		result.append({"keyword":str(word),"lines":lines.map(func(l): return {"side":l.side,"name":l.name,"text":l.text})})
	result.sort_custom(func(a,b): return a.lines.size() > b.lines.size() if a.lines.size() != b.lines.size() else a.keyword < b.keyword)
	return result
```

(`Equipment.worn`이 없는 옛 장비 구조면 `actor.gear.weapon`만 읽고 형태는 `Forms.of_actor(actor)`로 대신한다.)

- [ ] **Step 4: 화면** — `character_folio.gd` `status(ui, list, actor)`에 카드 하나(`EffectLinks`), 제목 "영혼석 연계":
  - `groups`가 비면 "연계 없음".
  - 묶음마다: 키워드 칩(`KeywordPopup.chips(ui, card, [keyword])`) + " 연계", 그 아래 줄마다 `"%s · %s — %s" % [SIDE_NAMES[side], name, text]`(글자 12, 줄바꿈 허용).

- [ ] **Step 5: CI** — 스위트 목록에 `effect_report keywords effect_links`(도감의 `codex_ui` 뒤, 없으면 `essences` 뒤).

- [ ] **Step 6: 전체 확인**

```bash
fail=0; for suite in $(sed -n 's/.*for suite in \(.*\); do/\1/p' .github/workflows/deploy-pages.yml); do out=$(godot --headless --path . --script "res://tests/${suite}.gd" 2>&1); if echo "$out" | grep -q "SCRIPT ERROR\|ERROR"; then echo "FAIL $suite"; fail=1; fi; done; echo "fail=$fail"
```

Expected: `fail=0`.

- [ ] **Step 7: Commit**

```bash
git add tools/fill_effect_roles.py data/content/stone_effects.json expedition/progression/effect_links.gd expedition/ui/screens/character_folio.gd .github/workflows/deploy-pages.yml tests/effect_links.gd
git commit -m "Explain how equipped soul stones link: who applies each keyword, who uses it"
```

---

## 끝난 뒤 확인

- 실제 전투 뒤 리포트에 영혼석 줄, 키워드 칩 팝업, 상태창 연계 카드.
- 스펙 대응: §1 → Task 1, §2 → Task 2, §3 → Task 3, §4 테스트 → 각 Task. §5의 장치는 만들지 않았다.
