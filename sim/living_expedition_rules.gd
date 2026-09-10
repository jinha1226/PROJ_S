extends RefCounted
const EVENT:="campaign.living_expedition_initialized"
const TAG:="independent_explorer"
const FLOOR_TAG:="visitor_floor:"
const SPECIES:=["human","elf","dwarf","orc","beastkin"]
static func expanded_exploration(world)->bool:
	for event in world.events:
		if event.type==EVENT:return int(event.data.get("version",1))>=4
	return false
static func snapshot_expanded_exploration(snapshot:Dictionary)->bool:
	for row in snapshot.get("events",[]):
		if row.get("type","")==EVENT:return int(row.get("data",{}).get("version",1))>=4
	return false
static func roster_randomized(world)->bool:
	for event in world.events:
		if event.type==EVENT:return int(event.data.get("version",1))>=3
	return false
static func snapshot_roster_randomized(snapshot:Dictionary)->bool:
	for row in snapshot.get("events",[]):
		if row.get("type","")==EVENT:return int(row.get("data",{}).get("version",1))>=3
	return false
static func enabled(world)->bool:
	for event in world.events:
		if event.type==EVENT:return true
	return false
static func snapshot_enabled(snapshot:Dictionary)->bool:
	for row in snapshot.get("events",[]):
		if row.get("type","")==EVENT:return true
	return false
static func independent(world,id:int)->bool:
	var entity=world.entities.get(id)
	return entity!=null and TAG in entity.tags
static func present(world,id:int)->bool:
	if not independent(world,id) or world.party_encounter==null:return false
	var party=world.party_encounter;var entity=world.entities[id];var member=party.member(id)
	return member!=null and party.expedition_cycle.phase=="DUNGEON" and member.presence=="RECRUITABLE" \
		and FLOOR_TAG+str(party.expedition_cycle.floor_index) in entity.tags and "visitor_returned" not in entity.tags
static func species(seed_value:int,index:int)->String:
	return str(SPECIES[posmod(seed_value+index,SPECIES.size())])
