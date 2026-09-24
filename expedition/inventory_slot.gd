extends Button
## Adapted from ../playtest/item_inventory_slot.gd: recessed slot,
## selected brackets, quantity badge and immutable display row.
var row: Dictionary = {}
var selected := false

func configure(value: Dictionary, chosen: bool = false) -> void:
	row = value.duplicate(true); selected = chosen
	disabled = row.is_empty()
	tooltip_text = row.get("label","빈 가방 칸")
	custom_minimum_size = Vector2(68,68); size_flags_horizontal = SIZE_EXPAND_FILL
	set_meta("inventory_slot",true); set_meta("item_id",row.get("id","")); queue_redraw()

func _ready() -> void:
	clip_contents = true; texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in ["normal","hover","pressed","focus","disabled"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw); mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw); button_up.connect(queue_redraw)
	resized.connect(queue_redraw)

func _draw() -> void:
	var bounds := Rect2(Vector2.ONE,size-Vector2.ONE*2)
	var plate := bounds.grow(-2)
	var border := Color("dfba75") if selected else Color("ae9160") if is_hovered() else Color("65563e")
	draw_rect(bounds,Color("0d0b09"))
	draw_rect(plate,Color("25211b") if not row.is_empty() else Color("17140f"))
	draw_line(plate.position,Vector2(plate.end.x,plate.position.y),border.lightened(0.12))
	draw_line(plate.position,Vector2(plate.position.x,plate.end.y),border)
	draw_line(Vector2(plate.position.x,plate.end.y),plate.end,Color("090706"),2)
	draw_line(Vector2(plate.end.x,plate.position.y),plate.end,Color("090706"),2)
	if selected or is_hovered(): draw_rect(bounds,border,false,2)
	if row.is_empty():
		draw_line(plate.get_center()-Vector2(4,0),plate.get_center()+Vector2(4,0),Color("65563e")); return
	var icon: Texture2D = row.get("icon")
	if icon != null:
		var side := minf(plate.size.x,plate.size.y)-12
		draw_texture_rect(icon,Rect2(plate.get_center()-Vector2.ONE*side/2,Vector2.ONE*side),false)
	elif row.category == "장비":
		var center := plate.get_center()
		var ink := Color("d1b16d")
		match str(row.get("gear_slot","")):
			"weapon":
				draw_line(center+Vector2(-15,15),center+Vector2(13,-13),Color("d0c8b4"),4)
				draw_line(center+Vector2(-12,5),center+Vector2(-3,14),ink,4)
			"armour":
				draw_colored_polygon(PackedVector2Array([center+Vector2(-12,-15),center+Vector2(12,-15),center+Vector2(16,0),center+Vector2(10,16),center+Vector2(-10,16),center+Vector2(-16,0)]),Color("657c86"))
				draw_line(center+Vector2(-8,-8),center+Vector2(8,-8),ink,2)
			"shield":
				draw_colored_polygon(PackedVector2Array([center+Vector2(0,-17),center+Vector2(15,-11),center+Vector2(12,8),center+Vector2(0,17),center+Vector2(-12,8),center+Vector2(-15,-11)]),Color("657c86"))
				draw_line(center+Vector2(0,-13),center+Vector2(0,11),ink,2)
			"ring":
				draw_arc(center,12,0,TAU,24,ink,5)
				draw_circle(center+Vector2(0,-12),4,Color("69cfc2"))
	var font := get_theme_default_font()
	var count := "×%d" % row.quantity
	var extent := font.get_string_size(count,HORIZONTAL_ALIGNMENT_LEFT,-1,11)
	var badge := Rect2(bounds.end-extent-Vector2(6,4),extent+Vector2(5,3))
	draw_rect(badge,Color("0d0b09"))
	draw_string(font,badge.position+Vector2(2,font.get_ascent(11)),count,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("eee4ce"))
	if row.category == "파츠": draw_circle(Vector2(9,9),3,Color("d1b16d"))
