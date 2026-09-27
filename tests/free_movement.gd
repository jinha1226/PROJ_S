extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func run() -> void:
	var s = Session.new_run(731,"sword",Session.MobileEffects.PROFILE)
	Fixture.arena(s,64); s.npcs.clear(); s.enemies.clear(); s.enable_free_movement()
	var hero: Dictionary = s.party[0]
	var start := Vector2(3.5,3.5)
	s.Free.place(hero,start)
	var dest := Vector2(4.23,3.87)
	var before: int = s.time
	check(s.Free.submit(s,s.Free.choice(hero,"MOVE",dest,"이동")),"arbitrary direction accepted")
	check(s.Free.position(hero).is_equal_approx(dest),"world coordinate stays unsnapped")
	check(hero.pos == Vector2i(4,3),"terrain cache is floor, not authority")
	check(s.time > before,"continuous move spends turn time")
	before = s.time
	check(not s.Free.submit(s,s.Free.choice(hero,"MOVE",Vector2(7,7),"이동")),"one action cannot cross unlimited distance")
	check(s.time == before and s.Free.position(hero).is_equal_approx(dest),"refused move leaves hero and time unchanged")
	var foe: Dictionary = s.make_actor(101,"근접",true)
	foe.hp = 100; foe.max_hp = 100; foe.pos = Vector2i(5,3)
	s.Floor.MonsterAI.configure(foe,"MELEE"); s.enemies.append(foe)
	foe.ready_at = s.time+1000
	s.Free.place(foe,Vector2(5.24,3.87))
	check(not s.Free.reaches(s,hero,foe,1),"true distance excludes target just outside melee")
	s.Free.place(foe,Vector2(5.22,3.87))
	check(s.Free.reaches(s,hero,foe,1),"true distance includes target inside melee")
	s.Free.place(foe,Vector2(4.8,4.8))
	check(not s.Free.reaches(s,hero,foe,1),"diagonal range is a circle")
	s.tile(Vector2i(4,4)).terrain = "wall"
	check(not s.Free.segment(s,Vector2(3.5,4.5),Vector2(5.5,4.5)),"swept movement cannot pass through wall")
	check(not s.Free.segment(s,Vector2(3.8,3.8),Vector2(4.3,4.3)),"actor radius cannot cut a wall corner")
	check(not s.Free.sees(s,Vector2(3.5,4.5),Vector2(5.5,4.5),4),"ranged attacks cannot cross walls")
	s.Free.place(hero,Vector2(3.5,4.5)); s.Free.place(foe,Vector2(6.3,4.8))
	var path: Array = s.Free.route(s,hero,Vector2(5.3,4.6))
	check(path.size() > 2,"continuous route goes around obstruction")
	for i in range(1,path.size()): check(s.Free.segment(s,path[i-1],path[i]),"every path segment clears radius")
	s.tile(Vector2i(4,4)).terrain = "stone"
	s.Free.place(hero,Vector2(3.5,3.5)); s.Free.place(foe,Vector2(3.96,3.5))
	check(not s.Free.fits(s,Vector2(3.8,3.5),hero),"actors collide without relying on terrain occupancy")
	s.Free.place(foe,Vector2(6.17,4.31))
	var first: Vector2 = s.Free.approach(s,hero,foe)
	check(first.x != floorf(first.x)+0.5 and first.y != floorf(first.y)+0.5,"AI approaches along arbitrary heading")
	var mate: Dictionary = s.make_actor(1,"동료",false); s.party.append(mate); s.companions = true
	s.Free.place(mate,Vector2(2.7,2.9)); s.Free.place(hero,Vector2(5.1,3.9))
	var follow: Dictionary = s.Free.follow(s,mate)
	check(follow.kind == "MOVE" and follow.has("world"),"companion follows continuous position")
	check(s.Free.perform(s,mate,follow),"companion commits continuous movement")
	# Actual button path uses exact actor distances and the original scheduler.
	s.Free.place(hero,Vector2(3.5,3.5)); s.Free.place(foe,Vector2(4.41,3.79))
	mate.ready_at = s.time+1000; foe.ready_at = s.time+1000
	s.phase = "BATTLE"; s.floor_state.observe(s)
	before = s.time
	check(s.Free.attack(s) and s.time > before,"attack command commits an in-range action without snapping")
	check(s.Free.position(hero).is_equal_approx(Vector2(3.5,3.5)),"attacking does not recenter the actor")
	hero.statuses.freeze = s.time+300
	before = s.time
	check(not s.Free.submit(s,s.Free.choice(hero,"MOVE",Vector2(3.8,3.5),"이동")) and s.time == before,"immobilization rejects continuous movement without spending time")
	hero.statuses.clear(); hero.level = 10
	s.Essences.bind(hero,"FIRE_CALLER/broken")
	s.Free.place(foe,Vector2(5.2,5.2)); foe.ready_at = s.time+1000
	var outer: Dictionary = s.make_actor(102,"범위 밖",true)
	outer.hp = 100; outer.max_hp = 100; outer.pos = Vector2i(6,5); outer.ready_at = s.time+1000
	s.Floor.MonsterAI.configure(outer,"MELEE"); s.enemies.append(outer)
	s.Free.place(outer,Vector2(6.01,5.6)); s.floor_state.observe(s)
	check(s.Free.submit(s,s.Free.choice(hero,"WAIT",s.Free.position(hero),"대기")),"wait still drives automatic soulstones")
	check(foe.statuses.has("burn") and not outer.statuses.has("burn"),"wait area is a true circle, not its enclosing tile square")
	hero.statuses.clear(); foe.statuses.clear(); outer.statuses.clear()
	s.Free.place(hero,Vector2(3.24,3.38)); s.Free.place(foe,Vector2(4.02,3.73))
	s.Abilities.resolve(s,hero,"PUSH",foe.pos)
	check(s.Free.position(foe).is_equal_approx(Vector2(4.02,3.73)+(Vector2(4.02,3.73)-Vector2(3.24,3.38)).normalized()),"push follows actual heading and preserves fractional endpoint")
	s.Free.place(mate,Vector2(2.5,6.5)); s.Free.place(foe,Vector2(5.84,4.27)); hero.cast_world = s.Free.position(foe)
	s.Abilities.resolve(s,hero,"GOBLIN_SHIV",foe.pos)
	check(s.Free.gap(hero,foe) <= 1 and not is_equal_approx(s.Free.position(hero).x,floorf(s.Free.position(hero).x)+0.5),"lunge lands within true melee range without snapping")
	s.Free.place(hero,Vector2(7.24,7.31)); s.Free.place(mate,Vector2(7.76,7.69))
	s.tile(Vector2i(7,7)).terrain = "bog"
	s.Scheduler.Hazards.tick_cell(s,Vector2i(7,7),s.tile(Vector2i(7,7)))
	check(hero.statuses.has("poison") and mate.statuses.has("poison"),"terrain affects both bodies sharing a terrain cell")
	s.Free.place(hero,Vector2(3.5,3.5)); s.tile(Vector2i(4,3)).terrain = "wall"
	var slide: Vector2 = s.Free.steer(s,hero,Vector2(1,0.4))
	check(slide.x == 3.5 and slide.y > 3.5 and s.Free.segment(s,s.Free.position(hero),slide,s.Free.RADIUS,hero,true),"joystick slides along a blocked wall without crossing it")
	print("Free movement: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
