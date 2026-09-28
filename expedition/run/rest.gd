extends RefCounted
## One inter-zone stop after each of the first three bosses. It has no world
## ticks and never consumes food.

static func enter(s) -> void:
	s.phase = "REST"
	s.auto.running = false
	s.intents.clear()
	s.effect_delays.clear()
	for actor in s.party:
		if bool(actor.get("dead",false)): continue
		actor.downed = false
		actor.erase("bleedout_turns")
		actor.erase("downed_source")
		actor.hp = int(actor.max_hp)
		actor.mp = int(actor.max_mp)
		actor.stress = maxi(0,int(actor.get("stress",0))-30)
		actor.condition = "붕괴" if actor.stress >= 150 else "불안" if actor.stress >= 100 else "평온"
		actor.reservation = {}
	s.message("휴식처")
