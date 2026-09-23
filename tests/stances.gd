extends SceneTree
## Stances: aptitude from personality, session gating, conflict, and the three
## behaviour programmes the tactics selector runs.
const Session = preload("res://expedition/session.gd")
const Stances = preload("res://expedition/stances.gd")
const Knobs = preload("res://expedition/knobs.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func profile(values: Dictionary) -> DungeonHexacoProfile:
	return Hexaco.new({"H":500,"E":500,"X":500,"A":500,"C":500,"O":500}.merged(values,true))

func run() -> void:
	data()
	print("Stances: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func data() -> void:
	var bold := profile({"X":900,"E":100,"C":1000})
	var timid := profile({"E":900,"C":900,"X":100})
	var kind := profile({"A":900,"H":800})
	check(Stances.aptitude(bold) == {"CHARGER":800,"SKIRMISHER":100,"GUARDIAN":0},"bold aptitudes")
	check(Stances.aptitude(timid) == {"CHARGER":-800,"SKIRMISHER":800,"GUARDIAN":0},"timid aptitudes")
	check(Stances.default_stance(bold) == "CHARGER" and Stances.default_stance(timid) == "SKIRMISHER" and Stances.default_stance(kind) == "GUARDIAN","default stance is the best aptitude")
	check(Stances.default_stance(profile({})) == "CHARGER","ties resolve in IDS order")
	# Comfort: within best - (200 + C/5).
	check(Stances.comfortable(bold,"CHARGER") and not Stances.comfortable(bold,"GUARDIAN"),"bold: charger yes, guardian no (800 vs 0, band 400)")
	check(not Stances.comfortable(bold,"SKIRMISHER"),"bold: skirmisher 700 below the best, band is 400")
	var lax := profile({"X":700,"E":300,"C":0})
	check(Stances.aptitude(lax).CHARGER == 400 and not Stances.comfortable(lax,"SKIRMISHER"),"C 0: band is only 200")
	# Session: fields, gating, solo guardian refused.
	var s = Session.new(731,true,true,true,3)
	var hero: Dictionary = s.party[0]
	check(Stances.IDS.has(hero.stance) and hero.stance == Stances.default_stance(hero.profile) and hero.protect_id == -1,"new actors start on their default stance")
	check(s.set_stance(0,"GUARDIAN") and hero.stance == "GUARDIAN","stance changes in town")
	check(not s.set_stance(0,"NOPE") and not s.set_stance(9,"CHARGER"),"unknown stance / index refused")
	check(s.set_protect(0,1) and hero.protect_id == 1 and not s.set_protect(0,0) and s.set_protect(0,-1),"protect target: another member or auto; never self")
	var solo = Session.new(731,true,false,true,1)
	check(not solo.set_stance(0,"GUARDIAN") and solo.set_stance(0,"SKIRMISHER"),"solo cannot be a guardian")
	s.depart(); Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = s.party[0].pos+Vector2i(3,0)
	s.floor_state.observe(s)
	check(not s.set_stance(0,"CHARGER"),"not while fighting")
	# Suggested stance follows the build.
	hero.equipped_abilities = ["KOBOLD_SLING",""]
	check(Stances.ranged_part(hero) == "KOBOLD_SLING" and Stances.suggested(hero) == "SKIRMISHER","a ranged part suggests skirmisher")
	hero.equipped_abilities = ["PUSH","GUARD"]
	check(Stances.ranged_part(hero) == "" and Stances.suggested(hero) == "GUARDIAN","guard suggests guardian")
	hero.equipped_abilities = ["PUSH",""]
	check(Stances.suggested(hero) == "CHARGER","otherwise charger")
	# Conflict: an uncomfortable stance conflicts like a knob; anxious members fall back.
	hero.profile = bold; hero.knobs = Knobs.defaults(bold); hero.stance = "GUARDIAN"; hero.stress = 0
	check(Knobs.conflicted(hero),"stance outside the aptitude band conflicts")
	check(Stances.effective(hero) == "GUARDIAN","calm: the chosen stance")
	hero.stress = 120; s.stress(hero,0)
	check(Stances.effective(hero) == "CHARGER","anxious: personality's own stance")
	hero.stress = 0; hero.stance = "CHARGER"
	check(not Knobs.conflicted(hero),"comfortable stance: no conflict")
	# Battle start charges the conflict once, whether from knobs or stance.
	hero.stance = "GUARDIAN"; s.auto.prev_threats = 0
	var stress_before: int = hero.stress
	# The 8 of a conflict runs through stress(), which scales it by emotionality:
	# bold has E 100, so 8*(650+100)/1000 = 6.
	check(s.auto_stop_reason() == "BATTLE_START" and hero.stress == stress_before+6 and hero.conflicted,"stance conflict costs stress at battle start")
