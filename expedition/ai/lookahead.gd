extends RefCounted
## One-round lookahead from public information only: apply the action's
## immediate effect to a scratch view of positions/HP/intents, then estimate
## what every party member would take this round the way `lethal_threat` does.
## Pure and deterministic — the session is never mutated, only read.
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Abilities = preload("res://expedition/items/abilities.gd")

## `baseline` is the candidate-independent half of the answer: {member id ->
## whether that member is already in lethal danger}. It costs one
## `Rules.lethal_threat` per member and never changes with the action, so
## `Utility.context` computes it once and hands it back here.
static func baseline(s) -> Dictionary:
	var rows: Dictionary = {}
	for member in s.friends(): rows[member.id] = Rules.lethal_threat(s,member) >= int(member.hp)
	return rows

static func predict(s, actor: Dictionary, action: Dictionary, before: Dictionary = {}) -> Dictionary:
	var kind: String = str(action.kind)
	var damage: int = int(action.get("damage",0))
	var pos_override: Dictionary = {}      # actor id -> Vector2i
	var hp_override: Dictionary = {}       # actor id -> int
	var protected: Dictionary = {}         # ally id -> guardian id
	var intents: Array = s.intents.duplicate()
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
			if Abilities.has(kind):
				var def: Dictionary = Abilities.definition(kind)
				if def.effect == "PUSH" and not victim.is_empty():
					var landing: Vector2i = action.cell+(action.cell-actor.pos)
					if s.can_step(action.cell,landing): pos_override[victim.id] = landing
					else:
						hp_override[victim.id] = int(victim.hp)-damage
						enemies_hit += mini(damage,int(victim.hp))
					intents = intents.filter(func(i): return i.id != victim.id)
				elif def.effect == "GUARD" and not victim.is_empty(): protected[victim.id] = actor.id
				elif def.effect == "HEAL":
					var recipient: Dictionary = victim if def.target == "ALLY" else actor
					if not recipient.is_empty(): hp_override[recipient.id] = mini(int(recipient.max_hp),int(recipient.hp)+int(def.heal))
				elif def.effect in ["DAMAGE","LUNGE"]:
					# Only foes are touched here: `parts_candidates.gd` never emits
					# a DAMAGE candidate whose cells catch a living ally, or the
					# actor itself when the part has `self_hit`, so there is no
					# friendly splash left for the prediction to account for.
					var cells: Array = Abilities.cells(s,actor,kind,action.cell) if def.effect == "DAMAGE" else [action.cell]
					for other in s.enemies:
						if other.hp > 0 and other.pos in cells:
							hp_override[other.id] = int(other.hp)-damage
							enemies_hit += mini(damage,int(other.hp))
					if def.effect == "LUNGE": pos_override[actor.id] = Abilities.lunge_cell(s,actor,kind,action.cell)
	# A foe that is dropped to 0 stops winding up: its telegraph goes with it,
	# whoever killed it. The PUSH branch drops its victim's intent on top of
	# this because a shoved caster is interrupted even when it survives.
	if not hp_override.is_empty(): intents = intents.filter(func(i): return int(hp_override.get(i.id,1)) > 0)
	var rows: Dictionary = before if not before.is_empty() else baseline(s)
	var before_lethal := 0
	var after_lethal := 0
	var self_hit := 0
	var ally_hit := 0
	for member in s.friends():
		if bool(rows.get(member.id,false)): before_lethal += 1
		var now: int = threat_after(s,member,pos_override,hp_override,protected,intents)
		if now >= int(hp_override.get(member.id,member.hp)): after_lethal += 1
		if member.id == actor.id: self_hit = now
		else: ally_hit += now
	return {"self":self_hit,"allies":ally_hit,"enemies":enemies_hit,"lethal_saved":maxi(0,before_lethal-after_lethal)}

## `Rules.lethal_threat` over the scratch view: the same intent/role/sight/
## cast-recovery conditions, with dead foes gone, moved actors read at their new
## cells, and a guarded member taking half.
static func threat_after(s, member: Dictionary, pos_override: Dictionary, hp_override: Dictionary, protected: Dictionary, intents: Array) -> int:
	var pos: Vector2i = pos_override.get(member.id,member.pos)
	var worst := 0
	var bonus := 0
	for intent in intents:
		if intent.cell == pos and (not s.manual_mode or int(intent.get("resolve_at",s.time)) <= s.time+100): worst = maxi(worst,int(intent.damage)+bonus)
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
