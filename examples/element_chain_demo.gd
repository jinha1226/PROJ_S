extends SceneTree

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")


func _init() -> void:
	var sim = Simulator.new(7, 5, 20260827)
	var fire_position := Vector2i(2, 2)
	var target_position := Vector2i(4, 2)
	var goblin = sim.world.add_entity("goblin", "Mok", target_position, 100)
	sim.world.tile_at(fire_position).flammability = 100

	_print_step("Ignite a wooden tile", sim.step(Command.ignite(fire_position, 70)).events)
	_print_step("Extinguish it with water", sim.step(Command.pour_water(fire_position, 70)).events)
	_print_step("Make a conductive path", sim.step(Command.pour_water(Vector2i(3, 2), 60)).events)
	_print_step("Wet the goblin's tile", sim.step(Command.pour_water(target_position, 60)).events)
	_print_step("Discharge electricity", sim.step(Command.discharge(fire_position, 40)).events)

	print("\nFinal state: fire=%d wetness=%d goblin_hp=%d" % [
		sim.world.tile_at(fire_position).fire,
		sim.world.tile_at(fire_position).wetness,
		goblin.health,
	])
	quit()


func _print_step(title: String, events: Array) -> void:
	print("\n== %s ==" % title)
	for event in events:
		print(event.describe())
