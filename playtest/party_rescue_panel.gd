extends PanelContainer

const Rules=preload("res://sim/party_rescue_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
var host
var rows:VBoxContainer

func _init()->void:
	name="PartyRescuePanel"
	rows=VBoxContainer.new();add_child(rows)
	z_index=30

func refresh(p_host)->void:
	host=p_host
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var w=host.session.sim.world
	visible=false
	if not Rules.enabled(w) or not host.session.field_turns_active():return
	var ids:Array[int]=Rules.downed_ids(w)
	var actor:int=w.party_control_actor_id()
	var active_links:Dictionary=Rules.links(w)
	if not ids.is_empty():
		_label("조작 중 · "+str(w.entities[actor].display_name)+" · 기본 행동 1회 = 1턴")
		_label("주변의 적을 따돌리면 HP 1로 회복합니다.")
	for id in ids:
		var remaining:int=maxi(0,w.combatant_states[id].downed_resolve_at-w.world_time)
		_label("%s · 전투불능 · %.1f턴 남음"%[w.entities[id].display_name,remaining/100.0])
		var action=Action.new("ASSIST",actor,Vector2i(-1,-1),id)
		var reason:String=host.session.sim.party_coordinator._action_error(action)
		_button("%s 부축하기 (1턴)"%w.entities[id].display_name,action,not reason.is_empty())
		if not reason.is_empty() and not active_links.has(actor):
			_label({"assist_not_adjacent":"바로 옆으로 이동하세요.","party_actor_unavailable":"행동 가능한 동료가 필요합니다.","party_actor_busy":"행동 시간이 아직 남았습니다.","target_already_assisted":"다른 동료가 부축하고 있습니다."}.get(reason,"지금은 부축할 수 없습니다."))
	if active_links.has(actor):
		_label("부축 중 · 이동 시간 1.5배 · 이동하면 동료가 따라옵니다")
		_button("부축 내려놓기 (1턴)",Action.new("RELEASE",actor))
	if (not w.can_act(actor,w.world_time) or w.party_encounter.member(actor).busy_until>w.world_time):
		_button("위기 상황 · 1턴 진행",Action.new("CRISIS",actor))
	for id in w.party_encounter.active_party_member_ids:
		var source=Rules.dialogue_source(w,actor,id)
		if source==null:continue
		_label("휴식 대화 · %s\n%s가 %s를 부축해 구했습니다."%[w.entities[id].display_name,w.entities[source.actor_id].display_name,w.entities[source.target_id].display_name])
		_button("무사해서 다행이야 (1턴)",Action.new("REASSURE",actor,Vector2i(-1,-1),id))
		_button("다음에도 서로 돕자 (1턴)",Action.new("PROMISE",actor,Vector2i(-1,-1),id))
		break
	visible=rows.get_child_count()>0
	if visible:
		position=Vector2(12,90)
		size=Vector2(minf(host.size.x-24,360),0)

func _label(message:String)->void:
	var label=Label.new();label.text=message
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x=260
	rows.add_child(label)

func _button(title:String,action,disabled:bool=false)->void:
	var button=Button.new();button.text=title;button.disabled=disabled
	button.custom_minimum_size.y=44
	button.pressed.connect(func():
		var result:Dictionary=host.session.commit_field_action(action)
		host.notice_text="행동을 완료했습니다." if bool(result.get("accepted",false)) else "지금은 실행할 수 없습니다. · "+str(result.get("reason",""))
		if bool(result.get("accepted",false)) and action.type in ["PROMISE","REASSURE"]:
			var member=host.session.sim.world.party_encounter.member(action.target_id)
			var warm:bool=member.personality_profile==null or member.personality_profile.value("A")>=500
			host.notice_text=("다음에는 내가 네 곁을 지킬게." if warm else "알겠어. 다음엔 내 차례야.") if action.type=="PROMISE" else ("고마워. 네가 와 줄 줄 알았어." if warm else "…덕분에 살았어.")
		host.action_feedback_text=host.notice_text
		host._request_refresh())
	rows.add_child(button)
