extends RefCounted

const RULESET_ID:="round-planned-combat-v1"
const PHASES:=["EXPLORATION","DEPLOYMENT","PLANNING","RESOLVING","INTERRUPTED"]
const Codec=preload("res://sim/int64_codec.gd")

static func fresh()->Dictionary:
	return {"schema":1,"ruleset":RULESET_ID,"round_id":0,"phase":"EXPLORATION",
		"round_start_time":"0","participants":[],"order":[],"plans":{},
		"plan_revision":0,"execution_cursor":0,"completed_actor_ids":[],
		"interrupt_reason":"","round_time_committed":false,"slot_progress":{},
		"slot_spent":{},"slot_attacks":{},"known_enemy_ids":[],"rng_commitment":"","last_boundary_time":"0","stage_rooms":{}}

static func wire_error(row:Variant,width:int,height:int)->String:
	if not row is Dictionary:return "round_state_shape"
	var keys:Array=row.keys();keys.sort();var expected:Array=fresh().keys();expected.sort()
	if keys!=expected or row.schema!=1 or row.ruleset!=RULESET_ID or row.phase not in PHASES:return "round_state_header"
	if not row.stage_rooms is Dictionary or row.stage_rooms.size()>18:return "stage_state_shape"
	for room_key in row.stage_rooms:
		if not room_key is String or not preload("res://sim/nine_room_floor_state.gd").valid_room_key(room_key):return "stage_room_key"
		var stage:Variant=row.stage_rooms[room_key]
		if not stage is Dictionary:return "stage_room_shape"
		var fields:Array=stage.keys();fields.sort()
		if fields!=["entry","started","turn","waves"] or not stage.started is bool:return "stage_room_shape"
		for field in ["turn","waves"]:
			if not integer(stage[field]) or stage[field]<0:return "stage_counter"
		if not stage.entry is Array or stage.entry.size()!=2:return "stage_entry"
		for coordinate in stage.entry:
			if not integer(coordinate) or coordinate<0:return "stage_entry"
		if stage.entry[0]>=width or stage.entry[1]>=height:return "stage_entry_bounds"
	for key in ["round_id","plan_revision","execution_cursor"]:
		if not integer(row[key]) or int(row[key])<0 or int(row[key])>1000000000:return "round_state_counter"
	for key in ["round_start_time","last_boundary_time"]:
		if not Codec.is_canonical(row[key]) or int(row[key])<0:return "round_state_time"
	if not row.round_time_committed is bool or not row.interrupt_reason is String or not row.rng_commitment is String:return "round_state_field"
	for key in ["participants","order","completed_actor_ids","known_enemy_ids"]:
		if not row[key] is Array or row[key].size()>1028:return "round_state_roster"
		var seen:Dictionary={}
		for id in row[key]:
			if not Codec.is_canonical(id) or int(id)<1 or seen.has(id):return "round_state_actor"
			seen[id]=true
	if row.order.size()!=row.participants.size() or row.execution_cursor>row.order.size():return "round_state_order"
	for id in row.order:
		if id not in row.participants:return "round_state_order"
	if not row.plans is Dictionary or not row.slot_progress is Dictionary or not row.slot_spent is Dictionary or not row.slot_attacks is Dictionary:return "round_state_plans"
	if row.plans.size()!=row.order.size():return "round_state_plans"
	for id in row.order:
		if not row.plans.has(id):return "round_state_missing_plan"
		var error:=plan_error(row.plans[id],width,height)
		if not error.is_empty() or row.plans[id].actor_id!=id:return "round_state_plan_"+error
	for id in row.completed_actor_ids:
		if row.order.find(id)<0 or row.order.find(id)>=int(row.execution_cursor):return "round_state_completed"
	for id in row.slot_progress:
		if id not in row.order or not integer(row.slot_progress[id]) or int(row.slot_progress[id])<0 or int(row.slot_progress[id])>row.plans[id].path.size():return "round_state_progress"
	for id in row.slot_spent:
		if id not in row.order or not integer(row.slot_spent[id]) or int(row.slot_spent[id])<0 or int(row.slot_spent[id])>12:return "round_state_spent"
	for id in row.slot_attacks:
		if id not in row.order or not integer(row.slot_attacks[id]) or int(row.slot_attacks[id])<0 or int(row.slot_attacks[id])>3:return "round_state_attacks"
	return ""

static func plan_error(p:Variant,width:int,height:int)->String:
	if not p is Dictionary:return "shape"
	var keys:Array=p.keys();keys.sort()
	if keys!=["action","actor_id","anchor","destination","item_operation","move_budget","origin","path","source","target_cell","target_policy"]:return "keys"
	if not Codec.is_canonical(p.actor_id) or int(p.actor_id)<1 or p.source not in ["AI","USER"] or p.anchor!="WORLD_TILE" or p.target_policy not in ["CELL","ENTITY"]:return "identity"
	if not p.action is Dictionary or not preload("res://sim/party_action_command.gd").wire_error(p.action).is_empty() or p.action.actor_id!=p.actor_id:return "action"
	if not preload("res://sim/round_item_rules.gd").wire_error(p.item_operation).is_empty():return "item"
	if not integer(p.move_budget) or int(p.move_budget)<1 or int(p.move_budget)>12 or not p.path is Array or p.path.size()>12:return "budget"
	for cell in [p.origin,p.destination,p.target_cell]+p.path:
		if not cell is Array or cell.size()!=2:return "cell"
		for value in cell:
			if not integer(value):return "cell"
		if not (int(cell[0])==-1 and int(cell[1])==-1) and (int(cell[0])<0 or int(cell[1])<0 or int(cell[0])>=width or int(cell[1])>=height):return "bounds"
	var last:Vector2i=Vector2i(p.origin[0],p.origin[1])
	for cell in p.path:
		var next:=Vector2i(cell[0],cell[1]);var delta:=next-last
		if maxi(absi(delta.x),absi(delta.y))!=1:return "path"
		last=next
	if last!=Vector2i(p.destination[0],p.destination[1]):return "destination"
	return ""

static func integer(v:Variant)->bool:
	return v is int or v is float and is_finite(v) and v==floor(v)

static func normalized(value:Variant)->Variant:
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[key]=normalized(value[key])
		return result
	if value is Array:return value.map(func(v):return normalized(v))
	if value is float and integer(value):return int(value)
	return value
