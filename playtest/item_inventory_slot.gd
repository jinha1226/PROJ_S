class_name ItemInventorySlot
extends Button

const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")

const EMPTY_FILL:=DarkSkin.SLOT_EMPTY
const FILLED_FILL:=DarkSkin.SLOT_FILLED
const EQUIPPED_FILL:=DarkSkin.SLOT_EQUIPPED
const BORDER:=DarkSkin.IRON_EDGE
const BORDER_HOVER:=DarkSkin.IRON_LIGHT
const BORDER_SELECTED:=DarkSkin.BRASS
const MUTED:=DarkSkin.BONE_DIM
const DANGER:=DarkSkin.BLOOD
const COUNT_INK:=DarkSkin.BONE

var _row:Dictionary={}
var _slot_index:=0
var _equipment_slot:=""
var _selected:=false


func _ready()->void:
	focus_mode=Control.FOCUS_NONE
	flat=true
	clip_contents=true
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus","disabled"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(queue_redraw)
	set_meta("visual_family",DarkSkin.VISUAL_FAMILY)
	set_meta("pixel_material","RECESSED_IRON_SLOT")


func configure(row:Dictionary,slot_index:int,equipment_slot:String="",
		selected:bool=false)->void:
	_row=row.duplicate(true)
	_slot_index=slot_index
	_equipment_slot=equipment_slot
	_selected=selected
	var empty:=bool(_row.get("empty",false))
	disabled=empty
	text=""
	tooltip_text=_tooltip_text()
	set_meta("item_instance_id",str(_row.get("instance_id","")))
	set_meta("item_slot",_equipment_slot)
	set_meta("inventory_slot_index",_slot_index)
	set_meta("inventory_slot",true)
	set_meta("empty_inventory_slot",empty)
	set_meta("item_definition_id",str(_row.get("definition_id","")))
	set_meta("visual_family",DarkSkin.VISUAL_FAMILY)
	set_meta("pixel_material","RECESSED_IRON_SLOT")
	queue_redraw()


func item_row()->Dictionary:
	return _row.duplicate(true)


func set_selected(value:bool)->void:
	_selected=value
	queue_redraw()


func slot_draw_spec()->Dictionary:
	var texture:=_item_texture()
	return {
		"slot_index":_slot_index,
		"equipment_slot":_equipment_slot,
		"empty":bool(_row.get("empty",false)),
		"selected":_selected,
		"equipped":bool(_row.get("equipped",false)) or not _equipment_slot.is_empty(),
		"definition_id":str(_row.get("definition_id","")),
		"category":str(_row.get("category","")),
		"quantity":int(_row.get("quantity",0)),
		"uses_texture":texture!=null,
		"texture":texture,
		"touch_size":get_combined_minimum_size(),
	}.duplicate(true)


func _draw()->void:
	var bounds:=Rect2(Vector2.ZERO,size).grow(-1.0)
	var empty:=bool(_row.get("empty",false))
	var equipped:=bool(_row.get("equipped",false)) or not _equipment_slot.is_empty() and not empty
	var fill:=EMPTY_FILL if empty else (EQUIPPED_FILL if equipped else FILLED_FILL)
	if is_pressed():fill=fill.lightened(0.05)
	var border:=BORDER_SELECTED if _selected else (BORDER_HOVER if is_hovered() else BORDER)
	if not empty and not bool(_row.get("requirements_met",true)):border=DANGER
	# Two-level square bevel reads at 1x pixel scale without glossy gradients.
	draw_rect(bounds,DarkSkin.IRON_SHADOW,true)
	var plate:=bounds.grow(-2.0)
	draw_rect(plate,fill,true)
	draw_line(plate.position,Vector2(plate.end.x,plate.position.y),
		border.lightened(0.12),1.0)
	draw_line(plate.position,Vector2(plate.position.x,plate.end.y),
		border.lightened(0.05),1.0)
	draw_line(Vector2(plate.position.x,plate.end.y),plate.end,
		DarkSkin.IRON_SHADOW.darkened(0.2),2.0)
	draw_line(Vector2(plate.end.x,plate.position.y),plate.end,
		DarkSkin.IRON_SHADOW.darkened(0.2),2.0)
	if _selected or is_hovered():draw_rect(bounds,border,false,2.0)
	if _selected:_draw_selection_brackets(bounds)
	var inner:=plate.grow(-4.0)
	if empty:
		_draw_empty_slot(inner)
		return
	var texture:=_item_texture()
	if texture!=null:
		var side:=minf(inner.size.x,inner.size.y)
		var icon_bounds:=Rect2(inner.get_center()-Vector2.ONE*side*0.5,Vector2.ONE*side)
		draw_texture_rect(texture,icon_bounds,false,Color.WHITE)
	else:
		_draw_fallback_icon(inner)
	if equipped:_draw_equipped_corner(bounds)
	if int(_row.get("quantity",1))>1:_draw_quantity(bounds,int(_row.quantity))


func _draw_selection_brackets(bounds:Rect2)->void:
	var length:=7.0
	var inset:=2.0
	var left:=bounds.position+Vector2(inset,inset)
	var right:=bounds.end-Vector2(inset,inset)
	for points in [
		[left,left+Vector2(length,0)],[left,left+Vector2(0,length)],
		[Vector2(right.x,left.y),Vector2(right.x-length,left.y)],
		[Vector2(right.x,left.y),Vector2(right.x,left.y+length)],
		[Vector2(left.x,right.y),Vector2(left.x+length,right.y)],
		[Vector2(left.x,right.y),Vector2(left.x,right.y-length)],
		[right,right-Vector2(length,0)],[right,right-Vector2(0,length)],
	]:
		draw_line(points[0],points[1],BORDER_SELECTED,2.0)


func _item_texture()->Texture2D:
	var definition_id:=str(_row.get("definition_id","")).to_upper()
	var category:=str(_row.get("category","")).to_upper()
	if category=="WEAPON":return Assets.weapon_texture(definition_id)
	if category=="ARMOR" and definition_id!="SHIELD_WOOD":
		return Assets.armor_texture(definition_id)
	return null


func _draw_empty_slot(bounds:Rect2)->void:
	var tone:=MUTED.darkened(0.25)
	match _equipment_slot:
		"MAIN_HAND":
			draw_line(bounds.position+Vector2(bounds.size.x*0.30,bounds.size.y*0.72),
				bounds.position+Vector2(bounds.size.x*0.70,bounds.size.y*0.28),tone,2.0)
		"OFF_HAND":_draw_shield(bounds,tone)
		"ARMOR":_draw_armor(bounds,tone)
		"ACCESSORY_1","ACCESSORY_2":
			draw_arc(bounds.get_center(),minf(bounds.size.x,bounds.size.y)*0.18,0.0,TAU,16,tone,2.0)
		_:
			var center:=bounds.get_center()
			draw_line(center-Vector2(5,0),center+Vector2(5,0),tone,1.0)
			draw_line(center-Vector2(0,5),center+Vector2(0,5),tone,1.0)


func _draw_fallback_icon(bounds:Rect2)->void:
	var definition_id:=str(_row.get("definition_id","")).to_upper()
	var category:=str(_row.get("category","")).to_upper()
	if definition_id=="SHIELD_WOOD":
		_draw_shield(bounds,Color("#b87a38"));return
	if definition_id.begins_with("POTION"):
		_draw_potion(bounds,Color("#d94b5b"));return
	if definition_id=="FOOD_RATION":
		_draw_ration(bounds);return
	if definition_id.begins_with("SCROLL"):
		_draw_scroll(bounds);return
	if category=="ACCESSORY":
		_draw_charm(bounds);return
	_draw_material(bounds)


func _draw_potion(bounds:Rect2,liquid:Color)->void:
	var center:=bounds.get_center()
	var bottle:=Rect2(center+Vector2(-8,-4),Vector2(16,16))
	draw_rect(Rect2(center+Vector2(-4,-11),Vector2(8,7)),Color("#9fc4c2"),true)
	draw_rect(bottle,Color("#c5d9d3"),true)
	draw_rect(Rect2(bottle.position+Vector2(2,7),Vector2(12,7)),liquid,true)
	draw_rect(bottle,Color("#eef1df"),false,2.0)


func _draw_ration(bounds:Rect2)->void:
	var center:=bounds.get_center()
	var pack:=Rect2(center-Vector2(10,8),Vector2(20,16))
	draw_rect(pack,Color("#9b6a3e"),true)
	draw_rect(pack,Color("#d09b55"),false,2.0)
	draw_line(center+Vector2(-7,-4),center+Vector2(7,4),Color("#e0c17a"),2.0)
	draw_line(center+Vector2(-7,4),center+Vector2(7,-4),Color("#e0c17a"),2.0)


func _draw_scroll(bounds:Rect2)->void:
	var center:=bounds.get_center()
	var paper:=Rect2(center-Vector2(8,11),Vector2(16,22))
	draw_rect(paper,Color("#d8c792"),true)
	draw_rect(paper,Color("#6f5430"),false,2.0)
	for y in [-4.0,1.0,6.0]:
		draw_line(center+Vector2(-5,y),center+Vector2(5,y),Color("#705b3d"),1.0)


func _draw_charm(bounds:Rect2)->void:
	var center:=bounds.get_center()
	var radius:=minf(bounds.size.x,bounds.size.y)*0.22
	draw_arc(center,radius,0.0,TAU,20,Color("#d2a94b"),3.0)
	draw_circle(center,radius*0.38,Color("#45b8c4"))


func _draw_material(bounds:Rect2)->void:
	var center:=bounds.get_center()
	var points:=PackedVector2Array([center+Vector2(0,-12),center+Vector2(9,-2),
		center+Vector2(5,11),center+Vector2(-7,8),center+Vector2(-10,-3)])
	draw_colored_polygon(points,Color("#7fb8a2"))
	draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[4],points[0]]),
		Color("#d2e2c8"),2.0)


func _draw_shield(bounds:Rect2,tone:Color)->void:
	var center:=bounds.get_center()
	var points:=PackedVector2Array([center+Vector2(-10,-10),center+Vector2(10,-10),
		center+Vector2(8,5),center+Vector2(0,13),center+Vector2(-8,5)])
	draw_colored_polygon(points,tone)
	draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[4],points[0]]),
		tone.lightened(0.35),2.0)


func _draw_armor(bounds:Rect2,tone:Color)->void:
	var center:=bounds.get_center()
	var body:=Rect2(center-Vector2(9,7),Vector2(18,18))
	draw_rect(body,tone,true)
	draw_line(body.position,body.position+Vector2(-7,6),tone,4.0)
	draw_line(Vector2(body.end.x,body.position.y),body.position+Vector2(body.size.x+7,6),tone,4.0)


func _draw_equipped_corner(bounds:Rect2)->void:
	var origin:=bounds.position+Vector2(3,3)
	var corner:=PackedVector2Array([origin,origin+Vector2(9,0),
		origin+Vector2(0,9)])
	draw_colored_polygon(corner,BORDER_SELECTED)


func _draw_quantity(bounds:Rect2,quantity:int)->void:
	var label:="×%d"%quantity
	var font:=get_theme_default_font()
	var font_size:=11
	var extent:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var badge:=Rect2(bounds.end-extent-Vector2(6,4),extent+Vector2(5,3))
	draw_rect(badge,Color("#020607dd"),true)
	draw_string(font,badge.position+Vector2(2,font.get_ascent(font_size)),label,
		HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,COUNT_INK)


func _tooltip_text()->String:
	if bool(_row.get("empty",false)):
		return "빈 장비 슬롯" if not _equipment_slot.is_empty() else "빈 가방 칸"
	var suffix:=" · 장착 중" if bool(_row.get("equipped",false)) else ""
	var quantity:=int(_row.get("quantity",1))
	if quantity>1:suffix+=" · %d개"%quantity
	return "%s%s"%[str(_row.get("label","아이템")),suffix]
