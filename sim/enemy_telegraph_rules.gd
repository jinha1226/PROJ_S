extends RefCounted
## Pure input-boundary plans. UI and execution read the same pre-action world.
const Rules=preload("res://sim/field_turn_rules.gd")
const Board=preload("res://sim/enemy_squad_blackboard.gd")

static func plans(sim)->Dictionary:
	var result:Dictionary={}
	var world=sim.world
	if not Rules.active(world):return result
	var board:Dictionary={}
	for id in world.party_encounter.enemy_ids:
		if not Rules.visible(world,id):continue
		if board.is_empty():board=Board.build(world)
		var row:Dictionary=sim.party_coordinator.forecast_enemy_action(id,board)
		if not bool(row.get("accepted",false)):
			row=sim.party_coordinator.forecast_exploration_patrol(id,world.step_index+1,world.step_index+1,world.world_time)
		if not bool(row.get("accepted",false)):continue
		row.target_id=int(row.get("target_id",-1))
		var target=world.entities.get(int(row.target_id))
		row.target_position=[target.position.x,target.position.y] if target!=null else [-1,-1]
		result[id]=row
	return result

static func resolve(sim,id:int,plan:Dictionary)->Dictionary:
	var row:Dictionary=plan.duplicate(true)
	var world=sim.world
	var origin:Vector2i=world.entities[id].position
	# Displacement cancels the committed action, rather than dragging its area.
	if row.from_position!=[origin.x,origin.y]:row.action_type="HOLD"
	if row.action_type=="MOVE":
		var destination:=Vector2i(int(row.destination[0]),int(row.destination[1]))
		if not sim.movement.assess_move(id,destination).accepted:row.action_type="HOLD"
	elif row.action_type=="MELEE":
		row.target_id=-1
		for member_id in world.party_encounter.active_party_member_ids:
			var actor=world.entities[member_id]
			if [actor.position.x,actor.position.y]==row.target_position and sim.melee.can_attack(id,member_id):
				row.target_id=member_id;break
		if int(row.target_id)<0:row.action_type="HOLD"
	return row

static func overlays(sim)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var batch:=plans(sim)
	for id in batch:
		var row:Dictionary=batch[id]
		if row.action_type=="HOLD":continue
		result.append({"actor_id":id,"role":"ENEMY","from_position":row.from_position,
			"ready_in":maxi(0,int(sim.world.party_encounter.enemy_busy_rows[id])-int(sim.world.world_time)),
			"type":row.action_type,"destination":row.destination,"target_position":row.target_position,
			"target_id":row.target_id,"source":"SUGGESTED","source_label":"예고",
			"source_color":"#ff6655" if row.action_type=="MELEE" else "#ffcf68",
			"opacity":0.85,"line_style":"SOLID","marker_style":"SQUARE",
			"draw_connector":true,"approximate":false,"speech_headline":""})
	return result
