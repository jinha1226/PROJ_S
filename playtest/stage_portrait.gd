extends "res://playtest/stage_touch_button.gd"
const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
var actor:Dictionary={}
func _ready():
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true;resized.connect(queue_redraw)
func _draw():
	var texture:Texture2D=Assets.actor_layer_spec(actor).get("body_texture")
	if texture!=null:
		var side:=minf(size.x-16,size.y-40)
		draw_texture_rect(texture,Rect2(Vector2((size.x-side)/2,7),Vector2(side,side)),false)
	var font:=get_theme_font("font")
	for i in range(2):
		var value:int=actor.get("health",0) if i==0 else actor.get("energy",0)
		var maximum:int=maxi(1,actor.get("max_health",1) if i==0 else actor.get("max_energy",1))
		var rect:=Rect2(8,size.y-32+i*13,size.x-16,11)
		draw_rect(rect,Color("#101820"));var fill:=rect;fill.size.x*=clampf(float(value)/maximum,0,1)
		draw_rect(fill,Color("#386c40") if i==0 else Color("#295e83"))
		draw_string(font,rect.position+Vector2(2,9),"%d/%d"%[value,maximum],HORIZONTAL_ALIGNMENT_LEFT,rect.size.x,10,Color.WHITE)
