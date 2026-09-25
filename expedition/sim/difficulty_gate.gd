extends RefCounted
## §5 difficulty gate: floor N measured against the hero who cleared floors
## 1..N−1 (all of their kill XP and the essences those kills would drop), or a
## share of that clear. Packs are fought one at a time from full HP.
const Session = preload("res://expedition/run/session.gd")
const Runner = preload("res://expedition/sim/model_b_runner.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const FIGHT_LIMIT := 120

## Kill XP and essence drops of floors 1..depth−1 for this seed, scaled by
## `share` percent: a half clear takes half the kills of every species.
static func baseline(seed: int, kit: String, depth: int, share: int = 100) -> Dictionary:
	var s = Session.new_run(seed,kit)
	var rules: Dictionary = Session.CombatStats.content.kill_xp
	var xp := 0
	var kills: Dictionary = {}
	for d in range(1,depth):
		s.depth = d; s.floor_state.build(s)
		for enemy in s.enemies:
			xp += int(rules.base)+d*int(rules.per_depth)
			var id: String = str(enemy.get("part_id",""))
			if Essences.has(id): kills[id] = int(kills.get(id,0))+1
	var drops: Dictionary = {}
	for id in kills:
		var taken: int = int(kills[id])*share/100
		if taken > 0: drops[id] = taken
	return {"xp":xp*share/100,"essences":drops}

## A session on floor `depth` whose hero has the baseline's level and wears its
## most common essences, each absorbed once (a stone has no tiers: the first
## kill's certain drop is all it takes).
static func prepare(seed: int, kit: String, depth: int, share: int = 100):
	var base: Dictionary = baseline(seed,kit,depth,share)
	var s = Session.new_run(seed,kit)
	s.depth = depth; s.floor_state.build(s)
	var hero: Dictionary = s.party[0]
	var phase: String = s.phase
	s.phase = "CAMP"
	s.gain_level_xp(hero,int(base.xp))
	var ids: Array = base.essences.keys()
	ids.sort_custom(func(a,b): return int(base.essences[a]) > int(base.essences[b]) or (int(base.essences[a]) == int(base.essences[b]) and str(a) < str(b)))
	for id in ids:
		if Essences.absorbed(hero,str(id)): continue
		s.parts_bag[id] = int(s.parts_bag.get(id,0))+1
		s.absorb_essence(0,str(id))
	for id in ids:
		var free: int = hero.equipped_abilities.find("")
		if free < 0: break
		if str(id) not in hero.equipped_abilities: s.equip_part(0,free,str(id))
	s.phase = phase
	hero.hp = hero.max_hp; hero.mp = hero.max_mp
	s.events.clear()
	return s

## The nearest free cell two to five steps from `members[0]`, ring by ring.
static func stand_near(s, members: Array) -> bool:
	var hero: Dictionary = s.party[0]
	var target: Vector2i = members[0].pos
	for radius in range(2,6):
		for dy in range(-radius,radius+1):
			for dx in range(-radius,radius+1):
				var cell: Vector2i = target+Vector2i(dx,dy)
				if maxi(absi(dx),absi(dy)) != radius or not s.inside(cell) or not s.is_free(cell): continue
				hero.pos = cell
				return true
	return false

## Every pack of the floor, in group order, each fought alone from full HP.
## `camp_needed`: the losses of the whole floor add up to at least one full HP bar.
static func run_floor(s) -> Dictionary:
	var hero: Dictionary = s.party[0]
	var groups: Dictionary = {}
	for enemy in s.enemies: groups.get_or_add(str(enemy.get("group","")),[]).append(enemy)
	var names: Array = groups.keys()
	names.sort()
	var rows: Array = []
	var lost_total := 0; var wins := 0
	for group in names:
		var members: Array = groups[group]
		var others: Array = s.enemies.filter(func(e): return str(e.get("group","")) != group)
		s.enemies = members
		if not stand_near(s,members): s.enemies = others+members; continue
		hero.hp = hero.max_hp; hero.mp = hero.max_mp; hero.statuses = {}
		for id in hero.cooldowns: hero.cooldowns[id] = 0
		s.floor_state.observe(s)
		var result := "TIMEOUT"
		for _turn in range(FIGHT_LIMIT):
			if hero.hp <= 0 or s.phase == "DEFEAT": result = "DEFEAT"; break
			if members.all(func(e): return e.hp <= 0): result = "WIN"; break
			Runner.hero_turn(s)
		if result == "TIMEOUT" and members.all(func(e): return e.hp <= 0): result = "WIN"
		var lost: int = int(hero.max_hp)-maxi(0,int(hero.hp))
		rows.append({"group":group,"members":members.size(),"result":result,"hp_lost":lost,"hp_lost_percent":lost*100/maxi(1,int(hero.max_hp))})
		lost_total += lost
		if result == "WIN": wins += 1
		s.enemies = others+members
		if result == "DEFEAT": break
	var mean := 0.0
	for row in rows: mean += float(row.hp_lost_percent)
	return {"fights":rows,"mean_loss_percent":mean/maxf(1.0,rows.size()),"camp_needed":lost_total >= int(hero.max_hp),"wins":wins}
