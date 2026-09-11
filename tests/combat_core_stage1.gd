extends SceneTree

const Core = preload("res://prototype/combat_core.gd")

func _init() -> void:
	var core = Core.new()
	var before:Array = core.actors.duplicate(true)
	assert(not core.submit(Vector2i(3,0)).accepted)
	assert(core.actors == before and core.time == 0)
	core.walls[core.actors[0].position+Vector2i.LEFT] = true
	assert(not core.submit(Vector2i.LEFT).accepted)
	assert(core.actors == before and core.time == 0)
	core.actors[1].position = core.actors[0].position+Vector2i.RIGHT
	core.actors[1].hp = 5
	var result:Dictionary = core.submit(Vector2i.RIGHT)
	assert(result.accepted and core.actors[1].hp == 0)
	assert(core.actors[0].hp == 20) # Killed enemy gets no retaliation.
	assert(core.actor_at(core.actors[1].position).is_empty())
	assert(core.time == 100 and core.actors[2].ready_at == 100)
	var a = Core.new()
	var b = Core.new()
	for step in range(30):
		assert(a.submit(Vector2i.ZERO) == b.submit(Vector2i.ZERO))
		assert(a.actors == b.actors)
	assert(a.terminal() == "DEFEAT")
	before = a.actors.duplicate(true)
	assert(not a.submit(Vector2i.ZERO).accepted and a.actors == before)
	print("Combat core stage 1: PASS (blocked input, clock, immediate death, replay, terminal)")
	quit()
