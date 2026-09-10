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

func _ready()->void:
	name="AbilityLoadout"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var title:=Label.new();title.text="이능 결속 · 6칸";add_child(title)
	var help:=Label.new();help.text="보관 중인 이능 획득물을 선택해 빈 슬롯에 결속합니다.\n결속 시 아이템을 소비하며, 같은 이능은 중복 결속할 수 없습니다."
	help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size",11);add_child(help)
	summary=Label.new();add_child(summary)
	slot_grid=GridContainer.new();slot_grid.name="AbilitySlots";slot_grid.columns=2
	slot_grid.add_theme_constant_override("h_separation",6)
	slot_grid.add_theme_constant_override("v_separation",6);add_child(slot_grid)
	for i in range(6):
		var button:=Button.new();button.name="AbilitySlot%d"%i
		button.custom_minimum_size=Vector2(0,68)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.clip_text=true
		button.pressed.connect(_select.bind(i));slot_grid.add_child(button)
	var actions:=HBoxContainer.new();add_child(actions)
	remove_button=Button.new();remove_button.text="해제 · 정책 미정"
	remove_button.custom_minimum_size.y=44
	remove_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	remove_button.pressed.connect(_remove_selected);actions.add_child(remove_button)
	PixelSkin.apply_action_button(remove_button,PixelSkin.BRASS)
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size",11);add_child(feedback)
	var label:=Label.new();label.text="보관 중인 이능 획득물";add_child(label)
	picker=VBoxContainer.new();add_child(picker)
	confirmation=ConfirmationDialog.new();confirmation.title="이능 결속 확인"
	confirmation.dialog_autowrap=true
	confirmation.ok_button_text="소비하고 결속";confirmation.cancel_button_text="취소"
	confirmation.confirmed.connect(_confirm_binding)
	confirmation.canceled.connect(func():pending_instance_id="")
	add_child(confirmation)
	if not binding_rows.is_empty():_refresh()


func configure(id:int, rows:Array, stored_items:Array=[], bind_callback:Callable=Callable(), remove_callback:Callable=Callable())->void:
	actor_id=id
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
	selected_slot=index;_refresh()


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
			button.text="%d  %s\n%s"%[i+1,str(row.get("label",row.get("ability_id","이능"))),
				str(row.get("effect","결속됨"))]
		elif state=="EMPTY":
			button.text="%d  빈 슬롯\nLV%02d부터 개방"%[i+1,int(row.get("unlock_level",i+1))]
		else:
			button.text="%d  잠금\nLV%02d부터 개방"%[i+1,int(row.get("unlock_level",i+1))]
		button.disabled=state=="LOCKED"
		PixelSkin.apply_action_button(button,PixelSkin.BRASS if i==selected_slot else PixelSkin.CYAN)
	summary.text="결속 %d / 개방 %d / 6칸 · 액티브·패시브 공용"%[bound,open_slots]
	remove_button.disabled=not remove_action.is_valid() or selected_slot>=binding_rows.size() or str(binding_rows[selected_slot].get("state",""))!="BOUND"
	for child in picker.get_children():
		picker.remove_child(child);child.queue_free()
	if item_rows.is_empty():
		var empty:=Label.new();empty.text="결속할 이능 획득물이 없습니다.";picker.add_child(empty)
	else:
		for row in item_rows:
			var button:=Button.new()
			var preview:Dictionary=row.get("effect_preview",{}) if row.get("effect_preview",{}) is Dictionary else {}
			button.text="%s · %s\n%s · MP%d · 사거리%d"%[
				str(row.get("label",row.get("ability_id","이능"))),
				str(row.get("ability_id","")),str(preview.get("effect","효과 미리보기 없음")),
				int(preview.get("cost",0)),int(preview.get("range",0))]
			button.custom_minimum_size.y=48;button.clip_text=true
			button.pressed.connect(_bind_item.bind(str(row.get("instance_id",""))))
			picker.add_child(button);PixelSkin.apply_action_button(button)


func _bind_item(instance_id:String)->void:
	if not bind_action.is_valid():
		feedback.text="결속 서비스가 연결되지 않았습니다."
		return
	for row in item_rows:
		if str(row.get("instance_id",""))!=instance_id:continue
		var preview:Dictionary=row.get("effect_preview",{})
		pending_instance_id=instance_id
		confirmation.dialog_text="%s\nMP %d · 사거리 %d\n\n획득물 1개를 소비하고 빈 결속 한도 1칸을 사용합니다.\n현재 해제할 수 없습니다. 결속할까요?"%[
			str(preview.get("label",row.get("ability_id","이능"))),
			int(preview.get("cost",0)),int(preview.get("range",0))]
		confirmation.popup_centered(Vector2i(300,220))
		return


func _confirm_binding()->void:
	var instance_id:=pending_instance_id
	pending_instance_id=""
	if instance_id.is_empty() or not bind_action.is_valid():return
	var result:Variant=bind_action.call(instance_id)
	if not result is Dictionary or not bool(result.get("accepted",false)):
		feedback.text=str(result.get("message","이능을 결속할 수 없습니다.")) if result is Dictionary else "이능을 결속할 수 없습니다."
		return
	feedback.text="%s 결속 완료 · 아이템을 소비했습니다."%str(result.get("ability_id","이능"))
	if result.get("bindings",[]) is Array:
		binding_rows=result.bindings.duplicate(true)
	for index in range(item_rows.size()-1,-1,-1):
		if str(item_rows[index].get("instance_id",""))==instance_id:item_rows.remove_at(index)
	_refresh()


func _remove_selected()->void:
	if not remove_action.is_valid():return
	var result:Variant=remove_action.call(actor_id,selected_slot)
	feedback.text=str(result.get("message","이능을 해제할 수 없습니다.")) if result is Dictionary else "이능을 해제할 수 없습니다."
