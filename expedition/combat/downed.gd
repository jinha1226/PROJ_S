extends RefCounted
## Party companions remain on the floor for three completed turns after a
## lethal hit. A nearby living party member can spend an action to rescue one.
const Body = preload("res://game/rebuilt/body_bridge.gd")
const TurnCore = preload("res://sim/turn_engine.gd")
const TURNS := 3

static func is_downed(actor: Dictionary) -> bool:
	return not actor.is_empty() and int(actor.get("hp",0)) <= 0 and bool(actor.get("downed",false))

static func at(s, point: Vector2i) -> Dictionary:
	for actor in s.party:
		if is_downed(actor) and actor.pos == point: return actor
	return {}

static func enter(s, actor: Dictionary, source: int) -> void:
	actor.downed = true
	actor.bleedout_turns = TURNS
	actor.downed_source = source
	actor.ap = 0
	actor.reservation = {}
	s.remember_important(actor,"SELF_HARM",int(actor.id)+1,source+1,850)
	for ally in s.alive():
		s.remember_important(ally,"ALLY_DOWNED",int(actor.id)+1,source+1,750)
		s.stress(ally,8)

static func can_rescue(s, rescuer: Dictionary, actor: Dictionary) -> bool:
	return s.on_floor() and rescuer in s.party and actor in s.party and rescuer != actor \
		and int(rescuer.hp) > 0 and int(rescuer.ap) > 0 and is_downed(actor) \
		and not s.status_blocks(rescuer,"RESCUE") and s.melee_reach(rescuer.pos,actor.pos)

static func rescue(s, rescuer: Dictionary, actor: Dictionary) -> bool:
	if not can_rescue(s,rescuer,actor): return false
	# Pull the casualty off the contact tile when there is room. This frees a
	# one-cell corridor for the rest of the party instead of trapping the fight
	# behind a revived member who cannot act until the next tick.
	if s.on_floor():
		var exits: Array = []
		for direction in s.DIRECTIONS:
			var point: Vector2i = actor.pos+direction
			if s.is_free(point) and int(s.tile(point).fire) <= 0 and str(s.tile(point).terrain) not in ["lava","bog","deep_water"]: exits.append(point)
		exits.sort_custom(func(a,b):
			var danger_a: int = s.Tactics.danger(s,a)
			var danger_b: int = s.Tactics.danger(s,b)
			if danger_a != danger_b: return danger_a < danger_b
			var near_a := 999
			var near_b := 999
			for foe in s.combat_enemies():
				near_a = mini(near_a,s.distance(a,foe.pos))
				near_b = mini(near_b,s.distance(b,foe.pos))
			return near_a > near_b if near_a != near_b else str(a) < str(b))
		if not exits.is_empty(): actor.pos = exits[0]
	actor.hp = maxi(1,int(actor.max_hp)/4)
	actor.downed = false
	actor.erase("bleedout_turns")
	actor.erase("downed_source")
	actor.statuses.erase("bleed")
	actor.statuses.erase("burn")
	actor.statuses.erase("poison")
	actor.ready_at = maxi(int(actor.get("ready_at",0)),int(s.time)+100)
	actor.ap = 0
	if bool(actor.get("npc",false)): actor.state = "PARTY"
	Body.heal(actor)
	s.StoneEffects.Vfx.emit(s,"revive",actor.pos,rescuer.pos)
	s.serial += 1
	s.remember_important(actor,"RESCUED",int(rescuer.id)+1,int(rescuer.id)+1,850)
	s.remember_important(rescuer,"ALLY_RESCUED",int(actor.id)+1,int(rescuer.id)+1,750)
	s.message("%s, %s 구조" % [rescuer.name,actor.name])
	return true

static func tick(s) -> void:
	for actor in s.party:
		if not is_downed(actor): continue
		actor.bleedout_turns = maxi(0,int(actor.bleedout_turns)-1)
		if int(actor.bleedout_turns) > 0: continue
		actor.downed = false
		actor.dead = true
		actor.erase("bleedout_turns")
		actor.erase("downed_source")
		if bool(actor.get("npc",false)):
			actor.state = "DEAD"
			actor.awake = false
			actor.activity = ""
		s.serial += 1
		for ally in s.alive():
			s.remember_important(ally,"ALLY_LOST",int(actor.id)+1,int(actor.id)+1,900)
			s.stress(ally,22)
		s.message("%s 사망" % actor.name)

static func choice(s, rescuer: Dictionary) -> Dictionary:
	if rescuer not in s.party or int(rescuer.hp) <= 0: return {}
	var downed: Array = s.party.filter(func(a): return is_downed(a))
	if downed.is_empty(): return {}
	downed.sort_custom(func(a,b): return int(a.bleedout_turns) < int(b.bleedout_turns) if int(a.bleedout_turns) != int(b.bleedout_turns) else int(a.id) < int(b.id))
	for actor in downed:
		if can_rescue(s,rescuer,actor): return {"kind":"RESCUE","cell":actor.pos,"reason":"동료 구조"}
		var goals: Array = []
		for direction in s.DIRECTIONS:
			var point: Vector2i = actor.pos+direction
			if s.is_free(point) and s.melee_reach(point,actor.pos): goals.append(point)
		if goals.is_empty(): continue
		var route: Dictionary = TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,rescuer.pos,goals,
			func(a,b): return s.can_step(a,b),func(_p): return 100)
		if route.found and route.path.size() > 1:
			return {"kind":"MOVE","cell":route.path[1],"reason":"동료 구조"}
	return {}
