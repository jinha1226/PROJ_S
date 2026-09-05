class_name CampaignEncounterStream
extends RefCounted

const RULESET_ID := "campaign-encounter-distance-stream-v1"
const ACTIVATION_RADIUS := 12
const FLOOR_TAG_PREFIX := "campaign_floor:"
const EXPEDITION_TAG_PREFIX := "campaign_expedition:"
const GROUP_TAG_PREFIX := "encounter_group:"


static func current_floor_enemy_ids(world)->Array[int]:
	var result:Array[int]=[]
	if world==null or world.party_encounter==null:return result
	var state=world.party_encounter
	var cycle=state.expedition_cycle
	if cycle==null:return state.enemy_ids.duplicate()
	var floor_tag:=FLOOR_TAG_PREFIX+str(int(cycle.floor_index))
	var expedition_tag:=EXPEDITION_TAG_PREFIX+str(int(cycle.expedition_index))
	for enemy_id_value in state.enemy_ids:
		var enemy_id:=int(enemy_id_value)
		var entity=world.entities.get(enemy_id)
		if entity!=null and floor_tag in entity.tags and expedition_tag in entity.tags:
			result.append(enemy_id)
	# Old town fixtures could record a deeper return floor before authored floors
	# existed. Preserve that last expedition's enemy scope while in town; runtime
	# action activation still returns an empty set outside DUNGEON.
	if result.is_empty() and str(cycle.phase)=="TOWN":
		for enemy_id_value in state.enemy_ids:
			var enemy_id:=int(enemy_id_value)
			var entity=world.entities.get(enemy_id)
			if entity!=null and expedition_tag in entity.tags:
				result.append(enemy_id)
	# Pre-campaign saves and compact fixtures have no floor tags. Their historical
	# single encounter remains the entire current scope.
	if result.is_empty() and not _has_campaign_enemy(world,state.enemy_ids):
		for enemy_id_value in state.enemy_ids:result.append(int(enemy_id_value))
	result.sort();return result


static func active_enemy_ids(world)->Array[int]:
	var current:=current_floor_enemy_ids(world)
	if world==null or world.party_encounter==null or current.is_empty():return []
	var state=world.party_encounter
	if state.expedition_cycle!=null \
			and str(state.expedition_cycle.phase)!="DUNGEON":return []
	var alive:Array[int]=[]
	for enemy_id in current:
		if world.entities.has(enemy_id) and world.is_unresolved_enemy(enemy_id):
			alive.append(enemy_id)
	if alive.is_empty() or str(state.safe_phase)=="GROUPED_COMPLETE":return []
	var contact_group:=group_id(world,int(state.contact_enemy_id)) \
		if int(state.contact_enemy_id)>0 else ""
	if not contact_group.is_empty():return _alive_group(world,alive,contact_group)
	var aware_groups:Dictionary={}
	for enemy_id in alive:
		var awareness=state.enemy_awareness(enemy_id)
		if awareness!=null and awareness.awareness_state in ["ALERT","HUNTING",
				"SEARCHING","RETURNING"]:
			aware_groups[group_id(world,enemy_id)]=true
	if not aware_groups.is_empty():
		return _nearest_group(world,alive,aware_groups.keys(),2147483647)
	var hero=world.entities.get(state.protagonist_id)
	if hero==null:return []
	return _nearest_group(world,alive,_group_ids(world,alive),ACTIVATION_RADIUS,
		hero.position)


static func observation(world)->Dictionary:
	var unavailable:={"schema_version":1,"ruleset_id":RULESET_ID,
		"available":false,"floor_index":0,"activation_radius":ACTIVATION_RADIUS,
		"active_group_id":"","cleared_group_count":0,"group_count":0,
		"remaining_enemy_count":0,"groups":[]}
	if world==null or world.party_encounter==null:return unavailable.duplicate(true)
	var current:=current_floor_enemy_ids(world)
	var active:=active_enemy_ids(world)
	var active_group:=group_id(world,active[0]) if not active.is_empty() else ""
	var grouped:Dictionary={}
	for enemy_id in current:
		var group:=group_id(world,enemy_id)
		if not grouped.has(group):grouped[group]=[]
		grouped[group].append(enemy_id)
	var rows:Array[Dictionary]=[];var cleared:=0;var remaining:=0
	var ids:Array=grouped.keys();ids.sort()
	for group_value in ids:
		var group:=str(group_value);var members:Array=grouped[group]
		var alive_count:=0
		for enemy_id in members:
			if world.is_unresolved_enemy(int(enemy_id)):alive_count+=1
		remaining+=alive_count
		var status:="CLEARED" if alive_count==0 else (
			"ACTIVE" if group==active_group else "DORMANT")
		if status=="CLEARED":cleared+=1
		rows.append({"group_id":group,"status":status,
			"enemy_count":members.size(),"remaining_enemy_count":alive_count,
			"enemy_ids":members.duplicate()})
	var cycle=world.party_encounter.expedition_cycle
	return {"schema_version":1,"ruleset_id":RULESET_ID,"available":true,
		"floor_index":int(cycle.floor_index) if cycle!=null else 1,
		"activation_radius":ACTIVATION_RADIUS,"active_group_id":active_group,
		"cleared_group_count":cleared,"group_count":rows.size(),
		"remaining_enemy_count":remaining,"groups":rows}.duplicate(true)


static func group_id(world,enemy_id:int)->String:
	var entity=world.entities.get(enemy_id) if world!=null else null
	if entity==null:return ""
	for tag_value in entity.tags:
		var tag:=str(tag_value)
		if tag.begins_with(GROUP_TAG_PREFIX):return tag.trim_prefix(GROUP_TAG_PREFIX)
	return "LEGACY"


static func victory_scope(world)->Dictionary:
	var cycle=world.party_encounter.expedition_cycle
	var ids:=current_floor_enemy_ids(world)
	return {"schema_version":1,"ruleset_id":RULESET_ID,
		"floor_index":int(cycle.floor_index) if cycle!=null else 1,
		"expedition_index":int(cycle.expedition_index) if cycle!=null else 1,
		"enemy_ids":ids.map(func(value):return str(int(value)))}


static func is_campaign_runtime(world)->bool:
	return world!=null and world.party_encounter!=null \
		and _has_campaign_enemy(world,world.party_encounter.enemy_ids)


static func _nearest_group(world,alive:Array[int],groups:Array,
		maximum_distance:int,origin:Vector2i=Vector2i(-1,-1))->Array[int]:
	if origin==Vector2i(-1,-1):
		var hero=world.entities.get(world.party_encounter.protagonist_id)
		if hero==null:return []
		origin=hero.position
	var ranked:Array[Dictionary]=[]
	for group_value in groups:
		var group:=str(group_value);var members:=_alive_group(world,alive,group)
		if members.is_empty():continue
		var distance:=2147483647
		for enemy_id in members:
			var position:Vector2i=world.entities[enemy_id].position
			distance=mini(distance,maxi(absi(position.x-origin.x),
				absi(position.y-origin.y)))
		if distance<=maximum_distance:
			ranked.append({"group_id":group,"distance":distance,"members":members})
	ranked.sort_custom(func(a:Dictionary,b:Dictionary):
		return int(a.distance)<int(b.distance) if int(a.distance)!=int(b.distance) \
			else str(a.group_id)<str(b.group_id))
	if ranked.is_empty():return []
	var result:Array[int]=[]
	for value in ranked[0].members:result.append(int(value))
	return result


static func _alive_group(world,alive:Array[int],group:String)->Array[int]:
	var result:Array[int]=[]
	for enemy_id in alive:
		if group_id(world,enemy_id)==group:result.append(enemy_id)
	result.sort();return result


static func _group_ids(world,ids:Array[int])->Array:
	var result:Array=[]
	for enemy_id in ids:
		var group:=group_id(world,enemy_id)
		if group not in result:result.append(group)
	result.sort();return result


static func _has_campaign_enemy(world,ids:Array)->bool:
	for enemy_id_value in ids:
		var entity=world.entities.get(int(enemy_id_value))
		if entity==null:continue
		for tag_value in entity.tags:
			if str(tag_value).begins_with(FLOOR_TAG_PREFIX):return true
	return false
