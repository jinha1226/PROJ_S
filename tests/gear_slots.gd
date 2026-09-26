extends SceneTree
const Fixture = preload("res://tests/followup_fixture.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var d := Fixture.reset(); var s = d.s; s.phase = "CAMP"
	var legacy := {"gear":{"weapon":{"type":"sword"},"shield":{"type":"shield"},"ring":{"type":"fire"}}}
	var worn := Equipment.worn(legacy)
	check(worn.keys().size() == 5 and worn.offhand.type == "shield" and worn.ring1.type == "fire","old gear migrates to five slots without losing items")
	var snapshot: Dictionary = worn.duplicate(true)
	check(Equipment.worn(legacy) == snapshot,"slot migration is idempotent")
	var shield := {"type":"shield"}; var bow := {"type":"bow"}
	s.gear_bag = [shield,bow]
	check(s.equip_gear(0,shield) and Stats.stats(s,d.hero).sh == 15,"shield provides its block")
	check(s.equip_gear(0,bow) and d.hero.gear.offhand.is_empty() and s.gear_bag.any(func(i): return i.type == "shield"),"two-hand swap returns shield to bag")
	check(not s.equip_gear(0,s.gear_bag.filter(func(i): return i.type == "shield")[0]),"offhand cannot be worn with a two-hand weapon")
	var sword := {"type":"sword"}; var orb := {"type":"orb"}
	s.gear_bag.append(sword); s.gear_bag.append(orb)
	check(s.equip_gear(0,sword) and s.equip_gear(0,orb) and Stats.stats(s,d.hero).power == 3,"orb adds spell power without block")
	var ring1 := {"type":"power","uid":1,"props":[{"key":"hp","value":10}],"affix":"GEAR_AMP_1"}
	var ring2 := {"type":"power","uid":2,"props":[{"key":"hp","value":10}],"affix":"GEAR_AMP_1"}
	s.gear_bag.append(ring1); s.gear_bag.append(ring2)
	d.hero.hp = 40; d.hero.mp = 0
	check(s.equip_gear(0,ring1) and s.equip_gear(0,ring2),"rings automatically fill both available slots")
	check(d.hero.max_hp == 120 and d.hero.hp == 40,"both ring properties add but do not heal")
	check(Equipment.effects(d.hero).count("GEAR_AMP_1") == 1 and s.StoneEffects.modifier(s,"bleed_tick",d.hero) == 2,"duplicate amplification activates once")
	var third := {"type":"ev","uid":3}; s.gear_bag.append(third)
	check(not s.equip_gear(0,third) and s.equip_gear(0,third,"ring2"),"occupied rings require explicit replacement choice")
	for i in range(4):
		check(s.unequip_gear(0,"ring1"),"ring can be removed")
		check(s.equip_gear(0,ring1,"ring1"),"ring can be restored")
	check(d.hero.hp == 40 and d.hero.max_hp == 110,"repeated equipment swapping never refills HP")
	var mp_ring := {"type":"power","uid":4,"props":[{"key":"mp","value":9}]}; s.gear_bag.append(mp_ring)
	check(s.equip_gear(0,mp_ring,"ring2") and d.hero.max_mp == 69 and d.hero.mp == 0,"MP equipment changes only the maximum")
	d = Fixture.reset(s); d.hero.gear.offhand = {"type":"off_mace"}; s.StoneEffects.force = 0
	s.blow_form = "SLASH"; s.Forms.supplemental(s,d.hero,d.foe,5)
	check(d.foe.statuses.has("fracture") and s.blow_form == "SLASH","offhand applies a second wound without changing killing form")
	check(Stats.stats(s,d.hero).damage == Stats.stats(s,d.ally).damage,"offhand does not grant a second weapon damage budget")
	s.StoneEffects.force = -1
	print("Gear slots: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
