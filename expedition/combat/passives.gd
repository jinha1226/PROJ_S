extends RefCounted
## What a fight asks of passives. The headline effects and the role combos
## live in `StoneEffects`, the element sets in `TagSets`; this file keeps the
## hooks the fight already calls, and 가시 갑옷's reflection.
const Abilities = preload("res://expedition/items/abilities.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")

static func adjacent_allies(s, actor: Dictionary) -> int:
	var count := 0
	for other in s.party+s.npcs+s.enemies:
		if other.id != actor.id and other.hp > 0 and other.enemy == actor.enemy and s.melee_reach(actor.pos,other.pos): count += 1
	return count

## Strictly below 50% of maximum health.
static func under_half(actor: Dictionary) -> bool:
	return int(actor.hp)*2 < int(actor.max_hp)

## Damage `attacker` is about to deal to the actual recipient after 엄호.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int, form: String = "HIT") -> int:
	return StoneEffects.outgoing(s,attacker,target,TagSets.outgoing(s,attacker,target,amount),form)

## Damage `target` finally takes, after guards and defence.
static func incoming(s, target: Dictionary, amount: int) -> int:
	return StoneEffects.incoming(s,target,TagSets.incoming(s,target,amount))

## After the hit landed: the stones' procs, then 가시 갑옷 returns thirty
## percent of what an adjacent attacker dealt, as retaliation that triggers
## nothing further.
static func after_hit(s, target: Dictionary, attacker: Dictionary, form: String, amount: int = 0) -> void:
	if form == "RETALIATE" or attacker.is_empty() or attacker.hp <= 0: return
	StoneEffects.after_hit(s,target,attacker,form,amount)
	if attacker.hp <= 0 or amount <= 0: return
	if target.get("statuses",{}).has("thorns") and s.melee_reach(target.pos,attacker.pos):
		s.damage(attacker,maxi(1,amount*Abilities.THORN_PERCENT/100),target.id,"RETALIATE")

static func round_start(s, actor: Dictionary) -> void:
	StoneEffects.round_start(s,actor)
