extends SceneTree

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")


func _init() -> void:
	var human_sim = _make_lane("human", 20260827)
	var human_id: int = human_sim.world.entities.keys()[0]
	var human_destination = human_sim.assess_destination(human_id, Vector2i(2, 0))
	print("human shallow_water: water_score=%d total=%d" % [
		human_destination.evaluation.water_score,
		human_destination.evaluation.total_risk])

	var amphibian_sim = _make_lane("amphibian", 20260827)
	var amphibian_id: int = amphibian_sim.world.entities.keys()[0]
	var amphibian_destination = amphibian_sim.assess_destination(
		amphibian_id, Vector2i(2, 0))
	print("amphibian shallow_water: water_score=%d total=%d" % [
		amphibian_destination.evaluation.water_score,
		amphibian_destination.evaluation.total_risk])

	var floor_move = human_sim.step(Command.move_to(human_id, Vector2i(1, 0)))
	print("move floor @%d→%d" % [floor_move.start_time, floor_move.end_time])
	var water_move = human_sim.step(Command.move_to(human_id, Vector2i(2, 0)))
	print("move shallow_water @%d→%d" % [water_move.start_time, water_move.end_time])
	var encoded := JSON.stringify(human_sim.snapshot())
	var restored = Simulator.from_snapshot(JSON.parse_string(encoded))
	print("snapshot restore: exact=%s" % str(
		restored != null and restored.snapshot() == human_sim.snapshot()).to_lower())
	quit(0)


func _make_lane(species_id: String, seed: int):
	var sim = Simulator.new(3, 1, seed)
	sim.world.bootstrap_set_terrain(Vector2i(1, 0), "floor")
	sim.world.bootstrap_set_terrain(Vector2i(2, 0), "shallow_water")
	sim.world.add_entity(
		species_id, species_id.capitalize(), Vector2i.ZERO, 100, [], species_id)
	return sim
