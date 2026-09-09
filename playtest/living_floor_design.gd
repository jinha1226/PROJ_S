extends RefCounted
## Authored discovery pocket on each floor, before the existing large branches.
const CARDINAL_DIRECTIONS=[Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
const Terrain=preload("res://sim/terrain_registry.gd")
static func apply(source:Dictionary,floor_index:int)->Dictionary:
	var out:Dictionary=source.duplicate(true)
	var width:int=out.width;var height:int=out.height
	var terrain:Array=out.terrain;var entry:Vector2i=out.entry_position
	var floor_material:="floor" if floor_index==1 else "rubble"
	for y in range(entry.y-13,entry.y+14):
		for x in range(2,34):
			if x<=0 or y<=0 or x>=width-1 or y>=height-1:continue
			terrain[y*width+x]=floor_material
	# A visible creek/drain splits the pocket; two crossings form a loop.
	for y in range(entry.y-12,entry.y+13):
		for x in range(17,20):terrain[y*width+x]="shallow_water"
	for y in [entry.y,entry.y+8]:
		for x in range(14,23):terrain[y*width+x]="wood_floor" if floor_index==1 else "metal"
	# Broken, accessible courtyard. Wall shapes have readable entrances.
	for y in range(entry.y-12,entry.y-3):
		for x in range(24,33):
			terrain[y*width+x]="stone_floor" if floor_index==1 else "metal"
			if (x in [24,32] or y in [entry.y-12,entry.y-4]) and x not in [27,28,29]:terrain[y*width+x]="wall"
	var camp:=entry+Vector2i(5,3);var relic:=Vector2i(28,entry.y-8)
	for center in [entry,camp,relic,out.anchor_portal_position,out.transition_portal_position]:
		for dy in range(-1,2):
			for dx in range(-1,2):
				var p:Vector2i=center+Vector2i(dx,dy)
				if p.x>0 and p.y>0 and p.x<width-1 and p.y<height-1:terrain[p.y*width+p.x]="stone_floor"
	out.terrain=terrain;out.ruleset_id="living-floor-discovery-v2"
	out["landmarks"]=[{"kind":"CAMP","label":"모험가 야영지","position":camp},
		{"kind":"RELIC","label":"잠든 중계석" if floor_index==1 else "냉각로 핵","position":relic},
		{"kind":"WELL","label":"오래된 우물" if floor_index==1 else "폐환기구","position":entry+Vector2i(8,9)}]
	out["visitor_positions"]=[camp+Vector2i(0,1),entry+Vector2i(13,0),entry+Vector2i(8,7)]
	return out

static func connectivity_error(layout:Dictionary)->String:
	var width:=int(layout.get("width",0));var height:=int(layout.get("height",0))
	var terrain:Array=layout.get("terrain",[])
	if width<=0 or height<=0 or terrain.size()!=width*height:return "invalid_layout"
	var entry:Variant=layout.get("entry_position")
	if not entry is Vector2i:return "entry_missing"
	var queue:Array[Vector2i]=[entry];var seen:Dictionary={entry:true}
	while not queue.is_empty():
		var current:Vector2i=queue.pop_front()
		for direction in CARDINAL_DIRECTIONS:
			var next:Vector2i=current+direction
			if next.x<0 or next.y<0 or next.x>=width or next.y>=height or seen.has(next):continue
			if not Terrain.definition(str(terrain[next.y*width+next.x])).get("passable",false):continue
			seen[next]=true;queue.append(next)
	var required:Array=[layout.get("exit_position"),layout.get("anchor_portal_position"),
		layout.get("transition_portal_position")]
	required.append_array(layout.get("supply_positions",[]))
	required.append_array(layout.get("visitor_positions",[]))
	for row in layout.get("landmarks",[]):
		if row is Dictionary:required.append(row.get("position"))
	for value in required:
		if not value is Vector2i or not seen.has(value):return "required_cell_unreachable"
	return ""
