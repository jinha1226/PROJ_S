class_name BaseSettlementRules
extends RefCounted

const SCHEMA_VERSION:=1
const RULESET_ID:="base-settlement-grid-v1"
const WIDTH:=16
const HEIGHT:=16
const BUILDING_TYPES:=["STORAGE","LODGE","CLINIC","MARKET","ARMORY","GATE"]
const CONSTRUCTIBLE_TYPES:=["CLINIC","MARKET","ARMORY"]
const LABELS:={"STORAGE":"창고","LODGE":"숙소","CLINIC":"진료소",
	"MARKET":"시장","ARMORY":"대장간","GATE":"원정문"}
const FOOTPRINTS:={"STORAGE":Vector2i(3,3),"LODGE":Vector2i(3,2),
	"CLINIC":Vector2i(3,3),"MARKET":Vector2i(3,2),
	"ARMORY":Vector2i(3,2),"GATE":Vector2i(3,3)}
const CONSTRUCTION_COSTS:={
	"CLINIC":{"TIMBER":3,"STONE":2,"HERBS":2},
	"MARKET":{"TIMBER":6,"STONE":3,"HERBS":0},
	"ARMORY":{"TIMBER":3,"STONE":6,"HERBS":0},
}
const NEW_BASELINE:=[
	{"instance_id":"BLD_STORAGE_1","type_id":"STORAGE","tile_origin":[1,2],"rotation":0},
	{"instance_id":"BLD_LODGE_1","type_id":"LODGE","tile_origin":[11,2],"rotation":0},
	{"instance_id":"BLD_GATE_1","type_id":"GATE","tile_origin":[6,13],"rotation":0},
]
const LEGACY_EXTRA:=[
	{"instance_id":"BLD_CLINIC_1","type_id":"CLINIC","tile_origin":[1,8],"rotation":0},
	{"instance_id":"BLD_MARKET_1","type_id":"MARKET","tile_origin":[5,8],"rotation":0},
	{"instance_id":"BLD_ARMORY_1","type_id":"ARMORY","tile_origin":[11,8],"rotation":0},
]
const BLOCKED_TILES:=[Vector2i(0,0),Vector2i(1,0),Vector2i(14,0),Vector2i(15,0),
	Vector2i(0,1),Vector2i(15,1),Vector2i(0,5),Vector2i(15,5),Vector2i(0,11),
	Vector2i(15,11),Vector2i(2,6),Vector2i(13,6),Vector2i(4,11),Vector2i(11,11)]


static func has_initialization(events:Array)->bool:
	for event in events:
		if str(event.type)=="base.settlement_initialized":return true
	return false


static func buildings(events:Array,levels:Dictionary)->Array[Dictionary]:
	var by_id:Dictionary={}
	var baseline:Array=NEW_BASELINE.duplicate(true)
	if not has_initialization(events):baseline.append_array(LEGACY_EXTRA.duplicate(true))
	for row_value in baseline:
		var row:Dictionary=row_value
		by_id[str(row.instance_id)]=row.duplicate(true)
	for event in events:
		match str(event.type):
			"base.building_constructed":
				var row:Dictionary=event.data.get("building",{}).duplicate(true)
				if not row.is_empty():by_id[str(row.instance_id)]=row
	var result:Array[Dictionary]=[]
	for instance_id in by_id:
		var source:Dictionary=by_id[instance_id]
		var type_id:=str(source.type_id);var footprint:=rotated_footprint(type_id,int(source.rotation))
		result.append({"instance_id":instance_id,"type_id":type_id,
			"label":str(LABELS.get(type_id,type_id)),
			"tile_origin":source.tile_origin.duplicate(true),
			"footprint":[footprint.x,footprint.y],"rotation":int(source.rotation),
			"level":int(levels.get(type_id,1)),"movable":false,
			"fixed":type_id=="GATE","service_available":true})
	result.sort_custom(func(a:Dictionary,b:Dictionary):return str(a.instance_id)<str(b.instance_id))
	return result


static func tiles()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var position:=Vector2i(x,y);var reserved:=_reserved(position)
			var terrain_id:="TREE" if position in BLOCKED_TILES else "CLEARING"
			result.append({"position":[x,y],"terrain_id":terrain_id,
				"buildable":terrain_id=="CLEARING" and not reserved,"reserved":reserved})
	return result


static func rotated_footprint(type_id:String,rotation:int)->Vector2i:
	return FOOTPRINTS.get(type_id,Vector2i.ZERO) if rotation==0 else Vector2i.ZERO


static func placement_error(type_id:String,tile_origin:Vector2i,rotation:int,
		current:Array,ignore_instance_id:String="")->String:
	if type_id not in BUILDING_TYPES:return "base_building_type_unknown"
	if rotation!=0:return "base_building_rotation_invalid"
	if type_id=="GATE":return "base_gate_fixed"
	var footprint:=rotated_footprint(type_id,rotation)
	var rect:=Rect2i(tile_origin,footprint)
	if tile_origin.x<0 or tile_origin.y<0 or rect.end.x>WIDTH or rect.end.y>HEIGHT:
		return "base_building_out_of_bounds"
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var position:=Vector2i(x,y)
			if position in BLOCKED_TILES:return "base_building_terrain_blocked"
			if _reserved(position):return "base_building_reserved"
	for value in current:
		if not value is Dictionary or str(value.get("instance_id",""))==ignore_instance_id:continue
		var other:Dictionary=value;var origin:Array=other.get("tile_origin",[])
		var size:Array=other.get("footprint",[])
		if origin.size()==2 and size.size()==2 and rect.intersects(Rect2i(
				Vector2i(int(origin[0]),int(origin[1])),Vector2i(int(size[0]),int(size[1])))):
			return "base_building_overlap"
	var proposed:=current.duplicate(true)
	if not ignore_instance_id.is_empty():
		proposed=proposed.filter(func(row):return str(row.get("instance_id",""))!=ignore_instance_id)
	proposed.append({"instance_id":"__PROPOSED__","type_id":type_id,
		"tile_origin":[tile_origin.x,tile_origin.y],"footprint":[footprint.x,footprint.y]})
	if not _access_connected(proposed):return "base_building_blocks_access"
	return ""


static func type_built(rows:Array,type_id:String)->bool:
	for row in rows:
		if row is Dictionary and str(row.get("type_id",""))==type_id:return true
	return false


static func next_instance_id(rows:Array,type_id:String)->String:
	var suffix:=1
	while true:
		var candidate:="BLD_%s_%d"%[type_id,suffix]
		var found:=false
		for row in rows:
			if str(row.get("instance_id",""))==candidate:found=true;break
		if not found:return candidate
		suffix+=1
	return ""


static func _reserved(position:Vector2i)->bool:
	return Rect2i(6,13,3,3).has_point(position) \
		or position.x==7 and position.y>=10 and position.y<=12 \
		or Rect2i(6,6,3,3).has_point(position)


static func _access_connected(rows:Array)->bool:
	var occupied:Dictionary={}
	for row in rows:
		var origin:Array=row.get("tile_origin",[]);var size:Array=row.get("footprint",[])
		if origin.size()!=2 or size.size()!=2:continue
		for y in range(int(origin[1]),int(origin[1])+int(size[1])):
			for x in range(int(origin[0]),int(origin[0])+int(size[0])):
				occupied[Vector2i(x,y)]=true
	var start:=Vector2i(7,12);var visited:Dictionary={start:true};var queue:Array[Vector2i]=[start]
	while not queue.is_empty():
		var current:Vector2i=queue.pop_front()
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next:Vector2i=current+direction
			if next.x<0 or next.y<0 or next.x>=WIDTH or next.y>=HEIGHT \
					or visited.has(next) or occupied.has(next) or next in BLOCKED_TILES:continue
			visited[next]=true;queue.append(next)
	if not visited.has(Vector2i(7,7)):return false
	for row in rows:
		if str(row.get("type_id",""))=="GATE":continue
		var origin:Array=row.tile_origin;var size:Array=row.footprint;var accessible:=false
		var rect:=Rect2i(Vector2i(int(origin[0]),int(origin[1])),Vector2i(int(size[0]),int(size[1])))
		for y in range(rect.position.y-1,rect.end.y+1):
			for x in range(rect.position.x-1,rect.end.x+1):
				if (x==rect.position.x-1 or x==rect.end.x or y==rect.position.y-1 or y==rect.end.y) \
						and visited.has(Vector2i(x,y)):accessible=true
		if not accessible:return false
	return true
