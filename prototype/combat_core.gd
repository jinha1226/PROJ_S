extends RefCounted

## Standalone turn authority. No scene, campaign, save or rendering dependencies.
const SIZE := Vector2i(9, 9)
const Kernel=preload("res://sim/combat_kernel.gd")
const DIRECTIONS = Kernel.DIRECTIONS
const SIGHT_RADIUS = Kernel.SIGHT_RADIUS
var visible:Dictionary = {}
var memory:Dictionary = {}
var walls: Dictionary = {}
var actors: Array[Dictionary] = []
var time := 0
var events: Array[Dictionary] = []

func _init() -> void:
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if x == 0 or y == 0 or x == SIZE.x-1 or y == SIZE.y-1:
				walls[Vector2i(x,y)] = true
	walls[Vector2i(4,4)] = true
	actors = [make_actor(1,Vector2i(2,6),20,5), make_actor(2,Vector2i(6,2),10,2),
		make_actor(3,Vector2i(6,6),10,2)]
	refresh_sight()

func make_actor(id:int, position:Vector2i, hp:int, power:int) -> Dictionary:
	return {"id":id,"position":position,"hp":hp,"power":power,"ready_at":0,
		"move_cost":100,"attack_cost":100,"wait_cost":100}

func solid(cell:Vector2i) -> bool:
	return not Rect2i(Vector2i.ZERO,SIZE).has_point(cell) or walls.has(cell)

func open_edge(origin:Vector2i, target:Vector2i) -> bool:
	return Kernel.open_edge(origin,target,solid)

func sees(origin:Vector2i, target:Vector2i) -> bool:
	if not Rect2i(Vector2i.ZERO,SIZE).has_point(target):return false
	return Kernel.sees(origin,target,solid)

func refresh_sight() -> void:
	visible.clear()
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var cell := Vector2i(x,y)
			if sees(actors[0].position,cell):
				visible[cell] = true
				memory[cell] = walls.has(cell)

func actor_at(position:Vector2i) -> Dictionary:
	for actor in actors:
		if actor.hp > 0 and actor.position == position:return actor
	return {}

func terminal() -> String:
	if actors[0].hp <= 0:return "DEFEAT"
	for actor in actors.slice(1):
		if actor.hp > 0:return ""
	return "VICTORY"

func submit(delta:Vector2i) -> Dictionary:
	events = []
	if not terminal().is_empty():return {"accepted":false,"reason":"finished"}
	if delta != Vector2i.ZERO and delta not in DIRECTIONS:
		return {"accepted":false,"reason":"adjacent_only"}
	if not resolve(actors[0],delta):return {"accepted":false,"reason":"blocked"}
	# All actors use the same absolute action clock. Input pauses at hero readiness.
	var completed:=Kernel.advance(int(actors[0].ready_at),_next_actor,_dispatch_actor)
	assert(completed,"Combat timeline failed to advance")
	if terminal().is_empty():time=int(actors[0].ready_at)
	refresh_sight()
	return {"accepted":true,"events":events.duplicate(true),"time":time,"terminal":terminal()}

func _next_actor(end:int)->Dictionary:
	var best:Dictionary={}
	if not terminal().is_empty():return best
	for actor in actors.slice(1):
		if actor.hp>0:best=Kernel.earlier(best,int(actor.ready_at),int(actor.id),end)
	return best

func _dispatch_actor(next:Dictionary)->bool:
	time=int(next.at)
	for actor in actors:
		if actor.id==next.id:return resolve(actor,enemy_step(actor))
	return false

func resolve(actor:Dictionary, delta:Vector2i) -> bool:
	var target_cell:Vector2i = actor.position + delta
	var cost := int(actor.wait_cost)
	if delta != Vector2i.ZERO:
		if solid(target_cell) or not open_edge(actor.position,target_cell):return false
		var target := actor_at(target_cell)
		if not target.is_empty():
			if (actor.id == 1) == (target.id == 1):return false
			cost = int(actor.attack_cost)
			target.hp = maxi(0,int(target.hp)-int(actor.power))
			events.append({"kind":"hit","actor":actor.id,"target":target.id,"amount":actor.power})
			if target.hp == 0:events.append({"kind":"death","actor":target.id})
		else:
			cost = int(actor.move_cost)
			actor.position = target_cell
			events.append({"kind":"move","actor":actor.id})
	else:events.append({"kind":"wait","actor":actor.id})
	actor.ready_at = time + maxi(1,cost)
	return true

func enemy_step(actor:Dictionary) -> Vector2i:
	# Bounded BFS on this tiny board; living allies block movement.
	var start:Vector2i = actor.position
	if not sees(start,actors[0].position):return Vector2i.ZERO
	var queue:Array[Vector2i] = [start]
	var first:Dictionary = {start:Vector2i.ZERO}
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for direction in DIRECTIONS:
			var next:Vector2i = cell + direction
			if solid(next) or not open_edge(cell,next) or first.has(next):continue
			var occupant := actor_at(next)
			if not occupant.is_empty() and occupant.id != 1:continue
			first[next] = direction if cell == start else first[cell]
			if next == actors[0].position:return first[next]
			queue.append(next)
	return Vector2i.ZERO
