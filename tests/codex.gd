extends SceneTree
## The codex (2026-09-26 codex spec §1–2): one file across runs, written only
## by real runs, broken files set aside, unknown keys kept.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Gear = preload("res://expedition/items/gear.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Codex = preload("res://expedition/progression/codex.gd")
var failures := 0
var checks := 0

class FakeSession:
	var codex: Dictionary = {}
	var records_codex := true
	var codex_dirty := false
	var depth := 1
	var codex_test_stones: Dictionary = {}
	var codex_run_ended := false

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	Codex.path = "user://test_codex_codex.json"
	wipe()
	fresh(); round_trip(); broken(); unknown_keys(); keys(); records(); off(); real_run(); not_real(); entries(); extended()
	wipe()
	var affix_session = Session.new_run(44)
	affix_session.records_codex = true; affix_session.codex = Codex.empty()
	Codex.note_affix(affix_session,"GEAR_AMP_1")
	check(int(affix_session.codex.affixes.GEAR_AMP_1.found) == 1,"an acquired gear option is recorded")
	var groups := Codex.item_rows(affix_session.codex)
	check(groups.filter(func(g): return g.group == "affixes")[0].rows.size() == 1,"only discovered options are shown")
	affix_session.records_codex = false; Codex.note_affix(affix_session,"GEAR_AMP_2")
	check(not affix_session.codex.affixes.has("GEAR_AMP_2"),"test gear never records an option")
	var legacy: Dictionary = Codex.empty(); legacy.erase("affixes"); legacy.future = {"keep":true}
	check(Codex.write(legacy),"a legacy version-one codex writes")
	var migrated := Codex.read()
	check(migrated.affixes.is_empty() and bool(migrated.future.keep),"old codex adds an empty affix section and preserves unknown keys")
	check(Codex.write(affix_session.codex) and int(Codex.read().affixes.GEAR_AMP_1.found) == 1,"options persist across runs")
	var bosses_book := Codex.empty()
	bosses_book.monsters["boss:golem"] = {"seen":true}
	var boss_stone := Codex.stone_entry(bosses_book,"FURNACE_HEART")
	check(boss_stone.species_known and boss_stone.name == "용광로 심장" and boss_stone.group == "TANK","boss stones have a name and filter group after discovery")
	check(boss_stone.text.contains("최대 HP +20") and boss_stone.text.contains("방어 +3"),"effectless boss stones show their actual base stats")
	wipe()

	print("Codex: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func wipe() -> void:
	for p in [Codex.path,Codex.bad_path()]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func session() -> FakeSession:
	var s := FakeSession.new(); s.codex = Codex.read(); return s

func fresh() -> void:
	wipe()
	var data := Codex.read()
	check(data == Codex.empty(),"no file reads as an empty codex")
	check(not FileAccess.file_exists(Codex.path),"reading does not create the file")

func round_trip() -> void:
	wipe()
	var s := session()
	Codex.note_kill(s,{"species_id":"dcss_rat","enemy":true})
	check(s.codex_dirty,"a note marks the codex dirty")
	Codex.flush(s)
	check(FileAccess.file_exists(Codex.path) and not s.codex_dirty,"flush writes and clears dirty")
	check(int(Codex.read().monsters.dcss_rat.kills) == 1,"the kill survives the round trip")

func broken() -> void:
	wipe()
	var f := FileAccess.open(Codex.path,FileAccess.WRITE); f.store_string("{ not json"); f.close()
	var data := Codex.read()
	check(data == Codex.empty(),"a broken file reads as empty")
	check(FileAccess.file_exists(Codex.bad_path()) and not FileAccess.file_exists(Codex.path),"the broken file is set aside")

func unknown_keys() -> void:
	wipe()
	var start := Codex.empty(); start["future"] = {"x":1}
	Codex.write(start)
	var s := session()
	Codex.note_kill(s,{"species_id":"dcss_rat","enemy":true}); Codex.flush(s)
	check(int(Codex.read().get("future",{}).get("x",0)) == 1,"an unknown key is kept")

func keys() -> void:
	check(Codex.monster_key({"species_id":"dcss_rat"}) == "dcss_rat","a monster is its species")
	check(Codex.monster_key({"species_id":"goblin","boss":true,"boss_kind":"chief"}) == "boss:chief","a boss is its kind")
	check(Codex.stone_key("SPIDER_WEB/pierced@poison") == "SPIDER_WEB/pierced","a variant stone keys without its element")
	check(Codex.stone_key("RAT_GNAW") == "RAT_GNAW/cut","a bare id keys as its headline part")
	check(Codex.stone_key("no_such") == "","an unknown stone has no key")

func records() -> void:
	wipe()
	var s := session()
	var rat := {"species_id":"dcss_rat","enemy":true,"variant_element":"poison"}
	Codex.note_seen(s,rat); s.codex_dirty = false
	Codex.note_seen(s,rat)
	check(not s.codex_dirty,"seeing the same thing again changes nothing")
	check(s.codex.monsters.dcss_rat.seen and s.codex.monsters.dcss_rat.variants == ["poison"],"seen with its variant once")
	Codex.note_stone(s,"SPIDER_WEB/pierced@poison"); Codex.note_stone(s,"SPIDER_WEB/pierced")
	check(int(s.codex.stones["SPIDER_WEB/pierced"].found) == 2 and s.codex.stones["SPIDER_WEB/pierced"].variants == ["poison"],"stones pile under one key")
	Codex.note_absorb(s,"SPIDER_WEB/pierced")
	check(bool(s.codex.stones["SPIDER_WEB/pierced"].absorbed),"absorbed is kept")
	Codex.note_unrand(s,"blood_axe")
	check(int(s.codex.unrands.blood_axe.found) == 1,"an unrand is counted")
	s.depth = 7; Codex.note_run_end(s)
	check(int(s.codex.runs) == 1 and int(s.codex.deepest) == 7,"a run end counts the run and the depth")

func off() -> void:
	wipe()
	var s := session(); s.records_codex = false
	Codex.note_kill(s,{"species_id":"dcss_rat","enemy":true}); Codex.note_stone(s,"RAT_GNAW")
	Codex.flush(s)
	check(s.codex == Codex.empty() and not FileAccess.file_exists(Codex.path),"a session that does not record writes nothing")

func real_session():
	var s = Session.new_run(731)
	s.records_codex = true; s.codex = Codex.read()
	return s

func real_run() -> void:
	wipe()
	var s = real_session()
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	# No stone on the kill itself: the drop below is rolled by hand.
	foe.hp = 5; foe.max_hp = 5; foe.pos = c+Vector2i(1,0); foe.species_id = "dcss_rat"; foe.variant_element = ""; foe.part_id = ""
	s.floor_state.observe(s)
	check(bool(s.codex.monsters.get("dcss_rat",{}).get("seen",false)),"a monster in sight is seen")
	s.codex_dirty = false
	s.floor_state.observe(s)
	check(not s.codex_dirty,"looking again at the same monster changes nothing")
	s.Reactions.begin_action(s)
	s.damage(foe,50,int(s.party[0].id),"physical")
	check(int(s.codex.monsters.dcss_rat.kills) == 1,"a party kill is counted")
	s.parts_bag.clear()
	foe.part_id = "RAT_GNAW"; foe.erase("part_rolled"); s.essence_seen.clear()
	Gear.roll_part(s,foe)
	var got: Array = s.parts_bag.keys()
	check(got.size() == 1 and int(s.codex.stones.get(Codex.stone_key(str(got[0])),{}).get("found",0)) == 1,"a dropped stone is found")
	s.phase = "CAMP"
	check(Essences.absorb(s,s.party[0],str(got[0])) == "","the stone is absorbed")
	check(bool(s.codex.stones[Codex.stone_key(str(got[0]))].absorbed),"an absorbed stone is marked")

func not_real() -> void:
	wipe()
	var s = Session.new_run(731)
	check(not s.records_codex,"a session does not record unless told")
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 5; foe.pos = c+Vector2i(1,0); foe.species_id = "dcss_rat"
	s.floor_state.observe(s)
	s.damage(foe,50,int(s.party[0].id),"physical")
	Gear.grant_test_loadout(s)
	Codex.flush(s)
	check(not FileAccess.file_exists(Codex.path),"a test session leaves no codex file")

func entries() -> void:
	var data := Codex.empty()
	var rat := Codex.monster_entry(data,"dcss_rat")
	check(not rat.known and int(rat.zone) == 1 and not rat.has("name"),"an unseen monster shows only its zone")
	data.monsters["dcss_rat"] = {"seen":true,"kills":3,"variants":["poison"]}
	rat = Codex.monster_entry(data,"dcss_rat")
	check(rat.known and rat.name == "쥐" and int(rat.kills) == 3,"a seen monster shows its name and kills")
	check(rat.parts.size() == 3 and rat.parts.map(func(p): return p.form) == ["SLASH","IMPACT","PIERCE"],"its three parts in form order")
	check(rat.body_line.begins_with("공격 "),"its body line")
	var locked := Codex.stone_entry(data,"RAT_GNAW/broken")
	check(not locked.found and locked.species_known and locked.hint == "타격으로 마무리","a locked part of a seen species hints its form")
	var hidden := Codex.stone_entry(Codex.empty(),"RAT_GNAW/broken")
	check(not hidden.species_known and hidden.name == "???","a part of an unseen species hides its name")
	data.stones["RAT_GNAW/cut"] = {"found":1,"absorbed":false,"variants":[]}
	var got := Codex.stone_entry(data,"RAT_GNAW/cut")
	check(got.found and not got.text.is_empty() and not got.subtype.is_empty(),"a found part shows its effect and subtype")
	var done := Codex.completion(data)
	check(int(done.monsters[0]) == 1 and int(done.monsters[1]) == Codex.monster_list().size(),"monster completion")
	check(int(done.stones[0]) == 1 and int(done.stones[1]) == Codex.stone_list().size(),"stone completion")
	check(Codex.monster_list().filter(func(m): return m.boss).size() == 4,"four bosses on the monster list")

func extended() -> void:
	wipe()
	var s = real_session()
	Gear.grant_gear(s,{"type":"axe","unrand":"AXE"})
	check(int(s.codex.unrands.AXE.found) == 1,"actual unrand grant records the uppercase content id")
	check(Codex.unrand_ids().size() == 12,"all twelve artifact rows are catalogued")
	check(Codex.unrand_entry(s.codex,"AXE").name == "피 먹는 도끼","artifact has localized name")
	check(not Codex.unrand_entry(s.codex,"AXE").text.is_empty(),"known artifact includes both effect and cost")
	check(Codex.unrand_entry(Codex.empty(),"AXE").name == "???","unknown artifact hides its name")
	Codex.note_run_end(s); Codex.note_run_end(s)
	check(int(s.codex.runs) == 1,"run completion is counted exactly once")
	Codex.flush(s); var after := Codex.read()
	check(int(after.runs) == 1 and not FileAccess.file_exists(Codex.path+".tmp"),"atomic flush leaves a complete file")
	var before: int = int(after.stones.size())
	Gear.grant_test_loadout(s); s.phase = "CAMP"
	Essences.absorb(s,s.party[0],"RAT_GNAW/broken")
	check(s.codex.stones.size() == before,"debug stones and their absorption do not count")
	Gear.grant_part(s,"RAT_GNAW/broken")
	check(int(s.codex.stones["RAT_GNAW/broken"].found) == 1,"real acquisition after debug grant counts")
	# The final boss is an NPC, not an entry in s.enemies.
	var c: Vector2i = Fixture.arena(s,8)
	var fallen: Dictionary = s.make_actor(950,"타락한 모험가",false)
	fallen.merge({"hp":5,"max_hp":5,"pos":c+Vector2i(1,0),"boss":true,"boss_kind":"fallen","fallen":true,"hostile":true,"npc":true,"roster_id":-1,"defeated":false,"gear_rewarded":true,"memory_kind":""},true)
	s.npcs.append(fallen); s.floor_state.observe(s)
	check(bool(s.codex.monsters.get("boss:fallen",{}).get("seen",false)),"final NPC boss is seen")
	s.damage(fallen,100,int(s.party[0].id),"physical")
	check(int(s.codex.monsters["boss:fallen"].kills) == 1,"final NPC boss kill is recorded")
	# Existing extensions survive sanitization; malformed sections do not crash.
	var file := FileAccess.open(Codex.path,FileAccess.WRITE)
	file.store_string('{"version":1,"runs":"bad","stones":[],"monsters":{"bad":42},"future":{"x":1}}'); file.close()
	var safe := Codex.read()
	check(safe.runs == 0 and safe.stones.is_empty() and safe.monsters.is_empty() and safe.future.x == 1,"valid JSON with bad schema is sanitized")
	# A write failure keeps dirty data available for a later retry.
	var path := Codex.path; Codex.path = "user://missing_codex_directory/book.json"
	s.codex_dirty = true; Codex.flush(s)
	check(s.codex_dirty,"failed persistence retains dirty data")
	Codex.path = path
