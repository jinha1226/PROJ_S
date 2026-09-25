extends RefCounted
## The compatibility auto-battle path: rounds driven by the rules, the
## reservations and commands that steer them, and the stop events that halt a run.
const Abilities = preload("res://expedition/items/abilities.gd")
const ElementRules = preload("res://sim/environment_rules.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const IntentUI = preload("res://expedition/ui/companion_intent_ui.gd")
const Knobs = preload("res://expedition/ai/knobs.gd")
const NpcAI = preload("res://expedition/actors/npc_ai.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Stances = preload("res://expedition/ai/stances.gd")
const Tactics = preload("res://expedition/ai/tactical_action_selector.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
## Evaluation priority: the hard events first, then the soft alerts.
const AUTO_STOPS := ["BATTLE_START","BATTLE_END","DEATH","ALLY_LETHAL","HP_LOW"]

static func auto_attack(s) -> bool:
	if s.phase != "BATTLE": return false
	var actor: Dictionary = s.party[s.selected]
	if actor.hp <= 0 or actor.ap <= 0: return false
	var targets: Array = s.combat_enemies()
	targets.sort_custom(func(a,b):
		var av: int = a.hp if actor.basic_target == "LOWEST_HP" else s.distance(actor.pos,a.pos)
		var bv: int = b.hp if actor.basic_target == "LOWEST_HP" else s.distance(actor.pos,b.pos)
		return av < bv if av != bv else a.id < b.id)
	for enemy in targets:
		if not s.attack_preview(enemy.pos).is_empty(): return s.act("ATTACK",enemy.pos)
	var best: Array = []
	for enemy in targets:
		var goals: Array = []
		for direction in s.DIRECTIONS:
			var cell: Vector2i = enemy.pos+direction
			if s.is_free(cell) and s.melee_reach(cell,enemy.pos) and Tactics.danger(s,cell) == 0: goals.append(cell)
		var route := TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,goals,func(a,b): return s.can_step(a,b) and Tactics.danger(s,b) == 0,func(_p): return 100)
		if route.found and route.path.size() > 1 and (best.is_empty() or route.path.size() < best.size()): best = route.path
	return s.act("MOVE",best[1]) if not best.is_empty() else false

static func reservation_choice(s, actor: Dictionary) -> Dictionary:
	var order: Dictionary = actor.reservation
	if order.is_empty() or actor.hp <= 0 or actor.ap <= 0 or not s.on_floor(): return {}
	var cell: Vector2i = order.cell
	var def: Dictionary = Abilities.definition(order.kind)
	if order.kind == "ATTACK" or def.get("target","") == "ENEMY":
		var target: Dictionary = {}
		for enemy in s.enemies:
			if enemy.id == order.target_id and enemy.hp > 0: target = enemy; break
		if target.is_empty(): return {}
		if not def.is_empty():
			if not Abilities.legal(s,actor,order.kind,target.pos): return {}
		elif s.attack_preview(target.pos,actor.id).is_empty(): return {}
		cell = target.pos
	elif order.kind == "MOVE":
		if cell not in s.movement_cells(actor.id): return {}
	elif order.kind == "WAIT": cell = actor.pos
	elif not def.is_empty():
		if def.target == "SELF": cell = actor.pos
		if not Abilities.legal(s,actor,order.kind,cell): return {}
	else: return {}
	return {"kind":order.kind,"cell":cell,"reason":"직접 예약","reserved":true}

static func reserve_action(s, index: int, kind: String, cell: Vector2i) -> bool:
	if not s.companions or not s.on_floor() or index < 0 or index >= s.party.size() or index == s.selected: return false
	var actor: Dictionary = s.party[index]
	var previous: Dictionary = actor.reservation
	actor.reservation = {"kind":kind,"cell":cell,"target_id":s.at(cell).get("id",-1)}
	if s.reservation_choice(actor).is_empty(): actor.reservation = previous; return false
	return true

static func cancel_reservation(s, index: int) -> void:
	if index >= 0 and index < s.party.size(): s.party[index].reservation = {}

## The party command's answer for `actor`, or {} when the rules decide.
static func command_choice(s, actor: Dictionary) -> Dictionary:
	if s.party_command == "HOLD_POSITION":
		if s.combat_enemies().any(func(e): return s.melee_reach(actor.pos,e.pos)): return {}
		return {"kind":"WAIT","cell":actor.pos,"reason":"자리 지키기"}
	if s.party_command == "STOP_ATTACK":
		var destination: Vector2i = s.rally_point()
		if actor.pos == destination or maxi(absi(actor.pos.x-destination.x),absi(actor.pos.y-destination.y)) <= 1:
			return {"kind":"WAIT","cell":actor.pos,"reason":"공격 중지"}
		var goals: Array = []
		for direction in s.DIRECTIONS:
			var point: Vector2i = destination+direction
			if s.is_free(point): goals.append(point)
		var route: Dictionary = TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,goals,func(a,b): return s.can_step(a,b),func(_p): return 100) if not goals.is_empty() else {}
		return {"kind":"MOVE","cell":route.path[1],"reason":"집합"} if not route.is_empty() and route.found and route.path.size() > 1 else {"kind":"WAIT","cell":actor.pos,"reason":"집합 대기"}
	if s.party_command == "RETREAT":
		var best: Vector2i = Tactics.retreat_cell(s,actor)
		return {"kind":"WAIT" if best == actor.pos else "MOVE","cell":best,"reason":"후퇴"}
	if s.party_command == "ATTACK_TARGET":
		for enemy in s.combat_enemies():
			if enemy.id != s.command_target: continue
			if s.melee_reach(actor.pos,enemy.pos): return {"kind":"ATTACK","cell":enemy.pos,"reason":"집중 공격"}
			var goals: Array = []
			for direction in s.DIRECTIONS:
				if s.is_free(enemy.pos+direction) and s.melee_reach(enemy.pos+direction,enemy.pos): goals.append(enemy.pos+direction)
			var route: Dictionary = TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,goals,func(a,b): return s.can_step(a,b) and Tactics.danger(s,b) == 0,func(_p): return 100)
			return {"kind":"MOVE","cell":route.path[1],"reason":"집중 공격 접근"} if route.found and route.path.size() > 1 else {"kind":"WAIT","cell":actor.pos,"reason":"대상 경로 없음"}
	return {}

static func companion_choice(s, actor: Dictionary) -> Dictionary:
	var rescue: Dictionary = s.Downed.choice(s,actor)
	if not rescue.is_empty(): return rescue
	var reserved: Dictionary = s.reservation_choice(actor)
	if not reserved.is_empty(): return reserved
	if s.companions:
		var ordered: Dictionary = s.command_choice(actor)
		if not ordered.is_empty(): return ordered
	# An ally outside the hero's light still needs to close the gap even if the
	# hero has entered combat. A foe in the ally's own sight takes priority.
	if not s.floor_state.visible.has(actor.pos) and not s.enemies.any(func(e): return e.hp > 0 and not s.dominated(e) and MonsterAI.line(s,actor.pos,e.pos,MonsterAI.sight(s))):
		return s.floor_state.follow(s,actor)
	if s.floor_state.safe(s): return s.floor_state.follow(s,actor)
	return Tactics.choose(s,actor)

## Read-only display preview for currently actionable party members. `choose`
## is deterministic and does not commit a decision; exhausted members are
## omitted instead of predicting their next round.
static func companion_intent_snapshot(s) -> Array:
	var result: Array = []
	if not s.in_combat(): return result
	for actor in s.party:
		if actor.hp <= 0 or actor.ap <= 0 or s.phase != "BATTLE": continue
		var choice: Dictionary = s.command_choice(actor)
		if choice.is_empty(): choice = Tactics.choose(s,actor)
		var target_id := -1
		if choice.get("kind", "") in ["ATTACK", "PUSH"] or Abilities.has(str(choice.get("kind", ""))):
			var target: Dictionary = s.at(choice.get("cell", actor.pos))
			target_id = int(target.get("id", -1)) if not target.is_empty() else -1
		var dto := IntentUI.adapt(actor,choice,target_id,_intent_id(s,actor,choice,target_id))
		if not dto.is_empty(): result.append(dto)
	return result

static func _intent_id(s, actor: Dictionary, choice: Dictionary, target_id: int) -> int:
	var actor_id := int(actor.get("id",-1))
	var signature := "%s|%s|%d|%s|%d" % [str(choice.get("kind","")),str(actor.get("pos",Vector2i.ZERO)),int(actor.get("ap",0)),str(choice.get("cell",Vector2i.ZERO)),target_id]
	var cached: Dictionary = s.intent_preview_ids.get(actor_id,{})
	if str(cached.get("signature","")) != signature:
		s.intent_decision_serial += 1
		cached = {"signature":signature,"decision_id":s.intent_decision_serial}
		s.intent_preview_ids[actor_id] = cached
	return int(cached.decision_id)

## One rules-driven round: every living member spends its AP through the
## command or the rules, then the round ends. Game UI and simulator both call this.
static func auto_step(s) -> bool:
	if not s.in_combat() or s.alive().is_empty(): return false
	s.battle_stats.rounds = int(s.battle_stats.get("rounds",0))+1
	# Snapshot before anyone acts: the stop events ask what changed *during* the
	# round, so a death or a cleared field inside this step must still be a delta.
	s.remember_round()
	for actor in s.party:
		var guard := 0
		# One roll per member per round, so one tally however many actions it spends.
		var noted := false
		while actor.hp > 0 and actor.ap > 0 and s.phase == "BATTLE" and guard < 4:
			guard += 1
			var choice: Dictionary = s.Downed.choice(s,actor)
			if choice.is_empty(): choice = s.command_choice(actor)
			if choice.is_empty(): choice = Tactics.choose(s,actor)
			if not noted and str(choice.get("mistake","")) != "":
				s.note_mistake(actor,str(choice.mistake)); noted = true
			s.note_explain(actor,choice)
			# last_action reports what actually ran, not what was wanted.
			var target: Dictionary = s.at(choice.get("cell",actor.pos))
			s.intent_decision_serial += 1
			s.active_intent_event = IntentUI.adapt(actor,choice,int(target.get("id",-1)),s.intent_decision_serial)
			var acted: bool = s.act_as(actor,str(choice.get("kind","WAIT")),choice.get("cell",actor.pos),false)
			if acted:
				actor.last_action = str(choice.get("reason","대기"))
			else:
				var wait_choice := {"kind":"WAIT","cell":actor.pos,"reason":"대기"}
				s.active_intent_event = IntentUI.adapt(actor,wait_choice,-1,_intent_id(s,actor,wait_choice,-1))
				if not s.act_as(actor,"WAIT",actor.pos,false): s.active_intent_event = {}; break
				actor.last_action = "대기"
			s.active_intent_event = {}
		# Did the stance get what it wanted this round? One tally per member.
		var row: Dictionary = s.member_stats(actor.id)
		if not row.is_empty() and actor.hp > 0:
			row.role_rounds = row.get("role_rounds",{"in_role":0,"total":0})
			row.role_rounds.total += 1
			if Stances.in_role(s,actor): row.role_rounds.in_role += 1
	if s.on_floor(): s.end_round()
	return true

## Who is fighting against their standing orders, noted at every battle start.
## It costs nothing now — the badge is only there to explain the mistakes the
## member is about to make.
static func open_battle_conflicts(s) -> void:
	for actor in s.alive():
		actor.conflicted = Knobs.conflicted(actor)

## The end of a fight cancels the standing order: a retreat called against one
## pack must not still be running when the next one is sighted.
static func end_battle_orders(s) -> void:
	s.party_command = "FOLLOW"
	s.command_target = -1

## Snapshot of what auto_stop_reason compares against next round.
static func remember_round(s) -> void:
	s.auto.prev_threats = s.party_enemies().size()
	s.auto.prev_low = s.alive().filter(func(a): return a.hp*100/a.max_hp <= int(s.auto.hp_low)).map(func(a): return a.id)
	s.auto.prev_alive = s.alive().size()

## The first stop event that applies at the start of this round, or "".
## Every applicable event is considered in AUTO_STOPS priority order, so a
## disabled or suppressed one never swallows a lower-priority event.
static func auto_stop_reason(s) -> String:
	if not s.on_floor(): return ""
	var threats: int = s.party_enemies().size()
	var living: Array = s.alive()
	var applies := {
		"BATTLE_START": threats > 0 and int(s.auto.prev_threats) == 0,
		"BATTLE_END": threats == 0 and int(s.auto.prev_threats) > 0,
		"DEATH": living.size() < int(s.auto.prev_alive),
		"ALLY_LETHAL": living.any(func(a): return Rules.lethal_threat(s,a) >= a.hp),
		"HP_LOW": living.any(func(a): return a.hp*100/a.max_hp <= int(s.auto.hp_low) and a.id not in s.auto.prev_low)}
	var hard := false
	for reason in AUTO_STOPS:
		if not applies[reason]: continue
		if reason in ["BATTLE_START","BATTLE_END","DEATH"]: hard = true
		if not bool(s.auto.stops.get(reason,false)): continue
		# Repeated alerts are suppressed for three rounds; the hard events never are.
		if reason in ["ALLY_LETHAL","HP_LOW"] and s.auto.last_stop.reason == reason and s.round_number-int(s.auto.last_stop.round) < 3:
			continue
		if reason == "BATTLE_END": s.end_battle_orders()
		s.auto.last_stop = {"reason":reason,"round":s.round_number}
		s.auto.stops_log.append(reason)
		# The report belongs to one battle: the conflicts are opened first so
		# that the fresh rows already carry who fights against their orders.
		if reason == "BATTLE_START": s.open_battle_conflicts(); s.reset_battle_stats()
		s.battle_stats.stops.append(reason)
		s.remember_round()
		return reason
	# Nothing was raised, but a hard event happened: consume it so it cannot re-fire.
	if hard:
		if applies.BATTLE_START: s.open_battle_conflicts(); s.reset_battle_stats()
		if applies.BATTLE_END: s.end_battle_orders()
		s.remember_round()
	for a in s.alive(): a.conflicted = Knobs.conflicted(a)
	return ""

static func companion_previews(s) -> Array:
	var previews: Array = []
	# A solo run that has recruited someone has companions too, and in manual
	# play a companion's AP is only refilled on its own turn.
	if s.party.size() < 2 or not s.on_floor(): return previews
	# `selected` is an index into the party, not an actor id.
	for index in range(s.party.size()):
		var actor: Dictionary = s.party[index]
		if index == s.selected or actor.hp <= 0 or (actor.ap <= 0 and not s.manual_mode): continue
		var choice: Dictionary = s.companion_choice(actor).duplicate(true)
		choice.actor = actor.id
		previews.append(choice)
	return previews

static func end_round(s) -> bool:
	if not s.on_floor(): return false
	s.world_time += 100
	# The floor's NPCs take their round before the monsters do.
	# Everyone listens to this round's noise first; only then is it cleared, so
	# that what the npcs themselves do is heard next round and nothing else is
	# lost down an early return below.
	var awake: Array = []
	for npc in s.npcs:
		if npc.hp > 0 and NpcAI.sense(s,npc): awake.append(npc)
	s.noise.clear()
	for npc in awake: NpcAI.turn(s,npc)
	for enemy in s.enemies:
		s.enemy_attack_turn(enemy)
		if s.party[0].hp <= 0: break
	if s.party[0].hp <= 0: s.check_battle_end(); return true
	for y in range(s.BOARD_SIDE):
		for x in range(s.BOARD_SIDE):
			var point := Vector2i(x,y)
			var cell: Dictionary = s.tile(point)
			var suppression := 0
			if cell.fire > 0 or cell.wet > 0:
				var result := ElementRules.project_existing_fire_tick(cell.fire, cell.wet, 0, s.world_time)
				cell.fire = result.fire_after_decay
				cell.wet = maxi(0, result.wetness_after_suppression - ElementRules.WETNESS_DECAY_PER_ENVIRONMENT_TICK)
				suppression = int(result.suppression)
				var victim: Dictionary = s.at(point)
				if not victim.is_empty() and result.known_damage > 0: s.damage(victim, result.known_damage, 999, "FIRE")
			if suppression > 0 or cell.has("steam_until") or bool(cell.get("ice",false)) or bool(cell.get("poison_pool",false)):
				s.Reactions.tile_tick(s, point, cell, suppression)
	s.Reactions.refresh_wet(s)
	# The round's guards end with the round, win or lose: a cleared room must not
	# carry 엄호 into EXPLORE.
	for actor in s.party+s.npcs: actor["guarded"] = false; actor["protected_by"] = -1
	s.check_battle_end()
	if not s.on_floor(): return true
	# Round-start passives run for the fighters only: the whole 64×64 roster is
	# not in this battle, so a distant monster must not regenerate off-screen.
	for actor in s.friends()+s.party_enemies(): Passives.round_start(s,actor)
	# Cooldowns and 철벽 belong to everyone fighting beside the party; stress, the
	# hunger clock and the action budget stay the party's own bookkeeping.
	for actor in s.friends():
		actor.iron_guard = false
		for id in actor.cooldowns: actor.cooldowns[id] = maxi(0,int(actor.cooldowns[id])-1)
	for actor in s.alive():
		if not s.floor_state.safe(s): s.stress(actor,2)
		actor.ap = s.action_budget(actor)
	s.Downed.tick(s)
	s.round_number += 1
	s.floor_state.observe(s)
	if s.companions and s.party[s.selected].hp <= 0: s.selected = s.party.find(s.alive()[0])
	s.plan_enemies()
	return true

static func action_budget(s, actor: Dictionary) -> int:
	if s.party.size() == 1: return s.solo_rule("solo_actions")
	return 1 if actor.stress >= 150 else 2

static func solo_rule(s, key: String) -> int:
	if s.party.size() != 1: return int(s.DEFAULT_RULES[key])
	return int(s.rules_config.get(key,s.DEFAULT_RULES[key]))

static func plan_enemies(s) -> void:
	Floor.MonsterAI.plan(s)

static func enemy_attack_turn(s, enemy: Dictionary) -> void:
	s.Reactions.begin_action(s)
	_enemy_attack_turn(s,enemy)
	if s.presentation != null: s.presentation.capture(s,enemy.id)

static func _enemy_attack_turn(s, enemy: Dictionary) -> void:
	if not s.on_floor() or enemy.hp <= 0 or s.alive().is_empty(): return
	s.floor_state.enemy_turn(s,enemy)
