class_name BattleTimelineBar
extends Control

## Top bidirectional action timeline (allies left, enemies right, center = act).
## Presentation only: never calls commit/skill APIs; interpolates <= 0.10 s between
## committed states. Spec: docs/concepts/BATTLE_ACTION_TIMELINE_HANDOFF.ko.md 3-6.

signal entry_tapped(entity_ids: Array)
signal pointer_held(held: bool)

const Presenter = preload("res://playtest/battle_timeline_presenter.gd")
const Assets = preload("res://playtest/fixed_front_topdown_assets.gd")
const UiSkin = preload("res://playtest/dark_pixel_ui_skin.gd")
const BAR_HEIGHT := 48.0
const CENTER_WIDTH := 24.0
const PORTRAIT_SIZE := 26.0
const TOUCH_SIZE := 48.0
const LERP_DURATION_MSEC := 100
const FLASH_DURATION_MSEC := 800
const PORTRAIT_CROP := Rect2(48, 16, 160, 160)
const ALLY_FRAME := Color("#508cb0")
const LABEL_FONT_SIZE := 11
const PORTRAIT_TOP := 12.0
const TAG_BASELINE := 47.0
const HEADER_BASELINE := 10.0

var _state: Dictionary = {}
var _layout: Dictionary = {}
var _target_x: Dictionary = {}     # item key -> target x
var _shown_x: Dictionary = {}      # item key -> currently drawn x
var _from_x: Dictionary = {}       # item key -> x the running interpolation left from
var _lerp_started_msec := -1
var _blocked := false
var _blocked_at_msec := -1
var _taps_enabled := true
var _flash_until := {}             # entity_id -> msec
var _held_key := -1               # representative entity of the pressed item
var _pointer_down := false


## Pure layout: the same dictionary in always yields the same geometry out, so the
## acceptance test can call it without a node in the tree. No member state is read
## or written here.
static func layout_spec(state: Dictionary, width: float, height: float = BAR_HEIGHT) -> Dictionary:
	var center := Rect2((width - CENTER_WIDTH) * 0.5, 0.0, CENTER_WIDTH, height)
	var left_rail := Rect2(TOUCH_SIZE * 0.5, 0.0, maxf(0.0, center.position.x - TOUCH_SIZE * 0.5), height)
	var right_rail := Rect2(center.end.x, 0.0, maxf(0.0, width - center.end.x - TOUCH_SIZE * 0.5), height)
	var world_time := int(state.get("world_time", 0))
	var by_side := {"ALLY": [], "ENEMY": []}
	# A side that parks an item of unknown timing at its outer end keeps that spot
	# clear of the timed scale, so two items that must not merge can never claim
	# overlapping touch squares either.
	var parked := {"ALLY": false, "ENEMY": false}
	for entry in state.get("entries", []):
		if entry is Dictionary and _moment_of(entry) == null:
			parked[_side_of(entry)] = true
	for entry in state.get("entries", []):
		if not entry is Dictionary: continue
		var side := _side_of(entry)
		var moment = _moment_of(entry)
		var timed := moment != null
		var remaining := -1
		var ratio := 1.0
		if timed:
			remaining = maxi(0, int(moment) - world_time)
			ratio = clampf(float(remaining) / float(Presenter.HORIZON_WORLD_TIME), 0.0, 1.0)
		var rail := left_rail.size.x if side == "ALLY" else right_rail.size.x
		if timed and bool(parked[side]): rail = maxf(0.0, rail - TOUCH_SIZE)
		var x := center.position.x - ratio * rail
		if side == "ENEMY": x = center.end.x + ratio * rail
		by_side[side].append({"entity_ids": [int(entry.get("entity_id", -1))], "side": side, "x": x,
			"marker": str(entry.get("marker", "")), "portrait_key": str(entry.get("portrait_key", "")),
			"status": str(entry.get("status", "")), "is_next": bool(entry.get("is_next_candidate", false)),
			"out_of_range": timed and remaining > Presenter.HORIZON_WORLD_TIME,
			"confidence": str(entry.get("timing_confidence", "")), "timed": timed,
			"group_keys": [str(entry.get("group_key", ""))], "group_label": "", "remaining": remaining,
			"touch": Rect2(x - TOUCH_SIZE * 0.5, 0.0, TOUCH_SIZE, height)})
	var items: Array = _merge_side(by_side.ALLY) + _merge_side(by_side.ENEMY)
	items.sort_custom(_left_to_right)
	for item in items:
		item["touch"] = Rect2(clampf(float(item.x) - TOUCH_SIZE * 0.5, 0.0, maxf(0.0, width - TOUCH_SIZE)),
			0.0, TOUCH_SIZE, height)
	var hidden := int(state.get("hidden_visible_enemy_count", 0))
	return {"center": center, "left_rail": left_rail, "right_rail": right_rail, "items": items,
		"hidden_label": "+%d" % hidden if hidden > 0 else ""}


static func _side_of(entry: Dictionary) -> String:
	return "ENEMY" if str(entry.get("side", "ALLY")) == "ENEMY" else "ALLY"


## Authoritative moment (spec 4): the core's earliest real chance. An enemy without
## eligible_at has none -- its raw busy row is not a moment, so the item is parked at
## the outer end instead of being drawn at a made-up time.
static func _moment_of(entry: Dictionary):
	var moment = entry.get("eligible_at")
	if moment == null and _side_of(entry) == "ALLY": moment = entry.get("ready_at")
	return moment


## Same side only: touch squares that overlap collapse into one item so no finger
## target is ambiguous. The representative is the earliest member, and an item with
## no known moment never merges into a timed group (its position means "unknown",
## not "then"). Compression is spatial; it never invents a shared execution batch.
static func _merge_side(rows: Array) -> Array:
	rows.sort_custom(_earliest_first)
	var merged: Array = []
	for row in rows:
		if not merged.is_empty():
			var head: Dictionary = merged.back()
			if bool(head.timed) == bool(row.timed) and head.touch.intersects(row.touch):
				head.entity_ids.append_array(row.entity_ids)
				head.group_keys.append_array(row.group_keys)
				head["is_next"] = bool(head.is_next) or bool(row.is_next)
				head["group_label"] = _group_label(head)
				continue
		merged.append(row)
	return merged


static func _group_label(item: Dictionary) -> String:
	if not bool(item.timed): return ""
	for key in item.group_keys:
		if str(key) != str(item.group_keys[0]): return "근접한 차례"
	return "같은 행동 묶음"


static func _earliest_first(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.timed) != bool(b.timed): return bool(a.timed)
	if int(a.remaining) != int(b.remaining): return int(a.remaining) < int(b.remaining)
	return int(a.entity_ids[0]) < int(b.entity_ids[0])


static func _left_to_right(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a.x), float(b.x)): return float(a.x) < float(b.x)
	return int(a.entity_ids[0]) < int(b.entity_ids[0])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	resized.connect(_relayout)


## Adopt a committed DTO. The previous interpolation is replaced, never queued
## (spec 5.4): positions leave wherever they are drawn right now and reach the new
## targets within LERP_DURATION_MSEC.
func set_state(state: Dictionary) -> void:
	_state = state.duplicate(true)
	_relayout()


## Pause and resume the drawing interpolation. Resuming does not fast-forward: the
## blocked span is added to the interpolation start so only the remaining part runs.
func set_presentation_blocked(blocked: bool) -> void:
	if _blocked == blocked: return
	_blocked = blocked
	var now := Time.get_ticks_msec()
	if blocked:
		_blocked_at_msec = now
		return
	if _blocked_at_msec >= 0 and _lerp_started_msec >= 0:
		_lerp_started_msec += now - _blocked_at_msec
	_blocked_at_msec = -1


## Brief center highlight for an actor that really acted (drawing only: this never
## drives, delays or replays the battle).
func flash_actor(entity_id: int) -> void:
	_flash_until[int(entity_id)] = Time.get_ticks_msec() + FLASH_DURATION_MSEC
	queue_redraw()


## Taps are muted while another surface owns targeting (spec 6). Input stays
## absorbed either way so nothing reaches the map underneath.
func set_taps_enabled(enabled: bool) -> void:
	if _taps_enabled == enabled: return
	_taps_enabled = enabled
	if not enabled and _pointer_down:
		_pointer_down = false
		_held_key = -1
		pointer_held.emit(false)
	queue_redraw()


func taps_enabled() -> bool:
	return _taps_enabled


func current_layout() -> Dictionary:
	return _layout


func _relayout() -> void:
	_layout = layout_spec(_state, size.x, maxf(1.0, size.y))
	var targets: Dictionary = {}
	var from: Dictionary = {}
	for item in _layout.items:
		var key := int(item.entity_ids[0])
		targets[key] = float(item.x)
		# A newly shown item starts at its target: it never slides in from a
		# position it never held.
		from[key] = float(_shown_x.get(key, item.x))
	_target_x = targets
	_from_x = from
	_shown_x = from.duplicate()
	_lerp_started_msec = Time.get_ticks_msec()
	_blocked_at_msec = _lerp_started_msec if _blocked else -1
	if _blocked:
		# Blocking stops predicted motion, not committed truth (spec 5): a manual
		# skill committed while paused syncs at once instead of animating.
		_shown_x = targets.duplicate()
	queue_redraw()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var flashing := not _flash_until.is_empty()
	for entity_id in _flash_until.keys():
		if now >= int(_flash_until[entity_id]): _flash_until.erase(entity_id)
	if _blocked:
		if flashing: queue_redraw()
		return
	var ratio := 1.0
	if _lerp_started_msec >= 0:
		ratio = clampf(float(now - _lerp_started_msec) / float(LERP_DURATION_MSEC), 0.0, 1.0)
	var moved := false
	for key in _target_x:
		var goal := float(_target_x[key])
		var value := lerpf(float(_from_x.get(key, goal)), goal, ratio)
		if not is_equal_approx(value, float(_shown_x.get(key, goal))): moved = true
		_shown_x[key] = value
	if moved or flashing: queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION: return
		if int(event.button_index) != MOUSE_BUTTON_LEFT: return
		_handle_pointer(event.position, bool(event.pressed))
		accept_event()
	elif event is InputEventScreenTouch:
		_handle_pointer(event.position, bool(event.pressed))
		accept_event()
	elif _pointer_down and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		accept_event()


## The whole strip absorbs the press (no map panning underneath) and holds the
## autonomous battle while the finger is down; the tap itself is information only.
func _handle_pointer(at: Vector2, pressed: bool) -> void:
	if pressed:
		_pointer_down = true
		_held_key = _key_at(at)
		pointer_held.emit(true)
		queue_redraw()
		return
	var released_on := _key_at(at)
	var held := _held_key
	_held_key = -1
	if _pointer_down:
		_pointer_down = false
		pointer_held.emit(false)
	if _taps_enabled and released_on >= 0 and released_on == held:
		var entity_ids := _entity_ids_of(held)
		if not entity_ids.is_empty(): entry_tapped.emit(entity_ids)
	queue_redraw()


## Items are identified by their representative entity, never by index: a state
## committed between press and release may reorder or regroup them.
func _key_at(at: Vector2) -> int:
	var index := _item_at(at)
	return -1 if index < 0 else int(_layout.items[index].entity_ids[0])


func _entity_ids_of(key: int) -> Array:
	for item in _layout.get("items", []):
		if int(item.entity_ids[0]) == key: return (item.entity_ids as Array).duplicate()
	return []


func _item_at(at: Vector2) -> int:
	var items: Array = _layout.get("items", [])
	var best := -1
	var best_distance := INF
	for index in range(items.size()):
		var item: Dictionary = items[index]
		if not (item.touch as Rect2).has_point(at): continue
		var distance := absf(_drawn_x(item) - at.x)
		if distance >= best_distance: continue
		best = index
		best_distance = distance
	return best


func _drawn_x(item: Dictionary) -> float:
	return float(_shown_x.get(int(item.entity_ids[0]), float(item.x)))


func _draw() -> void:
	if _layout.is_empty(): return
	var font := get_theme_default_font()
	var center: Rect2 = _layout.center
	var middle := size.y * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiSkin.CANVAS, 0.9))
	draw_line(Vector2(TOUCH_SIZE * 0.5, middle), Vector2(center.position.x, middle), UiSkin.IRON_EDGE, 1.0)
	draw_line(Vector2(center.end.x, middle), Vector2(size.x - TOUCH_SIZE * 0.5, middle), UiSkin.IRON_EDGE, 1.0)
	var flashing := not _flash_until.is_empty()
	if flashing: draw_rect(center, Color(UiSkin.BRASS, 0.22))
	draw_rect(center, UiSkin.BRASS if flashing else UiSkin.BRASS_DARK, false, 1.0)
	if font != null:
		draw_string(font, Vector2(center.position.x, HEADER_BASELINE), "행동",
			HORIZONTAL_ALIGNMENT_CENTER, center.size.x, LABEL_FONT_SIZE, UiSkin.BRASS)
		var hidden := str(_layout.hidden_label)
		if not hidden.is_empty():
			# Observed participants left out by the display cap -- not a button, and
			# not a claim that they act soon (spec 3, 7).
			draw_string(font, Vector2(size.x - TOUCH_SIZE, HEADER_BASELINE), hidden,
				HORIZONTAL_ALIGNMENT_RIGHT, TOUCH_SIZE - 2.0, LABEL_FONT_SIZE, UiSkin.BONE_DIM)
	for item in _layout.items:
		_draw_item(item, font, int(item.entity_ids[0]) == _held_key)


func _draw_item(item: Dictionary, font: Font, held: bool) -> void:
	var ally := str(item.side) == "ALLY"
	var frame := ALLY_FRAME if ally else UiSkin.BLOOD
	var tint := 1.0 if _taps_enabled else 0.7
	# Nudge each side outward so the two center portraits never overlap.
	var middle_x := _drawn_x(item) + (-2.0 if ally else 2.0)
	var portrait := Rect2(middle_x - PORTRAIT_SIZE * 0.5, PORTRAIT_TOP, PORTRAIT_SIZE, PORTRAIT_SIZE)
	draw_rect(portrait, Color("#11191e"))
	var texture: Texture2D = Assets.body_texture(str(item.portrait_key)) if ally \
		else Assets.monster_texture(str(item.portrait_key))
	if texture != null:
		draw_texture_rect_region(texture, portrait.grow(-2.0), PORTRAIT_CROP, Color(1, 1, 1, tint))
	draw_rect(portrait, Color(frame, tint), false, 2.0 if held else 1.0)
	_draw_direction(portrait, ally, Color(frame, tint))
	if _is_flashing(item):
		draw_rect(portrait.grow(1.0), UiSkin.BONE, false, 2.0)
	if font == null: return
	var badge := Rect2(portrait.position.x - 1.0, portrait.position.y - 1.0, 14.0, 13.0)
	draw_rect(badge, UiSkin.CANVAS)
	draw_rect(badge, UiSkin.IRON_EDGE, false, 1.0)
	draw_string(font, Vector2(badge.position.x + 1.0, badge.end.y - 3.0), str(item.marker),
		HORIZONTAL_ALIGNMENT_CENTER, badge.size.x - 2.0, LABEL_FONT_SIZE, UiSkin.BONE)
	var count := int((item.entity_ids as Array).size())
	if count > 1:
		# Members were merged only because their touch squares overlapped; the batch
		# meaning stays in group_label (brass edge = one real batch, iron = merely
		# adjacent moments) and the member list belongs to the tap popup.
		var tally := Rect2(portrait.end.x - 13.0, portrait.position.y - 1.0, 14.0, 13.0)
		draw_rect(tally, UiSkin.CANVAS)
		draw_rect(tally, UiSkin.BRASS if str(item.group_label) == "같은 행동 묶음" else UiSkin.IRON_EDGE, false, 1.0)
		draw_string(font, Vector2(tally.position.x + 1.0, tally.end.y - 3.0), "×%d" % count,
			HORIZONTAL_ALIGNMENT_CENTER, tally.size.x - 2.0, LABEL_FONT_SIZE, UiSkin.BONE)
	var tag := _tag_text(item)
	if tag.is_empty(): return
	draw_string(font, Vector2(middle_x - TOUCH_SIZE * 0.5, TAG_BASELINE), tag,
		HORIZONTAL_ALIGNMENT_CENTER, TOUCH_SIZE, LABEL_FONT_SIZE, _tag_color(item))


## Ready and next are facts the core already settled; 예상 marks a prediction that
## has not been confirmed against the core order, and … only says "past the horizon".
## An item with no known moment gets no tag at all rather than a guessed one.
func _tag_text(item: Dictionary) -> String:
	if not bool(item.timed): return ""
	if bool(item.out_of_range):
		return "예상 …" if str(item.confidence) == "EXPECTED" else "…"
	if bool(item.is_next): return "다음"
	if str(item.status) == "READY": return "준비"
	return "예상" if str(item.confidence) == "EXPECTED" else ""


func _tag_color(item: Dictionary) -> Color:
	if bool(item.is_next) and not bool(item.out_of_range): return UiSkin.BRASS
	if str(item.status) == "READY" and not bool(item.out_of_range): return UiSkin.BONE
	return UiSkin.BONE_DIM


func _is_flashing(item: Dictionary) -> bool:
	for entity_id in item.entity_ids:
		if _flash_until.has(int(entity_id)): return true
	return false


## Side is never colour alone (spec 3): allies face left, enemies face right.
func _draw_direction(portrait: Rect2, ally: bool, color: Color) -> void:
	var middle := portrait.position.y + portrait.size.y * 0.5
	var tip := portrait.position.x - 5.0 if ally else portrait.end.x + 5.0
	var base := portrait.position.x - 1.0 if ally else portrait.end.x + 1.0
	draw_colored_polygon(PackedVector2Array([Vector2(tip, middle), Vector2(base, middle - 4.0),
		Vector2(base, middle + 4.0)]), color)
