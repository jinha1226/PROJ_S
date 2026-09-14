extends RefCounted
static var CONTENT:Dictionary=preload("res://sim/json_content_loader.gd").load_document("res://data/content/first_floor_stages.json")
const LEGEND={".":"stone_floor","#":"wall","~":"shallow_water","r":"rubble"}
static func room(id:int)->Dictionary:return CONTENT.rooms[id]
static func stamp(terrain:Array[String],origin:Vector2i,id:int)->void:
	var spec:=room(id)
	for y in range(8):
		for x in range(8):terrain[(origin.y+y)*24+origin.x+x]=LEGEND[spec.rows[y][x]]
static func npc_position()->Vector2i:
	var id:int=CONTENT.event_room;var cell:Array=room(id).npc_cell
	return Vector2i(id%3*8+cell[0],id/3*8+cell[1])
