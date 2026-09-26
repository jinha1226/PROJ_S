extends RefCounted
const Zones = preload("res://expedition/level/zones.gd")
## Leaving town and taking the stairs down, and the levels won on the way.
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
const Memory = preload("res://sim/party_memory_state.gd")
const NpcRoster = preload("res://expedition/actors/npc_roster.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Essences = preload("res://expedition/progression/essences.gd")

static func depart(s) -> bool:
	if s.phase != "IDLE" or s.alive().is_empty(): return false
	var kit: Dictionary = CombatStats.kit(s.kit_id)
	if kit.is_empty(): return false
	s.depth = 1; s.score = 0; s.run_stats = {"mistakes":0,"kills":0}
	s.bag.clear(); s.known.clear(); s.pending_choice.clear()
	s.essence_seen.clear(); s.events.clear()
	s.appearances = s.Consumables.shuffle_appearances(s.seed_value)
	s.time = 0; s.boundary = 100; s.turn_serial = 0; s.roll_serial = 0
	s.party[0].gear.weapon = {"type":str(kit.weapon),"enchant":0}
	s.party[0].gear.armour = {"type":"robe","enchant":0}
	var hero: Dictionary = s.party[0]
	var kit_spell: String = str(kit.get("spell",""))
	hero.buffs = {}; hero.spells = []; hero.prepared = []
	hero.essences = {}; hero.essence_spells = {}; hero.equipped_abilities = [""]
	if not kit_spell.is_empty():
		var essence: String = str(Essences.CASTER_BY_SCHOOL.get(str(kit.axis),""))
		hero.essences[essence] = 1
		hero.essence_spells[essence] = kit_spell
		Essences.sync_slots(hero)
		hero.equipped_abilities[0] = essence
		Essences.sync_spells(hero)
	StatSheet.refresh_pools(s,hero)
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
	return s.enemies.any(func(e): return e.get("boss",false) and e.hp > 0) or s.npcs.any(func(n): return n.get("fallen",false) and n.hp > 0)

static func descend(s) -> bool:
	if s.depth >= Zones.FINAL_DEPTH: return false
	if s.phase != "EXPLORE" or not s.floor_state.safe(s) or s.stairs_sealed(): return false
	if s.party.any(func(actor): return s.Downed.is_downed(actor)): return false
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
	while actor.level < Essences.MAX_LEVEL and actor.level_xp >= actor.level*actor.level*65:
		actor.level += 1
		actor.max_hp += 4; actor.hp = mini(actor.max_hp,actor.hp+4)
		actor.max_mp += 2; actor.mp = mini(actor.max_mp,actor.mp+2)
		if actor in s.party: s.message("%s 레벨 %d" % [actor.name,int(actor.level)])
	Essences.sync_slots(actor)
	return int(actor.level)-before
