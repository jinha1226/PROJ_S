class_name PartyExceptionCommand
extends RefCounted

const Int64CodecScript = preload("res://sim/int64_codec.gd")

const RULESET_ID := "party-exception-command-v1"
const COMMAND_IDS := ["ATTACK_TARGET", "RETREAT", "STOP_ATTACK",
	"HOLD_POSITION", "FOLLOW"]


static func event_data(command_id: String, target_id: int) -> Dictionary:
	return {
		"schema_version": 1,
		"ruleset_id": RULESET_ID,
		"command_id": command_id,
		"target_id": str(target_id),
	}

static func actor_event_data(actor_id:int,command_id:String,target_id:int)->Dictionary:
	var row:=event_data(command_id,target_id)
	row["schema_version"]=2
	row["actor_id"]=str(actor_id)
	return row

static func actor_data_error(value:Variant)->String:
	if not value is Dictionary:return "invalid_actor_command_data"
	var keys:Array=value.keys();keys.sort()
	if keys!=["actor_id","command_id","ruleset_id","schema_version","target_id"] \
			or value.get("schema_version")!=2 or value.get("ruleset_id")!=RULESET_ID \
			or value.get("command_id") not in COMMAND_IDS \
			or not Int64CodecScript.is_canonical(value.get("actor_id")) \
			or Int64CodecScript.parse(value.actor_id,"actor directive")<=0 \
			or not Int64CodecScript.is_canonical(value.get("target_id")):
		return "invalid_actor_command_data"
	var target_id:=Int64CodecScript.parse(value.target_id,"actor directive target")
	if (str(value.command_id)=="ATTACK_TARGET" and target_id<=0) \
			or (str(value.command_id)!="ATTACK_TARGET" and target_id!=-1):
		return "invalid_actor_command_target"
	return ""


static func data_error(value: Variant) -> String:
	if not value is Dictionary:
		return "invalid_party_command_data"
	var keys: Array = value.keys(); keys.sort()
	if keys != ["command_id", "ruleset_id", "schema_version", "target_id"] \
			or value.get("schema_version") != 1 \
			or value.get("ruleset_id") != RULESET_ID \
			or value.get("command_id") not in COMMAND_IDS \
			or not Int64CodecScript.is_canonical(value.get("target_id")):
		return "invalid_party_command_data"
	var target_id := Int64CodecScript.parse(value.target_id, "party command target")
	if (str(value.command_id) == "ATTACK_TARGET" and target_id <= 0) \
			or (str(value.command_id) != "ATTACK_TARGET" and target_id != -1):
		return "invalid_party_command_target"
	return ""


static func effective(world, state) -> Dictionary:
	var fallback := {
		"command_id": "FOLLOW",
		"target_id": -1,
		"anchor": [world.entities[world.party_control_actor_id()].position.x,
			world.entities[world.party_control_actor_id()].position.y],
		"explicit": false,
		"event_id": -1,
	}
	var commands:Array=preload("res://sim/runtime_history_index.gd").sync(world).commands
	for event_index in range(commands.size() - 1, -1, -1):
		var event = commands[event_index]
		if event.type in ["party.regroup_completed","party.disengage_completed",
				"dungeon.expedition_returned","party.expedition_auto_returned"]:
			break
		if event.type != "party.command_issued" \
				or not data_error(event.data).is_empty():
			continue
		var command_id := str(event.data.command_id)
		var target_id := Int64CodecScript.parse(event.data.target_id,
			"party command target")
		if command_id == "ATTACK_TARGET" \
				and (not world.entities.has(target_id) \
				or not world.is_autonomous_target(target_id)):
			return fallback
		return {
			"command_id": command_id,
			"target_id": target_id,
			"anchor": [event.position.x, event.position.y],
			"explicit": true,
			"event_id": int(event.id),
		}
	return fallback

static func effective_for_actor(world,state,actor_id:int)->Dictionary:
	var fallback := {"actor_id":actor_id,"command_id":"FOLLOW","target_id":-1,
		"anchor":[world.entities[actor_id].position.x,world.entities[actor_id].position.y],
		"explicit":false,"event_id":-1}
	if state.expedition_cycle!=null and str(state.expedition_cycle.phase)=="TOWN":
		return fallback
	var commands:Array=preload("res://sim/runtime_history_index.gd").sync(world).commands
	for event_index in range(commands.size()-1,-1,-1):
		var event=commands[event_index]
		if event.type in ["party.regroup_completed","party.disengage_completed",
				"dungeon.expedition_returned","party.expedition_auto_returned"]:
			break
		if event.type=="party.command_issued" and data_error(event.data).is_empty():
			if preload("res://sim/field_turn_rules.gd").enabled(world) and actor_id==world.party_control_actor_id():
				continue
			var global_target:=Int64CodecScript.parse(event.data.target_id,
				"party command target")
			if str(event.data.command_id)=="ATTACK_TARGET" and (
					not world.entities.has(global_target) \
					or not world.is_autonomous_target(global_target)):
				return fallback
			return {"actor_id":actor_id,"command_id":str(event.data.command_id),
				"target_id":global_target,"anchor":[event.position.x,event.position.y],
				"explicit":true,"event_id":int(event.id)}
		if event.type!="party.actor_command_issued":continue
		var data:Dictionary=event.data
		if not actor_data_error(data).is_empty() \
				or Int64CodecScript.parse(data.actor_id,"actor directive")!=actor_id:
			continue
		var target_id:=Int64CodecScript.parse(data.target_id,"actor directive target")
		if str(data.command_id)=="ATTACK_TARGET" and (not world.entities.has(target_id) \
				or not world.is_autonomous_target(target_id)):
			return fallback
		return {"actor_id":actor_id,"command_id":str(data.command_id),
			"target_id":target_id,"anchor":[event.position.x,event.position.y],
			"explicit":true,"event_id":int(event.id)}
	return fallback


static func label_ko(command_id: String) -> String:
	return {
		"ATTACK_TARGET": "공격 대상 지정",
		"RETREAT": "후퇴",
		"STOP_ATTACK": "공격 중지",
		"HOLD_POSITION": "자리 지키기",
		"FOLLOW": "따라오기",
	}.get(command_id, command_id)
