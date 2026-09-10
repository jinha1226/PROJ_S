class_name BaseProgressionService
extends RefCounted

var _session_ref:WeakRef
var _session:
	get:return _session_ref.get_ref()

func _init(session)->void:
	_session_ref=weakref(session)

func base_overview()->Dictionary:
	if _session.sim==null or _session.sim.world==null or _session.sim.world.party_encounter==null:
		return {"enabled":false,"phase":"UNAVAILABLE","stock":{},"carried":{},
			"capacity":0,"facilities":[],"residents":[],"last_return":{},
			"can_return":false,"return_reason":"session_not_initialized",
			"message":_session.reason_message("session_not_initialized"),"trade":[]}.duplicate(true)
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:
		return {"enabled":false,"phase":"UNAVAILABLE","stock":{},"carried":{},
			"capacity":0,"facilities":[],"residents":[],"last_return":{},
			"can_return":false,"return_reason":"base_scenario_unavailable",
			"message":"이 시나리오에서는 기지를 사용할 수 없습니다.","trade":[]}.duplicate(true)
	var state=_session.sim.world.party_encounter;var cycle=state.expedition_cycle
	var phase:=str(cycle.phase);var expedition_index:=int(cycle.expedition_index)
	var work:Dictionary=preload("res://sim/base_work_rules.gd").current(_session.sim.world.events)
	var levels:Dictionary=_session.BaseProgressionRulesScript.facility_levels(_session.sim.world.events)
	var stock:Dictionary=_session.BaseProgressionRulesScript.secured_stock(_session.sim.world.events,
		expedition_index,phase)
	var carried:Dictionary=_session.BaseProgressionRulesScript.carried(_session.sim.world.events,
		expedition_index,phase)
	var facilities:Array[Dictionary]=[]
	var settlement:Dictionary=_session._base_settlement_service.overview()
	var settlement_buildings:Array=settlement.get("buildings",[])
	for facility_id in _session.BaseProgressionRulesScript.FACILITY_IDS:
		var level:=int(levels[facility_id]);var next_level:=mini(3,level+1)
		var price:Dictionary=_session.BaseProgressionRulesScript.cost(facility_id,level+1) \
			if level<3 else {}
		var built:bool=_session.BaseSettlementRulesScript.type_built(
			settlement_buildings,facility_id)
		var can_upgrade:bool=work.is_empty() and built and phase=="TOWN" and level<3 \
			and _session.BaseProgressionRulesScript.can_afford(stock,price)
		var message:String="증축 가능" if can_upgrade else ("먼저 건설해야 합니다" if not built \
			else ("최대 레벨" if level>=3 \
			else ("마을에서 증축할 수 있습니다" if phase!="TOWN" else "자원이 부족합니다")))
		if not work.is_empty():message="진행 중인 작업을 먼저 완료하세요"
		facilities.append({"id":facility_id,
			"label":str(_session.BaseProgressionRulesScript.FACILITY_LABELS[facility_id]),
			"level":level,"max_level":3,
			"effect_text":_session.BaseProgressionRulesScript.effect_text(facility_id,level),
			"next_effect_text":_session.BaseProgressionRulesScript.effect_text(
				facility_id,next_level) if level<3 else "",
			"cost":price,"built":built,"can_upgrade":can_upgrade,"message":message})
	var residents:Array[Dictionary]=[]
	for entity_id_value in _session.company_member_ids():
		var entity_id:=int(entity_id_value);var entity=_session.sim.world.entities.get(entity_id)
		var combatant=_session.sim.world.combatant_states.get(entity_id)
		if entity==null or combatant==null or int(entity.health)<=0 \
				or str(combatant.life_state)!="ACTIVE":continue
		residents.append({"entity_id":entity_id,"display_name":str(entity.display_name),
			"is_player":entity_id==_session.sim.world.party_encounter.protagonist_id,
			"health":int(entity.health),"max_health":int(entity.max_health),
			"activity":({"PRODUCE":"물약 제조 중","REST":"휴식 중"}.get(str(work.get("action","")),"공사 중") \
				if not work.is_empty() and int(work.worker_id)==entity_id else "대기 중") if phase=="TOWN" else "원정 중"})
	var return_assessment:Dictionary=base_return_assessment()
	var trade:Array[Dictionary]=[]
	var market_built:bool=_session.town_service_available("MARKET")
	for resource_id in _session.BaseProgressionRulesScript.RESOURCE_IDS:
		var can_sell:bool=market_built and phase=="TOWN" and int(stock[resource_id])>0
		trade.append({"resource_id":resource_id,"label":{"TIMBER":"목재",
			"STONE":"석재","HERBS":"약초"}[resource_id],
			"stock":int(stock[resource_id]),"amount":1,
			"unit_price":int(_session.BaseProgressionRulesScript.TRADE_PRICES[resource_id]),
			"can_sell":can_sell,"message":"1개 판매" if can_sell else (
				"먼저 시장을 건설해야 합니다" if not market_built else (
				"마을에서 판매할 수 있습니다" if phase!="TOWN" else "재고 없음"))})
	var last_return:Dictionary={}
	if phase=="TOWN" and expedition_index>0:
		var banked:Dictionary=_session.BaseProgressionRulesScript.carried(_session.sim.world.events,
			expedition_index,"DUNGEON")
		last_return={"expedition_index":expedition_index,
			"reason":str(cycle.return_reason),"world_time":int(cycle.returned_at_world_time),
			"banked":banked,"message":"원정 물자를 기지 창고에 보관했습니다."}
	return {"enabled":true,"phase":phase,"stock":stock,"carried":carried,
		"private_home_owned":_session.private_home_available(),
		"capacity":int(_session.BaseProgressionRulesScript.STORAGE_CAPACITY[int(levels.STORAGE)]),
		"facilities":facilities,"residents":residents,"last_return":last_return,
		"can_return":bool(return_assessment.get("accepted",false)),
		"return_reason":str(return_assessment.get("reason","ok")),
		"message":str(return_assessment.get("message","")),"trade":trade,
		"settlement":settlement,"work":work,
		"gold":_session.town_gold(),
		"rest":preload("res://playtest/base_rest_service.gd").overview(_session,settlement_buildings,work),
		"production":preload("res://sim/base_production_rules.gd").overview(
			_session.sim.world,settlement_buildings,stock,work)}.duplicate(true)


func _base_cache_rows()->Array[Dictionary]:
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:return []
	if _session.sim==null or _session.sim.world==null or _session.sim.world.party_encounter==null:return []
	var cycle:Variant=_session.sim.world.party_encounter.expedition_cycle
	if cycle==null or str(cycle.phase)!="DUNGEON":return []
	var rows:Array[Dictionary]=_session.BaseResourceCacheRulesScript.caches(_session.sim.world,_session._map_layout,_session.world_seed,
		int(cycle.expedition_index))
	rows.append_array(preload("res://sim/base_monster_supply_rules.gd").caches(
		_session.sim.world,_session._map_layout))
	for row in rows:
		var gathered:=0
		for event in _session.sim.world.events:
			if event.type=="base.resource_gathered" \
					and str(event.data.get("cache_id",""))==str(row.cache_id):
				gathered+=int(event.data.get("amount",0))
		row["available_amount"]=maxi(0,int(row.amount)-gathered)
		row["available"]=int(row.available_amount)>0
	return rows


func take_battle_resource(cache_id:String)->Dictionary:
	# BattleLootService validates membership in the just-cleared battlefield.
	# Use the same carried/secured ledger and finite capacity as floor caches.
	var state=_session.sim.world.party_encounter
	if state.expedition_cycle.phase!="DUNGEON" or state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"]:
		return _session._rejection_dto("base_gather_unsafe")
	var selected:Dictionary={}
	for row in _base_cache_rows():
		if str(row.cache_id)==cache_id and bool(row.available):selected=row;break
	if selected.is_empty():return _session._rejection_dto("ground_item_missing")
	var overview:Dictionary=base_overview()
	var free:int=int(overview.capacity)-_session.BaseProgressionRulesScript.total_resources(overview.carried)
	if free<=0:return _session._rejection_dto("base_gather_capacity_full")
	var amount:int=mini(free,int(selected.available_amount))
	var event=_session.sim.world.emit_event("base.resource_gathered",int(_session.sim.world.party_control_actor_id()),-1,
		Vector2i(int(selected.position[0]),int(selected.position[1])),amount,-1,
		{"schema_version":1,"ruleset_id":"monster-salvage-v1","cache_id":cache_id,
			"resource_id":str(selected.resource_id),"amount":amount,
			"expedition_index":int(state.expedition_cycle.expedition_index),
			"floor_index":int(state.expedition_cycle.floor_index),"position":selected.position.duplicate()})
	if event==null:return _session._rejection_dto("base_gather_failed")
	return {"accepted":true,"reason":"ok","amount":amount,"resource_id":str(selected.resource_id),
		"message":"%s %d개 확보 · 귀환 시 창고 보관"%[
			preload("res://sim/base_monster_supply_rules.gd").LABELS[str(selected.resource_id)],amount]}


func _base_cache_at(position:Vector2i)->Dictionary:
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:return {}
	for row in _base_cache_rows():
		if row.position==[position.x,position.y]:return row.duplicate(true)
	return {}


func base_gather_assessment()->Dictionary:
	if _session.sim==null or _session.sim.world==null or _session.sim.world.party_encounter==null:
		return _session._rejection_dto("session_not_initialized")
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:return _session._rejection_dto("base_scenario_unavailable")
	var state=_session.sim.world.party_encounter;var cycle=state.expedition_cycle
	if cycle==null or cycle.phase!="DUNGEON":return _session._rejection_dto("base_gather_dungeon_required")
	if state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"] or not _session.sim.world.is_settled():
		return _session._rejection_dto("base_gather_unsafe")
	var hero=_session.sim.world.entities.get(_session.sim.world.party_control_actor_id())
	if hero==null or not _session.sim.world.can_act(_session.sim.world.party_control_actor_id(),_session.sim.world.world_time):
		return _session._rejection_dto("base_gather_actor_missing")
	var visible:Dictionary=_session._presentation_visible_cells(hero.position)
	var candidates:Array[Dictionary]=[]
	for row in _base_cache_rows():
		if not bool(row.available):continue
		var position:=Vector2i(int(row.position[0]),int(row.position[1]))
		if maxi(absi(position.x-hero.position.x),absi(position.y-hero.position.y))<=1 \
				and visible.has(_session._position_key(position)):
			candidates.append(row)
	if candidates.is_empty():return _session._rejection_dto("base_gather_cache_not_reached")
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.cache_id)<str(b.cache_id))
	var row:Dictionary=candidates[0]
	var levels:Dictionary=_session.BaseProgressionRulesScript.facility_levels(_session.sim.world.events)
	var carried:Dictionary=_session.BaseProgressionRulesScript.carried(_session.sim.world.events,
		int(cycle.expedition_index),"DUNGEON")
	var free:int=int(_session.BaseProgressionRulesScript.STORAGE_CAPACITY[int(levels.STORAGE)]) \
		-_session.BaseProgressionRulesScript.total_resources(carried)
	if free<=0:
		var rejected:Dictionary=_session._rejection_dto("base_gather_capacity_full")
		rejected["resource_id"]=str(row.resource_id);rejected["amount"]=0
		rejected["position"]=row.position.duplicate(true);rejected["contextual"]=true
		return rejected
	var amount:int=mini(free,int(row.available_amount))
	return _session._feedback_dto({"accepted":true,"reason":"ok","cache_id":str(row.cache_id),
		"resource_id":str(row.resource_id),"amount":amount,
		"position":row.position.duplicate(true),"cache_remaining_after":int(row.available_amount)-amount})


func base_gather()->Dictionary:
	var assessment:Dictionary=base_gather_assessment()
	if not bool(assessment.get("accepted",false)):return assessment
	var rollback_memento:Variant=_session.sim.capture_rollback_memento()
	if not rollback_memento is Dictionary:return _session._rejection_dto("snapshot_unavailable")
	var journal_size_before:int=_session.command_journal.size()
	var advanced:Dictionary=_session._advance_item_action_time()
	if not bool(advanced.get("accepted",false)):
		_session._rollback_session_transaction(rollback_memento,journal_size_before)
		return _session._rejection_dto("base_gather_time_failed")
	while _session.command_journal.size()>journal_size_before:_session.command_journal.pop_back()
	var state=_session.sim.world.party_encounter;var hero_id:=int(_session.sim.world.party_control_actor_id())
	var post_cycle=state.expedition_cycle
	if not _session.sim.world.can_act(hero_id,_session.sim.world.world_time) or post_cycle==null \
			or (post_cycle.phase=="DUNGEON" and state.safe_phase not in [
				"GROUPED","GROUPED_COMPLETE"]):
		_session._rollback_session_transaction(rollback_memento,journal_size_before)
		return _session._rejection_dto("base_gather_interrupted")
	var position:=Vector2i(int(assessment.position[0]),int(assessment.position[1]))
	var event=_session.sim.world.emit_event("base.resource_gathered",hero_id,-1,position,
		int(assessment.amount),-1,{"schema_version":1,
			"ruleset_id":_session.BaseResourceCacheRulesScript.RULESET_ID,
			"cache_id":str(assessment.cache_id),
			"resource_id":str(assessment.resource_id),"amount":int(assessment.amount),
			"expedition_index":int(state.expedition_cycle.expedition_index),
			"floor_index":int(state.expedition_cycle.floor_index),
			"position":assessment.position.duplicate(true)})
	state.revision+=1
	var error:String=_session.sim.world.world_state_error()
	if event==null or not error.is_empty():
		_session._rollback_session_transaction(rollback_memento,journal_size_before)
		return _session._rejection_dto(error if not error.is_empty() else "base_gather_failed")
	_session.command_journal.append({"kind":"base","operation":{"action":"GATHER"}})
	var result:=assessment.duplicate(true);result["event_id"]=int(event.id)
	result["carried"]=_session.BaseProgressionRulesScript.carried(_session.sim.world.events,
		int(state.expedition_cycle.expedition_index),str(state.expedition_cycle.phase))
	result["time_cost"]=_session.ITEM_ACTION_TIME_COST
	return _session._feedback_dto(result)


func base_upgrade(facility_id:String)->Dictionary:
	if not _session.private_home_available():return _session._rejection_dto("private_home_required")
	if _session.sim!=null and not preload("res://sim/base_work_rules.gd").current(_session.sim.world.events).is_empty():
		return _session._rejection_dto("base_work_busy")
	if _session.sim==null or _session.sim.world==null or _session.sim.world.party_encounter==null:
		return _session._rejection_dto("session_not_initialized")
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:return _session._rejection_dto("base_scenario_unavailable")
	var state=_session.sim.world.party_encounter;var cycle=state.expedition_cycle
	if cycle==null or cycle.phase!="TOWN":return _session._rejection_dto("base_upgrade_town_required")
	if facility_id not in _session.BaseProgressionRulesScript.FACILITY_IDS:
		return _session._rejection_dto("base_facility_unknown")
	if not _session._base_settlement_service.type_built(facility_id):
		return _session._rejection_dto("base_facility_not_built")
	var levels:Dictionary=_session.BaseProgressionRulesScript.facility_levels(_session.sim.world.events)
	var from_level:int=int(levels[facility_id])
	if from_level>=3:return _session._rejection_dto("base_facility_max_level")
	var stock:Dictionary=_session.BaseProgressionRulesScript.secured_stock(_session.sim.world.events,
		int(cycle.expedition_index),"TOWN")
	var price:Dictionary=_session.BaseProgressionRulesScript.cost(facility_id,from_level+1)
	if not _session.BaseProgressionRulesScript.can_afford(stock,price):
		return _session._rejection_dto("base_resources_insufficient")
	var rollback:Dictionary=_session.sim.snapshot();var hero_id:=int(_session.sim.world.party_control_actor_id())
	var event=_session.sim.world.emit_event("base.facility_upgraded",hero_id,-1,state.group_anchor,
		from_level+1,-1,{"schema_version":1,
			"ruleset_id":_session.BaseProgressionRulesScript.RULESET_ID,"facility_id":facility_id,
			"from_level":from_level,"to_level":from_level+1,"cost":price.duplicate(true)})
	state.revision+=1;var error:String=_session.sim.world.world_state_error()
	if event==null or not error.is_empty():
		_session.sim=_session.SimulatorScript.from_snapshot(rollback)
		return _session._rejection_dto(error if not error.is_empty() else "base_upgrade_failed")
	_session.command_journal.append({"kind":"base","operation":{"action":"UPGRADE",
		"facility_id":facility_id}})
	return _session._feedback_dto({"accepted":true,"reason":"ok","event_id":int(event.id),
		"facility_id":facility_id,"level":from_level+1,
		"stock":_session.BaseProgressionRulesScript.secured_stock(_session.sim.world.events,
			int(cycle.expedition_index),"TOWN")})


func base_sell(resource_id:String,amount:int=1)->Dictionary:
	if _session.sim==null or _session.sim.world==null or _session.sim.world.party_encounter==null:
		return _session._rejection_dto("session_not_initialized")
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:return _session._rejection_dto("base_scenario_unavailable")
	if not _session.town_service_available("MARKET"):
		return _session._rejection_dto("base_market_not_built")
	var state=_session.sim.world.party_encounter;var cycle=state.expedition_cycle
	if cycle==null or cycle.phase!="TOWN":return _session._rejection_dto("base_sell_town_required")
	if resource_id not in _session.BaseProgressionRulesScript.RESOURCE_IDS or amount<1:
		return _session._rejection_dto("base_trade_invalid")
	var stock:Dictionary=_session.BaseProgressionRulesScript.secured_stock(_session.sim.world.events,
		int(cycle.expedition_index),"TOWN")
	if int(stock[resource_id])<amount:return _session._rejection_dto("base_resources_insufficient")
	var rollback:Dictionary=_session.sim.snapshot();var hero_id:=int(_session.sim.world.party_control_actor_id())
	var unit_price:int=int(_session.BaseProgressionRulesScript.TRADE_PRICES[resource_id])
	var event=_session.sim.world.emit_event("base.resource_sold",hero_id,-1,state.group_anchor,
		amount*unit_price,-1,{"schema_version":1,
			"ruleset_id":_session.BaseProgressionRulesScript.RULESET_ID,"resource_id":resource_id,
			"amount":amount,"unit_price":unit_price,"gold":amount*unit_price})
	state.revision+=1;var error:String=_session.sim.world.world_state_error()
	if event==null or not error.is_empty():_session.sim=_session.SimulatorScript.from_snapshot(rollback)
	if event==null or not error.is_empty():return _session._rejection_dto(
		error if not error.is_empty() else "base_trade_failed")
	_session.command_journal.append({"kind":"base","operation":{"action":"SELL",
		"resource_id":resource_id,"amount":amount}})
	return _session._feedback_dto({"accepted":true,"reason":"ok","event_id":int(event.id),
		"resource_id":resource_id,"amount":amount,"gold_earned":amount*unit_price,
		"gold":_session.town_gold(),"stock":_session.BaseProgressionRulesScript.secured_stock(
			_session.sim.world.events,int(cycle.expedition_index),"TOWN")})


func base_return_assessment()->Dictionary:
	if _session.sim==null or _session.sim.world==null or _session.sim.world.party_encounter==null:
		return _session._rejection_dto("session_not_initialized")
	if _session.scenario_id!=_session.DUO_SCENARIO_ID:return _session._rejection_dto("base_scenario_unavailable")
	var state=_session.sim.world.party_encounter;var cycle=state.expedition_cycle
	if cycle==null or cycle.phase!="DUNGEON":return _session._rejection_dto("base_return_dungeon_required")
	if state.safe_phase not in ["GROUPED","GROUPED_COMPLETE"] or not _session.sim.world.is_settled():
		return _session._rejection_dto("base_return_unsafe")
	var hero=_session.sim.world.entities.get(_session.sim.world.party_control_actor_id())
	var entry:Variant=_session._map_layout.get("entry_position")
	var anchor:Variant=_session._map_layout.get("anchor_portal_position")
	if hero==null or not _session.sim.world.can_act(_session.sim.world.party_control_actor_id(),_session.sim.world.world_time):
		return _session._rejection_dto("base_return_actor_missing")
	var at_entry:bool=entry is Vector2i and hero.position==entry
	var at_active_anchor:bool=anchor is Vector2i and hero.position==anchor \
		and int(cycle.floor_index) in state.activated_anchor_portal_floors
	if not at_entry and not at_active_anchor:return _session._rejection_dto("base_return_portal_required")
	var nearby_enemy_ids:Array[int]=[]
	for enemy_id in _session.CampaignEncounterStreamScript.active_enemy_ids(_session.sim.world):
		var enemy=_session.sim.world.entities.get(enemy_id)
		if enemy!=null and maxi(absi(enemy.position.x-hero.position.x),
				absi(enemy.position.y-hero.position.y))<=3:nearby_enemy_ids.append(enemy_id)
	if not nearby_enemy_ids.is_empty():return _session._rejection_dto("base_return_contested")
	return _session._feedback_dto({"accepted":true,"reason":"ok","position":[hero.position.x,
		hero.position.y],"entry_mode":"ENTRY" if at_entry else "ANCHOR_PORTAL",
		"expedition_index":int(cycle.expedition_index),
		"carried":_session.BaseProgressionRulesScript.carried(_session.sim.world.events,
			int(cycle.expedition_index),"DUNGEON")})


func base_return()->Dictionary:
	var assessment:Dictionary=base_return_assessment()
	if not bool(assessment.get("accepted",false)):return assessment
	var rollback:Dictionary=_session.sim.snapshot()
	if rollback.is_empty():return _session._rejection_dto("snapshot_unavailable")
	var state=_session.sim.world.party_encounter;var cycle=state.expedition_cycle
	if not cycle.manual_return(int(_session.sim.world.world_time)):
		return _session._rejection_dto("base_return_failed")
	state.reset_ration(int(_session.sim.world.world_time))
	var hero_id:=int(_session.sim.world.party_control_actor_id())
	var event=_session.sim.world.emit_event("dungeon.expedition_returned",hero_id,-1,
		_session.sim.world.entities[hero_id].position,
		_session.BaseProgressionRulesScript.total_resources(assessment.carried),-1,
		{"schema_version":1,"ruleset_id":_session.ExpeditionCycleScript.RULESET_ID,
			"return_reason":"MANUAL_EXTRACT","entry_mode":str(assessment.entry_mode),
			"expedition_index":int(assessment.expedition_index),
			"haul":assessment.carried.duplicate(true)})
	var refilled_ids:Array=[]
	if event!=null:
		for member_id in state.party_member_ids:
			if state.member(member_id).refill_energy():refilled_ids.append(str(member_id))
		if not refilled_ids.is_empty():
			_session.sim.world.emit_event("party.energy_refilled",hero_id,-1,
				_session.sim.world.entities[hero_id].position,refilled_ids.size(),int(event.id),
				{"schema_version":1,"ruleset_id":"party-active-skills-v1",
					"reason":"TOWN_RETURN","member_ids":refilled_ids})
	if event!=null and _session.town_life_enabled():
		if not _session._ensure_town_guild_candidates():event=null
	state.revision+=1;var error:String=_session.sim.world.world_state_error()
	if event==null or not error.is_empty():
		_session.sim=_session.SimulatorScript.from_snapshot(rollback)
		return _session._rejection_dto(error if not error.is_empty() else "base_return_failed")
	_session.command_journal.append({"kind":"base","operation":{"action":"RETURN"}})
	_session._clear_run_completion_transients()
	return _session._feedback_dto({"accepted":true,"reason":"ok","event_id":int(event.id),
		"banked":assessment.carried.duplicate(true),"expedition_cycle":_session.expedition_cycle_status(),
		"stock":_session.BaseProgressionRulesScript.secured_stock(_session.sim.world.events,
			int(cycle.expedition_index),"TOWN")})
