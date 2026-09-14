extends HBoxContainer
const Touch=preload("res://playtest/stage_touch_button.gd")
const Portrait=preload("res://playtest/stage_portrait.gd")
var _signature:Array=[]
var _page:=0
func _init():
	name="StageContextBar";custom_minimum_size.y=84;add_theme_constant_override("separation",4)
static func style_button(b:Button):
	preload("res://playtest/stage_button_skin.gd").apply(b)
func button(label:String,node_name:String)->Button:
	var b=Touch.new();b.name=node_name;b.text=label;b.custom_minimum_size=Vector2(44,84)
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.clip_text=true
	b.add_theme_font_size_override("font_size",14);style_button(b)
	add_child(b);return b
func sync(host):
	visible=host.session.room_enabled()
	if not visible:return
	var s=host.session;var active:bool=s.round_active();var r:Dictionary=s.round_status()
	var members:Array=s.party_cards();var ids:Array=members.map(func(row):return int(row.entity_id))
	var selected:int=host.selected_member_id if host.selected_member_id in ids else s.sim.world.party_control_actor_id()
	var skills:Array=s.active_skill_rows(selected) if active else []
	var loot:int=s.ground_item_count_at_protagonist() if r.phase!="DEPLOYMENT" else 0
	var signature:Array=[active,r.phase,r.cursor,r.plan_revision,selected,ids,skills.map(func(row):return row.skill_id),_page,loot]
	if signature!=_signature:
		_signature=signature
		for child in get_children():remove_child(child);child.queue_free()
		for row in members:
			if active and int(row.entity_id)!=selected:continue
			if not active and get_child_count()>=3:break
			var id:int=row.entity_id;var portrait=Portrait.new();portrait.name="StagePortrait%d"%id
			portrait.custom_minimum_size=Vector2(64,84);portrait.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			style_button(portrait);add_child(portrait)
			portrait.set_skin_accent(id==selected)
			portrait.pressed.connect(func():host._open_member_detail(id,"STATUS"))
			portrait.tooltip_text=str(row.display_name)+" · 상태 / 숙련 / 가방"
		if active:
			for i in range(2):
				var b:=button("—","StageSkill%d"%i)
				b.held.connect(func():_page+=1;_signature=[];sync(host))
				b.pressed.connect(func():
					var skill:Dictionary=b.get_meta("skill",{})
					if not skill.is_empty():host._on_manual_skill_selected(selected,str(skill.skill_id),str(skill.label)))
			var proceed:=button("배치 완료" if r.phase=="DEPLOYMENT" else "진행 ▶","StageProceed")
			proceed.set_skin_accent(true)
			proceed.pressed.connect(host._on_product_execute)
		if loot>0:
			var pickup:=button("줍기\n%d"%loot,"StagePickup")
			pickup.pressed.connect(func():host._on_product_pickup();host._request_refresh())
	for row in members:
		var portrait=get_node_or_null("StagePortrait%d"%int(row.entity_id))
		if portrait!=null:portrait.actor=row;portrait.queue_redraw()
	if active:
		var pages:=maxi(1,ceili(float(skills.size())/2))
		for i in range(2):
			var b=get_node("StageSkill%d"%i);var index:=(_page%pages)*2+i
			var row:Dictionary=skills[index] if index<skills.size() else {}
			b.set_meta("skill",row)
			b.text="%s\nMP %d"%[row.label,row.cost] if not row.is_empty() else "빈 슬롯"
			b.disabled=r.phase=="DEPLOYMENT" or row.is_empty() or host.grid.stage_motion_busy()
			b.set_skin_accent(not row.is_empty() and host._battle_target_actor_id==selected and host._battle_target_skill_id==str(row.get("skill_id","")))
			b.tooltip_text=str(row.get("message","변이를 획득하면 사용할 수 있습니다"))+" · 길게 눌러 다음 스킬"
		var proceed=get_node("StageProceed")
		proceed.disabled=r.phase=="RESOLVING" or host.grid.stage_motion_busy()
		if r.get("individual",false) and r.phase!="DEPLOYMENT":
			var current:Dictionary=r.order[r.cursor] if r.cursor<r.order.size() else {}
			proceed.text="적 턴 진행" if not current.get("ally",false) else "행동 실행" if current.get("type","HOLD")!="HOLD" or not current.get("path",[]).is_empty() else "턴 종료"
			for i in range(2):get_node("StageSkill%d"%i).disabled=get_node("StageSkill%d"%i).disabled or not current.get("ally",false)
	var pickup=get_node_or_null("StagePickup")
	if pickup!=null:pickup.disabled=host.grid.stage_motion_busy() or r.phase=="RESOLVING"
