extends HBoxContainer

signal skill_selected(actor_id:int,skill_id:String,label:String)
signal page_requested(actor_id:int,page:int)
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var targeting:=false
var explicit_pointer_input:=false
var slot_count:=2
var page_index:=0

func configure(actor_id:int,rows:Array,pending_actor:int,pending_skill:String)->void:
	targeting=pending_actor>0
	custom_minimum_size.y=48
	add_theme_constant_override("separation",2)
	var page_count:=maxi(1,ceili(float(rows.size())/slot_count))
	page_index=clampi(page_index,0,page_count-1)
	var displayed:=rows.slice(page_index*slot_count,(page_index+1)*slot_count)
	for row in displayed:
		var button:=Button.new()
		button.name="ActorSkill_%d_%s"%[actor_id,str(row.skill_id)]
		button.set_meta("actor_id",actor_id);button.set_meta("skill_id",str(row.skill_id))
		button.set_meta("skill_label",str(row.label))
		button.text="%s\n%s"%[str(row.label),"예약 · 취소" if bool(row.get("reserved",false)) else "기력 %d"%int(row.cost)]
		button.custom_minimum_size=Vector2(44,48)
		button.clip_text=true
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",12)
		button.disabled=not bool(row.can_select) or pending_actor>0
		button.tooltip_text=str(row.get("message",""))
		DarkSkin.apply_action_button(button,DarkSkin.BRASS if bool(row.get("reserved",false)) \
			or actor_id==pending_actor and str(row.skill_id)==pending_skill else DarkSkin.CYAN)
		button.pressed.connect(func():
			if not explicit_pointer_input:skill_selected.emit(actor_id,str(row.skill_id),str(row.label)))
		add_child(button)
	for slot in range(displayed.size(),slot_count):
		var empty:=Control.new()
		empty.name="EmptySkillSlot%d"%slot
		empty.custom_minimum_size=Vector2(44,48)
		empty.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		empty.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(empty)
	if page_count>1:
		var next:=Button.new();next.name="ActorSkillPage_%d"%actor_id
		next.text="%d/%d\n›"%[page_index+1,page_count]
		next.custom_minimum_size=Vector2(44,48)
		next.set_meta("actor_id",actor_id);next.set_meta("next_page",(page_index+1)%page_count)
		next.disabled=targeting;next.tooltip_text="다음 스킬 · 결속한 이능 포함"
		next.pressed.connect(func():
			if not explicit_pointer_input:page_requested.emit(actor_id,(page_index+1)%page_count))
		DarkSkin.apply_action_button(next);add_child(next)

func update_rows(actor_id:int,rows:Array)->void:
	for row in rows:
		var button:=get_node_or_null("ActorSkill_%d_%s"%[actor_id,str(row.skill_id)]) as Button
		if button==null:continue
		var reserved:=bool(row.get("reserved",false))
		var label:="%s\n%s"%[str(row.label),"예약 · 취소" if reserved else "기력 %d"%int(row.cost)]
		if button.text!=label:
			button.text=label;DarkSkin.apply_action_button(button,DarkSkin.BRASS if reserved else DarkSkin.CYAN)
		button.disabled=not bool(row.can_select) or targeting
		button.tooltip_text=str(row.get("message",""))
