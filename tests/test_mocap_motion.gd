class_name MocapMotionTests
extends RefCounted

const CLIP_PATH := "res://assets/mocap/cmu/02_07_swordplay_game.json"


func run() -> Array[String]:
	var failures: Array[String] = []
	var file := FileAccess.open(CLIP_PATH, FileAccess.READ)
	if file == null:
		return ["mocap clip JSON should exist"]
	var payload: Variant = JSON.parse_string(file.get_as_text())
	if not payload is Dictionary:
		return ["mocap clip JSON should parse as a dictionary"]
	var joints: Array = payload.get("joints", [])
	var bones: Array = payload.get("bones", [])
	var frames: Array = payload.get("frames", [])
	if int(payload.get("fps", 0)) != 30:
		failures.append("mocap clip should be baked at 30 fps")
	if frames.size() < 60:
		failures.append("mocap clip should contain at least two seconds of motion")
	if joints.size() < 20:
		failures.append("mocap clip should contain a full humanoid joint set")
	if not joints.has("sword_tip"):
		failures.append("mocap clip should include a weapon endpoint")
	for spec_value in bones:
		var spec: Dictionary = spec_value
		if not joints.has(spec.get("a", "")) or not joints.has(spec.get("b", "")):
			failures.append("every mocap bone should reference valid joints")
			break
	if not frames.is_empty():
		var first_frame: Array = frames[0]
		var middle_frame: Array = frames[frames.size() / 2]
		if first_frame.size() != joints.size():
			failures.append("every frame should provide one point per joint")
		var sword_index := joints.find("sword_tip")
		var start_tip := _vec3(first_frame[sword_index])
		var middle_tip := _vec3(middle_frame[sword_index])
		if start_tip.distance_to(middle_tip) < 0.25:
			failures.append("weapon endpoint should travel enough to read as an attack")
	return failures


func _vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
