extends RefCounted
## Part passives. A closed list of kinds and four hooks; nothing else in the
## game reads a passive. Party members carry the passives of their equipped
## parts, monsters the passive of their species part.
const Abilities = preload("res://expedition/abilities.gd")
const KINDS := ["PACK","RETALIATE","DIRTY","AMBUSHER","THICK_HIDE","BLOODLUST","REGEN","AMPHIBIOUS"]

static func of(actor: Dictionary) -> Array:
	var ids: Array = [actor.get("part_id","")] if actor.enemy else actor.equipped_abilities
	var result: Array = []
	for id in ids:
		var def: Dictionary = Abilities.DEFINITIONS.get(id,{})
		if not def.is_empty() and not def.passive.is_empty(): result.append(def.passive)
	return result

static func adjacent_allies(s, actor: Dictionary) -> int:
	var count := 0
	for other in s.party+s.enemies:
		if other.id != actor.id and other.hp > 0 and other.enemy == actor.enemy and s.melee_reach(actor.pos,other.pos): count += 1
	return count

## Strictly below 50% of maximum health.
static func under_half(actor: Dictionary) -> bool:
	return int(actor.hp)*2 < int(actor.max_hp)

## Damage `attacker` is about to deal to `target`, before 엄호 redirects it.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	for passive in of(attacker):
		var value: int = int(passive.value)
		match passive.kind:
			"PACK": amount += value*adjacent_allies(s,attacker)
			"DIRTY": if under_half(target): amount += value
			"AMBUSHER": if adjacent_allies(s,target) == 0: amount += value
			"BLOODLUST": if under_half(attacker): amount += value
			"AMPHIBIOUS":
				var tile: Dictionary = s.tile(attacker.pos)
				if tile.terrain == "water" or int(tile.wet) > 0: amount += value
	return amount

## Damage `target` finally takes, after guards and defence.
static func incoming(s, target: Dictionary, amount: int) -> int:
	for passive in of(target):
		match passive.kind:
			"THICK_HIDE": amount = maxi(1,amount-int(passive.value))
	return amount

## After the hit landed. Retaliation is plain damage with its own form so it
## never triggers passives again.
static func after_hit(s, target: Dictionary, attacker: Dictionary, form: String) -> void:
	if form == "RETALIATE" or attacker.is_empty() or attacker.hp <= 0: return
	for passive in of(target):
		match passive.kind:
			"RETALIATE":
				if s.melee_reach(target.pos,attacker.pos):
					s.message("%s · 반격" % target.name)
					s.damage(attacker,int(passive.value),target.id,"RETALIATE")

static func round_start(s, actor: Dictionary) -> void:
	if actor.hp <= 0: return
	for passive in of(actor):
		match passive.kind:
			"REGEN":
				var before: int = actor.hp
				actor.hp = mini(int(actor.max_hp),int(actor.hp)+int(passive.value))
				if actor.hp > before: s.Body.heal(actor)
