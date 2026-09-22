extends RefCounted
## One player action per call through the public session API. No combat math here.
## Returns the kind of action taken ("HEAL"|"GUARD"|"MOVE"|"ATTACK"|"WAIT"|ability id),
## or "" when the hero could not act — the runner tallies from that word
## instead of guessing from state diffs.
static func step(s, policy: String) -> String:
	var hero: Dictionary = s.party[s.selected]
	if hero.hp <= 0 or hero.ap <= 0: return ""
	if policy == "tactical":
		if hero.hp < 14 and s.supplies[0] > 0 and s.use_supply(0): return "HEAL"
		if hero.hp < 10 and s.supplies[5] > 0 and s.use_supply(5): return "HEAL"
	if s.combat_enemies().is_empty() and approach(s,hero): return "MOVE"
	if policy == "rules":
		# The hero reads the same rule list companions do; no potions or bandages
		# here, so a skill's worth is never masked by supplies.
		var choice: Dictionary = s.Tactics.choose(s,hero)
		if s.act(choice.kind,choice.cell): return choice.kind
		return "WAIT" if s.act("WAIT",hero.pos) else ""
	if s.auto_attack(): return "ATTACK"
	return "WAIT" if s.act("WAIT",hero.pos) else ""

## Nothing in sight: walk one cell towards the encounter room's centre, the way
## a player rounds a pillar instead of waiting out the fight in the doorway.
static func approach(s, hero: Dictionary) -> bool:
	var rooms: Array = s.floor_state.layout.get("rooms",[])
	if rooms.is_empty(): return false
	var target: Vector2i = Rect2i(rooms[0].rect).get_center()
	if hero.pos == target: return false
	var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,hero.pos,[target],func(a,b): return s.can_step(a,b),func(_p): return 100)
	return s.act("MOVE",route.path[1]) if route.found and route.path.size() > 1 else false
