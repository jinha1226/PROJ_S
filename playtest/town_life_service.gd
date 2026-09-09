extends RefCounted
## Public-town / private-home boundary and company membership. Commands, not
## UI refreshes, change canonical state; every command replays from the journal.
const Rules=preload("res://sim/town_life_rules.gd")
const Work=preload("res://sim/base_work_rules.gd")
const Settlement=preload("res://sim/base_settlement_rules.gd")
const Emotion=preload("res://sim/party_emotion_model.gd")
const Rest=preload("res://playtest/base_rest_service.gd")
const Population=preload("res://sim/town_population_rules.gd")

static func overview(session)->Dictionary:
	if session.sim==null:return {"enabled":false}
	var world=session.sim.world;var party=world.party_encounter
	var life:=Rules.state(world.events)
	if not life.enabled:return life
	var field_count:=Rules.field_count(world)
	var company_count:=Rules.living_company_count(world)
	var completed:=Rules.successful_returns(world.events)
	var pending:Array[int]=[]
	for index in completed:
		if index not in life.claimed:pending.append(index)
	var rows:Array[Dictionary]=[]
	for id in party.party_member_ids:
		var member=party.member(id);var entity=world.entities.get(id)
		if entity==null or member==null or member.presence=="EXILED":continue
		if world.combatant_states[id].life_state=="DEAD":continue
		var active:bool=id in party.active_party_member_ids
		var joined:bool=id in life.members
		var identity:=Population.identity(str(entity.display_name))
		var talks:Array=life.talks.get(str(id),[])
		var talked:bool=int(party.expedition_cycle.expedition_index) in talks
		var threshold:=1
		var temperament:="대담함"
		if member.personality_profile!=null:
			threshold=1 if member.personality_profile.value("X")>=450 else 2
			temperament="사교적" if threshold==1 else "신중함"
		# The original companion is the accessible first contact, without
		# throwing away their actual personality or combat decisions.
		if str(entity.display_name)=="나래":threshold=1
		var relation:Dictionary={} if id==world.party_control_actor_id() else session.sim.relationships.effective_relation(id,world.party_control_actor_id())
		var grievance:int=int(relation.get("personal",{}).get("grievance",0))
		var join_reason:=""
		if completed.is_empty():join_reason="첫 원정에서 물자를 가져온 뒤 동행을 제안하세요"
		elif talks.size()<threshold:join_reason="서로 알아가는 중 · 대화 %d/%d"%[talks.size(),threshold]
		elif grievance>=30:join_reason="관계가 나빠 동행을 원하지 않습니다"
		elif int(member.stress)>=700:join_reason="불안이 커서 먼저 휴식이 필요합니다"
		elif world.combatant_states[id].life_state!="ACTIVE":join_reason="먼저 치료가 필요합니다"
		if not identity.explores:join_reason="마을에서 %s 일을 맡고 있습니다"%str(identity.job)
		elif not life.house_owned and company_count>=2:join_reason="더 많은 대원이 머물려면 탐험대의 집이 필요합니다"
		elif company_count>=6:join_reason="탐험대 정원은 여섯 명입니다"
		var roster_full:bool=field_count>=Rules.FIELD_LIMIT
		var activity:=Population.town_activity(str(entity.display_name),id,int(life.visits),member.personality_profile)
		if joined and active and party.expedition_cycle.phase=="DUNGEON":activity={"label":"원정 중","location":"던전","tile":[7,12]}
		rows.append({"entity_id":id,"display_name":str(entity.display_name),"health":int(entity.health),
			"species_id":str(entity.species_id),
			"max_health":int(entity.max_health),"active":active,"joined":joined,"temperament":temperament,
			"occupation":identity.job,"adventurer":bool(identity.explores),
			"activity":activity.label,"tile":activity.tile,"location":activity.location,
			"facility_id":str(activity.get("facility_id","DUNGEON")),
			"can_talk":id!=world.party_control_actor_id() and not talked,"talks":talks.size(),
			"can_join":not joined and join_reason.is_empty(),"join_reason":join_reason,
			"can_assign":joined and not active and not roster_full and world.combatant_states[id].life_state=="ACTIVE",
			"can_reserve":active and id!=world.party_control_actor_id() and world.combatant_states[id].life_state=="ACTIVE" and world.combatant_states[id].status_rows.is_empty(),
			"can_rest":joined and _needs_rest(member,world.world_time) and session.town_gold()>=session.TOWN_SHRINE_COST,
			"trust":int(relation.get("personal",{}).get("trust_delta",0))})
	_place_residents(rows)
	var reason:=""
	if life.house_owned:reason="이미 탐험대의 집이 있습니다"
	elif completed.size()<Rules.REQUIRED_RETURNS:reason="물자를 가져온 원정 %d/%d"%[completed.size(),Rules.REQUIRED_RETURNS]
	elif company_count<2:reason="먼저 동료 한 명을 영입하세요"
	elif session.town_gold()<Rules.HOUSE_COST:reason="집 구입에 %d골드가 필요합니다"%Rules.HOUSE_COST
	life.merge({"residents":rows,"completed_returns":completed.size(),"pending_rewards":pending,
		"reward_gold":pending.size()*Rules.BOUNTY,"gold":session.town_gold(),
		"house_cost":Rules.HOUSE_COST,"can_acquire":reason.is_empty(),"house_reason":reason,
		"field_limit":Rules.FIELD_LIMIT,"active_count":field_count,
		"phase":str(party.expedition_cycle.phase),"stage":"탐험대의 집" if life.house_owned else (
			"여관 · 동료와 함께" if company_count>1 else "여관 · 혼자 시작"),
		"settlement":_public_map(),"work":{}},true)
	return life

static func _public_map()->Dictionary:
	var buildings:=Settlement.buildings([], {"STORAGE":2,"LODGE":3,"CLINIC":2})
	for row in buildings:
		row.label={"LODGE":"여관","STORAGE":"보관소","CLINIC":"치유소","ARMORY":"대장간"}.get(row.type_id,row.label)
	return {"width":16,"height":16,"tiles":Settlement.tiles(),"buildings":buildings,"build_options":[]}

static func _place_residents(rows:Array)->void:
	var occupied:Array=[]
	var buildings:=Settlement.buildings([],{})
	for row in rows:
		var origin:=Vector2i(int(row.tile[0]),int(row.tile[1]));var placed:=false
		for radius in range(5):
			for dy in range(-radius,radius+1):
				for dx in range(-radius,radius+1):
					var p:=origin+Vector2i(dx,dy)
					if p in occupied or p in Settlement.BLOCKED_TILES or p.x<1 or p.x>14 or p.y<1 or p.y>14:continue
					var blocked:=false
					for building in buildings:
						if Rect2i(Vector2i(building.tile_origin[0],building.tile_origin[1]),Vector2i(building.footprint[0],building.footprint[1])).has_point(p):blocked=true;break
					if blocked:continue
					row.tile=[p.x,p.y];occupied.append(p);placed=true;break
				if placed:break
			if placed:break

static func _needs_rest(member,time:int)->bool:
	if int(member.stress)>0:return true
	var projection:=Emotion.town_rest_projection(member.emotion_state,time)
	for key in Emotion.TOWN_REST_REDUCTION:
		if int(projection.before[key])>0:return true
	return false

static func commit(session,operation:Dictionary)->Dictionary:
	var error:=Rules.operation_error(operation)
	if not error.is_empty():return _reject(error,"올바르지 않은 마을 명령입니다")
	if session.sim==null or session.scenario_id!=session.DUO_SCENARIO_ID:return _reject("town_life_unavailable","이 원정에서는 사용할 수 없습니다")
	var world=session.sim.world;var party=world.party_encounter
	var action:=str(operation.action)
	var life:=Rules.state(world.events)
	if action=="START":
		if life.enabled or not session.command_journal.is_empty():return _reject("town_life_started","새 게임에서만 여관 생활을 시작할 수 있습니다")
	elif not life.enabled or party.expedition_cycle.phase!="TOWN":return _reject("town_required","마을에서만 가능합니다")
	if not Work.current(world.events).is_empty():return _reject("base_work_busy","진행 중인 작업을 먼저 마치거나 취소하세요")
	var view:Dictionary=overview(session) if life.enabled else {}
	var id:=int(operation.get("entity_id","-1"));var row:Dictionary={}
	for resident in view.get("residents",[]):
		if int(resident.entity_id)==id:row=resident;break
	if action in ["TALK","JOIN","ASSIGN","RESERVE","REST"]:
		if row.is_empty():return _reject("town_resident_missing","이 인물은 마을에서 만날 수 없습니다")
		var field:String={"TALK":"can_talk","JOIN":"can_join","ASSIGN":"can_assign","RESERVE":"can_reserve","REST":"can_rest"}[action]
		if not bool(row[field]):return _reject("town_action_unavailable",str(row.join_reason) if action=="JOIN" else "지금은 할 수 없습니다")
	if action=="CLAIM" and view.pending_rewards.is_empty():return _reject("town_reward_missing","물자를 가져온 원정의 보상을 받을 수 있습니다")
	if action=="ACQUIRE" and not view.can_acquire:return _reject("town_house_unavailable",str(view.house_reason))
	var captured:Variant=session.sim.snapshot()
	if not captured is Dictionary or captured.is_empty():return _reject("snapshot_unavailable","현재 상태를 보관할 수 없습니다")
	var rollback:Dictionary=captured
	var journal_size:int=session.command_journal.size()
	var event;var ok:=true;var message:=""
	var data:={"expedition_index":int(party.expedition_cycle.expedition_index),"entity_id":str(id)}
	match action:
		"START":
			data["founder_id"]=str(party.protagonist_id)
			event=world.emit_event(Rules.START_EVENT,party.protagonist_id,-1,party.group_anchor,0,-1,data)
			for member_id in party.active_party_member_ids.duplicate():
				if member_id==party.protagonist_id:continue
				party.active_party_member_ids.erase(member_id);party.member(member_id).presence="RECRUITABLE"
			message="여관방에서 첫 원정을 준비합니다. 먼저 물자를 구해 돌아오세요."
		"TALK":
			event=world.emit_event("town.conversation",world.party_control_actor_id(),id,party.group_anchor,1,-1,data)
			# Sharing useful expedition information is a small, remembered aid.
			ok=event!=null and session.sim.relationships.record_aid(id,world.party_control_actor_id(),event.id,10)
			message="%s와 원정 이야기를 나눴습니다. 이번 방문의 대화가 관계에 남습니다."%str(row.display_name)
		"JOIN","ASSIGN":
			if action=="JOIN":
				event=world.emit_event("town.company_joined",world.party_control_actor_id(),id,party.group_anchor,1,-1,data)
				if not life.house_owned and Rules.living_company_count(world)>2:
					ok=false;message="여관 생활 중에는 탐험대원이 두 명까지 함께 머물 수 있습니다"
			if ok and Rules.field_count(world)<Rules.FIELD_LIMIT:
				# Existing equip/roster path, journaled only as the enclosing command.
				if action=="JOIN":ok=bool(session._apply_roster_change("RECRUIT",id,false).get("accepted",false))
				else:
					party.active_party_member_ids.append(id);party.active_party_member_ids.sort()
					party.member(id).presence="GROUPED";world.entities[id].position=party.group_anchor
				event=world.emit_event("town.company_assigned",world.party_control_actor_id(),id,party.group_anchor,1,-1,data)
			if ok and action=="JOIN":ok=_equip_new_resident(session,id)
			message="%s · %s"%[str(row.display_name),"탐험대 합류" if action=="JOIN" else "원정에 편성했습니다"] if ok else message
		"RESERVE":
			party.active_party_member_ids.erase(id);party.member(id).presence="RECRUITABLE"
			event=world.emit_event("town.company_reserved",world.party_control_actor_id(),id,party.group_anchor,0,-1,data)
			message="%s는 마을에서 대기합니다. 장비와 관계는 유지됩니다."%str(row.display_name)
		"REST":
			# Same physical/emotional transaction as the private lodge, immediate
			# paid public service; no private building or clock required.
			event=world.emit_event("town.inn_payment",world.party_control_actor_id(),id,party.group_anchor,session.TOWN_SHRINE_COST,-1,{"cost":session.TOWN_SHRINE_COST})
			if event!=null:event=Rest.complete(session,{"worker_id":id,"gold_cost":session.TOWN_SHRINE_COST,"order_id":-1})
			message="%s가 여관에서 휴식했습니다."%str(row.display_name)
		"CLAIM":
			for index in view.pending_rewards:
				event=world.emit_event("town.expedition_reward",world.party_control_actor_id(),-1,party.group_anchor,Rules.BOUNTY,-1,{"expedition_index":index,"gold":Rules.BOUNTY})
				if event==null:ok=false;break
			message="원정 물자 조사 보상 · %d골드"%int(view.reward_gold)
		"ACQUIRE":
			event=world.emit_event("town.house_acquired",world.party_control_actor_id(),-1,party.group_anchor,Rules.HOUSE_COST,-1,{"cost":Rules.HOUSE_COST})
			message="탐험대의 집을 구했습니다. 창고와 숙소를 확장하고 작업실을 지을 수 있습니다."
	party.revision+=1
	if action=="START" and event!=null:
		ok=bool(session.base_return().get("accepted",false))
		if ok:ok=session._ensure_town_guild_candidates()
	var audit:String=world.world_state_error()
	if not ok or event==null or not audit.is_empty():
		session.sim=session.SimulatorScript.from_snapshot(rollback)
		session.command_journal.resize(journal_size)
		return _reject(audit if not audit.is_empty() else "town_life_failed",message if not message.is_empty() else "마을 행동을 완료하지 못했습니다")
	session.command_journal.resize(journal_size)
	session.command_journal.append({"kind":"town_life","operation":operation.duplicate(true)})
	return {"accepted":true,"reason":"ok","message":message}

static func _reject(reason:String,message:String)->Dictionary:
	return {"accepted":false,"reason":reason,"message":message}

static func _equip_new_resident(session,id:int)->bool:
	var world=session.sim.world
	var inventory=world.item_state.inventory(id)
	if inventory!=null and inventory.equipped_item("MAIN_HAND")!=null:return true
	var weapon:String=Population.identity(str(world.entities[id].display_name)).weapon
	var granted:Dictionary=session.ItemOperationsScript.commit_grant(world,id,weapon,1,world.entities[id].position,"TOWN_COMPANY_EQUIPMENT")
	return bool(granted.get("accepted",false)) and bool(session.ItemOperationsScript.commit_equip(world,id,str(granted.instance_id),"MAIN_HAND",world.entities[id].position,0).get("accepted",false))
