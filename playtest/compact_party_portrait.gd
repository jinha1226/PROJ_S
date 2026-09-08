extends Button

const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
var actor:Dictionary={}
var selected:=false
var party_count:=1
var party_index:=0
var order_reserved:=false

func _portrait(texture:Texture2D,rect:Rect2)->void:
	var tones:=[Color("#508cb0"),Color("#bd853d"),Color("#61934e"),Color("#ac4949")]
	var style=preload("res://playtest/dark_pixel_ui_skin.gd").panel_surface(Color("#11191e"),tones[party_index%4],0,2)
	draw_style_box(style,rect)
	if texture!=null:
		# Portrait crops the body atlas to head/shoulders, as in the concept.
		draw_texture_rect_region(texture,rect.grow(-3),Rect2(48,16,160,160))

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
		var side:=52.0
		var portrait_x:=4.0 if party_count==3 else (size.x-side)*0.5
		_portrait(texture,Rect2(portrait_x,3,side,side))
		if party_count==3:
			draw_string(font,Vector2(59,28),str(actor.get("display_name","")),HORIZONTAL_ALIGNMENT_LEFT,size.x-63,11,Color("#d0c8b4"))
		_draw_health(Rect2(5,57,size.x-10,5),health,maximum)
		draw_string(font,Vector2(2,68),"%d/%d"%[health,maximum],HORIZONTAL_ALIGNMENT_CENTER,size.x-4,11,Color("#e4e2d8"))
	else:
		_draw_expanded(texture,font,health,maximum)
	if selected:draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),Color("#c6a34c"),false,1)
	if order_reserved:draw_circle(Vector2(size.x-8,9),5,Color("#e3bd57"))

func _draw_expanded(texture:Texture2D,font:Font,health:int,maximum:int)->void:
	var portrait_side:=minf(60.0,size.y-8.0)
	var portrait:=Rect2(Vector2(4,2),Vector2.ONE*portrait_side)
	_portrait(texture,portrait)
	var left:=portrait.end.x+3.0
	var width:=maxf(1.0,size.x-left-4.0)
	var name_text:=str(actor.get("display_name",""))
	draw_string(font,Vector2(left,17),name_text,HORIZONTAL_ALIGNMENT_LEFT,width,11,Color("#d0c8b4"))
	var bar:=Rect2(left,23,width,5)
	_draw_health(bar,health,maximum)
	draw_string(font,Vector2(left,41),"%d/%d"%[health,maximum],HORIZONTAL_ALIGNMENT_LEFT,width,10,Color("#d0c8b4"))
	if actor.has("energy"):
		draw_string(font,Vector2(left,57),"기력 %d"%int(actor.energy),HORIZONTAL_ALIGNMENT_LEFT,width,10,Color("#88b9ce"))
	if party_count==1:
		var emotion:Dictionary=actor.get("emotion",{})
		draw_string(font,Vector2(left+86,41),str(emotion.get("label","평온")),HORIZONTAL_ALIGNMENT_LEFT,maxf(1,width-86),11,Color("#aaa896"))

func _draw_health(bar:Rect2,health:int,maximum:int)->void:
	draw_rect(bar,Color("#030607"))
	var fill:=bar;fill.size.x*=clampf(float(health)/maximum,0,1)
	draw_rect(fill,Color("#a94c4c") if health*4<=maximum else Color("#72ad70"))
