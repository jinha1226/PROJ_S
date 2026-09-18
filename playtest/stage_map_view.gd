extends Control
## Node-selection overlay. Presentation only: it never touches the simulator.
signal room_selected(room_id:int)
signal abandon_requested
signal closed
const ROLE_LABEL:={"COMBAT":"전투","HAZARD":"위험","SAFE":"휴식","STAIRS":"계단"}
var _buttons:Dictionary={}
var _panel:PanelContainer;var _grid:GridContainer;var _title:Label;var _abandon:Button;var _close:Button
func _init()->void:
	set_anchors_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP;visible=false
	var dim:=ColorRect.new();dim.color=Color(0,0,0,0.72);dim.set_anchors_preset(Control.PRESET_FULL_RECT);add_child(dim)
	_panel=PanelContainer.new();_panel.set_anchors_preset(Control.PRESET_CENTER);_panel.custom_minimum_size=Vector2(328,420);add_child(_panel)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",12);_panel.add_child(box)
	_title=Label.new();_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;box.add_child(_title)
	_grid=GridContainer.new();_grid.columns=3;_grid.add_theme_constant_override("h_separation",8);_grid.add_theme_constant_override("v_separation",8);box.add_child(_grid)
	var row:=HBoxContainer.new();box.add_child(row)
	_abandon=Button.new();_abandon.text="거점으로 귀환";_abandon.custom_minimum_size=Vector2(150,48);_abandon.pressed.connect(func():abandon_requested.emit());row.add_child(_abandon)
	_close=Button.new();_close.text="닫기";_close.custom_minimum_size=Vector2(100,48);_close.pressed.connect(close);row.add_child(_close)
func open(map:Dictionary)->void:
	for child in _grid.get_children():_grid.remove_child(child);child.queue_free()
	_buttons.clear()
	_title.text="%d층 · 다음 방을 고르세요"%int(map.get("floor_index",1))
	var by_id:Dictionary={}
	for n in map.get("nodes",[]):by_id[int(n.id)]=n
	for id in range(9):
		var slot:Control
		if by_id.has(id):
			var n:Dictionary=by_id[id];var b:=Button.new()
			b.custom_minimum_size=Vector2(100,100);b.text="%s\n%s"%[ROLE_LABEL.get(str(n.role),str(n.role)),str(n.name)]
			if bool(n.current):b.text="▶ "+b.text
			elif bool(n.visited) and bool(n.cleared):b.text="✓ "+b.text
			b.disabled=not bool(n.reachable);b.pressed.connect(func():room_selected.emit(id))
			_buttons[id]=b;slot=b
		else:
			slot=Control.new();slot.custom_minimum_size=Vector2(100,100)
		_grid.add_child(slot)
	_abandon.disabled=bool(map.get("in_combat",false))
	visible=true
func close()->void:visible=false;closed.emit()
func node_button(id:int)->Button:return _buttons.get(id)
