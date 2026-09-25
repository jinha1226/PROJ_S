extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Floor = preload("res://expedition/level/continuous_floor.gd")
const Generator = preload("res://expedition/level/floor_generator.gd")
const Zones = preload("res://expedition/level/zones.gd")
const Common = preload("res://expedition/actors/bosses/boss_common.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for depth in [3,6,9,12]:
		var theme: Dictionary = Floor.theme_for(depth)
		var template: String = Zones.boss_template(Zones.zone_of(depth))
		check(bool(theme.boss) and template in theme.templates.required,"boss theme %d" % depth)
		for seed in range(10):
			var layout: Dictionary = Generator.generate(theme,seed,depth)
			check(Generator.validate(layout,theme).is_empty(),"valid boss layout %d seed %d" % [depth,seed])
			check(layout.npc_rooms.is_empty(),"no ordinary NPC rooms on boss floor")
			check(layout.rooms.any(func(r): return str(r.template_id) == template),"boss room template %d" % depth)
		var s = Session.new(7,false,false,true,1)
		s.depart(); s.depth = depth; s.floor_state.build(s); s.NpcRoster.place(s)
		var bosses: Array = (s.enemies+s.npcs).filter(func(e): return e.get("boss",false))
		check(bosses.size() == 1,"one boss %d" % depth)
		if bosses.is_empty(): continue
		var boss: Dictionary = bosses[0]
		check(int(boss.max_hp) >= Common.boss_hp(depth),"zone boss health %d" % depth)
		check(s.enemies.filter(func(e): return not e.get("boss",false)).all(func(e): return e.pos != boss.pos),"boss spawn has its own cell")
		check(s.enemies.size() > 1,"boss floor keeps ordinary encounters")
		check(s.stairs_sealed(),"stairs sealed while boss lives")
		if depth == 3:
			check(s.enemies.filter(func(e): return int(e.get("chief",-1)) == int(boss.id)).size() == 4,"chief's four guards")
		elif depth == 6:
			check(s.floor_state.features.values().filter(func(f): return str(f.get("kind","")) == "lever").size() == 3,"foundry levers")
		elif depth == 9:
			check(s.enemies.filter(func(e): return int(e.get("bound_to",-1)) == int(boss.id)).size() == 4,"eater's four bound")
		else:
			check(bool(boss.get("fallen",false)) and not bool(boss.enemy) and bool(boss.hostile),"last boss is a hostile NPC")
		boss.hp = 0
		check(not s.stairs_sealed(),"stairs unsealed after boss falls")
	print("Boss floor: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
