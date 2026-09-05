class_name CampaignWorldMap
extends RefCounted

# Both authored floors live in one immutable simulation topology. Floor changes
# therefore preserve the complete event, injury, item, memory and relationship
# history without rewriting old movement against a different tile layer.
const SCHEMA_VERSION := 1
const RULESET_ID := "campaign-world-two-floor-v1"
const FLOOR_GAP := 8
const FloorMapScript = preload("res://playtest/campaign_floor_map.gd")


static func generate(seed:int, selected_floor:int=1)->Dictionary:
	var floor_one:Dictionary=FloorMapScript.generate(1,seed)
	var floor_two:Dictionary=FloorMapScript.generate(2,seed)
	if floor_one.is_empty() or floor_two.is_empty():return {}
	var floor_one_size:=Vector2i(int(floor_one.width),int(floor_one.height))
	var floor_two_size:=Vector2i(int(floor_two.width),int(floor_two.height))
	var offsets:={1:Vector2i.ZERO,
		2:Vector2i(floor_one_size.x+FLOOR_GAP,0)}
	var world_size:=Vector2i(offsets[2].x+floor_two_size.x,
		maxi(floor_one_size.y,floor_two_size.y))
	var terrain:Array[String]=[];terrain.resize(world_size.x*world_size.y)
	terrain.fill("wall")
	_copy_terrain(floor_one,terrain,world_size,offsets[1])
	_copy_terrain(floor_two,terrain,world_size,offsets[2])
	var floors:Dictionary={
		1:_translated_floor(floor_one,offsets[1]),
		2:_translated_floor(floor_two,offsets[2]),
	}
	var world_hazards:Array[Dictionary]=[]
	for floor_index in [1,2]:
		for row_value in floors[floor_index].get("floor_hazards",[]):
			world_hazards.append((row_value as Dictionary).duplicate(true))
	var base:Dictionary={"schema_version":SCHEMA_VERSION,
		"ruleset_id":RULESET_ID,"seed":seed,"width":world_size.x,
		"height":world_size.y,"terrain":terrain,"campaign_floors":floors,
		"campaign_floor_indices":[1,2],"hazards":world_hazards}
	return select_floor(base,selected_floor)


static func select_floor(world_layout:Dictionary,floor_index:int)->Dictionary:
	var floors:Variant=world_layout.get("campaign_floors",{})
	if not floors is Dictionary or not floors.has(floor_index):return {}
	var result:=world_layout.duplicate(true)
	var floor:Dictionary=floors[floor_index]
	for key in floor:
		result[key]=floor[key].duplicate(true) if floor[key] is Array \
			or floor[key] is Dictionary else floor[key]
	# Hazards belong to the immutable aggregate topology and are installed once.
	# floor_hazards remains available for current-floor presentation.
	result["hazards"]=world_layout.get("hazards",[]).duplicate(true)
	return result


static func selected(seed:int,floor_index:int)->Dictionary:
	return generate(seed,floor_index)


static func floor_bounds(layout:Dictionary)->Rect2i:
	var raw:Variant=layout.get("floor_bounds",[])
	return Rect2i(int(raw[0]),int(raw[1]),int(raw[2]),int(raw[3])) \
		if raw is Array and raw.size()==4 else Rect2i()


static func _copy_terrain(source:Dictionary,target:Array[String],
		world_size:Vector2i,offset:Vector2i)->void:
	var width:=int(source.width);var height:=int(source.height)
	var rows:Array=source.terrain
	for y in range(height):
		for x in range(width):
			target[(offset.y+y)*world_size.x+offset.x+x]=str(rows[y*width+x])


static func _translated_floor(source:Dictionary,offset:Vector2i)->Dictionary:
	var result:Dictionary={"floor_index":int(source.floor_index),
		"floor_label":str(source.floor_label),"theme_id":str(source.theme_id),
		"floor_ruleset_id":str(source.ruleset_id),
		"floor_bounds":[offset.x,offset.y,int(source.width),int(source.height)],
		"floor_width":int(source.width),"floor_height":int(source.height),
		"anchor_portal_clear_radius":int(source.anchor_portal_clear_radius),
		"planned_contact_count":int(source.planned_contact_count),
		"planned_enemy_count":int(source.planned_enemy_count),
		"door_positions":_positions(source.get("door_positions",[]),offset),
		"entry_position":source.entry_position+offset,
		"hero_position":source.hero_position+offset,
		"anchor_portal_position":source.anchor_portal_position+offset,
		"transition_portal_position":source.transition_portal_position+offset,
		"exit_position":source.exit_position+offset,
		"room_centers":_positions(source.get("room_centers",[]),offset),
		"supply_positions":_positions(source.get("supply_positions",[]),offset)}
	var rooms:Array[Rect2i]=[]
	for room_value in source.get("rooms",[]):
		var room:Rect2i=room_value;rooms.append(Rect2i(room.position+offset,room.size))
	result["rooms"]=rooms
	var regions:Array[Dictionary]=[]
	for row_value in source.get("regions",[]):
		var row:Dictionary=row_value.duplicate(true);var bounds:Array=row.bounds
		row.bounds=[int(bounds[0])+offset.x,int(bounds[1])+offset.y,
			int(bounds[2]),int(bounds[3])];regions.append(row)
	result["regions"]=regions;result["field_regions"]=regions.duplicate(true)
	var routes:Array[Dictionary]=[]
	for row_value in source.get("routes",[]):
		var row:Dictionary=row_value.duplicate(true)
		row.points=_positions(row.get("points",[]),offset);routes.append(row)
	result["routes"]=routes
	var groups:Array[Dictionary]=[]
	for row_value in source.get("encounter_groups",[]):
		var row:Dictionary=row_value.duplicate(true);var position:Array=row.position
		row.position=[int(position[0])+offset.x,int(position[1])+offset.y]
		groups.append(row)
	result["encounter_groups"]=groups
	var roster:Array[Dictionary]=[]
	for row_value in source.get("runtime_enemy_roster",[]):
		var row:Dictionary=row_value.duplicate(true)
		row.position=(row.position as Vector2i)+offset;roster.append(row)
	result["runtime_enemy_roster"]=roster
	result["enemy_roster"]=roster.duplicate(true)
	result["enemy_positions"]=roster.map(func(row):return row.position)
	var floor_hazards:Array[Dictionary]=[]
	for row_value in source.get("hazards",[]):
		var row:Dictionary=row_value.duplicate(true)
		row.position=(row.position as Vector2i)+offset;floor_hazards.append(row)
	result["floor_hazards"]=floor_hazards
	result["material_positions"]=_position_dictionary(
		source.get("material_positions",{}),offset)
	result["presentation_material_positions"]=_position_dictionary(
		source.get("presentation_material_positions",{}),offset)
	return result


static func _positions(values:Array,offset:Vector2i)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	for value in values:
		if value is Vector2i:result.append(value+offset)
	return result


static func _position_dictionary(value:Variant,offset:Vector2i)->Dictionary:
	var result:Dictionary={}
	if not value is Dictionary:return result
	for key in value:result[key]=_positions(value[key],offset)
	return result
