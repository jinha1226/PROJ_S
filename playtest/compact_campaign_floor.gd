extends RefCounted
## Scale authored geography, not camera zoom or loaded world topology.
static func reduce(source:Dictionary)->Dictionary:
	var out:Dictionary=geometry(source)
	var width:int=int(source.width)/2;var height:int=int(source.height)/2
	out.width=width;out.height=height;out.ruleset_id="campaign-floor-regions-compact-v2"
	out.anchor_portal_clear_radius=4
	var terrain:Array[String]=[];terrain.resize(width*height)
	for y in range(height):
		for x in range(width):terrain[y*width+x]=str(source.terrain[(y*2)*int(source.width)+x*2])
	# Restore walkable authored routes after sampling; one-tile margins prevent
	# diagonal corner blockage and preserve branch connectivity.
	for route in out.routes:
		for index in range(1,route.points.size()):
			var a:Vector2i=route.points[index-1];var b:Vector2i=route.points[index]
			var steps:int=maxi(absi(b.x-a.x),absi(b.y-a.y))
			for step in range(steps+1):
				var p:Vector2i=Vector2i(Vector2(a).lerp(Vector2(b),float(step)/maxi(1,steps)).round())
				clear(terrain,width,height,p,1)
	for key in ["entry_position","anchor_portal_position","transition_portal_position"]:clear(terrain,width,height,out[key],2)
	for p in out.supply_positions:clear(terrain,width,height,p,1)
	var accessible:Dictionary=flood(terrain,width,height,out.entry_position)
	for p in out.supply_positions:
		if accessible.has(p):continue
		var nearest:Vector2i=out.entry_position;var best:int=2147483647
		for cell in accessible:
			var distance:int=absi(cell.x-p.x)+absi(cell.y-p.y)
			if distance<best:best=distance;nearest=cell
		var cursor:Vector2i=p
		while cursor!=nearest:
			clear(terrain,width,height,cursor,1)
			if cursor.x!=nearest.x:cursor.x+=signi(nearest.x-cursor.x)
			else:cursor.y+=signi(nearest.y-cursor.y)
		accessible=flood(terrain,width,height,out.entry_position)
	var occupied:Dictionary={out.entry_position:true,out.anchor_portal_position:true,out.transition_portal_position:true}
	var roster:Array[Dictionary]=[]
	for group in out.encounter_groups:
		var center:=Vector2i(int(group.position[0]),int(group.position[1]))
		clear(terrain,width,height,center,2)
		for species in group.species_ids:
			var found:=false
			for radius in range(5):
				for y in range(-radius,radius+1):
					for x in range(-radius,radius+1):
						var p:=center+Vector2i(x,y)
						if occupied.has(p) or p.x<1 or p.y<1 or p.x>=width-1 or p.y>=height-1:continue
						if terrain[p.y*width+p.x]=="wall":continue
						occupied[p]=true;roster.append({"position":p,"species_id":str(species),"group_id":group.group_id,"route_id":group.route_id});found=true;break
					if found:break
				if found:break
			if not found:return {}
	for x in range(width):terrain[x]="wall";terrain[(height-1)*width+x]="wall"
	for y in range(height):terrain[y*width]="wall";terrain[y*width+width-1]="wall"
	out.terrain=terrain;out.runtime_enemy_roster=roster;out.enemy_roster=roster.duplicate(true)
	out.enemy_positions=roster.map(func(row):return row.position)
	# Rebuild material positions from actual sampled terrain, not stale coordinates.
	for key in out.material_positions:out.material_positions[key]=[]
	for y in range(height):
		for x in range(width):
			var material:String=terrain[y*width+x]
			if out.material_positions.has(material):out.material_positions[material].append(Vector2i(x,y))
	return out

static func geometry(value:Variant,key:String="")->Variant:
	if value is Vector2i:return Vector2i(value.x/2,value.y/2)
	if value is Rect2i:return Rect2i(value.position/2,Vector2i(maxi(1,value.size.x/2),maxi(1,value.size.y/2)))
	if value is Dictionary:
		var result:Dictionary={}
		for child in value:result[child]=geometry(value[child],str(child))
		return result
	if value is Array:
		var result:Array=[]
		if key in ["position","bounds"]:
			for number in value:result.append(int(number)/2)
		else:
			for child in value:result.append(geometry(child))
		return result
	return value

static func clear(terrain:Array[String],width:int,height:int,center:Vector2i,radius:int)->void:
	for y in range(center.y-radius,center.y+radius+1):
		for x in range(center.x-radius,center.x+radius+1):
			if x>0 and y>0 and x<width-1 and y<height-1:terrain[y*width+x]="stone_floor"

static func flood(terrain:Array[String],width:int,height:int,start:Vector2i)->Dictionary:
	var queue:Array=[start];var seen:Dictionary={start:true};var cursor:int=0
	while cursor<queue.size():
		var p:Vector2i=queue[cursor];cursor+=1
		for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var n:Vector2i=p+d
			if n.x<0 or n.y<0 or n.x>=width or n.y>=height or seen.has(n):continue
			if terrain[n.y*width+n.x]=="wall":continue
			seen[n]=true;queue.append(n)
	return seen
