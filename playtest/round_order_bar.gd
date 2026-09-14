extends VBoxContainer
const PixelSkin=preload("res://playtest/dark_pixel_ui_skin.gd")
var scroll:ScrollContainer
var line:HBoxContainer
var detail:Label
var _signature:Array=[]

func _init()->void:
	name="RoundOrderBar";custom_minimum_size.y=66
	scroll=ScrollContainer.new();scroll.custom_minimum_size.y=44
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	line=HBoxContainer.new();line.add_theme_constant_override("separation",3);scroll.add_child(line)
	detail=Label.new();detail.add_theme_font_size_override("font_size",11)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(detail)

func sync(host)->void:
	var status:Dictionary=host.session.round_status();visible=bool(status.active)
	if not visible:return
	var signature:Array=[status.round_id,status.plan_revision,status.phase,status.cursor,host.selected_member_id,host.selected_target_id]
	if signature==_signature:return
	_signature=signature
	for child in line.get_children():line.remove_child(child);child.queue_free()
	var preview:Dictionary=host.session.round_preview();var selected_result:Dictionary={}
	for slot in preview.get("slots",[]):
		if int(slot.actor_id)==host.selected_member_id:selected_result=slot
	for index in range(status.order.size()):
		var row:Dictionary=status.order[index];var button:=Button.new()
		button.name="RoundActor%d"%int(row.actor_id);button.custom_minimum_size=Vector2(68,44)
		var action_label:String={"HOLD":"대기","MOVE":"이동","MELEE":"공격","SKILL":"이능","HIDDEN":"미확인"}.get(row.type,row.type)
		if not row.path.is_empty():action_label="이동+"+action_label if row.type!="HOLD" else "이동"
		button.text="%d %s\n%s%s"%[index+1,row.name,action_label," ✓" if row.completed else ""]
		button.add_theme_font_size_override("font_size",11)
		button.tooltip_text="%s · HP %d/%d · 이동 %d칸 · %s"%[row.name,row.health,row.max_health,row.move_budget,"자동 작성" if row.source=="AI" else "수정한 계획"] if row.visible else "이미 발견한 적이 시야 밖에 있습니다"
		PixelSkin.apply_action_button(button,PixelSkin.BRASS if row.ally else PixelSkin.BLOOD,row.actor_id==host.selected_member_id or row.actor_id==host.selected_target_id)
		button.pressed.connect(func():
			if row.ally:host._select_member(int(row.actor_id),str(row.name))
			elif row.visible:host._focus_battle_enemy(int(row.actor_id))
		)
		line.add_child(button)
	var suffix:String=" · 예상 취소: "+str(selected_result.get("reason","")) if selected_result.get("status")=="CANCELLED" else ""
	detail.text="라운드 %d · %s%s"%[int(status.round_id),"새 위협 발견 · 남은 계획 확인 후 [계속 진행]" if status.phase=="INTERRUPTED" else "아군 선택 → 이동·공격·이능 수정 → [진행]",suffix]
	detail.tooltip_text="확률 결과는 기존 고정 난수로 예측합니다. 아직 드러나지 않은 변화가 있으면 실행을 멈춥니다."
