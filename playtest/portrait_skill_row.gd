extends HBoxContainer

signal skill_selected(actor_id:int,skill_id:String,label:String)
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")

func configure(actor_id:int,rows:Array,pending_actor:int,pending_skill:String)->void:
	custom_minimum_size.y=48
	add_theme_constant_override("separation",2)
	for row in rows:
		var button:=Button.new()
		button.name="ActorSkill_%d_%s"%[actor_id,str(row.skill_id)]
		button.text="%s\n기력 %d"%[str(row.label),int(row.cost)]
		button.custom_minimum_size=Vector2(48,48)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",12)
		button.disabled=not bool(row.can_select) or pending_actor>0
		button.tooltip_text=str(row.get("message",""))
		DarkSkin.apply_action_button(button,DarkSkin.BRASS if actor_id==pending_actor \
			and str(row.skill_id)==pending_skill else DarkSkin.CYAN)
		button.pressed.connect(func():skill_selected.emit(actor_id,str(row.skill_id),str(row.label)))
		add_child(button)
