extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const FloorHud = preload("res://expedition/ui/screens/floor_hud.gd")
var checks := 0
var failures := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func field(size: int = 2) -> Dictionary:
	var s = Session.new(317,false,true,true,size)
	s.depart()
	s.manual_mode = true
	var center: Vector2i = Fixture.arena(s,9)
	s.party[0].pos = center
	s.party[1].pos = center+Vector2i.RIGHT
	if size > 2: s.party[2].pos = center+Vector2i(0,2)
	for enemy in s.enemies: enemy.ready_at = 999999
	s.floor_state.observe(s)
	return {"s":s,"center":center}

func run() -> void:
	rescue_by_hero()
	countdown_and_death()
	rescue_by_companion()
	hero_still_falls()
	print("Companion rescue: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func rescue_by_hero() -> void:
	var f := field(); var s = f.s
	var hero: Dictionary = s.party[0]; var mate: Dictionary = s.party[1]
	mate.npc = true; mate.state = "PARTY"; s.roster.append(mate)
	s.damage(mate,999,999,"IMPACT")
	check(s.Downed.is_downed(mate) and int(mate.bleedout_turns) == 3 and mate.state == "PARTY","lethal hit starts a three-turn downed state")
	check(FloorHud.portrait_state(mate) == "빈사 · 3턴","the portrait shows the rescue countdown")
	check(s.phase != "DEFEAT" and s.downed_at(mate.pos) == mate and not s.is_free(mate.pos),"downed companion remains on the floor and blocks movement")
	check(hero.memory.salience_for_subject(mate.id+1,["ALLY_DOWNED"]) > 0 and hero.memory.salience_for_subject(mate.id+1,["ALLY_LOST"]) == 0,"the fall is remembered without a premature death memory")
	s.damage(mate,999,999,"IMPACT")
	check(int(mate.bleedout_turns) == 3,"later hits cannot restart the rescue countdown")
	check(s.submit("RESCUE",mate.pos),"hero spends an action to rescue adjacent companion")
	check(mate.hp == maxi(1,int(mate.max_hp)/4) and not s.Downed.is_downed(mate) and mate.state == "PARTY","rescue restores health and roster state")
	check(mate.memory.salience_for_subject(hero.id+1,["RESCUED"]) >= 700 and hero.memory.salience_for_subject(mate.id+1,["ALLY_RESCUED"]) >= 700,"both remember the rescue")
	check(hero.memory.salience_for_subject(mate.id+1,["ALLY_LOST"]) == 0,"rescue leaves no death memory")
	check(not s.submit("RESCUE",mate.pos),"a living companion cannot be rescued twice")

func countdown_and_death() -> void:
	var f := field(); var s = f.s
	var hero: Dictionary = s.party[0]; var mate: Dictionary = s.party[1]
	mate.npc = true; mate.state = "PARTY"; s.roster.append(mate)
	s.damage(mate,999,999,"IMPACT")
	check(s.submit("WAIT",hero.pos) and int(mate.bleedout_turns) == 2,"one completed turn removes one count")
	check(s.submit("WAIT",hero.pos) and int(mate.bleedout_turns) == 1,"the last rescue turn is visible")
	check(s.submit("WAIT",hero.pos) and mate.state == "DEAD" and not s.Downed.is_downed(mate),"countdown expiry kills the companion")
	check(hero.memory.salience_for_subject(mate.id+1,["ALLY_LOST"]) >= 700 and not s.Downed.can_rescue(s,hero,mate),"death is remembered and can no longer be rescued")

func rescue_by_companion() -> void:
	var f := field(3); var s = f.s
	var mate: Dictionary = s.party[1]; var rescuer: Dictionary = s.party[2]
	mate.pos = rescuer.pos+Vector2i(3,0)
	s.floor_state.observe(s)
	s.damage(mate,999,999,"IMPACT")
	check(s.companion_choice(rescuer).kind == "MOVE","a companion routes toward a distant casualty")
	mate.pos = rescuer.pos+Vector2i.RIGHT
	s.floor_state.observe(s)
	check(s.companion_choice(rescuer).kind == "RESCUE","another companion prioritizes rescue")
	check(s.submit("WAIT",s.party[0].pos),"hero's turn advances the companion AI")
	check(mate.hp > 0 and not s.Downed.is_downed(mate) and mate.memory.salience_for_subject(rescuer.id+1,["RESCUED"]) > 0,"companion actually rescues and leaves a memory")

func hero_still_falls() -> void:
	var f := field(); var s = f.s
	s.damage(s.party[0],999,999,"IMPACT")
	check(s.phase == "DEFEAT" and not s.Downed.is_downed(s.party[0]),"hero death still ends the run")
