class_name ActiveSkillRegistry
extends RefCounted

## Initial balance hypotheses, not production progression values.
const RULESET_ID:="active-combat-prototype-v1"
const MAX_ENERGY:=12
const SKILLS:={
	"FIREBALL":{"name":"화염구(시험)","cost":3,"range":5,"target":"TILE","effect":"HEAT","power":1400,"element":"FIRE"},
	"STRIKE":{"name":"강타","cost":3,"range":1,"target":"ENEMY","effect":"DAMAGE","power":30,"element":"PHYSICAL"},
	"FIREBOLT":{"name":"화염탄","cost":3,"range":5,"target":"ENEMY","effect":"DAMAGE","power":32,"element":"FIRE"},
	"BARRIER":{"name":"보호막","cost":4,"range":4,"target":"ALLY","effect":"BARRIER","power":28,"element":"NONE"},
	"MEND":{"name":"응급 치유","cost":4,"range":4,"target":"ALLY","effect":"HEAL","power":24,"element":"NONE"},
	"SHOVE":{"name":"밀치기","cost":3,"range":1,"target":"ENEMY","effect":"SHOVE","power":8,"element":"PHYSICAL"},
}

static func definition(id:String)->Dictionary:
	return SKILLS.get(id,{}).duplicate(true)

static func error()->String:
	for id in SKILLS:
		var row:Dictionary=SKILLS[id]
		if int(row.cost)<=0 or int(row.cost)>MAX_ENERGY or int(row.range)<1 \
				or int(row.power)<0:return "invalid_active_skill_"+id
	return ""
