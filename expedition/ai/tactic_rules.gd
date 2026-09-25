extends RefCounted
## Shared rule schema: UI and AI use the same catalog and validation. The
## catalog itself is derived from the parts catalog so that no skill id is
## listed twice; abilities.gd preloads this file, so it is loaded lazily here.
const CONDITIONS_BY_TARGET := {
	"SELF":["ALWAYS","HP","STATUS","DANGER"],
	"ENEMY":["ALWAYS","HP","STATUS","CHARGING","DANGER"],
	"ALLY":["ALLY_LETHAL"]}
const TARGETS_BY_TARGET := {"SELF":["SELF"],"ENEMY":["NEAREST","LOWEST_HP"],"ALLY":["ALLY"]}
static var _catalog: Dictionary = {}
const BASIC_TARGETS = ["NEAREST","LOWEST_HP"]
const BASIC_TARGET_DEFAULT = "NEAREST"
const TARGET_NAMES = {"NEAREST":"가까운 적","LOWEST_HP":"체력이 낮은 적","SELF":"자신","ALLY":"인접 아군"}
const WHEN_NAMES = {"ALWAYS":"사용 가능할 때","HP":"체력 기준","STATUS":"특정 상태일 때","CHARGING":"대상이 공격 준비 중","DANGER":"자신이 공격받을 위험","ALLY_LETHAL":"아군이 이번 라운드 공격받으면 죽을 때"}
const STATUS_NAMES = {"WET":"젖음","FIRE":"불 위에 있음"}

## Rule catalog: {id: {name, description, targets, conditions}} for every part.
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var definitions: Dictionary = load("res://expedition/items/abilities.gd").DEFINITIONS
		for id in definitions:
			var def: Dictionary = definitions[id]
			_catalog[id] = {"name":str(def.name),"description":str(def.description),
				"targets":TARGETS_BY_TARGET[def.target].duplicate(),"conditions":CONDITIONS_BY_TARGET[def.target].duplicate()}
	return _catalog

static func skill(id: String) -> Dictionary:
	var at := id.find("@")
	if at < 0: return catalog().get(id,{})
	var base: Dictionary = catalog().get(id.substr(0,at),{})
	if base.is_empty(): return {}
	var def: Dictionary = load("res://expedition/items/abilities.gd").definition(id)
	if def.is_empty(): return {}
	var row: Dictionary = base.duplicate(true)
	row.name = str(def.name); row.description = str(def.description)
	return row

static func defaults() -> Array:
	return []

static func make_rule(id: String, target: String, when: String) -> Dictionary:
	return {"skill":id,"target":target,"when":when,"enabled":true,"subject":"SELF" if target == "SELF" else "TARGET","threshold":50,"comparison":"BELOW","status":"WET"}

static func valid(rule: Dictionary) -> bool:
	var def: Dictionary = skill(rule.get("skill",""))
	if def.is_empty(): return false
	return rule.get("target") in def.targets and rule.get("when") in def.conditions and rule.get("enabled") is bool and rule.get("subject") in ["SELF","TARGET"] and rule.get("comparison") in ["BELOW","ABOVE"] and rule.get("threshold") is int and rule.threshold >= 10 and rule.threshold <= 100 and STATUS_NAMES.has(rule.get("status",""))

static func matches(s, source: Dictionary, candidate: Dictionary, rule: Dictionary) -> bool:
	if not rule.enabled or candidate.kind != rule.skill: return false
	var target: Dictionary = source if rule.target == "SELF" else s.at(candidate.cell)
	if target.is_empty() or target.hp <= 0: return false
	# 엄호 targets a living ally other than the actor, never a foe and never self.
	if rule.target == "ALLY" and (target.get("enemy",false) or target.id == source.id): return false
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
		"ALLY_LETHAL": return lethal_threat(s,target) >= target.hp
	return false

## The largest single hit `ally` could take this round. An approximation, not a
## simulation: it assumes every enemy that can reach the ally does so this round
## and ignores movement, line-of-fire blocking by other actors and ordering. A
## cell-locked caster intent counts at its announced damage; every other enemy
## counts at its role damage. Both gain the floor's darkness bonus, which
## `MonsterAI` adds on resolution — but only on the floor, since room and boss
## intents resolve flat. Only enemies that are already alert, or that would
## become alert on sight this turn, and that are not still recovering from a
## cast, are counted.
static func lethal_threat(s, ally: Dictionary) -> int:
	var worst := 0
	var bonus := 0
	for intent in s.intents:
		if intent.cell == ally.pos and (not s.manual_mode or int(intent.get("resolve_at",s.time)) <= s.time+100): worst = maxi(worst,int(intent.damage)+bonus)
	var roles: Dictionary = s.Floor.MonsterAI.ROLES
	for e in s.combat_enemies():
		if e.hp <= 0 or int(e.get("cast_recovery",0)) > 0: continue
		if not e.get("alert",false) and not s.Floor.MonsterAI.line(s,e.pos,ally.pos,9): continue
		var role: String = e.get("role","MELEE")
		if not roles.has(role): role = "MELEE"
		var hit := 0
		if s.melee_reach(e.pos,ally.pos):
			# monster_ai.gd: a non-melee role that finds itself in contact strikes for 4.
			hit = int(roles[role].damage) if role == "MELEE" else 4
		elif role != "MELEE" and s.Floor.MonsterAI.line(s,e.pos,ally.pos,int(roles[role].range)):
			hit = int(roles[role].damage)
		if hit > 0: worst = maxi(worst,hit+bonus)
	return worst

static func summary(rule: Dictionary) -> String:
	var condition: String = WHEN_NAMES[rule.when]
	if rule.when == "HP": condition = ("자신" if rule.subject == "SELF" else "대상")+" 체력 %d%% %s" % [rule.threshold,"이하" if rule.comparison == "BELOW" else "이상"]
	if rule.when == "STATUS": condition = ("자신" if rule.subject == "SELF" else "대상")+" · "+STATUS_NAMES[rule.status]
	return TARGET_NAMES[rule.target]+" · "+condition
