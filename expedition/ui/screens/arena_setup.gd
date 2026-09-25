extends RefCounted
## The battle-test setup screen: an arena, a seed, a party size, and for every
## member a stance and two freely chosen parts. It only reads and writes
## `ui.arena_config` — the session is built when 시작 is pressed. The hero is manual.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
const Builder = preload("res://expedition/level/encounter_builder.gd")
const ROLES := ["MELEE","RANGED","CASTER"]
const ROLE_NAMES := {"MELEE":"근접","RANGED":"원거리","CASTER":"마법"}
const MEMBER_NAMES := ["아린","브란","세라"]

static func build(ui) -> Control:
	var root := VBoxContainer.new(); root.name = "ArenaSetup"
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation",4)
	ui.label(root,"전투 시험",20)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",4); scroll.add_child(list)
	arena_row(ui,list)
	seed_row(ui,list)
	if str(ui.arena_config.arena) == "custom": custom_row(ui,list)
	var probe = Session.new(int(ui.arena_config.seed),true,int(ui.arena_config.size) > 1,true,int(ui.arena_config.size))
	for i in range(int(ui.arena_config.size)): member_card(ui,list,i,probe.party[i])
	var buttons := HBoxContainer.new(); buttons.add_theme_constant_override("separation",4); root.add_child(buttons)
	var back = ui.button(buttons,"시작 화면",ui.leave_arena); back.name = "ArenaBack"
	# A hand-made arena with nobody in it is not a fight; the presets always are.
	var empty: bool = str(ui.arena_config.arena) == "custom" and ui.arena_config.custom.all(func(row): return str(row[0]).is_empty())
	var start = ui.button(buttons,"시작",ui.start_arena,not empty); start.name = "ArenaStart"
	start.tooltip_text = "적을 하나 이상 고르세요" if empty else "고른 구성으로 전투를 시작합니다"
	return root

## The arena roster and the party size.
static func arena_row(ui, list: VBoxContainer) -> void:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",4); list.add_child(row)
	ui.label(row,"아레나",14)
	var ids: Array = Session.ARENA_PRESETS.keys()
	var pick := OptionButton.new(); pick.name = "ArenaPick"; pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size.y = 44; pick.clip_text = true
	for id in ids: pick.add_item(caption(ids,id))
	pick.select(maxi(0,ids.find(str(ui.arena_config.arena))))
	pick.item_selected.connect(func(index): ui.arena_config.arena = ids[index]; ui.show_arena_setup())
	row.add_child(pick)
	var size := OptionButton.new(); size.name = "ArenaSize"; size.custom_minimum_size = Vector2(72,44)
	for count in [1,2,3]: size.add_item("%d인" % count)
	size.select(clampi(int(ui.arena_config.size)-1,0,2))
	size.item_selected.connect(func(index): resize(ui,index+1))
	row.add_child(size)

## "opt_archers · 코볼트/원거리, …" — the roster, so the pick is not an id alone.
static func caption(ids: Array, id: String) -> String:
	var preset: Dictionary = Session.ARENA_PRESETS[id]
	if id == "custom": return str(preset.label)
	var names: Array = preset.members.map(func(row): return "%s/%s" % [display(str(row[0])),ROLE_NAMES.get(str(row[1]),str(row[1]))])
	return "%s · %s" % [preset.label,", ".join(names)]

static func display(species_id: String) -> String:
	return str(Builder.species(species_id).get("display_name",species_id))

static func seed_row(ui, list: VBoxContainer) -> void:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",4); list.add_child(row)
	ui.label(row,"시드",14)
	var box := SpinBox.new(); box.name = "ArenaSeed"; box.min_value = 0; box.max_value = 99999; box.step = 1
	box.value = int(ui.arena_config.seed); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 44
	box.value_changed.connect(func(value): ui.arena_config.seed = int(value))
	row.add_child(box)
	var fixed := CheckButton.new(); fixed.name = "ArenaSeedFixed"; fixed.text = "고정"
	fixed.button_pressed = bool(ui.arena_config.fixed_seed); fixed.custom_minimum_size.y = 44
	fixed.tooltip_text = "고정하지 않으면 시작할 때마다 새 시드를 뽑습니다."
	fixed.toggled.connect(func(pressed): ui.arena_config.fixed_seed = pressed)
	row.add_child(fixed)

## The hand-made roster: up to three foes as a species and a role.
static func custom_row(ui, list: VBoxContainer) -> void:
	var box := CharacterUI.card(list,"적 구성")
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",4); box.add_child(row)
	var table: Array = Builder.table()
	for slot in range(3):
		var pick := OptionButton.new(); pick.name = "ArenaFoe%d" % slot
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pick.custom_minimum_size.y = 44; pick.clip_text = true
		pick.add_item("없음")
		for species in table:
			for role in ROLES: pick.add_item("%s·%s" % [str(species.display_name),ROLE_NAMES[role]])
		var current: Array = ui.arena_config.custom[slot]
		var index := 0
		for i in range(table.size()):
			if str(table[i].species_id) == str(current[0]): index = 1+i*ROLES.size()+maxi(0,ROLES.find(str(current[1])))
		pick.select(index)
		pick.item_selected.connect(func(choice): choose_foe(ui,slot,table,choice))
		row.add_child(pick)

static func choose_foe(ui, slot: int, table: Array, choice: int) -> void:
	if choice <= 0: ui.arena_config.custom[slot] = ["",""]
	else: ui.arena_config.custom[slot] = [str(table[(choice-1)/ROLES.size()].species_id),ROLES[(choice-1)%ROLES.size()]]
	# An empty roster closes 시작, so the screen is rebuilt on every foe change.
	ui.show_arena_setup()

## A party size change keeps the cards it already has and fills the rest.
static func resize(ui, count: int) -> void:
	ui.arena_config.size = count
	while ui.arena_config.members.size() < count: ui.arena_config.members.append({"stance":"CHARGER","parts":["",""]})
	ui.show_arena_setup()

## One member: the hero chooses parts; companions also choose a stance.
static func member_card(ui, list: VBoxContainer, index: int, probe: Dictionary) -> void:
	var setup: Dictionary = ui.arena_config.members[index]
	var solo: bool = int(ui.arena_config.size) == 1
	if solo and str(setup.stance) == "GUARDIAN": setup.stance = "CHARGER"
	var box := CharacterUI.card(list,str(probe.get("name",MEMBER_NAMES[index])))
	box.name = "ArenaMember%d" % index
	if index > 0:
		var stances := HBoxContainer.new(); stances.add_theme_constant_override("separation",4); box.add_child(stances)
		for id in Stances.IDS:
			var pick = ui.button(stances,Stances.NAMES[id],func(): choose_stance(ui,index,id),true)
			pick.name = "ArenaStance_%d_%s" % [index,id]
			pick.toggle_mode = true; pick.button_pressed = id == str(setup.stance)
	var slots := HBoxContainer.new(); slots.add_theme_constant_override("separation",4); box.add_child(slots)
	var ids: Array = Abilities.DEFINITIONS.keys()
	for slot in range(2):
		var pick := OptionButton.new(); pick.name = "ArenaPart_%d_%d" % [index,slot]
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pick.custom_minimum_size.y = 44; pick.clip_text = true
		pick.add_item("빈 슬롯")
		for id in ids: pick.add_item(str(Abilities.definition(id).name))
		pick.select(ids.find(str(setup.parts[slot]))+1)
		# One part, one slot: what the other slot holds cannot be picked again.
		var other: int = ids.find(str(setup.parts[1-slot]))
		if other >= 0: pick.set_item_disabled(other+1,true)
		pick.item_selected.connect(func(choice): choose_part(ui,index,slot,ids,choice))
		slots.add_child(pick)
	# The seed rolls the personality, so the chance is quoted with its seed.
	probe["stance"] = str(setup.stance)
	var chance := CharacterUI.text(box,"실수 확률 %d%% · 시드 %d 기준" % [Stances.mistake_chance(probe),int(ui.arena_config.seed)],12)
	chance.tooltip_text = "시드 고정이 꺼져 있으면 시작 시 시드가 새로 정해져 값이 달라집니다."
	chance.mouse_filter = Control.MOUSE_FILTER_STOP

## The other slot's picker has to grey the part out, so a pick rebuilds the screen.
static func choose_part(ui, index: int, slot: int, ids: Array, choice: int) -> void:
	ui.arena_config.members[index].parts[slot] = "" if choice <= 0 else str(ids[choice-1])
	ui.show_arena_setup()

static func choose_stance(ui, index: int, id: String) -> void:
	ui.arena_config.members[index].stance = id
	ui.show_arena_setup()
