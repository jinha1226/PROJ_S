class_name ProgressionRegistry
extends RefCounted

const RULESET_ID := "solo-progression-v1"
const SCHEMA_VERSION := 1
const VICTORY_XP := 100
const FOCUS_TOTAL := 100
const SKILL_IDS := ["MELEE", "GUARD", "EXPLORATION"]
const DEFAULT_FOCUS := {"MELEE":50, "GUARD":30, "EXPLORATION":20}
const MAX_XP := 1000000
const MAX_RANK := 20

const DEFINITIONS := {
	"MELEE":{"label":"근접 전투", "description":"근접 공격의 피해를 안정적으로 높입니다.",
		"effect_id":"MELEE_POWER", "milestone_rank":3,
		"milestone_label":"능동 전투 기술 (후속 개발)"},
	"GUARD":{"label":"방어술", "description":"방어 행동을 다루는 기반 숙련입니다.",
		"effect_id":"HOLD_GUARD_RATE", "milestone_rank":3,
		"milestone_label":"반격 태세 (후속 개발)"},
	"EXPLORATION":{"label":"탐험술", "description":"이동과 위험 대응을 위한 기반 숙련입니다.",
		"effect_id":"FUTURE_EXPLORATION", "milestone_rank":3,
		"milestone_label":"노련한 발걸음 (후속 개발)"},
}

static func definition(skill_id:String)->Dictionary:
	return DEFINITIONS[skill_id].duplicate(true) if skill_id in SKILL_IDS else {}

static func focus_preset(skill_id:String)->Dictionary:
	if skill_id not in SKILL_IDS:return {}
	var result:={}
	for id in SKILL_IDS:result[id]=60 if id==skill_id else 20
	return result

static func focus_error(focus:Variant)->String:
	if not focus is Dictionary:return "invalid_progression_focus_shape"
	var keys:Array=focus.keys();keys.sort()
	var expected:Array=SKILL_IDS.duplicate();expected.sort()
	if keys!=expected:return "invalid_progression_focus_keys"
	var total:=0
	for skill_id in SKILL_IDS:
		if not focus[skill_id] is int or int(focus[skill_id])<0 \
				or int(focus[skill_id])>FOCUS_TOTAL:return "invalid_progression_focus_value"
		total+=int(focus[skill_id])
	return "" if total==FOCUS_TOTAL else "invalid_progression_focus_total"

static func level_for_xp(xp_total:int)->int:
	var level:=1
	while level<100 and xp_total>=xp_floor_for_level(level+1):level+=1
	return level

static func xp_floor_for_level(level:int)->int:
	if level<=1:return 0
	return 25*(level-1)*(level+2)

static func skill_rank(training_total:int)->int:
	var rank:=0
	while rank<MAX_RANK and training_total>=training_floor_for_rank(rank+1):rank+=1
	return rank

static func training_floor_for_rank(rank:int)->int:
	if rank<=0:return 0
	return 25*rank*(rank+1)

static func melee_power_bonus(rank:int)->int:
	return clampi(rank,0,MAX_RANK)*2

static func guard_reduction_milli(rank:int)->int:
	# HOLD starts at 25% physical reduction. Each authoritative GUARD rank adds
	# five percentage points, with a hard 50% cap. Character level is not used.
	return mini(500,250+50*clampi(rank,0,MAX_RANK))
