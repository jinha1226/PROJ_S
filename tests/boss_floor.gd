extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for depth in [3,6,9]:
		var theme: Dictionary = Floor.theme_for(depth)
		check(theme.boss and "boss_lair" in theme.templates.required,"boss theme %d" % depth)
		for seed in range(10):
			var layout: Dictionary = Generator.generate(theme,seed,depth)
			check(Generator.validate(layout,theme).is_empty(),"valid boss layout %d seed %d" % [depth,seed])
			check(layout.npc_rooms.is_empty(),"no NPC rooms")
		var s = Session.new(7,false,false,true,1); s.depth = depth; s.floor_state.build(s)
		var bosses: Array = s.enemies.filter(func(e): return e.get("boss",false))
		check(bosses.size() == 1,"one boss %d" % depth)
		if bosses.is_empty(): continue
		var boss: Dictionary = bosses[0]
		check(boss.pattern == (depth/3-1)%3,"pattern %d" % depth)
		check(boss.hp == 64+8*(depth/3-1),"boss health scales with depth")
		check(s.enemies.filter(func(e): return not e.get("boss",false)).all(func(e): return e.pos != boss.pos),"boss spawn does not overlap the ordinary roster")
		check(s.enemies.size() > 1,"boss floor keeps ordinary encounters")
		check(s.stairs_sealed(),"stairs sealed")
		boss.hp = 0
		check(not s.stairs_sealed(),"stairs unsealed")
	patterns()
	print("Boss floor: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func patterns() -> void:
	var s = Session.new(3,false,false,true,1); s.depth = 3; s.floor_state.build(s)
	for enemy in s.enemies: if not enemy.get("boss",false): enemy.hp = 0
	var boss: Dictionary = s.enemies.filter(func(e): return e.get("boss",false))[0]
	boss.pos = s.party[0].pos+Vector2i.RIGHT; boss.alert = true; boss.cooldown = 0
	s.floor_state.observe(s)
	s.plan_enemies()
	check(boss.charging and s.intents.any(func(i): return i.id == boss.id and i.kind == "BOSS"),"goo intent")
	var hp: int = s.party[0].hp
	s.end_round(); check(s.intents.any(func(i): return i.id == boss.id),"intent persists through fuse")
	s.end_round(); check(s.party[0].hp < hp,"goo blast lands")
	var giant = Session.new(5,false,false,true,1); giant.depth = 9; giant.floor_state.build(giant)
	for enemy in giant.enemies: if not enemy.get("boss",false): enemy.hp = 0
	boss = giant.enemies.filter(func(e): return e.get("boss",false))[0]
	boss.hp = boss.max_hp/2; giant.plan_enemies()
	check(boss.shield and boss.pylon.x >= 0,"giant shield")
	hp = boss.hp; giant.damage(boss,10,0,"SLASH")
	check(boss.hp == hp,"shield blocks")
	giant.party[0].pos = boss.pylon+Vector2i.RIGHT; giant.party[0].ap = 1; giant.floor_state.observe(giant)
	check(giant.act("PYLON",boss.pylon) and not boss.shield,"pylon disables shield")
