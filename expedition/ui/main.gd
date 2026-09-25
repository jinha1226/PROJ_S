extends Control
const Session = preload("res://expedition/run/session.gd")
const Presentation = preload("res://expedition/ui/battle_presentation.gd")
const MapView = preload("res://expedition/ui/map_view.gd")
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
const ArenaSetup = preload("res://expedition/ui/screens/arena_setup.gd")
const StartScreen = preload("res://expedition/ui/screens/start_screen.gd")
const FloorHud = preload("res://expedition/ui/screens/floor_hud.gd")
const CampScreen = preload("res://expedition/ui/screens/camp_screen.gd")
const ResultCard = preload("res://expedition/ui/screens/result_card.gd")
const Popups = preload("res://expedition/ui/screens/popups.gd")
const AutoBattleHud = preload("res://expedition/ui/screens/autobattle_hud.gd")
const Art = preload("res://expedition/art/mobile_art.gd")
const Banners = preload("res://expedition/ui/screens/banners.gd")
var portrait_gesture = preload("res://expedition/legacy/portrait_gesture.gd").new()
var navigation = preload("res://expedition/level/exploration_navigation.gd").new()
const NAVIGATION_STEP_SECONDS := 0.11
var navigation_clock := 0.0
var view_side := 11
var log_popup: PopupPanel
var log_filter := "전체"
var auto_explore_button: Button
var inventory_filter := "전체"
var inventory_actor := 0
## The starting kit the picker has on it, spent when a run departs.
var kit_choice := "sword"
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
var pending_item := ""
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var skin := Theme.new(); skin.default_font = FONT; skin.default_font_size = 12
	for state in ["normal","hover","pressed","focus","disabled"]:
		var frame_state: int = {"normal":0,"hover":1,"pressed":2,"focus":1,"disabled":3}[state]
		var box := StyleBoxTexture.new(); box.texture = Art.ui_frame(frame_state)
		box.texture_margin_left = 10; box.texture_margin_right = 10
		box.texture_margin_top = 10; box.texture_margin_bottom = 10
		box.content_margin_left = 8; box.content_margin_right = 8
		box.content_margin_top = 5; box.content_margin_bottom = 5
		skin.set_stylebox(state,"Button",box)
	skin.set_color("font_color","Button",Color("e0d3b9"))
	skin.set_stylebox("panel","PopupPanel",CharacterUI.surface(Color("100f0d")))
	theme = skin
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,0 if side in ["left","right"] else 8)
	add_child(margin)
	root_layout = VBoxContainer.new(); root_layout.add_theme_constant_override("separation",4); margin.add_child(root_layout)
	parked = Node.new(); parked.name = "Parked"; add_child(parked)
	map_popup = PopupPanel.new(); add_child(map_popup)
	var map_box := VBoxContainer.new(); map_box.custom_minimum_size = Vector2(300,360); map_popup.add_child(map_box)
	map_view = MapView.new(); map_view.session = session; map_view.ui_font = FONT; map_view.minimum_side = 280
	map_box.add_child(map_view)
	var map_legend := label(map_box,"▲ 현재 위치     › 계단     ◆ 동료",12)
	map_legend.name = "MapLegend"; map_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button(map_box,"닫기",func(): map_popup.hide())
	details_popup = PopupPanel.new(); add_child(details_popup)
	modal_content = VBoxContainer.new(); modal_content.custom_minimum_size = Vector2(popup_width(),210); details_popup.add_child(modal_content)
	# Popup content is rebuilt by every show_* on open; clearing on hide raced with a same-frame rebuild.
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
	set_action_button_text(auto_explore_button,"탐색" if session != null and session.manual_mode else "자동탐험")

func popup_open() -> bool:
	return details_popup.visible or map_popup.visible or log_popup.visible or item_popup.visible or is_instance_valid(offer_popup) and offer_popup.visible

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
	if navigation_clock >= NAVIGATION_STEP_SECONDS and not navigation_camera_busy():
		navigation_clock = 0; navigation_tick()

func navigation_camera_busy() -> bool:
	return session != null and not session.party.is_empty() and is_instance_valid(board) \
		and board.walk_actor_id == int(session.party[0].id) and board.walk_elapsed < board.walk_duration

func navigation_tick() -> void:
	if navigation_camera_busy():
		if session.phase != "EXPLORE" or not session.party_enemies().is_empty(): stop_navigation()
		return
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
	elif key == KEY_TAB:
		FloorHud.arm_attack(self)
		get_viewport().set_input_as_handled()

func toggle_explore() -> void:
	if navigation.active: stop_navigation(); return
	mode = ""; pending_item = ""; reservation_actor = -1
	if navigation.explore(session): set_action_button_text(auto_explore_button,"중지")
	else: notice = "주변에 적 있음"; refresh()

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
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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

func action_button(parent: Node, text: String, texture: Texture2D, callback: Callable, enabled: bool = true) -> Button:
	var node := button(parent,text,callback,enabled)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.custom_minimum_size.y = 54
	for state in ["font_color","font_hover_color","font_pressed_color","font_disabled_color","font_focus_color"]:
		node.add_theme_color_override(state,Color.TRANSPARENT)
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_child(picture)
	picture.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	picture.offset_left = 5; picture.offset_right = -5
	picture.offset_top = 3; picture.offset_bottom = 31
	var caption := label(node,text,12)
	caption.name = "ActionCaption"
	caption.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	caption.offset_left = 2; caption.offset_right = -2
	caption.offset_top = -20; caption.offset_bottom = -4
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color",Color("e5e7e8") if enabled else Color("80888c"))
	return node

func set_action_button_text(action: Button, value: String) -> void:
	if not is_instance_valid(action): return
	action.text = value
	var caption: Label = action.get_node_or_null("ActionCaption")
	if caption != null: caption.text = value

func mark_selected(button_node: Button) -> void:
	var style := button_node.get_theme_stylebox("normal").duplicate()
	if style is StyleBoxTexture:
		style.texture = Art.ui_frame(5)
	elif style is StyleBoxFlat:
		style.border_color = Color("e9c575")
		style.set_border_width_all(2)
	button_node.add_theme_stylebox_override("normal",style)

func gauge(parent: Node, value: int, maximum: int, color: Color) -> void:
	var bar := ProgressBar.new(); bar.max_value = maximum; bar.value = value; bar.show_percentage = false
	bar.custom_minimum_size.y = 4; bar.mouse_filter = MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new(); fill.bg_color = color
	var background := StyleBoxFlat.new(); background.bg_color = Color("0b1016")
	bar.add_theme_stylebox_override("fill",fill); bar.add_theme_stylebox_override("background",background); parent.add_child(bar)

func resource_gauge(parent: Button, id: String, value: int, color: Color, hint: String) -> void:
	var bar := ProgressBar.new(); bar.name = id; bar.max_value = 100; bar.value = clampi(value,0,100)
	bar.show_percentage = false; bar.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(bar); bar.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	bar.offset_left = 4; bar.offset_right = -4; bar.offset_top = -7; bar.offset_bottom = -3
	var fill := StyleBoxFlat.new(); fill.bg_color = color
	var background := StyleBoxFlat.new(); background.bg_color = Color("080c10")
	bar.add_theme_stylebox_override("fill",fill); bar.add_theme_stylebox_override("background",background)
	parent.custom_minimum_size.y = 48; parent.tooltip_text = hint
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := parent.get_theme_stylebox(state).duplicate()
		if style is StyleBoxFlat:
			style.content_margin_bottom = 8
		parent.add_theme_stylebox_override(state,style)

func modal(title: String, body: String) -> void:
	clear(modal_content); label(modal_content,title,18)
	var text := RichTextLabel.new(); text.text = body; text.custom_minimum_size = Vector2(popup_width(),210); text.size_flags_vertical = SIZE_EXPAND_FILL; modal_content.add_child(text)
	button(modal_content,"닫기",func(): details_popup.hide()); details_popup.popup_centered()

## The router: which screen the run's state asks for, and the board and minimap
## that are parked between screens. The screens themselves are in ui/screens/.
func refresh() -> void:
	if is_instance_valid(board) and board.is_presenting(): return
	call_deferred("show_banners")
	Popups.update_offer_popup(self)
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
		StartScreen.build_start_screen(self); return
	map_view.session = session; map_view.queue_redraw()
	if session.phase == "CAMP": CampScreen.build_camp_screen(self); show_choice_if_pending(); return
	if session.phase == "DEFEAT": ResultCard.build_result_card(self); return
	FloorHud.build(self,elapsed,impact_elapsed)
	show_choice_if_pending()

func show_choice_if_pending() -> void:
	if session != null and not session.pending_choice.is_empty(): Popups.show_choice(self)

func finish_presentation() -> void:
	action_effects = []; reset_effects = true; auto_clock = 0.0
	if session.manual_mode:
		if not session.in_combat(): report_battle()
		refresh(); return
	var reason: String = session.auto_stop_reason()
	if not reason.is_empty():
		session.auto.running = false
		AutoBattleHud.note_stop(self,reason)
	if not session.in_combat():
		session.auto.running = false
		report_battle()
	refresh()

func run_action(callback: Callable, navigating: bool = false) -> void:
	if is_instance_valid(board) and board.is_presenting(): return
	if not navigating: stop_navigation()
	var hero_before: Vector2i = session.party[0].pos if session != null and not session.party.is_empty() else Vector2i(-1,-1)
	session.effects.clear()
	var recorder = Presentation.new()
	var show_battle: bool = not session.manual_mode and is_processing() and session.phase == "BATTLE" and not session.party_enemies().is_empty()
	if show_battle:
		recorder.begin(session); session.presentation = recorder
	var accepted: bool = callback.call()
	pending_attack = {}
	notice = "" if accepted else "사용 불가"
	if accepted:
		mode = ""; pending_item = ""; reservation_actor = -1
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
	if accepted and is_instance_valid(board) and session.on_floor() and not session.party.is_empty() and hero_before != session.party[0].pos:
		board.animate_walk(int(session.party[0].id),hero_before,session.party[0].pos,NAVIGATION_STEP_SECONDS)

func queue_action(kind: String, point: Vector2i) -> void:
	if session.reserve_action(reservation_actor,kind,point):
		notice = session.party[reservation_actor].name+" · 다음 행동 예약 완료"
		reservation_actor = -1; mode = ""
	else: notice = "예약 불가"
	refresh()

func on_cell(point: Vector2i) -> void:
	if session == null or not session.on_floor(): return
	stop_navigation()
	if mode == "COMMAND_TARGET":
		var marked: Dictionary = session.at(point)
		if not marked.is_empty() and session.issue_party_command("ATTACK_TARGET",int(marked.id)):
			mode = ""; notice = ""; refresh()
		return
	if session.manual_mode and mode == "ATTACK":
		var target: Dictionary = session.at(point)
		if not target.is_empty() and (target.enemy or session.wanderer(target)) and not session.attack_preview(point).is_empty():
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
		if session.wanderer(wanderer) and not wanderer.get("summoned",false):
			if wanderer.get("hostile",false):
				if session.attack_preview(point).is_empty(): Popups.show_enemy_info(self,wanderer)
				else: run_action(func(): return session.act("ATTACK",point))
			elif session.melee_reach(session.party[session.selected].pos,point): Popups.show_npc(self,wanderer)
			else: notice = "%s · %s" % [wanderer.name,wanderer.get("activity","")] if not str(wanderer.get("activity","")).is_empty() else str(wanderer.name); refresh()
			return
		if feature.get("kind","") == "curio": Popups.show_curio(self,point); return
		if feature.get("kind","") == "stairs" and session.distance(session.party[session.selected].pos,point) <= 1: show_stairs(); return
		if not feature.is_empty() and feature.get("kind","") != "item" and session.distance(session.party[session.selected].pos,point) <= 1:
			run_action(func(): return session.floor_state.interact(session,point)); return
	if not pending_item.is_empty(): run_action(func(): return session.use_item(pending_item,point)); return
	if mode.begins_with("CAST:"):
		var spell_id := mode.trim_prefix("CAST:")
		# A refused cast says why rather than swallowing the tap.
		var refusal: String = Session.Spells.refusal(session,session.party[0],spell_id,point)
		if not refusal.is_empty():
			notice = refusal; refresh(); return
		run_action(func(): return session.cast(spell_id,point)); return
	if not mode.is_empty() and mode != "ATTACK": run_action(func(): return session.act(mode,point)); return
	var actor: Dictionary = session.at(point)
	if session.wanderer(actor): return
	if not actor.is_empty():
		if actor.enemy:
			if session.manual_mode:
				if session.attack_preview(point).is_empty(): Popups.show_enemy_info(self,actor)
				else: run_action(func(): return session.act("ATTACK",point))
			else: run_action(func(): return session.act("ATTACK",point))
		else:
			var index: int = session.party.find(actor)
			if index >= 0 and actor != session.party[session.selected] and session.walk_reach(session.party[session.selected].pos,point):
				run_action(func(): return session.act("SWAP",point))
			elif index >= 0 and not session.manual_mode: select_actor(index)
		return
	if maxi(absi(point.x-session.party[session.selected].pos.x),absi(point.y-session.party[session.selected].pos.y)) > 1:
		if navigation.start(session,point): navigation_tick()
		else: notice = "이동 불가"; refresh()
	else: run_action(func(): return session.act("MOVE",point))

func focus_enemy(point: Vector2i) -> void:
	var target: Dictionary = session.at(point)
	if target in session.combat_enemies() and session.issue_party_command("ATTACK_TARGET",int(target.id)):
		notice = "집중 공격"

## The screens keep their entry points on the node: the tests, the signals and
## the sibling screens all reach them through `main`.
func new_run() -> void: StartScreen.new_run(self)
func depart() -> void: StartScreen.depart(self)
func select_actor(index: int) -> void: FloorHud.select_actor(self,index)
func choose_item(kind: String) -> void: FloorHud.choose_item(self,kind)
func inspect_cell(point: Vector2i) -> void: Popups.inspect_cell(self,point)
func show_menu() -> void: Popups.show_menu(self)
func show_logs() -> void: Popups.show_logs(self)
func show_map() -> void: Popups.show_map(self)
func show_supplies() -> void: Popups.show_supplies(self)
func show_item_detail(id: String) -> void: Popups.show_item_detail(self,id)
func inventory_rows() -> Array: return Popups.inventory_rows(self)
func show_character(index: int, tab: String = "상태") -> void: Popups.show_character(self,index,tab)
func show_tactics() -> void: Popups.show_tactics(self)
func open_rule(index: int) -> void: Popups.open_rule(self,index)
func change_basic_target(value: String) -> void: Popups.change_basic_target(self,value)
func change_tactic_rule(index: int, field: String, value: Variant) -> void: Popups.change_tactic_rule(self,index,field,value)
func show_stairs() -> void: CampScreen.show_stairs(self)
func auto_interval() -> float: return AutoBattleHud.auto_interval(self)
func auto_tick() -> void: AutoBattleHud.auto_tick(self)
func check_stop() -> void: AutoBattleHud.check_stop(self)
func report_battle() -> void: AutoBattleHud.report_battle(self)
func show_battle_report() -> void: AutoBattleHud.show_battle_report(self)

func show_banners() -> void: Banners.show_next(self)
