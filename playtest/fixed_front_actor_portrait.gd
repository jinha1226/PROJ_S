class_name FixedFrontActorPortrait
extends Control

const Assets = preload("res://playtest/fixed_front_topdown_assets.gd")
const BACKDROP := Color("#071012")
const SHADOW := Color("#02050799")

var _actor:Dictionary={}


func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)


func set_actor(value:Dictionary)->void:
	_actor=value.duplicate(true)
	queue_redraw()


func actor_dto()->Dictionary:
	return _actor.duplicate(true)


func portrait_draw_spec()->Dictionary:
	var portrait_actor:=_actor.duplicate(true);portrait_actor["facing"]=[0,1]
	var layer:=Assets.actor_layer_spec(portrait_actor)
	var inset:=maxf(2.0,minf(size.x,size.y)*0.05)
	var square_size:=maxf(1.0,minf(size.x,size.y)-inset*2.0)
	var source_size:Vector2=layer.get("source_canvas_size",Assets.SOURCE_CANVAS_SIZE)
	var source_offset:Vector2=layer.get("visual_center_offset_source_px",Vector2.ZERO)
	var scaled_offset:=Vector2(source_offset.x*square_size/maxf(1.0,source_size.x),
		source_offset.y*square_size/maxf(1.0,source_size.y))
	var center:=Vector2(size.x*0.5,size.y*0.5)+scaled_offset
	var bounds:=Rect2(center-Vector2.ONE*square_size*0.5,Vector2.ONE*square_size)
	return layer.merged({"bounds":bounds,"uses_actual_asset":bool(layer.get("uses_sprite",false)),
		"visual_center_offset_px":scaled_offset,"fixed_front":true,
		"ascii_glyph":false},true).duplicate(true)


func _draw()->void:
	draw_rect(Rect2(Vector2.ZERO,size),BACKDROP,true)
	var spec:=portrait_draw_spec()
	if not bool(spec.get("uses_sprite",false)):return
	var bounds:Rect2=spec.bounds
	var shadow_rect:=Rect2(Vector2(bounds.get_center().x-bounds.size.x*0.24,
		bounds.end.y-bounds.size.y*0.14),Vector2(bounds.size.x*0.48,bounds.size.y*0.10))
	draw_set_transform(Vector2.ZERO)
	draw_circle(shadow_rect.get_center(),shadow_rect.size.x*0.5,SHADOW)
	if str(spec.get("asset_family",""))=="KENNEY_TINY_DUNGEON":
		preload("res://playtest/kenney_dungeon_assets.gd").draw_actor(self,spec,bounds)
		return
	for texture_key in ["body_texture","armor_texture","offhand_texture","weapon_texture",
			"foreground_texture"]:
		var texture:Texture2D=spec.get(texture_key,null)
		if texture!=null:draw_texture_rect(texture,bounds,false,Color.WHITE)
