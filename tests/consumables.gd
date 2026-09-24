extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Consumables = preload("res://expedition/items/consumables.gd")
var checks := 0
var failures := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	check(Consumables.potions().size() == 8 and Consumables.scrolls().size() == 8,"16 catalog entries")
	check(Consumables.kinds().size() == 16 and Consumables.kinds().duplicate().all(func(k): return int(Consumables.definition(k).weight) > 0),"every item has a weight")
	check(Consumables.content.appearances.potion.size() == 10 and Consumables.content.appearances.scroll.size() == 10,"ten appearances each")
	var looks: Dictionary = Consumables.shuffle_appearances(91)
	check(looks == Consumables.shuffle_appearances(91) and looks != Consumables.shuffle_appearances(92),"seeded appearance shuffle")
	check(looks.values().size() == looks.values().duplicate().reduce(func(a,b): return a if b in a else a+[b],[]).size(),"distinct appearances")
	for seed in range(3):
		var floor = Session.new_run(seed+10)
		var drops: Array = floor.floor_state.features.values().filter(func(f): return f.kind == "item")
		check(drops.size() >= 4 and drops.size() <= 6,"floor drops 4-6 items")
	var s = Session.new_run(57)
	var c: Vector2i = Fixture.arena(s,10)
	var hero: Dictionary = s.party[0]
	s.floor_state.features[c+Vector2i.RIGHT] = {"kind":"item","item_id":"healing"}
	check(s.act("MOVE",c+Vector2i.RIGHT) and int(s.bag.get("healing",0)) == 1 and not s.floor_state.features.has(c+Vector2i.RIGHT),"step picks up bottle")
	check(s.item_label("healing") == looks.healing or s.item_label("healing") != "치유 물약","unidentified label hides kind")
	hero.hp = 30; hero.ap = 1
	check(s.use_item("healing") and hero.hp == 50 and s.known.has("healing") and not s.bag.has("healing"),"drinking heals and identifies")
	s.grant_item("healing"); hero.hp = hero.max_hp; hero.ap = 1
	check(not s.use_item("healing") and s.bag.healing == 1,"full health does not waste healing")
	s.grant_item("identify"); s.grant_item("frost")
	hero.ap = 1
	check(s.use_item("identify") and s.known.has("identify") and not s.pending_choice.is_empty(),"identify scroll asks for a kind")
	check(not s.act("WAIT",hero.pos) and not s.use_item("healing"),"choice blocks other actions")
	check(s.resolve_choice("frost") and s.known.has("frost") and s.pending_choice.is_empty(),"choice identifies only selected kind")
	s.grant_item("upgrade",1,true); hero.ap = 1
	check(s.use_item("upgrade") and s.pending_choice.kind == "upgrade","upgrade asks for gear")
	var enchant: int = int(hero.gear.weapon.enchant)
	check(s.resolve_choice("weapon") and int(hero.gear.weapon.enchant) == enchant+1,"upgrade adds enchant")
	s.grant_item("toxic_gas",1,true); hero.ap = 1
	check(s.use_item("toxic_gas") and hero.statuses.has("poison"),"harmful potion poisons drinker")
	s.grant_item("liquid_flame",1,true); hero.ap = 1
	var wood: Vector2i = hero.pos+Vector2i.RIGHT
	s.tile(wood).terrain = "wood"
	check(not s.use_item("liquid_flame",hero.pos+Vector2i(6,0)) and s.bag.liquid_flame == 1,"throw range gate")
	check(s.use_item("liquid_flame",wood) and s.tile(wood).fire > 0,"thrown flame lights wood")
	s.grant_item("magic_mapping",1,true); hero.ap = 1
	check(s.use_item("magic_mapping") and s.floor_state.explored.has(wood),"mapping reveals floor")
	s.grant_item("mirror_image",1,true); hero.ap = 1
	var before: int = s.npcs.size()
	check(s.use_item("mirror_image") and s.npcs.size() == before+2,"mirror image summons two allies")
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	root.add_child(scene); await process_frame
	scene.session = s; s.grant_item("identify",1,true); s.grant_item("strength")
	scene.refresh(); await process_frame
	scene.run_action(func(): return s.use_item("identify")); await process_frame
	check(not s.pending_choice.is_empty() and scene.details_popup.visible,"scroll opens its required choice")
	var choices: Array = scene.modal_content.find_children("*","Button",true,false)
	var strength: Array = choices.filter(func(b): return b.text == s.appearances.strength)
	check(strength.size() == 1,"choice uses unknown appearance")
	if not strength.is_empty(): strength[0].pressed.emit(); await process_frame
	check(s.pending_choice.is_empty() and s.known.has("strength"),"choice popup resolves identification")
	scene.queue_free(); await process_frame
	var probe = Session.new_run(58)
	var origin: Vector2i = Fixture.arena(probe,12)
	var actor: Dictionary = probe.party[0]
	var foe: Dictionary = probe.make_actor(100,"적",true)
	foe.pos = origin+Vector2i(2,0); foe.hp = 20; foe.max_hp = 20; foe.alert = true
	probe.enemies.append(foe); probe.floor_state.observe(probe)
	probe.grant_item("lullaby",1,true)
	check(probe.use_item("lullaby") and int(foe.sleep_until) > probe.time and not foe.alert,"lullaby sleeps visible foe")
	probe.damage(foe,1,actor.id,"SLASH")
	check(int(foe.sleep_until) == 0,"damage wakes sleeping foe")
	foe.hp = 0; probe.floor_state.observe(probe)
	probe.grant_item("recharging",1,true); actor.mp = 2; actor.ap = 1
	check(probe.use_item("recharging") and actor.mp == actor.max_mp,"recharging restores MP")
	probe.grant_item("strength",1,true); actor.ap = 1
	var damage_before: int = int(Session.CombatStats.stats(probe,actor).damage)
	check(probe.use_item("strength") and actor.str_bonus == 3 and actor.max_hp == 60 and int(Session.CombatStats.stats(probe,actor).damage) >= damage_before,"strength changes body and combat stats")
	probe.grant_item("teleportation",1,true); actor.ap = 1
	var place: Vector2i = actor.pos
	check(probe.use_item("teleportation") and absi(actor.pos.x-place.x)+absi(actor.pos.y-place.y) >= 12,"teleport goes to distant floor cell")
	print("Consumables: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
