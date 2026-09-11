extends SceneTree

const Core = preload("res://prototype/combat_core.gd")

func _init() -> void:
	var c = Core.new()
	c.actors[0].position = Vector2i(2,2)
	c.walls[Vector2i(3,2)] = true
	assert(c.open_edge(Vector2i(2,2),Vector2i(3,3)))
	assert(c.submit(Vector2i(1,1)).accepted)
	c.actors[0].position = Vector2i(2,2)
	c.walls[Vector2i(2,3)] = true
	var before:Array = c.actors.duplicate(true)
	assert(not c.submit(Vector2i(1,1)).accepted and c.actors == before)
	assert(not c.sees(Vector2i(2,2),Vector2i(3,3)))
	assert(c.sees(Vector2i(2,2),Vector2i(3,2))) # Wall face is visible.
	assert(not c.sees(Vector2i(2,2),Vector2i(4,2)))
	assert(not c.sees(Vector2i(1,1),Vector2i(7,7)))
	for y in range(1,8):
		for x in range(1,8):
			var a := Vector2i(x,y)
			if c.solid(a):continue
			for by in range(1,8):
				for bx in range(1,8):
					var b := Vector2i(bx,by)
					if not c.solid(b):assert(c.sees(a,b) == c.sees(b,a))
	c = Core.new()
	c.refresh_sight()
	var old_memory:Dictionary = c.memory.duplicate()
	c.actors[0].position = Vector2i(1,1)
	c.refresh_sight()
	for cell in old_memory:assert(c.memory.has(cell))
	c.actors[1].position = Vector2i(7,7)
	assert(c.enemy_step(c.actors[1]) == Vector2i.ZERO)
	c = Core.new()
	c.actors[1].position = c.actors[0].position+Vector2i.RIGHT
	c.actors[1].hp = 100
	c.actors[2].hp = 0
	c.actors[0].attack_cost = 140
	c.actors[1].attack_cost = 80
	var result:Dictionary = c.submit(Vector2i.RIGHT)
	assert(result.accepted and c.time == 140)
	assert(c.actors[1].ready_at == 160 and c.actors[0].hp == 16)
	print("Combat core stage 2: PASS (corners, LOS symmetry, radius, memory, detection, action costs)")
	quit()
