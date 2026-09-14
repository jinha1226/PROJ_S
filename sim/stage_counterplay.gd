extends RefCounted
const Rooms=preload("res://sim/room_transition_rules.gd")
static var CONFIG:Dictionary=preload("res://sim/json_content_loader.gd").load_document("res://data/content/stage_counterplay.json")

static func enabled(w)->bool:return Rooms.enabled(w)
static func key(w)->String:
	return "%d:%d"%[w.party_encounter.nine_room_floor.floor_index,w.party_encounter.nine_room_floor.active_room_id]
static func current(w)->Dictionary:
	return w.party_encounter.round_combat.stage_rooms.get(key(w),{}) if enabled(w) else {}
static func enemies(w)->Array:
	return w.party_encounter.enemy_ids.filter(func(id):return Rooms.actor_active(w,id) and w.is_unresolved_enemy(id))

static func prepare(sim,r:Dictionary)->bool:
	var w=sim.world;var room_key:=key(w)
	if not r.stage_rooms.has(room_key):
		var p:Vector2i=w.entities[w.party_control_actor_id()].position
		r.stage_rooms[room_key]={"started":false,"turn":0,"waves":0,"entry":[p.x,p.y]}
	if not r.stage_rooms[room_key].started:
		r.phase="DEPLOYMENT"
		return true
	# Movement happens before publishing attacks, never during UI observation.
	for id in enemies(w):
		if not w.can_act(id,w.world_time):continue
		var phase_event=w.emit_event("stage.enemy_movement",id,-1,w.entities[id].position,0,-1,{"round_id":r.round_id,"room":room_key})
		if phase_event==null:return false
		for i in range(load("res://sim/round_combat_rules.gd").move_budget(w,id)):
			var p:Dictionary=sim.party_coordinator.forecast_enemy_action(id)
			if p.get("action_type","")!="MOVE":break
			var to:=Vector2i(p.destination[0],p.destination[1]);var assessment=sim.movement.assess_move(id,to)
			if not assessment.accepted:break
			var old:Vector2i=w.entities[id].position
			var cost:int=preload("res://sim/field_action_timing.gd").duration(w,id,"MOVE",int(preload("res://sim/terrain_registry.gd").definition(str(assessment.terrain_id)).move_time_cost))
			if sim.movement.commit_preflighted_move(id,to,str(assessment.terrain_id),cost,phase_event.id)==null:return false
			w.reindex_entity_occupancy(id,old,to)
	return true

static func deployment_error(w,p:Dictionary)->String:
	if p.action.type!="HOLD" or not p.item_operation.is_empty():return "deployment_move_only"
	for other in w.party_encounter.round_combat.plans.values():
		if other.actor_id!=p.actor_id and w.party_encounter.member(int(other.actor_id))!=null and other.destination==p.destination:return "deployment_occupied"
	var entry:Array=current(w).entry;var origin:=Vector2i(entry[0],entry[1])
	for raw in p.path:
		var cell:=Vector2i(raw[0],raw[1])
		if not Rooms.current(w,cell) or Rooms.distance(origin,cell)>int(CONFIG.deployment_radius):return "deployment_outside_entry"
	return ""

static func deploy(sim)->Dictionary:
	var w=sim.world;var r:Dictionary=w.party_encounter.round_combat
	var rollback:Dictionary=sim.capture_rollback_memento(false);var start:int=w.events.size()
	for id in w.party_encounter.active_party_member_ids:
		var p:Dictionary=r.plans.get(str(id),{})
		if p.is_empty():continue
		var error:=deployment_error(w,p)
		if not error.is_empty():
			sim.restore_rollback_memento(rollback);return {"accepted":false,"reason":error}
		for raw in p.path:
			var cell:=Vector2i(raw[0],raw[1]);var a=sim.movement.assess_move(id,cell)
			if not a.accepted:
				sim.restore_rollback_memento(rollback);return {"accepted":false,"reason":"deployment_blocked"}
			var old:Vector2i=w.entities[id].position
			var cost:int=preload("res://sim/field_action_timing.gd").duration(w,id,"MOVE",int(preload("res://sim/terrain_registry.gd").definition(str(a.terrain_id)).move_time_cost))
			if sim.movement.commit_preflighted_move(id,cell,str(a.terrain_id),cost)==null:
				sim.restore_rollback_memento(rollback);return {"accepted":false,"reason":"deployment_failed"}
			w.reindex_entity_occupancy(id,old,cell)
	current(w).started=true
	r.phase="EXPLORATION"
	w.party_encounter.group_anchor=w.entities[w.party_control_actor_id()].position
	if not load("res://sim/round_plan_service.gd").begin(sim):
		sim.restore_rollback_memento(rollback);return {"accepted":false,"reason":"deployment_plan_failed"}
	return {"accepted":true,"reason":"deployment_complete","completed":false,"time_cost":0,"slots":[],"events_start":start,"events_end":w.events.size()}

static func finish_round(sim)->bool:
	var w=sim.world;var state:=current(w)
	if state.is_empty():return true
	state.turn=int(state.turn)+1
	var living:=enemies(w)
	# Clearing the last enemy on the deadline wins; there is no empty-room wave.
	if living.is_empty() or w.entities[w.party_control_actor_id()].health<=0:return true
	if int(state.turn)<(int(state.waves)+1)*int(CONFIG.rounds_per_wave):return true
	var count:=mini(int(CONFIG.wave_size),int(CONFIG.max_active_enemies)-living.size())
	if count<=0:return true
	var cells:Array[Vector2i]=[];var bounds:=Rooms.bounds(w)
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var p:=Vector2i(x,y)
			if x not in [bounds.position.x,bounds.end.x-1] and y not in [bounds.position.y,bounds.end.y-1]:continue
			if not Rooms.safe(w,p):continue
			if w.entities.values().any(func(e):return w.occupies_tile(e.id) and e.position==p):continue
			if w.party_encounter.active_party_member_ids.any(func(id):return Rooms.distance(w.entities[id].position,p)<=1):continue
			cells.append(p)
	if cells.is_empty():return true # Blocked edges postpone, never overwrite an actor.
	var spawned:Array=[]
	for i in range(mini(count,cells.size())):
		var species:String=CONFIG.reinforcement_species[i%CONFIG.reinforcement_species.size()]
		var profile:Dictionary=preload("res://sim/enemy_perception_registry.gd").profile(species)
		var party=w.party_encounter
		var tags:Array=["party_enemy","campaign_floor:%d"%party.nine_room_floor.floor_index,"campaign_expedition:%d"%party.expedition_cycle.expedition_index,"encounter_group:ROOM_%d"%party.nine_room_floor.active_room_id,"stage_reinforcement"]
		var enemy=w.add_entity(str(profile.entity_kind),str(profile.display_name),cells[i],int(profile.max_health),tags,species,"enemy","GOBLIN_MELEE_V1" if species=="goblin" else preload("res://sim/dcss_enemy_registry.gd").loadout_id(species))
		if enemy==null:return false
		party.enemy_ids.append(enemy.id);party.enemy_busy_rows[enemy.id]=w.world_time
		party.enemy_awareness_rows[enemy.id]=preload("res://sim/enemy_awareness_state.gd").new(enemy.id,enemy.position)
		spawned.append(str(enemy.id))
	w.party_encounter.enemy_ids.sort();state.waves=int(state.waves)+1
	return w.emit_event("stage.reinforced",w.party_control_actor_id(),-1,w.entities[w.party_control_actor_id()].position,spawned.size(),-1,{"room":key(w),"wave":state.waves,"entity_ids":spawned})!=null

static func recent_log(w)->String:
	var lines:Array[String]=[]
	for i in range(w.events.size()-1,maxi(-1,w.events.size()-65),-1):
		var event=w.events[i];var actor=w.entities.get(event.actor_id);var target=w.entities.get(event.target_id)
		if event.type=="stage.reinforced":lines.append("적 %d마리가 증원되었습니다."%event.magnitude)
		elif event.type.begins_with("combat.") and event.type.ends_with("_damage") and target!=null:
			lines.append("%s · %d 피해"%[target.display_name,event.magnitude])
		elif event.type=="action.move" and actor!=null:lines.append("%s 이동"%actor.display_name)
		if lines.size()==3:break
	lines.reverse();return "\n".join(lines)

static func status(w)->Dictionary:
	var state:=current(w)
	return {"turn":int(state.get("turn",0)),"waves":int(state.get("waves",0)),"remaining":maxi(0,(int(state.get("waves",0))+1)*int(CONFIG.rounds_per_wave)-int(state.get("turn",0)))}
