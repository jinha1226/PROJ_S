extends RefCounted
## One-round lookahead from public information only: apply the action's
## immediate effect to a scratch view of positions/HP/intents, then estimate
## what every party member would take this round the way `lethal_threat` does.
## Pure and deterministic — the session is never mutated, only read.
const Rules = preload("res://expedition/tactic_rules.gd")
const Abilities = preload("res://expedition/abilities.gd")

static func predict(s, actor: Dictionary, action: Dictionary) -> Dictionary:
	var kind: String = str(action.kind)
	var damage: int = int(action.get("damage",0))
	var pos_override: Dictionary = {}      # actor id -> Vector2i
	var hp_override: Dictionary = {}       # actor id -> int
	var protected: Dictionary = {}         # ally id -> guardian id
	var intents: Array = s.intents.duplicate(true)
	var enemies_hit := 0
	var victim: Dictionary = s.at(action.cell) if kind != "MOVE" and kind != "WAIT" else {}
	match kind:
		"MOVE": pos_override[actor.id] = action.cell
		"ATTACK":
			if not victim.is_empty():
				hp_override[victim.id] = int(victim.hp)-damage
				enemies_hit += mini(damage,int(victim.hp))
		"GUARD":
			if not victim.is_empty(): protected[victim.id] = actor.id
		_:
			if Abilities.DEFINITIONS.has(kind):
				var def: Dictionary = Abilities.DEFINITIONS[kind]
				if def.effect == "PUSH" and not victim.is_empty():
					var landing: Vector2i = action.cell+(action.cell-actor.pos)
					if s.can_step(action.cell,landing): pos_override[victim.id] = landing
					else:
						hp_override[victim.id] = int(victim.hp)-damage
						enemies_hit += mini(damage,int(victim.hp))
					intents = intents.filter(func(i): return i.id != victim.id)
				elif def.effect == "GUARD" and not victim.is_empty(): protected[victim.id] = actor.id
				elif def.effect in ["DAMAGE","LUNGE"]:
					var cells: Array = Abilities.cells(s,actor,kind,action.cell) if def.effect == "DAMAGE" else [action.cell]
					for other in s.enemies:
						if other.hp > 0 and other.pos in cells:
							hp_override[other.id] = int(other.hp)-damage
							enemies_hit += mini(damage,int(other.hp))
					if def.effect == "LUNGE": pos_override[actor.id] = Abilities.lunge_cell(s,actor,kind,action.cell)
	var before_lethal := 0
	var after_lethal := 0
	var self_hit := 0
	var ally_hit := 0
	for member in s.alive():
		var was: int = Rules.lethal_threat(s,member)
		if was >= int(member.hp): before_lethal += 1
		var now: int = threat_after(s,member,pos_override,hp_override,protected,intents)
		if now >= int(member.hp): after_lethal += 1
		if member.id == actor.id: self_hit = now
		else: ally_hit += now
	return {"self":self_hit,"allies":ally_hit,"enemies":enemies_hit,"lethal_saved":maxi(0,before_lethal-after_lethal)}

## `Rules.lethal_threat` over the scratch view: the same intent/role/sight/
## cast-recovery conditions, with dead foes gone, moved actors read at their new
## cells, and a guarded member taking half.
static func threat_after(s, member: Dictionary, pos_override: Dictionary, hp_override: Dictionary, protected: Dictionary, intents: Array) -> int:
	var pos: Vector2i = pos_override.get(member.id,member.pos)
	var worst := 0
	var bonus: int = s.Floor.enemy_bonus(s.light)
	for intent in intents:
		if intent.cell == pos: worst = maxi(worst,int(intent.damage)+(bonus if s.floor_mode else 0))
	var roles: Dictionary = s.Floor.MonsterAI.ROLES
	for e in s.combat_enemies():
		if int(hp_override.get(e.id,e.hp)) <= 0 or int(e.get("cast_recovery",0)) > 0: continue
		var epos: Vector2i = pos_override.get(e.id,e.pos)
		if not e.get("alert",false) and not s.Floor.MonsterAI.line(s,epos,pos,9): continue
		var role: String = e.get("role","MELEE")
		if not roles.has(role): role = "MELEE"
		var hit := 0
		if s.melee_reach(epos,pos):
			# monster_ai.gd: a non-melee role that finds itself in contact strikes for 4.
			hit = int(roles[role].damage) if role == "MELEE" else 4
		elif role != "MELEE" and s.Floor.MonsterAI.line(s,epos,pos,int(roles[role].range)):
			hit = int(roles[role].damage)
		if hit > 0: worst = maxi(worst,hit+bonus)
	if protected.has(member.id): worst = maxi(1,worst/2) if worst > 0 else 0
	return worst
