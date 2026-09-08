extends Control

signal take_requested(battle_id:int,instance_id:String)
signal closed
const Slot=preload("res://playtest/item_inventory_slot.gd")
const DarkSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var battle_id:=-1
var body:VBoxContainer
var message:Label

func _ready()->void:
	name="BattleLootPanel";z_index=85;mouse_filter=Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,10)
	add_child(margin)
	var panel:=PanelContainer.new();DarkSkin.apply_panel(panel,"FOLIO");margin.add_child(panel)
	body=VBoxContainer.new();body.add_theme_constant_override("separation",8);panel.add_child(body)

func configure(inventory:Dictionary,loot:Dictionary,feedback:String="")->void:
	battle_id=int(loot.battle_id)
	for child in body.get_children():body.remove_child(child);child.queue_free()
	var title:=Label.new();title.text="전투 종료 · 전리품";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	message=Label.new();message.text=feedback if not feedback.is_empty() else "오른쪽 아이템을 눌러 가져가세요."
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message.add_theme_font_size_override("font_size",13)
	body.add_child(message)
	var columns:=HBoxContainer.new();columns.name="LootColumns"
	columns.add_theme_constant_override("separation",8);columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	_column(columns,"내 가방 %d/%d"%[inventory.used_backpack_slots,inventory.capacity],
		inventory.backpack_rows,false,int(inventory.capacity))
	_column(columns,"전리품 %d"%loot.rows.size(),loot.rows,true,0)
	var close_button:=Button.new();close_button.name="LootClose";close_button.text="완료 · 남은 것은 바닥에 두기"
	close_button.custom_minimum_size.y=48;DarkSkin.apply_action_button(close_button,DarkSkin.BRASS)
	close_button.pressed.connect(func():closed.emit());body.add_child(close_button)

func _column(parent:Control,title:String,rows:Array,loot:bool,capacity:int)->void:
	var column:=VBoxContainer.new();column.name="LootRight" if loot else "BagLeft"
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(column)
	var label:=Label.new();label.text=title;label.add_theme_font_size_override("font_size",14);column.add_child(label)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	var grid:=GridContainer.new();grid.columns=2;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",3);grid.add_theme_constant_override("v_separation",3)
	scroll.add_child(grid)
	for index in range(maxi(rows.size(),capacity)):
		var row:Dictionary=rows[index] if index<rows.size() else {"empty":true}
		var cell:=VBoxContainer.new();cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation",1);grid.add_child(cell)
		var slot:=Slot.new();slot.name=("LootItem_" if loot else "BagItem_")+str(index)
		slot.custom_minimum_size=Vector2(48,56);slot.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		slot.configure(row,index);cell.add_child(slot)
		if not row.get("empty",false):
			var caption:=Label.new();caption.text=str(row.get("label","아이템"))
			caption.add_theme_font_size_override("font_size",11);caption.clip_text=true
			caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;cell.add_child(caption)
			if loot:slot.pressed.connect(_take.bind(str(row.instance_id)))
			else:slot.pressed.connect(_describe.bind(row))
	if loot and rows.is_empty():
		var empty:=Label.new();empty.text="남은 전리품 없음";empty.add_theme_font_size_override("font_size",12)
		column.add_child(empty)

func _take(instance_id:String)->void:
	take_requested.emit(battle_id,instance_id)

func _describe(row:Dictionary)->void:
	message.text=str(row.get("display_name",row.get("label",row.get("definition_id","아이템"))))
