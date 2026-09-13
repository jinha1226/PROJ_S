extends RefCounted
const Legacy=preload("res://playtest/legacy_base_work_service.gd")
const New=preload("res://playtest/settlement_work_service.gd")
static func commit(session,operation:Dictionary)->Dictionary:
	var error:=preload("res://sim/base_work_rules.gd").operation_error(operation)
	if not error.is_empty():return {"accepted":false,"reason":error}
	return New.commit(session,operation) if int(operation.get("version",1))==2 else Legacy.commit(session,operation)
