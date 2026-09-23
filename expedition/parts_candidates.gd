extends RefCounted
## Every part the member could press this round, as unscored candidates in the
## same pool the stance programme fills (설계 §1 4단계, §5). What used to be
## `Tactics.rule_candidates` lives here, minus the hand-written scores: the
## legality and safety checks stay, the numbers are `Utility.score`'s business.
##
## Each candidate: `kind` = 파츠 id, `tag` "PART", `cell` = 대상 칸,
## `damage` = 이 행동이 줄 피해, `target_id` = 대상 id, `reason` = 파츠 이름.
const Abilities = preload("res://expedition/abilities.gd")

static func candidates(s, actor: Dictionary) -> Array:
	var options: Array = []
	push_options(s,actor,options)
	guard_options(s,actor,options)
	part_options(s,actor,options)
	return options

static func part(id: String, cell: Vector2i, damage: int, target_id: int) -> Dictionary:
	return {"kind":id,"tag":"PART","cell":cell,"damage":damage,"target_id":target_id,
		"reason":str(Abilities.DEFINITIONS[id].name)}

## 밀치기: only foes in reach, and only where the shove is safe. The gain used
## to be a hand-written `benefit` bonus; the lookahead considerations
## (`la_ally_hit`, `la_lethal_saved`) are what weigh it now — until Task 3
## lands those, a push is scored by its rule condition alone. `benefit` itself
## survives as one half of the "do not drag a foe off an ally" test.
static func push_options(s, actor: Dictionary, options: Array) -> void:
	if "PUSH" not in actor.equipped_abilities: return
	for enemy in s.combat_enemies():
		if enemy.hp <= 0 or not s.melee_reach(actor.pos,enemy.pos): continue
		var landing: Vector2i = enemy.pos+(enemy.pos-actor.pos)
		var moved: bool = s.can_step(enemy.pos,landing)
		var benefit := 0
		var unsafe := false
		for ally in s.friends():
			var before: int = s.Tactics.threat(s,enemy,ally.pos,enemy.pos)
			var after: int = 0 if enemy.get("charging",false) else s.Tactics.threat(s,enemy,ally.pos,landing if moved else enemy.pos)
			benefit += before-after
			if after > before: unsafe = true
		# Do not push a foe onto healing water or out of another ally's melee reach.
		if moved:
			if enemy.get("boss",false) and enemy.get("pattern",-1) == 0 and s.tile(landing).terrain == "water": unsafe = true
			for ally in s.friends():
				if ally.id != actor.id and s.melee_reach(ally.pos,enemy.pos) and not s.melee_reach(ally.pos,landing) and benefit <= 0: unsafe = true
		if unsafe: continue
		# A shove with nowhere to go is an 8-damage hit instead.
		options.append(part("PUSH",enemy.pos,0 if moved else int(s.CombatStats.stats(s,actor).damage) if s.manual_mode else s.Growth.power(actor,"MELEE",8),int(enemy.id)))

## 엄호 has no self form: one candidate per adjacent living ally.
static func guard_options(s, actor: Dictionary, options: Array) -> void:
	if "GUARD" not in actor.equipped_abilities: return
	for mate in s.friends():
		if mate.id != actor.id and s.melee_reach(actor.pos,mate.pos):
			options.append(part("GUARD",mate.pos,0,int(mate.id)))

## The species parts: every legal target cell, minus the ones that would catch
## an ally or nobody at all.
static func part_options(s, actor: Dictionary, options: Array) -> void:
	for id in actor.equipped_abilities:
		if not Abilities.DEFINITIONS.has(id) or Abilities.DEFINITIONS[id].effect in ["PUSH","GUARD"]: continue
		var def: Dictionary = Abilities.DEFINITIONS[id]
		var targets: Array = [actor] if def.target == "SELF" else s.combat_enemies()
		for target in targets:
			if not Abilities.legal(s,actor,id,target.pos): continue
			if def.effect == "DAMAGE":
				var cells: Array = Abilities.cells(s,actor,id,target.pos)
				if s.friends().any(func(a): return (a.id != actor.id or def.self_hit) and a.pos in cells): continue
				if not s.combat_enemies().any(func(e): return e.hp > 0 and e.pos in cells): continue
			var damage: int = Abilities.power(s,actor,def) if def.effect in ["DAMAGE","LUNGE"] else 0
			options.append(part(id,target.pos,damage,int(target.id)))
