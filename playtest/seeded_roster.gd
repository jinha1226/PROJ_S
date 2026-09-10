extends RefCounted
## Bootstrap v3 only. Independent RNG never consumes simulation randomness.
const SPECIES:=["human","elf","dwarf","orc","beastkin"]
const NAMES:=["나래","루온","아린","카엘","테린","모라","리엔","벨"]
static func rng(world_seed:int,personality_seed:int,channel:String)->RandomNumberGenerator:
	var bytes:PackedByteArray=("roster-v3/%d/%d/%s"%[world_seed,personality_seed,channel]).sha256_buffer()
	var value:=0
	for i in range(7):value=(value<<8)|int(bytes[i])
	var random:=RandomNumberGenerator.new();random.seed=value
	return random
static func companion(world_seed:int,personality_seed:int)->Dictionary:
	var random:=rng(world_seed,personality_seed,"companion")
	return {"name":NAMES[random.randi_range(0,NAMES.size()-1)],"species":SPECIES[random.randi_range(0,4)],
		"loadout":"SUPPORT_V1" if random.randi_range(0,1)==0 else "VANGUARD_V1"}
static func population(world_seed:int,personality_seed:int)->Array:
	var people:Array=preload("res://sim/town_population_rules.gd").PEOPLE.duplicate(true)
	var explorers:Array=people.slice(0,8)
	var random:=rng(world_seed,personality_seed,"population")
	for index in range(explorers.size()-1,0,-1):
		var other:=random.randi_range(0,index);var swap=explorers[index]
		explorers[index]=explorers[other];explorers[other]=swap
	explorers.resize(random.randi_range(5,8))
	explorers.append_array(people.slice(8))
	for person in explorers:person["species"]=SPECIES[random.randi_range(0,4)]
	return explorers
static func apply_layout(layout:Dictionary,world_seed:int,personality_seed:int)->Dictionary:
	var result:=layout.duplicate(true)
	var floors:Dictionary=result.get("campaign_floors",{})
	if floors.is_empty():_floor(result,world_seed,personality_seed)
	else:
		for index in floors:_floor(floors[index],world_seed,personality_seed)
		result=preload("res://playtest/campaign_world_map.gd").select_floor(result,int(result.get("floor_index",1)))
	return result
static func _floor(floor:Dictionary,world_seed:int,personality_seed:int)->void:
	for key in ["enemy_roster","runtime_enemy_roster"]:
		for row in floor.get(key,[]):
			var random:=rng(world_seed,personality_seed,"enemy/%s/%s"%[floor.get("floor_index",1),str(row.position)])
			row.species_id="kobold" if random.randi_range(0,1)==0 else "goblin"
	for group in floor.get("encounter_groups",[]):
		var species:Array[String]=[]
		for row in floor.get("enemy_roster",[]):
			if row.get("group_id","")==group.get("group_id",""):species.append(str(row.species_id))
		if not species.is_empty():group.species_ids=species
