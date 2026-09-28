extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Drop = preload("res://expedition/progression/stone_drop.gd")
const Rest = preload("res://expedition/run/rest.gd")
const Icons = preload("res://expedition/art/soulstone_icons.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Mobile = preload("res://expedition/progression/attack_wait.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var s = Session.new(317)
	var actor: Dictionary = s.party[0]
	actor.combat_profile = "attack_wait_v1"
	actor.level = 6
	Essences.sync_slots(actor)
	var groups := {"red":[],"purple":[],"green":[]}
	for id in Essences.catalog():
		groups[Essences.colour(str(id))].append(str(id))
	check(groups.red.size() >= 2 and not groups.purple.is_empty() and not groups.green.is_empty(),"three colours have usable stones")
	var first: String = groups.red[0]
	var second: String = groups.red[1]
	var third: String = groups.green[0]
	check(Icons.stone_icon(first) != null and Icons.stone_icon(third) != null,"composite icons load without editor import")
	for id in Mobile.catalog(): check(Icons.stone_icon(str(id)) != null,"composite icon exists: "+str(id))
	check(Essences.bind(actor,first).is_empty(),"first stone binds")
	var old_effect: String = Essences.automatic_effect_id(first)
	actor.aw_state = {"cooldowns":{old_effect:200},"uses":{old_effect:1},"attack_preps":{}}
	s.parts_bag[second] = 1
	s.parts_bag[third] = 1
	s.phase = "CAMP"
	check(s.swap_stone(0,0,second).is_empty(),"same colour swap at camp")
	check(actor.equipped_abilities[0] == second and int(s.parts_bag.get(first,0)) == 1 and int(s.parts_bag.get(second,0)) == 0,"swap returns old stone to shared bag")
	if old_effect != Essences.automatic_effect_id(second): check(not actor.aw_state.cooldowns.has(old_effect) and not actor.aw_state.uses.has(old_effect),"removed automatic effect loses cooldown and use record")
	var companion: Dictionary = s.make_actor(1,"브란",false)
	companion.combat_profile = "attack_wait_v1"; companion.level = 6; Essences.sync_slots(companion)
	s.party.append(companion)
	check(s.absorb_essence(1,first).is_empty() and companion.equipped_abilities[0] == first,"returned stone can move to a companion")
	check(not s.overwrite_stone(0,0,third).is_empty(),"different colour refuses outside rest")
	s.phase = "BATTLE"
	check(not s.swap_stone(0,0,first).is_empty(),"combat prevents same colour swap")
	s.phase = "CAMP"
	actor.hp = 7; actor.mp = 2; actor.stress = 83; actor.downed = true
	var food: int = s.food
	Rest.enter(s)
	check(s.phase == "REST" and actor.hp == actor.max_hp and actor.mp == actor.max_mp,"rest heals the party")
	check(actor.stress == 53 and not actor.downed and s.food == food,"rest clears downed and stress without food")
	check(s.overwrite_stone(0,0,third).is_empty(),"different colour overwrite at rest")
	check(actor.equipped_abilities[0] == third and not actor.essences.has(second) and int(s.parts_bag.get(second,0)) == 0,"overwrite destroys old stone")
	check(int(s.parts_bag.get(first,0)) == 0 and int(s.parts_bag.get(third,0)) == 0,"overwrite consumes only the new stone")
	s.stone_bag_limit = 3
	s.parts_bag = {first:1,second:1,third:1}
	var incoming: String = groups.purple[0]
	s.parts_bag[incoming] = 1
	s.pending_stone_drops = [{"token":1,"stone":incoming}]
	check(Drop.resolve(s,1,-1) == "버릴 영혼석 선택","full bag requires discard")
	check(Drop.resolve(s,1,-1,first).is_empty(),"full bag replaces a chosen stone")
	check(Essences.bag_count(s) == 3 and int(s.parts_bag.get(first,0)) == 0,"bag stays at three")
	s.stone_bag_limit = 0
	s.parts_bag[first] = 1; s.pending_stone_drops = [{"token":2,"stone":first}]
	check(Drop.resolve(s,2,-1).is_empty() and Essences.bag_count(s) == 4,"development bag has no cap")
	var legacy = Session.new(441)
	var legacy_actor: Dictionary = legacy.party[0]
	legacy_actor.level = 6; Essences.sync_slots(legacy_actor)
	check(Essences.bind(legacy_actor,first).is_empty(),"legacy stone binds for cleanup test")
	var old_skill: String = str(Abilities.held(legacy_actor)[0])
	legacy_actor.cooldowns[old_skill] = 4
	var replacement: String = groups.green.filter(func(id): return Essences.base_of(str(id)) != Essences.base_of(first))[0]
	legacy.parts_bag[replacement] = 1; legacy.phase = "REST"
	check(legacy.overwrite_stone(0,0,replacement).is_empty(),"legacy overwrite uses the same slot rule")
	check(old_skill not in Abilities.held(legacy_actor) and not legacy_actor.cooldowns.has(old_skill),"removed skill and cooldown are cleared")
	check(not legacy_actor.rules.any(func(rule): return Abilities.base_id(str(rule.get("skill",""))) == Abilities.base_id(old_skill)),"removed skill rule is cleared")
	print("Three-colour rules: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
