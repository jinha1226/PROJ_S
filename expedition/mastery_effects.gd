extends RefCounted
const Mastery = preload("res://expedition/mastery.gd")
const Stats = preload("res://expedition/combat_stats.gd")

static func sword_level(actor: Dictionary) -> int:
	if str(actor.get("gear",{}).get("weapon",{}).get("type","")) not in ["sword","dagger"]: return 0
	return Mastery.rank(actor,"sword")

static func attack_raw(s, source: Dictionary, target: Dictionary, raw: int) -> int:
	if sword_level(source) >= 10 and s.CombatRules.roll(s,source,target,"sword_critical",100) < 10:
		s.message(str(source.name)+" 치명타")
		return ceili(raw*1.5)
	return raw

static func on_attack(s, source: Dictionary, target: Dictionary, result: Dictionary) -> void:
	if not bool(result.get("hit",false)) or target.hp <= 0: return
	var level := sword_level(source)
	if level >= 3: target.statuses["bleed"] = s.time+200
	if level >= 5 and Mastery.rank(source,"fire") >= 3:
		var fire_damage := 8 if level >= 8 and Mastery.rank(source,"fire") >= 6 else 4
		s.CombatRules.damage(s,source,target,fire_damage,"fire")

static func on_dodge(s, defender: Dictionary, attacker: Dictionary) -> void:
	if sword_level(defender) < 5 or attacker.hp <= 0 or not s.melee_reach(defender.pos,attacker.pos): return
	Mastery.record(defender,int(attacker.id),"sword")
	s.CombatRules.damage(s,defender,attacker,maxi(1,int(Stats.stats(s,defender).damage)/2),"physical")
	s.message(str(defender.name)+" 반격")

static func fire_power(caster: Dictionary, power: int) -> int:
	return ceili(power*1.5) if Mastery.rank(caster,"fire") >= 10 else power

static func on_spell_hit(s, caster: Dictionary, target: Dictionary, school: String) -> void:
	if school != "fire": return
	if target.hp > 0 and Mastery.rank(caster,"fire") >= 3: target.statuses["burn"] = s.time+300
	if Mastery.rank(caster,"fire") >= 5 and Mastery.rank(caster,"sword") >= 3:
		var sword_damage: int = int(Stats.stats(s,caster).damage)/2
		for other in s.enemies:
			if other.id != target.id and other.hp > 0 and s.melee_reach(target.pos,other.pos):
				s.CombatRules.damage(s,caster,other,maxi(1,sword_damage),"physical")
