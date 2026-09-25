# 이능 화면·알림·NPC 이능·난이도 게이트 Implementation Plan (3 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the level-and-essence progression its screens and its NPC side: the 이능 tab, the level-up and essence banners, numeric stat sheets with source breakdowns, monster inspection, personality-driven NPC essence loadouts, and the §5 difficulty gate.

**Architecture:** Two new UI modules (`essence_tab.gd` for the folio tab, `banners.gd` for the centre banners) read only the Plan 1 interfaces (`Essences`, `StatSheet`, `TagSets`, the `Session` wrappers and `session.events`). One new actor module (`npc_essences.gd`) scores and equips essences for independent NPCs and gives them essences from their own hunts. One new sim module (`difficulty_gate.gd`) rebuilds the "cleared floors 1..N−1" hero and fights floor N pack by pack, and a manual test writes the result to `docs/balance/`.

**Tech Stack:** Godot 4.6 GDScript, headless SceneTree tests (`godot --headless --path . --script res://tests/<suite>.gd`).

**Spec:** `docs/superpowers/specs/2026-09-25-bestiary-progression-design.md` (§3.9 NPC, §4 알림과 화면, §5 난이도 곡선, §7 테스트). Plans 1 and 2 (`2026-09-25-essence-core.md`, `2026-09-25-essence-content.md`) must be merged first.

## Global Constraints

- 최대 레벨 10, 이능 슬롯 수 = 레벨(1~10칸). 이능 단계 최대 3.
- 끼우기와 빼기는 야영 중이거나 주변에 깨어 있는 적이 없을 때만 한다 (`Essences.can_manage(session)`).
- 이능 화면: 슬롯 격자(최대 10칸, 5칸씩 두 줄)와 가방의 이능 카드 목록. 켜진 태그 세트는 슬롯 줄 아래에 보여 준다.
- 레벨 업: 화면 가운데 큰 배너. 슬롯이 늘었으면 "이능 슬롯 +1"을 함께 보여 준다.
- 이능 획득: 큰 카드로 기본 스탯·패시브·액티브·역할 태그·속성 태그를 보여 준다. 변종 카드는 속성 색 테두리를 쓴다. 이미 가진 이능이면 "단계 상승 가능"을 표시한다.
- 캐릭터 화면: 능력치 넷, 방어 수치 셋, 속성 저항 다섯을 모두 숫자로 보여 준다. 누르면 그 수치가 어디서 왔는지(종족, 장비, 이능별)를 풀어 보여 준다. 숙련 표시와 숙련 아이콘을 뺀다.
- 몬스터: 전투 화면에서 몬스터를 길게 누르면 스탯과 이능을 보여 준다.
- NPC: 원만성이 낮으면 광폭·기습 태그를, 성실성이 높으면 수호 태그를, 개방성이 높으면 술사 태그를 우선한다. 이미 켜진 세트를 이어 가는 이능을 먼저 고른다. NPC가 몬스터를 잡아 얻은 이능은 NPC가 가진다. 영입하면 그대로 따라온다.
- 난이도 합격선: 기준 주인공이 전투 한 번에 평균 HP의 25~40%를 잃는다. 층을 끝까지 탐험하려면 야영이 한 번 이상 필요하다. 앞 층 몬스터의 절반만 잡은 주인공은 전투당 HP 손실이 뚜렷하게 크다. 결과는 `docs/balance/`에 기록한다.
- 검사 수를 줄이지 않는다: 고치는 기존 스위트는 검사를 바꿔 쓰되 개수를 줄이지 않는다.
- Commit with explicit paths only (`git commit -m "..." -- <paths>`); other sessions edit this repo concurrently. End every commit message with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Plan 1 interfaces this plan consumes

These exist once Plan 1 is merged. Use the names exactly.

- `expedition/progression/essences.gd` (`Essences`): `ROLES` `{"PACK":"무리","BERSERK":"광폭","AMBUSH":"기습","GUARD":"수호","ARCHER":"사수","CASTER":"술사"}`, `ELEMENTS` `{"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지"}`, `MAX_TIER` (3), `MAX_LEVEL` (10), `CASTER_BY_SCHOOL` (`{"fire":<essence id>, ...}`); `has(id)`, `row(id)`, `title(id) -> String`, `stats(id, tier) -> Dictionary` (keys from `StatSheet.KEYS`), `role(id)`, `element(id)`, `school(id)`, `tier(actor, id) -> int` (0 when not absorbed), `equipped(actor) -> Array`, `slot_count(actor) -> int`, `sync_slots(actor)`, `absorb(s, actor, id) -> String`, `equip(s, actor, slot, id) -> bool`, `unequip(s, actor, slot) -> bool`, `spell_cap(tier) -> int`, `spell_choices(actor, id) -> Array`, `choose_spell(s, actor, id, spell_id) -> bool`, `sync_spells(actor)`, `caster_tier(actor, school) -> int`. `equip`/`unequip`/`absorb`/`choose_spell` check `can_manage(s)` (IDLE, CAMP, or EXPLORE with `floor_state.safe(s)`); `put(actor, slot, id)`/`take(actor, slot)` are the unchecked forms NPCs use mid-floor. UI buttons are enabled by `Essences.can_manage(session)`.
- Actor fields: `essences` `{id: tier}`, `essence_spells` `{essence_id: spell_id}`, `equipped_abilities` (Array sized `slot_count`), `pool_bonus` `{"hp","mp"}`.
- `expedition/progression/stat_sheet.gd` (`StatSheet`): `KEYS` `["str","dex","int","con","ac","ev","sh","res_fire","res_ice","res_air","res_poison","res_will"]`, `NAMES` (Korean label per key), `sheet(s, actor) -> {key: {"total": int, "parts": [{"from": String, "value": int}]}}` (works for monsters too), `value(s, actor, key) -> int`, `refresh_pools(s, actor)`.
- `expedition/progression/tag_sets.gd` (`TagSets`): `counts(actor) -> Dictionary`, `level(actor, tag) -> int` (0, 2 or 3), `active(actor) -> Array` of `{"tag","level","text"}`.
- `Session`: `absorb_essence(index, id) -> String` ("" on success), `choose_essence_spell(index, essence_id, spell_id) -> bool`, `equip_part(index, slot, id) -> bool` and `unequip_part(index, slot) -> bool` (absorbed essences, allowed when `Essences.can_manage(s)`), `gain_level_xp(actor, amount) -> int`, `events: Array` with `{"kind":"LEVEL_UP","actor":id,"level":n}` and `{"kind":"ESSENCE","id":essence_id,"new":bool}`.
- Variant essence ids from Plan 2 have the form `"<BASE>@<element>"`, for example `"GOBLIN_SHIV@fire"`.

## File structure

| File | Responsibility |
| --- | --- |
| Create `expedition/ui/screens/essence_tab.gd` | The 이능 tab: slot grid, bag with 흡수, owned essences, active sets, slot chooser, caster spell picker, shared essence text helpers |
| Create `expedition/ui/screens/banners.gd` | Level-up and essence-acquired centre banners drawn from `session.events` |
| Create `expedition/actors/npc_essences.gd` | NPC essence scoring by HEXACO, greedy loadout with set continuation, essences from NPC hunts |
| Create `expedition/sim/difficulty_gate.gd` | Baseline hero for floor N and pack-by-pack fights |
| Modify `expedition/sim/model_b_runner.gd` | Extract the hero's turn into `hero_turn(s)` for reuse |
| Modify `expedition/ui/screens/character_folio.gd` | Tabs, heading, numeric stat sheet with breakdowns; drop the Plan 1 minimal parts tab |
| Modify `expedition/ui/screens/popups.gd` | Route the 이능 tab, bag 흡수 buttons, monster inspection, NPC level line |
| Modify `expedition/ui/main.gd` | Show banners after every refresh |
| Modify `expedition/run/session.gd` | Call `NpcEssences.on_hunt` on kills |
| Create tests `tests/essence_ui.gd`, `tests/stat_sheet_ui.gd`, `tests/banners.gd`, `tests/inspect_ui.gd`, `tests/npc_essences.gd`, `tests/difficulty_gate.gd` | One suite per task |
| Modify tests `tests/character_ui.gd`, `tests/parts.gd`, `tests/abilities_growth.gd`, `tests/companion_tactics.gd`, `tests/continuous_floor.gd`, `tests/test_loadout.gd`, `tests/skill_rule_conditions.gd` | Follow the tab rename |

---

### Task 1: The 이능 tab

**Files:**
- Create: `expedition/ui/screens/essence_tab.gd`
- Modify: `expedition/ui/screens/character_folio.gd` (tab list, heading; delete `parts` and `replace`)
- Modify: `expedition/ui/screens/popups.gd` (`show_character`, `show_tactics`, the bag's `"파츠"` branch, `equip_from_bag`)
- Test: `tests/essence_ui.gd`

**Interfaces:**
- Consumes: `Essences.*`, `TagSets.active`, `Session.absorb_essence`, `Session.equip_part`, `Session.unequip_part` (see above).
- Produces: `EssenceTab.build(ui, list: VBoxContainer, actor: Dictionary) -> void`, `EssenceTab.chooser(ui, slot: int) -> void`, `EssenceTab.slot_detail(ui, slot: int, id: String) -> void`, `EssenceTab.pick_spell(ui, index: int, id: String) -> void`, `EssenceTab.tag_line(id: String) -> String`, `EssenceTab.stat_line(id: String, tier: int) -> String`, `EssenceTab.active_line(id: String) -> String`, `EssenceTab.border_for(id: String, fallback: Color) -> Color`, `EssenceTab.tag_name(tag: String) -> String`, `EssenceTab.ELEMENT_COLORS`. Node names: `EssenceSlots` (GridContainer), `EssenceSlot<n>` (Button), `EssenceSets`, `EssenceBag`, `EssenceOwned` (PanelContainer), `EssenceAbsorb_<id>`, `EssencePick_<id>`, `EssenceUnequip`, `EssenceSpellPick_<id>`, `EssenceSpell_<spell id>` (Button). Folio tabs are `["상태","성격","기억","이능"]`; `show_character(i,"파츠")` opens `"이능"`.

- [ ] **Step 1: Write the failing test**

Create `tests/essence_ui.gd`:

```gdscript
extends SceneTree
## §4 이능 화면: the slot grid, 흡수 from the bag, equipping, sets and the
## caster's spell picker.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func frames(n: int) -> void:
	for _i in range(n): await process_frame

func button(scene, node_name: String) -> Button:
	var found: Array = scene.modal_content.find_children(node_name,"Button",true,false)+scene.item_detail.find_children(node_name,"Button",true,false)
	return found[0] if not found.is_empty() else null

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await frames(4)
	s.phase = "CAMP"
	var hero: Dictionary = s.party[0]
	s.parts_bag["RAT_GNAW"] = 2
	s.parts_bag["RIVER_RAT_SPLASH"] = 1
	scene.show_character(0,"이능")
	await frames(4)
	var tabs: Array = scene.modal_content.find_child("CharacterTabs",true,false).get_children().map(func(b): return b.text)
	check(tabs == ["상태","성격","기억","이능"],"the folio has four tabs ending in 이능")
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("이능 슬롯"))
	check(not heading.is_empty() and heading[0].text == "이능 슬롯 0 / 1","level one: no essence worn, one slot")
	var grid: GridContainer = scene.modal_content.find_child("EssenceSlots",true,false)
	check(grid != null and grid.columns == 5 and grid.get_child_count() == 10,"ten slot cells in two rows of five")
	check(not button(scene,"EssenceSlot0").disabled and button(scene,"EssenceSlot1").disabled,"only the level's slots open")
	check(button(scene,"EssenceSlot1").text == "Lv.2","a locked slot names the level that opens it")
	# 흡수: a new essence, then a tier up.
	var absorb: Button = button(scene,"EssenceAbsorb_RAT_GNAW")
	check(absorb != null and not absorb.disabled,"the bag offers 흡수 in camp")
	absorb.pressed.emit(); await frames(3)
	check(Essences.tier(hero,"RAT_GNAW") == 1 and int(s.parts_bag.RAT_GNAW) == 1,"흡수 takes one copy and learns the essence")
	check(scene.modal_content.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("단계 1 → 2")),"the bag row now offers the next tier")
	button(scene,"EssenceAbsorb_RAT_GNAW").pressed.emit(); await frames(3)
	check(Essences.tier(hero,"RAT_GNAW") == 2,"a second copy raises the tier")
	check(scene.modal_content.find_child("EssenceOwned",true,false) != null,"owned essences are listed")
	# Equip through the slot chooser.
	button(scene,"EssenceSlot0").pressed.emit(); await frames(3)
	var pick: Button = button(scene,"EssencePick_RAT_GNAW")
	check(pick != null and not pick.disabled,"the chooser lists the absorbed essence")
	pick.pressed.emit(); await frames(4)
	check(hero.equipped_abilities[0] == "RAT_GNAW","the chooser equips into the slot")
	scene.item_popup.hide()
	# Not while enemies are awake.
	s.phase = "BATTLE"
	scene.show_character(0,"이능"); await frames(3)
	check(button(scene,"EssenceAbsorb_RIVER_RAT_SPLASH").disabled,"흡수 is refused in battle")
	s.phase = "CAMP"
	# A second slot and a set.
	s.gain_level_xp(hero,65)
	check(Essences.slot_count(hero) == 2,"level two opens a second slot")
	check(s.absorb_essence(0,"RIVER_RAT_SPLASH").is_empty() and s.equip_part(0,1,"RIVER_RAT_SPLASH"),"a second pack essence is worn")
	scene.show_character(0,"이능"); await frames(3)
	var sets: Node = scene.modal_content.find_child("EssenceSets",true,false)
	check(sets != null and sets.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("무리 2")),"the pack set shows under the grid")
	# A caster essence and its spell.
	var caster: String = str(Essences.CASTER_BY_SCHOOL.fire)
	s.parts_bag[caster] = 1
	check(s.absorb_essence(0,caster).is_empty() and s.unequip_part(0,1) and s.equip_part(0,1,caster),"the fire caster essence is worn")
	EssenceTab.pick_spell(scene,0,caster); await frames(3)
	var options: Array = scene.item_detail.find_children("EssenceSpell_*","Button",true,false)
	check(options.size() == Essences.spell_choices(hero,caster).size() and options.size() > 0,"one button per allowed spell")
	var first: String = str(options[0].name).trim_prefix("EssenceSpell_")
	options[0].pressed.emit(); await frames(3)
	check(str(hero.essence_spells.get(caster,"")) == first,"the picker sets the essence's spell")
	# The old tab name still opens the new tab.
	scene.show_character(0,"파츠"); await frames(3)
	check(scene.character_tab == "이능","파츠 opens 이능")
	scene.queue_free(); await process_frame
	print("Essence UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/essence_ui.gd`
Expected: FAIL with a parse error: `Could not resolve ... essence_tab.gd`.

- [ ] **Step 3: Create `expedition/ui/screens/essence_tab.gd`**

```gdscript
extends RefCounted
## The 이능 tab (§4): the slot grid, the bag with 흡수, what this member has
## absorbed, the sets that are on and, for a caster essence, its spell. The
## text helpers are shared with the banners and the monster inspection.
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const COLUMNS := 5
const BORDER := Color("6d5b3f")
const ELEMENT_COLORS := {"fire":Color("d9643a"),"ice":Color("6fb7e0"),"air":Color("e0cf52"),"poison":Color("79b84a"),"will":Color("a57ad6")}
const SCHOOL_NAMES := {"fire":"화염","ice":"냉기","air":"전기","hex":"변이","summon":"소환"}

## A variant essence ("<BASE>@<element>") wears its element's colour.
static func border_for(id: String, fallback: Color = BORDER) -> Color:
	if not id.contains("@"): return fallback
	return ELEMENT_COLORS.get(Essences.element(id),fallback)

static func tag_name(tag: String) -> String:
	return str(Essences.ROLES.get(tag,Essences.ELEMENTS.get(tag,tag)))

static func tag_line(id: String) -> String:
	var tags: Array = []
	if not str(Essences.role(id)).is_empty(): tags.append(tag_name(str(Essences.role(id))))
	if not str(Essences.element(id)).is_empty(): tags.append(tag_name(str(Essences.element(id))))
	return " · ".join(tags)

static func stat_line(id: String, tier: int) -> String:
	var stats: Dictionary = Essences.stats(id,clampi(tier,1,Essences.MAX_TIER))
	var parts: Array = []
	for key in StatSheet.KEYS:
		if int(stats.get(key,0)) != 0: parts.append("%s %+d" % [StatSheet.NAMES[key],int(stats[key])])
	return "기본 스탯 없음" if parts.is_empty() else " · ".join(parts)

## The passive and the active, as the parts catalogue words them; a caster
## essence's active is its school's spell.
static func active_line(id: String) -> String:
	var school: String = str(Essences.school(id))
	if not school.is_empty(): return "주문 이능 · %s 계열 주문 하나를 액티브로 쓴다" % str(SCHOOL_NAMES.get(school,school))
	var def: Dictionary = Abilities.DEFINITIONS.get(id.split("@")[0],{})
	return str(def.get("description",""))

static func surface(border: Color) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new(); skin.bg_color = Color("1b1916"); skin.border_color = border
	skin.set_border_width_all(2); skin.set_content_margin_all(8)
	return skin

static func label(parent: Node, value: String, font_size: int = 14) -> Label:
	var line := Label.new(); line.text = value; line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL; line.add_theme_font_size_override("font_size",font_size)
	line.add_theme_color_override("font_color",Color("e0d4bc")); parent.add_child(line); return line

static func card(parent: Node, title: String, node_name: String) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.name = node_name; panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",surface(BORDER)); parent.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",6); panel.add_child(box)
	label(box,title,18).add_theme_color_override("font_color",Color("e5d0a4"))
	return box

static func owned(actor: Dictionary) -> Array:
	var ids: Array = actor.get("essences",{}).keys()
	ids.sort()
	return ids

static func build(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var editable: bool = Essences.can_manage(ui.session) and actor.hp > 0
	var slots := GridContainer.new(); slots.name = "EssenceSlots"; slots.columns = COLUMNS
	slots.add_theme_constant_override("h_separation",4); slots.add_theme_constant_override("v_separation",4)
	list.add_child(slots)
	var open: int = Essences.slot_count(actor)
	for slot in range(Essences.MAX_LEVEL): slot_cell(ui,slots,actor,slot,slot < open,editable)
	sets(list,actor)
	bag(ui,list,actor,editable)
	absorbed(ui,list,actor,editable)

static func slot_cell(ui, grid: GridContainer, actor: Dictionary, slot: int, open: bool, editable: bool) -> void:
	var id: String = str(actor.equipped_abilities[slot]) if open and slot < actor.equipped_abilities.size() else ""
	var caption: String = "Lv.%d" % (slot+1) if not open else ("+" if id.is_empty() else Essences.title(id))
	var cell: Button = ui.button(grid,caption,func(): pressed_slot(ui,slot),open and (editable or not id.is_empty()))
	cell.name = "EssenceSlot%d" % slot
	cell.custom_minimum_size = Vector2(66,66)
	cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_theme_font_size_override("font_size",11)
	if not id.is_empty(): cell.add_theme_stylebox_override("normal",surface(border_for(id,Color("c6a34c"))))

static func pressed_slot(ui, slot: int) -> void:
	var actor: Dictionary = ui.session.party[ui.tactics_actor]
	var id: String = str(actor.equipped_abilities[slot]) if slot < actor.equipped_abilities.size() else ""
	if id.is_empty(): chooser(ui,slot)
	else: slot_detail(ui,slot,id)

static func sets(list: VBoxContainer, actor: Dictionary) -> void:
	var box := card(list,"켜진 세트","EssenceSets")
	var rows: Array = TagSets.active(actor)
	if rows.is_empty(): label(box,"켜진 세트 없음",13)
	for row in rows: label(box,"%s %d · %s" % [tag_name(str(row.tag)),int(row.level),str(row.text)],13)

static func bag(ui, list: VBoxContainer, actor: Dictionary, editable: bool) -> void:
	var index: int = ui.tactics_actor
	var box := card(list,"가방의 이능","EssenceBag")
	var ids: Array = ui.session.parts_bag.keys()
	ids.sort()
	var shown := 0
	for entry in ids:
		var id: String = str(entry)
		if int(ui.session.parts_bag[id]) <= 0 or not Essences.has(id): continue
		shown += 1
		var tier: int = Essences.tier(actor,id)
		var row := HBoxContainer.new(); box.add_child(row)
		var info := VBoxContainer.new(); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(info)
		label(info,"%s ×%d" % [Essences.title(id),int(ui.session.parts_bag[id])],15)
		if not tag_line(id).is_empty(): label(info,tag_line(id),12)
		if tier >= Essences.MAX_TIER: label(info,"최고 단계",12)
		elif tier == 0: label(info,"새 이능 · "+stat_line(id,1),12)
		else: label(info,"단계 %d → %d · %s" % [tier,tier+1,stat_line(id,tier+1)],12)
		var absorb: Button = ui.button(row,"흡수",func(): absorb_press(ui,index,id),editable and tier < Essences.MAX_TIER)
		absorb.name = "EssenceAbsorb_"+id
	if shown == 0: label(box,"가방에 이능 없음",13)

static func absorb_press(ui, index: int, id: String) -> void:
	var reason: String = ui.session.absorb_essence(index,id)
	if not reason.is_empty(): ui.notice = reason
	ui.show_character(index,"이능")

static func absorbed(ui, list: VBoxContainer, actor: Dictionary, editable: bool) -> void:
	var index: int = ui.tactics_actor
	var box := card(list,"흡수한 이능","EssenceOwned")
	var ids: Array = owned(actor)
	if ids.is_empty(): label(box,"흡수한 이능 없음",13)
	for id in ids:
		var tier: int = Essences.tier(actor,id)
		label(box,"%s · %d단계%s" % [Essences.title(id),tier," · 장착" if id in actor.equipped_abilities else ""],15)
		if not tag_line(id).is_empty(): label(box,tag_line(id),12)
		label(box,stat_line(id,tier),12)
		if not str(Essences.school(id)).is_empty():
			var spell_id: String = str(actor.get("essence_spells",{}).get(id,""))
			var spell: Dictionary = ui.session.CombatStats.content.spells.get(spell_id,{})
			label(box,"주문: %s" % str(spell.get("name","선택 안 함")),12)
			var pick: Button = ui.button(box,"주문 선택",func(): pick_spell(ui,index,id),editable)
			pick.name = "EssenceSpellPick_"+str(id)

## The absorbed essences this member is not wearing yet, one tap each.
static func chooser(ui, slot: int) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); label(ui.item_detail,"이능 장착",20)
	var shown := 0
	for id in owned(actor):
		if id in actor.equipped_abilities: continue
		shown += 1
		var pick: Button = ui.button(ui.item_detail,"%s · %d단계" % [Essences.title(id),Essences.tier(actor,id)],func():
			if ui.session.equip_part(index,slot,id):
				ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"이능"),Essences.can_manage(ui.session) and actor.hp > 0)
		pick.name = "EssencePick_"+str(id)
	if shown == 0: label(ui.item_detail,"흡수한 이능 없음",14)
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

static func slot_detail(ui, slot: int, id: String) -> void:
	var index: int = ui.tactics_actor
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail)
	label(ui.item_detail,"%s · %d단계" % [Essences.title(id),Essences.tier(actor,id)],20)
	if not tag_line(id).is_empty(): label(ui.item_detail,tag_line(id),13)
	label(ui.item_detail,stat_line(id,Essences.tier(actor,id)),13)
	label(ui.item_detail,active_line(id),13).custom_minimum_size.x = ui.popup_width()
	if not str(Essences.school(id)).is_empty():
		var pick: Button = ui.button(ui.item_detail,"주문 선택",func(): pick_spell(ui,index,id),Essences.can_manage(ui.session))
		pick.name = "EssenceSpellPick_"+id
	var off: Button = ui.button(ui.item_detail,"해제",func():
		if ui.session.unequip_part(index,slot):
			ui.item_popup.hide(); ui.refresh(); ui.show_character(index,"이능"),Essences.can_manage(ui.session) and actor.hp > 0)
	off.name = "EssenceUnequip"
	ui.button(ui.item_detail,"닫기",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()

## The spells this caster essence's tier allows; the chosen one is ticked.
static func pick_spell(ui, index: int, id: String) -> void:
	var actor: Dictionary = ui.session.party[index]
	ui.clear(ui.item_detail); label(ui.item_detail,"%s · 주문 선택" % Essences.title(id),18)
	var chosen: String = str(actor.get("essence_spells",{}).get(id,""))
	var catalogue: Dictionary = ui.session.CombatStats.content.spells
	for entry in Essences.spell_choices(actor,id):
		var spell_id: String = str(entry)
		var row: Dictionary = catalogue.get(spell_id,{})
		var caption: String = "%s%s · Lv%d · %dMP" % ["✓ " if spell_id == chosen else "",str(row.get("name",spell_id)),int(row.get("level",1)),int(row.get("mp",0))]
		var pick: Button = ui.button(ui.item_detail,caption,func():
			if ui.session.choose_essence_spell(index,id,spell_id):
				ui.item_popup.hide(); ui.show_character(index,"이능"),Essences.can_manage(ui.session))
		pick.name = "EssenceSpell_"+spell_id
		pick.icon = Art.spell_icon(spell_id); pick.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pick.add_theme_constant_override("icon_max_width",28)
	ui.button(ui.item_detail,"취소",func(): ui.item_popup.hide()); ui.item_popup.popup_centered()
```

- [ ] **Step 4: Switch the folio to the new tab**

In `expedition/ui/screens/character_folio.gd`:

1. Add after the other preloads:

```gdscript
const Essences = preload("res://expedition/progression/essences.gd")
```

2. Replace the tab loop header line (the line that starts with `	for name in [` inside `shell`, whatever list Plan 1 left in it) with:

```gdscript
	for name in ["상태","성격","기억","이능"]:
```

3. Replace the whole line that starts with `	var heading := Label.new(); heading.text =` with:

```gdscript
	var heading := Label.new(); heading.text = heading_text(ui,tab)
```

and add this function directly after `shell`:

```gdscript
static func heading_text(ui, tab: String) -> String:
	var actor: Dictionary = ui.session.party[ui.tactics_actor]
	if tab == "이능": return "이능 슬롯 %d / %d" % [Essences.equipped(actor).size(),Essences.slot_count(actor)]
	return "현재 상태" if tab == "상태" else tab
```

4. Delete `static func parts(...)` and `static func replace(...)` with their doc comments. Check nothing else calls them:

Run: `grep -rn "CharacterUI.parts\|CharacterUI.replace\|\.replace(ui" expedition`
Expected: no output.

- [ ] **Step 5: Route the tab and the bag in `popups.gd`**

1. Add after `const CharacterUI = ...`:

```gdscript
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
```

2. In `show_character`, make the first line of the body map the old name, and replace the whole `match tab:` block with the four tabs:

```gdscript
static func show_character(ui, index: int, tab: String = "상태") -> void:
	if tab == "파츠": tab = "이능"
	var session = ui.session
	ui.stop_navigation()
	ui.tactics_actor = clampi(index,0,session.party.size()-1); ui.character_tab = tab
	ui.clear(ui.modal_content)
	var list: VBoxContainer = CharacterUI.shell(ui,tab)
	var actor: Dictionary = session.party[ui.tactics_actor]
	match tab:
		"상태": CharacterUI.status(ui,list,actor)
		"이능": EssenceTab.build(ui,list,actor)
		"성격": CharacterUI.personality(ui,list,actor)
		"기억": CharacterUI.memories(ui,list,actor)
	ui.details_popup.popup_centered(Vector2i(ui.get_viewport_rect().size))
```

3. `show_tactics` opens the new tab:

```gdscript
static func show_tactics(ui) -> void:
	show_character(ui,ui.tactics_actor,"이능")
```

4. Replace the whole `elif row.category == "파츠":` branch in the bag item detail (everything down to the line before `ui.button(ui.item_detail,"닫기",...)`) with:

```gdscript
	elif row.category == "파츠":
		for i in range(session.party.size()):
			var member: Dictionary = session.party[i]
			var tier: int = Essences.tier(member,id)
			var caption: String = "%s 흡수" % member.name if tier == 0 else "%s 흡수 (%d→%d단계)" % [member.name,tier,tier+1]
			var absorb = ui.button(ui.item_detail,caption,func(): absorb_from_bag(ui,i,id),Essences.can_manage(session) and member.hp > 0 and Essences.has(id) and tier < Essences.MAX_TIER)
			absorb.name = "BagAbsorb%d" % i
```

5. Replace `static func equip_from_bag(...)` with:

```gdscript
static func absorb_from_bag(ui, member: int, id: String) -> void:
	var reason: String = ui.session.absorb_essence(member,id)
	if not reason.is_empty():
		ui.notice = reason; return
	ui.item_popup.hide(); ui.refresh(); show_supplies(ui)
```

Run: `grep -rn "equip_from_bag" expedition tests`
Expected: no output.

- [ ] **Step 6: Run the test to verify it passes**

Run: `godot --headless --path . --script res://tests/essence_ui.gd`
Expected: `Essence UI: 20 checks, 0 failures` and exit 0.

- [ ] **Step 7: Commit**

```bash
git add expedition/ui/screens/essence_tab.gd tests/essence_ui.gd
git commit -m "Add the 이능 tab: slot grid, 흡수, sets and caster spells

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/ui/screens/essence_tab.gd expedition/ui/screens/character_folio.gd expedition/ui/screens/popups.gd tests/essence_ui.gd
```

---

### Task 2: Numeric stat sheet with source breakdowns

**Files:**
- Modify: `expedition/ui/screens/character_folio.gd` (`status`, new `sheet_cards`, `breakdown`)
- Test: `tests/stat_sheet_ui.gd`

**Interfaces:**
- Consumes: `StatSheet.sheet(s, actor)`, `StatSheet.NAMES`, `CharacterUI.detail(ui, title, message)` (existing).
- Produces: `CharacterUI.STAT_GROUPS`, `CharacterUI.sheet_cards(ui, list, actor) -> void`, `CharacterUI.breakdown(entry: Dictionary, key: String) -> String`. Node names: `StatGroup_능력치`, `StatGroup_방어 수치`, `StatGroup_속성 저항` (PanelContainer), `Stat_<key>` (Button).

- [ ] **Step 1: Write the failing test**

Create `tests/stat_sheet_ui.gd`:

```gdscript
extends SceneTree
## §4 캐릭터 화면: every stat as a number, and a tap that says where it came from.
const Session = preload("res://expedition/run/session.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(4): await process_frame
	s.phase = "CAMP"
	var hero: Dictionary = s.party[0]
	s.parts_bag["ORC_CLEAVER"] = 1
	check(s.absorb_essence(0,"ORC_CLEAVER").is_empty() and s.equip_part(0,0,"ORC_CLEAVER"),"an orc essence is worn")
	scene.show_character(0,"상태")
	for _i in range(4): await process_frame
	for group in ["능력치","방어 수치","속성 저항"]:
		check(scene.modal_content.find_child("StatGroup_"+group,true,false) != null,"the status tab has the %s card" % group)
	var sheet: Dictionary = StatSheet.sheet(s,hero)
	for key in StatSheet.KEYS:
		var cell: Button = scene.modal_content.find_child("Stat_"+key,true,false)
		check(cell != null,"a button for "+key)
		if cell == null: continue
		var shown: String = ("%d%%" if key.begins_with("res_") else "%d") % int(sheet[key].total)
		check(cell.text.ends_with(shown),"%s shows its total %s" % [key,shown])
	var strength: Button = scene.modal_content.find_child("Stat_str",true,false)
	strength.pressed.emit()
	for _i in range(3): await process_frame
	var lines: Array = scene.item_detail.find_children("*","Label",true,false).map(func(l): return l.text)
	check(lines.any(func(t): return t.contains("합계  %d" % int(sheet.str.total))),"the breakdown ends in the total")
	check(lines.any(func(t): return t.contains("+2")),"the orc essence's +2 is listed as its own line")
	check(CharacterUI.breakdown({"total":0,"parts":[]},"res_fire") == "기본값 없음\n합계  0%","an empty resistance still says its total")
	check(not scene.modal_content.find_children("*","Label",true,false).any(func(l): return l.text.contains("숙련")),"no mastery on the status tab")
	scene.item_popup.hide(); scene.queue_free(); await process_frame
	print("Stat sheet UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/stat_sheet_ui.gd`
Expected: FAIL, `the status tab has the 능력치 card` and the `Stat_*` checks fail.

- [ ] **Step 3: Implement**

In `character_folio.gd` add after the preloads:

```gdscript
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const STAT_GROUPS := [["능력치",["str","dex","int","con"]],["방어 수치",["ac","ev","sh"]],["속성 저항",["res_fire","res_ice","res_air","res_poison","res_will"]]]
```

In `status`, manual branch, replace the four lines from `var values: Dictionary = CombatStats.stats(ui.session,actor)` through the `for entry in [...]` loop body with:

```gdscript
		var values: Dictionary = CombatStats.stats(ui.session,actor)
		var combat := card(list,"전투")
		var stats := grid(combat,2)
		for entry in [["피해",values.damage],["공격 시간",values.delay]]:
			var stat := card(stats,str(entry[0])); text(stat,str(entry[1]),20)
		sheet_cards(ui,list,actor)
```

Add below `status`:

```gdscript
## The twelve numbers of §2, grouped; a tap opens where each one came from.
static func sheet_cards(ui, list: VBoxContainer, actor: Dictionary) -> void:
	var sheet: Dictionary = StatSheet.sheet(ui.session,actor)
	for group in STAT_GROUPS:
		var keys: Array = group[1]
		var box := card(list,str(group[0])); box.get_parent().name = "StatGroup_"+str(group[0])
		var cells := grid(box,keys.size())
		for key in keys:
			var entry: Dictionary = sheet.get(key,{"total":0,"parts":[]})
			var shown: String = ("%d%%" if str(key).begins_with("res_") else "%d") % int(entry.total)
			var cell = ui.button(cells,"%s\n%s" % [StatSheet.NAMES[key],shown],func(): detail(ui,str(StatSheet.NAMES[key]),breakdown(entry,str(key))))
			cell.name = "Stat_"+str(key); cell.custom_minimum_size = Vector2(0,52)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.add_theme_font_size_override("font_size",12)

## "종족  +12 / 이능 오크  +2 / 합계  14": one line per non-zero source.
static func breakdown(entry: Dictionary, key: String) -> String:
	var unit: String = "%" if key.begins_with("res_") else ""
	var lines: Array = []
	for part in entry.get("parts",[]):
		if int(part.value) != 0: lines.append("%s  %+d%s" % [str(part.from),int(part.value),unit])
	if lines.is_empty(): lines.append("기본값 없음")
	lines.append("합계  %d%s" % [int(entry.get("total",0)),unit])
	return "\n".join(lines)
```

`detail` splits the message into one Label; the test reads its text with `contains`, so the single Label holding all lines passes.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/stat_sheet_ui.gd`
Expected: `Stat sheet UI: 32 checks, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add tests/stat_sheet_ui.gd
git commit -m "Show all twelve stats on the status tab with their sources

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/ui/screens/character_folio.gd tests/stat_sheet_ui.gd
```

---

### Task 3: Level-up and essence banners

**Files:**
- Create: `expedition/ui/screens/banners.gd`
- Modify: `expedition/ui/main.gd` (preload, `show_banners`, call from `refresh`)
- Test: `tests/banners.gd`

**Interfaces:**
- Consumes: `session.events` entries `{"kind":"LEVEL_UP","actor":id,"level":n}` and `{"kind":"ESSENCE","id":id,"new":bool}`; `EssenceTab.tag_line/stat_line/active_line/border_for`.
- Produces: `Banners.show_next(ui) -> bool`, `Banners.showing(ui) -> bool`; `main.show_banners() -> void`. Node names: `LevelUpBanner`, `EssenceBanner` (PanelContainer, direct children of `main`), `BannerOk` (Button), `BannerSlotLine`, `BannerUpgrade` (Label).

- [ ] **Step 1: Write the failing test**

Create `tests/banners.gd`:

```gdscript
extends SceneTree
## §4 알림: a level gained and an essence found each get a big centre banner,
## one at a time, tapped away.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Banners = preload("res://expedition/ui/screens/banners.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func frames(n: int) -> void:
	for _i in range(n): await process_frame

func labels(node: Node) -> Array:
	return node.find_children("*","Label",true,false).map(func(l): return l.text)

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await frames(4)
	s.events.clear()
	var hero: Dictionary = s.party[0]
	check(s.gain_level_xp(hero,65) == 1,"one level gained")
	s.events.append({"kind":"ESSENCE","id":"GOBLIN_SHIV@fire","new":true})
	s.parts_bag["RAT_GNAW"] = 1
	s.phase = "CAMP"
	check(s.absorb_essence(0,"RAT_GNAW").is_empty(),"the hero already has the rat essence")
	s.events.append({"kind":"ESSENCE","id":"RAT_GNAW","new":false})
	scene.refresh(); await frames(3)
	var level: Node = scene.get_node_or_null("LevelUpBanner")
	check(level != null,"refresh shows the level-up banner first")
	check(level != null and labels(level).has("레벨 2"),"the banner names the new level")
	check(level != null and level.find_child("BannerSlotLine",true,false).text == "이능 슬롯 +1","and the slot it opened")
	var rect: Rect2 = level.get_global_rect()
	check(absf(rect.get_center().x-195) <= 2 and absf(rect.get_center().y-422) <= 2,"the banner sits in the centre")
	check(scene.get_node_or_null("EssenceBanner") == null,"one banner at a time")
	level.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	var found: Node = scene.get_node_or_null("EssenceBanner")
	check(found != null and scene.get_node_or_null("LevelUpBanner") == null,"tapping it brings the next one")
	check(found != null and labels(found).has("새 이능"),"a new essence says so")
	check(found != null and labels(found).has(EssenceTab.tag_line("GOBLIN_SHIV@fire")),"both tags are shown")
	var skin: StyleBoxFlat = found.get_theme_stylebox("panel")
	check(skin.border_color == EssenceTab.ELEMENT_COLORS.fire,"a fire variant has a fire border")
	found.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	var again: Node = scene.get_node_or_null("EssenceBanner")
	check(again != null and again.find_child("BannerUpgrade",true,false) != null,"an essence someone holds offers a tier up")
	check(again != null and again.find_child("BannerUpgrade",true,false).text.contains(str(hero.name)),"naming who can take it")
	again.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	check(not Banners.showing(scene) and not s.events.any(func(e): return str(e.kind) in ["LEVEL_UP","ESSENCE"]),"the queue is drained")
	s.events.append({"kind":"LEVEL_UP","actor":999,"level":3})
	check(not Banners.show_next(scene) and s.events.is_empty(),"a level-up of someone outside the party is dropped silently")
	scene.queue_free(); await process_frame
	print("Banners: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/banners.gd`
Expected: FAIL with a parse error: `Could not resolve ... banners.gd`.

- [ ] **Step 3: Create `expedition/ui/screens/banners.gd`**

```gdscript
extends RefCounted
## §4 알림: the big centre banners — a level gained, an essence found. They
## come from `session.events`, one at a time, and a tap on 확인 brings the next.
const Essences = preload("res://expedition/progression/essences.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
const KINDS := ["LEVEL_UP","ESSENCE"]
const NODES := ["LevelUpBanner","EssenceBanner"]
const GOLD := Color("c6a34c")

static func showing(ui) -> bool:
	return NODES.any(func(n): return ui.has_node(n))

static func member(s, id: int) -> Dictionary:
	for actor in s.party:
		if int(actor.id) == id: return actor
	return {}

## Pops the next banner-worthy event and shows it; false when nothing shows.
static func show_next(ui) -> bool:
	if ui.session == null or showing(ui): return false
	if is_instance_valid(ui.board) and ui.board.is_presenting(): return false
	while true:
		var at: int = ui.session.events.find_custom(func(e): return str(e.get("kind","")) in KINDS)
		if at < 0: return false
		var event: Dictionary = ui.session.events.pop_at(at)
		if str(event.kind) == "LEVEL_UP":
			var actor: Dictionary = member(ui.session,int(event.get("actor",-1)))
			if actor.is_empty(): continue
			level_banner(ui,actor,int(event.get("level",1)))
			return true
		essence_banner(ui,str(event.get("id","")),bool(event.get("new",true)))
		return true
	return false

static func frame(ui, node_name: String, border: Color) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.name = node_name; panel.z_index = 50
	var skin := StyleBoxFlat.new(); skin.bg_color = Color(0.07,0.06,0.05,0.97); skin.border_color = border
	skin.set_border_width_all(4); skin.set_corner_radius_all(10); skin.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel",skin)
	panel.custom_minimum_size = Vector2(minf(340.0,ui.size.x-32.0),0)
	ui.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation",8); panel.add_child(box)
	return box

static func line(box: VBoxContainer, value: String, font_size: int, color: Color = Color("e0d4bc")) -> Label:
	var label := Label.new(); label.text = value; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",color)
	box.add_child(label); return label

## 확인 closes this banner and asks for the next; the panel leaves the tree at
## once so `showing` is false before the next one is built.
static func finish(ui, box: VBoxContainer) -> void:
	var panel: PanelContainer = box.get_parent()
	var ok := Button.new(); ok.name = "BannerOk"; ok.text = "확인"; ok.custom_minimum_size.y = 48
	ok.add_theme_font_size_override("font_size",20)
	ok.pressed.connect(func():
		ui.remove_child(panel); panel.queue_free(); show_next(ui))
	box.add_child(ok)
	panel.reset_size()
	panel.position = ((ui.size-panel.get_combined_minimum_size())/2).floor()

static func level_banner(ui, actor: Dictionary, level: int) -> void:
	var box := frame(ui,"LevelUpBanner",GOLD)
	line(box,"레벨 %d" % level,36,Color("ffe0a3"))
	line(box,str(actor.name),18)
	line(box,"HP +4 · MP +2",16)
	if level <= Essences.MAX_LEVEL: line(box,"이능 슬롯 +1",22,GOLD).name = "BannerSlotLine"
	finish(ui,box)

static func essence_banner(ui, id: String, is_new: bool) -> void:
	var box := frame(ui,"EssenceBanner",EssenceTab.border_for(id,GOLD))
	line(box,"새 이능" if is_new else "이능 획득",16,GOLD)
	line(box,Essences.title(id),28,Color("ffe0a3"))
	var tags: String = EssenceTab.tag_line(id)
	if not tags.is_empty(): line(box,tags,16)
	line(box,EssenceTab.stat_line(id,1),15)
	line(box,EssenceTab.active_line(id),14)
	var owners: Array = ui.session.party.filter(func(a): return Essences.tier(a,id) > 0 and Essences.tier(a,id) < Essences.MAX_TIER).map(func(a): return str(a.name))
	if not owners.is_empty(): line(box,"단계 상승 가능 · "+", ".join(owners),16,GOLD).name = "BannerUpgrade"
	finish(ui,box)
```

- [ ] **Step 4: Hook the banners into `main.gd`**

Add after `const Art = ...`:

```gdscript
const Banners = preload("res://expedition/ui/screens/banners.gd")
```

In `refresh()`, add as the second line, right after `if is_instance_valid(board) and board.is_presenting(): return`:

```gdscript
	call_deferred("show_banners")
```

Add next to the other one-line routers at the end of the file:

```gdscript
func show_banners() -> void: Banners.show_next(self)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/banners.gd`
Expected: `Banners: 15 checks, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add expedition/ui/screens/banners.gd tests/banners.gd
git commit -m "Show level-up and essence banners from session events

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/ui/screens/banners.gd expedition/ui/main.gd tests/banners.gd
```

---

### Task 4: Monster inspection and the NPC line

**Files:**
- Modify: `expedition/ui/screens/popups.gd` (`show_enemy_info`, `show_npc`)
- Test: `tests/inspect_ui.gd`

**Interfaces:**
- Consumes: `StatSheet.sheet`, `Essences.has/title/equipped`, `EssenceTab.tag_line/active_line`; the existing long-press path `board.cell_inspected → main.inspect_cell → Popups.inspect_cell → show_enemy_info`.
- Produces: labels `EnemyDefence`, `EnemyResist` (only when a resistance is non-zero), `EnemyEssence` in the enemy popup; `NpcLevel` in the NPC popup.

- [ ] **Step 1: Write the failing test**

Create `tests/inspect_ui.gd`:

```gdscript
extends SceneTree
## §2.4 and §4: a long press on a monster shows its stats and essence; the npc
## popup shows level and worn essences instead of a mastery.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func label(scene, node_name: String) -> Label:
	return scene.modal_content.find_child(node_name,true,false)

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(4): await process_frame
	var foe: Dictionary = s.enemies.filter(func(e): return Essences.has(str(e.get("part_id",""))))[0]
	var hero: Dictionary = s.party[0]
	var cell: Vector2i = hero.pos+Vector2i(1,0)
	if not s.is_free(cell): cell = hero.pos+Vector2i(0,1)
	foe.pos = cell; foe.res = {"fire":25}
	s.floor_state.observe(s)
	check(s.floor_state.visible.has(cell),"the monster stands in sight")
	scene.inspect_cell(cell)
	for _i in range(3): await process_frame
	check(scene.details_popup.visible and label(scene,"EnemyInfo") != null,"a long press opens the monster's card")
	var sheet: Dictionary = StatSheet.sheet(s,foe)
	check(label(scene,"EnemyDefence") != null and label(scene,"EnemyDefence").text == "방어 %d   회피 %d   막기 %d" % [int(sheet.ac.total),int(sheet.ev.total),int(sheet.sh.total)],"defence numbers from the stat sheet")
	check(label(scene,"EnemyResist") != null and label(scene,"EnemyResist").text.contains("%d%%" % int(sheet.res_fire.total)),"its resistance is listed")
	check(label(scene,"EnemyEssence") != null and label(scene,"EnemyEssence").text == "이능 · "+Essences.title(str(foe.part_id)),"its essence is named")
	scene.details_popup.hide()
	foe.res = {}
	scene.inspect_cell(cell)
	for _i in range(3): await process_frame
	check(label(scene,"EnemyResist") == null,"no resistance line when every resistance is zero")
	scene.details_popup.hide()
	var npc: Dictionary = s.roster[0]
	npc.essences = {"ORC_CLEAVER":1}; npc.equipped_abilities = ["ORC_CLEAVER"]
	scene.Popups.show_npc(scene,npc)
	for _i in range(3): await process_frame
	check(label(scene,"NpcLevel") != null and label(scene,"NpcLevel").text == "Lv.%d · 이능 %s" % [int(npc.level),Essences.title("ORC_CLEAVER")],"the npc line shows level and essences")
	scene.details_popup.hide(); scene.queue_free(); await process_frame
	print("Inspect UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/inspect_ui.gd`
Expected: FAIL on `defence numbers from the stat sheet` and the checks after it.

- [ ] **Step 3: Implement in `popups.gd`**

In `show_enemy_info`, insert directly after the line that shows `"HP %d/%d   AC %d ..."`:

```gdscript
	var sheet: Dictionary = StatSheet.sheet(session,enemy)
	var defence = ui.label(ui.modal_content,"방어 %d   회피 %d   막기 %d" % [int(sheet.ac.total),int(sheet.ev.total),int(sheet.sh.total)],14)
	defence.name = "EnemyDefence"
	var resists: Array = []
	for key in ["res_fire","res_ice","res_air","res_poison","res_will"]:
		if int(sheet[key].total) != 0: resists.append("%s %d%%" % [StatSheet.NAMES[key],int(sheet[key].total)])
	if not resists.is_empty():
		var resist = ui.label(ui.modal_content,"저항  "+"  ".join(resists),13)
		resist.name = "EnemyResist"
	var essence: String = str(enemy.get("part_id",""))
	if Essences.has(essence):
		var named = ui.label(ui.modal_content,"이능 · "+Essences.title(essence),15)
		named.name = "EnemyEssence"
		if not EssenceTab.tag_line(essence).is_empty(): ui.label(ui.modal_content,EssenceTab.tag_line(essence),13)
		var words = ui.label(ui.modal_content,EssenceTab.active_line(essence),13)
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; words.custom_minimum_size.x = ui.popup_width()
```

In `show_npc`, replace the level line Plan 1 left (the `ui.label(words,"Lv.%d" ...)` line and any `axis` line before it) with:

```gdscript
	var worn: Array = Essences.equipped(npc).map(func(id): return Essences.title(str(id)))
	var level_line = ui.label(words,"Lv.%d · 이능 %s" % [int(npc.get("level",1)),", ".join(worn) if not worn.is_empty() else "없음"],13)
	level_line.name = "NpcLevel"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/inspect_ui.gd`
Expected: `Inspect UI: 7 checks, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add tests/inspect_ui.gd
git commit -m "Show monster stats and essence on long press; npc level line

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/ui/screens/popups.gd tests/inspect_ui.gd
```

---

### Task 5: NPC essence choice and NPC hunts

**Files:**
- Create: `expedition/actors/npc_essences.gd`
- Modify: `expedition/run/session.gd` (preload; one call in the kill block of `after_damage`)
- Test: `tests/npc_essences.gd`

**Interfaces:**
- Consumes: `Essences.role/element/tier/slot_count/sync_slots/equip/unequip/has/school/spell_choices/choose_spell/sync_spells/MAX_TIER`, `StatSheet.refresh_pools`, `Hexaco.sample`.
- Produces: `NpcEssences.preference(npc, id) -> int`, `NpcEssences.continuing(picked: Array, id: String) -> int`, `NpcEssences.choose(s, npc) -> void`, `NpcEssences.on_hunt(s, enemy, hunters: Array) -> void`, `NpcEssences.DROP_PERCENT` (25), `NpcEssences.SET_BONUS` (300). Actor field `essence_seen: {species_id: true}` on NPCs.

- [ ] **Step 1: Write the failing test**

Create `tests/npc_essences.gd`:

```gdscript
extends SceneTree
## §3.9: strangers pick essences by personality, keep a set going, earn their
## own essences from their own kills and bring them along when recruited.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const NpcEssences = preload("res://expedition/actors/npc_essences.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func stranger(s, index: int, facets: Dictionary, essences: Dictionary, level: int) -> Dictionary:
	var npc: Dictionary = s.roster[index]
	npc.profile = Hexaco.new(facets)
	npc.level = level; npc.essences = essences.duplicate(); npc.essence_spells = {}; npc.essence_seen = {}
	npc.equipped_abilities = []
	Essences.sync_slots(npc)
	return npc

func run() -> void:
	var s = Session.new_run(731)
	var caster: String = str(Essences.CASTER_BY_SCHOOL.fire)
	var pool := {"ORC_CLEAVER":1,"HOB_CLUB":1,"RAT_GNAW":1,caster:1}
	var blunt: Dictionary = stranger(s,0,{"A":100,"C":500,"O":500},pool,1)
	NpcEssences.choose(s,blunt)
	check(blunt.equipped_abilities == ["ORC_CLEAVER"],"low agreeableness wears the berserker")
	var careful: Dictionary = stranger(s,1,{"A":900,"C":950,"O":100},pool,1)
	NpcEssences.choose(s,careful)
	check(careful.equipped_abilities == ["HOB_CLUB"],"high conscientiousness wears the guard")
	var curious: Dictionary = stranger(s,2,{"A":900,"C":100,"O":950},pool,1)
	NpcEssences.choose(s,curious)
	check(curious.equipped_abilities == [caster],"high openness wears the caster")
	check(not str(curious.essence_spells.get(caster,"")).is_empty(),"and picks a spell for it")
	var pack: Dictionary = stranger(s,3,{"A":100,"C":500,"O":500},{"ORC_CLEAVER":1,"GNOLL_SPEAR":1,"GOBLIN_SHIV":1},2)
	NpcEssences.choose(s,pack)
	check(pack.equipped_abilities == ["GNOLL_SPEAR","ORC_CLEAVER"],"a second berserker keeps the set going over an equal ambusher")
	check(NpcEssences.continuing(["GNOLL_SPEAR"],"ORC_CLEAVER") == 1 and NpcEssences.continuing(["GNOLL_SPEAR"],"GOBLIN_SHIV") == 0,"continuation counts shared tags")
	# Its own hunt.
	var hunter: Dictionary = stranger(s,4,{"A":500,"C":500,"O":500},{},1)
	var foe: Dictionary = s.enemies.filter(func(e): return Essences.has(str(e.get("part_id",""))))[0]
	var bag: Dictionary = s.parts_bag.duplicate(true)
	NpcEssences.on_hunt(s,foe,[hunter])
	check(Essences.tier(hunter,str(foe.part_id)) == 1,"the first kill of a species gives the npc its essence")
	check(hunter.equipped_abilities[0] == str(foe.part_id),"and it wears it at once")
	check(hunter.essence_seen.has(str(foe.species_id)),"the species is remembered")
	check(s.parts_bag == bag,"the party bag is untouched")
	var hero_before: Dictionary = s.party[0].get("essences",{}).duplicate()
	NpcEssences.on_hunt(s,foe,[s.party[0]])
	check(s.party[0].get("essences",{}) == hero_before,"party members take nothing through this path")
	# The session's kill path calls it.
	var other: Dictionary = stranger(s,5,{"A":500,"C":500,"O":500},{},1)
	var second: Dictionary = s.enemies.filter(func(e): return e.hp > 0 and e.id != foe.id and Essences.has(str(e.get("part_id",""))))[0]
	other.hp = other.max_hp; other.state = "MET"; other.pos = second.pos+Vector2i(1,0)
	s.npcs.append(other)
	s.damage(second,9999,int(other.id),"SLASH")
	check(second.hp <= 0 and Essences.tier(other,str(second.part_id)) == 1,"an npc's own kill in play gives it the essence")
	check(s.parts_bag == bag,"still nothing for the party")
	# Recruited, it keeps them.
	var kept: Dictionary = other.essences.duplicate(); var worn: Array = other.equipped_abilities.duplicate()
	s.Recruit.join(s,other)
	check(s.party[-1].essences == kept and s.party[-1].equipped_abilities == worn,"recruiting keeps the essences and the loadout")
	print("NPC essences: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/npc_essences.gd`
Expected: FAIL with a parse error: `Could not resolve ... npc_essences.gd`.

- [ ] **Step 3: Create `expedition/actors/npc_essences.gd`**

```gdscript
extends RefCounted
## §3.9: how a stranger picks the essences it wears, and what it takes from its
## own hunts. Party members are the player's to dress; nothing here touches them.
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const DROP_PERCENT := 25
const SET_BONUS := 300
const PLAIN := 300

## Low A leans to 광폭·기습, high C to 수호, high O to 술사; the tier counts too.
static func preference(npc: Dictionary, id: String) -> int:
	var profile = npc.profile
	var score: int = 100*Essences.tier(npc,id)
	match str(Essences.role(id)):
		"BERSERK", "AMBUSH": score += 1000-int(profile.value("A"))
		"GUARD": score += int(profile.value("C"))
		"CASTER": score += int(profile.value("O"))
		_: score += PLAIN
	return score

## How many already chosen essences share a role or an element with `id`.
static func continuing(picked: Array, id: String) -> int:
	var count := 0
	for other in picked:
		var same_role: bool = not str(Essences.role(id)).is_empty() and Essences.role(id) == Essences.role(str(other))
		var same_element: bool = not str(Essences.element(id)).is_empty() and Essences.element(id) == Essences.element(str(other))
		if same_role or same_element: count += 1
	return count

## Greedy loadout: each slot takes the best-scoring essence left, scored with a
## bonus for every chosen essence it would make a set with. Ties go to the id.
static func choose(s, npc: Dictionary) -> void:
	Essences.sync_slots(npc)
	var count: int = Essences.slot_count(npc)
	var pool: Array = npc.get("essences",{}).keys()
	var picked: Array = []
	while picked.size() < mini(count,pool.size()):
		var best := ""; var best_score := -(1 << 30)
		for entry in pool:
			var id: String = str(entry)
			if id in picked: continue
			var score: int = preference(npc,id)+SET_BONUS*continuing(picked,id)
			if score > best_score or (score == best_score and id < best): best = id; best_score = score
		picked.append(best)
	for slot in range(count):
		if not str(npc.equipped_abilities[slot]).is_empty(): Essences.take(npc,slot)
	for slot in range(picked.size()):
		var id: String = picked[slot]
		Essences.put(npc,slot,id)
		if not str(Essences.school(id)).is_empty() and str(npc.get("essence_spells",{}).get(id,"")).is_empty():
			var choices: Array = Essences.spell_choices(npc,id)
			if not choices.is_empty(): npc.get_or_add("essence_spells",{})[id] = str(choices[choices.size()-1])
	Essences.sync_spells(npc)
	StatSheet.refresh_pools(s,npc)

## An independent NPC's own kill: the first of a species always gives its
## essence, later ones one time in four; then the loadout is chosen again.
static func on_hunt(s, enemy: Dictionary, hunters: Array) -> void:
	var id: String = str(enemy.get("part_id",""))
	if not Essences.has(id): return
	for npc in hunters:
		if npc in s.party or not bool(npc.get("npc",false)) or int(npc.hp) <= 0: continue
		var seen: Dictionary = npc.get_or_add("essence_seen",{})
		var species: String = str(enemy.get("species_id",""))
		if seen.has(species) and Hexaco.sample(s.seed_value,int(s.depth)*100000+int(enemy.id)*100+int(npc.id)%100,"npc_essence",100) >= DROP_PERCENT: continue
		seen[species] = true
		var tier: int = Essences.tier(npc,id)
		if tier >= Essences.MAX_TIER: continue
		npc.get_or_add("essences",{})[id] = tier+1
		choose(s,npc)
```

- [ ] **Step 4: Call it from the session's kill path**

In `expedition/run/session.gd`, add with the other preloads:

```gdscript
const NpcEssences = preload("res://expedition/actors/npc_essences.gd")
```

In `after_damage`, inside `if target.enemy and target.hp <= 0:`, add as the last statement of that block (after the `if target.get("boss",false): ... else: roll_part(target,hunters)` lines):

```gdscript
		NpcEssences.on_hunt(self,target,hunters)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/npc_essences.gd`
Expected: `NPC essences: 14 checks, 0 failures`.

Run the NPC suites that share the kill path:
Run: `for t in npc_progression npc_roster npc_behaviour npc_hostility recruit; do godot --headless --path . --script res://tests/$t.gd >/dev/null 2>&1 || echo FAIL $t; done`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add expedition/actors/npc_essences.gd tests/npc_essences.gd
git commit -m "Let npcs choose essences by personality and take them from their own kills

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/actors/npc_essences.gd expedition/run/session.gd tests/npc_essences.gd
```

---

### Task 6: Difficulty gate

**Files:**
- Modify: `expedition/sim/model_b_runner.gd` (extract `hero_turn`)
- Create: `expedition/sim/difficulty_gate.gd`
- Create: `tests/difficulty_gate.gd` (manual gate; writes `docs/balance/difficulty-gate.json` and `.md`)

**Interfaces:**
- Consumes: `Session.new_run(seed, kit)`, `s.floor_state.build(s)`, `s.gain_level_xp`, `s.absorb_essence`, `s.equip_part`, `Essences.has/slot_count/MAX_TIER`, `Session.CombatStats.content.kill_xp`.
- Produces: `Runner.hero_turn(s) -> void`; `Gate.baseline(seed: int, kit: String, depth: int, share: int = 100) -> Dictionary` (`{"xp":int,"essences":{id:count}}`), `Gate.prepare(seed, kit, depth, share = 100)` → session, `Gate.run_floor(s) -> Dictionary` (`{"fights":[{"group","members","result","hp_lost","hp_lost_percent"}],"mean_loss_percent":float,"camp_needed":bool,"wins":int}`), `Gate.FIGHT_LIMIT` (120).

- [ ] **Step 1: Extract the hero's turn in `model_b_runner.gd`**

Replace the loop body lines in `run_one` from `var hero: Dictionary = s.party[0]` through `if not s.submit(kind,target): s.submit("WAIT",hero.pos)` with one call:

```gdscript
		hero_turn(s)
```

and add the function below `run_one`:

```gdscript
## One hero action the way a player would take it: the tactical choice, or a
## step toward the nearest monster when nothing is in reach.
static func hero_turn(s) -> void:
	var hero: Dictionary = s.party[0]
	hero.ap = 1
	var choice: Dictionary = Tactics.choose(s,hero)
	var kind: String = str(choice.get("kind","WAIT"))
	var target: Vector2i = choice.get("cell",hero.pos)
	if kind == "WAIT" and s.party_enemies().is_empty():
		var goals: Array = []
		for enemy in s.enemies:
			if enemy.hp <= 0: continue
			for direction in s.DIRECTIONS:
				var cell: Vector2i = enemy.pos+direction
				if s.is_free(cell) and s.melee_reach(cell,enemy.pos): goals.append(cell)
		if not goals.is_empty():
			var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,hero.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100)
			if route.found and route.path.size() > 1: kind = "MOVE"; target = route.path[1]
	if not s.submit(kind,target): s.submit("WAIT",hero.pos)
```

Run: `godot --headless --path . --script res://tests/model_b_runner.gd`
Expected: `Model B runner: 0 failures` (the extraction changes nothing).

- [ ] **Step 2: Write the gate test**

Create `tests/difficulty_gate.gd`:

```gdscript
extends SceneTree
## §5 난이도 게이트 (manual): the hero who cleared floors 1..N−1 fights each
## pack of floor N from full HP. Writes docs/balance/difficulty-gate.{json,md}.
## Not part of the regular suite loop: it builds dozens of floors.
const Gate = preload("res://expedition/sim/difficulty_gate.gd")
const DEPTHS := [2,3,4,5]
const KITS := ["sword","fire"]
const SEEDS := [100,101,102]
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var first: Dictionary = Gate.run_floor(Gate.prepare(100,"sword",2))
	check(first == Gate.run_floor(Gate.prepare(100,"sword",2)),"the same seed reproduces the whole floor")
	check(not first.fights.is_empty(),"floor two has packs to fight")
	check(first.fights.all(func(f): return f.result in ["WIN","DEFEAT","TIMEOUT"] and int(f.hp_lost_percent) >= 0 and int(f.hp_lost_percent) <= 100),"every fight is accounted for")
	var base: Dictionary = Gate.baseline(100,"sword",3)
	var half: Dictionary = Gate.baseline(100,"sword",3,50)
	check(int(base.xp) > 0 and int(half.xp) == int(base.xp)/2,"half a clear is half the kill XP")
	var rows: Array = []
	for depth in DEPTHS:
		for kit in KITS:
			for share in [100,50]:
				var losses: Array = []; var camps := 0; var wins := 0; var fights := 0
				for seed in SEEDS:
					var floor_row: Dictionary = Gate.run_floor(Gate.prepare(seed,kit,depth,share))
					losses.append(float(floor_row.mean_loss_percent))
					camps += 1 if floor_row.camp_needed else 0
					wins += int(floor_row.wins); fights += floor_row.fights.size()
				var mean: float = losses.reduce(func(a,b): return a+b,0.0)/maxf(1.0,losses.size())
				rows.append({"depth":depth,"kit":kit,"share":share,"mean_loss_percent":snappedf(mean,0.1),"camp_rate":float(camps)/SEEDS.size(),"win_rate":float(wins)/maxf(1.0,fights)})
	for row in rows:
		if row.share != 100: continue
		var halfway: Array = rows.filter(func(r): return r.depth == row.depth and r.kit == row.kit and r.share == 50)
		check(not halfway.is_empty() and float(halfway[0].mean_loss_percent) >= float(row.mean_loss_percent),"%d층 %s: half a clear never hurts less" % [row.depth,row.kit])
	write(rows)
	print("Difficulty gate: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func write(rows: Array) -> void:
	var json := FileAccess.open("res://docs/balance/difficulty-gate.json",FileAccess.WRITE)
	json.store_string(JSON.stringify({"seeds":SEEDS,"rows":rows},"  ")); json.close()
	var lines: Array = ["# 난이도 게이트","","`tests/difficulty_gate.gd`가 쓴다. 기준 주인공(1~N−1층을 모두 잡은 레벨과 이능)과 절반만 잡은 주인공이 N층 무리를 하나씩, 매번 HP를 채우고 싸운 결과다. 합격선: 기준 주인공의 전투당 HP 손실 25~40%, 야영 필요, 절반 주인공은 뚜렷하게 더 잃음.","","| 층 | 킷 | 기준 | 전투당 HP 손실 | 야영 필요 비율 | 승률 | 합격선 |","| --- | --- | --- | --- | --- | --- | --- |"]
	for row in rows:
		var verdict: String = "—" if row.share != 100 else ("통과" if float(row.mean_loss_percent) >= 25.0 and float(row.mean_loss_percent) <= 40.0 and float(row.camp_rate) > 0.0 else "조정 필요")
		lines.append("| %d | %s | %s | %.1f%% | %.0f%% | %.0f%% | %s |" % [int(row.depth),str(row.kit),"다 잡음" if row.share == 100 else "절반",float(row.mean_loss_percent),float(row.camp_rate)*100.0,float(row.win_rate)*100.0,verdict])
	var md := FileAccess.open("res://docs/balance/difficulty-gate.md",FileAccess.WRITE)
	md.store_string("\n".join(lines)+"\n"); md.close()
```

- [ ] **Step 3: Run it to verify it fails**

Run: `godot --headless --path . --script res://tests/difficulty_gate.gd`
Expected: FAIL with a parse error: `Could not resolve ... difficulty_gate.gd`.

- [ ] **Step 4: Create `expedition/sim/difficulty_gate.gd`**

```gdscript
extends RefCounted
## §5 difficulty gate: floor N measured against the hero who cleared floors
## 1..N−1 (all of their kill XP and the essences those kills would drop), or a
## share of that clear. Packs are fought one at a time from full HP.
const Session = preload("res://expedition/run/session.gd")
const Runner = preload("res://expedition/sim/model_b_runner.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const FIGHT_LIMIT := 120

## Kill XP and essence drops of floors 1..depth−1 for this seed, scaled by
## `share` percent: a half clear takes half the kills of every species.
static func baseline(seed: int, kit: String, depth: int, share: int = 100) -> Dictionary:
	var s = Session.new_run(seed,kit)
	var rules: Dictionary = Session.CombatStats.content.kill_xp
	var xp := 0
	var kills: Dictionary = {}
	for d in range(1,depth):
		s.depth = d; s.floor_state.build(s)
		for enemy in s.enemies:
			xp += int(rules.base)+d*int(rules.per_depth)
			var id: String = str(enemy.get("part_id",""))
			if Essences.has(id): kills[id] = int(kills.get(id,0))+1
	var drops: Dictionary = {}
	for id in kills:
		var taken: int = int(kills[id])*share/100
		if taken > 0: drops[id] = taken
	return {"xp":xp*share/100,"essences":drops}

## A session on floor `depth` whose hero has the baseline's level and wears its
## most common essences, each absorbed once for the certain first kill and once
## more per four further kills (the 25% drop), up to the top tier.
static func prepare(seed: int, kit: String, depth: int, share: int = 100):
	var base: Dictionary = baseline(seed,kit,depth,share)
	var s = Session.new_run(seed,kit)
	s.depth = depth; s.floor_state.build(s)
	var hero: Dictionary = s.party[0]
	var phase: String = s.phase
	s.phase = "CAMP"
	s.gain_level_xp(hero,int(base.xp))
	var ids: Array = base.essences.keys()
	ids.sort_custom(func(a,b): return int(base.essences[a]) > int(base.essences[b]) or (int(base.essences[a]) == int(base.essences[b]) and str(a) < str(b)))
	for id in ids:
		var copies: int = mini(Essences.MAX_TIER,1+(int(base.essences[id])-1)/4)
		s.parts_bag[id] = int(s.parts_bag.get(id,0))+copies
		for _i in range(copies): s.absorb_essence(0,str(id))
	for id in ids:
		var free: int = hero.equipped_abilities.find("")
		if free < 0: break
		if str(id) not in hero.equipped_abilities: s.equip_part(0,free,str(id))
	s.phase = phase
	hero.hp = hero.max_hp; hero.mp = hero.max_mp
	s.events.clear()
	return s

## The nearest free cell two to five steps from `members[0]`, ring by ring.
static func stand_near(s, members: Array) -> bool:
	var hero: Dictionary = s.party[0]
	var target: Vector2i = members[0].pos
	for radius in range(2,6):
		for dy in range(-radius,radius+1):
			for dx in range(-radius,radius+1):
				var cell: Vector2i = target+Vector2i(dx,dy)
				if maxi(absi(dx),absi(dy)) != radius or not s.inside(cell) or not s.is_free(cell): continue
				hero.pos = cell
				return true
	return false

## Every pack of the floor, in group order, each fought alone from full HP.
## `camp_needed`: the losses of the whole floor add up to at least one full HP bar.
static func run_floor(s) -> Dictionary:
	var hero: Dictionary = s.party[0]
	var groups: Dictionary = {}
	for enemy in s.enemies: groups.get_or_add(str(enemy.get("group","")),[]).append(enemy)
	var names: Array = groups.keys()
	names.sort()
	var rows: Array = []
	var lost_total := 0; var wins := 0
	for group in names:
		var members: Array = groups[group]
		var others: Array = s.enemies.filter(func(e): return str(e.get("group","")) != group)
		s.enemies = members
		if not stand_near(s,members): s.enemies = others+members; continue
		hero.hp = hero.max_hp; hero.mp = hero.max_mp; hero.statuses = {}
		for id in hero.cooldowns: hero.cooldowns[id] = 0
		s.floor_state.observe(s)
		var result := "TIMEOUT"
		for _turn in range(FIGHT_LIMIT):
			if hero.hp <= 0 or s.phase == "DEFEAT": result = "DEFEAT"; break
			if members.all(func(e): return e.hp <= 0): result = "WIN"; break
			Runner.hero_turn(s)
		if result == "TIMEOUT" and members.all(func(e): return e.hp <= 0): result = "WIN"
		var lost: int = int(hero.max_hp)-maxi(0,int(hero.hp))
		rows.append({"group":group,"members":members.size(),"result":result,"hp_lost":lost,"hp_lost_percent":lost*100/maxi(1,int(hero.max_hp))})
		lost_total += lost
		if result == "WIN": wins += 1
		s.enemies = others+members
		if result == "DEFEAT": break
	var mean := 0.0
	for row in rows: mean += float(row.hp_lost_percent)
	return {"fights":rows,"mean_loss_percent":mean/maxf(1.0,rows.size()),"camp_needed":lost_total >= int(hero.max_hp),"wins":wins}
```

- [ ] **Step 5: Run the gate**

Run: `godot --headless --path . --script res://tests/difficulty_gate.gd`
Expected: `Difficulty gate: 12 checks, 0 failures`, and `docs/balance/difficulty-gate.json` and `docs/balance/difficulty-gate.md` exist.

Run: `sed -n 1,30p docs/balance/difficulty-gate.md`
Expected: a table with 16 rows. The 합격선 column is information for tuning. "조정 필요" rows are not a test failure; tuning is Plan 2's content work and later balance passes.

- [ ] **Step 6: Commit**

```bash
git add expedition/sim/difficulty_gate.gd tests/difficulty_gate.gd docs/balance/difficulty-gate.json docs/balance/difficulty-gate.md
git commit -m "Add the floor difficulty gate for the level-and-essence hero

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- expedition/sim/model_b_runner.gd expedition/sim/difficulty_gate.gd tests/difficulty_gate.gd docs/balance/difficulty-gate.json docs/balance/difficulty-gate.md
```

---

### Task 7: Existing suites follow the tab rename; full run

**Files:**
- Modify: `tests/character_ui.gd`, `tests/parts.gd`, `tests/abilities_growth.gd`, `tests/companion_tactics.gd`, `tests/continuous_floor.gd`, `tests/test_loadout.gd`, `tests/skill_rule_conditions.gd`

**Interfaces:**
- Consumes: node names and tab names from Task 1 (`EssenceSlots`, `EssenceSlot<n>`, `EssencePick_<id>`, heading `이능 슬롯 n / m`, tab `이능`).
- Produces: nothing new.

- [ ] **Step 1: Find every place that still names the old tab or its nodes**

Run: `grep -n "\"파츠 슬롯\|PartSlot\|CharacterUI.replace\|character_tab == \"파츠\"\|\"숙련\"\|\[\"상태\",\"성격\",\"기억\"" tests/*.gd`
Expected: a list of hits in the files above (Plan 1 already removed the `"숙련"` tab, so hits for `"숙련"` should be gone; if any remain, remove that tab name from the list it appears in).

- [ ] **Step 2: Apply the mechanical renames**

```bash
sed -i 's/character_tab == "파츠"/character_tab == "이능"/g; s/\["상태","성격","기억","파츠"\]/["상태","성격","기억","이능"]/g; s/\["상태","파츠"\]/["상태","이능"]/g' tests/character_ui.gd tests/companion_tactics.gd tests/continuous_floor.gd tests/abilities_growth.gd
```

- [ ] **Step 3: Rewrite the slot-card assertions by hand**

For each remaining hit from Step 1, replace the assertion with the new node model. The rules, one per old pattern:

| Old | New |
| --- | --- |
| `find_children("PartSlot*","PanelContainer",true,false).size() == N` | `find_child("EssenceSlots",true,false).get_child_count() == 10` |
| heading text `"파츠 슬롯 a / b"` | `"이능 슬롯 %d / %d" % [Essences.equipped(actor).size(),Essences.slot_count(actor)]` with `const Essences = preload("res://expedition/progression/essences.gd")` at the top of the file |
| `scene.CharacterUI.replace(scene,slot)` then a button by visible text | `preload("res://expedition/ui/screens/essence_tab.gd").chooser(scene,slot)` then `scene.item_detail.find_child("EssencePick_"+id,true,false)` |
| a `"장착"`/`"교체"`/`"해제"` button on a slot card | press `EssenceSlot<n>`; an empty slot opens the chooser, a filled one opens the detail with `EssenceUnequip` |

Each replaced assertion stays one `check(...)`, so the check counts do not drop.

- [ ] **Step 4: Run the whole suite**

Run:

```bash
for t in tests/*.gd; do case $t in *floor_fixture*|*difficulty_gate*) continue;; esac; godot --headless --path . --script res://$t >/dev/null 2>&1 || echo FAIL $t; done
```

Expected: no `FAIL` lines. If `ui_smoke` fails, check it on a clean worktree of the commit before this plan first; it has failed there before for reasons outside this work.

- [ ] **Step 5: Commit**

```bash
git commit -m "Point the folio suites at the 이능 tab

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" -- tests/character_ui.gd tests/parts.gd tests/abilities_growth.gd tests/companion_tactics.gd tests/continuous_floor.gd tests/test_loadout.gd tests/skill_rule_conditions.gd
```

---

## Self-review against the spec

| Spec requirement | Task |
| --- | --- |
| §4 레벨 업 배너, "이능 슬롯 +1" | 3 |
| §4 이능 획득 카드: 스탯·패시브·액티브·역할·속성, 변종 색 테두리, "단계 상승 가능" | 3 |
| §4 이능 화면: 격자 10칸(5×2), 가방 카드, 켜진 세트 | 1 |
| §3.3 교체는 안전할 때만 | 1 (buttons follow `Essences.can_manage`; the test checks battle refusal) |
| §3.5 주문 이능의 주문 선택 | 1 |
| §4 캐릭터 화면 12개 수치와 출처 | 2 |
| §2.4 몬스터 길게 누르면 스탯과 이능 | 4 |
| §3.9 NPC 성격별 선택, 세트 이어 가기, 자기 사냥 이능, 영입 시 유지 | 5 |
| §5 난이도 게이트, `docs/balance/` 기록, 절반 주인공 비교 | 6 |
| §7 기존 스위트는 검사 수를 줄이지 않고 고침 | 7 |
