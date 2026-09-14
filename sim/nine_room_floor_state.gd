extends RefCounted
const Generator=preload("res://sim/nine_room_generator.gd")
static var _topologies:Dictionary={}
static func create(layout:Dictionary)->Dictionary:
	var floors:Array=[]
	for index in [1,2]:
		var floor:Dictionary=layout.campaign_floors[index]
		floors.append({"floor_index":index,"offset":floor.nine_offset.duplicate(),"rooms":floor.nine_rooms.duplicate(true),"portals":floor.nine_portals.duplicate(true)})
	return {"schema_version":2,"care":load("res://sim/nine_room_care_rules.gd").create(),"ruleset_id":Generator.RULESET_ID,"generator_version":Generator.VERSION,"seed":str(layout.seed),"floor_index":int(layout.floor_index),"floors":floors,"active_room_id":4,"revision":1,"request_serial":0,"action_boundary":0,"visited":["1:4"],"discovered_portals":layout.campaign_floors[int(layout.floor_index)].nine_rooms[4].exits.duplicate(),"pending_exit":{},"pending_pursuit":[],"effect_processed_at":{}}

static func normalize(value:Variant)->Dictionary:
	return preload("res://sim/round_combat_state.gd").normalized(value) if value is Dictionary else {}

static func wire_error(s:Variant,width:int,height:int)->String:
	if not s is Dictionary:return "room_state_shape"
	if s.is_empty():return ""
	s=normalize(s)
	var keys:Array=s.keys();keys.erase("care");keys.sort()
	if keys!=["action_boundary","active_room_id","discovered_portals","effect_processed_at","floor_index","floors","generator_version","pending_exit","pending_pursuit","request_serial","revision","ruleset_id","schema_version","seed","visited"]:return "room_state_keys"
	if s.schema_version not in [1,2] or (s.schema_version==2)!=s.has("care") or s.ruleset_id!=Generator.RULESET_ID or s.generator_version!=Generator.VERSION or not preload("res://sim/int64_codec.gd").is_canonical(s.seed):return "room_state_version"
	if s.has("care"):
		var care_error:String=load("res://sim/nine_room_care_rules.gd").wire_error(s.care)
		if not care_error.is_empty():return care_error
	for field in ["revision","request_serial","action_boundary","floor_index","active_room_id"]:
		if not integer(s[field]) or s[field]<0:return "room_state_counter"
	if s.floor_index not in [1,2] or s.active_room_id not in range(9) or width!=48 or height!=24:return "room_state_bounds"
	if not s.floors is Array or s.floors.size()!=2:return "room_floor_count"
	# Regenerate topology only at decode/full-validation boundaries, never on a
	# movement tick. Canonical metadata cannot smuggle an unpaired portal.
	if not _topologies.has(s.seed):
		if _topologies.size()>128:_topologies.clear()
		_topologies[s.seed]=create(Generator.world_layout(int(s.seed))).floors
	if normalize({"floors":s.floors}).floors!=_topologies[s.seed]:return "room_topology_mismatch"
	for field in ["visited","discovered_portals"]:
		if not s[field] is Array:return "room_discovery_shape"
		var seen:Dictionary={}
		for key in s[field]:
			if not key is String or seen.has(key):return "room_discovery_duplicate"
			seen[key]=true
	for key in s.visited:
		var parts:PackedStringArray=key.split(":")
		if parts.size()!=2 or not parts[0].is_valid_int() or int(parts[0]) not in [1,2] or not parts[1].is_valid_int() or int(parts[1]) not in range(9):return "room_visit_invalid"
	if "%d:%d"%[s.floor_index,s.active_room_id] not in s.visited:return "room_active_not_visited"
	var portal_keys:Array=[]
	for floor in s.floors:
		for portal in floor.portals:portal_keys.append(portal.portal_id)
	for key in s.discovered_portals:
		if key not in portal_keys:return "room_discovery_invalid"
	if not s.effect_processed_at is Dictionary:return "room_effect_shape"
	for key in s.effect_processed_at:
		if not key is String or not preload("res://sim/int64_codec.gd").is_canonical(s.effect_processed_at[key]) or int(s.effect_processed_at[key])<0:return "room_effect_clock"
	if not s.pending_exit is Dictionary or not s.pending_pursuit is Array:return "room_pending_shape"
	if not s.pending_exit.is_empty():
		var k:Array=s.pending_exit.keys();k.sort()
		if k!=["actor_id","from_room","portal_id","request_id","revision","stage"] or s.pending_exit.portal_id not in portal_keys or not integer(s.pending_exit.from_room) or s.pending_exit.from_room!=s.active_room_id or not preload("res://sim/int64_codec.gd").is_canonical(s.pending_exit.actor_id) or s.pending_exit.stage not in ["REQUESTED","RESOLVED"]:return "room_exit_invalid"
	var pursued:Dictionary={}
	for row in s.pending_pursuit:
		var k:Array=row.keys();k.sort()
		if k!=["eligible_boundary","entity_id","floor_index","portal_id","source_room","target_room"] or not preload("res://sim/int64_codec.gd").is_canonical(row.entity_id) or int(row.entity_id)<1 or pursued.has(row.entity_id) or row.portal_id not in portal_keys or not integer(row.eligible_boundary) or row.eligible_boundary<0 or row.floor_index not in [1,2] or row.source_room not in range(9) or row.target_room not in range(9):return "room_pursuit_invalid"
		pursued[row.entity_id]=true
	return ""

static func integer(v:Variant)->bool:
	return v is int or v is float and is_finite(v) and v==floor(v)

static func world_error(w)->String:
	var s:Dictionary=w.party_encounter.nine_room_floor
	if s.is_empty():return ""
	if s.has("care"):
		for key in s.care.residuals.keys()+s.care.combat_actor_ids:
			if int(key) not in w.party_encounter.party_member_ids:return "care_member_invalid"
	if int(s.floor_index)!=int(w.party_encounter.expedition_cycle.floor_index):return "room_floor_scope_mismatch"
	for key in s.effect_processed_at:
		if not valid_room_key(key) or int(s.effect_processed_at[key])>w.world_time:return "room_effect_clock_invalid"
	# Catch-up may have touched a target whose transition subsequently failed.
	# Such a room clock is valid even though it was never visited.
	for id in w.party_encounter.active_party_member_ids:
		if w.party_encounter.member(id).presence in ["DEFEATED","EXILED"]:continue
		if preload("res://sim/room_transition_rules.gd").membership(w.entities[id].position)!=Vector2i(int(s.floor_index),int(s.active_room_id)):return "room_party_membership_mismatch"
	for row in s.pending_pursuit:
		var id:=int(row.entity_id)
		if id not in w.party_encounter.enemy_ids or not w.entities.has(id):return "room_pursuit_actor_invalid"
		if preload("res://sim/room_transition_rules.gd").membership(w.entities[id].position)!=Vector2i(int(row.floor_index),int(row.source_room)):return "room_pursuit_source_mismatch"
	return ""

static func event_error(w,e)->String:
	if not str(e.type).begins_with("room."):
		if str(e.type).begins_with("care.") or e.type=="health.restored" and e.data.get("kind")=="CARE" or e.type=="party.energy_recovered" and e.data.get("ruleset_id")=="nine-room-care-v1":return load("res://sim/nine_room_care_rules.gd").event_error(w,e)
		return ""
	var s:Dictionary=w.party_encounter.nine_room_floor
	if s.is_empty():return "room_event_without_ruleset"
	if e.type=="room.exit_requested":
		var keys:Array=e.data.keys();keys.sort()
		if keys!=["portal_id","request_id","revision","schema_version"] or e.data.schema_version!=1 or not preload("res://sim/int64_codec.gd").is_canonical(e.data.request_id) or int(e.data.request_id)<1 or int(e.data.request_id)>int(s.request_serial) or not integer(e.data.revision) or e.data.revision<1 or e.actor_id!=w.party_encounter.protagonist_id:return "room_request_event_invalid"
	elif e.type=="room.exit_failed":
		var keys:Array=e.data.keys();keys.sort()
		if keys!=["reason","request_id"] or not e.data.reason is String or not preload("res://sim/int64_codec.gd").is_canonical(e.data.request_id):return "room_failure_event_invalid"
	elif e.type in ["room.entered","room.pursuit_arrived"]:
		var keys:Array=e.data.keys();keys.sort()
		if keys!=["floor_index","from_position","portal_id","request_id","ruleset_id","schema_version","source_room","target_room","to_position"] or e.data.schema_version!=1 or e.data.ruleset_id!=Generator.RULESET_ID or e.data.floor_index not in [1,2] or e.data.source_room not in range(9) or e.data.target_room not in range(9):return "room_entry_event_invalid"
		for field in ["from_position","to_position"]:
			if not e.data[field] is Array or e.data[field].size()!=2 or not integer(e.data[field][0]) or not integer(e.data[field][1]):return "room_entry_position_invalid"
		var from:=Vector2i(e.data.from_position[0],e.data.from_position[1]);var to:=Vector2i(e.data.to_position[0],e.data.to_position[1])
		var rules=preload("res://sim/room_transition_rules.gd")
		if rules.membership(from)!=Vector2i(e.data.floor_index,e.data.source_room) or rules.membership(to)!=Vector2i(e.data.floor_index,e.data.target_room) or e.position!=to:return "room_entry_membership_invalid"
		var p:Dictionary={}
		for portal in s.floors[int(e.data.floor_index)-1].portals:
			if portal.portal_id==e.data.portal_id:p=portal;break
		if p.is_empty() or [mini(int(e.data.source_room),int(e.data.target_room)),maxi(int(e.data.source_room),int(e.data.target_room))]!=[int(p.a),int(p.b)]:return "room_entry_portal_invalid"
		var local:Array=p.a_cell if int(e.data.target_room)==int(p.a) else p.b_cell
		var exit:=Vector2i(local[0]+(int(e.data.floor_index)-1)*24,local[1])
		if rules.distance(to,exit)>int(Generator.CONFIG.arrival_radius) or to==exit:return "room_entry_arrival_invalid"
		if e.type=="room.entered" and e.actor_id not in w.party_encounter.party_member_ids or e.type=="room.pursuit_arrived" and e.actor_id not in w.party_encounter.enemy_ids:return "room_entry_actor_invalid"
	else:return "room_event_kind_invalid"
	return ""

static func valid_room_key(key:String)->bool:
	var parts:=key.split(":")
	return parts.size()==2 and parts[0] in ["1","2"] and parts[1] in ["0","1","2","3","4","5","6","7","8"]
