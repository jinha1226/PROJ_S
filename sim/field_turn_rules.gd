extends RefCounted

## One dungeon timeline. GROUPED is retained as a save wire value, not a
## combat gate; living companions occupy their own cells throughout a floor.
const TAG := "field_turns_v1"

static func enabled(world)->bool:
	return world!=null and world.party_encounter!=null and world.entities.has(
		world.party_encounter.protagonist_id) and TAG in world.entities[
		world.party_encounter.protagonist_id].tags

static func active(world)->bool:
	return enabled(world) and world.party_encounter.safe_phase!="PARTY_DEFEATED" \
		and (world.party_encounter.expedition_cycle==null or \
		world.party_encounter.expedition_cycle.phase=="DUNGEON")

static func visible(world,enemy_id:int)->bool:
	var enemy=world.entities.get(enemy_id)
	if enemy==null or not world.is_autonomous_target(enemy_id):return false
	return not preload("res://sim/party_perception_registry.gd").visible_party_members(
		world,world.party_encounter,enemy.position).is_empty()

static func visible_cells(world)->Dictionary:
	var cells:Dictionary={}
	for id in world.party_encounter.active_party_member_ids:
		var member=world.party_encounter.member(id)
		if member.presence!="DEPLOYED" or not world.can_act(id,world.world_time):continue
		var origin:Vector2i=world.entities[id].position
		var radius:int=preload("res://sim/party_perception_registry.gd").sight_range(world,world.party_encounter,id)
		for y in range(maxi(0,origin.y-radius),mini(world.height,origin.y+radius+1)):
			for x in range(maxi(0,origin.x-radius),mini(world.width,origin.x+radius+1)):
				if preload("res://sim/enemy_perception_registry.gd").has_line_of_sight(world,origin,Vector2i(x,y)):
					cells["%d:%d"%[x,y]]=true
	return cells

static func place_companions(sim)->bool:
	var world=sim.world
	if not active(world):return true
	var party=world.party_encounter
	for id in party.active_party_member_ids:
		var member=party.member(id)
		if member.presence!="GROUPED":continue
		var destination:Variant=sim.party_coordinator._fallback_cell(party.group_anchor,{})
		if destination==null:return false
		var previous:Vector2i=world.entities[id].position
		world.entities[id].position=destination
		member.presence="DEPLOYED"
		world.reindex_entity_occupancy(id,previous,destination)
	return true
