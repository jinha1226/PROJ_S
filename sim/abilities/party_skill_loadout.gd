class_name PartySkillLoadout
extends RefCounted

const RULESET_ID := "party-skill-loadout-v1"
const LOADOUTS := {
	"VANGUARD_V1":["STRIKE","SHOVE"],
	"SUPPORT_V1":["FIREBOLT","MEND"],
}

static func skills(loadout_id:String)->Array:
	return LOADOUTS.get(loadout_id,[]).duplicate()

static func has(loadout_id:String)->bool:
	return LOADOUTS.has(loadout_id)
