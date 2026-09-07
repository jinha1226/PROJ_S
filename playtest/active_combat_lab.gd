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
	board=preload("res://playtest/active_combat_lab_board.gd").new();board.model=model
	board.size_flags_vertical=Control.SIZE_EXPAND_FILL;board.custom_minimum_size.y=180
	board.picked.connect(_pick);layout.add_child(board)
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.y=34;feedback.add_theme_font_size_override("font_size",12);layout.add_child(feedback)
	party=HBoxContainer.new();party.add_theme_constant_override("separation",3);layout.add_child(party)
	dock=HBoxContainer.new();dock.add_theme_constant_override("separation",3);layout.add_child(dock)
	log_label=Label.new();log_label.custom_minimum_size.y=48;log_label.add_theme_font_size_override("font_size",11)
	log_label.max_lines_visible=3;log_label.clip_text=true;layout.add_child(log_label)
	_refresh()

func _button(parent:Control,title:String,callback:Callable)->Button:
	var button:=Button.new();button.text=title;button.custom_minimum_size=Vector2(44,48)
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true
	button.add_theme_font_size_override("font_size",12);UISkin.apply_action_button(button)
	button.pressed.connect(callback);parent.add_child(button);return button

func _clear_children(parent:Control)->void:
	for child in parent.get_children():parent.remove_child(child);child.queue_free()

func _refresh()->void:
	header.text="전투 실험 · %d턴 %s"%[model.turn,model.terminal]
	_clear_children(party)
	for id in range(1,5):
		var actor:=model.actor(id)
		var button:=_button(party,"%s\nHP %d · 기력 %d"%[actor.name,actor.hp,actor.energy],_party_pick.bind(id))
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
	log_label.text="\n".join(model.history.slice(maxi(0,model.history.size()-3)))
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
		var actor:=model.actor(id)
		feedback.text="%s · %s\n%s"%[actor.name,actor.personality," / ".join(actor.skills)]

func _submit(kind:String,id:int=-1,position:Vector2i=Vector2i(-1,-1))->void:
	var result:=model.act(kind,id,position)
	if result.accepted:_clear_selection();_refresh()
	else:feedback.text=str(result.reason)

func _clear_selection()->void:skill="";target_id=-1

func _cycle_kit()->void:
	if model.turn!=0:return
	kit_index=(kit_index+1)%KITS.size();model.actor(1).skills=KITS[kit_index].duplicate()
	_clear_selection();_refresh()
