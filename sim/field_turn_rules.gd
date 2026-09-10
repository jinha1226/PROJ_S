extends RefCounted

## One dungeon timeline. GROUPED is retained as a save wire value, not a
## combat gate; living companions occupy their own cells throughout a floor.
const TAG := "field_turns_v1"
const FORMATIONS := {"NONE":"자유", "COLUMN":"종대", "LINE":"횡대", "WEDGE":"쐐기"}

static func formation(world)->String:
	for index in range(world.events.size()-1,-1,-1):
		if world.events[index].type=="party.field_formation_selected":
			return str(world.events[index].data.get("formation","NONE"))
	return "NONE"

static func formation_cell(world,actor_id:int)->Vector2i:
	var party=world.party_encounter
	var leader:int=world.party_control_actor_id()
	var followers:Array=party.active_party_member_ids.duplicate()
	followers.erase(leader)
	var index:int=followers.find(actor_id)
	var back:Vector2i=-party.facing
	var right:=Vector2i(-party.facing.y,party.facing.x)
	var offset:Vector2i=back*(index+1)
	match formation(world):
		"LINE":offset=right*((index/2+1)*(1 if index%2==0 else -1))
		"WEDGE":offset=back*(index/2+1)+right*((index/2+1)*(1 if index%2==0 else -1))
	return world.entities[leader].position+offset

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
	var vision=preload("res://sim/vision_rules.gd")
	for id in world.party_encounter.active_party_member_ids:
		var member=world.party_encounter.member(id)
		if member.presence!="DEPLOYED" or not world.can_act(id,world.world_time):continue
		var origin:Vector2i=world.entities[id].position
		var profile=vision.profile_for_entity(world.entities[id])
		var visible=vision.visible_cells(world,origin,world.party_encounter.facing,profile,
			vision.lighting_for_world(world))
		for key in visible:cells[key]=true
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
