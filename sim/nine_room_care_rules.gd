extends RefCounted

static var CONFIG:Dictionary=preload("res://sim/json_content_loader.gd").load_document("res://data/content/nine_room_care.json")
const RULESET_ID:="nine-room-care-v1"
const Stats=preload("res://sim/actor_stat_rules.gd")
const Body=preload("res://sim/body_penalty_rules.gd")
const Rooms=preload("res://sim/room_transition_rules.gd")
static var last_error:=""

static func create()->Dictionary:
	return {"ruleset_id":RULESET_ID,"revision":1,"request_serial":0,"last_request_id":0,"last_result":"NONE","residuals":{},"combat_round_id":0,"combat_actor_ids":[]}

static func enabled(w)->bool:
	return w!=null and w.party_encounter!=null and w.party_encounter.nine_room_floor.has("care")

static func state(w)->Dictionary:
	return w.party_encounter.nine_room_floor.care

static func wire_error(c:Variant)->String:
	if CONFIG.get("schema_version")!=1 or CONFIG.get("ruleset_id")!=RULESET_ID:return "care_registry_version"
	for key in ["rest_food_cost","rest_recovery_units","rest_time_cost","combat_recovery_units","base_recovery_milli","stat_recovery_milli"]:
		var value:Variant=CONFIG.get(key)
		if not (value is int or value is float and is_finite(value) and value==floor(value)) or value<1 or value>10000:return "care_registry_value"
	if not c is Dictionary:return "care_state_shape"
	var keys:Array=c.keys();keys.sort()
	if keys!=["combat_actor_ids","combat_round_id","last_request_id","last_result","request_serial","residuals","revision","ruleset_id"] or c.ruleset_id!=RULESET_ID:return "care_state_version"
	for key in ["revision","request_serial","last_request_id","combat_round_id"]:
		if not c[key] is int or c[key]<0:return "care_state_counter"
	if c.revision<1 or c.last_request_id>c.request_serial or c.last_result not in ["NONE","COMPLETED","INTERRUPTED"] or not c.residuals is Dictionary or not c.combat_actor_ids is Array:return "care_state_invalid"
	var seen:Dictionary={}
	for key in c.combat_actor_ids:
		if not key is String or not key.is_valid_int() or int(key)<1 or seen.has(key):return "care_actor_invalid"
		seen[key]=true
	for key in c.residuals:
		var row:Variant=c.residuals[key]
		if not key is String or not key.is_valid_int() or int(key)<1 or not row is Dictionary or row.keys().size()!=2 or not row.has("hp") or not row.has("mp"):return "care_residual_shape"
		for resource in ["hp","mp"]:
			if not row[resource] is int or row[resource]<0 or row[resource]>=1000:return "care_residual_invalid"
	return ""

static func profile(w,id:int)->Dictionary:
	var core:Dictionary=Stats.for_entity(w,id)
	var hp:int=int(CONFIG.base_recovery_milli)+maxi(0,int(core.get("STR",5)))*int(CONFIG.stat_recovery_milli)
	var mp:int=int(CONFIG.base_recovery_milli)+maxi(0,int(core.get("INT",5)))*int(CONFIG.stat_recovery_milli)
	return {"hp_milli":hp*int(Body.current(w,id).recovery_milli)/1000,"mp_milli":mp,"tissue_rates":Body.RECOVERY_RATES.duplicate()}

static func eligible(w)->Array:
	var ids:Array=[]
	for id in w.party_encounter.active_party_member_ids:
		if w.party_encounter.member(id).presence=="DEPLOYED" and w.can_act(id,w.world_time):ids.append(id)
	return ids

static func amounts(w,id:int,units:int)->Dictionary:
	var rates:=profile(w,id);var carry:Dictionary=state(w).residuals.get(str(id),{"hp":0,"mp":0})
	var entity=w.entities[id];var member=w.party_encounter.member(id)
	var hp_total:int=int(rates.hp_milli)*units+int(carry.hp)
	var mp_total:int=int(rates.mp_milli)*units+int(carry.mp)
	var hp:=mini(entity.max_health-entity.health,hp_total/1000)
	var mp:=mini(member.max_energy-member.energy,mp_total/1000)
	var tissues:Dictionary={"SKIN":0,"SOFT_TISSUE":0,"BONE":0}
	if Body.enabled(w) and w.body_states.get(id)!=null:
		for part in w.body_states[id].parts:
			if part.condition=="SEVERED":continue
			for layer in part.layers:tissues[layer.layer_id]+=mini(1000-int(layer.integrity),int(rates.tissue_rates[layer.layer_id])*units)
	return {"actor_id":str(id),"name":entity.display_name,"hp":hp,"mp":mp,"hp_residual":0 if entity.health+hp>=entity.max_health else hp_total%1000,"mp_residual":0 if member.energy+mp>=member.max_energy else mp_total%1000,"profile":rates,"tissues":tissues,"tissue_units":units if Body.enabled(w) and Body.needs_recovery(w.body_states.get(id)) else 0}

static func safety(session)->String:
	var w=session.sim.world;var party=w.party_encounter
	if not w.is_settled():return "다른 행동을 처리 중입니다"
	if party.expedition_cycle.phase!="DUNGEON" or session._run_is_complete():return "원정 중 안전한 방에서만 쉴 수 있습니다"
	if party.member(w.party_control_actor_id()).busy_until>w.world_time:return "아직 다음 행동을 할 수 없습니다"
	if party.round_combat.phase!="EXPLORATION":return "현재 방에서 교전 중입니다"
	if not party.nine_room_floor.pending_exit.is_empty() or party.nine_room_floor.pending_pursuit.any(func(row):return row.floor_index==party.nine_room_floor.floor_index and row.target_room==party.nine_room_floor.active_room_id):return "추격 또는 방 이동 중입니다"
	if party.safe_phase not in ["GROUPED","GROUPED_COMPLETE"]:return "파티가 집결하지 않았습니다"
	var ids:=eligible(w)
	if ids.is_empty():return "휴식 가능한 인물이 없습니다"
	for id in party.active_party_member_ids:
		if party.member(id).presence in ["DEFEATED","EXILED"]:continue
		if id not in ids:return "쓰러진 동료는 구조가 필요합니다"
		if not Rooms.same_room(w,w.entities[id].position,w.entities[w.party_control_actor_id()].position) or Rooms.distance(w.entities[id].position,w.entities[w.party_control_actor_id()].position)>2:return "파티가 집결하지 않았습니다"
		if not w.combatant_states[id].status_rows.is_empty():return "상태이상 중에는 쉴 수 없습니다"
		var exposure=session.sim.evaluate_exposure_for_entity(id,w.entities[id].position)
		if exposure!=null and exposure.evaluation!=null and exposure.evaluation.total_risk>0:return "파티 주변 지형이 위험합니다"
	for id in party.enemy_ids:
		if not w.can_act(id,w.world_time) or not Rooms.same_room(w,w.entities[id].position,w.entities[w.party_control_actor_id()].position):continue
		if load("res://sim/field_turn_rules.gd").visible(w,id) or party.enemy_awareness(id).awareness_state in ["ALERT","HUNTING","SEARCHING","SUSPICIOUS"]:return "현재 방에 적의 위협이 있습니다"
	return ""

static func preview(session)->Dictionary:
	var w=session.sim.world
	if not enabled(w):return {"accepted":false,"reason":"기존 저장은 이전 휴식 규칙을 사용합니다"}
	var settings_error:=wire_error(state(w))
	if not settings_error.is_empty():return {"accepted":false,"reason":"회복 설정 또는 상태를 확인해야 합니다"}
	var rows:Array=[];var needs:=false
	for id in eligible(w):
		var row:=amounts(w,id,int(CONFIG.rest_recovery_units));rows.append(row)
		needs=needs or w.entities[id].health<w.entities[id].max_health or w.party_encounter.member(id).energy<w.party_encounter.member(id).max_energy or row.tissue_units>0
	var reason:=safety(session)
	if reason.is_empty() and not needs:reason="이미 충분히 회복했습니다"
	if reason.is_empty() and w.party_encounter.ration_milli<int(CONFIG.rest_food_cost)*1000:reason="파티 식량이 부족합니다"
	return {"accepted":reason.is_empty(),"reason":reason,"revision":int(state(w).revision),"request_id":int(state(w).request_serial)+1,"food_cost":int(CONFIG.rest_food_cost),"time_cost":int(CONFIG.rest_time_cost),"members":rows}

static func recover(w,ids:Array,units:int,context:String,cause:int=-1)->bool:
	for id in ids:
		if id not in eligible(w):continue
		var row:=amounts(w,id,units)
		state(w).residuals[str(id)]={"hp":row.hp_residual,"mp":row.mp_residual}
		var root=w.emit_event("care.recovered",id,id,w.entities[id].position,0,cause,{"ruleset_id":RULESET_ID,"context":context,"units":units,"hp":row.hp,"mp":row.mp,"hp_residual":row.hp_residual,"mp_residual":row.mp_residual,"profile":row.profile})
		if root==null:return false
		if row.hp>0:
			w.entities[id].health+=int(row.hp)
			if w.emit_event("health.restored",id,id,w.entities[id].position,int(row.hp),root.id,{"schema_version":1,"ruleset_id":RULESET_ID,"kind":"CARE","health_after":w.entities[id].health})==null:return false
		if row.mp>0:
			w.party_encounter.member(id).energy+=int(row.mp)
			if w.emit_event("party.energy_recovered",id,id,w.entities[id].position,int(row.mp),root.id,{"schema_version":1,"ruleset_id":RULESET_ID,"energy_after":w.party_encounter.member(id).energy})==null:return false
		if Body.enabled(w):
			var changes:=Body.heal_layers(w.body_states.get(id),units)
			if not changes.is_empty():
				var event=w.emit_event("body.rest_recovered",id,id,w.entities[id].position,0,root.id,{"pulses":units,"changes":changes})
				if event==null or not Body.record(w,id,event.id):return false
	state(w).revision+=1;w.party_encounter.revision+=1
	return true

static func mark_combat(w,id:int)->void:
	if not enabled(w) or id not in eligible(w):return
	var c:=state(w);var round_id:int=w.party_encounter.round_combat.round_id
	if c.combat_round_id!=round_id:c.combat_round_id=round_id;c.combat_actor_ids=[]
	if str(id) not in c.combat_actor_ids:c.combat_actor_ids.append(str(id))

static func finish_combat(w)->bool:
	if not enabled(w):return true
	var c:=state(w)
	var ids:Array=c.combat_actor_ids.map(func(id):return int(id)) if c.combat_round_id==w.party_encounter.round_combat.round_id else []
	c.combat_actor_ids=[]
	return ids.is_empty() or recover(w,ids,int(CONFIG.combat_recovery_units),"COMBAT")

static func deny_combat(w,id:int)->void:
	if enabled(w):state(w).combat_actor_ids.erase(str(id))

static func commit(session,revision:int,request_id:int)->Dictionary:
	last_error=""
	var w=session.sim.world;var checked:=preview(session)
	if not checked.accepted:return checked
	if revision!=checked.revision or request_id!=checked.request_id:return {"accepted":false,"reason":"휴식 요청이 변경됐습니다"}
	var rollback:Dictionary=session.sim.capture_rollback_memento(false)
	var event_start:int=w.events.size();var c:=state(w)
	c.request_serial=request_id;c.last_request_id=request_id
	w.party_encounter.ration_milli-=int(CONFIG.rest_food_cost)*1000
	var paid=w.emit_event("care.rest_paid",w.party_control_actor_id(),-1,w.entities[w.party_control_actor_id()].position,int(CONFIG.rest_food_cost),-1,{"ruleset_id":RULESET_ID,"request_id":request_id,"ration_after":w.party_encounter.ration_milli})
	var result=load("res://sim/systems/field_turn_system.gd").step(session.sim,load("res://sim/party_action_command.gd").hold(w.party_control_actor_id()),int(CONFIG.rest_time_cost),rollback) if paid!=null else null
	if result==null or not result.accepted:
		session.sim.restore_rollback_memento(rollback);return {"accepted":false,"reason":"휴식을 처리하지 못했습니다"}
	var interrupted:=not safety(session).is_empty()
	for event in w.events.slice(event_start):
		if event.target_id in w.party_encounter.active_party_member_ids and event.magnitude>0 and event.type.begins_with("combat.") and event.type.ends_with("_damage"):interrupted=true
	c.last_result="INTERRUPTED" if interrupted else "COMPLETED";c.revision+=1
	var ok:=interrupted or recover(w,eligible(w),int(CONFIG.rest_recovery_units),"REST",paid.id)
	var finished=w.emit_event("care.rest_finished",w.party_control_actor_id(),-1,w.entities[w.party_control_actor_id()].position,0,paid.id,{"ruleset_id":RULESET_ID,"request_id":request_id,"result":c.last_result}) if ok else null
	# Payment precedes the field step and has its previous step index, just as
	# an exit request precedes its movement. Validate that root separately.
	last_error=event_error(w,paid)
	if last_error.is_empty():last_error="care_completion_event_failed" if finished==null else w.runtime_step_postcondition_error(event_start+1)
	if not last_error.is_empty():
		session.sim.restore_rollback_memento(rollback);return {"accepted":false,"reason":"휴식 상태 검증에 실패했습니다"}
	return {"accepted":true,"reason":"interrupted" if interrupted else "ok","message":"위협으로 휴식 중단 · 식량과 시간은 소비되며 휴식 회복은 지급되지 않았습니다" if interrupted else "개인별 휴식 회복 완료 · 파티 식량 %d 소비"%int(CONFIG.rest_food_cost)}

static func event_error(w,e)->String:
	if e.type=="health.restored" and e.data.get("kind")=="CARE" or e.type=="party.energy_recovered" and e.data.get("ruleset_id")==RULESET_ID:
		var source=w.event_by_id(e.cause_id)
		var resource:="hp" if e.type=="health.restored" else "mp"
		if source==null or source.type!="care.recovered" or source.actor_id!=e.actor_id or e.target_id!=e.actor_id or e.magnitude!=source.data.get(resource) or source.world_time!=e.world_time or e.data.get("ruleset_id")!=RULESET_ID:return "care_healing_cause_invalid"
		var keys:Array=e.data.keys();keys.sort()
		var after_key:="health_after" if resource=="hp" else "energy_after"
		if keys!=(["health_after","kind","ruleset_id","schema_version"] if resource=="hp" else ["energy_after","ruleset_id","schema_version"]) or e.data.get("schema_version")!=1 or not e.data.get(after_key) is int or e.magnitude<=0 or e.data[after_key]<1 or e.data[after_key]>(w.entities[e.actor_id].max_health if resource=="hp" else w.party_encounter.member(e.actor_id).max_energy):return "care_healing_shape_invalid"
	if not e.type.begins_with("care."):return ""
	if not enabled(w) or e.data.get("ruleset_id")!=RULESET_ID:return "care_event_ruleset_invalid"
	var keys:Array=e.data.keys();keys.sort()
	if e.type=="care.recovered":
		if keys!=["context","hp","hp_residual","mp","mp_residual","profile","ruleset_id","units"] or e.magnitude!=0:return "care_recovery_shape_invalid"
		if e.actor_id!=e.target_id or w.party_encounter.member(e.actor_id)==null or e.data.get("context") not in ["REST","COMBAT"] or e.data.get("units")!=(int(CONFIG.rest_recovery_units) if e.data.context=="REST" else int(CONFIG.combat_recovery_units)):return "care_recovery_invalid"
		var core:Dictionary=Stats.for_entity(w,e.actor_id).duplicate()
		if e.actor_id==w.party_encounter.protagonist_id:
			for later in w.events:
				if later.id>e.id and later.type=="growth.stat_spent":core[str(later.data.target_id)]-=int(later.magnitude)
		var hp_rate:int=(int(CONFIG.base_recovery_milli)+maxi(0,int(core.STR))*int(CONFIG.stat_recovery_milli))*int(Body.historical(w,e.actor_id,e.id).recovery_milli)/1000
		var mp_rate:int=int(CONFIG.base_recovery_milli)+maxi(0,int(core.INT))*int(CONFIG.stat_recovery_milli)
		if e.data.profile!={"hp_milli":hp_rate,"mp_milli":mp_rate,"tissue_rates":Body.RECOVERY_RATES}:return "care_profile_invalid"
		for key in ["hp","mp","hp_residual","mp_residual"]:
			if not e.data.get(key) is int or e.data[key]<0:return "care_recovery_amount_invalid"
		if e.data.hp_residual>=1000 or e.data.mp_residual>=1000:return "care_recovery_residual_invalid"
		if e.data.context=="REST":
			var paid=w.event_by_id(e.cause_id)
			if paid==null or paid.type!="care.rest_paid" or e.world_time!=paid.world_time+int(CONFIG.rest_time_cost):return "care_rest_cause_invalid"
	elif e.type=="care.rest_paid":
		if keys!=["ration_after","request_id","ruleset_id"] or e.target_id!=-1 or e.cause_id!=-1 or e.actor_id not in w.party_encounter.party_member_ids:return "care_payment_shape_invalid"
		if e.magnitude!=int(CONFIG.rest_food_cost) or not e.data.get("request_id") is int or e.data.request_id<1 or e.data.request_id>state(w).request_serial or not e.data.get("ration_after") is int or e.data.ration_after<0:return "care_payment_invalid"
	elif e.type=="care.rest_finished":
		if keys!=["request_id","result","ruleset_id"] or e.target_id!=-1 or e.magnitude!=0:return "care_completion_shape_invalid"
		var paid=w.event_by_id(e.cause_id)
		if paid==null or paid.type!="care.rest_paid" or paid.data.request_id!=e.data.get("request_id") or e.data.get("result") not in ["COMPLETED","INTERRUPTED"] or e.world_time!=paid.world_time+int(CONFIG.rest_time_cost):return "care_completion_invalid"
	else:return "care_event_kind_invalid"
	return ""

static func history_error(w)->String:
	if not enabled(w):return ""
	var state_error:=wire_error(state(w))
	if not state_error.is_empty():return state_error
	var residuals:Dictionary={};var payments:Dictionary={};var completions:Dictionary={};var recovered:Dictionary={}
	var last_request:int=0;var last_result:="NONE"
	for e in w.events:
		if e==null:return "care_history_event_missing"
		if str(e.type).begins_with("care."):
			var error:=event_error(w,e)
			if not error.is_empty():return error
		if e.type=="care.rest_paid":
			if int(e.data.request_id)!=last_request+1:return "care_payment_duplicate_or_gap"
			last_request+=1;payments[e.id]=last_request
		elif e.type=="care.rest_finished":
			if not payments.has(e.cause_id) or completions.has(e.cause_id):return "care_completion_duplicate"
			completions[e.cause_id]=str(e.data.result);last_result=str(e.data.result)
		elif e.type=="care.recovered":
			var actor:=str(e.actor_id);var previous:Dictionary=residuals.get(actor,{"hp":0,"mp":0})
			for resource in ["hp","mp"]:
				var total:int=int(e.data.profile[resource+"_milli"])*int(e.data.units)+int(previous[resource])
				var amount:int=e.data[resource];var carry:int=e.data[resource+"_residual"]
				if amount>total/1000 or amount<total/1000 and carry!=0 or carry not in [0,total%1000]:return "care_residual_projection_invalid"
			if e.data.context=="REST":
				var key:="%d:%s"%[e.cause_id,actor]
				if recovered.has(key):return "care_rest_actor_duplicate"
				recovered[key]=true
			residuals[actor]={"hp":e.data.hp_residual,"mp":e.data.mp_residual}
	if payments.size()!=completions.size():return "care_rest_incomplete"
	for key in recovered:
		if completions.get(int(str(key).split(":")[0]))!="COMPLETED":return "care_interrupted_rest_healed"
	var c:=state(w)
	if c.request_serial!=last_request or c.last_request_id!=last_request or c.last_result!=last_result or c.residuals!=residuals:return "care_history_projection_mismatch"
	return ""
