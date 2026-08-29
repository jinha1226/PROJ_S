class_name DungeonDuelState
extends RefCounted

const SCHEMA_VERSION:=3
const ACTOR_COUNT:=5
const ActorScript=preload("res://sim/dungeon_population/dungeon_actor_state.gd")
const Int64CodecScript=preload("res://sim/int64_codec.gd")

var seed:int=1
var turn_index:int=0
var world_time:int=0
var phase:="ACTIVE"
var actors:Dictionary={}
var events:Array[Dictionary]=[]
var next_event_id:int=1
var last_resolution:Dictionary={}

func to_dict()->Dictionary:
	var actor_rows:Array=[];var ids:Array=actors.keys();ids.sort()
	for entity_id in ids:actor_rows.append(actors[entity_id].to_dict())
	return {"schema_version":SCHEMA_VERSION,"seed":str(seed),"turn_index":str(turn_index),
		"world_time":str(world_time),"phase":phase,"actors":actor_rows,
		"events":events.duplicate(true),"next_event_id":str(next_event_id),
		"last_resolution":last_resolution.duplicate(true)}

static func from_dict(row:Dictionary):
	var state=load("res://sim/dungeon_population/dungeon_population_state.gd").new()
	state.seed=Int64CodecScript.parse(row.seed,"duel seed")
	state.turn_index=Int64CodecScript.parse(row.turn_index,"duel turn")
	state.world_time=Int64CodecScript.parse(row.world_time,"duel time")
	state.phase=str(row.phase);state.actors.clear()
	for actor_row in row.actors:
		var actor=ActorScript.from_dict(actor_row);state.actors[actor.entity_id]=actor
	state.events.clear();for event in row.events:state.events.append(_canonical_event(event))
	state.next_event_id=Int64CodecScript.parse(row.next_event_id,"duel next event")
	state.last_resolution=_canonical_resolution(row.last_resolution)
	return state

static func wire_error(row:Variant,action_ids:Array,action_definitions:Dictionary={})->String:
	if not row is Dictionary:return "invalid_duel_state_shape"
	var keys:Array=row.keys();keys.sort()
	if keys != ["actors","events","last_resolution","next_event_id","phase","schema_version",
			"seed","turn_index","world_time"] or row.schema_version!=SCHEMA_VERSION:
		return "invalid_duel_state_wire"
	for key in ["seed","turn_index","world_time","next_event_id"]:
		if not Int64CodecScript.is_canonical(row.get(key)):return "noncanonical_duel_int64"
	var turn:=Int64CodecScript.parse(row.turn_index,"duel turn")
	var time:=Int64CodecScript.parse(row.world_time,"duel time")
	if turn<0 or time!=turn*100 or Int64CodecScript.parse(row.next_event_id,"duel next event")<=0:
		return "invalid_duel_time"
	if row.phase not in ["ACTIVE","COMPLETE"] or not row.actors is Array \
			or row.actors.size()!=ACTOR_COUNT:return "invalid_duel_phase_or_actor_count"
	var active_positions:Dictionary={};var active_count:=0
	for index in range(ACTOR_COUNT):
		var error:=ActorScript.wire_error(row.actors[index])
		if not error.is_empty():return error
		var actor_id:=Int64CodecScript.parse(row.actors[index].entity_id,"duel actor")
		if actor_id!=index+1:return "duel_actor_order_mismatch"
		if row.actors[index].presence=="ACTIVE":
			active_count+=1;var position_key:=JSON.stringify(row.actors[index].position)
			if active_positions.has(position_key):return "duel_active_position_collision"
			active_positions[position_key]=true
		var current_intent:=str(row.actors[index].current_intent_id)
		if not current_intent.is_empty():
			if current_intent not in action_ids:return "unknown_duel_current_intent"
			var definition:Dictionary=action_definitions.get(current_intent,{})
			if not definition.is_empty():
				var target_id:=Int64CodecScript.parse(row.actors[index].intent_target_id,"duel intent target")
				if definition.target_role=="OTHER" and (target_id<1 or target_id>ACTOR_COUNT or target_id==actor_id):
					return "duel_intent_target_mismatch"
				if definition.target_role=="SELF" and target_id!=actor_id:return "duel_intent_target_mismatch"
				if definition.target_role=="NONE" and target_id!=-1:return "duel_intent_target_mismatch"
		if Int64CodecScript.parse(row.actors[index].intent_started_turn,"duel intent start")>turn \
				or Int64CodecScript.parse(row.actors[index].commitment_until_turn,"duel commitment")>turn+20:
			return "duel_intent_time_mismatch"
	if (row.phase=="COMPLETE")!=(active_count<=1):return "duel_terminal_projection_mismatch"
	if not row.events is Array or row.events.size()>512:return "invalid_duel_events"
	var previous_event_id:=0;var seen_event_ids:Dictionary={}
	for event in row.events:
		var event_error:=_event_wire_error(event,action_ids,action_definitions)
		if not event_error.is_empty():return event_error
		var event_id:=Int64CodecScript.parse(event.event_id,"duel event")
		if event_id<=previous_event_id:return "duel_event_order_mismatch"
		var event_turn:=Int64CodecScript.parse(event.turn_index,"duel event turn")
		if event_turn<1 or event_turn>turn \
				or Int64CodecScript.parse(event.world_time,"duel event time")!=event_turn*100:
			return "duel_event_time_mismatch"
		previous_event_id=event_id;seen_event_ids[event_id]=true
	if Int64CodecScript.parse(row.next_event_id,"duel next event")<=previous_event_id:
		return "duel_next_event_mismatch"
	return _resolution_wire_error(row.last_resolution,action_ids,action_definitions,turn,
		previous_event_id,seen_event_ids)

static func _event_wire_error(event:Variant,action_ids:Array,action_definitions:Dictionary)->String:
	if not event is Dictionary:return "invalid_duel_event"
	var keys:Array=event.keys();keys.sort()
	if keys != ["action_id","actor_id","event_id","magnitude","position","target_id","turn_index","type","world_time"]:
		return "invalid_duel_event"
	for key in ["actor_id","event_id","target_id","turn_index","world_time"]:
		if not Int64CodecScript.is_canonical(event.get(key)):return "noncanonical_duel_event"
	var actor_id:=Int64CodecScript.parse(event.actor_id,"duel event actor")
	var target_id:=Int64CodecScript.parse(event.target_id,"duel event target")
	if actor_id<1 or actor_id>ACTOR_COUNT or target_id < -1 or target_id>ACTOR_COUNT \
			or target_id==actor_id and event.type in ["DAMAGE","ESCAPED","MEMORY","MOVE"] \
			or event.type not in ["ACTION","DAMAGE","DEATH","ESCAPED","HEAL","MEMORY","MOVE","STATUS_TICK"] \
			or event.action_id not in action_ids or not _integer(event.magnitude) or int(event.magnitude)<0 \
			or not event.position is Array or event.position.size()!=2 \
			or not _integer(event.position[0]) or not _integer(event.position[1]) \
			or int(event.position[0])<0 or int(event.position[0])>=21 \
			or int(event.position[1])<0 or int(event.position[1])>=21:return "invalid_duel_event_semantics"
	if event.type in ["DAMAGE","ESCAPED","MEMORY","MOVE"] and target_id<1:return "invalid_duel_event_target"
	if event.type in ["DEATH","STATUS_TICK"] and target_id!=-1:return "invalid_duel_event_target"
	if event.type=="HEAL" and target_id!=actor_id:return "invalid_duel_event_target"
	if not action_definitions.is_empty():
		var definition:Dictionary=action_definitions.get(str(event.action_id),{})
		if definition.is_empty():return "missing_duel_event_action_definition"
		if event.type=="ACTION":
			if definition.target_role=="OTHER" and (target_id<1 or target_id==actor_id):
				return "duel_action_event_target_mismatch"
			if definition.target_role=="SELF" and target_id!=actor_id:return "duel_action_event_target_mismatch"
			if definition.target_role=="NONE" and target_id!=-1:return "duel_action_event_target_mismatch"
		elif event.type in ["ESCAPED","MOVE"] and definition.atomic_verb!="MOVE":
			return "duel_move_event_action_mismatch"
		elif event.type=="ESCAPED" and definition.movement_direction!="AWAY":
			return "duel_escape_action_mismatch"
		elif event.type in ["DAMAGE","MEMORY"] and definition.atomic_verb!="MELEE":
			return "duel_melee_event_action_mismatch"
		elif event.type=="HEAL" and definition.atomic_verb!="USE_ITEM":return "duel_item_event_action_mismatch"
	return ""

static func _resolution_wire_error(resolution:Variant,action_ids:Array,action_definitions:Dictionary,
		turn:int,last_event_id:int,seen_event_ids:Dictionary)->String:
	if not resolution is Dictionary:return "invalid_duel_resolution"
	if resolution.is_empty():return "" if turn==0 else "missing_duel_resolution"
	var keys:Array=resolution.keys();keys.sort()
	if keys != ["action_rows","event_ids","turn_index"] or not Int64CodecScript.is_canonical(resolution.turn_index) \
			or Int64CodecScript.parse(resolution.turn_index,"duel resolution turn")!=turn \
			or not resolution.action_rows is Array or not resolution.event_ids is Array:
		return "invalid_duel_resolution"
	var previous_actor:=0
	for action in resolution.action_rows:
		if not action is Dictionary:return "invalid_duel_resolution"
		var action_keys:Array=action.keys();action_keys.sort()
		if action_keys != ["action_id","actor_id","target_id"] or action.action_id not in action_ids \
				or not Int64CodecScript.is_canonical(action.actor_id) \
				or not Int64CodecScript.is_canonical(action.target_id):return "invalid_duel_resolution"
		var actor_id:=Int64CodecScript.parse(action.actor_id,"duel action actor")
		var target_id:=Int64CodecScript.parse(action.target_id,"duel action target")
		if actor_id<=previous_actor or actor_id<1 or actor_id>ACTOR_COUNT or target_id < -1 \
				or target_id>ACTOR_COUNT:return "invalid_duel_resolution"
		var definition:Dictionary=action_definitions.get(str(action.action_id),{})
		if not definition.is_empty():
			if definition.target_role=="OTHER" and (target_id<1 or target_id==actor_id):
				return "duel_resolution_target_mismatch"
			if definition.target_role=="SELF" and target_id!=actor_id:
				return "duel_resolution_target_mismatch"
			if definition.target_role=="NONE" and target_id!=-1:
				return "duel_resolution_target_mismatch"
		previous_actor=actor_id
	var previous:=0
	for value in resolution.event_ids:
		if not Int64CodecScript.is_canonical(value):return "invalid_duel_resolution"
		var event_id:=Int64CodecScript.parse(value,"duel resolution event")
		if event_id<=previous or event_id>last_event_id or not seen_event_ids.has(event_id):
			return "invalid_duel_resolution"
		previous=event_id
	return ""

static func _canonical_event(event:Dictionary)->Dictionary:
	return {"event_id":str(event.event_id),"turn_index":str(event.turn_index),
		"world_time":str(event.world_time),"type":str(event.type),"actor_id":str(event.actor_id),
		"target_id":str(event.target_id),"action_id":str(event.action_id),
		"magnitude":int(event.magnitude),"position":[int(event.position[0]),int(event.position[1])]}

static func _canonical_resolution(row:Dictionary)->Dictionary:
	if row.is_empty():return {}
	var actions:Array=[]
	for action in row.action_rows:
		actions.append({"actor_id":str(action.actor_id),"action_id":str(action.action_id),
			"target_id":str(action.target_id)})
	var event_ids:Array=[];for value in row.event_ids:event_ids.append(str(value))
	return {"turn_index":str(row.turn_index),"action_rows":actions,"event_ids":event_ids}

static func _integer(value:Variant)->bool:return value is int or (value is float and value==floor(value))
