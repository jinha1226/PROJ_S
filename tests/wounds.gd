extends SceneTree
## Wounds (2026-09-26 damage forms spec §4.3–4.4): a landed primary blow may
## leave a bleed, a fracture or exposed vitals by its form; spells, ticks and
## secondary damage never do.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Scheduler = preload("res://expedition/time/scheduler.gd")
const Hud = preload("res://expedition/ui/screens/floor_hud.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	by_form(); odds(); not_these(); fracture(); exposed(); harmful(); covered(); ticking(); scheduled(); displayed(); direct_physical()
	Forms.force = -1; StoneEffects.force = -1
	print("Wounds: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duel(weapon: String, species: String) -> Dictionary:
	StoneEffects.force = 99
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]
	hero.gear.weapon = {"type":weapon,"enchant":0}
	s.party[1].pos = c+Vector2i(-4,0)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = species
	foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.ev = 0; foe.ac = 0
	s.floor_state.observe(s)
	s.effects.clear()
	return {"s":s,"c":c,"hero":hero,"foe":foe}

## One landed blow of `form` from the hero, as the attack path would carry it.
func blow(d: Dictionary, form: String, amount: int = 5, element: String = "physical") -> void:
	d.s.Reactions.begin_action(d.s)
	var was: String = Forms.begin(d.s,form)
	d.s.damage(d.foe,amount,int(d.hero.id),element)
	Forms.end(d.s,was)

func procs(s) -> Array:
	return s.effects.filter(func(e): return e.get("kind","") == "PROC").map(func(e): return str(e.text))

func by_form() -> void:
	Forms.force = 0
	for row in [["SLASH","bleed","출혈!"],["IMPACT","fracture","골절!"],["PIERCE","exposed","급소!"]]:
		var w := duel("sword","dcss_rat")
		blow(w,row[0])
		check(w.foe.statuses.has(row[1]),"%s leaves %s" % [row[0],row[1]])
		check(row[2] in procs(w.s),"%s raises %s" % [row[0],row[2]])
	var d := duel("sword","dcss_rat")
	blow(d,"SLASH")
	check(int(d.foe.statuses.bleed) == int(d.s.time)+300,"a bleed lasts 300")
	var e := duel("sword","dcss_rat")
	blow(e,"PIERCE")
	check(int(e.foe.statuses.exposed) == int(e.s.time)+200,"exposed lasts 200")

func odds() -> void:
	# The roll must be under the chance: 30 on a skeleton's soft skin, 10 on a beetle.
	Forms.force = 25
	var soft := duel("sword","skeleton_soldier"); blow(soft,"SLASH")
	var tough := duel("sword","rock_beetle"); blow(tough,"SLASH")
	check(soft.foe.statuses.has("bleed") and not tough.foe.statuses.has("bleed"),"a roll of 25 cuts soft skin, not tough")
	Forms.force = 15
	var ordinary := duel("sword","dcss_frilled_lizard"); blow(ordinary,"PIERCE")
	check(ordinary.foe.statuses.has("exposed"),"a roll of 15 pierces anyone")
	Forms.force = 99
	var none := duel("sword","skeleton_soldier"); blow(none,"SLASH")
	check(not none.foe.statuses.has("bleed"),"a roll of 99 wounds nobody")

func not_these() -> void:
	Forms.force = 0
	var spell := duel("staff","dcss_rat")
	spell.s.casting += 1; blow(spell,"PIERCE"); spell.s.casting -= 1
	check(not spell.foe.statuses.has("exposed"),"a spell never wounds")
	var counter := duel("sword","dcss_rat")
	blow(counter,"SLASH",5,"COUNTER")
	check(not counter.foe.statuses.has("bleed"),"a counter never wounds")
	var tick := duel("sword","dcss_rat")
	tick.foe.statuses = {"bleed":tick.s.time+300}
	Statuses.tick(tick.s)
	check(tick.foe.statuses.keys() == ["bleed"],"a bleed tick wounds nothing more")
	var formless := duel("sword","dcss_rat")
	blow(formless,"")
	check(formless.foe.statuses.is_empty(),"a blow with no form wounds nothing")
	var nothing := duel("sword","dcss_rat")
	blow(nothing,"SLASH",0)
	check(nothing.foe.statuses.is_empty(),"no damage, no wound")

func fracture() -> void:
	var d := duel("sword","dcss_rat")
	var before: int = StoneEffects.delay(d.s,d.foe,100)
	d.foe.statuses["fracture"] = d.s.time+300
	check(StoneEffects.delay(d.s,d.foe,100) == before*125/100,"a fracture slows a quarter")
	d.foe["boss"] = true
	check(StoneEffects.delay(d.s,d.foe,100) == before*112/100,"a boss limps half as much")
	check(StoneEffects.delay(d.s,d.foe,100,"WAIT") == before,"fracture leaves waiting alone")
	check(StoneEffects.delay(d.s,d.foe,100,"CAST") == before,"fracture leaves casting alone")
	check(StoneEffects.delay(d.s,d.foe,100,"RAT_GNAW") == before*112/100,"a physical part is an attack")
	check(StoneEffects.delay(d.s,d.foe,100,"FIRE_CALLER") == before,"an elemental part is unaffected")
	var hero: Dictionary = d.hero
	var move_before: int = d.s.action_cost(hero,"MOVE",d.c+Vector2i(0,1))
	hero.statuses["fracture"] = d.s.time+300
	check(d.s.action_cost(hero,"MOVE",d.c+Vector2i(0,1)) == move_before*125/100,"hero movement slows exactly once")

func exposed() -> void:
	var d := duel("sword","dcss_rat")
	var before: int = StoneEffects.crit_chance(d.s,d.hero,d.foe)
	d.foe.statuses["exposed"] = d.s.time+200
	check(StoneEffects.crit_chance(d.s,d.hero,d.foe) == before+25,"exposed vitals add 25 to a crit")
	# One crit roll spends it, whether or not the crit lands.
	StoneEffects.force = 99
	d.s.Reactions.begin_action(d.s)
	StoneEffects.outgoing(d.s,d.hero,d.foe,10,"physical")
	check(not d.foe.statuses.has("exposed"),"a crit roll spends exposed vitals")
	# A spell does not spend it.
	d.foe.statuses["exposed"] = d.s.time+200
	d.s.casting += 1
	StoneEffects.outgoing(d.s,d.hero,d.foe,10,"fire")
	d.s.casting -= 1
	check(d.foe.statuses.has("exposed"),"a spell leaves exposed vitals")

func harmful() -> void:
	for status in ["fracture","exposed","bleed"]:
		check(status in Statuses.HARMFUL and status in StoneEffects.HARMFUL,"%s is harmful" % status)
	var d := duel("sword","dcss_rat")
	d.foe.statuses["immune"] = d.s.time+300
	Forms.force = 0
	blow(d,"IMPACT")
	check(not d.foe.statuses.has("fracture"),"immunity stops a fracture")
	d.foe.statuses["fracture"] = d.s.time+100; d.s.effects.clear()
	blow(d,"IMPACT")
	check(int(d.foe.statuses.fracture) == d.s.time+100 and "골절!" not in procs(d.s),"a blocked refresh neither extends an old fracture nor announces a new one")
	check(StoneEffects.status_ticks({"enemy":false,"equipped_abilities":["GOBLIN_HEXER"]},"fracture",300) == 450,"a hexer can lengthen fractures")

func covered() -> void:
	Forms.force = 0
	var d := duel("sword","dcss_rat")
	var ally: Dictionary = d.s.party[1]
	ally.pos = d.c+Vector2i(0,1); ally.hp = ally.max_hp
	d.hero.protected_by = ally.id; ally.guarded = true
	var was: String = Forms.begin(d.s,"IMPACT")
	d.s.damage(d.hero,8,int(d.foe.id),"physical")
	Forms.end(d.s,was)
	check(ally.statuses.has("fracture") and not d.hero.statuses.has("fracture"),"the protector takes the wound")
	check(d.s.effects.any(func(e): return e.get("kind","") == "PROC" and e.get("text","") == "골절!" and e.cell == ally.pos),"the wound notice appears over the protector")

func ticking() -> void:
	Forms.force = 0
	var d := duel("sword","dcss_rat")
	blow(d,"IMPACT"); var deadline: int = d.foe.statuses.fracture
	d.s.time += 100; blow(d,"IMPACT")
	check(int(d.foe.statuses.fracture) == deadline+100,"reapplying fracture refreshes its duration")
	d.s.time = int(d.foe.statuses.fracture); Statuses.tick(d.s)
	check(not d.foe.statuses.has("fracture"),"fracture expires at its boundary")
	var e := duel("sword","dcss_rat")
	blow(e,"PIERCE"); e.s.time = int(e.foe.statuses.exposed); Statuses.tick(e.s)
	check(not e.foe.statuses.has("exposed"),"exposed vitals expire unused")

func scheduled() -> void:
	Forms.force = 99
	var d := duel("sword","dcss_rat")
	d.foe.statuses["fracture"] = d.s.time+300; d.foe.alert = true; d.foe.charging = false; d.foe.part_id = ""
	d.foe.role = "MELEE"; d.foe.basic_attack = 1
	Scheduler.act(d.s,d.foe)
	check(int(d.foe.ready_at)-int(d.s.time) == 125,"the monster scheduler also delays a fractured attacker")
	var npc: Dictionary = d.s.make_actor(888,"적대 NPC",false)
	npc.npc = true; npc.hostile = true; npc.awake = true; npc.pos = d.c+Vector2i(-1,0)
	npc.statuses["fracture"] = d.s.time+300; d.s.npcs.append(npc)
	Scheduler.act(d.s,npc)
	check(int(npc.ready_at)-int(d.s.time) == 125,"independent NPC attacks also obey fracture delay")

func displayed() -> void:
	var d := duel("sword","dcss_rat")
	d.hero.statuses = {"fracture":d.s.time+300,"exposed":d.s.time+200}
	var words: String = Hud.portrait_state(d.hero)
	check(words.contains("골절") and words.contains("급소 노출") and not words.contains("fracture") and not words.contains("exposed"),"the portrait uses Korean wound names")

func direct_physical() -> void:
	Forms.force = 0
	var d := duel("sword","dcss_rat")
	d.s.damage(d.hero,3,int(d.foe.id),"IMPACT")
	check(d.hero.statuses.has("fracture") and d.s.blow_form == "","a direct physical boss-style attack wounds and restores context")
	var hazard := duel("sword","dcss_rat")
	hazard.s.damage(hazard.hero,3,999,"IMPACT")
	check(not hazard.hero.statuses.has("fracture"),"a sourceless physical hazard does not wound")
