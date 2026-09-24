extends RefCounted
## Leaving town and taking the stairs down, and the levels won on the way.
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const NpcRoster = preload("res://expedition/actors/npc_roster.gd")
const Spells = preload("res://expedition/spells/spells.gd")

static func depart(s) -> bool:
	if s.phase != "IDLE" or s.alive().is_empty(): return false
	var kit: Dictionary = CombatStats.kit(s.kit_id)
	if kit.is_empty(): return false
	s.depth = 1; s.score = 0; s.run_stats = {"mistakes":0,"kills":0}
	s.time = 0; s.boundary = 100; s.turn_serial = 0; s.roll_serial = 0
	s.party[0].gear.weapon = {"type":str(kit.weapon),"enchant":0}
	s.party[0].gear.armour = {"type":"robe","enchant":0}
	s.party[0].skill_xp[str(kit.axis)] = 25
	var kit_spell: String = str(kit.get("spell",""))
	s.party[0].books = []; s.party[0].buffs = {}
	s.party[0].spells = []; s.party[0].prepared = []
	if not kit_spell.is_empty():
		# A magic kit leaves with its school's primer and the first spell in it.
		s.party[0].spells = [kit_spell]
		s.party[0].prepared = [kit_spell]
		s.party[0].books = [str(Spells.definition(kit_spell).get("book",""))]
	for actor in s.party:
		# A debt owed or refused outlives the run it was made in.
		actor.memory.records = actor.memory.records.filter(func(record): return int(record.salience) >= 700 or str(record.kind) in Memory.SOCIAL_KINDS)
		actor.hit_and_run = false; actor.important_memories = {}
	s.reset_battle_stats()
	s.auto.prev_threats = 0; s.auto.prev_low = []; s.auto.prev_alive = s.alive().size()
	s.auto.stops_log = []; s.auto.last_stop = {"reason":"","round":-99}
	s.floor_state.build(s)
	if s.roster.is_empty(): NpcRoster.generate(s)
	NpcRoster.place(s)
	s.message("%d층 진입" % s.depth); return true

static func stairs_sealed(s) -> bool:
	return s.enemies.any(func(e): return e.get("boss",false) and e.hp > 0)

static func descend(s) -> bool:
	if s.phase != "EXPLORE" or not s.floor_state.safe(s) or s.stairs_sealed(): return false
	var stairs: Vector2i = s.floor_state.layout.get("stairs",Vector2i(-1,-1))
	if stairs.x < 0 or not s.alive().any(func(a): return s.distance(a.pos,stairs) <= 1): return false
	s.depth += 1; s.score += 20
	for actor in s.party: actor.reservation = {}; actor.hit_and_run = false
	s.end_battle_orders(); s.reset_battle_stats()
	s.floor_state.build(s)
	if s.roster.is_empty(): NpcRoster.generate(s)
	NpcRoster.place(s)
	s.message("%d층 진입" % s.depth); return true

static func gain_level_xp(s, actor: Dictionary, amount: int) -> int:
	var before := int(actor.get("level",1))
	actor.level_xp = int(actor.get("level_xp",0))+maxi(0,amount)
	while actor.level < 12 and actor.level_xp >= actor.level*actor.level*65:
		actor.level += 1
		actor.max_hp += 4; actor.hp = mini(actor.max_hp,actor.hp+4)
		actor.max_mp += 2; actor.mp = mini(actor.max_mp,actor.mp+2)
	return actor.level-before
