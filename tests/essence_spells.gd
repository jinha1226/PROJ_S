extends SceneTree
## Spells come from caster essences: the tier sets the reach, the mind and the
## tier set the failure, and no book is left anywhere.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	kits(); tiers(); failure(); casting(); no_books()
	print("Essence spells: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func kits() -> void:
	for school in Essences.CASTER_BY_SCHOOL:
		var s = Session.new_run(7,school); var hero: Dictionary = s.party[0]
		var essence: String = str(Essences.CASTER_BY_SCHOOL[school])
		check(int(hero.essences.get(essence,0)) == 1 and hero.equipped_abilities[0] == essence,"the %s kit starts with its caster essence slotted" % school)
		check(hero.prepared == ["%s_1" % school] and hero.spells == ["%s_1" % school],"the %s kit has its first spell ready" % school)
		check(not hero.has("books"),"the %s kit carries no book" % school)
	var sword = Session.new_run(7,"sword")
	check(sword.party[0].essences.is_empty() and sword.party[0].prepared.is_empty(),"a swordsman starts with no essence and no spell")
	var fire = Session.new_run(7,"fire")
	check(int(fire.party[0].max_mp) == 18+2,"the fire kit's essence lends two MP")

func tiers() -> void:
	var s = Session.new_run(7,"fire"); var hero: Dictionary = s.party[0]
	s.phase = "CAMP"
	check(Essences.spell_choices(hero,"FIRE_CALLER") == ["fire_1","fire_2","fire_3"],"tier one reaches the third level")
	check(not s.choose_essence_spell(0,"FIRE_CALLER","fire_4"),"the fourth is out of reach")
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_3") and hero.prepared == ["fire_3"],"a chosen spell is the one ready")
	s.parts_bag["FIRE_CALLER"] = 1
	check(s.absorb_essence(0,"FIRE_CALLER") == "" and Essences.spell_choices(hero,"FIRE_CALLER").size() == 6,"tier two reaches the sixth")
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_6") and hero.prepared == ["fire_6"],"and takes it")
	s.parts_bag["GOBLIN_HEXER"] = 1
	check(s.absorb_essence(0,"GOBLIN_HEXER") == "" and hero.essence_spells.GOBLIN_HEXER == "hex_1","a new caster essence picks its first spell")
	check("hex_1" in hero.spells and "hex_1" not in hero.prepared,"known, but not ready until it is slotted")
	s.gain_level_xp(hero,65)
	check(s.equip_part(0,1,"GOBLIN_HEXER") and hero.prepared == ["fire_6","hex_1"],"slotted, it is ready in slot order")
	check(s.unequip_part(0,0) and hero.prepared == ["hex_1"],"unslotted, its spell goes")
	check(not s.choose_essence_spell(0,"FROST_IMP","ice_1"),"an essence the hero never absorbed has no choice")
	s.gain_level_xp(hero,999999)
	for id in ["FIRE_CALLER","FROST_IMP","STORM_BAT","GNOLL_SUMMONER","FIRE_CALLER@ice","FROST_IMP@fire"]:
		hero.essences[id] = maxi(1,int(hero.essences.get(id,0)))
		hero.essence_spells[id] = Essences.spell_choices(hero,id)[0]
	hero.equipped_abilities = ["FIRE_CALLER","FROST_IMP","STORM_BAT","GNOLL_SUMMONER","FIRE_CALLER@ice","FROST_IMP@fire","GOBLIN_HEXER","","",""]
	Essences.sync_spells(hero)
	check(hero.prepared.size() == Essences.READY_SPELLS and s.PREPARED_SLOTS == Essences.READY_SPELLS,"no more than five stand ready")

func failure() -> void:
	var s = Session.new_run(7,"fire"); var hero: Dictionary = s.party[0]
	hero.essences = {"FIRE_CALLER":2}; hero.equipped_abilities = ["FIRE_CALLER"]
	check(Spells.failure(s,hero,"fire_6") == 8+54-16-20,"level six at tier two with sixteen mind")
	hero.level = 3; hero.essences = {"FIRE_CALLER":2,"FROST_IMP":1,"GOBLIN_HEXER":1}
	hero.equipped_abilities = ["FIRE_CALLER","FROST_IMP","GOBLIN_HEXER"]
	check(Spells.failure(s,hero,"fire_6") == 8+54-20-20-10,"술사 3 takes ten more off")
	hero.essences = {"FIRE_CALLER":3}; hero.equipped_abilities = ["FIRE_CALLER","",""]
	check(Spells.failure(s,hero,"fire_1") == 0,"a mastered caster never fumbles an easy spell")
	check(Spells.failure(s,hero,"ice_1") == clampi(8+9-18,0,85),"another school has no tier to lean on")

func casting() -> void:
	var s = Session.new_run(7,"fire"); var hero: Dictionary = s.party[0]
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.pos = c+Vector2i(2,0)
	s.floor_state.observe(s)
	hero.essences.FIRE_CALLER = 3
	check(Spells.can_cast(s,hero,"fire_1",foe.pos),"the kit spell casts with no book")
	check(s.cast("fire_1",foe.pos) and int(foe.hp) < 30,"and burns the foe")

func no_books() -> void:
	check(not Stats.content.has("books") and not Stats.content.loot.has("books"),"no books in the data")
	check(Stats.content.spells.values().all(func(row): return not row.has("book")),"no spell names a book")
	var s = Session.new_run(9,"fire")
	for method in ["learn_spell","prepare_spell","grant_book","book_tier","random_book"]:
		check(not s.has_method(method),"the session has no "+method)
	var source: String = FileAccess.get_file_as_string("res://expedition/spells/spells.gd")
	check(not source.contains("func learnable") and not source.contains("func book"),"spells have no book helpers")
	s.grant_part("FROST_IMP")
	check(int(s.parts_bag.get("FROST_IMP",0)) == 1 and s.log_lines[-1].contains(Essences.title("FROST_IMP")),"a caster essence can be found like any other")
