extends RefCounted

## A destination is an order, never a teleport. Every step uses canonical
## pathfinding, occupancy, movement cost and the individual action scheduler.
const Action=preload("res://sim/party_action_command.gd")

static func assess(sim,actor_id:int,goal:Vector2i)->Dictionary:
	var world=sim.world;var party=world.party_encounter
	if party==null or party.safe_phase!="ENGAGED" or not world.is_settled() \
			or actor_id not in party.active_party_member_ids \
			or party.member(actor_id).presence!="DEPLOYED" or not world.can_act(actor_id,world.world_time):
		return {"accepted":false,"message":"행동 가능한 파티원을 선택하세요."}
	if not world.in_bounds(goal):return {"accepted":false,"message":"맵 안의 타일을 선택하세요."}
	var path:Dictionary=sim.pathfinder.find_path(actor_id,goal)
	return {"accepted":bool(path.get("found",false)),
		"message":"이동 후 위치 유지" if path.get("found",false) else "이동할 수 없는 타일입니다."}

static func action(sim,actor_id:int,goal:Vector2i,fallback):
	if sim.world.entities[actor_id].position==goal:
		# Hold formation but retain basic attacks against enemies already in reach.
		return fallback if fallback.type=="MELEE" else Action.hold(actor_id)
	var path:Dictionary=sim.pathfinder.find_path(actor_id,goal)
	if path.get("found",false) and path.path.size()>1:
		var move=Action.move_to(actor_id,path.path[1])
		if sim.party_coordinator._action_error(move).is_empty():return move
	# Temporary obstruction: wait and replan on the next actual action.
	return Action.hold(actor_id)
