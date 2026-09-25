extends SceneTree
## Fifty spells in five schools, written in eight shapes; three books a school,
## read at camp and nowhere else.
const Session = preload("res://expedition/run/session.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Curios = preload("res://expedition/items/curios.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const SCHOOLS := ["fire", "ice", "air", "hex", "summon"]
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	data()
	start()
	learning()
	drops()
	await process_frame
	await effects()
	held_monsters()
	turned()
	rays()
	determinism()
	print("Spellbooks: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## ── the table ────────────────────────────────────────────────────────────

func data() -> void:
	var rows: Dictionary = Stats.content.spells
	var schooled: Array = Spells.schooled()
	check(schooled.size() == 50,"fifty spells in the table")
	check(Spells.primitives.size() == 8,"eight primitives")
	for school in SCHOOLS:
		var mine: Array = schooled.filter(func(id): return str(rows[id].school) == school)
		check(mine.size() == 10,"%s has ten spells" % school)
		for level in range(1,11):
			var id: String = "%s_%d" % [school,level]
			check(rows.has(id),"%s exists" % id)
			if not rows.has(id): continue
			var row: Dictionary = rows[id]
			check(int(row.level) == level,"%s knows its level" % id)
			check(str(row.shape) in Spells.primitives,"%s is one of the eight shapes" % id)
			check(int(row.mp) == 2+level,"%s costs 2 + level MP" % id)
			var tier: int = 1 if level <= 3 else (2 if level <= 6 else 3)
			check(Essences.spell_cap(tier) >= level and (tier == 1 or Essences.spell_cap(tier-1) < level),"%s needs a tier-%d caster essence" % [id,tier])
			check(not str(row.name).is_empty() and not str(row.note).is_empty(),"%s is named and described" % id)
	check(not Stats.content.has("books"),"no books any more")
	for school in SCHOOLS:
		var caster: String = str(Essences.CASTER_BY_SCHOOL[school])
		for tier in [1,2,3]:
			var reach: Array = Essences.spell_choices({"essences":{caster:tier}},caster)
			check(not reach.is_empty() and reach.all(func(id): return str(rows[id].school) == school),"%s tier %d reaches only its school" % [school,tier])
			check(reach.size() == Essences.spell_cap(tier),"%s tier %d reaches its band" % [school,tier])
	# The relics stay in the data and out of every book: nothing drops them.
	for id in ["blast","blink","mend","passwall","ward","turret","ignite"]:
		check(Stats.content.spells.has(id),"the relic %s is still in the table" % id)
		check(str(Stats.content.spells[id].get("book","")).is_empty(),"no book holds the relic %s" % id)
	# A relic with no cast branch refuses before spending MP.
	var rs = Session.new(19,false,false,true,1); rs.depart(); Fixture.arena(rs,8)
	var rh: Dictionary = rs.party[0]; rh.spells.append("ward"); rh.prepared = ["ward"]; rh.mp = rh.max_mp
	check(Spells.refusal(rs,rh,"ward",rh.pos) == "아직 쓸 수 없는 유물" and not Spells.cast(rs,rh,"ward",rh.pos) and rh.mp == rh.max_mp,"an effect-less relic is refused and costs nothing")
	check(Stats.content.summons.size() == 5,"five kinds of summon")
	for kind in ["hound","imp","rat","wolf","mirror"]:
		var row: Dictionary = Stats.content.summons[kind]
		check(int(row.hp) > 0 and int(row.power) > 0 and int(row.speed) > 0 and int(row.duration) > 0,"%s is a whole creature" % kind)
	check(int(Stats.content.summons.wolf.hp) == 40,"a wolf comes with forty hit points")

## ── the start ────────────────────────────────────────────────────────────

func start() -> void:
	for school in SCHOOLS:
		var s = Session.new_run(7,school)
		var hero: Dictionary = s.party[0]
		check(hero.equipped_abilities[0] == Essences.CASTER_BY_SCHOOL[school],"the %s kit wears its caster essence" % school)
		check(hero.spells == ["%s_1" % school],"the %s kit knows its first spell" % school)
		check(hero.prepared == ["%s_1" % school],"the %s kit has it ready" % school)
	var sword = Session.new_run(7,"sword")
	check(sword.party[0].essences.is_empty() and sword.party[0].spells.is_empty(),"a swordsman departs with no spell")

func learning() -> void:
	var s = Session.new_run(7,"fire")
	var hero: Dictionary = s.party[0]
	s.phase = "CAMP"
	check("fire_1" in Essences.spell_choices(hero,"FIRE_CALLER"),"the kit spell is in reach")
	check("fire_2" in Essences.spell_choices(hero,"FIRE_CALLER"),"so is the second")
	check("fire_3" in Essences.spell_choices(hero,"FIRE_CALLER"),"and the third")
	check("fire_4" not in Essences.spell_choices(hero,"FIRE_CALLER"),"but not the fourth")
	check(not s.choose_essence_spell(0,"FIRE_CALLER","fire_4"),"a spell out of reach is refused")
	check(hero.essence_spells.FIRE_CALLER == "fire_1","and the choice stands")
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_3"),"a spell in reach is chosen at camp")
	check(hero.prepared == ["fire_3"],"and is the one ready")
	check(hero.spells == ["fire_3"],"one essence, one spell")
	s.parts_bag["FIRE_CALLER"] = 2
	check(s.absorb_essence(0,"FIRE_CALLER") == "","a second copy raises the tier")
	check(Essences.tier(hero,"FIRE_CALLER") == 2,"to two")
	check("fire_6" in Essences.spell_choices(hero,"FIRE_CALLER"),"tier two reaches the sixth")
	check("fire_7" not in Essences.spell_choices(hero,"FIRE_CALLER"),"not the seventh")
	check(s.absorb_essence(0,"FIRE_CALLER") == "","a third copy")
	check("fire_10" in Essences.spell_choices(hero,"FIRE_CALLER"),"tier three reaches the tenth")
	check(s.absorb_essence(0,"FIRE_CALLER") != "","and there is no fourth tier")
	check(not s.choose_essence_spell(0,"FROST_IMP","ice_1"),"another school needs its own essence")
	s.parts_bag["FROST_IMP"] = 1
	check(s.absorb_essence(0,"FROST_IMP") == "","found in the dungeon, it is absorbed")
	check(hero.essence_spells.FROST_IMP == "ice_1","its first spell is chosen")
	check("ice_1" in hero.spells,"a second school begins")
	check("ice_1" not in hero.prepared,"but only a slotted essence readies its spell")
	s.phase = "BATTLE"
	check(not s.choose_essence_spell(0,"FIRE_CALLER","fire_2"),"nothing is chosen in a fight")
	check(hero.essence_spells.FIRE_CALLER == "fire_3","the choice stands")
	s.phase = "CAMP"
	check(s.choose_essence_spell(0,"FIRE_CALLER","fire_2"),"back at camp it is chosen")
	s.gain_level_xp(hero,65)
	check(s.equip_part(0,1,"FROST_IMP"),"the second slot takes the frost essence")
	check(hero.prepared == ["fire_2","ice_1"],"two spells ready, in slot order")
	check(s.unequip_part(0,1),"unslotted")
	check(hero.prepared == ["fire_2"],"its spell goes")
	check(hero.spells.has("ice_1"),"but it is still known")
	check(s.PREPARED_SLOTS == 5,"five stand ready at most")
	check(Essences.READY_SPELLS == 5,"the essences agree")

func drops() -> void:
	var boss = Session.new_run(5,"fire")
	Fixture.arena(boss,10)
	boss.depth = 6
	var target: Dictionary = boss.enemies[0]
	target.boss = true; target.part_id = "FURNACE_HEART"
	target.hp = 60; target.max_hp = 60
	boss.parts_bag.clear()
	boss.damage(target,9999,0,"physical")
	check(target.hp <= 0,"the boss falls")
	check(int(boss.parts_bag.get("FURNACE_HEART",0)) == 1,"a boss always leaves its essence")
	check(not boss.party[0].has("books"),"and never a book")
	var found: Dictionary = {}
	for key in range(40):
		var curio = Session.new_run(key,"fire")
		curio.parts_bag.clear()
		var casters: Array = Essences.CASTER_BY_SCHOOL.values()
		curio.grant_part(str(casters[key % casters.size()]))
		for id in curio.parts_bag: found[id] = true
	check(found.size() == 5,"every school's caster essence can be found")
	var curio = Session.new_run(9,"fire")
	var known: int = curio.party[0].spells.size()
	curio.grant_part("GOBLIN_HEXER")
	check(int(curio.parts_bag.GOBLIN_HEXER) == 1,"a found essence joins the bag")
	check(curio.party[0].spells.size() == known,"and teaches nothing on its own")

func board(school: String, seed_value: int) -> Dictionary:
	var s = Session.new_run(seed_value,school)
	var centre: Vector2i = Fixture.arena(s,10)
	var hero: Dictionary = s.party[0]
	hero.mp = 999; hero.max_mp = 999
	hero.essences[str(Essences.CASTER_BY_SCHOOL[school])] = 3
	for enemy in s.enemies: enemy.hp = 0
	var foe: Dictionary = s.enemies[0]
	foe.hp = 200; foe.max_hp = 200; foe.pos = centre+Vector2i(2,0)
	foe.alert = true; foe.ready_at = 99000; foe.will = 0
	s.floor_state.observe(s)
	return {"s":s,"hero":hero,"foe":foe,"centre":centre}

func ready(s, hero: Dictionary, id: String) -> void:
	hero.spells.append(id)
	hero.prepared = [id]

func effects() -> void:
	await bolt_and_line()
	await cone_and_burst()
	await wall_and_self()
	await mark_shape()
	await summon_shape()

func bolt_and_line() -> void:
	# bolt: one victim, and resistance is read.
	var one: Dictionary = board("fire",21)
	ready(one.s,one.hero,"fire_1")
	var before: int = one.foe.hp
	check(one.s.cast("fire_1",one.foe.pos),"화염탄 is cast")
	check(one.foe.hp < before,"화염탄 wounds what it names")
	var plain: int = before-int(one.foe.hp)
	var tough: Dictionary = board("fire",21)
	ready(tough.s,tough.hero,"fire_1")
	tough.foe.res = {"fire":50}
	var whole: int = tough.foe.hp
	tough.s.cast("fire_1",tough.foe.pos)
	var resisted: int = whole-int(tough.foe.hp)
	check(resisted > 0,"a half-resistant foe still takes something")
	check(plain > resisted,"and less than one with no resistance")
	# line: three cells straight ahead, both foes on it.
	var run: Dictionary = board("ice",22)
	ready(run.s,run.hero,"ice_1")
	var cells: Array = Spells.cells(run.s,run.hero,"ice_1",run.foe.pos)
	check(cells.size() == 3,"서리창 covers three cells")
	check(cells[0] == run.hero.pos+Vector2i(1,0) and cells[2] == run.hero.pos+Vector2i(3,0),"and they run straight out from the caster")
	var second: Dictionary = run.s.enemies[1]
	second.hp = 200; second.max_hp = 200; second.pos = run.hero.pos+Vector2i(1,0); second.ready_at = 99000
	run.s.floor_state.observe(run.s)
	check(run.s.cast("ice_1",run.foe.pos),"서리창 is cast")
	check(run.foe.hp < 200 and second.hp < 200,"the line hits everything standing on it")
	check(run.foe.statuses.has("slow"),"and leaves them slowed")
	await process_frame

func cone_and_burst() -> void:
	var fan: Dictionary = board("ice",23)
	ready(fan.s,fan.hero,"ice_4")
	var cells: Array = Spells.cells(fan.s,fan.hero,"ice_4",fan.foe.pos)
	check(cells.size() == 3,"the fan is three cells wide")
	check(fan.foe.pos in cells and fan.foe.pos+Vector2i(0,1) in cells and fan.foe.pos+Vector2i(0,-1) in cells,"and it opens across the line of sight")
	check(fan.s.cast("ice_4",fan.foe.pos),"둔화 강화 is cast")
	check(fan.foe.hp < 200 and fan.foe.statuses.has("slow"),"the fan wounds and slows")
	# burst: a radius, and only the foes in it.
	var ring: Dictionary = board("fire",24)
	ready(ring.s,ring.hero,"fire_3")
	var ally: Dictionary = ring.s.party[0]
	var blast: Array = Spells.cells(ring.s,ring.hero,"fire_3",ring.foe.pos)
	check(blast.size() == 9,"a radius of one is nine cells")
	var friend: Dictionary = Spells.summon(ring.s,ring.hero,ring.foe.pos+Vector2i(1,0),"hound")
	var friend_hp: int = friend.hp
	var hero_hp: int = ally.hp
	check(ring.s.cast("fire_3",ring.foe.pos),"화염 폭발 is cast")
	check(ring.foe.hp < 200,"the burst burns the foe")
	check(friend.hp == friend_hp and ally.hp == hero_hp,"and spares everyone on the hero's side")
	await process_frame

func wall_and_self() -> void:
	var barrier: Dictionary = board("ice",25)
	ready(barrier.s,barrier.hero,"ice_6")
	var s = barrier.s
	var aim: Vector2i = barrier.hero.pos+Vector2i(1,0)
	var cells: Array = Spells.cells(s,barrier.hero,"ice_6",aim)
	check(cells.size() == 3,"빙벽 is three cells wide")
	check(s.is_free(aim),"the cell is open before the wall")
	var cast_at: int = s.time
	check(s.cast("ice_6",aim),"빙벽 is cast")
	check(not s.is_free(aim),"and nothing may stand there")
	check(not s.can_step(barrier.hero.pos,aim),"nor step into it")
	var until: int = int(s.tile(aim).wall_until)
	check(until == cast_at+300,"the barrier stands for three turns")
	var guard := 0
	while (s.tile(aim).has("wall_until") or s.time <= until) and guard < 20:
		s.act("WAIT",s.party[0].pos); guard += 1
	check(s.time > until,"the clock runs past the wall's span")
	check(not s.tile(aim).has("wall_until"),"the wall is simply gone")
	check(s.is_free(aim),"and the cell is open again")
	# self: one stored charge, spent by the next spell of its school and no other.
	var store: Dictionary = board("fire",26)
	ready(store.s,store.hero,"fire_1")
	var plain: int = store.foe.hp
	store.s.cast("fire_1",store.foe.pos)
	var normal: int = plain-int(store.foe.hp)
	var boosted: Dictionary = board("fire",26)
	boosted.hero.spells.append_array(["fire_2","fire_1"])
	boosted.hero.prepared = ["fire_2","fire_1"]
	check(boosted.s.cast("fire_2",boosted.hero.pos),"열 축적 is cast on nobody but the caster")
	check(int(boosted.hero.buffs.get("next_fire",0)) == 150,"and stores the next fire spell's half again")
	var hot: int = boosted.foe.hp
	boosted.s.cast("fire_1",boosted.foe.pos)
	var first: int = hot-int(boosted.foe.hp)
	check(boosted.hero.buffs.is_empty(),"the charge is spent")
	check(first > normal,"the stored heat lands on the first spell after it")
	var again: int = boosted.foe.hp
	boosted.s.cast("fire_1",boosted.foe.pos)
	check(again-int(boosted.foe.hp) < first,"and never on the second")
	await process_frame

func mark_shape() -> void:
	# A mark hangs a status, and the status expires on its own.
	var hex: Dictionary = board("hex",27)
	ready(hex.s,hex.hero,"hex_1")
	check(hex.s.cast("hex_1",hex.foe.pos),"혼란 is cast")
	check(hex.foe.statuses.has("confuse"),"and the mark lands on a foe with no will")
	var until: int = int(hex.foe.statuses.confuse)
	var guard := 0
	while hex.foe.statuses.has("confuse") and guard < 20:
		hex.s.act("WAIT",hex.s.party[0].pos); guard += 1
	check(hex.s.time > until,"the clock runs past the mark's span")
	check(not hex.foe.statuses.has("confuse"),"the mark runs out on its own")
	# weak: thirty per cent off what the victim can still hit with.
	var weak: Dictionary = board("hex",28)
	var full: int = int(Session.CombatStats.stats(weak.s,weak.foe).damage)
	weak.foe.statuses["weak"] = weak.s.time+300
	check(int(Session.CombatStats.stats(weak.s,weak.foe).damage) == full*7/10,"약화 takes thirty per cent off the blow")
	# bind: the feet stop.
	var bind: Dictionary = board("hex",29)
	var step: Vector2i = bind.hero.pos+Vector2i(0,1)
	check(bind.s.can_submit(bind.hero,"MOVE",step),"the hero could walk")
	bind.hero.statuses["bind"] = bind.s.time+300
	check(not bind.s.can_submit(bind.hero,"MOVE",step),"속박 refuses the step")
	check(not bind.s.act_as(bind.hero,"MOVE",step,false),"and the move itself is refused")
	# The arms are free: put the foe within reach and the bound hero still swings.
	bind.foe.pos = bind.hero.pos+Vector2i(1,0)
	bind.s.floor_state.observe(bind.s)
	check(bind.s.can_submit(bind.hero,"ATTACK",bind.foe.pos),"a bound hero may still swing")
	bind.hero.statuses.erase("bind")
	bind.hero.statuses["freeze"] = bind.s.time+300
	check(not bind.s.act_as(bind.hero,"MOVE",step,false),"빙결 stops the feet too")
	check(not bind.s.act_as(bind.hero,"ATTACK",bind.foe.pos,false),"and the arms with them")
	# dominate: a foe counted on the hero's side while the spell holds.
	var rule: Dictionary = board("hex",30)
	ready(rule.s,rule.hero,"hex_9")
	check(rule.foe not in rule.s.friends(),"a monster is nobody's friend")
	check(rule.s.cast("hex_9",rule.foe.pos),"지배 is cast")
	check(bool(rule.foe.enemy),"the flag never moves")
	check(rule.s.dominated(rule.foe),"but the clock says whose side it is on")
	check(rule.s.friends().any(func(a): return int(a.id) == int(rule.foe.id)),"and it counts as a friend")
	check(rule.s.hostiles_of(rule.foe).all(func(a): return bool(a.enemy)),"it fights its own kind now")
	rule.s.time = int(rule.foe.dominated_until)+1
	check(not rule.s.dominated(rule.foe),"two turns later it is a monster again")
	check(rule.foe not in rule.s.friends(),"and no friend of anyone")
	await process_frame

func summon_shape() -> void:
	var s_pack: Dictionary = board("summon",31)
	var s = s_pack.s
	var hero: Dictionary = s_pack.hero
	ready(s,hero,"summon_3")
	check(s.cast("summon_3",hero.pos),"하급 소환 is cast")
	var pets: Array = s.npcs.filter(func(n): return bool(n.get("summoned",false)))
	check(pets.size() == 2,"two imps answer")
	check(pets.all(func(p): return str(p.name) == "임프" and int(p.max_hp) == 12),"and they are imps")
	check(pets.all(func(p): return s.melee_reach(hero.pos,p.pos)),"they stand within arm's reach")
	check(pets.all(func(p): return p in s.friends()),"they count as friends")
	check(pets.all(func(p): return not Session.Recruit.can_aid(s,p).is_empty()),"they take no food")
	check(pets.all(func(p): return not Session.Recruit.propose(s,p).accepted),"they will not join")
	check(s.roster.all(func(n): return not bool(n.get("summoned",false))),"they are not on the roster")
	check(s.companion_rows().all(func(r): return str(r.name) != "임프"),"and not companions of record")
	# A wolf is the bigger creature, and it goes when its time is up.
	var wolf_pack: Dictionary = board("summon",32)
	ready(wolf_pack.s,wolf_pack.hero,"summon_7")
	check(wolf_pack.s.cast("summon_7",wolf_pack.hero.pos),"상급 소환 is cast")
	var wolves: Array = wolf_pack.s.npcs.filter(func(n): return bool(n.get("summoned",false)))
	check(wolves.size() == 1 and int(wolves[0].max_hp) == 40,"one wolf with forty hit points")
	var born: int = int(wolves[0].expires_at)
	var guard := 0
	while wolf_pack.s.npcs.any(func(n): return bool(n.get("summoned",false))) and guard < 20:
		wolf_pack.s.act("WAIT",wolf_pack.s.party[0].pos); guard += 1
	check(wolf_pack.s.time > born,"the clock runs past the wolf's span")
	check(wolf_pack.s.npcs.all(func(n): return not bool(n.get("summoned",false))),"the wolf is gone when its time is up")
	# A creature fights with the power its row gave it, and 공명 lifts that.
	var power_pack: Dictionary = board("summon",34)
	var rat: Dictionary = Spells.summon(power_pack.s,power_pack.hero,power_pack.hero.pos+Vector2i(0,1),"rat")
	var wolf: Dictionary = Spells.summon(power_pack.s,power_pack.hero,power_pack.hero.pos+Vector2i(0,-1),"wolf")
	var rat_damage: int = int(Session.CombatStats.stats(power_pack.s,rat).damage)
	var wolf_damage: int = int(Session.CombatStats.stats(power_pack.s,wolf).damage)
	check(rat_damage == int(Stats.content.summons.rat.power),"a rat hits with a rat's power")
	check(wolf_damage == int(Stats.content.summons.wolf.power),"a wolf hits with a wolf's")
	check(wolf_damage > rat_damage,"and the wolf hits harder than the rat")
	var hound: Dictionary = Spells.summon(power_pack.s,power_pack.hero,power_pack.hero.pos+Vector2i(1,0),"hound")
	var plain_hound: int = int(Session.CombatStats.stats(power_pack.s,hound).damage)
	ready(power_pack.s,power_pack.hero,"summon_8")
	check(power_pack.s.cast("summon_8",power_pack.hero.pos),"공명 is cast")
	check(hound.statuses.has("summon_power"),"and the hound resonates")
	check(int(Session.CombatStats.stats(power_pack.s,hound).damage) == plain_hound*3/2,"a resonating hound hits half again as hard")
	# Nobody grieves a spell running out — nor a summon cut down.
	var grief: Dictionary = board("summon",33)
	ready(grief.s,grief.hero,"summon_1")
	grief.s.cast("summon_1",grief.hero.pos)
	var dog: Array = grief.s.npcs.filter(func(n): return bool(n.get("summoned",false)))
	check(dog.size() == 1,"the hound answers")
	if dog.is_empty(): return
	grief.s.phase = "BATTLE"
	grief.hero.stress = 0
	grief.s.floor_state.observe(grief.s)
	grief.s.damage(dog[0],9999,int(grief.foe.id),"physical")
	check(int(dog[0].hp) <= 0,"the hound falls")
	check(int(grief.hero.stress) == 0,"and the party is not shaken by it")
	await process_frame

## ── the statuses hold monsters too ───────────────────────────────────────

## 빙결 stops a monster where it stands; 속박 only takes its feet.
func held_monsters() -> void:
	var ice: Dictionary = board("ice",41)
	var s = ice.s
	ready(s,ice.hero,"ice_3")
	check(s.cast("ice_3",ice.foe.pos),"빙결 is cast at a foe")
	check(ice.foe.statuses.has("freeze"),"and the foe is frozen")
	# Hold it long enough to watch three turns go past unused.
	ice.foe.statuses["freeze"] = s.time+900
	ice.foe.ready_at = s.time+50
	ice.foe.alert = true
	var where: Vector2i = ice.foe.pos
	var hero_hp: int = ice.hero.hp
	var clock: int = s.time
	for i in range(3): s.act("WAIT",s.party[0].pos)
	check(s.time > clock+200,"three turns of the clock go by")
	check(ice.foe.pos == where,"a frozen monster does not move")
	check(int(ice.hero.hp) == hero_hp,"nor strike")
	# 속박 takes the feet only: the foe starts beside the hero and keeps swinging.
	var hex: Dictionary = board("hex",42)
	var bound = hex.s
	bound.phase = "BATTLE"
	hex.foe.pos = hex.hero.pos+Vector2i(1,0)
	hex.foe.ready_at = bound.time+50
	hex.foe.alert = true
	hex.foe.statuses["bind"] = bound.time+900
	bound.floor_state.observe(bound)
	var stood: Vector2i = hex.foe.pos
	var before_hp: int = hex.hero.hp
	for i in range(4):
		if hex.hero.hp <= 0: break
		bound.act("WAIT",bound.party[0].pos)
	check(hex.foe.pos == stood,"a bound monster does not move")
	check(int(hex.hero.hp) < before_hp,"but it still reaches what stands beside it")

## ── a dominated monster changes sides ────────────────────────────────────

func turned() -> void:
	var pack: Dictionary = board("hex",43)
	var s = pack.s
	var foe: Dictionary = pack.foe
	ready(s,pack.hero,"hex_9")
	check(not s.party_enemies().is_empty(),"a monster is a threat to begin with")
	check(s.cast("hex_9",foe.pos),"지배 is cast")
	check(s.dominated(foe),"the foe is dominated")
	check(s.side_of(foe) == s.side_of(pack.hero),"and stands on the hero's side")
	check(bool(foe.enemy),"without its flag moving")
	s.floor_state.observe(s)
	check(s.party_enemies().is_empty(),"a dominated monster is no threat to the party")
	check(s.floor_state.safe(s),"the floor is quiet while it holds")
	check(s.combat_enemies().all(func(e): return int(e.id) != int(foe.id)),"nor a foe an npc would pick")
	check(s.hostiles_of(pack.hero).all(func(e): return int(e.id) != int(foe.id)),"and no foe of the hero's")
	# It comes for its own kind, and gets there before the spell runs out.
	var other: Dictionary = s.enemies[1]
	other.hp = 200; other.max_hp = 200; other.pos = foe.pos+Vector2i(1,0)
	other.alert = true; other.ready_at = 99000
	s.floor_state.observe(s)
	check(s.hostiles_of(foe).any(func(a): return int(a.id) == int(other.id)),"its own kind are its foes now")
	check(s.hostiles_of(foe).all(func(a): return bool(a.enemy)),"and nobody on the hero's side is")
	var struck: int = other.hp
	s.phase = "BATTLE"
	foe.ready_at = s.time+50
	s.act("WAIT",s.party[0].pos)
	check(int(other.hp) < struck,"a dominated monster attacks another monster")
	# And when it wears off it is a monster again.
	s.time = int(foe.dominated_until)+1
	s.floor_state.observe(s)
	check(not s.dominated(foe),"the spell runs out")
	check(s.side_of(foe) == 1,"and it is back on the dungeon's side")
	check(s.party_enemies().any(func(e): return int(e.id) == int(foe.id)),"a threat once more")
	# A burst the hero throws never touches one it holds.
	var spare: Dictionary = board("hex",45)
	spare.hero.spells.append_array(["hex_9","fire_3"])
	spare.hero.prepared = ["hex_9","fire_3"]
	spare.hero.essences.FIRE_CALLER = 3
	check(spare.s.cast("hex_9",spare.foe.pos),"지배 again")
	check(spare.s.dominated(spare.foe),"and it holds")
	var untouched: int = spare.foe.hp
	spare.s.cast("fire_3",spare.foe.pos+Vector2i(1,0))
	check(int(spare.foe.hp) == untouched,"the hero's burst spares what it holds")

## ── a line needs a ray ───────────────────────────────────────────────────

func rays() -> void:
	var pack: Dictionary = board("ice",44)
	var s = pack.s
	var hero: Dictionary = pack.hero
	ready(s,hero,"ice_1")
	var off: Vector2i = hero.pos+Vector2i(2,1)
	check(Spells.refusal(s,hero,"ice_1",off) == "직선이 아님","an off-ray cell is refused by name")
	var mp: int = hero.mp
	check(not s.cast("ice_1",off),"and the spell is not cast")
	check(int(hero.mp) == mp,"so no MP is spent")
	check(Spells.on_ray(hero.pos,hero.pos+Vector2i(0,3)),"a column is a ray")
	check(Spells.on_ray(hero.pos,hero.pos+Vector2i(2,2)),"so is a diagonal")
	check(not Spells.on_ray(hero.pos,hero.pos),"the caster's own cell is not")
	var diagonal: Vector2i = hero.pos+Vector2i(1,1)
	var victim: Dictionary = pack.foe
	victim.pos = diagonal
	s.floor_state.observe(s)
	check(Spells.refusal(s,hero,"ice_1",diagonal) == "","a diagonal is a ray like any other")
	check(s.cast("ice_1",diagonal),"and the line is cast along it")
	check(int(victim.hp) < 200,"reaching what stands on it")
	check(int(hero.mp) < mp,"this one spends its MP")

## ── determinism ──────────────────────────────────────────────────────────

## The same seed, the same spells, the same numbers: every roll goes through
## the one lane that carries the clock and the caster.
func determinism() -> void:
	var first: Array = trace(404)
	var second: Array = trace(404)
	var other: Array = trace(405)
	check(first == second,"the same seed plays the same way")
	check(first != other,"a different seed does not")

func trace(seed_value: int) -> Array:
	var pack: Dictionary = board("fire",seed_value)
	var s = pack.s
	var hero: Dictionary = pack.hero
	hero.spells.append_array(["fire_3","fire_9"])
	hero.prepared = ["fire_1","fire_3","fire_9"]
	var result: Array = []
	for id in ["fire_1","fire_3","fire_9","fire_1"]:
		s.cast(id,pack.foe.pos)
		result.append([id,int(pack.foe.hp),int(hero.mp),s.roll_serial])
	return result
