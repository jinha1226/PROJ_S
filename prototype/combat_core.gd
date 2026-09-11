extends RefCounted

## Standalone turn authority. No scene, campaign, save or rendering dependencies.
const SIZE := Vector2i(9, 9)
const DIRECTIONS := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]
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

func make_actor(id:int, position:Vector2i, hp:int, power:int) -> Dictionary:
	return {"id":id,"position":position,"hp":hp,"power":power,"ready_at":0}

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
		return {"accepted":false,"reason":"adjacent_cardinal_only"}
	if not resolve(actors[0],delta):return {"accepted":false,"reason":"blocked"}
	# All actors use the same absolute action clock. Input pauses at hero readiness.
	while terminal().is_empty():
		var next:Dictionary = actors[0]
		for actor in actors:
			if actor.hp > 0 and (actor.ready_at < next.ready_at or
				actor.ready_at == next.ready_at and actor.id < next.id):next = actor
		time = int(next.ready_at)
		if next.id == 1:break
		resolve(next,enemy_step(next))
	return {"accepted":true,"events":events.duplicate(true),"time":time,"terminal":terminal()}

func resolve(actor:Dictionary, delta:Vector2i) -> bool:
	var target_cell:Vector2i = actor.position + delta
	if delta != Vector2i.ZERO:
		if not Rect2i(Vector2i.ZERO,SIZE).has_point(target_cell) or walls.has(target_cell):return false
		var target := actor_at(target_cell)
		if not target.is_empty():
			if (actor.id == 1) == (target.id == 1):return false
			target.hp = maxi(0,int(target.hp)-int(actor.power))
			events.append({"kind":"hit","actor":actor.id,"target":target.id,"amount":actor.power})
			if target.hp == 0:events.append({"kind":"death","actor":target.id})
		else:
			actor.position = target_cell
			events.append({"kind":"move","actor":actor.id})
	else:events.append({"kind":"wait","actor":actor.id})
	actor.ready_at = time + 100
	return true

func enemy_step(actor:Dictionary) -> Vector2i:
	# Bounded BFS on this tiny board; living allies block movement.
	var start:Vector2i = actor.position
	var queue:Array[Vector2i] = [start]
	var first:Dictionary = {start:Vector2i.ZERO}
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for direction in DIRECTIONS:
			var next:Vector2i = cell + direction
			if not Rect2i(Vector2i.ZERO,SIZE).has_point(next) or walls.has(next) or first.has(next):continue
			var occupant := actor_at(next)
			if not occupant.is_empty() and occupant.id != 1:continue
			first[next] = direction if cell == start else first[cell]
			if next == actors[0].position:return first[next]
			queue.append(next)
	return Vector2i.ZERO
