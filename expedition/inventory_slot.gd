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
	var border := Color("d1b16d") if selected else Color("87969b") if is_hovered() else Color("46525c")
	draw_rect(bounds,Color("080e14"))
	draw_rect(plate,Color("202e35") if not row.is_empty() else Color("111a22"))
	draw_line(plate.position,Vector2(plate.end.x,plate.position.y),border.lightened(0.12))
	draw_line(plate.position,Vector2(plate.position.x,plate.end.y),border)
	draw_line(Vector2(plate.position.x,plate.end.y),plate.end,Color("05090c"),2)
	draw_line(Vector2(plate.end.x,plate.position.y),plate.end,Color("05090c"),2)
	if selected or is_hovered(): draw_rect(bounds,border,false,2)
	if row.is_empty():
		draw_line(plate.get_center()-Vector2(4,0),plate.get_center()+Vector2(4,0),Color("46525c")); return
	var icon: Texture2D = row.get("icon")
	if icon != null:
		var side := minf(plate.size.x,plate.size.y)-12
		draw_texture_rect(icon,Rect2(plate.get_center()-Vector2.ONE*side/2,Vector2.ONE*side),false)
	var font := get_theme_default_font()
	var count := "×%d" % row.quantity
	var extent := font.get_string_size(count,HORIZONTAL_ALIGNMENT_LEFT,-1,11)
	var badge := Rect2(bounds.end-extent-Vector2(6,4),extent+Vector2(5,3))
	draw_rect(badge,Color("080e14"))
	draw_string(font,badge.position+Vector2(2,font.get_ascent(11)),count,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("eee4ce"))
	if row.category == "이능": draw_circle(Vector2(9,9),3,Color("d1b16d"))
