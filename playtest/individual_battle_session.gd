extends RefCounted

const Scheduler=preload("res://sim/systems/individual_battle_scheduler.gd")
const Skills=preload("res://sim/abilities/party_active_skill_service.gd")
const Codec=preload("res://sim/int64_codec.gd")
var _host_ref:WeakRef
var host:
	get:return _host_ref.get_ref()
var queues:Dictionary={}
var movements:Dictionary={}
var _sim
var _cache_key:=""
var _next:Dictionary={}

func _init(session)->void:_host_ref=weakref(session)

func _bind()->void:
	if _sim!=host.sim:
		_sim=host.sim;queues.clear();movements.clear();_cache_key="";_next.clear()
	if _sim!=null and _sim.world.party_encounter.safe_phase!="ENGAGED":
		queues.clear();movements.clear()

func movement_assessment(actor_id:int,goal:Vector2i)->Dictionary:
	_bind()
	if _sim==null:return {"accepted":false,"message":"전투 중에만 이동을 지정할 수 있습니다."}
	for id in movements:
		if int(id)!=actor_id and movements[id]==goal and _sim.world.can_act(id,_sim.world.world_time):
			return {"accepted":false,"message":"다른 파티원에게 지정한 위치입니다."}
	return preload("res://sim/systems/battle_position_order.gd").assess(_sim,actor_id,goal)

func reserve_move(actor_id:int,goal:Vector2i,append_journal:bool=true)->Dictionary:
	var assessed:=movement_assessment(actor_id,goal)
	if not assessed.get("accepted",false):return assessed
	movements[actor_id]=goal
	if append_journal:host.command_journal.append({"kind":"reserve_move","operation":{
		"actor_id":str(actor_id),"destination":[goal.x,goal.y]}})
	return {"accepted":true,"reason":"ok","message":"이동 지시 예약 · 도착 후 위치 유지"}

func hero_turn_pending()->bool:
	# The protagonist's own event is next. Presentation decides whether to hold
	# the display clock there; nothing canonical depends on this query.
	_bind()
	if _sim==null:return false
	var next:Dictionary=next_event()
	return not next.is_empty() and int(next.actor_id)==int(_sim.world.party_encounter.protagonist_id)

func next_event()->Dictionary:
	_bind()
	if _sim==null:return {}
	var world=_sim.world
	var key:="%d/%d/%d/%d"%[world.get_instance_id(),world.step_index,
		world.world_time,world.party_encounter.revision]
	if key!=_cache_key:_next=Scheduler.next_event(_sim);_cache_key=key
	return _next.duplicate()

func assessment(actor_id:int,skill_id:String,target_id:int)->Dictionary:
	_bind()
	return Skills.assess(host.sim.world,actor_id,skill_id,target_id,true)

func reserve(actor_id:int,skill_id:String,target_id:int,append_journal:bool=true)->Dictionary:
	var assessed:=assessment(actor_id,skill_id,target_id)
	if not bool(assessed.get("accepted",false)):return assessed
	queues[actor_id]={"skill_id":skill_id,"target_id":target_id}
	if append_journal:host.command_journal.append({"kind":"reserve_skill","operation":{
		"actor_id":str(actor_id),"skill_id":skill_id,"target_id":str(target_id)}})
	return {"accepted":true,"reason":"ok","message":"다음 행동에 예약됨"}

func cancel(actor_id:int,append_journal:bool=true)->Dictionary:
	_bind()
	if not queues.has(actor_id):return {"accepted":false,"reason":"no_reserved_skill"}
	queues.erase(actor_id)
	if append_journal:host.command_journal.append({"kind":"cancel_reserved_skill",
		"operation":{"actor_id":str(actor_id)}})
	return {"accepted":true,"reason":"ok","message":"예약 취소"}

func queued(actor_id:int)->Dictionary:
	_bind()
	return queues.get(actor_id,{}).duplicate()

func commit(expected:Dictionary={},append_journal:bool=true,survival_rules:bool=true)->Dictionary:
	var next:=next_event()
	if next.is_empty():return {"accepted":false,"reason":"individual_battle_not_engaged"}
	var operation:={"actor_id":str(next.actor_id),"at":str(next.at)}
	if not expected.is_empty() and operation!=expected:
		return {"accepted":false,"reason":"individual_battle_stale_event"}
	var result=Scheduler.step(host.sim,queues.get(int(next.actor_id),{}),
		movements.get(int(next.actor_id),Vector2i(-1,-1)),survival_rules)
	if not result.accepted:return host._rejection_dto(result.reason)
	var reservation_failed:bool=queues.has(int(next.actor_id))
	for event in result.events:
		if event.type=="action.skill" and int(event.actor_id)==int(next.actor_id):reservation_failed=false
	queues.erase(int(next.actor_id));_cache_key=""
	if host.sim.world.party_encounter.safe_phase!="ENGAGED":queues.clear();movements.clear()
	if append_journal:host.command_journal.append({"kind":"individual_survival_step" if survival_rules else "individual_step","operation":operation})
	host._clear_draft()
	var dto:Dictionary=host._result_dto(result,null,null)
	dto["actor_id"]=int(next.actor_id)
	dto["reservation_rejection"]="예약 조건이 달라져 기본 행동을 했습니다." if reservation_failed else ""
	return dto

static func operation_error(kind:String,row:Variant)->String:
	if not row is Dictionary:return "invalid_individual_operation"
	var keys:Array=row.keys();keys.sort()
	if kind in ["individual_step","individual_survival_step"]:
		if keys!=["actor_id","at"] or not Codec.is_canonical(row.get("at")) \
				or Codec.parse(row.at,"battle at")<0:return "invalid_individual_step"
	elif kind=="cancel_reserved_skill":
		if keys!=["actor_id"]:return "invalid_reserved_skill_cancel"
	elif kind=="reserve_move":
		if keys!=["actor_id","destination"] or not row.get("destination") is Array \
				or row.destination.size()!=2:return "invalid_reserved_move"
		for value in row.destination:
			if not (value is int or value is float and value==floor(value)) \
					or value<0 or value>2147483647:return "invalid_reserved_move"
	elif kind=="reserve_skill":
		if keys!=["actor_id","skill_id","target_id"] \
				or row.get("skill_id") not in Skills.ENABLED_SKILLS \
				or not Codec.is_canonical(row.get("target_id")) \
				or Codec.parse(row.target_id,"skill target")<=0:return "invalid_reserved_skill"
	else:return "unknown_individual_operation"
	if not Codec.is_canonical(row.get("actor_id")) \
			or Codec.parse(row.actor_id,"battle actor")<(0 if kind in ["individual_step","individual_survival_step"] else 1):
		return "invalid_individual_actor"
	return ""
