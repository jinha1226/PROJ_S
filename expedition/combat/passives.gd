extends RefCounted
## What a fight asks of passives. The family passives live in `Families`, the
## role and element sets in `TagSets`; this file keeps the four hooks the
## fight already calls, and 가시 갑옷's reflection.
const Abilities = preload("res://expedition/items/abilities.gd")
const Families = preload("res://expedition/combat/families.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")

static func adjacent_allies(s, actor: Dictionary) -> int:
	var count := 0
	for other in s.party+s.npcs+s.enemies:
		if other.id != actor.id and other.hp > 0 and other.enemy == actor.enemy and s.melee_reach(actor.pos,other.pos): count += 1
	return count

## Strictly below 50% of maximum health.
static func under_half(actor: Dictionary) -> bool:
	return int(actor.hp)*2 < int(actor.max_hp)

## Damage `attacker` is about to deal to `target`, before 엄호 redirects it.
static func outgoing(s, attacker: Dictionary, target: Dictionary, amount: int) -> int:
	return TagSets.outgoing(s,attacker,target,Families.outgoing(s,attacker,target,amount))

## Damage `target` finally takes, after guards and defence.
static func incoming(s, target: Dictionary, amount: int) -> int:
	return TagSets.incoming(s,target,amount)

## After the hit landed: 가시 갑옷 returns thirty percent of what an adjacent
## attacker dealt, as retaliation that triggers nothing further.
static func after_hit(s, target: Dictionary, attacker: Dictionary, form: String, amount: int = 0) -> void:
	if form == "RETALIATE" or attacker.is_empty() or attacker.hp <= 0 or amount <= 0: return
	if target.get("statuses",{}).has("thorns") and s.melee_reach(target.pos,attacker.pos):
		s.damage(attacker,maxi(1,amount*Abilities.THORN_PERCENT/100),target.id,"RETALIATE")

static func round_start(s, actor: Dictionary) -> void:
	Families.round_start(s,actor)
