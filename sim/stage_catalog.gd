extends RefCounted
const Items=preload("res://sim/item_registry.gd")
const Loader=preload("res://sim/json_content_loader.gd")
const Perception=preload("res://sim/enemy_perception_registry.gd")
const VERSION:=2
const SIZE:=8
const LEGEND={".":"stone_floor","#":"wall","~":"shallow_water","r":"rubble"}
const ROLES:=["COMBAT","HAZARD","SAFE","STAIRS"]
const ENEMY_ROLES:=["ASSAULT","ARCHER","SHIELD","SUPPORT"]
const OBJECTIVES:=["ELIMINATE","SURVIVE","REACH","PROTECT"]
const EDGES:=["N","E","S","W"]
const HAZARD_TYPES:=["shallow_water"]
const DESIGN_KEYS:=["concept","counterplay","difficulty","failure_mode","intended_solution"]
static var _floors:Dictionary={}

# "floor" collides with GDScript's built-in Math floor(); an unqualified call from inside
# this class (e.g. room()) resolves to the builtin, not our static method, and crashes.
# _floor_doc() is the real implementation; floor() is the public alias callers use as
# Catalog.floor(index), which is a qualified call and unaffected by the collision.
static func _floor_doc(index:int)->Dictionary:
	if not _floors.has(index):_floors[index]=Loader.load_document("res://data/content/stages/f%d.json"%index)
	return _floors[index]
static func floor(index:int)->Dictionary:return _floor_doc(index)
static func room(floor_index:int,id:int)->Dictionary:return _floor_doc(floor_index).rooms[id]
static func wave_enemies(spec:Dictionary,wave:int)->Array:
	return spec.get("enemies",[]).filter(func(e):return int(e.wave)==wave)
static func stamp(terrain:Array[String],width:int,origin:Vector2i,spec:Dictionary)->void:
	for y in range(SIZE):
		for x in range(SIZE):terrain[(origin.y+y)*width+origin.x+x]=LEGEND[spec.rows[y][x]]
static func _cell_ok(spec:Dictionary,cell:Variant)->bool:
	return cell is Array and cell.size()==2 and int(cell[0]) in range(SIZE) and int(cell[1]) in range(SIZE) and spec.rows[int(cell[1])][int(cell[0])]!="#"
static func error(doc:Variant)->String:
	if not doc is Dictionary or int(doc.get("version",0))!=VERSION:return "version"
	if not doc.get("rooms") is Array or doc.rooms.size()!=9:return "room_count"
	if not doc.get("edges") is Array or not doc.has("event_room"):return "floor_keys"
	var ids:Dictionary={}
	for spec in doc.rooms:
		var id:String=str(spec.get("id",""))
		if id.is_empty() or ids.has(id):return "room_id"
		ids[id]=true
		for key in ["name","role","biome","hint","rows","entries","enemies","reinforcements","objective","hazards","loot","design"]:
			if not spec.has(key):return "%s_missing:%s"%[key,id]
		if spec.role not in ROLES:return "role:"+id
		if not spec.rows is Array or spec.rows.size()!=SIZE:return "rows:"+id
		for row in spec.rows:
			if not row is String or row.length()!=SIZE:return "rows:"+id
			for ch in row:
				if not LEGEND.has(ch):return "legend:"+id
		var seen:Dictionary={}
		for e in spec.enemies:
			if not e is Dictionary or not e.has("cell") or not e.has("kind") or not e.has("role") or not e.has("wave"):return "enemy_keys:"+id
			if not _cell_ok(spec,e.cell):return "enemy_on_wall:"+id
			var key:="%d:%d"%[int(e.cell[0]),int(e.cell[1])]
			if int(e.wave)==0 and seen.has(key):return "enemy_cell_duplicate:"+id
			if int(e.wave)==0:seen[key]=true
			if e.role not in ENEMY_ROLES:return "enemy_role:"+id
			if int(e.wave)<0:return "enemy_wave:"+id
			if Perception.profile(str(e.kind)).is_empty():return "enemy_kind:"+id
		for dir in spec.entries:
			if dir not in EDGES or not spec.entries[dir] is Array:return "entries:"+id
			for cell in spec.entries[dir]:
				if not _cell_ok(spec,cell):return "entry_cell:"+id
		var r:Dictionary=spec.reinforcements
		if not r is Dictionary or int(r.get("interval_rounds",0))<1 or int(r.get("cap",-1))<0 or not r.get("spawn_edges") is Array:return "reinforcements:"+id
		for edge in r.spawn_edges:
			if edge not in EDGES:return "spawn_edge:"+id
		var o:Dictionary=spec.objective
		if not o is Dictionary or o.get("type","") not in OBJECTIVES or not o.has("retreat_allowed"):return "objective:"+id
		if o.type=="SURVIVE" and int(o.get("rounds",0))<1:return "objective_rounds:"+id
		if o.type in ["REACH","PROTECT"] and not _cell_ok(spec,o.get("cell")):return "objective_cell:"+id
		for h in spec.hazards:
			if not h is Dictionary or h.get("type","") not in HAZARD_TYPES or not _cell_ok(spec,h.get("cell")):return "hazard:"+id
		for drop in spec.loot:
			if not _cell_ok(spec,drop.get("cell")) or not Items.has(str(drop.get("item",""))) or int(drop.get("quantity",0))<1:return "loot:"+id
		if spec.has("npc_cell") and not _cell_ok(spec,spec.npc_cell):return "npc_cell:"+id
		var d:Variant=spec.design
		if not d is Dictionary:return "design_missing:"+id
		var keys:Array=d.keys();keys.sort()
		if keys!=DESIGN_KEYS:return "design_keys:"+id
		for key in ["concept","intended_solution","counterplay","failure_mode"]:
			if not d[key] is String or str(d[key]).strip_edges().is_empty():return "design_text:"+id
		if int(d.difficulty)<1 or int(d.difficulty)>5:return "design_difficulty:"+id
	return ""
