extends HBoxContainer

signal actor_selected(actor_id:int)
signal skill_selected(actor_id:int,skill_id:String,skill_label:String)
signal command_selected(actor_id:int,command_id:String)
signal pause_toggled
signal targeting_cancelled

const UiSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const TARGET_SIZE:=48
const FONT_SIZE:=12

var session
var actor_id:=-1

func configure(value,current_actor_id:int,targeting:bool,prompt:String,
		autoplay_paused:bool)->void:
	session=value;actor_id=current_actor_id
	custom_minimum_size.y=TARGET_SIZE
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",2)
	if targeting:
		_build_targeting(prompt)
		return
	_build_controls(autoplay_paused)

func _build_targeting(prompt:String)->void:
	var message:=Label.new();message.name="ManualTargetPrompt"
	message.text=prompt;message.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	message.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	message.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size",FONT_SIZE)
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(message)
	var cancel:=_button("취소","ManualTargetCancel")
	cancel.custom_minimum_size=Vector2(64,TARGET_SIZE)
	cancel.pressed.connect(func():targeting_cancelled.emit())
	add_child(cancel)

func _build_controls(autoplay_paused:bool)->void:
	var cards:Array=session.party_cards() if session!=null else []
	var selected:Dictionary={}
	for row_value in cards:
		if row_value is Dictionary and int(row_value.get("entity_id",-1))==actor_id:
			selected=row_value;break
	var skill_rows:Array=session.active_skill_rows(actor_id) \
		if session!=null and session.has_method("active_skill_rows") else []
	var energy:=int(skill_rows[0].get("energy",0)) if not skill_rows.is_empty() else 0
	var maximum:=int(skill_rows[0].get("max_energy",12)) if not skill_rows.is_empty() else 12
	var actor_menu:=MenuButton.new();actor_menu.name="ManualActorSelector"
	actor_menu.text="%s\n기력 %d/%d"%[_short_name(str(selected.get("display_name","인물"))),energy,maximum]
	actor_menu.custom_minimum_size=Vector2(78,TARGET_SIZE)
	actor_menu.clip_text=true
	actor_menu.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	actor_menu.add_theme_font_size_override("font_size",FONT_SIZE)
	actor_menu.tooltip_text="사용할 인물 선택 · 현재 %s"%str(selected.get("display_name","인물"))
	UiSkin.apply_action_button(actor_menu,UiSkin.BRASS)
	var actor_popup:=actor_menu.get_popup()
	_prepare_touch_popup(actor_popup)
	for index in range(cards.size()):
		var row:Variant=cards[index]
		if not row is Dictionary:continue
		actor_popup.add_item(str(row.get("display_name","인물")),index)
		actor_popup.set_item_as_radio_checkable(actor_popup.get_item_count()-1,true)
		var actor_available:=bool(row.get("alive",true))
		actor_popup.set_item_disabled(actor_popup.get_item_count()-1,not actor_available)
		if not actor_available:
			actor_popup.set_item_tooltip(actor_popup.get_item_count()-1,"쓰러진 인물은 선택할 수 없습니다.")
		actor_popup.set_item_checked(actor_popup.get_item_count()-1,
			int(row.get("entity_id",-1))==actor_id)
	actor_popup.id_pressed.connect(func(index:int):
		if index>=0 and index<cards.size() and cards[index] is Dictionary:
			actor_selected.emit(int(cards[index].get("entity_id",-1))))
	add_child(actor_menu)
	for index in range(2):
		var row:Dictionary=skill_rows[index] if index<skill_rows.size() \
			and skill_rows[index] is Dictionary else {}
		var skill:=_button(_skill_text(row,index),"ManualSkill%d"%index)
		skill.custom_minimum_size=Vector2(TARGET_SIZE,TARGET_SIZE)
		skill.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		skill.disabled=row.is_empty() or not bool(row.get("can_select",false))
		skill.tooltip_text=str(row.get("message",row.get("reason","사용할 수 없습니다.")))
		if not row.is_empty():
			skill.pressed.connect(_choose_skill.bind(str(row.get("skill_id","")),
				str(row.get("label","스킬"))))
		add_child(skill)
	var tactic:=MenuButton.new();tactic.name="ActorDirectiveMenu"
	var directive:Dictionary=session.actor_command_status(actor_id) \
		if session!=null and session.has_method("actor_command_status") else {}
	var command_id:=str(directive.get("command_id","FOLLOW"))
	tactic.text="지침·%s"%_command_short_label(command_id)
	tactic.custom_minimum_size=Vector2(62,TARGET_SIZE)
	tactic.clip_text=true
	tactic.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	tactic.add_theme_font_size_override("font_size",FONT_SIZE)
	tactic.tooltip_text="%s 개인 지침 · 지속 행동 (스킬과 별개)"%str(selected.get("display_name","인물"))
	UiSkin.apply_action_button(tactic,UiSkin.CYAN)
	var tactic_popup:=tactic.get_popup()
	_prepare_touch_popup(tactic_popup)
	var commands:=[["ATTACK_TARGET","표적 추격"],["RETREAT","후퇴"],
		["STOP_ATTACK","공격 중지"],["HOLD_POSITION","자리 지키기"],["FOLLOW","자율 전투"]]
	for index in range(commands.size()):
		var command_id_value:=str(commands[index][0])
		tactic_popup.add_item(str(commands[index][1]),index)
		if command_id_value!="ATTACK_TARGET" and session.has_method("actor_command_assessment"):
			var assessment:Dictionary=session.actor_command_assessment(actor_id,command_id_value)
			tactic_popup.set_item_disabled(index,not bool(assessment.get("accepted",false)))
			tactic_popup.set_item_tooltip(index,str(assessment.get("message",
				assessment.get("reason","지금 변경할 수 없습니다."))))
	tactic_popup.id_pressed.connect(func(index:int):
		if index>=0 and index<commands.size():command_selected.emit(actor_id,str(commands[index][0])))
	add_child(tactic)
	var pause:=_button("재개" if autoplay_paused else "정지","ManualAutoplayPause")
	pause.custom_minimum_size=Vector2(TARGET_SIZE,TARGET_SIZE)
	pause.tooltip_text="자동 전투 재개" if autoplay_paused else "자동 전투 일시정지"
	pause.pressed.connect(func():pause_toggled.emit())
	add_child(pause)

func _button(label:String,node_name:String)->Button:
	var button:=Button.new();button.name=node_name;button.text=label
	button.clip_text=true;button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size",FONT_SIZE)
	UiSkin.apply_action_button(button)
	return button

func _choose_skill(skill_id:String,skill_label:String)->void:
	skill_selected.emit(actor_id,skill_id,skill_label)

func _prepare_touch_popup(popup:PopupMenu)->void:
	# 16px glyphs plus 32px vertical separation produce approximately 48px rows
	# on the bundled pixel font, while five directive entries still fit 640px.
	popup.add_theme_font_size_override("font_size",16)
	popup.add_theme_constant_override("v_separation",32)

func _skill_text(row:Dictionary,index:int)->String:
	if row.is_empty():return "스킬 %d"%(index+1)
	return "%s %d"%[str(row.get("label","스킬")),int(row.get("cost",0))]

func _short_name(value:String)->String:
	return value if value.length()<=5 else value.left(5)

func _command_short_label(command_id:String)->String:
	return {"ATTACK_TARGET":"추격","RETREAT":"후퇴","STOP_ATTACK":"중지",
		"HOLD_POSITION":"고정","FOLLOW":"자율"}.get(command_id,"자율")
