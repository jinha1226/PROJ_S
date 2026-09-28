extends RefCounted
## One-round lookahead from public information only: apply the action's
## immediate effect to a scratch view of positions/HP/intents, then estimate
## what every party member would take this round the way `lethal_threat` does.
## Pure and deterministic — the session is never mutated, only read.
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const MobileEffects = preload("res://expedition/progression/attack_wait.gd")

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
	var mobile: Dictionary = mobile_effects(s,actor,kind,victim,damage)
	if kind == "ATTACK": damage = int(mobile.damage)
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
	for id in mobile.extra:
		var other: Dictionary = s.actor_by_id(int(id))
		if other.is_empty(): continue
		var prior: int = int(hp_override.get(id,other.hp))
		var dealt: int = mini(maxi(0,prior),int(mobile.extra[id]))
		hp_override[id] = prior-dealt
		enemies_hit += dealt
		mobile.value += dealt
	for id in mobile.positions: pos_override[id] = mobile.positions[id]
	for id in mobile.heals:
		var healed: Dictionary = s.actor_by_id(int(id))
		if healed.is_empty(): continue
		hp_override[id] = mini(int(healed.max_hp),int(hp_override.get(id,healed.hp))+int(mobile.heals[id]))
	# A foe that is dropped to 0 stops winding up: its telegraph goes with it,
	# whoever killed it. The PUSH branch drops its victim's intent on top of
	# this because a shoved caster is interrupted even when it survives.
	if not hp_override.is_empty() or not mobile.interrupted.is_empty():
		intents = intents.filter(func(i): return int(hp_override.get(i.id,1)) > 0 and not mobile.interrupted.has(i.id))
	var rows: Dictionary = before if not before.is_empty() else baseline(s)
	var before_lethal := 0
	var after_lethal := 0
	var self_hit := 0
	var ally_hit := 0
	for member in s.friends():
		if bool(rows.get(member.id,false)): before_lethal += 1
		var now: int = threat_after(s,member,pos_override,hp_override,protected,intents,mobile,actor)
		if not mobile.guard.is_empty() or int(mobile.threat) > 0 or not mobile.statuses.is_empty():
			var unprotected: int = threat_after(s,member,pos_override,hp_override,protected,intents)
			mobile.value += maxi(0,unprotected-now)
		if now >= int(hp_override.get(member.id,member.hp)): after_lethal += 1
		var recovery: int = maxi(0,int(hp_override.get(member.id,member.hp))-int(member.hp))
		if member.id == actor.id: self_hit = now-recovery
		else: ally_hit += now-recovery
	return {"self":self_hit,"allies":ally_hit,"enemies":enemies_hit,"lethal_saved":maxi(0,before_lethal-after_lethal),"mobile_value":int(mobile.value)}

## Read the equipped automatic rules without firing them. The projection only
## covers this action and the next enemy response; timed healing and summons
## receive a small future value instead of pretending they happen immediately.
static func mobile_effects(s, actor: Dictionary, kind: String, victim: Dictionary, base_damage: int) -> Dictionary:
	var result := {"damage":base_damage,"extra":{},"heals":{},"guard":{},"statuses":{},
		"positions":{},"interrupted":{},"threat":0,"value":0}
	if not MobileEffects.active(actor) or kind not in ["ATTACK","WAIT"]: return result
	if kind == "WAIT" and s.status_blocks(actor,"ATTACK"): return result
	var ids: Array = MobileEffects.effects(actor)
	ids.sort_custom(func(a,b):
		var ar: Dictionary = MobileEffects.data.effects[a]
		var br: Dictionary = MobileEffects.data.effects[b]
		var ac: bool = str(ar.role) == "CHAIN"
		var bc: bool = str(br.role) == "CHAIN"
		return not ac if ac != bc else str(a) < str(b))
	var owner_view: Dictionary = actor.duplicate()
	owner_view.statuses = actor.get("statuses",{}).duplicate(true)
	var target_view: Dictionary = victim.duplicate() if not victim.is_empty() else actor.duplicate()
	target_view.statuses = target_view.get("statuses",{}).duplicate(true)
	var ranged: bool = not victim.is_empty() and MobileEffects.distance(actor.pos,victim.pos) > 1
	if kind == "ATTACK":
		var attack_percent := int(actor.get("aw_state",{}).get("aim",0))*10 if ranged else 0
		for prep in actor.get("aw_state",{}).get("attack_preps",{}).values():
			if str(prep.get("id","")) in ids: attack_percent += int(prep.get("percent",0))
		for id in ids:
			var r: Dictionary = MobileEffects.data.effects[id]
			if str(r.event) != "ATTACK" or not MobileEffects.ready(s,actor,str(id),r): continue
			if not MobileEffects.conditions(s,owner_view,r,{"target":target_view,"self_statuses":owner_view.statuses,"ranged":ranged}): continue
			if str(r.op) == "attack_bonus":
				attack_percent += int(r.percent)
				if r.has("consume"): target_view.statuses.erase(str(r.consume))
		result.damage = maxi(0,base_damage*(100+attack_percent)/100)
		if victim.is_empty() or int(result.damage) <= 0: return result
	var event := "HIT" if kind == "ATTACK" else "WAIT"
	for id in ids:
		var r: Dictionary = MobileEffects.data.effects[id]
		if str(r.event) != event or not MobileEffects.ready(s,actor,str(id),r): continue
		var ctx := {"target":target_view,"self_statuses":owner_view.statuses,"ranged":ranged,
			"lost":mini(maxi(0,int(result.damage)),int(victim.get("hp",0)))}
		if not MobileEffects.conditions(s,owner_view,r,ctx): continue
		var op: String = str(r.op)
		match op:
			"status":
				if survives(result,victim):
					add_status(s,result,victim,str(r.status),int(r.get("ticks",300)),target_view)
					if r.has("damage"): add_extra(s,result,victim,r,int(r.damage))
			"status_area":
				for foe in MobileEffects.targets(s,actor,actor.pos,int(r.radius),int(r.get("count",0))):
					add_status(s,result,foe,str(r.status),int(r.get("ticks",300)))
					if int(r.get("damage",0)) > 0: add_extra(s,result,foe,r,int(r.damage))
			"damage":
				if survives(result,victim): add_extra(s,result,victim,r,int(r.damage))
			"extra":
				if survives(result,victim):
					add_extra(s,result,victim,r,maxi(1,int(s.CombatStats.stats(s,actor).damage)*int(r.damage_percent)/100))
			"heal_ally":
				var injured: Array = MobileEffects.allies(s,actor,int(r.radius)).filter(func(a): return int(a.hp) < int(a.max_hp))
				if not injured.is_empty(): add_heal(result,injured[0],int(r.heal))
			"heal_self": add_heal(result,actor,int(r.heal))
			"drain":
				if int(ctx.lost) > 0: add_heal(result,actor,mini(int(r.cap),maxi(1,int(ctx.lost)*int(r.percent)/100)))
			"prepare": add_guard(s,result,actor,r)
			"ally_guard":
				var mates: Array = MobileEffects.allies(s,actor,int(r.get("radius",2)))
				if int(r.get("count",0)) > 0: mates = mates.slice(0,int(r.count))
				for mate in mates: add_guard(s,result,mate,r)
			"threat":
				if MobileEffects.encounter_active(s,actor): result.threat = maxi(int(result.threat),int(r.get("amount",0)))
			"bless":
				if not owner_view.statuses.has("blessing"): result.value += 3
				owner_view.statuses.blessing = int(s.time)+int(r.get("ticks",300))
			"regen":
				if int(actor.hp) < int(actor.max_hp): result.value += mini(int(actor.max_hp)-int(actor.hp),int(r.get("heal",0))*int(r.get("pulses",1)))
			"summon":
				if s.Spells.Summons.summons_of(s,actor).size() < int(r.cap) and not s.Spells.Summons.summon_cells(s,actor).is_empty(): result.value += 12
			"attack_prep": result.value += 3
			"cleanse":
				for mate in MobileEffects.allies(s,actor,int(r.radius)):
					if mate.get("statuses",{}).keys().any(func(name): return name in s.Statuses.HARMFUL): result.value += 4; break
			"push":
				if survives(result,victim) and not bool(victim.get("boss",false)):
					var landing: Vector2i = victim.pos+Vector2i(signi(victim.pos.x-actor.pos.x),signi(victim.pos.y-actor.pos.y))
					if s.can_step(victim.pos,landing):
						result.positions[victim.id] = landing
						result.interrupted[victim.id] = true
			"burst":
				var centre: Vector2i = victim.pos if not victim.is_empty() else actor.pos
				for foe in MobileEffects.targets(s,actor,centre,int(r.get("radius",1))):
					add_extra(s,result,foe,r,int(r.get("damage",0)))
			"lightning":
				if not victim.is_empty():
					var current: Dictionary = victim
					var visited: Array = []
					for _hop in range(int(r.get("count",1))):
						visited.append(int(current.id))
						add_extra(s,result,current,r,int(r.get("damage",0)))
						var near: Array = MobileEffects.targets(s,actor,current.pos,int(r.get("radius",1))).filter(func(t): return int(t.id) not in visited)
						near.sort_custom(func(a,b): return MobileEffects.distance(current.pos,a.pos) < MobileEffects.distance(current.pos,b.pos) if MobileEffects.distance(current.pos,a.pos) != MobileEffects.distance(current.pos,b.pos) else int(a.id) < int(b.id))
						if near.is_empty(): break
						current = near[0]
			"spread", "extend":
				if not victim.is_empty() and target_view.statuses.has(str(r.status)):
					var near: Array = MobileEffects.targets(s,actor,victim.pos,int(r.get("radius",1))).filter(func(t): return int(t.id) != int(victim.id))
					near.sort_custom(func(a,b): return MobileEffects.distance(victim.pos,a.pos) < MobileEffects.distance(victim.pos,b.pos) if MobileEffects.distance(victim.pos,a.pos) != MobileEffects.distance(victim.pos,b.pos) else int(a.id) < int(b.id))
					if int(r.get("count",0)) > 0: near = near.slice(0,int(r.count))
					for foe in near:
						if op == "spread": add_status(s,result,foe,str(r.status),int(r.get("ticks",300)))
						else: result.value += 1
			"pet_focus", "pet_buff", "pet_bless", "pet_extend":
				if not s.Spells.Summons.summons_of(s,actor).is_empty(): result.value += 3
	return result

static func survives(result: Dictionary, victim: Dictionary) -> bool:
	return not victim.is_empty() and int(victim.hp) > int(result.damage)+int(result.extra.get(victim.id,0))

static func add_extra(s, result: Dictionary, target: Dictionary, rule: Dictionary, amount: int) -> void:
	if target.is_empty() or int(target.hp) <= 0 or amount <= 0: return
	var element: String = str(rule.get("element","physical"))
	if element not in ["physical","SLASH","IMPACT","PIERCE"]:
		amount = maxi(0,amount*(100-int(s.CombatStats.stats(s,target).res.get(element,0)))/100)
	result.extra[target.id] = int(result.extra.get(target.id,0))+amount

static func add_heal(result: Dictionary, target: Dictionary, amount: int) -> void:
	var missing: int = maxi(0,int(target.max_hp)-int(target.hp)-int(result.heals.get(target.id,0)))
	if missing > 0:
		var gained: int = mini(missing,amount)
		result.heals[target.id] = int(result.heals.get(target.id,0))+gained
		result.value += gained*2

static func add_guard(s, result: Dictionary, target: Dictionary, rule: Dictionary) -> void:
	var guard: Dictionary = result.guard.get(target.id,{"reduction":0,"armour":0,"dodge":0})
	guard.reduction = maxi(int(guard.reduction),int(rule.get("reduction",0)))
	guard.reduction = maxi(int(guard.reduction),int(rule.get("share",0)))
	guard.armour = maxi(int(guard.armour),int(rule.get("mods",{}).get("armour",0)))
	guard.dodge = maxi(int(guard.dodge),int(rule.get("mods",{}).get("dodge",0)))
	result.guard[target.id] = guard
	if rule.has("reaction"):
		var reaction: String = str(rule.reaction)
		if reaction == "reflect": result.value += maxi(1,Rules.lethal_threat(s,target)*int(rule.get("percent",0))/100)
		elif reaction == "burst": result.value += int(rule.get("damage",0))
		elif reaction == "status": result.value += {"stun":8,"burn":5,"poison":3,"bleed":3,"weak":3}.get(str(rule.get("status","")),2)

static func add_status(s, result: Dictionary, target: Dictionary, name: String, ticks: int, view: Dictionary = {}) -> void:
	if target.is_empty() or int(target.hp) <= 0 or target.get("statuses",{}).has("immune"): return
	if name in ["stun","freeze"] and bool(target.get("aw_cc_locked",false)): return
	ticks = s.Statuses.resisted_ticks(s,target,name,ticks)
	if ticks <= 0: return
	var worn: Dictionary = result.statuses.get(target.id,target.get("statuses",{}).duplicate(true))
	if int(worn.get(name,0)) >= int(s.time)+ticks: return
	worn[name] = int(s.time)+ticks
	result.statuses[target.id] = worn
	if not view.is_empty(): view.statuses = worn
	result.value += maxi(1,int({"stun":8,"freeze":7,"burn":5,"poison":3,"bleed":3,"slow":3,"weak":3,"confuse":3}.get(name,2))*mini(ticks,300)/300)

## `Rules.lethal_threat` over the scratch view: the same intent/role/sight/
## cast-recovery conditions, with dead foes gone, moved actors read at their new
## cells, and a guarded member taking half.
static func threat_after(s, member: Dictionary, pos_override: Dictionary, hp_override: Dictionary, protected: Dictionary, intents: Array, mobile: Dictionary = {}, actor: Dictionary = {}) -> int:
	var pos: Vector2i = pos_override.get(member.id,member.pos)
	var worst := 0
	for intent in intents:
		if intent.cell == pos and (not s.manual_mode or int(intent.get("resolve_at",s.time)) <= s.time+100): worst = maxi(worst,int(intent.damage))
	var roles: Dictionary = s.Floor.MonsterAI.ROLES
	for e in s.combat_enemies():
		if int(hp_override.get(e.id,e.hp)) <= 0 or int(e.get("cast_recovery",0)) > 0: continue
		var forecast_status: Dictionary = mobile.get("statuses",{}).get(e.id,{})
		if forecast_status.has("stun") or forecast_status.has("freeze"): continue
		var epos: Vector2i = pos_override.get(e.id,e.pos)
		if not e.get("alert",false) and not s.Floor.MonsterAI.line(s,epos,pos,9): continue
		if int(mobile.get("threat",0)) > 0 and not actor.is_empty() and member.id != actor.id and s.Floor.MonsterAI.line(s,epos,actor.pos,5):
			var actor_priority: int = s.distance(epos,actor.pos)*4-s.MobileEffects.threat(s,e,actor)-int(mobile.threat)
			var member_priority: int = s.distance(epos,pos)*4-s.MobileEffects.threat(s,e,member)
			if actor_priority < member_priority: continue
		var role: String = e.get("role","MELEE")
		if not roles.has(role): role = "MELEE"
		var hit := 0
		if s.melee_reach(epos,pos):
			# monster_ai.gd: a non-melee role that finds itself in contact strikes for 4.
			hit = int(roles[role].damage) if role == "MELEE" else 4
		elif role != "MELEE" and s.Floor.MonsterAI.line(s,epos,pos,int(roles[role].range)):
			hit = int(roles[role].damage)
		if forecast_status.has("weak"): hit = maxi(0,hit*7/10)
		if hit > 0: worst = maxi(worst,hit)
	if protected.has(member.id): worst = maxi(1,worst/2) if worst > 0 else 0
	var guard: Dictionary = mobile.get("guard",{}).get(member.id,{})
	if not guard.is_empty():
		worst = maxi(0,worst-int(guard.get("armour",0)))
		worst = worst*(100-int(guard.get("reduction",0)))/100
		worst = worst*(100-int(guard.get("dodge",0)))/100
	return worst
