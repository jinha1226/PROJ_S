class_name CommandResult
extends RefCounted

var ok: bool = false
var code: StringName = &"UNKNOWN"
var payload: Dictionary = {}


static func success(result_payload: Dictionary = {}) -> CommandResult:
	var result := CommandResult.new()
	result.ok = true
	result.code = &"OK"
	result.payload = result_payload.duplicate(true)
	return result


static func failure(error_code: StringName, result_payload: Dictionary = {}) -> CommandResult:
	var result := CommandResult.new()
	result.ok = false
	result.code = error_code
	result.payload = result_payload.duplicate(true)
	return result
