class_name BodyFunctionRules
extends RefCounted

const RULESET_ID:="body-function-b1-v1"
const ARM_IDS:=["LEFT_ARM","RIGHT_ARM"]
const LEG_IDS:=["LEFT_LEG","RIGHT_LEG"]


static func appraisal(body)->Dictionary:
	if body==null or not body.has_method("validation_error") \
			or not body.validation_error().is_empty():return {}
	var usable_arms:=_usable_count(body,ARM_IDS)
	var usable_legs:=_usable_count(body,LEG_IDS)
	return {"ruleset_id":RULESET_ID,"usable_arm_count":usable_arms,
		"usable_leg_count":usable_legs,"one_handed_available":usable_arms>=1,
		"two_handed_available":usable_arms>=2,"off_hand_available":usable_arms>=2,
		"locomotion_mode":"NORMAL" if usable_legs==2 else (
			"HINDERED" if usable_legs==1 else "CRAWLING")}.duplicate(true)


static func weapon_use_error(body,weapon)->String:
	var dto:=appraisal(body)
	if dto.is_empty():return "invalid_body_state"
	if weapon==null or not weapon.has_method("validation_error") \
			or not weapon.validation_error().is_empty():
		return "invalid_weapon_definition"
	# Generic unarmed combat includes kicks, bites and body checks and therefore
	# remains a last-resort action after both arms are lost. A species claw still
	# requires at least one usable arm.
	if bool(weapon.natural_weapon):
		if str(weapon.weapon_id)=="NATURAL_CLAW" \
				and not bool(dto.one_handed_available):
			return "natural_weapon_limb_unavailable"
		return ""
	if bool(weapon.two_handed) and not bool(dto.two_handed_available):
		return "two_handed_limb_unavailable"
	if not bool(dto.one_handed_available):return "weapon_limb_unavailable"
	return ""


static func _usable_count(body,part_ids:Array)->int:
	var result:=0
	for part_id in part_ids:
		if body.part_condition(str(part_id))=="FUNCTIONAL":result+=1
	return result
