extends VBoxContainer

signal inspected(actor_id:int)
const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
var caption:Label
var strip:HBoxContainer

func _ready()->void:
	caption=Label.new();caption.add_theme_font_size_override("font_size",11);add_child(caption)
	strip=HBoxContainer.new();strip.add_theme_constant_override("separation",2);add_child(strip)

func refresh(model,kind:String)->void:
	for child in strip.get_children():strip.remove_child(child);child.queue_free()
	if not model.terminal.is_empty():caption.text="전투 종료";return
	caption.text="행동 순서 · T%d · ~는 후속 행동 예상"%model.timeline.now
	if not kind.is_empty():caption.text="선택 후 예상 · 다음 내 차례 +%d · ~는 추정"%model.timeline.duration(model.actor(1),kind)
	for entry in model.timeline.forecast(model.actors,kind,6):
		var actor:Dictionary=model.actor(int(entry.id))
		var button:=Button.new();button.custom_minimum_size=Vector2(44,44)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true
		button.add_theme_font_size_override("font_size",11)
		var marker:="나" if int(actor.id)==1 else (str(actor.id) if actor.team=="PARTY" else "E%d"%(int(actor.id)-4))
		button.text="%s\n%s+%d"%[marker,"~" if entry.estimated else "",int(entry.time)-model.timeline.now]
		button.icon=Assets.body_texture(str(actor.species_id))
		button.expand_icon=true;button.add_theme_constant_override("icon_max_width",14)
		button.modulate=Color("#b8e8a0") if actor.team=="PARTY" else Color("#ffac9e")
		button.pressed.connect(func():inspected.emit(int(actor.id)))
		strip.add_child(button)
