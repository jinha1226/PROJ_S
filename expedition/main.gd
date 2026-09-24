extends Control
const Session = preload("res://expedition/session.gd")
const Presentation = preload("res://expedition/battle_presentation.gd")
const Board = preload("res://expedition/board.gd")
const MapView = preload("res://expedition/map_view.gd")
const Art = preload("res://expedition/mobile_art.gd")
const InventorySlot = preload("res://expedition/inventory_slot.gd")
const CharacterUI = preload("res://expedition/character_ui.gd")
const BattleHud = preload("res://expedition/battle_hud.gd")
const ArenaSetup = preload("res://expedition/arena_setup.gd")
const Stances = preload("res://expedition/stances.gd")
var portrait_gesture = preload("res://expedition/legacy/portrait_gesture.gd").new()
var navigation = preload("res://expedition/exploration_navigation.gd").new()
const NAVIGATION_STEP_SECONDS := 0.06
var navigation_clock := 0.0
var view_side := 17
var log_popup: PopupPanel
var auto_explore_button: Button
var inventory_filter := "전체"
var inventory_selected := ""
var inventory_slots: Array = []
var item_popup: PopupPanel
var item_detail: VBoxContainer
const FONT = preload("res://assets/fonts/NanumSquareR.ttf")
const SKILLS = [["PUSH","GUARD"],["ATTACK","GUARD"],["WATER","ELECTRIC"]]
const SKILL_NAMES = [["밀쳐내기","엄호"],["강타","엄호"],["물","방전"]]
var session = null
## Battle test mode: the town session set aside while a throwaway arena session
## fights, the setup screen's own state, and whether that screen is showing.

var arena_config := {"arena":"early_hob","seed":0,"fixed_seed":false,"size":1,
	"members":[{"stance":"CHARGER","parts":["",""]},{"stance":"CHARGER","parts":["",""]},{"stance":"CHARGER","parts":["",""]}],
	"custom":[["",""],["",""],["",""]]}
var mode_arena_setup := false
var mode_arena_active := false
var mode := ""
var reservation_actor := -1
var pending_item := -1
var pending_attack: Dictionary = {}
var attack_button: Button
var show_attack_range := false
var action_effects: Array = []
var reset_effects := false
var root_layout: VBoxContainer
## Where the retained board and minimap wait while a screen that has no floor
## on it is up. They stay children of this scene, so they are freed with it.
var parked: Node
var board
var end_turn_button: Button
var wait_button: Button
var advance_attack_button: Button
var character_tab := "상태"
var minimap
var map_view
var map_popup: PopupPanel
var details_popup: PopupPanel
var modal_content: VBoxContainer
## An npc's own offer has its own popup: it outranks whatever else is open and
## the run waits on it.
var offer_popup: PopupPanel
var offer_content: VBoxContainer
var proposal_line := ""
var notice := "":
	set(value):
		notice = value
		if is_instance_valid(toast):
			toast.text = value
			toast.visible = not value.is_empty()
			toast_remaining = 2.5
var toast: Label
var toast_remaining := 0.0
var item_buttons: Array = []
var skill_buttons: Array = []
var portrait_buttons: Array = []
var tactics_actor := 0
var tactics_expanded := -1
## Auto battle (floor mode): the timer that drives the rounds, the sentence of
## the last stop event and whether this battle has been reported.
var auto_clock := 0.0
var stop_text := ""
var battle_reported := false

func _ready() -> void:
	var skin := Theme.new(); skin.default_font = FONT; skin.default_font_size = 12
	for state in ["normal","hover","pressed","focus","disabled"]:
		var box := StyleBoxFlat.new(); box.bg_color = Color("151c24") if state != "pressed" else Color("433c2c")
		box.border_color = Color("bba16b") if state in ["hover","pressed","focus"] else Color("50535a")
		box.set_border_width_all(1); box.set_corner_radius_all(4)
		box.content_margin_left = 3; box.content_margin_right = 3; skin.set_stylebox(state,"Button",box)
	skin.set_stylebox("panel","PopupPanel",CharacterUI.surface(Color("101416")))
	theme = skin
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,0 if side in ["left","right"] else 8)
	add_child(margin)
	root_layout = VBoxContainer.new(); root_layout.add_theme_constant_override("separation",5); margin.add_child(root_layout)
	parked = Node.new(); parked.name = "Parked"; add_child(parked)
	map_popup = PopupPanel.new(); add_child(map_popup)
	var map_box := VBoxContainer.new(); map_box.custom_minimum_size = Vector2(300,360); map_popup.add_child(map_box)
	map_view = MapView.new(); map_view.session = session; map_view.ui_font = FONT; map_view.minimum_side = 280
	map_box.add_child(map_view)
	button(map_box,"닫기",func(): map_popup.hide())
	details_popup = PopupPanel.new(); add_child(details_popup)
	modal_content = VBoxContainer.new(); modal_content.custom_minimum_size = Vector2(popup_width(),210); details_popup.add_child(modal_content)
	item_popup = PopupPanel.new(); details_popup.add_child(item_popup)
	item_popup.transient = true; item_popup.exclusive = true
	item_detail = VBoxContainer.new(); item_detail.custom_minimum_size = Vector2(300,200); item_popup.add_child(item_detail)
	offer_popup = PopupPanel.new(); offer_popup.name = "OfferPopup"; add_child(offer_popup)
	offer_content = VBoxContainer.new(); offer_content.custom_minimum_size = Vector2(popup_width(),160); offer_popup.add_child(offer_content)
	log_popup = PopupPanel.new(); add_child(log_popup)
	toast = Label.new(); toast.name = "NoticeToast"; toast.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(toast); toast.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	toast.anchor_top = 0.22; toast.anchor_bottom = 0.22
	toast.offset_left = 16; toast.offset_right = -16
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_font_size_override("font_size",16)
	toast.add_theme_stylebox_override("normal",CharacterUI.surface(Color(0.04,0.05,0.07,0.92)))
	toast.z_index = 10; toast.visible = false
	refresh()

func stop_navigation() -> void:
	navigation.stop(); navigation_clock = 0
	if is_instance_valid(auto_explore_button): auto_explore_button.text = "탐색" if session != null and session.manual_mode else "자동탐험"

func popup_open() -> bool:
	return details_popup.visible or map_popup.visible or log_popup.visible or item_popup.visible or is_instance_valid(offer_popup) and offer_popup.visible

## One timer step of the auto battle: 0.7s at 1×, half that at 2×.
func auto_interval() -> float:
	return 0.7/float(maxi(1,int(session.auto.speed)))

## A stop event outranks the round: it halts the run, names itself in the
## banner and, at the end of a battle, opens the report.
func auto_tick() -> void:
	if is_instance_valid(board) and board.is_presenting(): return
	if session == null: return
	var reason: String = session.auto_stop_reason()
	if not reason.is_empty():
		session.auto.running = false
		note_stop(reason)
		if reason == "BATTLE_END": report_battle()
		refresh(); return
	# Nothing to fight: the run would spin on a refused auto_step.
	if not session.in_combat():
		session.auto.running = false; refresh(); return
	battle_reported = false
	run_action(session.auto_step)
	if is_instance_valid(board) and board.is_presenting(): return
	# The report is a summary, not a stop: it follows every battle, including
	# one whose BATTLE_END stop the player switched off.
	if not session.in_combat(): report_battle()

## The report of the battle that just ended, once.
func report_battle() -> void:
	if battle_reported: return
	battle_reported = true
	show_battle_report()

func toggle_auto() -> void:
	stop_navigation()
	session.auto.running = not session.auto.running
	var toggle = find_child("AutoToggle",true,false)
	if toggle != null: toggle.text = "⏸ 정지" if session.auto.running else "▶ 재개"
	if session.auto.running: stop_text = ""
	auto_clock = 0.0
	refresh()

func toggle_speed() -> void:
	session.auto.speed = 1 if int(session.auto.speed) > 1 else 2
	if is_instance_valid(board): board.playback_speed = float(session.auto.speed)
	var speed = find_child("SpeedToggle",true,false)
	if speed != null: speed.text = "%d×" % int(session.auto.speed)
	auto_clock = 0.0
	refresh()

## `auto_stop_reason` has side effects, so the HUD asks it in exactly two
## places: every auto tick, and once at the end of every player action — a
## battle can begin or end by hand while the run is stopped.
func check_stop() -> void:
	if session != null and session.manual_mode: return
	if session == null or session.auto.running: return
	var reason: String = session.auto_stop_reason()
	if reason.is_empty(): return
	note_stop(reason)
	if reason == "BATTLE_END": report_battle()

func note_stop(reason: String) -> void:
	stop_text = stop_message(reason)
	# A fresh battle owes the player a fresh report.
	if reason == "BATTLE_START": battle_reported = false
	auto_clock = 0.0

## The Korean sentence of a stop event, with whoever caused it.
func stop_message(reason: String) -> String:
	match reason:
		"BATTLE_START": return "전투 시작 · 적 %d" % session.party_enemies().size()
		"BATTLE_END": return "전투 종료"
		"DEATH":
			var fallen: Array = session.party.filter(func(a): return a.hp <= 0)
			return "%s 쓰러짐" % (fallen[-1].name if not fallen.is_empty() else "아군")
		"ALLY_LETHAL":
			var risked: Array = session.alive().filter(func(a): return Session.Rules.lethal_threat(session,a) >= a.hp)
			return "%s 치명 위기" % (risked[0].name if not risked.is_empty() else "아군")
		"HP_LOW":
			var low: Array = session.alive().filter(func(a): return a.hp*100/a.max_hp <= int(session.auto.hp_low))
			return "%s 체력 %d%% 이하" % [low[0].name if not low.is_empty() else "아군",int(session.auto.hp_low)]
	return ""

## 후퇴 is the one standing order the HUD still offers, and the only control
## that works mid-run: calling the party off cannot wait for the next stop.
func toggle_retreat() -> void:
	session.party_command = "FOLLOW" if session.party_command == "RETREAT" else "RETREAT"
	refresh()

func show_battle_report() -> void:
	stop_navigation(); BattleHud.report(self)

## Battle test mode (§3): the setup screen, a throwaway arena session started
## from it, and the way back to the town session it set aside.
func show_arena_setup() -> void:
	stop_navigation(); details_popup.hide()
	if session != null: session.auto.running = false
	mode_arena_setup = true; refresh()

func start_arena() -> void:
	mode_arena_setup = false
	if not bool(arena_config.fixed_seed): arena_config.seed = randi() % 100000
	var arena: Dictionary = Session.ARENA_PRESETS.get(str(arena_config.arena),{}).duplicate(true)
	if str(arena_config.arena) == "custom":
		arena.members = arena_config.custom.filter(func(row): return not str(row[0]).is_empty()).map(func(row): return [str(row[0]),str(row[1])])
	details_popup.hide()
	session = Session.arena_test(int(arena_config.seed),int(arena_config.size),arena,arena_config.members)
	session.manual_mode = true
	mode_arena_active = true
	mode = ""; pending_attack = {}; show_attack_range = false
	stop_text = ""; battle_reported = false; action_effects = []; reset_effects = true
	check_stop()
	refresh()

func leave_arena() -> void:
	mode_arena_setup = false; mode_arena_active = false; details_popup.hide(); session = null
	stop_text = ""; battle_reported = false; action_effects = []; reset_effects = true
	refresh()

func _process(delta: float) -> void:
	if is_instance_valid(board) and board.is_presenting(): return
	toast_remaining = maxf(0,toast_remaining-delta)
	if is_instance_valid(toast): toast.visible = toast_remaining > 0 and not notice.is_empty()
	portrait_gesture.tick(self)
	if session != null and not session.manual_mode and session.auto.running and not popup_open():
		auto_clock += delta
		if auto_clock >= auto_interval():
			auto_clock = 0.0; auto_tick()
	if session == null or not navigation.active: return
	if details_popup.visible or map_popup.visible or log_popup.visible or not get_window().has_focus(): stop_navigation(); return
	navigation_clock += delta
	if navigation_clock >= NAVIGATION_STEP_SECONDS:
		navigation_clock = 0; navigation_tick()

func navigation_tick() -> void:
	var step: Vector2i = navigation.next_step(session)
	if step.x < 0: stop_navigation(); return
	var health: Array = session.party.map(func(a): return a.hp)
	run_action(func(): return session.act("MOVE",step),true)
	if session.party.map(func(a): return a.hp) != health or not session.party_enemies().is_empty() or session.party[session.selected].pos != step:
		stop_navigation()
	elif session.floor_state.features.keys().any(func(p): return session.floor_state.features[p].kind in ["curio","stairs"] and not session.floor_state.features[p].used and session.distance(step,p) <= 1):
		stop_navigation()
	elif not navigation.automatic and step == navigation.destination: stop_navigation()

func _input(event: InputEvent) -> void:
	if session != null: portrait_gesture.handle(self,event)

func _unhandled_key_input(event: InputEvent) -> void:
	if session == null or not session.manual_mode or not session.on_floor() or popup_open(): return
	if not event.pressed or event.is_echo(): return
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var direction := Vector2i.ZERO
	match key:
		KEY_UP, KEY_W, KEY_K: direction = Vector2i.UP
		KEY_DOWN, KEY_S, KEY_J: direction = Vector2i.DOWN
		KEY_LEFT, KEY_A, KEY_H: direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D, KEY_L: direction = Vector2i.RIGHT
		KEY_Q: direction = Vector2i(-1,-1)
		KEY_E: direction = Vector2i(1,-1)
		KEY_Z: direction = Vector2i(-1,1)
		KEY_C: direction = Vector2i(1,1)
	if direction != Vector2i.ZERO:
		var point: Vector2i = session.party[0].pos+direction
		if session.inside(point):
			var occupant: Dictionary = session.at(point)
			if not occupant.is_empty() and occupant.enemy: run_action(func(): return session.act("ATTACK",point))
			else: run_action(func(): return session.act("MOVE",point))
		get_viewport().set_input_as_handled()
	elif key in [KEY_PERIOD,KEY_SPACE]:
		run_action(func(): return session.act("WAIT",session.party[0].pos))
		get_viewport().set_input_as_handled()

func toggle_explore() -> void:
	if navigation.active: stop_navigation(); return
	mode = ""; pending_item = -1; reservation_actor = -1
	if navigation.explore(session): auto_explore_button.text = "탐험 중지"
	else: notice = "주변에 적 있음"; refresh()

func show_logs() -> void:
	stop_navigation(); clear(log_popup)
	var skin: Theme = theme.duplicate()
	var panel := CharacterUI.surface(Color("101416")); panel.set_content_margin_all(8); panel.shadow_size = 0
	skin.set_stylebox("panel","PopupPanel",panel); log_popup.theme = skin
	var box := VBoxContainer.new(); box.custom_minimum_size = size-Vector2(16,16); log_popup.add_child(box)
	label(box,"전체 기록",22)
	var history := RichTextLabel.new(); history.name = "FullHistory"; history.size_flags_vertical = SIZE_EXPAND_FILL
	history.add_theme_font_size_override("normal_font_size",18); history.text = "\n\n".join(session.log_lines)
	history.scroll_following = true; box.add_child(history)
	button(box,"닫기",func(): log_popup.hide())
	log_popup.popup_centered(Vector2i(size))

## Popup content width. The window, not the HUD's own size, bounds a modal, and
## the cap leaves room for the panel's own margins on a 320px phone.
const POPUP_MAX_WIDTH := 288.0
func popup_width() -> float:
	return minf(POPUP_MAX_WIDTH,get_viewport_rect().size.x-32)

func clear(node: Node) -> void:
	if node == modal_content:
		item_popup.hide()
		details_popup.theme = theme
		modal_content.custom_minimum_size = Vector2(popup_width(),210)
	for child in node.get_children(): node.remove_child(child); child.queue_free()
	if node == modal_content: details_popup.reset_size()

func label(parent: Node, text: String, font_size: int = 12) -> Label:
	var node := Label.new(); node.text = text; node.add_theme_font_size_override("font_size",font_size)
	node.mouse_filter = MOUSE_FILTER_IGNORE; parent.add_child(node); return node

func button(parent: Node, text: String, callback: Callable, enabled: bool = true) -> Button:
	var node := Button.new(); node.text = text; node.disabled = not enabled
	node.custom_minimum_size = Vector2(0,44); node.size_flags_horizontal = SIZE_EXPAND_FILL
	node.pressed.connect(callback); parent.add_child(node); return node

func icon_button(parent: Node, texture: Texture2D, callback: Callable, hint: String, count: String = "") -> Button:
	var node := button(parent,"",callback)
	node.tooltip_text = hint; node.custom_minimum_size = Vector2(0,48)
	var picture := TextureRect.new(); picture.texture = texture; picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; picture.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_child(picture); picture.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	picture.offset_left = 4; picture.offset_right = -4; picture.offset_top = 4; picture.offset_bottom = -4
	if count != "":
		var number := label(node,count,12); number.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		number.offset_left = -18; number.offset_top = -18; number.offset_right = -2; number.offset_bottom = -2
		number.add_theme_color_override("font_shadow_color",Color.BLACK); number.add_theme_constant_override("shadow_offset_x",1); number.add_theme_constant_override("shadow_offset_y",1)
	return node

func gauge(parent: Node, value: int, maximum: int, color: Color) -> void:
	var bar := ProgressBar.new(); bar.max_value = maximum; bar.value = value; bar.show_percentage = false
	bar.custom_minimum_size.y = 4; bar.mouse_filter = MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new(); fill.bg_color = color; fill.set_corner_radius_all(2)
	var background := StyleBoxFlat.new(); background.bg_color = Color("0b1016")
	bar.add_theme_stylebox_override("fill",fill); bar.add_theme_stylebox_override("background",background); parent.add_child(bar)

func resource_gauge(parent: Button, id: String, value: int, color: Color, hint: String) -> void:
	var bar := ProgressBar.new(); bar.name = id; bar.max_value = 100; bar.value = clampi(value,0,100)
	bar.show_percentage = false; bar.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(bar); bar.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	bar.offset_left = 4; bar.offset_right = -4; bar.offset_top = -7; bar.offset_bottom = -3
	var fill := StyleBoxFlat.new(); fill.bg_color = color; fill.set_corner_radius_all(2)
	var background := StyleBoxFlat.new(); background.bg_color = Color("080c10")
	bar.add_theme_stylebox_override("fill",fill); bar.add_theme_stylebox_override("background",background)
	parent.custom_minimum_size.y = 48; parent.tooltip_text = hint
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := parent.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_bottom = 8; parent.add_theme_stylebox_override(state,style)

func refresh() -> void:
	if is_instance_valid(board) and board.is_presenting(): return
	update_offer_popup()
	var elapsed := 0.0
	var impact_elapsed := 0.0
	# Opening a popup or selecting a member must not erase an attack that just
	# resolved: the flash and the shake carry their own clocks across a refresh.
	if not reset_effects and action_effects.is_empty() and is_instance_valid(board):
		action_effects = board.effects.duplicate(true); elapsed = board.effect_time
		impact_elapsed = board.impact_time
	reset_effects = false
	# The renderer and the minimap keep their incremental caches: a rebuilt
	# 80x80 minimap would redraw every known tile on every action.
	if is_instance_valid(board):
		if board.get_parent() != null: board.get_parent().remove_child(board)
		clear(board)
		board.actor_visuals.clear(); board.foreground = null; board.intent_overlay = null
		board.visible = false; parked.add_child(board)
	if is_instance_valid(minimap) and minimap.get_parent() != null:
		minimap.get_parent().remove_child(minimap)
		minimap.visible = false; parked.add_child(minimap)
	clear(root_layout); item_buttons.clear(); skill_buttons.clear(); portrait_buttons.clear()
	auto_explore_button = null; wait_button = null; advance_attack_button = null
	if mode_arena_setup:
		root_layout.add_child(ArenaSetup.build(self)); return
	if session == null:
		build_start_screen(); return
	map_view.session = session; map_view.queue_redraw()
	if session.phase == "CAMP": build_camp_screen(); return
	if session.phase == "DEFEAT": build_result_card(); return
	var header := HBoxContainer.new(); header.name = "TopHUD"; header.add_theme_constant_override("separation",3); root_layout.add_child(header)
	if not is_instance_valid(minimap):
		minimap = MapView.new(); minimap.compact = true; minimap.minimum_side = 44
		minimap.ui_font = FONT; minimap.expand_requested.connect(show_map)
	if minimap.get_parent() != null: minimap.get_parent().remove_child(minimap)
	minimap.session = session; minimap.visible = true; minimap.queue_redraw(); header.add_child(minimap)
	var place := label(header,"%d층" % session.depth,18); place.name = "Location"; place.size_flags_horizontal = SIZE_EXPAND_FILL
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var food_label := label(header,"식량 %d" % session.food,14); food_label.name = "FoodLabel"
	food_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var menu := button(header,"메뉴",show_menu); menu.name = "ExpeditionMenu"; menu.size_flags_horizontal = SIZE_SHRINK_END
	if not is_instance_valid(board):
		board = Board.new(); board.ui_font = FONT; board.cell_pressed.connect(on_cell)
		board.cell_inspected.connect(inspect_cell)
		board.zoom_changed.connect(func(value): view_side = value)
		board.gesture_started.connect(stop_navigation); board.playback_finished.connect(finish_presentation)
	board.session = session; board.view_side = view_side; board.action_footer = not session.manual_mode and not pending_attack.is_empty()
	if board.get_parent() != null: board.get_parent().remove_child(board)
	board.visible = true
	board.size_flags_vertical = SIZE_EXPAND_FILL; root_layout.add_child(board); board.queue_redraw()
	board.show_attack_range = show_attack_range; board.targeting_skill = mode
	board.effects = action_effects; action_effects = []; board.target_cell = pending_attack.get("cell",Vector2i(-1,-1))
	board.effect_time = elapsed; board.impact_time = impact_elapsed
	board.companion_previews = session.companion_previews(); board.companion_intents = session.companion_intent_snapshot()
	if not session.in_combat(): board.reset_intent_ui()
	if not session.manual_mode and not pending_attack.is_empty():
		var warning := Session.Scheduler.double_movers(session,int(pending_attack.time))
		var preview := label(board,"명중 %d%% · 피해 %d–%d · %d tick%s" % [pending_attack.chance,pending_attack.damage_min,pending_attack.damage_max,pending_attack.time," · 느린 행동" if not warning.is_empty() else ""],12)
		preview.name = "ActionPreview"
		preview.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
		preview.offset_left = 8; preview.offset_right = -8; preview.offset_top = -82; preview.offset_bottom = -58
		attack_button = button(board,"공격",confirm_attack)
		attack_button.name = "ConfirmAttack"
		attack_button.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
		attack_button.offset_left = 8; attack_button.offset_top = -56; attack_button.offset_right = 210; attack_button.offset_bottom = -8
	var recent: Array = session.log_lines.slice(maxi(0,session.log_lines.size()-(4 if session.manual_mode else 1)))
	var log_button := button(root_layout,"\n".join(recent),show_logs)
	log_button.name = "RecentLog"; log_button.custom_minimum_size.y = 72 if session.manual_mode else 36
	if session.manual_mode:
		log_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		log_button.autowrap_mode = TextServer.AUTOWRAP_OFF
		log_button.clip_text = true
	if session.manual_mode:
		build_manual_controls()
		return
	var party_row := HBoxContainer.new(); party_row.name = "PartyRow"
	party_row.add_theme_constant_override("separation",5); root_layout.add_child(party_row)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var column := VBoxContainer.new(); column.size_flags_horizontal = SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",2); party_row.add_child(column)
		# The card reports each member's state; the hero's actions are below.
		var portrait := button(column,"",func(): select_actor(i)); portrait.name = "MemberCard%d" % i
		portrait.tooltip_text = "길게 누르기: 상태"; portrait.custom_minimum_size.y = 62
		portrait_buttons.append(portrait)
		var caption := "%s [%s] · HP %d/%d\n스트레스 %d · %s\n%s" % [actor.name,Stances.SHORT[Stances.effective(actor)],actor.hp,actor.max_hp,actor.stress,actor.condition,actor.last_action]
		if bool(actor.get("conflicted",false)): caption += " ⚠ 갈등"
		var stats := label(portrait,caption,12 if session.party.size() == 1 else 10)
		stats.name = "MemberCaption%d" % i
		stats.set_anchors_and_offsets_preset(PRESET_FULL_RECT); stats.offset_left = 4; stats.offset_right = -4
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if i == session.selected:
			var gold := portrait.get_theme_stylebox("normal").duplicate(); gold.border_color = Color("e9c575")
			gold.set_border_width_all(2); portrait.add_theme_stylebox_override("normal",gold)
		if actor.hp <= 0: portrait.modulate = Color("636369")
	var shared := HBoxContainer.new(); root_layout.add_child(shared)
	for slot in range(5):
		var item := icon_button(shared,Art.item(slot),func(): choose_item(slot),Session.SUPPLY_NAMES[slot],str(session.supplies[slot]))
		item.disabled = session.supplies[slot] <= 0 or session.auto.running; item_buttons.append(item)
	if session.manual_mode:
		var spells := HBoxContainer.new(); spells.name = "SpellBar"; root_layout.add_child(spells)
		for slot in range(3):
			var prepared: Array = session.party[0].prepared
			var id: String = str(prepared[slot]) if slot < prepared.size() else ""
			var caption: String = str(Session.CombatStats.content.spells[id].name) if not id.is_empty() else "—"
			var spell := button(spells,caption,func(): choose_spell(id),not id.is_empty())
			spell.name = "Spell%d" % slot; spell.custom_minimum_size.y = 44
	var nav := GridContainer.new(); nav.name = "BottomActions"; nav.columns = 4; root_layout.add_child(nav)
	var attack := button(nav,"공격",func():
		if session.manual_mode:
			mode = "ATTACK"; show_attack_range = true; refresh()
		else: run_action(session.auto_attack),session.in_combat()); attack.name = "Attack"
	var wait := button(nav,"대기",func(): run_action(func(): return session.act("WAIT",session.party[session.selected].pos))); wait.name = "Wait"; wait_button = wait
	if session.manual_mode:
		var parts_button := button(nav,"파츠",show_part_actions,session.in_combat()); parts_button.name = "PartActions"
	if not session.manual_mode:
		var toggle := button(nav,"⏸ 정지" if session.auto.running else "▶ 전투",toggle_auto,session.in_combat()); toggle.name = "AutoToggle"
		var speed := button(nav,"%d×" % int(session.auto.speed),toggle_speed); speed.name = "SpeedToggle"
		var retreat := button(nav,"후퇴 해제" if session.party_command == "RETREAT" else "후퇴",toggle_retreat,session.in_combat()); retreat.name = "RetreatToggle"
	auto_explore_button = button(nav,"중지" if navigation.active else "자동탐험",toggle_explore,not session.in_combat() and not session.auto.running)
	var camp := button(nav,"야영",func(): run_action(session.camp),session.can_camp().is_empty() and not session.auto.running)
	camp.name = "CampButton"; camp.tooltip_text = session.can_camp()
	button(nav,"가방",show_supplies)
	if not session.manual_mode: build_stop_banner()

func build_manual_controls() -> void:
	var portraits := HBoxContainer.new(); portraits.name = "PortraitRow"
	portraits.add_theme_constant_override("separation",4); root_layout.add_child(portraits)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var portrait := button(portraits,"",func(): show_character(i,"상태"))
		portrait.name = "HeroStatus" if i == 0 else "MemberStatus%d" % i
		portrait.custom_minimum_size.y = 68
		var content := HBoxContainer.new(); content.mouse_filter = MOUSE_FILTER_IGNORE
		portrait.add_child(content); content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		var image := TextureRect.new(); image.texture = Art.portrait(i)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size.x = 56 if session.party.size() == 1 else 40
		image.mouse_filter = MOUSE_FILTER_IGNORE; content.add_child(image)
		var caption := label(content,"%s · Lv%d\nHP %d/%d · MP %d/%d\n스트레스 %d" % [actor.name,int(actor.level),int(actor.hp),int(actor.max_hp),int(actor.mp),int(actor.max_mp),int(actor.stress)],12 if session.party.size() == 1 else 10)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	var nav := HBoxContainer.new(); nav.name = "BottomActions"
	nav.add_theme_constant_override("separation",3); root_layout.add_child(nav)
	var attack := button(nav,"공격",arm_attack); attack.name = "Attack"
	attack.toggle_mode = true; attack.button_pressed = mode == "ATTACK"
	var wait := button(nav,"대기",func(): run_action(func(): return session.act("WAIT",session.party[0].pos))); wait.name = "Wait"; wait_button = wait
	auto_explore_button = button(nav,"중지" if navigation.active else "탐색",toggle_explore,not session.in_combat())
	var tactics := button(nav,"전술",show_manual_tactics); tactics.name = "Tactics"
	button(nav,"가방",show_supplies)
	for action in nav.get_children(): action.custom_minimum_size.y = 48

func arm_attack() -> void:
	if session == null or not session.manual_mode: return
	mode = "" if mode == "ATTACK" else "ATTACK"
	show_attack_range = mode == "ATTACK"
	refresh()

func show_manual_tactics() -> void:
	if session == null or not session.manual_mode: return
	clear(modal_content)
	var box := VBoxContainer.new(); box.name = "ManualTactics"; modal_content.add_child(box)
	label(box,"전술",20)
	var actor: Dictionary = session.party[0]
	for id in actor.prepared:
		var spell_id: String = str(id)
		var definition: Dictionary = Session.CombatStats.content.spells.get(spell_id,{})
		var spell := button(box,"%s · %d MP" % [str(definition.get("name",spell_id)),int(definition.get("mp",0))],func(): details_popup.hide(); choose_spell(spell_id),actor.mp >= int(definition.get("mp",0)))
		spell.name = "Spell_"+spell_id
	for id in actor.equipped_abilities:
		var part_id: String = str(id)
		if part_id.is_empty() or not Session.Abilities.DEFINITIONS.has(part_id): continue
		var def: Dictionary = Session.Abilities.DEFINITIONS[part_id]
		var available: bool = session.in_combat() and int(actor.cooldowns.get(part_id,0)) <= 0
		if def.target == "SELF": available = available and Session.Abilities.legal(session,actor,part_id,actor.pos)
		var part := button(box,str(def.name),choose_part.bind(part_id),available)
		part.name = "Part_"+part_id
	button(box,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func build_start_screen() -> void:
	var box := VBoxContainer.new(); box.name = "StartScreen"; box.size_flags_vertical = SIZE_EXPAND_FILL; root_layout.add_child(box)
	label(box,"하강",26)
	var start := button(box,"새 탐험",new_run); start.name = "NewRun"
	var arena := button(box,"전투 시험",show_arena_setup); arena.name = "ArenaButton"

func build_camp_screen() -> void:
	var box := VBoxContainer.new(); box.name = "CampScreen"; box.size_flags_vertical = SIZE_EXPAND_FILL; root_layout.add_child(box)
	label(box,"야영 · 식량 %d" % session.food,22)
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		var card := VBoxContainer.new(); card.name = "CampMember%d" % i; box.add_child(card)
		label(card,"%s  HP %d/%d  MP %d/%d" % [actor.name,actor.hp,actor.max_hp,actor.mp,actor.max_mp],15)
		if not session.manual_mode:
			button(card,"태세 · %s" % actor.stance,func(): show_character(i,"태세"))
			button(card,"파츠",func(): show_character(i,"파츠"))
		if session.manual_mode:
			button(card,"장비",func(): show_gear(i))
			button(card,"주문 준비",func(): show_prepare(i))
	button(box,"가방",show_supplies)
	var end := button(box,"야영 끝",func(): run_action(session.end_camp)); end.name = "CampEnd"

func show_menu() -> void:
	clear(modal_content)
	if session != null and session.manual_mode:
		button(modal_content,"야영",func(): details_popup.hide(); run_action(session.camp),session.can_camp().is_empty())
	button(modal_content,"기록",show_logs)
	button(modal_content,"가방",show_supplies)
	if session != null and session.manual_mode: button(modal_content,"인물",func(): show_character(0,"상태"))
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func show_gear(index: int) -> void:
	if session.phase != "CAMP" or index < 0 or index >= session.party.size(): return
	clear(modal_content)
	var box := VBoxContainer.new(); box.name = "GearScreen"; modal_content.add_child(box)
	var actor: Dictionary = session.party[index]
	label(box,actor.name+" · 장비",20)
	for slot in ["weapon","armour","shield","ring"]:
		var equipped: Dictionary = actor.gear[slot]
		var name: String = str(equipped.get("type","—"))
		var row := HBoxContainer.new(); box.add_child(row)
		label(row,slot+"  "+name,14)
		button(row,"해제",func():
			if session.unequip_gear(index,slot): show_gear(index),not equipped.is_empty())
	var current: Dictionary = Session.CombatStats.stats(session,actor)
	for i in range(session.gear_bag.size()):
		var item: Dictionary = session.gear_bag[i]
		var slot: String = session.gear_slot(item)
		if slot.is_empty(): continue
		var probe: Dictionary = actor.duplicate(true); probe.gear[slot] = item
		var next: Dictionary = Session.CombatStats.stats(session,probe)
		var choice := button(box,"%s  Δ피해 %+d  Δ시간 %+d  ΔAC %+d  ΔEV %+d" % [item.type,int(next.damage)-int(current.damage),int(next.delay)-int(current.delay),int(next.ac)-int(current.ac),int(next.ev)-int(current.ev)],func():
			if session.equip_gear(index,item): refresh(); show_gear(index))
		choice.name = "GearOption%d" % i
		choice.custom_minimum_size.y = 44
	button(box,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func show_part_actions() -> void:
	if session == null or not session.manual_mode or not session.in_combat(): return
	clear(modal_content)
	var box := VBoxContainer.new(); box.name = "PartActionMenu"; modal_content.add_child(box)
	label(box,"파츠",20)
	var actor: Dictionary = session.party[0]
	for id in actor.equipped_abilities:
		if str(id).is_empty() or not Session.Abilities.DEFINITIONS.has(id): continue
		var def: Dictionary = Session.Abilities.DEFINITIONS[id]
		var available: bool = int(actor.cooldowns.get(id,0)) <= 0
		if def.target == "SELF": available = Session.Abilities.legal(session,actor,str(id),actor.pos)
		var choice := button(box,str(def.name),choose_part.bind(str(id)),available)
		choice.custom_minimum_size.y = 44
	button(box,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func choose_part(id: String) -> void:
	if session == null or not Session.Abilities.DEFINITIONS.has(id): return
	details_popup.hide()
	var actor: Dictionary = session.party[0]
	if Session.Abilities.DEFINITIONS[id].target == "SELF":
		run_action(func(): return session.act(id,actor.pos))
	else:
		mode = id
		notice = "대상 선택"
		refresh()

func show_prepare(index: int) -> void:
	if session.phase != "CAMP" or index < 0 or index >= session.party.size(): return
	clear(modal_content)
	var box := VBoxContainer.new(); box.name = "PrepareScreen"; modal_content.add_child(box)
	var actor: Dictionary = session.party[index]
	label(box,actor.name+" · 주문",20)
	for id in actor.spells:
		var spell: Dictionary = Session.CombatStats.content.spells[id]
		button(box,("✓ " if id in actor.prepared else "○ ")+str(spell.name),func():
			if session.prepare_spell(index,id,id not in actor.prepared): show_prepare(index))
	button(box,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func show_stairs() -> void:
	clear(modal_content)
	var box := VBoxContainer.new(); box.name = "StairsPopup"; modal_content.add_child(box)
	label(box,"봉인됨" if session.stairs_sealed() else "%d층" % (session.depth+1),20)
	var descend_button := button(box,"내려가기",func(): details_popup.hide(); run_action(session.descend),not session.stairs_sealed())
	descend_button.name = "Descend"
	button(box,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func build_stop_banner() -> void:
	var banner := label(root_layout,stop_text,15)
	banner.name = "StopBanner"; banner.visible = not stop_text.is_empty()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; banner.clip_text = true

func new_run() -> void:
	session = Session.new_run(randi())
	stop_text = ""; battle_reported = false
	mode_arena_setup = false; mode_arena_active = false; mode = ""; pending_item = -1; pending_attack = {}; show_attack_range = false; action_effects = []; reset_effects = true
	check_stop(); refresh()

func depart() -> void:
	new_run()

func select_actor(index: int) -> void:
	stop_navigation()
	if session.party[index].hp <= 0: return
	if session.manual_mode and index != 0:
		show_character(index); return
	pending_attack = {}; show_attack_range = false
	session.selected = index; mode = ""; pending_item = -1; notice = session.party[index].name; refresh()

func finish_presentation() -> void:
	action_effects = []; reset_effects = true; auto_clock = 0.0
	if session.manual_mode:
		if not session.in_combat(): report_battle()
		refresh(); return
	var reason: String = session.auto_stop_reason()
	if not reason.is_empty():
		session.auto.running = false
		note_stop(reason)
	if not session.in_combat():
		session.auto.running = false
		report_battle()
	refresh()

func run_action(callback: Callable, navigating: bool = false) -> void:
	if is_instance_valid(board) and board.is_presenting(): return
	if not navigating: stop_navigation()
	session.effects.clear()
	var recorder = Presentation.new()
	var show_battle: bool = not session.manual_mode and is_processing() and session.phase == "BATTLE" and not session.party_enemies().is_empty()
	if show_battle:
		recorder.begin(session); session.presentation = recorder
	var accepted: bool = callback.call()
	pending_attack = {}
	notice = "" if accepted else "사용 불가"
	if accepted:
		mode = ""; pending_item = -1; reservation_actor = -1
		if session.manual_mode: show_attack_range = false
		# In floor mode auto_step ends the round itself.
	if show_battle: recorder.finish(session)
	session.presentation = null
	if accepted and show_battle and not recorder.frames.is_empty() and is_instance_valid(board):
		session.effects.clear(); action_effects = []
		board.playback_speed = float(session.auto.speed)
		board.play_frames(recorder.frames)
		return
	action_effects = session.effects.duplicate(true); session.effects.clear()
	reset_effects = accepted
	check_stop()
	refresh()

func preview_attack(point: Vector2i) -> void:
	pending_attack = session.attack_preview(point)
	show_attack_range = true
	notice = "공격 불가" if pending_attack.is_empty() else "%s · 명중 %d%% · 피해 %d–%d · %d tick" % [pending_attack.name,pending_attack.chance,pending_attack.damage_min,pending_attack.damage_max,pending_attack.time]
	refresh()

func choose_spell(id: String) -> void:
	if id.is_empty(): return
	if id in ["blink","mend"]:
		run_action(func(): return session.cast(id,session.party[0].pos)); return
	mode = "CAST:"+id; notice = "대상 선택"; refresh()

func confirm_attack() -> void:
	if pending_attack.is_empty(): return
	var current: Dictionary = session.attack_preview(pending_attack.cell)
	if current != pending_attack:
		pending_attack = {}; notice = "대상 선택"; refresh(); return
	var point: Vector2i = pending_attack.cell
	run_action(func(): return session.act("ATTACK",point))


func choose_item(slot: int) -> void:
	stop_navigation()
	reservation_actor = -1
	pending_attack = {}
	mode = ""; pending_item = slot
	if slot in [3,4]: notice = Session.SUPPLY_NAMES[slot]+" · 대상 칸 선택"; refresh()
	else: run_action(func(): return session.use_supply(slot))

func queue_action(kind: String, point: Vector2i) -> void:
	if session.reserve_action(reservation_actor,kind,point):
		notice = session.party[reservation_actor].name+" · 다음 행동 예약 완료"
		reservation_actor = -1; mode = ""
	else: notice = "예약 불가"
	refresh()

func on_cell(point: Vector2i) -> void:
	if session == null or not session.on_floor(): return
	stop_navigation()
	if session.manual_mode and mode == "ATTACK":
		var target: Dictionary = session.at(point)
		if not target.is_empty() and target.enemy and not session.attack_preview(point).is_empty():
			run_action(func(): return session.act("ATTACK",point))
		else:
			notice = "공격 대상 없음"
			refresh()
		return
	var feature: Dictionary = session.floor_state.features.get(point,{})
	if feature.get("kind","") == "pylon" and session.floor_state.visible.has(point):
		run_action(func(): return session.act("PYLON",point)); return
	if session.in_combat() and not session.manual_mode: focus_enemy(point); refresh(); return
	if session.floor_state.visible.has(point):
		# A tap only reaches an npc the party can see, and only an adjacent one talks.
		var wanderer: Dictionary = session.at(point)
		if session.wanderer(wanderer):
			if session.melee_reach(session.party[session.selected].pos,point): show_npc(wanderer)
			else: notice = "%s · %s" % [wanderer.name,wanderer.get("activity","")] if not str(wanderer.get("activity","")).is_empty() else str(wanderer.name); refresh()
			return
		if feature.get("kind","") == "curio": show_curio(point); return
		if feature.get("kind","") == "stairs" and session.distance(session.party[session.selected].pos,point) <= 1: show_stairs(); return
		if not feature.is_empty() and session.distance(session.party[session.selected].pos,point) <= 1:
			run_action(func(): return session.floor_state.interact(session,point)); return
	if pending_item >= 0: run_action(func(): return session.use_supply(pending_item,point)); return
	if mode.begins_with("CAST:"):
		var spell_id := mode.trim_prefix("CAST:")
		run_action(func(): return session.cast(spell_id,point)); return
	if not mode.is_empty() and mode != "ATTACK": run_action(func(): return session.act(mode,point)); return
	var actor: Dictionary = session.at(point)
	if session.wanderer(actor): return
	if not actor.is_empty():
		if actor.enemy:
			if session.manual_mode:
				if session.attack_preview(point).is_empty(): show_enemy_info(actor)
				else: run_action(func(): return session.act("ATTACK",point))
			else: run_action(func(): return session.act("ATTACK",point))
		else:
			# `selected` is a party index, and a recruit's id is its roster id: the
			# two only look alike for the three the run started with.
			var index: int = session.party.find(actor)
			if index >= 0: select_actor(index)
		return
	if maxi(absi(point.x-session.party[session.selected].pos.x),absi(point.y-session.party[session.selected].pos.y)) > 1:
		if navigation.start(session,point): navigation_tick()
		else: notice = "이동 불가"; refresh()
	else: run_action(func(): return session.act("MOVE",point))

func inspect_cell(point: Vector2i) -> void:
	if session == null or not session.manual_mode or not session.floor_state.visible.has(point): return
	var actor: Dictionary = session.at(point)
	if not actor.is_empty() and actor.enemy: show_enemy_info(actor)

func show_enemy_info(enemy: Dictionary) -> void:
	if enemy.is_empty() or enemy.hp <= 0: return
	clear(modal_content)
	var values: Dictionary = Session.CombatStats.stats(session,enemy)
	var title := label(modal_content,str(enemy.name),20); title.name = "EnemyInfo"
	label(modal_content,"HP %d/%d   AC %d   EV %d   속도 %d" % [int(enemy.hp),int(enemy.max_hp),int(values.ac),int(values.ev),int(values.delay)],14)
	var preview: Dictionary = session.attack_preview(enemy.pos)
	if not preview.is_empty():
		label(modal_content,"명중 %d%%   피해 %d–%d   %d tick" % [int(preview.chance),int(preview.damage_min),int(preview.damage_max),int(preview.time)],14)
		var attack := button(modal_content,"공격",func(): details_popup.hide(); run_action(func(): return session.act("ATTACK",enemy.pos)))
		attack.name = "InspectAttack"
	button(modal_content,"닫기",func(): details_popup.hide())
	details_popup.popup_centered()

func focus_enemy(point: Vector2i) -> void:
	var target: Dictionary = session.at(point)
	if target in session.combat_enemies() and session.floor_state.visible.has(point):
		session.command_target = target.id; session.party_command = "ATTACK_TARGET"
		notice = "집중 공격"

## One line of who this npc is: the nouns of its two social facets.
func npc_personality(npc: Dictionary) -> String:
	var words: Array = []
	for facet in ["X","A"]:
		var terms: Dictionary = Session.Hexaco.STYLE_AXES[facet]
		words.append(str(terms.high_noun if npc.profile.value(facet) >= 500 else terms.low_noun))
	return " · ".join(words)

## The npc popup: who it is, what it is doing, and the two things the party has
## to offer — a share of the food and a place in the line.
func show_npc(npc: Dictionary) -> void:
	stop_navigation(); clear(modal_content)
	modal_content.custom_minimum_size.y = 0
	var page := VBoxContainer.new(); page.name = "NpcPopup"; modal_content.add_child(page)
	var talk: Dictionary = Session.Recruit.dialogue(session,npc)
	label(page,str(npc.name),20)
	label(page,npc_personality(npc),14)
	var doing: String = str(npc.get("activity",""))
	if not doing.is_empty(): label(page,doing,14)
	label(page,"HP %d/%d" % [npc.hp,npc.max_hp],14)
	label(page,str(talk.line),15)
	var ask := button(page,"동행 제안",func(): propose_npc(npc),bool(talk.can_propose))
	ask.name = "ProposeButton"
	var share := button(page,"식량 1 나누기 · 보유 %d" % session.food,func(): details_popup.hide(); run_action(func(): return session.aid(npc)),bool(talk.can_aid))
	share.name = "AidButton"
	var close := button(page,"닫기",func(): details_popup.hide())
	close.name = "CloseNpc"
	details_popup.popup_centered()

## The ask itself always goes through: what comes back is the npc's answer, and
## the sentence it answers with is the notice.
func propose_npc(npc: Dictionary) -> void:
	details_popup.hide()
	# A lambda captures its locals by value, so the answer comes back on the node.
	proposal_line = ""
	run_action(func(): proposal_line = str(session.propose(npc).line); return true)
	notice = proposal_line

## An npc that asks to come along stops the run and waits for an answer; the
## popup lives exactly as long as the offer does.
func update_offer_popup() -> void:
	if session == null or not is_instance_valid(offer_popup): return
	var standing: Array = session.npcs.filter(func(n): return n.id == session.pending_offer) if session.pending_offer >= 0 else []
	if standing.is_empty():
		offer_popup.hide(); return
	var npc: Dictionary = standing[0]
	session.auto.running = false
	stop_navigation()
	stop_text = "%s이(가) 말을 겁니다" % npc.name
	clear(offer_content)
	label(offer_content,str(npc.name),20)
	label(offer_content,str(Session.Recruit.dialogue(session,npc).line),15)
	var accept := button(offer_content,"동행",func(): offer_popup.hide(); run_action(func(): return session.answer_offer(true)),session.alive().size() < Session.Recruit.MAX_PARTY)
	accept.name = "OfferAccept"
	var refuse := button(offer_content,"거절",func(): offer_popup.hide(); run_action(func(): return session.answer_offer(false)))
	refuse.name = "OfferDecline"
	offer_popup.popup_centered()

func show_map() -> void:
	stop_navigation()
	if session == null or not session.on_floor(): return
	map_view.session = session; map_view.queue_redraw(); map_popup.popup_centered()

func show_curio(point: Vector2i) -> void:
	stop_navigation(); clear(modal_content)
	var feature: Dictionary = session.floor_state.features.get(point,{})
	var def: Dictionary = Session.Curios.definition(feature)
	if def.is_empty(): return
	label(modal_content,def.name,22)
	if feature.used: label(modal_content,"조사 완료",16)
	else:
		for id in def.options:
			var choice: Dictionary = def.options[id]
			var caption: String = choice.label
			var reason: String = Session.Curios.error(session,point,id)
			button(modal_content,caption,func(): details_popup.hide(); run_action(func(): return Session.Curios.resolve(session,point,id)),reason.is_empty())
			var hint := label(modal_content,reason if not reason.is_empty() else choice.get("warning",""),14)
			hint.custom_minimum_size.x = popup_width(); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(modal_content,"지나가기",func(): details_popup.hide())
	details_popup.popup_centered()










func build_result_card() -> void:
	var card := VBoxContainer.new(); card.name = "ResultCard"; card.size_flags_vertical = SIZE_EXPAND_FILL; root_layout.add_child(card)
	label(card,"%d층에서 쓰러졌다" % session.depth,24)
	label(card,"점수 %d · 라운드 %d · 처치 %d" % [session.score,session.world_time/100,session.run_stats.kills],16)
	for actor in session.party.slice(1):
		label(card,"%s · %s" % [actor.name,"생존" if actor.hp > 0 else "%d층에서 전사" % session.depth],14)
	label(card,"실수 %d" % int(session.run_stats.mistakes),14)
	companion_history(card)
	var start := button(card,"새 Run",new_run); start.name = "NewRun"
	button(card,"시작 화면",func(): session = null; refresh())

## Who walked with the party this run, where they joined and whether they came
## back out (스펙 §1.2).
func companion_history(list: VBoxContainer) -> void:
	var rows: Array = session.companion_rows()
	if rows.is_empty(): return
	label(list,"동료 이력",15)
	for row in rows:
		label(list,"%s · %d층 합류 · %s" % [row.name,int(row.joined_floor),"생존" if row.alive else "전사"],13)


func modal(title: String, body: String) -> void:
	clear(modal_content); label(modal_content,title,18)
	var text := RichTextLabel.new(); text.text = body; text.custom_minimum_size = Vector2(popup_width(),210); text.size_flags_vertical = SIZE_EXPAND_FILL; modal_content.add_child(text)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()


func show_character(index: int, tab: String = "상태") -> void:
	stop_navigation()
	tactics_actor = clampi(index,0,session.party.size()-1); character_tab = tab
	clear(modal_content)
	var list: VBoxContainer = CharacterUI.shell(self,tab)
	var actor: Dictionary = session.party[tactics_actor]
	match tab:
		"상태": CharacterUI.status(self,list,actor)
		"숙련": CharacterUI.mastery(self,list,actor)
		"파츠": CharacterUI.parts(self,list,actor)
		"성격": CharacterUI.personality(self,list,actor)
		"기억": CharacterUI.memories(self,list,actor)
	details_popup.popup_centered(Vector2i(get_viewport_rect().size))

func show_mastery_detail(index: int, axis: String) -> void:
	if axis not in CharacterUI.Mastery.AXES: return
	tactics_actor = clampi(index,0,session.party.size()-1); character_tab = "숙련"
	clear(modal_content)
	var list: VBoxContainer = CharacterUI.shell(self,"숙련")
	CharacterUI.mastery_detail(self,list,session.party[tactics_actor],axis)
	details_popup.popup_centered(Vector2i(get_viewport_rect().size))

func show_tactics() -> void:
	show_character(tactics_actor,"파츠")

func open_rule(index: int) -> void:
	tactics_expanded = index
	clear(item_detail)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(popup_width(),minf(400,size.y-120))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; item_detail.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(list)
	build_skill_rules(list)
	item_popup.popup_centered()

func build_skill_rules(list: VBoxContainer) -> void:
	var actor: Dictionary = session.party[tactics_actor]
	label(list,"스킬 사용 순서",14)
	for index in range(actor.rules.size()):
		if index != tactics_expanded: continue
		var rule: Dictionary = actor.rules[index]
		var card := CharacterUI.card(list,"")
		var header := HBoxContainer.new(); card.add_child(header)
		label(header,Session.Rules.skill(rule.skill).name,18)
		var enabled := CheckButton.new(); enabled.text = "자동"; enabled.button_pressed = rule.enabled; enabled.custom_minimum_size.y = 44; header.add_child(enabled)
		enabled.toggled.connect(func(value): change_tactic_rule(index,"enabled",value))
		var summary := label(card,Session.Rules.summary(rule),11); summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if tactics_expanded != index: continue
		var def: Dictionary = Session.Rules.skill(rule.skill)
		tactic_pick(card,"누구에게?",def.targets,Session.Rules.TARGET_NAMES,rule.target,func(value): change_tactic_rule(index,"target",value))
		tactic_pick(card,"언제?",def.conditions,Session.Rules.WHEN_NAMES,rule.when,func(value): change_tactic_rule(index,"when",value))
		if rule.when in ["HP","STATUS"]:
			tactic_pick(card,"누구 기준?",["SELF"] if rule.target == "SELF" else ["SELF","TARGET"],{"SELF":"자신","TARGET":"대상"},"SELF" if rule.target == "SELF" else rule.subject,func(value): change_tactic_rule(index,"subject",value))
		if rule.when == "HP":
			var threshold := label(card,"체력 %d%%" % rule.threshold)
			var slider := HSlider.new(); slider.min_value = 10; slider.max_value = 100; slider.step = 10; slider.value = rule.threshold; slider.custom_minimum_size = Vector2(280,44); card.add_child(slider)
			slider.value_changed.connect(func(value): session.update_rule(tactics_actor,index,"threshold",int(value)); threshold.text = "체력 %d%%" % int(value); refresh())
			tactic_pick(card,"기준",["BELOW","ABOVE"],{"BELOW":"이하","ABOVE":"이상"},rule.comparison,func(value): change_tactic_rule(index,"comparison",value))
		if rule.when == "STATUS":
			tactic_pick(card,"어떤 상태?",Session.Rules.STATUS_NAMES.keys(),Session.Rules.STATUS_NAMES,rule.status,func(value): change_tactic_rule(index,"status",value))
		var ordering := HBoxContainer.new(); card.add_child(ordering)
		button(ordering,"↑ 먼저 사용",func(): session.reorder_rule(tactics_actor,index,-1); refresh(); show_tactics(); open_rule(index-1),index > 0)
		button(ordering,"↓ 나중에 사용",func(): session.reorder_rule(tactics_actor,index,1); refresh(); show_tactics(); open_rule(index+1),index < actor.rules.size()-1)
	var basic := VBoxContainer.new(); list.add_child(basic)
	label(basic,"기본 행동",14)
	tactic_pick(basic,"일반 공격 대상",Session.Rules.BASIC_TARGETS,Session.Rules.TARGET_NAMES,actor.basic_target,change_basic_target)
	button(list,"행동방침 기본값 복원",func(): session.reset_rules(tactics_actor); refresh(); show_tactics())
	button(list,"완료",func(): item_popup.hide())

func change_basic_target(value: String) -> void:
	if session.set_basic_target(tactics_actor,value): refresh(); show_tactics(); open_rule(tactics_expanded)

func change_tactic_rule(index: int, field: String, value: Variant) -> void:
	if session.update_rule(tactics_actor,index,field,value): refresh(); show_tactics(); open_rule(index)

func tactic_pick(parent: Node, title: String, values: Array, names: Dictionary, current: String, changed: Callable) -> void:
	label(parent,title,12)
	var pick := OptionButton.new(); pick.custom_minimum_size = Vector2(280,44)
	for value in values: pick.add_item(names[value])
	pick.select(maxi(0,values.find(current))); parent.add_child(pick)
	pick.item_selected.connect(func(index): changed.call(values[index]))

func show_supplies() -> void:
	stop_navigation()
	clear(modal_content); label(modal_content,"공용 가방",18); build_inventory()

func gear_name(item: Dictionary, slot: String) -> String:
	if slot == "shield": return "방패"
	var catalog: Dictionary = Session.CombatStats.content.weapons if slot == "weapon" else Session.CombatStats.content.armours if slot == "armour" else Session.CombatStats.content.rings if slot == "ring" else {}
	var id: String = str(item.get("type",""))
	return str(catalog.get(id,{}).get("name",id))

func inventory_rows() -> Array:
	var rows: Array = []
	var descriptions := ["HP +20","스트레스 -25","HP +5 · 스트레스 -10","목재 점화 · 사거리 4","물기 · 사거리 4"]
	for i in range(5):
		if session.supplies[i] > 0: rows.append({"id":"supply:%d"%i,"label":Session.SUPPLY_NAMES[i],"quantity":session.supplies[i],"category":"소모품","slot":i,"description":descriptions[i],"icon":Art.item(i)})
	for i in range(session.gear_bag.size()):
		var item: Dictionary = session.gear_bag[i]
		var slot: String = session.gear_slot(item)
		if slot.is_empty(): continue
		var name: String = gear_name(item,slot)
		rows.append({"id":"gear:%d"%i,"label":name,"quantity":1,"category":"장비","gear_index":i,"gear_slot":slot,"description":name})
	for i in range(session.party.size()):
		var actor: Dictionary = session.party[i]
		for slot in ["weapon","armour","shield","ring"]:
			var equipped: Dictionary = actor.gear.get(slot,{})
			if equipped.is_empty(): continue
			var name: String = gear_name(equipped,slot)
			rows.append({"id":"equipped:%d:%s"%[i,slot],"label":name,"quantity":1,"category":"장비","equipped_member":i,"equipped_slot":slot,"gear_slot":slot,"description":actor.name+" · 장착 중"})
	for id in Session.Abilities.DEFINITIONS:
		if session.parts_bag.get(id,0) <= 0: continue
		var def: Dictionary = Session.Abilities.DEFINITIONS[id]
		rows.append({"id":id,"label":def.item,"quantity":session.parts_bag[id],"category":"파츠","description":def.description,"icon":Art.item(int(def.icon))})
	rows.append({"id":"food","label":"식량","quantity":session.food,"category":"자원","description":"야영","icon":Art.navigation(3)})
	return rows

func build_inventory() -> void:
	var filters := HBoxContainer.new(); modal_content.add_child(filters)
	for category in ["전체","소모품","장비","파츠","자원"]:
		var pick := button(filters,category,func(): inventory_filter = category; show_supplies())
		pick.toggle_mode = true; pick.button_pressed = category == inventory_filter
	var rows: Array = inventory_rows().filter(func(r): return inventory_filter == "전체" or r.category == inventory_filter)
	label(modal_content,"%s · %d종 보유" % [inventory_filter,rows.size()],12)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(popup_width(),minf(300,size.y-310)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
	var grid := GridContainer.new(); grid.columns = 4; grid.size_flags_horizontal = SIZE_EXPAND_FILL; grid.add_theme_constant_override("h_separation",4); grid.add_theme_constant_override("v_separation",4); scroll.add_child(grid)
	inventory_slots.clear()
	for i in range(maxi(12,int(ceil(rows.size()/4.0))*4)):
		var slot = InventorySlot.new(); grid.add_child(slot)
		var row: Dictionary = rows[i] if i < rows.size() else {}
		slot.configure(row,row.get("id","") == inventory_selected); inventory_slots.append(slot)
		if not row.is_empty(): slot.pressed.connect(func(): show_item_detail(row.id))
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

func show_item_detail(id: String) -> void:
	var matches: Array = inventory_rows().filter(func(r): return r.id == id)
	if matches.is_empty(): item_popup.hide(); show_supplies(); return
	var row: Dictionary = matches[0]; inventory_selected = id
	for slot in inventory_slots:
		if is_instance_valid(slot): slot.selected = slot.row.get("id","") == id; slot.queue_redraw()
	clear(item_detail); label(item_detail,"%s × %d" % [row.label,row.quantity],18)
	var info := label(item_detail,row.description,12); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; info.custom_minimum_size.x = minf(290,size.x-32)
	if row.category == "소모품":
		if row.slot in [3,4]:
			button(item_detail,"사용 · 바닥 선택",func(): item_popup.hide(); details_popup.hide(); choose_item(row.slot),session.on_floor())
		else:
			for i in range(session.party.size()):
				button(item_detail,session.party[i].name+"에게 사용",func(): item_popup.hide(); details_popup.hide(); run_action(func(): return session.use_supply(row.slot,Vector2i(-1,-1),i)),session.phase in ["EXPLORE","BATTLE","CAMP"] and session.party[i].hp > 0)
	elif row.category == "장비":
		if row.has("equipped_member"):
			var member: int = int(row.equipped_member)
			button(item_detail,"해제",func():
				if session.unequip_gear(member,str(row.equipped_slot)): item_popup.hide(); refresh(); show_supplies(),session.phase == "CAMP")
		else:
			var gear: Dictionary = session.gear_bag[int(row.gear_index)]
			for i in range(session.party.size()):
				var actor: Dictionary = session.party[i]
				button(item_detail,actor.name+" 장착",func():
					if session.equip_gear(i,gear): item_popup.hide(); refresh(); show_supplies(),session.phase == "CAMP" and actor.hp > 0)
	elif row.category == "파츠":
		for i in range(session.party.size()):
			var member: Dictionary = session.party[i]
			for slot in range(2):
				button(item_detail,"%s %d번 장착" % [member.name,slot+1],equip_from_bag.bind(i,slot,id),session.phase == "CAMP" and member.hp > 0 and id not in member.equipped_abilities)
	button(item_detail,"닫기",func(): item_popup.hide()); item_popup.popup_centered(); item_popup.grab_focus()

func popup_list() -> VBoxContainer:
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(popup_width(),minf(330,size.y-300)); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; modal_content.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(list)
	return list

func equip_from_bag(member: int, slot: int, id: String) -> void:
	if session.equip_part(member,slot,id): item_popup.hide(); refresh(); show_supplies()
