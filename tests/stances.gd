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
	defence()
	target()
	await ui()
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
	hero.cooldowns = {}   # the part is ready again: only the contact decides below
	f.foes[0].pos = hero.pos+Vector2i(1,0); s.floor_state.observe(s)
	pick = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and near(pick.cell,f.foes[0].pos) > 1,"adjacent: steps away rather than trading blows")
	f.foes[0].pos = hero.pos+Vector2i(3,0); s.floor_state.observe(s)
	check(s.Tactics.choose(s,hero).kind == "KOBOLD_SLING","with room again it fires")
	# Contact is eight-way: a foe diagonally adjacent is contact too, so the
	# sling stays silent and the skirmisher opens distance rather than trading
	# blows (the rule filter in tactical_action_selector.gd already used
	# melee_reach here; the stance's own band now agrees).
	f.foes[0].pos = hero.pos+Vector2i(1,1); s.floor_state.observe(s)
	pick = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and near(pick.cell,f.foes[0].pos) >= 2,"diagonal contact: opens distance, not KOBOLD_SLING or ATTACK/WAIT")
	f.foes[0].pos = hero.pos+Vector2i(3,0); s.floor_state.observe(s)
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
	# 설계 §2.3 (d): no threat and nothing in reach — the pair advances on the
	# shared target instead of holding, and the step stays inside keep+1 of P.
	hero.pos = p.pos+Vector2i(-1,0); f.foes[0].pos = p.pos+Vector2i(4,0); s.floor_state.observe(s)
	check(Stances.threats_to(s,p).is_empty() and not Stances.party_target(s).is_empty(),"the charge is safe and the target is visible")
	pick = s.Tactics.choose(s,hero)
	check(pick.kind == "MOVE" and near(pick.cell,f.foes[0].pos) < near(hero.pos,f.foes[0].pos),"beside the protectee with no threat: advances with the charge")
	check(near(pick.cell,p.pos) <= 2,"the advancing guardian stays inside keep+1 of the protectee")
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
	mutual_guardians()

## Two guardians covering each other used to stand still forever: neither was
## threatened, so neither had a candidate but WAIT. With §2.3 (d)'s advance they
## walk the field together.
func mutual_guardians() -> void:
	var f := field(["GUARDIAN","GUARDIAN","GUARDIAN"]); var s = f.s
	s.party[0].protect_id = 1; s.party[1].protect_id = 0; s.party[2].protect_id = 0
	for a in s.party: a.rules = []
	var foe: Dictionary = f.foes[0]
	foe.pos = s.party[0].pos+Vector2i(5,0); s.floor_state.observe(s)
	var mark: Vector2i = foe.pos
	var before: Array = [s.party[0].pos,s.party[1].pos]
	for _r in range(3):
		for a in s.party: a.ap = 1
		s.auto_step()
	check(near(s.party[0].pos,mark) < near(before[0],mark),"mutual guardians: the first closes on the foe")
	check(near(s.party[1].pos,mark) < near(before[1],mark),"mutual guardians: the second closes too")
	check(near(s.party[0].pos,s.party[1].pos) <= 2,"mutual guardians advance together, never more than two apart")

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

## Self-defence, the no-path fallback and eight-way adjacency: what the stance
## does when the shared target is not the problem in front of it.
func defence() -> void:
	# A charger answers whatever is on it, not only the party's target.
	var f := field(["CHARGER","CHARGER","GUARDIAN"],2); var s = f.s
	s.party[0].pos = f.c; f.foes[0].pos = f.c+Vector2i(1,0)
	s.party[1].pos = f.c+Vector2i(0,4); f.foes[1].pos = f.c+Vector2i(1,4)
	s.floor_state.observe(s)
	check(Stances.party_target(s).id == f.foes[0].id,"the first charger's foe is the party target")
	var pick: Dictionary = s.Tactics.choose(s,s.party[1])
	check(pick.kind == "ATTACK" and pick.cell == f.foes[1].pos,"the second charger answers the foe on it")
	# A guardian standing off its charge does the same.
	var g := field(["GUARDIAN","CHARGER","CHARGER"],2); var t = g.s
	var hero: Dictionary = t.party[0]; var p: Dictionary = t.party[1]
	hero.protect_id = 1; hero.knobs.cohesion = -50   # keep two cells, so a foe on the guardian is no threat to p
	p.pos = g.c; hero.pos = g.c+Vector2i(2,0); g.foes[0].pos = g.c+Vector2i(3,0)
	t.party[2].pos = g.c+Vector2i(0,3); g.foes[1].pos = g.c+Vector2i(1,3)
	t.floor_state.observe(t)
	check(Stances.threats_to(t,p).is_empty() and Stances.party_target(t).id == g.foes[1].id,"the charge is safe and the target is elsewhere")
	pick = t.Tactics.choose(t,hero)
	check(pick.kind == "ATTACK" and pick.cell == g.foes[0].pos,"the guardian answers the foe on it")
	# Eight-way adjacency: diagonally beside the charge is beside it.
	hero.knobs.cohesion = 0; hero.pos = p.pos+Vector2i(-1,-1); g.foes[0].pos = g.c+Vector2i(8,0)
	t.floor_state.observe(t)
	# Beside is beside: the guardian does not shuffle onto a straight-adjacent
	# cell of the charge. With §2.3 (d) it spends the round advancing instead.
	pick = t.Tactics.choose(t,hero)
	check(pick.kind == "MOVE" and near(pick.cell,g.foes[1].pos) < near(hero.pos,g.foes[1].pos),"diagonally beside the charge: advances instead of shuffling")
	check(near(pick.cell,p.pos) >= near(hero.pos,p.pos),"the advance is not a step back toward the charge")
	# The only way through burns: a charger walks it rather than standing still.
	var h := field(["CHARGER","CHARGER","CHARGER"],1); var u = h.s
	var hh: Dictionary = u.party[0]
	u.party[1].pos = h.c+Vector2i(0,3); u.party[2].pos = h.c+Vector2i(0,4)
	hh.pos = h.c; h.foes[0].pos = h.c+Vector2i(2,0)
	for x in range(-1,6):
		u.tile(h.c+Vector2i(x,-1)).terrain = "wall"; u.tile(h.c+Vector2i(x,1)).terrain = "wall"
	u.tile(h.c+Vector2i(-1,0)).terrain = "wall"
	u.tile(h.c+Vector2i(1,0)).fire = 40
	u.floor_state.observe(u)
	check(Stances.steps_toward(u,hh,[h.c+Vector2i(1,0)]) == [h.c+Vector2i(1,0)],"the burning corridor cell is still a route")
	check(u.Tactics.choose(u,hh).kind == "MOVE","a blocked fire-free route does not leave the charger standing")

## The character window's stance card, the member-card letter and the role
## line on the battle report.
func ui() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	var s = Session.new(731,true,true,true,3)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(3): await process_frame
	scene.show_character(0,"성격")
	for frame in range(3): await process_frame
	var buttons: Array = scene.modal_content.find_children("Stance_*","Button",true,false)
	check(buttons.size() == 3 and buttons.any(func(b): return b.button_pressed),"three stance buttons, current one pressed")
	var bars: Array = scene.modal_content.find_children("Aptitude_*","Control",true,false)
	check(bars.size() == 3,"aptitude bars")
	var badge = scene.modal_content.find_child("StanceSuggestion",true,false)
	check(badge != null and badge.text.begins_with("빌드 추천"),"build suggestion badge")
	var guardian: Button = scene.modal_content.find_child("Stance_GUARDIAN",true,false)
	guardian.pressed.emit(); await process_frame
	check(s.party[0].stance == "GUARDIAN","button sets the stance")
	scene.show_character(0,"성격")
	for frame in range(3): await process_frame
	var protect = scene.modal_content.find_child("ProtectPick",true,false)
	check(protect != null and protect.item_count == 3,"guardian shows the protect picker: auto + two members")
	# The knob sliders carry warning labels of their own, so the stance warning
	# is looked for inside the stance card alone. 아린 is comfortable as a
	# charger and a guardian but not as a skirmisher, so both branches run.
	var warned: Array = []
	for id in Stances.IDS:
		check(s.set_stance(0,id),"stance %s can be taken in town" % id)
		scene.show_character(0,"성격")
		for frame in range(3): await process_frame
		var stance_card = scene.modal_content.find_child("StanceCard",true,false)
		var warn: Array = stance_card.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("⚠"))
		check(warn.is_empty() == Stances.comfortable(s.party[0].profile,id),"warning iff the stance is outside the aptitude band: "+id)
		warned.append(not warn.is_empty())
	check(true in warned and false in warned,"both branches of the comfort warning were seen")
	check(s.party[0].stance == "GUARDIAN","the stance card ends on the guardian")
	scene.details_popup.hide()
	var solo = Session.new(731,true,false,true,1)
	scene.session = solo; scene.refresh()
	scene.show_character(0,"성격")
	for frame in range(3): await process_frame
	check(scene.modal_content.find_child("Stance_GUARDIAN",true,false).disabled,"solo: guardian disabled")
	scene.details_popup.hide()
	# Member card shows the stance letter; report shows role rounds.
	scene.session = s; s.depart(); Fixture.arena(s,8); Fixture.equip_basics(s)
	var foe: Dictionary = s.enemies[0]; foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.part_id = ""; foe.pos = s.party[0].pos+Vector2i(1,0)
	s.floor_state.observe(s); scene.refresh()
	for frame in range(3): await process_frame
	var cards: Array = scene.find_children("MemberCard*","Button",true,false)
	check(cards.size() == 3 and cards[0].get_child(0).text.contains("[호]"),"member card carries the stance letter")
	s.reset_battle_stats(); s.auto_step(); foe.hp = 0; s.floor_state.observe(s)
	scene.show_battle_report()
	for frame in range(3): await process_frame
	var labels: Array = scene.modal_content.find_children("*","Label",true,false).map(func(l): return l.text)
	check(labels.any(func(t): return t.contains("역할")),"report shows role performance")
	scene.queue_free(); await process_frame
