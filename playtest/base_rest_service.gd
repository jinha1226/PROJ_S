extends RefCounted

const Work=preload("res://sim/base_work_rules.gd")
const Emotion=preload("res://sim/systems/party_emotion_system.gd")
const Morale=preload("res://sim/party_morale_model.gd")
const Settlement=preload("res://sim/base_settlement_rules.gd")
const WORK_STEPS:=10
const EmotionModel=preload("res://sim/party_emotion_model.gd")

static func overview(session,buildings:Array,work:Dictionary)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var world=session.sim.world;var party=world.party_encounter
	for id in session.company_member_ids():
		var member=party.member(int(id));var entity=world.entities.get(id)
		if member==null or entity==null or world.combatant_states[id].life_state!="ACTIVE":continue
		var emotional_projection:=EmotionModel.town_rest_projection(member.emotion_state,world.world_time)
		var emotional_id:="";var emotional_value:=0
		for emotion_id in EmotionModel.TOWN_REST_REDUCTION:
			var value:int=emotional_projection.before[emotion_id]
			if value>emotional_value:emotional_id=emotion_id;emotional_value=value
		var reason:=""
		if party.expedition_cycle.phase!="TOWN":reason="거점에서 휴식할 수 있습니다"
		elif not world.can_act(int(id),world.world_time) and not (session.town_life_enabled() \
			and member.presence=="RECRUITABLE" and world.combatant_states[id].status_rows.is_empty()):reason="지금은 이동할 수 없습니다"
		elif not Settlement.type_built(buildings,"LODGE"):reason="숙소가 필요합니다"
		elif not work.is_empty():reason="진행 중인 작업을 먼저 마치세요"
		elif int(member.stress)<=0 and emotional_value<=0:reason="충분히 안정되어 있습니다"
		elif session.town_gold()<session.TOWN_SHRINE_COST:reason="골드가 부족합니다"
		result.append({"entity_id":int(id),"label":str(entity.display_name),"stress":int(member.stress),
			"emotion_label":{"FEAR":"공포","ANGER":"분노","SADNESS":"슬픔","GUILT":"죄책감"}.get(emotional_id,"안정"),
			"emotion":emotional_value,"emotion_after":maxi(0,emotional_value-int(EmotionModel.TOWN_REST_REDUCTION.get(emotional_id,0))),
			"stress_after":maxi(0,int(member.stress)-session._base_lodge_recovery()),
			"cost":session.TOWN_SHRINE_COST,"can_rest":reason.is_empty(),"message":reason})
	return result

static func assess(session,entity_id:int)->Dictionary:
	var base:Dictionary=session.base_overview()
	for row in base.get("rest",[]):
		if int(row.entity_id)!=entity_id:continue
		if not bool(row.can_rest):return {"accepted":false,"reason":"base_rest_unavailable","message":row.message}
		for building in base.settlement.buildings:
			if building.type_id=="LODGE":
				return {"accepted":true,"type_id":"LODGE","cost":{},"gold_cost":row.cost,
					"tile_origin":building.tile_origin.duplicate(),"footprint":building.footprint.duplicate(),
					"work_steps":WORK_STEPS,"worker_id":entity_id}
	return {"accepted":false,"reason":"base_rest_target_missing","message":"휴식할 주민을 선택하세요."}

static func route(buildings:Array,origin:Vector2i,footprint:Vector2i)->Array:
	# Enter through the bottom door, then move to the bed. Other facilities stay
	# blocked; this is a base presentation route, not dungeon entity teleportation.
	var door:=Vector2i(origin.x+footprint.x/2,origin.y+footprint.y)
	var result:=Work.route_to_site(buildings,origin,footprint,door)
	if result.is_empty():return result
	for y in range(door.y-1,origin.y-1,-1):result.append([door.x,y])
	return result

static func complete(session,job:Dictionary):
	var world=session.sim.world;var party=world.party_encounter
	var id:=int(job.worker_id);var member=party.member(id);var entity=world.entities[id]
	# Release the reservation and charge the established shrine transaction in
	# this same atomic work step. Other purchases cannot spend reserved gold.
	var release=world.emit_event("base.rest_payment_released",id,-1,party.group_anchor,
		int(job.gold_cost),int(job.order_id),{"gold_cost":int(job.gold_cost)})
	if release==null:return null
	var source=world.emit_event("town.shrine_service",world.party_control_actor_id(),id,
		entity.position,int(job.gold_cost),int(job.order_id),{"schema_version":1,
			"ruleset_id":session.TOWN_SHRINE_RULESET_ID,"cost":int(job.gold_cost)})
	if source==null or not Emotion.commit_batch(world,[source]):return null
	var before:=int(member.stress);var after:=maxi(0,before-session._base_lodge_recovery())
	var mode_before:=str(member.mental_mode);var mode_after:=Morale.next_mode(mode_before,after)
	var morale=world.emit_event("party.morale_changed",id,-1,entity.position,absi(after-before),source.id,
		{"schema_version":1,"ruleset_id":Morale.RULESET_ID,"stress_before":before,
			"direct_delta":after-before,"contagion_delta":0,"recovery_delta":0,"stress_after":after,
			"mode_before":mode_before,"mode_after":mode_after,"trigger_codes":["TOWN_REST"],
			"source_event_ids":[str(source.id)]})
	if morale==null:return null
	member.stress=after;member.mental_mode=mode_after
	return world.emit_event("base.rest_completed",id,-1,party.group_anchor,before-after,int(job.order_id),
		{"stress_before":before,"stress_after":after,"gold_cost":int(job.gold_cost)})
