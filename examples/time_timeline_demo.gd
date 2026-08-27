extends SceneTree

const Simulator = preload("res://sim/simulator.gd")
const Command = preload("res://sim/sim_command.gd")


func _init() -> void:
	var sim = Simulator.new(2, 1, 20260827)

	var water_command = Command.pour_water(Vector2i.ZERO, 20)
	var water_preview = sim.preview(water_command)
	print("@%d POUR_WATER preview: %s, cost %d" % [
		water_preview.start_time, water_preview.speed_tier, water_preview.time_cost])
	print("timeline: %s" % _timeline_text(water_preview.timeline))
	var water_result = sim.step(water_command)
	print("planned markers == actual markers: %s" % str(
		_marker_signature(water_preview.timeline) == _marker_signature(water_result.timeline)))

	var discharge_command = Command.discharge(Vector2i.ZERO, 40)
	var discharge_preview = sim.preview(discharge_command)
	print("\n@%d DISCHARGE preview: %s, cost %d" % [
		discharge_preview.start_time, discharge_preview.speed_tier, discharge_preview.time_cost])
	print("timeline: %s" % _timeline_text(discharge_preview.timeline))
	var discharge_result = sim.step(discharge_command)
	print("planned markers == actual markers: %s" % str(
		_marker_signature(discharge_preview.timeline) == _marker_signature(discharge_result.timeline)))
	print("final: step_index=%d world_time=%d next_environment=%d" % [
		sim.world.step_index, sim.world.world_time,
		sim.world.scheduled_entries[0]["due_time"]])
	quit()


func _timeline_text(timeline: Array) -> String:
	var pieces: PackedStringArray = []
	for marker in timeline:
		var label := "action" if marker["kind"] == "action.start" else (
			"environment" if marker["kind"] == "system.environment_tick" else "ready")
		pieces.append("%s@%d" % [label, marker["at_time"]])
	return " -> ".join(pieces)


func _marker_signature(timeline: Array) -> Array:
	var result: Array = []
	for marker in timeline:
		result.append([marker["kind"], marker["at_time"], marker["schedule_id"]])
	return result
