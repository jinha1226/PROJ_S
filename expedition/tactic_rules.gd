extends RefCounted
## Shared rule schema: UI and AI use the same catalog and validation.
const SKILLS = {
	"PUSH":{"name":"밀치기","description":"인접한 적을 한 칸 밀어냅니다.","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"GUARD":{"name":"방어","description":"다음 공격의 피해를 줄입니다.","targets":["SELF"],"conditions":["ALWAYS","HP","STATUS","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"SHOCKWAVE":{"name":"수렁 충격파","targets":["SELF"],"conditions":["ALWAYS","HP","STATUS","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"BOMB":{"name":"폭탄 투척","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"IRON_HIDE":{"name":"철갑 방어","targets":["SELF"],"conditions":["ALWAYS","HP","STATUS","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"HEAVY_STRIKE":{"name":"시험 강타","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"THROWING_KNIFE":{"name":"시험 투척","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"FIELD_DRESSING":{"name":"시험 응급처치","targets":["SELF"],"conditions":["ALWAYS","HP","STATUS","DANGER","TELEGRAPHED","HOLDING_LINE"]},
	"LUNGE":{"name":"시험 돌진","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER","TELEGRAPHED","HOLDING_LINE"]}}
const BASIC_TARGETS = ["NEAREST","LOWEST_HP"]
const BASIC_TARGET_DEFAULT = "NEAREST"
const TARGET_NAMES = {"NEAREST":"가까운 적","LOWEST_HP":"체력이 낮은 적","SELF":"자신"}
const WHEN_NAMES = {"ALWAYS":"사용 가능할 때","HP":"체력 기준","STATUS":"특정 상태일 때","CHARGING":"대상이 공격 준비 중","DANGER":"자신이 공격받을 위험","TELEGRAPHED":"예고 공격 대상일 때","HOLDING_LINE":"전열에서 아군을 막고 있을 때"}
const STATUS_NAMES = {"WET":"젖음","FIRE":"불 위에 있음"}

static func defaults() -> Array:
	return [make_rule("PUSH","NEAREST","CHARGING"),make_rule("GUARD","SELF","TELEGRAPHED"),make_rule("GUARD","SELF","HOLDING_LINE")]

static func make_rule(skill: String, target: String, when: String) -> Dictionary:
	return {"skill":skill,"target":target,"when":when,"enabled":true,"subject":"SELF" if target == "SELF" else "TARGET","threshold":50,"comparison":"BELOW","status":"WET"}

static func valid(rule: Dictionary) -> bool:
	if not SKILLS.has(rule.get("skill","")): return false
	var def: Dictionary = SKILLS[rule.skill]
	return rule.get("target") in def.targets and rule.get("when") in def.conditions and rule.get("enabled") is bool and rule.get("subject") in ["SELF","TARGET"] and rule.get("comparison") in ["BELOW","ABOVE"] and rule.get("threshold") is int and rule.threshold >= 10 and rule.threshold <= 100 and STATUS_NAMES.has(rule.get("status",""))

static func matches(s, source: Dictionary, candidate: Dictionary, rule: Dictionary) -> bool:
	if not rule.enabled or candidate.kind != rule.skill: return false
	var target: Dictionary = source if rule.target == "SELF" else s.at(candidate.cell)
	if target.is_empty() or target.hp <= 0: return false
	var subject: Dictionary = source if rule.subject == "SELF" else target
	match rule.when:
		"ALWAYS": return true
		"HP":
			var percent: float = float(subject.hp)*100/subject.max_hp
			return percent <= rule.threshold if rule.comparison == "BELOW" else percent >= rule.threshold
		"STATUS": return s.tile(subject.pos).wet > 0 if rule.status == "WET" else s.tile(subject.pos).fire > 0
		"CHARGING": return target.get("charging",false)
		"DANGER":
			if s.Tactics.danger(s,source.pos) > 0: return true
			for foe in s.combat_enemies():
				if foe.hp > 0 and s.Tactics.threat(s,foe,source.pos,foe.pos) > 0: return true
		"TELEGRAPHED": return telegraphed(s,source)
		"HOLDING_LINE": return holding_line(s,source)
	return false

## A telegraphed enemy intent lands on the actor's own cell. Tile fire and
## plain melee adjacency are deliberately not counted: this condition exists to
## answer a wind-up, not the mere presence of a foe.
static func telegraphed(s, actor: Dictionary) -> bool:
	for intent in s.intents:
		if intent.cell == actor.pos: return true
	return false

## The actor stands in contact with a living visible enemy while at least one
## other living party member does not: the actor is the one holding the line.
## Never true for a solo party.
static func holding_line(s, actor: Dictionary) -> bool:
	var foes: Array = s.combat_enemies().filter(func(e): return e.hp > 0)
	if not foes.any(func(e): return s.melee_reach(actor.pos,e.pos)): return false
	for mate in s.alive():
		if mate.id == actor.id: continue
		if not foes.any(func(e): return s.melee_reach(mate.pos,e.pos)): return true
	return false

static func summary(rule: Dictionary) -> String:
	var condition: String = WHEN_NAMES[rule.when]
	if rule.when == "HP": condition = ("자신" if rule.subject == "SELF" else "대상")+" 체력 %d%% %s" % [rule.threshold,"이하" if rule.comparison == "BELOW" else "이상"]
	if rule.when == "STATUS": condition = ("자신" if rule.subject == "SELF" else "대상")+" · "+STATUS_NAMES[rule.status]
	return TARGET_NAMES[rule.target]+" · "+condition
