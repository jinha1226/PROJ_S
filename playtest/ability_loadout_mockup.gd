extends VBoxContainer

## Character ability-binding panel.
## The session remains authoritative; this control only renders DTOs and sends
## an explicit bind/remove request through the supplied callbacks.
const PixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var actor_id:=-1
var binding_rows:Array=[]
var item_rows:Array=[]
var selected_slot:=0
var slot_grid:GridContainer
var summary:Label
var feedback:Label
var picker:VBoxContainer
var remove_button:Button
var bind_action:Callable=Callable()
var remove_action:Callable=Callable()
var confirmation:ConfirmationDialog
var pending_instance_id:=""
var detail_title:Label
var mode_rows:VBoxContainer
var selected_item:=""
var mode_action:Callable=Callable()

func _ready()->void:
	name="AbilityLoadout"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	summary=Label.new();PixelSkin.apply_heading(summary);add_child(summary)
	slot_grid=GridContainer.new();slot_grid.name="AbilitySlots";slot_grid.columns=6
	slot_grid.add_theme_constant_override("h_separation",3)
	slot_grid.add_theme_constant_override("v_separation",6);add_child(slot_grid)
	for i in range(6):
		var button:=Button.new();button.name="AbilitySlot%d"%i
		button.custom_minimum_size=Vector2(44,48)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true
		button.pressed.connect(_select.bind(i));slot_grid.add_child(button)
	var card:=PanelContainer.new();card.add_theme_stylebox_override("panel",PixelSkin.panel_surface(PixelSkin.SLOT_FILLED,PixelSkin.BRASS_DARK,8,1));add_child(card)
	var content:=VBoxContainer.new();card.add_child(content)
	detail_title=Label.new();detail_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	PixelSkin.apply_heading(detail_title);content.add_child(detail_title)
	mode_rows=VBoxContainer.new();content.add_child(mode_rows)
	var actions:=HBoxContainer.new();add_child(actions)
	remove_button=Button.new();remove_button.text="해제 · 정책 미정"
	remove_button.custom_minimum_size.y=44
	remove_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	remove_button.pressed.connect(_remove_selected);actions.add_child(remove_button)
	PixelSkin.apply_action_button(remove_button,PixelSkin.BRASS)
	actions.visible=false
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size",11);feedback.visible=false;add_child(feedback)
	# Unconsumed parts live only in the item window. This page describes acquired
	# mutations, never a spoiler catalogue or a second consumption dialog.
	picker=VBoxContainer.new();add_child(picker);picker.visible=false
	if not binding_rows.is_empty():_refresh()


func configure(id:int, rows:Array, stored_items:Array=[], bind_callback:Callable=Callable(), remove_callback:Callable=Callable())->void:
	actor_id=id
	selected_item=""
	pending_instance_id=""
	if confirmation!=null:confirmation.hide()
	binding_rows=rows.duplicate(true)
	item_rows=stored_items.duplicate(true)
	bind_action=bind_callback
	remove_action=remove_callback
	selected_slot=0
	if feedback!=null:feedback.text=""
	if slot_grid!=null:_refresh()


func _select(index:int)->void:
	selected_slot=index;selected_item="";_refresh()

func update_rows(rows:Array,stored_items:Array)->void:
	if binding_rows==rows and item_rows==stored_items:return
	binding_rows=rows.duplicate(true);item_rows=stored_items.duplicate(true)
	if not selected_item.is_empty() and not item_rows.any(func(item):return str(item.get("instance_id",""))==selected_item):selected_item=""
	_refresh()

func _select_item(instance_id:String)->void:
	selected_item=instance_id;_refresh_detail()

func _refresh_detail()->void:
	for child in mode_rows.get_children():mode_rows.remove_child(child);child.queue_free()
	var row:Dictionary=binding_rows[selected_slot] if selected_slot<binding_rows.size() else {}
	for item in item_rows:
		if str(item.instance_id)==selected_item:
			if not item.get("consumed_before",false):detail_title.text=str(item.label);return
			row=item.get("effect_preview",{});break
	var filled:bool=not selected_item.is_empty() or str(row.get("state",""))=="BOUND"
	detail_title.text=str(row.get("label","변이")) if filled else "빈 슬롯"
	if not filled:
		return
	var planned:bool=bool(row.get("planned",false))
	var dual:bool=bool(row.get("dual_mode",false))
	_mode("상시 효과",str(row.get("passive","")),dual)
	var effect:=str(row.get("active",""))
	if effect.is_empty():effect="기본 위력 %d · 기력 %d · 사거리 %d"%[int(row.get("power",0)),int(row.get("cost",0)),int(row.get("range",0))]
	_mode("사용 기술",effect,not planned)

func _mode(title:String,effect:String,active:bool)->void:
	var card:=PanelContainer.new();card.custom_minimum_size.y=56
	card.add_theme_stylebox_override("panel",PixelSkin.panel_surface(PixelSkin.SLOT_FILLED,PixelSkin.CYAN if active else PixelSkin.IRON_EDGE,6,1))
	var label:=Label.new();label.text=title+"\n"+effect;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",14);card.add_child(label);mode_rows.add_child(card)


func _bound_count()->int:
	var count:=0
	for row in binding_rows:
		if str(row.get("state",""))=="BOUND":count+=1
	return count


func _refresh()->void:
	var bound:=_bound_count();var open_slots:=0
	for row in binding_rows:
		if str(row.get("state",""))!="LOCKED":open_slots+=1
	for i in range(6):
		var row:Dictionary=binding_rows[i] if i<binding_rows.size() else {}
		var state:=str(row.get("state","LOCKED"))
		var button:=slot_grid.get_child(i) as Button
		if state=="BOUND":
			button.text="A"
			button.icon=preload("res://playtest/dungeon_0x72_assets.gd").texture("flask_big_blue")
			button.expand_icon=true;button.add_theme_constant_override("icon_max_width",16)
		elif state=="EMPTY":
			button.text="+";button.icon=null
		else:
			button.text="잠금";button.icon=null;button.add_theme_font_size_override("font_size",11)
		button.tooltip_text=str(row.get("label","잠금"))+" · Lv.%d 개방"%int(row.get("unlock_level",i+1))
		button.disabled=state=="LOCKED"
		PixelSkin.apply_action_button(button,PixelSkin.BRASS if i==selected_slot else PixelSkin.CYAN)
	summary.text="변이 · 체득 %d / %d"%[bound,open_slots]
	_refresh_detail()
	remove_button.disabled=not remove_action.is_valid() or selected_slot>=binding_rows.size() or str(binding_rows[selected_slot].get("state",""))!="BOUND"
	for child in picker.get_children():
		picker.remove_child(child);child.queue_free()
	if item_rows.is_empty():
		var empty:=Label.new();empty.text="보관 중인 몬스터 고기가 없습니다.";picker.add_child(empty)
	else:
		for row in item_rows:
			var line:=HBoxContainer.new();picker.add_child(line)
			var button:=Button.new()
			var preview:Dictionary=row.get("effect_preview",{}) if row.get("effect_preview",{}) is Dictionary else {}
			button.text="%s · %d개"%[str(row.get("label","고기")),int(row.get("quantity",1))]
			button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			button.custom_minimum_size.y=48;button.clip_text=true
			button.pressed.connect(_select_item.bind(str(row.get("instance_id",""))))
			line.add_child(button);PixelSkin.apply_action_button(button)
			var absorb:=Button.new();absorb.text="먹기";absorb.custom_minimum_size=Vector2(52,48)
			absorb.disabled=bool(preview.get("planned",false)) or not bind_action.is_valid()
			absorb.tooltip_text=""
			absorb.pressed.connect(_bind_item.bind(str(row.get("instance_id",""))))
			line.add_child(absorb);PixelSkin.apply_action_button(absorb,PixelSkin.CYAN)


func _bind_item(instance_id:String)->void:
	if not bind_action.is_valid():
		feedback.text="결속 서비스가 연결되지 않았습니다."
		return
	for row in item_rows:
		if str(row.get("instance_id",""))!=instance_id:continue
		var preview:Dictionary=row.get("effect_preview",{})
		if bool(preview.get("planned",false)):return
		pending_instance_id=instance_id
		_confirm_binding()
		return


func _confirm_binding()->void:
	feedback.visible=true
	var instance_id:=pending_instance_id
	pending_instance_id=""
	if instance_id.is_empty() or not bind_action.is_valid():return
	var result:Variant=bind_action.call(instance_id)
	if not result is Dictionary or not bool(result.get("accepted",false)):
		feedback.text=str(result.get("message","변이을 결속할 수 없습니다.")) if result is Dictionary else "변이을 결속할 수 없습니다."
		return
	feedback.text="고기 섭취 · 포만감 +%d%s"%[int(result.get("nutrition_milli",0)/1000)," · 새 변이 체득" if bool(result.get("gains_ability",false)) else " · 식사만 적용"]
	if result.get("bindings",[]) is Array:
		binding_rows=result.bindings.duplicate(true)
	for index in range(item_rows.size()-1,-1,-1):
		if str(item_rows[index].get("instance_id",""))==instance_id:item_rows.remove_at(index)
	selected_item=""
	_refresh()


func _remove_selected()->void:
	if not remove_action.is_valid():return
	var result:Variant=remove_action.call(actor_id,selected_slot)
	feedback.text=str(result.get("message","변이을 해제할 수 없습니다.")) if result is Dictionary else "변이을 해제할 수 없습니다."
