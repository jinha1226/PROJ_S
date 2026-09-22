extends SceneTree
## Light tiers: darker floors pay more and hit harder, and ambush on first sight.
const Session = preload("res://expedition/session.gd")
const Floor = preload("res://expedition/continuous_floor.gd")
const MonsterAI = preload("res://expedition/monster_ai.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func solo(seed_value: int = 731) -> Variant:
	var s = Session.new(seed_value,true,false,true); s.depart()
	for enemy in s.enemies: enemy.hp = 0
	return s

func chest(s) -> Vector2i:
	return s.floor_state.features.keys().filter(func(p): return s.floor_state.features[p].get("curio_id","") == "LOCKED_CHEST")[0]

func run() -> void:
	check(Floor.light_tier(100) == "BRIGHT" and Floor.light_tier(60) == "BRIGHT","sixty and above is bright")
	check(Floor.light_tier(59) == "DIM" and Floor.light_tier(35) == "DIM","thirty-five to fifty-nine is dim")
	check(Floor.light_tier(34) == "DARK" and Floor.light_tier(0) == "DARK","below thirty-five is dark")
	check(Floor.loot_percent(90) == 100 and Floor.loot_percent(50) == 125 and Floor.loot_percent(20) == 150,"loot scales by tier")
	check(Floor.drop_percent(90) == 50 and Floor.drop_percent(50) == 65 and Floor.drop_percent(20) == 80,"essence drop scales by tier")
	check(Floor.enemy_bonus(90) == 0 and Floor.enemy_bonus(50) == 1 and Floor.enemy_bonus(20) == 2,"enemy damage bonus by tier")

	# Curio loot uses the tier at the moment of investigation.
	var expected := {}
	for light in [90,50,20]:
		var s = solo()
		var p: Vector2i = chest(s)
		s.party[0].pos = p+Vector2i.LEFT; s.light = light; s.floor_state.observe(s)
		check(Session.Curios.resolve(s,p,"TOOL"),"chest opens at light %d" % light)
		expected[light] = s.loot
	check(expected[50] == expected[90]*125/100 and expected[20] == expected[90]*150/100,"darker chest pays more (%s)" % expected)
	var altar = solo()
	var ap: Vector2i = altar.floor_state.features.keys().filter(func(p): return altar.floor_state.features[p].kind == "altar")[0]
	altar.party[0].pos = ap+Vector2i.LEFT; altar.light = 20; altar.floor_state.observe(altar)
	check(altar.floor_state.interact(altar,ap) and altar.loot == 37,"dark altar pays 150 percent")

	# Essence drops: same seeds, more drops when dark.
	var bright_drops := 0; var dark_drops := 0
	for seed_value in range(20):
		for light in [90,20]:
			var s = Session.new(seed_value,true,false,true); s.depart(); s.light = light
			var count := 0
			for enemy in s.enemies:
				var before: int = s.essences.values().reduce(func(a,b): return a+b,0)
				enemy.hp = 0; s.roll_essence(enemy)
				if s.essences.values().reduce(func(a,b): return a+b,0) > before: count += 1
			if light == 90: bright_drops += count
			else: dark_drops += count
	check(dark_drops > bright_drops,"dark floors drop more essences (%d vs %d)" % [dark_drops,bright_drops])

	# Enemy damage bonus per tier.
	for row in [[90,7],[50,8],[20,9]]:
		var s = solo()
		var foe: Dictionary = s.enemies[0]; foe.hp = 20; foe.alert = true
		s.party[0].pos = foe.pos+Vector2i.LEFT; s.light = row[0]; s.floor_state.observe(s)
		var hp: int = s.party[0].hp
		MonsterAI.strike(s,foe,s.party[0],7)
		check(s.party[0].hp == hp-row[1],"melee strike at light %d deals %d" % [row[0],row[1]])

	# Ambush: in the dark, an enemy seen for the first time acts at once.
	for light in [90,20]:
		var s = solo()
		var hero: Dictionary = s.party[0]
		var foe: Dictionary = s.enemies.filter(func(e): return e.role == "MELEE")[0]
		s.light = light
		var c := Fixture.arena(s,6)
		foe.hp = 20; foe.alert = false
		foe.pos = c+Vector2i(1,0)
		s.floor_state.seen_enemies.clear(); s.floor_state.observe(s)
		var hp: int = hero.hp
		s.act("WAIT",hero.pos)
		# Ordinary round: one strike. Dark: an extra strike the moment the foe is sighted.
		var lost: int = hp-hero.hp
		if light == 90: check(lost == 7,"bright first contact is one ordinary enemy turn (%d)" % lost)
		else: check(lost == 18,"dark first contact ambushes with an extra action (%d)" % lost)
		hp = hero.hp; s.act("WAIT",hero.pos)
		check(hp-hero.hp <= 9,"ambush happens only on first sight")

	# Decay: one light per four rounds, food unchanged.
	var s = solo()
	var light: int = s.light; var food: int = s.food
	for i in range(20): s.act("WAIT",s.party[0].pos)
	check(s.light == light-5 and s.food == food-1,"light drains one per four rounds, food one per twenty")
	print("Torch tradeoff: %d failures" % failures); quit(1 if failures else 0)
