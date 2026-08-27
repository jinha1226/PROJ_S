class_name SimTestCase
extends RefCounted

var errors: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func check_eq(got: Variant, expected: Variant, label: String = "") -> void:
	if got != expected:
		errors.append("%s: expected %s, got %s" % [label, str(expected), str(got)])


func find_event(events: Array, type: String):
	for event in events:
		if event.type == type:
			return event
	return null


func count_events(events: Array, type: String) -> int:
	var count := 0
	for event in events:
		if event.type == type:
			count += 1
	return count


func finish() -> bool:
	return errors.is_empty()
