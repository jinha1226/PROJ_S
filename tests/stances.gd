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

## Steps between two cells: what a MOVE actually closes, since a diagonal step
## costs the same as a straight one.
func near(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))

func run() -> void:
	data()
	charger()
	skirmisher()
	guardian()
	target()
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

## Three members with basics, foes revived on demand. Stances set explicitly.
func field(stances: Array, foes: int = 1) -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,9)
	Fixture.equip_basics(s)
	for i in range(3):
		s.party[i].stance = stances[i]; s.party[i].knobs = Knobs.DEFAULT.duplicate(); s.party[i].stress = 0
		s.party[i].pos = c+Vector2i(0,i)
	var revived: Array = []
	for i in range(foes):
		var foe: Dictionary = s.enemies[i]
		foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0; foe.part_id = ""
		foe.pos = c+Vector2i(4+i,0); revived.append(foe)
	s.floor_state.observe(s); s.selected = 0
	for a in s.party: a.ap = 1
	return {"s":s,"c":c,"foes":revived}

func charger() -> void:
	var f := field(["CHARGER","CHARGER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	hero.rules = []   # the stance decides until the last check hands it a rule
	var pick: Dictionary = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and near(pick.cell,f.foes[0].pos) < near(hero.pos,f.foes[0].pos),"charger closes on the target")
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	check(s.Tactics.choose(s,hero).kind == "ATTACK","adjacent: charger attacks")
	# Stands on a telegraphed cell and keeps hitting (posture 0); a very cautious charger sidesteps.
	s.intents = [{"id":f.foes[0].id,"cell":hero.pos,"damage":9,"kind":""}]; f.foes[0].charging = true
	check(s.Tactics.choose(s,hero).kind == "ATTACK","charger ignores the telegraph")
	hero.knobs.posture = -80
	check(s.Tactics.choose(s,hero).kind == "MOVE","posture -80: sidesteps")
	hero.knobs.posture = 0; s.intents = []; f.foes[0].charging = false
	# Fire underfoot is always avoided.
	s.tile(hero.pos).fire = 40
	check(s.Tactics.choose(s,hero).kind == "MOVE","fire is left even by a charger")
	s.tile(hero.pos).fire = 0
	# A matched PUSH rule still wins over the stance.
	s.intents = [{"id":f.foes[0].id,"cell":hero.pos,"damage":9,"kind":""}]; f.foes[0].charging = true
	hero.rules = [s.Abilities.default_rule("PUSH")]
	check(s.Tactics.choose(s,hero).kind == "PUSH","rules outrank the stance")

func skirmisher() -> void:
	var f := field(["SKIRMISHER","CHARGER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	hero.equipped_abilities = ["KOBOLD_SLING","GUARD"]; hero.rules = [s.Abilities.default_rule("KOBOLD_SLING")]; hero.cooldowns = {}
	# d > R: approach; 2..R: shoot; d < 2: open distance.
	f.foes[0].pos = hero.pos+Vector2i(6,0); s.floor_state.observe(s)
	var pick: Dictionary = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and pick.cell.x > hero.pos.x,"beyond range: closes in")
	f.foes[0].pos = hero.pos+Vector2i(3,0); s.floor_state.observe(s)
	check(s.Tactics.choose(s,hero).kind == "KOBOLD_SLING","in range: fires the part")
	hero.cooldowns.KOBOLD_SLING = 2
	check(s.Tactics.choose(s,hero).kind == "WAIT","in range on cooldown: holds position")
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	pick = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and near(pick.cell,f.foes[0].pos) > 1,"adjacent: steps away rather than trading blows")
	# Without a ranged part: approach, strike, break away.
	var g := field(["SKIRMISHER","CHARGER","CHARGER"]); var t = g.s; var h: Dictionary = t.party[0]
	g.foes[0].pos = h.pos+Vector2i(2,0); t.floor_state.observe(t)
	pick = t.Tactics.choose(t,h)
	check(pick.kind == "MOVE" and t.melee_reach(pick.cell,g.foes[0].pos),"no ranged part: closes to strike")
	t.act_as(h,pick.kind,pick.cell,false); h.ap = 1
	check(t.Tactics.choose(t,h).kind == "ATTACK","strikes")
	t.act_as(h,"ATTACK",g.foes[0].pos,false); h.ap = 1
	check(h.hit_and_run,"the strike arms the break-away")
	pick = t.Tactics.choose(t,h)
	check(pick.kind == "MOVE" and near(pick.cell,g.foes[0].pos) >= 2,"then breaks away")
	t.act_as(h,pick.kind,pick.cell,false)
	check(not h.hit_and_run,"break-away clears the flag")

func guardian() -> void:
	var f := field(["GUARDIAN","SKIRMISHER","CHARGER"]); var s = f.s; var hero: Dictionary = s.party[0]
	hero.rules = [s.Abilities.default_rule("GUARD")]   # 엄호 is the only rule under test here
	check(Stances.protectee(s,hero).id == s.party[1].id,"auto protectee: the skirmisher")
	s.party[1].stance = "CHARGER"; s.party[2].hp = 10
	check(Stances.protectee(s,hero).id == s.party[2].id,"no skirmisher: the lowest hp ratio")
	hero.protect_id = 1
	check(Stances.protectee(s,hero).id == s.party[1].id,"explicit target wins")
	# No threat: stay beside the protectee.
	var p: Dictionary = s.party[1]
	hero.pos = p.pos+Vector2i(0,-3); s.floor_state.observe(s)
	var pick: Dictionary = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and near(pick.cell,p.pos) < near(hero.pos,p.pos),"far from the protectee: moves to them")
	hero.pos = p.pos+Vector2i(-1,0); f.foes[0].pos = p.pos+Vector2i(6,0); s.floor_state.observe(s)
	check(s.Tactics.choose(s,hero).kind == "WAIT","beside the protectee with no threat: holds")
	# Threat approaching: step between.
	hero.pos = p.pos+Vector2i(0,-1); f.foes[0].pos = p.pos+Vector2i(2,0); s.floor_state.observe(s)
	pick = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and pick.cell == p.pos+Vector2i(1,0),"threat two cells out: steps between")
	hero.pos = p.pos+Vector2i(1,0); f.foes[0].pos = p.pos+Vector2i(2,0); s.floor_state.observe(s)
	check(s.Tactics.choose(s,hero).kind == "ATTACK","adjacent threat: attacks it")
	# Lethal threat on the protectee: guard rule.
	p.hp = 5; s.intents = [{"id":f.foes[0].id,"cell":p.pos,"damage":9,"kind":""}]; f.foes[0].charging = true
	check(s.Tactics.choose(s,hero).kind == "GUARD" and s.Tactics.choose(s,hero).cell == p.pos,"lethal: guards the protectee")
	hero.equipped_abilities = ["PUSH",""]; hero.rules = [s.Abilities.default_rule("PUSH")]
	s.intents = []; f.foes[0].charging = false; f.foes[0].pos = p.pos+Vector2i(2,0); hero.pos = p.pos+Vector2i(0,-1); s.floor_state.observe(s)
	pick = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and pick.cell == p.pos+Vector2i(1,0),"no guard part: still bodies the gap")

func target() -> void:
	var f := field(["CHARGER","SKIRMISHER","GUARDIAN"],2); var s = f.s
	f.foes[1].pos = s.party[0].pos+Vector2i(1,0); s.floor_state.observe(s)
	check(Stances.party_target(s).id == f.foes[1].id,"the charger's adjacent foe is the party target")
	s.party_command = "ATTACK_TARGET"; s.command_target = f.foes[0].id
	check(Stances.party_target(s).id == f.foes[0].id,"an attack order overrides")
	s.party_command = "FOLLOW"
	f.foes[1].pos = s.party[0].pos+Vector2i(5,0); s.floor_state.observe(s)
	check(Stances.party_target(s).id == f.foes[1].id or Stances.party_target(s).id == f.foes[0].id,"otherwise the nearest visible foe")
	# role_rounds: a charger beside its target counts as in-role.
	f.foes[1].pos = s.party[0].pos+Vector2i(1,0); s.floor_state.observe(s); s.reset_battle_stats()
	s.auto_step()
	var rr: Dictionary = s.member_stats(s.party[0].id).role_rounds
	check(rr.total == 1 and rr.in_role == 1,"role_rounds tallies the charger's contact round")
