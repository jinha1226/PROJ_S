extends Control

signal closed
const Model=preload("res://playtest/active_combat_lab_model.gd")
const UISkin=preload("res://playtest/dark_pixel_ui_skin.gd")
const Skills=preload("res://sim/abilities/active_skill_registry.gd")
var model=Model.new()
var board
var header:Label
var feedback:Label
var log_label:Label
var party:HBoxContainer
var dock:HBoxContainer
var timeline_hud
var skill:=""
var target_id:=-1
var kit_index:=0
const KITS:=[["FIREBOLT","BARRIER"],["STRIKE","SHOVE"],["MEND","BARRIER"]]

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var lab_theme:=Theme.new();UISkin.configure_theme(lab_theme);theme=lab_theme
	var background:=ColorRect.new();background.color=UISkin.CANVAS;background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var layout:=VBoxContainer.new();layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left=4;layout.offset_right=-4;layout.offset_top=4;layout.offset_bottom=-4
	layout.add_theme_constant_override("separation",4);add_child(layout)
	var top:=HBoxContainer.new();layout.add_child(top)
	header=Label.new();header.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.clip_text=true
	header.add_theme_font_size_override("font_size",14);top.add_child(header)
	_button(top,"재시작",func():model.reset();model.actor(1).skills=KITS[kit_index].duplicate();_clear_selection();_refresh())
	_button(top,"나가기",func():closed.emit();queue_free())
	timeline_hud=preload("res://playtest/active_combat_timeline_hud.gd").new()
	layout.add_child(timeline_hud);timeline_hud.inspected.connect(_show_report)
	board=preload("res://playtest/active_combat_lab_board.gd").new();board.model=model
	board.size_flags_vertical=Control.SIZE_EXPAND_FILL;board.custom_minimum_size.y=180
	board.picked.connect(_pick);layout.add_child(board)
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.y=34;feedback.add_theme_font_size_override("font_size",12);layout.add_child(feedback)
	party=HBoxContainer.new();party.add_theme_constant_override("separation",3);layout.add_child(party)
	dock=HBoxContainer.new();dock.add_theme_constant_override("separation",3);layout.add_child(dock)
	log_label=Label.new();log_label.custom_minimum_size.y=48;log_label.add_theme_font_size_override("font_size",11)
	log_label.max_lines_visible=3;log_label.clip_text=true;layout.add_child(log_label)
	log_label.mouse_filter=Control.MOUSE_FILTER_STOP
	log_label.gui_input.connect(func(event:InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:_show_report()
		elif event is InputEventScreenTouch and event.pressed:_show_report())
	_refresh()

func _button(parent:Control,title:String,callback:Callable)->Button:
	var button:=Button.new();button.text=title;button.custom_minimum_size=Vector2(44,48)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true
	button.add_theme_font_size_override("font_size",12);UISkin.apply_action_button(button)
	button.pressed.connect(callback);parent.add_child(button);return button

func _clear_children(parent:Control)->void:
	for child in parent.get_children():parent.remove_child(child);child.queue_free()

func _refresh()->void:
	header.text="전투 · %d회 행동 %s"%[model.turn,model.terminal]
	timeline_hud.refresh(model,skill)
	_clear_children(party)
	for id in range(1,5):
		var actor:=model.actor(id)
		var recent:=str(actor.last_action).split(" · ")[0].split(" (")[0]
		var button:=_button(party,"%s\nHP %d · 기 %d\n%s"%[actor.name,actor.hp,actor.energy,recent],_party_pick.bind(id))
		button.custom_minimum_size.y=64
		button.tooltip_text="%s · %s"%[actor.personality," / ".join(actor.skills)]
	_clear_children(dock)
	if skill.is_empty():
		for id in model.actor(1).skills:
			var definition:=Skills.definition(str(id))
			var button:=_button(dock,"%s %d"%[definition.name,definition.cost],_select.bind(str(id)))
			button.disabled=not model.terminal.is_empty() or int(model.actor(1).energy)<int(definition.cost)
		_button(dock,"대기",func():_submit("WAIT"))
		var kit:=_button(dock,"기술 구성",_cycle_kit);kit.disabled=model.turn!=0
	else:
		_button(dock,"취소",func():_clear_selection();_refresh())
		var use:=_button(dock,"사용",func():_submit(skill,target_id))
		use.disabled=target_id<0 or not model.preview(1,skill,target_id).accepted
	board.skill=skill;board.selected_id=target_id;board.queue_redraw()
	log_label.text="전투 기록 ▸ 터치해서 전체 행동 보기\n"+"\n".join(model.history.slice(maxi(0,model.history.size()-2)))
	if skill.is_empty():feedback.text="적 터치: 기본 공격 · 빈 인접 칸: 이동\n동료 자동전투 / 테스트 전용 · 원정 저장과 분리"

func _select(id:String)->void:
	skill=id;target_id=-1;feedback.text="%s · 대상 선택 (기력 %d)"%[Skills.SKILLS[id].name,Skills.SKILLS[id].cost]
	_refresh()

func _pick(cell:Vector2i)->void:
	var target:=model.actor_at(cell)
	if not skill.is_empty():
		_choose_target(int(target.get("id",-1)));return
	if not target.is_empty():
		if target.team=="ENEMY":_submit("ATTACK",int(target.id))
		return
	_submit("MOVE",-1,cell)

func _choose_target(id:int)->void:
	var preview:=model.preview(1,skill,id)
	if not preview.accepted:feedback.text=str(preview.reason);return
	target_id=id
	feedback.text="%s → %s · 피해 %d / 회복 %d / 보호 %d\n사용을 눌러 확정하세요."%[Skills.SKILLS[skill].name,model.actor(id).name,preview.damage,preview.healing,preview.barrier]
	_refresh()

func _party_pick(id:int)->void:
	if not skill.is_empty():_choose_target(id)
	else:
		_show_report(id)

func _show_report(focus_id:int=-1)->void:
	if has_node("CombatReport"):return
	var panel:=PanelContainer.new();panel.name="CombatReport"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left=8;panel.offset_right=-8;panel.offset_top=8;panel.offset_bottom=-8
	panel.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(panel)
	var column:=VBoxContainer.new();panel.add_child(column)
	_button(column,"전투 정보 · 닫기",func():panel.queue_free())
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	var text:=Label.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.add_theme_font_size_override("font_size",14)
	scroll.add_child(text)
	var lines:Array[String]=[]
	for actor in model.actors:
		if focus_id>0 and int(actor.id)!=focus_id:continue
		var names:Array[String]=[]
		for key in actor.skills:names.append(str(Skills.definition(str(key)).name))
		lines.append("%s · HP %d/%d · 기력 %d\n보유: %s\n최근: %s%s\n"%[actor.name,actor.hp,actor.max_hp,actor.energy," / ".join(names),actor.last_action," → "+str(actor.last_target) if not str(actor.last_target).is_empty() else ""])
		if not str(actor.get("last_reason","")).is_empty():lines.append("판단: "+str(actor.last_reason)+"\n")
		if model.body_bridge.enabled:
			var body=model.body_bridge.bodies.get(int(actor.id))
			if body!=null:
				var functions:Dictionary=model.body_bridge.Functions.appraisal(body)
				lines.append("육체: 상처 %d · 혈액 %d/%d · 충격 %d\n사용 가능 팔 %d · 다리 %d\n"%[body.wounds.size(),body.current_blood,body.body_scalars.blood_capacity,body.shock,functions.usable_arm_count,functions.usable_leg_count])
	lines.append("── 최근 행동부터 · 최대 100건 ──")
	for index in range(model.history.size()-1,-1,-1):
		if focus_id>0 and not str(model.actor(focus_id).name) in model.history[index]:continue
		lines.append(model.history[index])
	text.text="\n".join(lines)

func _submit(kind:String,id:int=-1,position:Vector2i=Vector2i(-1,-1))->void:
	var result:=model.act(kind,id,position)
	if result.accepted:_clear_selection();_refresh()
	else:feedback.text=str(result.reason)

func _clear_selection()->void:skill="";target_id=-1

func _cycle_kit()->void:
	if model.turn!=0:return
	kit_index=(kit_index+1)%KITS.size();model.actor(1).skills=KITS[kit_index].duplicate()
	_clear_selection();_refresh()
