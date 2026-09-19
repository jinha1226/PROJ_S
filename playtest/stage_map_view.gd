extends Control
## Node-selection overlay. Presentation only: it never touches the simulator.
signal room_selected(room_id:int)
signal abandon_requested
signal closed
signal camp_requested
signal camp_action_requested(action:String, target_id:int)
signal camp_finished
const ROLE_LABEL:={"COMBAT":"전투","HAZARD":"위험","SAFE":"휴식","STAIRS":"계단"}
var _buttons:Dictionary={}
var _panel:PanelContainer;var _grid:GridContainer;var _title:Label;var _abandon:Button;var _close:Button
var _camp:VBoxContainer
func _init()->void:
	set_anchors_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP;visible=false
	var dim:=ColorRect.new();dim.color=Color(0,0,0,0.72);dim.set_anchors_preset(Control.PRESET_FULL_RECT);add_child(dim)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(center)
	_panel=PanelContainer.new();_panel.custom_minimum_size=Vector2(328,420);center.add_child(_panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);_panel.add_child(box)
	_title=Label.new();_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;box.add_child(_title)
	_grid=GridContainer.new();_grid.columns=3;_grid.add_theme_constant_override("h_separation",8);_grid.add_theme_constant_override("v_separation",8);box.add_child(_grid)
	_camp=VBoxContainer.new();box.add_child(_camp)
	var row:=HBoxContainer.new();box.add_child(row)
	_abandon=Button.new();_abandon.text="거점으로 귀환";_abandon.custom_minimum_size=Vector2(150,48);_abandon.pressed.connect(func():abandon_requested.emit());row.add_child(_abandon)
	_close=Button.new();_close.text="닫기";_close.custom_minimum_size=Vector2(100,48);_close.pressed.connect(close);row.add_child(_close)
func open(map:Dictionary)->void:
	z_index=70
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in _grid.get_children():_grid.remove_child(child);child.queue_free()
	_buttons.clear()
	_title.text="%d층 · 다음 방을 고르세요"%int(map.get("floor_index",1))
	var by_id:Dictionary={}
	for n in map.get("nodes",[]):by_id[int(n.id)]=n
	for id in range(9):
		var slot:Control
		if by_id.has(id):
			var n:Dictionary=by_id[id];var b:=Button.new()
			b.custom_minimum_size=Vector2(100,100);b.clip_text=true;b.text="%s\n%s"%[ROLE_LABEL.get(str(n.role),str(n.role)),str(n.name)]
			if bool(n.current):b.text="▶ "+b.text
			elif bool(n.visited) and bool(n.cleared):b.text="✓ "+b.text
			b.disabled=not bool(n.reachable);b.pressed.connect(func():room_selected.emit(id))
			_buttons[id]=b;slot=b
		else:
			slot=Control.new();slot.custom_minimum_size=Vector2(100,100)
		_grid.add_child(slot)
	_abandon.disabled=bool(map.get("in_combat",false))
	visible=true
func set_expedition(status:Dictionary)->void:
	for child in _camp.get_children():_camp.remove_child(child);child.queue_free()
	_grid.show();_close.show()
	if not status.get("active",false):return
	var phase:=str(status.get("phase","ACTIVE"))
	var ended:=phase in ["COMPLETE","EXTRACTED","FAILED"]
	_title.text="원정 · %d / 3방 완료"%status.get("completed_rooms",[]).size()
	_abandon.disabled=_abandon.disabled or ended
	if ended:
		_grid.hide()
		_title.text="%s · 보존 골드 %d"%[{"COMPLETE":"완주","EXTRACTED":"철수","FAILED":"실패"}.get(phase,phase),int(status.get("preserved_gold",0))]
	if phase=="CAMP" or ended:
		_grid.hide()
		for member in status.get("members",[]):
			var label:=Label.new();label.text="동료 %d · HP %d/%d · 스트레스 %d · %s"%[int(member.entity_id),int(member.health),int(member.max_health),int(member.stress),str(member.life_state)];_camp.add_child(label)
			if phase=="CAMP":
				var row:=HBoxContainer.new();_camp.add_child(row)
				for action in ["HEAL","CALM","TREAT_INJURY"]:
					var b:=Button.new();b.text=str({"HEAL":"회복","CALM":"진정","TREAT_INJURY":"부상 치료"}[action])+" · 2CP";b.custom_minimum_size.y=44
					b.disabled=int(status.camp_cp)<2 or str(member.life_state)=="DEAD"
					b.pressed.connect(func():camp_action_requested.emit(action,int(member.entity_id)));row.add_child(b)
	if phase=="CAMP":
		_title.text="캠프 · 남은 %d CP"%int(status.camp_cp)
		_close.hide()
		var done:=Button.new();done.text="캠프 종료";done.custom_minimum_size.y=44;done.pressed.connect(func():camp_finished.emit());_camp.add_child(done)
	elif not ended and bool(status.get("camp_available",false)):
		var camp:=Button.new();camp.text="캠프 · 치료와 휴식";camp.custom_minimum_size.y=44;camp.pressed.connect(func():camp_requested.emit());_camp.add_child(camp)
func close()->void:visible=false;closed.emit()
func node_button(id:int)->Button:return _buttons.get(id)
