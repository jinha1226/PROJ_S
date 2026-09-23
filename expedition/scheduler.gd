extends RefCounted
## Hero actions open a half-open tick interval. Every other actor takes any
## turns whose ready_at lies inside it; a turn exactly at the end waits.
const Kernel = preload("res://sim/combat_kernel.gd")
const Tactics = preload("res://expedition/tactical_action_selector.gd")
const NpcAI = preload("res://expedition/npc_ai.gd")
const Rules = preload("res://expedition/combat_rules.gd")
const ElementRules = preload("res://sim/environment_rules.gd")

static func actors(s) -> Array:
	return s.party.slice(1).filter(func(a): return a.hp > 0) + s.npcs.filter(func(n): return n.hp > 0 and n.awake) + s.enemies.filter(func(e): return e.hp > 0)

static func awaken(s) -> void:
	for npc in s.npcs:
		if npc.hp <= 0: continue
		var was_awake: bool = bool(npc.awake)
		if NpcAI.sense(s, npc) and not was_awake:
			npc.ready_at = maxi(int(npc.get("ready_at", 0)), s.time)

## Resolve actors and environment already due at this exact tick before the
## hero submits another action. This closes the previous half-open interval.
static func flush_ready(s) -> bool:
	var now: int = s.time
	s.floor_state.observe(s)
	awaken(s)
	var complete: bool = Kernel.advance(now+1,
		func(limit: int) -> Dictionary:
			if s.phase == "DEFEAT": return {}
			var best: Dictionary = {}
			if s.boundary < limit: best = {"at":s.boundary,"id":-1}
			for actor in actors(s):
				var ready: int = maxi(now,int(actor.get("ready_at",now)))
				if ready < limit: best = Kernel.earlier(best,ready,int(actor.id),limit)
			return best,
		func(event: Dictionary) -> bool:
			s.time = int(event.at)
			if int(event.id) == -1:
				environment_tick(s); s.boundary += 100
			else: act(s,s.actor_by_id(int(event.id)))
			return true)
	s.time = now
	s.world_time = now
	s.floor_state.observe(s)
	return complete

static func advance(s, cost: int) -> bool:
	var end: int = s.time + maxi(1, cost)
	s.party[0].ready_at = end
	s.floor_state.observe(s)
	awaken(s)
	var complete: bool = Kernel.advance(end,
		func(limit: int) -> Dictionary:
			if s.phase == "DEFEAT": return {}
			var best: Dictionary = {}
			if s.boundary < limit: best = {"at":s.boundary, "id":-1}
			for actor in actors(s):
				var ready: int = maxi(s.time, int(actor.get("ready_at", s.time)))
				if ready >= limit: continue
				best = Kernel.earlier(best, ready, int(actor.id), limit)
			return best,
		func(event: Dictionary) -> bool:
			s.time = int(event.at)
			if int(event.id) == -1:
				environment_tick(s); s.boundary += 100
			else:
				act(s, s.actor_by_id(int(event.id)))
			return true)
	s.time = end
	s.world_time = end
	s.turn_serial += 1
	s.round_number = s.turn_serial + 1
	s.battle_stats.rounds = s.turn_serial
	s.floor_state.observe(s)
	awaken(s)
	s.noise.clear()
	s.plan_enemies()
	s.check_battle_end()
	return complete

static func act(s, actor: Dictionary) -> void:
	if actor.is_empty() or actor.hp <= 0: return
	var cost := 100
	var was: Vector2i = actor.pos
	if bool(actor.get("enemy", false)):
		s.enemy_attack_turn(actor)
		if actor.pos != was: cost = Rules.move_time(s, actor, actor.pos)
	elif s.wanderer(actor):
		NpcAI.turn(s, actor)
		if actor.pos != was: cost = Rules.move_time(s, actor, actor.pos)
	else:
		actor.ap = 1
		var choice: Dictionary = Tactics.choose(s, actor)
		var kind: String = str(choice.get("kind", "WAIT"))
		var cell: Vector2i = choice.get("cell", actor.pos)
		cost = s.action_cost(actor, kind, cell)
		s.resolving_companions = true
		if not s.act_as(actor, kind, cell, false):
			cost = 100; s.act_as(actor, "WAIT", actor.pos, false)
		s.resolving_companions = false
		s.note_explain(actor, choice)
		if str(choice.get("mistake", "")) != "": s.note_mistake(actor, str(choice.mistake))
	actor.ready_at = s.time + maxi(40, cost)

static func environment_tick(s) -> void:
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			var point := Vector2i(x, y)
			var cell: Dictionary = s.tile(point)
			if cell.fire <= 0 and cell.wet <= 0: continue
			var result: Dictionary = ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, s.time)
			cell.fire = result.fire_after_decay
			cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
			if result.known_damage > 0:
				var victim: Dictionary = s.at(point)
				if not victim.is_empty(): s.damage(victim, result.known_damage, 999, "FIRE")
	for actor in s.party + s.npcs:
		actor["guarded"] = false; actor["protected_by"] = -1
		actor.iron_guard = false
		for id in actor.cooldowns: actor.cooldowns[id] = maxi(0, int(actor.cooldowns[id]) - 1)
	for actor in s.party + s.npcs + s.enemies:
		if actor.hp <= 0: continue
		for status in actor.get("statuses",{}).keys():
			var until: int = int(actor.statuses[status])
			if until < s.time:
				actor.statuses.erase(status); continue
			if status == "bleed": Rules.damage(s,{},actor,2,"physical")
			elif status == "burn": Rules.damage(s,{},actor,1,"fire")
			elif status == "poison": Rules.damage(s,{},actor,2,"poison")
			if until <= s.time: actor.statuses.erase(status)
	for actor in s.alive():
		if not s.floor_state.safe(s): s.stress(actor, 2)
	for actor in s.friends() + s.party_enemies(): s.Passives.round_start(s, actor)

static func double_movers(s, cost: int) -> Array:
	var result: Array = []
	for enemy in s.party_enemies():
		var next: int = maxi(s.time, int(enemy.get("ready_at", s.time)))
		var actor_cost: int = s.action_cost(enemy, "ATTACK", enemy.pos)
		if next + actor_cost < s.time + cost: result.append(enemy)
	return result
