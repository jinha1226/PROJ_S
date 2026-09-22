extends RefCounted
## Shared rule schema: UI and AI use the same catalog and validation.
const SKILLS = {
	"PUSH":{"name":"밀치기","description":"인접한 적을 한 칸 밀어냅니다.","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER"]},
	"GUARD":{"name":"엄호","description":"인접 아군이 받을 피해를 대신 받고 절반만 입습니다.","targets":["ALLY"],"conditions":["ALLY_LETHAL"]},
	"SHOCKWAVE":{"name":"수렁 충격파","targets":["SELF"],"conditions":["ALWAYS","HP","STATUS","DANGER"]},
	"BOMB":{"name":"폭탄 투척","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER"]},
	"IRON_HIDE":{"name":"철갑 방어","targets":["SELF"],"conditions":["ALWAYS","HP","STATUS","DANGER"]},
	"HEAVY_STRIKE":{"name":"시험 강타","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER"]},
	"THROWING_KNIFE":{"name":"시험 투척","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER"]},
	"FIELD_DRESSING":{"name":"시험 응급처치","targets":["SELF"],"conditions":["ALWAYS","HP","STATUS","DANGER"]},
	"LUNGE":{"name":"시험 돌진","targets":["NEAREST","LOWEST_HP"],"conditions":["ALWAYS","HP","STATUS","CHARGING","DANGER"]}}
const BASIC_TARGETS = ["NEAREST","LOWEST_HP"]
const BASIC_TARGET_DEFAULT = "NEAREST"
const TARGET_NAMES = {"NEAREST":"가까운 적","LOWEST_HP":"체력이 낮은 적","SELF":"자신","ALLY":"인접 아군"}
const WHEN_NAMES = {"ALWAYS":"사용 가능할 때","HP":"체력 기준","STATUS":"특정 상태일 때","CHARGING":"대상이 공격 준비 중","DANGER":"자신이 공격받을 위험","ALLY_LETHAL":"아군이 이번 라운드 공격받으면 죽을 때"}
const STATUS_NAMES = {"WET":"젖음","FIRE":"불 위에 있음"}

static func defaults() -> Array:
	return [make_rule("PUSH","NEAREST","CHARGING"),make_rule("GUARD","ALLY","ALLY_LETHAL")]

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
	var bonus: int = s.Floor.enemy_bonus(s.light)
	for intent in s.intents:
		if intent.cell == ally.pos: worst = maxi(worst,int(intent.damage)+(bonus if s.floor_mode else 0))
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
