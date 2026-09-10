extends Button

const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
var actor:Dictionary={}
var selected:=false
var party_count:=1
var party_index:=0
var order_reserved:=false
var danger:=false

func _portrait(texture:Texture2D,rect:Rect2)->void:
	var tones:=[Color("#508cb0"),Color("#bd853d"),Color("#61934e"),Color("#ac4949")]
	var style=preload("res://playtest/dark_pixel_ui_skin.gd").panel_surface(Color("#11191e"),tones[party_index%4],0,2)
	draw_style_box(style,rect)
	if texture!=null:
		# Native 24px actors need a 16px bust crop, not the old 256px-art crop.
		var source_side:=texture.get_width()*2.0/3.0
		var source:=Rect2(texture.get_width()/6.0,0,source_side,source_side)
		var side:=maxf(source_side,floor((minf(rect.size.x,rect.size.y)-4)/source_side)*source_side)
		var destination:=Rect2((rect.get_center()-Vector2.ONE*side/2).floor(),Vector2.ONE*side)
		var layers:=Assets.actor_layer_spec(actor)
		for key in ["body_texture","armor_texture","offhand_texture","weapon_texture","foreground_texture"]:
			var layer:Texture2D=layers.get(key)
			if layer!=null:draw_texture_rect_region(layer,destination,source)

var emphasized_until_msec:=-1

func _process(_delta:float)->void:
	if emphasized_until_msec>=0:
		queue_redraw()
		if Time.get_ticks_msec()>=emphasized_until_msec:emphasized_until_msec=-1

func _ready()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true
	resized.connect(queue_redraw)

func _draw()->void:
	var texture:Texture2D=Assets.actor_layer_spec(actor).get("body_texture")
	var maximum:=maxi(1,int(actor.get("max_health",1)))
	var health:=int(actor.get("health",0))
	var font:=get_theme_font("font")
	if party_count>=3:
		var side:=36.0
		var portrait_x:=3.0
		_portrait(texture,Rect2(portrait_x,3,side,side))
		draw_string(font,Vector2(42,24),str(actor.get("display_name","")),HORIZONTAL_ALIGNMENT_LEFT,maxf(1,size.x-44),10,Color("#d0c8b4"))
		_draw_stats(font,2,size.x-4,47,health,maximum,HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_draw_expanded(texture,font,health,maximum)
	if selected:
		draw_rect(Rect2(Vector2.ONE*2,size-Vector2.ONE*4),Color("#f5cc67"),false,3)
		draw_circle(Vector2(9,9),3,Color("#f5cc67"))
	if danger:draw_rect(Rect2(Vector2.ONE*2,size-Vector2.ONE*4),Color("#ff6262"),false,3)
	if Time.get_ticks_msec()<emphasized_until_msec:
		draw_rect(Rect2(Vector2.ONE*2,size-Vector2.ONE*4),Color("#e4bb67"),false,2)
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
	_draw_stats(font,left,width,39,health,maximum,HORIZONTAL_ALIGNMENT_LEFT)
	if party_count==1:
		var emotion:Dictionary=actor.get("emotion",{})
		draw_string(font,Vector2(left+86,41),str(emotion.get("label","평온")),HORIZONTAL_ALIGNMENT_LEFT,maxf(1,width-86),11,Color("#aaa896"))

func _draw_stats(font:Font,left:float,width:float,baseline:float,health:int,maximum:int,alignment:int)->void:
	var labels:=["HP %d/%d"%[health,maximum],"MP %d/%d"%[int(actor.get("energy",0)),int(actor.get("max_energy",12))],"STR %d"%int(actor.get("stress",0))]
	var colors:=[Color("#b7d99d"),Color("#88b9ce"),Color("#d5a5b8")]
	for index in range(3):
		draw_string(font,Vector2(left,baseline+index*11),labels[index],alignment,width,10,colors[index])

func _draw_health(bar:Rect2,health:int,maximum:int)->void:
	draw_rect(bar,Color("#030607"))
	var fill:=bar;fill.size.x*=clampf(float(health)/maximum,0,1)
	draw_rect(fill,Color("#a94c4c") if health*4<=maximum else Color("#72ad70"))
