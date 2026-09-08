extends RefCounted

const Items=preload("res://sim/world_item_operations.gd")

## Derive the most recently cleared battlefield from canonical history. No
## second inventory, generated rewards, or movement-triggered pickup exists.
static func context(session)->Dictionary:
	var result:={"battle_id":-1,"rows":[]}
	if session.sim==null:return result
	var world=session.sim.world
	var state=world.party_encounter
	if state==null or state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"] \
			or not world.can_act(state.protagonist_id,world.world_time):return result
	var positions:Dictionary={}
	var found:=false
	for index in range(world.events.size()-1,-1,-1):
		var event=world.events[index]
		if event.type in ["party.deployment_completed","party.disengage_completed"]:break
		if event.type.begins_with("dungeon.") or event.type.begins_with("town."):break
		if event.type=="party.regroup_completed":
			if found:break
			found=true;result.battle_id=int(event.id)
		if found and event.type=="corpse.loot_materialized" \
				and (event.actor_id in state.enemy_ids or event.actor_id in state.party_member_ids):
			positions[event.position]=true
	if not found:return result
	for row in world.item_state.ground_items.rows:
		if positions.has(row.position):
			var display:Dictionary=session._item_presentation_row(row.item,"",false)
			display["position"]=[row.position.x,row.position.y]
			result.rows.append(display)
	return result

static func take(session,battle_id:int,instance_id:String)->Dictionary:
	var available:=context(session)
	if int(available.battle_id)!=battle_id or battle_id<=0:
		return {"accepted":false,"reason":"battle_loot_unavailable"}
	var selected:Dictionary={}
	for row in available.rows:
		if str(row.instance_id)==instance_id:selected=row;break
	if selected.is_empty():return {"accepted":false,"reason":"ground_item_missing"}
	var world=session.sim.world
	if not world.is_settled():return {"accepted":false,"reason":"world_not_settled"}
	var hero_id:int=world.party_encounter.protagonist_id
	var position:=Vector2i(int(selected.position[0]),int(selected.position[1]))
	var preview:=Items.preview_pickup(world,hero_id,instance_id,position)
	if not preview.get("accepted",false):return preview
	var rollback:Variant=session.sim.capture_rollback_memento()
	if not rollback is Dictionary:return {"accepted":false,"reason":"snapshot_unavailable"}
	# After victory the party gathers selected spoils from the cleared field.
	# The event records the actual source tile; actors are never teleported.
	var result:=Items.commit_pickup(world,hero_id,instance_id,position,0)
	if not result.get("accepted",false):return result
	world.party_encounter.revision+=1
	var error:String=world.world_state_error()
	if not error.is_empty():
		session.sim.restore_rollback_memento(rollback)
		return {"accepted":false,"reason":error}
	result["time_cost"]=0
	return result
