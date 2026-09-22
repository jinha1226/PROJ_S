extends RefCounted
## One player action per call through the public session API. No combat math here.
static func step(s, policy: String) -> bool:
	var hero: Dictionary = s.party[s.selected]
	if hero.hp <= 0 or hero.ap <= 0: return false
	if policy == "tactical":
		if hero.hp < 14 and s.supplies[0] > 0 and s.use_supply(0): return true
		if hero.hp < 10 and s.supplies[5] > 0 and s.use_supply(5): return true
		var adjacent := 0
		for e in s.combat_enemies():
			if maxi(absi(e.pos.x-hero.pos.x),absi(e.pos.y-hero.pos.y)) == 1: adjacent += 1
		if adjacent >= 2 and not hero.get("guarded",false) and s.act("GUARD",hero.pos): return true
	if s.auto_attack(): return true
	return s.act("WAIT",hero.pos)
