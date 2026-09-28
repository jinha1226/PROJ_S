extends SceneTree
## Paired 2v2 probe for the live attack/wait profile. Run manually:
## godot --headless --path . -s tests/utility_2v2_probe.gd
const Session = preload("res://expedition/run/session.gd")
const Mobile = preload("res://expedition/progression/attack_wait.gd")
const ROSTER := {"members":[["dcss_hobgoblin","MELEE"],["goblin","RANGED"]]}
const SAMPLES := 24

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var base: Array = []
	var stones: Array = []
	for seed_value in range(1,SAMPLES+1):
		base.append(fight(seed_value,false))
		stones.append(fight(seed_value,true))
	print("2v2 paired seeds=%d" % SAMPLES)
	print("empty: ",aggregate(base))
	print("random stones: ",aggregate(stones))
	print("paired wins gained/lost: ",paired_wins(base,stones))
	quit()

func picked_stones(seed_value: int) -> Array:
	var catalog: Array = Session.Essences.catalog().duplicate()
	catalog.sort()
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value*9871+43
	var result: Array = []
	for _member in range(2):
		var pool: Array = catalog.duplicate()
		var draw: Array = []
		for _slot in range(4):
			var index: int = rng.randi_range(0,pool.size()-1)
			draw.append(str(pool[index])); pool.remove_at(index)
		result.append(draw)
	return result

func fight(seed_value: int, with_stones: bool) -> Dictionary:
	var draws: Array = picked_stones(seed_value) if with_stones else [[],[]]
	var setup: Array = [{"auto_parts":draws[0]},{"auto_parts":draws[1]}]
	var s = Session.arena_test(seed_value,2,ROSTER,setup,Mobile.PROFILE)
	s.manual_mode = true
	for member in s.party: member.stress = 0
	var counts := {"ATTACK":0,"MOVE":0,"WAIT":0,"OTHER":0}
	var failed := 0
	for _step in range(80):
		if s.party[0].hp <= 0 or s.enemies.all(func(e): return e.hp <= 0): break
		if not s.Scheduler.flush_ready(s): break
		if s.party[0].hp <= 0 or s.enemies.all(func(e): return e.hp <= 0): break
		var hero: Dictionary = s.party[0]
		var action: Dictionary = s.Tactics.choose(s,hero)
		var kind: String = str(action.get("kind","WAIT"))
		counts[kind if counts.has(kind) else "OTHER"] += 1
		if not s.submit(kind,action.get("cell",hero.pos)):
			failed += 1
			if not s.submit("WAIT",hero.pos): break
	return {"win":s.enemies.all(func(e): return e.hp <= 0),"turns":s.turn_serial,
		"hp":s.party.reduce(func(sum,member): return sum+maxi(0,int(member.hp)),0),
		"counts":counts,"failed":failed,"stones":draws}

func aggregate(rows: Array) -> Dictionary:
	var wins := 0; var hp := 0; var turns := 0; var failed := 0
	var counts := {"ATTACK":0,"MOVE":0,"WAIT":0,"OTHER":0}
	for row in rows:
		wins += int(row.win); hp += int(row.hp); turns += int(row.turns); failed += int(row.failed)
		for kind in counts: counts[kind] += int(row.counts[kind])
	return {"wins":wins,"mean_hp":snappedf(float(hp)/rows.size(),0.1),
		"mean_turns":snappedf(float(turns)/rows.size(),0.1),"actions":counts,"invalid":failed}

func paired_wins(base: Array, stones: Array) -> Dictionary:
	var gained := 0; var lost := 0
	for i in range(base.size()):
		if stones[i].win and not base[i].win: gained += 1
		if base[i].win and not stones[i].win: lost += 1
	return {"gained":gained,"lost":lost}
