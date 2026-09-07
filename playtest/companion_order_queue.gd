extends RefCounted

## Transient one-action reservations, separate from turn drafts and world state.
const Action=preload("res://sim/party_action_command.gd")
const Request=preload("res://sim/party_turn_request.gd")
var orders:Dictionary={}
var encounter_id:=-1

func clear()->void:
	orders.clear();encounter_id=-1

func reserve(session,action)->Dictionary:
	var state=session.sim.world.party_encounter
	if state.safe_phase!="ENGAGED" or action.actor_id==state.protagonist_id \
			or action.actor_id not in state.party_member_ids:
		return {"accepted":false,"message":"전투 중인 동료만 지시할 수 있습니다."}
	var member=state.member(action.actor_id)
	if member==null or member.presence!="DEPLOYED":
		return {"accepted":false,"message":"행동할 수 없는 동료입니다."}
	if encounter_id!=state.encounter_id:clear()
	encounter_id=state.encounter_id
	orders[action.actor_id]=Action.from_dict(action.to_dict())
	return {"accepted":true,"message":"다음 행동을 예약했습니다. 주인공이 행동하면 실행됩니다."}

func resolve(session,direct,legacy:Dictionary)->Dictionary:
	var state=session.sim.world.party_encounter
	var selected:=legacy.duplicate()
	var consumed:Array=[]
	var cancelled:Array=[]
	if state.encounter_id!=encounter_id or state.safe_phase!="ENGAGED":
		return {"overrides":selected,"consumed":orders.keys(),"cancelled":orders.keys()}
	var ids:=orders.keys();ids.sort()
	for id in ids:
		var member=state.member(id)
		if member==null or member.presence!="DEPLOYED" or id not in state.party_member_ids:
			consumed.append(id);cancelled.append(id);continue
		if member.busy_until>session.sim.world.world_time \
				or not session.sim.world.can_act(id,session.sim.world.world_time):continue
		var action=orders[id]
		var candidate:=selected.duplicate();candidate[id]=action
		var preview:Dictionary=session.sim.preview_party_turn(Request.new(direct,_rows(candidate))).to_dict()
		if not preview.accepted:
			# Never retarget an invalid explicit order. Spend the normal action
			# holding instead; report cancellation when the turn actually commits.
			candidate[id]=Action.hold(id);cancelled.append(id)
		selected=candidate;consumed.append(id)
	return {"overrides":selected,"consumed":consumed,"cancelled":cancelled}

func consume(resolution:Dictionary)->void:
	for id in resolution.get("consumed",[]):orders.erase(id)

static func _rows(values:Dictionary)->Array:
	var rows:Array=[];var ids:=values.keys();ids.sort()
	for id in ids:rows.append({"actor_id":id,"action":values[id]})
	return rows
