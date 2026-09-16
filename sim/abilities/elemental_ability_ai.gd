extends RefCounted
## Read-only selection for the initial environment abilities.
const Runtime=preload("res://sim/abilities/monster_ability_runtime.gd")
const Action=preload("res://sim/party_action_command.gd")
static func suggest(world,actor:int):
	if not preload("res://sim/living_expedition_rules.gd").elemental_parts(world):return null
	var member=world.party_encounter.member(actor)
	if member==null or member.stress>=600 or world.entities[actor].health*2<world.entities[actor].max_health:return null
	var ids:Array=preload("res://sim/campaign_encounter_stream.gd").active_enemy_ids(world);ids.sort()
	for target in ids:
		if not Runtime.alive(world,target):continue
		var tile=world.tile_at(world.entities[target].position)
		for skill in ["ARC_GLAND","COLD_GLAND","WATER_SAC"]:
			if skill not in member.active_skill_ids() or not preload("res://sim/abilities/party_active_skill_service.gd").assess(world,actor,skill,target,false,true).accepted:continue
			if skill=="WATER_SAC" and (tile.wetness>=30 or tile.surface_id=="ICE"):continue
			if skill=="COLD_GLAND" and (tile.wetness<10 or tile.temperature<=0):continue
			if skill=="ARC_GLAND" and arc_reaches_ally(world,world.entities[target].position,45):continue
			return Action.skill(actor,skill,target)
	return null

static func arc_reaches_ally(world,origin:Vector2i,power:int)->bool:
	var queue:Array=[{"p":origin,"power":power}];var visited:Dictionary={}
	while not queue.is_empty():
		var row:Dictionary=queue.pop_front();var p:Vector2i=row.p
		if visited.has(p):continue
		visited[p]=true
		for id in world.party_encounter.active_party_member_ids:
			if Runtime.alive(world,id) and world.entities[id].position==p:return true
		if int(row.power)<=8:continue
		for next in world.cardinal_neighbors(p):
			if not visited.has(next) and world.tile_at(next).effective_conductivity()>=25:queue.append({"p":next,"power":int(row.power)-8})
	return false
