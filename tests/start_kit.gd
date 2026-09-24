extends SceneTree
## The run's first choice: one of ten kits, one per mastery axis.
const Session = preload("res://expedition/session.gd")
const Stats = preload("res://expedition/combat_stats.gd")
const Mastery = preload("res://expedition/mastery.gd")
const Spells = preload("res://expedition/spells.gd")
const Recruit = preload("res://expedition/npc_recruit.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	var kits: Array = Stats.kits()
	check(kits.size() == 10,"ten kits")
	check(kits.map(func(k): return str(k.id)) == Mastery.AXES,"kit ids are the mastery axes in order")
	for kit in kits:
		check(Stats.content.weapons.has(str(kit.weapon)),"kit %s carries a real weapon" % kit.id)
		check(str(kit.spell).is_empty() or Stats.content.spells.has(str(kit.spell)),"kit %s knows a real spell" % kit.id)
	# Every kit departs with its own weapon, a robe and rank 1 in its axis.
	for kit in kits:
		var id: String = str(kit.id)
		var s = Session.new_run(7,id)
		check(s != null,"run departs with kit "+id)
		if s == null: continue
		var hero: Dictionary = s.party[0]
		check(s.kit_id == id,"session remembers kit "+id)
		check(str(hero.gear.weapon.type) == str(kit.weapon),"%s holds %s" % [id,kit.weapon])
		check(str(hero.gear.armour.type) == "robe","%s wears a robe" % id)
		check(int(hero.skill_xp.get(str(kit.axis),0)) == 25,"%s starts with 25 xp in %s" % [id,kit.axis])
		check(Mastery.rank(hero,str(kit.axis)) == 1,"%s starts at rank 1" % id)
		var spell: String = str(kit.spell)
		if spell.is_empty():
			check(hero.spells.is_empty() and hero.prepared.is_empty(),"%s knows no spell" % id)
		else:
			check(hero.spells == [spell] and hero.prepared == [spell],"%s knows and prepares %s" % [id,spell])
		var stats: Dictionary = Stats.stats(s,hero)
		check(int(stats.range) == int(Stats.content.weapons[str(kit.weapon)].range),"%s reaches as far as its weapon" % id)
	# The weapon really is behind the numbers.
	var mace = Session.new_run(7,"mace")
	check(int(Stats.stats(mace,mace.party[0]).delay) == 145-4,"mace swings at its own delay, rank 1 faster")
	var bow = Session.new_run(7,"bow")
	check(int(Stats.stats(bow,bow.party[0]).range) == 6,"bow reaches six cells")
	var fire = Session.new_run(7,"fire")
	check(int(Stats.stats(fire,fire.party[0]).power) >= 4,"a staff focuses")
	check(str(Stats.stats(fire,fire.party[0]).trait) == "focus","staff trait is focus")
	# An id nobody offers is refused, both ways in.
	check(Session.new_run(7,"wizard") == null,"unknown kit refuses a run")
	var manual = Session.new(7,false,false,true,1)
	manual.kit_id = "wizard"
	check(not manual.depart(),"unknown kit refuses to depart")
	check(manual.phase == "IDLE","a refused departure leaves the session idle")
	check(Stats.kit("wizard").is_empty(),"unknown kit is not in the table")
	await process_frame
	for kit in kits:
		if str(kit.spell).is_empty(): continue
		await magic(str(kit.id),str(kit.spell))
	await summoned_hound()
	await start_screen()
	print("Start kit: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## Each magic kit's first spell, cast at a foe two cells east in an open arena.
func magic(id: String, spell: String) -> void:
	var s = Session.new_run(11,id)
	var centre: Vector2i = Fixture.arena(s,10)
	var hero: Dictionary = s.party[0]
	hero.mp = 18
	var foe: Dictionary = s.enemies[0] if not s.enemies.is_empty() else {}
	check(not foe.is_empty(),"%s fixture has a foe" % id)
	if foe.is_empty(): return
	foe.hp = 100; foe.max_hp = 100; foe.pos = centre+Vector2i(2,0); foe.alert = true; foe.ready_at = 9000
	for other in s.enemies:
		if other.id != foe.id: other.hp = 0
	s.floor_state.observe(s)
	var target: Vector2i = foe.pos if spell != "hound" else hero.pos
	check(Spells.can_cast(s,hero,spell,target),"%s can cast %s" % [id,spell])
	# The kit's own rank is enough to cast; a mastered caster never fumbles, so
	# what the spell does is what the check below reads.
	hero.skill_xp[str(Stats.content.spells[spell].school)] = 2500
	var before: int = foe.hp
	var lines: int = s.log_lines.size()
	check(s.cast(spell,target),"%s casts %s" % [id,spell])
	check(hero.mp < 18,"%s spends MP on %s" % [id,spell])
	match spell:
		"bolt", "cone", "cloud":
			check(foe.hp < before,"%s wounds the foe" % spell)
			if spell == "cone": check(foe.statuses.has("slow") or foe.hp <= 0,"서리 부채 slows what it hits")
		"confuse":
			var resisted: bool = s.log_lines.slice(lines).any(func(line): return str(line).ends_with("저항"))
			check(foe.statuses.has("confuse") or resisted,"혼란 lands or is resisted aloud")
		"hound":
			var pets: Array = s.npcs.filter(func(n): return bool(n.get("summoned",false)))
			check(pets.size() == 1,"one hound answers")
			if not pets.is_empty():
				check(s.melee_reach(hero.pos,pets[0].pos),"the hound stands beside the hero")
				check(bool(pets[0].awake) and bool(pets[0].npc),"the hound is an awake npc")
				check(pets[0] in s.friends(),"the hound counts as a friend")

## The hound belongs to nobody but the spell: it cannot be recruited, never
## shows in the run's history, and goes when its three hundred ticks are up.
func summoned_hound() -> void:
	var s = Session.new_run(13,"summon")
	Fixture.arena(s,10)
	var hero: Dictionary = s.party[0]
	hero.mp = 18
	for enemy in s.enemies: enemy.hp = 0
	s.floor_state.observe(s)
	var born: int = s.time
	check(s.cast("hound",hero.pos),"the hound is summoned")
	var pets: Array = s.npcs.filter(func(n): return bool(n.get("summoned",false)))
	check(pets.size() == 1,"exactly one hound")
	if pets.is_empty(): return
	var pet: Dictionary = pets[0]
	check(int(pet.expires_at) == born+300,"the hound lasts three hundred ticks")
	s.phase = "EXPLORE"
	check(Recruit.can_aid(s,pet) != "","a summon takes no food")
	check(not Recruit.propose(s,pet).accepted,"a summon will not join")
	check(not s.offer(pet),"a summon never asks to join")
	check(s.companion_rows().all(func(r): return str(r.name) != "사냥개"),"the hound is not a companion of record")
	check(s.roster.all(func(n): return not bool(n.get("summoned",false))),"the hound is not on the roster")
	# Walk the clock past its span; the environment tick clears it.
	for i in range(6):
		if s.party[0].hp <= 0: break
		s.act("WAIT",s.party[0].pos)
	check(s.time >= born+300,"the clock ran past the hound's span")
	check(s.npcs.all(func(n): return not bool(n.get("summoned",false))),"the hound is gone when it expires")
	check(pet.hp == 0,"the expired hound is down")

## The picker on the start screen, and the run it starts.
func start_screen() -> void:
	var main = load("res://expedition/main.tscn").instantiate()
	root.add_child(main); await process_frame
	var picker: Node = main.find_child("KitPick",true,false)
	check(picker != null,"start screen has a kit picker")
	if picker == null: main.queue_free(); return
	for kit in Stats.kits():
		check(main.find_child("Kit_"+str(kit.id),true,false) != null,"picker offers "+str(kit.id))
	check(main.kit_choice == "sword","sword is the default kit")
	var sword: Button = main.find_child("Kit_sword",true,false)
	check(sword.get_theme_stylebox("normal").border_color == Color("e9c575"),"the chosen kit wears the gold border")
	var bow: Button = main.find_child("Kit_bow",true,false)
	check(bow.custom_minimum_size.y >= 44,"kit buttons stay thumb-sized")
	bow.pressed.emit(); await process_frame
	check(main.kit_choice == "bow","pressing a kit chooses it")
	main.find_child("NewRun",true,false).pressed.emit(); await process_frame
	check(main.session != null and str(main.session.party[0].gear.weapon.type) == "bow","the run departs with the chosen bow")
	# A defeat hands the picker back.
	main.session.party[0].hp = 0; main.session.check_battle_end(); main.refresh(); await process_frame
	check(main.find_child("ResultCard",true,false) != null,"result card after a defeat")
	main.find_child("NewRun",true,false).pressed.emit(); await process_frame
	check(main.find_child("KitPick",true,false) != null,"the result card hands the picker back")
	main.queue_free(); await process_frame
