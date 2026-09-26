extends SceneTree
## Part drops (2026-09-26 damage forms spec §2): whether a stone drops is the
## old rule; which part it is follows the killing blow's form 50/25/25.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Gear = preload("res://expedition/items/gear.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	recorded(); spread(); unchanged_drop()
	print("Part drops: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## A dead rat killed by `form`, carrying the rat's stone, ready for roll_part.
func corpse(form: String) -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	revive(s,foe,form,int(foe.id))
	return {"s":s,"foe":foe}

## The same corpse again, as a fresh kill with another id and nothing seen yet.
func revive(s, foe: Dictionary, form: String, enemy_id: int) -> void:
	foe.id = enemy_id; foe.species_id = "dcss_rat"; foe.variant_element = ""; foe.part_id = "RAT_GNAW"
	foe.hp = 0; foe.last_form = form; foe.erase("part_rolled"); foe.erase("part_kind")
	s.essence_seen.clear()

func recorded() -> void:
	var d := corpse("SLASH")
	Gear.roll_part(d.s,d.foe)
	var roll: int = Hexaco.sample(d.s.seed_value,d.s.depth*10000+int(d.foe.id),"essence_part",100)
	check(str(d.foe.get("part_kind","")) == Forms.pick_part("SLASH",roll),"the dropped part follows the killing form and the roll")
	check(int(d.s.parts_bag.get("RAT_GNAW",0)) == 1,"the old stone still drops")

func spread() -> void:
	# Across many enemy ids a slash kill gives cut about half the time.
	# One session, the same corpse revived under 200 ids: a first kill always drops.
	var d := corpse("SLASH")
	var counts := {"cut":0,"broken":0,"pierced":0}
	for i in range(200):
		revive(d.s,d.foe,"SLASH",1000+i)
		Gear.roll_part(d.s,d.foe)
		counts[str(d.foe.part_kind)] += 1
	check(counts.cut > 80 and counts.cut < 120,"a slash kill drops cut about half the time (%d/200)" % counts.cut)
	check(counts.broken > 30 and counts.pierced > 30,"the other two still drop (%d, %d)" % [counts.broken,counts.pierced])
	var even := {"cut":0,"broken":0,"pierced":0}
	for i in range(200):
		revive(d.s,d.foe,"",2000+i)
		Gear.roll_part(d.s,d.foe)
		even[str(d.foe.part_kind)] += 1
	check(even.values().all(func(n): return n > 45),"no form spreads evenly (%s)" % str(even))

func unchanged_drop() -> void:
	# Second kill of the species: the old one-in-four rule still decides whether.
	var d := corpse("PIERCE")
	d.s.essence_seen["dcss_rat"] = true
	var roll: int = Hexaco.sample(d.s.seed_value,d.s.depth*10000+int(d.foe.id),"essence",100)
	Gear.roll_part(d.s,d.foe)
	var dropped: bool = int(d.s.parts_bag.get("RAT_GNAW",0)) == 1
	check(dropped == (roll < Essences.REPEAT_PERCENT),"whether it drops is the old rule")
	check(d.foe.has("part_kind") == dropped,"a part is picked only when a stone drops")
