extends SceneTree
const G=preload("res://sim/nine_room_generator.gd")
const S=preload("res://sim/nine_room_floor_state.gd")
var failures:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr(label)
func run():
	for seed in range(100):
		for floor in [1,2]:
			var g:=G.generate(seed,floor);check(g.rooms.size()==9,"nine rooms")
			check(g==G.generate(seed,floor),"deterministic "+str(seed))
			var seen:Dictionary={4:true};var todo:Array=[4]
			for a in todo:
				for edge in g.edges:
					var b:int=edge[1] if edge[0]==a else (edge[0] if edge[1]==a else -1)
					if b>=0 and not seen.has(b):seen[b]=true;todo.append(b)
			check(seen.size()==9,"connected")
			check(g.rooms[4].exits.size() in [2,3],"start two or three exits")
			var roles:Dictionary={}
			for room in g.rooms:
				roles[room.role]=roles.get(room.role,0)+1
				var start:=Vector2i(room.bounds[0]+3,room.bounds[1]+3);var visited:Dictionary={start:true};var queue:Array=[start]
				for p in queue:
					for d in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
						var c:Vector2i=p+d
						if c.x<room.bounds[0] or c.y<room.bounds[1] or c.x>=room.bounds[0]+8 or c.y>=room.bounds[1]+8 or visited.has(c) or g.terrain[c.y*24+c.x]=="wall":continue
						visited[c]=true;queue.append(c)
				check(visited.size()>=40,"40 walkable")
				for portal in g.portals:
					if room.room_id not in [portal.a,portal.b]:continue
					var c:Array=portal.a_cell if room.room_id==portal.a else portal.b_cell
					check(visited.has(Vector2i(c[0],c[1])),"portal reachable")
			check(roles=={"SAFE":2,"HAZARD":2,"COMBAT":4,"STAIRS":1},"roles")
			for p in g.portals:
				check(G.neighbors(p.a).has(p.b),"orthogonal edge")
				check((Vector2i(p.b_cell[0],p.b_cell[1])-Vector2i(p.a_cell[0],p.a_cell[1]))==Vector2i(p.direction[0],p.direction[1]),"portal symmetry")
	var world:=G.world_layout(44);var state:=S.create(world)
	check(S.wire_error(state,48,24).is_empty(),"state wire")
	check(S.wire_error(S.normalize(JSON.parse_string(JSON.stringify(state))),48,24).is_empty(),"json wire")
	print("NINE_ROOM_GENERATION ","PASS seeds100 floors2" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
