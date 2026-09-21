extends RefCounted
## Interior obstacles affect authoritative movement and line of sight. The
## three-cell-wide route network and encounter/recruit/supply cells stay open.
static func apply(terrain:Array[String],width:int,rooms:Array,routes:Array,protected_centers:Array,seed:int)->Array[Vector2i]:
	var protected:Dictionary={}
	for route in routes:
		for i in range(1,route.points.size()):
			var p:Vector2i=route.points[i-1];var end:Vector2i=route.points[i]
			while true:
				protect(protected,p,1)
				if p==end:break
				p+=Vector2i(signi(end.x-p.x),signi(end.y-p.y))
	for p in protected_centers:protect(protected,p,2)
	var placed:Array[Vector2i]=[]
	for i in range(rooms.size()):
		var room:Rect2i=rooms[i]
		for y in range(room.position.y+3,room.end.y-2,5):
			for x in range(room.position.x+3,room.end.x-2,5):
				var p:=Vector2i(x,y)
				if protected.has(p):continue
				terrain[y*width+x]="wall";placed.append(p)
				# A short broken wall rather than a completely closing partition.
				var extra:=p+Vector2i.RIGHT
				if posmod(x*13+y*7+seed,3)==0 and not protected.has(extra):
					terrain[extra.y*width+extra.x]="wall";placed.append(extra)
				for d in [Vector2i.DOWN,Vector2i.LEFT]:
					var edge:Vector2i=p+d
					if not protected.has(edge):terrain[edge.y*width+edge.x]="rubble"
		# One coherent flooded pocket, with the protected stone route as causeway.
		if i==2:
			for y in range(room.position.y+2,room.position.y+7):
				for x in range(room.position.x+2,room.position.x+7):
					var p:=Vector2i(x,y)
					if not protected.has(p) and terrain[y*width+x]!="wall":terrain[y*width+x]="shallow_water"
	return placed

static func protect(cells:Dictionary,center:Vector2i,radius:int)->void:
	for y in range(center.y-radius,center.y+radius+1):
		for x in range(center.x-radius,center.x+radius+1):cells[Vector2i(x,y)]=true
