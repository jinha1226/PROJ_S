extends Button

const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
var actor:Dictionary={}
var selected:=false
var party_count:=1

func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents=true
	resized.connect(queue_redraw)

func _draw()->void:
	var texture:Texture2D=Assets.actor_layer_spec(actor).get("body_texture")
	var maximum:=maxi(1,int(actor.get("max_health",1)))
	var health:=int(actor.get("health",0))
	var font:=get_theme_font("font")
	if party_count>=3:
		var side:=30.0 if party_count==3 else 34.0
		var portrait_x:=4.0 if party_count==3 else (size.x-side)*0.5
		if texture!=null:draw_texture_rect(texture,Rect2(portrait_x,2,side,side),false)
		if party_count==3:
			draw_string(font,Vector2(36,21),str(actor.get("display_name","")),HORIZONTAL_ALIGNMENT_LEFT,size.x-40,11,Color("#d0c8b4"))
		_draw_health(Rect2(5,38,size.x-10,5),health,maximum)
	else:
		_draw_expanded(texture,font,health,maximum)
	if selected:draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),Color("#c6a34c"),false,1)

func _draw_expanded(texture:Texture2D,font:Font,health:int,maximum:int)->void:
	var portrait_side:=minf(40.0,size.y-8.0)
	var portrait:=Rect2(Vector2(4,2),Vector2.ONE*portrait_side)
	if texture!=null:draw_texture_rect(texture,portrait,false)
	var left:=portrait.end.x+3.0
	var width:=maxf(1.0,size.x-left-4.0)
	var name_text:=str(actor.get("display_name",""))
	draw_string(font,Vector2(left,17),name_text,HORIZONTAL_ALIGNMENT_LEFT,width,11,Color("#d0c8b4"))
	var bar:=Rect2(left,23,width,5)
	_draw_health(bar,health,maximum)
	draw_string(font,Vector2(left,41),"%d/%d"%[health,maximum],HORIZONTAL_ALIGNMENT_LEFT,width,10,Color("#d0c8b4"))
	if party_count==1:
		var emotion:Dictionary=actor.get("emotion",{})
		draw_string(font,Vector2(left+86,41),str(emotion.get("label","평온")),HORIZONTAL_ALIGNMENT_LEFT,maxf(1,width-86),11,Color("#aaa896"))

func _draw_health(bar:Rect2,health:int,maximum:int)->void:
	draw_rect(bar,Color("#030607"))
	var fill:=bar;fill.size.x*=clampf(float(health)/maximum,0,1)
	draw_rect(fill,Color("#a94c4c") if health*4<=maximum else Color("#72ad70"))
