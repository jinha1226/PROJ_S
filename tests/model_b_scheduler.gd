extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Scheduler = preload("res://expedition/time/scheduler.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(reason)

func field(seed: int) -> Dictionary:
	var s = Session.new(seed,false,false,true,1)
	s.depart()
	Fixture.arena(s,10)
	var hero: Dictionary = s.party[0]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 100; foe.max_hp = 100; foe.pos = hero.pos+Vector2i(1,0)
	foe.alert = true; foe.role = "MELEE"; foe.part_id = ""
	foe.ready_at = s.time+100
	# The ticks below are catalog weapon delays: the starting kit's rank in the
	# axis is set aside so this suite measures the scheduler, not the mastery.
	s.floor_state.observe(s)
	return {"s":s,"h":hero,"e":foe}

func run() -> void:
	var row := field(5501)
	var s = row.s
	var hero: Dictionary = row.h
	var foe: Dictionary = row.e
	hero.gear.weapon = {"type":"dagger"}
	check(s.submit("ATTACK",foe.pos),"first dagger swing accepted")
	check(s.time == 75 and foe.ready_at == 100,"enemy is not scheduled inside the first 75 ticks")
	check(s.submit("ATTACK",foe.pos),"second dagger swing accepted")
	check(s.time == 150 and foe.ready_at == 200,"enemy acts at tick 100 during the second swing")
	var slow := field(5502)
	slow.h.gear.weapon = {"type":"mace"}
	check(slow.s.submit("ATTACK",slow.e.pos),"mace swing accepted")
	check(slow.s.time == 145 and slow.e.ready_at == 200,"mace allows one enemy action")
	check(Scheduler.double_movers(slow.s,51).is_empty(),"end-boundary action is not counted")
	slow.e.ready_at = slow.s.time
	check(Scheduler.double_movers(slow.s,101).size() == 1,"two actions strictly inside the interval are warned")
	var boundary := field(5504)
	check(boundary.s.submit("WAIT",boundary.h.pos) and boundary.s.time == 100 and boundary.e.ready_at == 100,"end-tick enemy waits for the next input")
	check(boundary.s.submit("WAIT",boundary.h.pos) and boundary.e.ready_at == 200,"end-tick enemy acts before the next hero action")
	var waking := field(5503)
	if not waking.s.npcs.is_empty():
		var npc: Dictionary = waking.s.npcs[0]
		npc.pos = waking.h.pos+Vector2i(2,0)
		npc.awake = false; npc.ready_at = -500
		waking.s.manual_mode = true
		Scheduler.awaken(waking.s)
		check(npc.awake and npc.ready_at == waking.s.time,"waking NPC cannot catch up missed turns")
	print("Model B scheduler: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
