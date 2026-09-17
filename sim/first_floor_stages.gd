extends RefCounted
const Catalog=preload("res://sim/stage_catalog.gd")
const LEGEND=Catalog.LEGEND
static var CONTENT:Dictionary=_build()
static func _build()->Dictionary:
	var doc:Dictionary=Catalog.floor(1)
	assert(Catalog.error(doc).is_empty(),"f1 stage catalog invalid: "+Catalog.error(doc))
	var rooms:Array=[]
	for spec in doc.rooms:
		var row:Dictionary=spec.duplicate(true)
		row["enemy_cells"]=Catalog.wave_enemies(spec,0).map(func(e):return e.cell)
		rooms.append(row)
	return {"version":doc.version,"edges":doc.edges,"event_room":doc.event_room,"rooms":rooms}
static func room(id:int)->Dictionary:return CONTENT.rooms[id]
static func stamp(terrain:Array[String],origin:Vector2i,id:int)->void:Catalog.stamp(terrain,24,origin,room(id))
static func npc_position()->Vector2i:
	var id:int=CONTENT.event_room;var cell:Array=room(id).npc_cell
	return Vector2i(id%3*8+cell[0],id/3*8+cell[1])
