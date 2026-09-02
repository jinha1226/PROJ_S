extends "res://tests/test_case.gd"

const BodyState=preload("res://sim/body_state.gd")
const FunctionRules=preload("res://sim/body_function_rules.gd")
const WeaponRegistry=preload("res://sim/weapon_registry.gd")
const Simulator=preload("res://sim/simulator.gd")
const MeleeSystem=preload("res://sim/systems/melee_combat_system.gd")


func test_limb_capacity_is_pure_detached_and_has_explicit_locomotion_modes()->bool:
	var body=BodyState.create(1,"beastkin",71)
	var pristine:Dictionary=body.to_dict()
	var first:=FunctionRules.appraisal(body)
	check_eq(first,{"ruleset_id":"body-function-b1-v1","usable_arm_count":2,
		"usable_leg_count":2,"one_handed_available":true,
		"two_handed_available":true,"off_hand_available":true,
		"locomotion_mode":"NORMAL"},"pristine body exposes full capacity")
	first.usable_arm_count=0
	check_eq(FunctionRules.appraisal(body).usable_arm_count,2,"appraisal is detached")
	check_eq(body.to_dict(),pristine,"appraisal never mutates anatomy")
	check_eq(body.transition_part_condition("LEFT_LEG","DISABLED",1),"",
		"one leg becomes unusable")
	check_eq(FunctionRules.appraisal(body).locomotion_mode,"HINDERED",
		"one usable leg loss is an explicit nonnumeric mode")
	check_eq(body.transition_part_condition("RIGHT_LEG","SEVERED",2),"",
		"second leg can be permanently lost")
	var crawling:=FunctionRules.appraisal(body)
	check_eq([crawling.usable_leg_count,crawling.locomotion_mode],[0,"CRAWLING"],
		"no usable legs derives crawling without inventing a speed penalty")
	return finish()


func test_arm_loss_gates_weapon_hands_but_keeps_generic_unarmed_fallback()->bool:
	var body=BodyState.create(2,"beastkin",81)
	var sword=WeaponRegistry.definition("SHORT_SWORD")
	var bow=WeaponRegistry.definition("BOW")
	var claw=WeaponRegistry.definition("NATURAL_CLAW")
	var unarmed=WeaponRegistry.definition("UNARMED_STRIKE")
	for weapon in [sword,bow,claw,unarmed]:
		check_eq(FunctionRules.weapon_use_error(body,weapon),"",
			"healthy body can use %s"%weapon.weapon_id)
	check_eq(body.transition_part_condition("LEFT_ARM","DISABLED",3),"",
		"one arm becomes unusable")
	var one_arm:=FunctionRules.appraisal(body)
	check_eq([one_arm.usable_arm_count,one_arm.one_handed_available,
		one_arm.two_handed_available,one_arm.off_hand_available],
		[1,true,false,false],"one arm retains one-hand use but loses two-hand and off-hand")
	check_eq(FunctionRules.weapon_use_error(body,sword),"","one-handed weapon remains usable")
	check_eq(FunctionRules.weapon_use_error(body,bow),"two_handed_limb_unavailable",
		"two-handed weapon requires both arms")
	check_eq(FunctionRules.weapon_use_error(body,claw),"","one remaining arm can claw")
	check_eq(body.transition_part_condition("RIGHT_ARM","SEVERED",4),"",
		"last arm can be permanently lost")
	check_eq(FunctionRules.weapon_use_error(body,sword),"weapon_limb_unavailable",
		"ordinary held weapon requires an arm")
	check_eq(FunctionRules.weapon_use_error(body,claw),"natural_weapon_limb_unavailable",
		"claw requires an arm")
	check_eq(FunctionRules.weapon_use_error(body,unarmed),"",
		"generic unarmed remains the universal last-resort attack")
	return finish()


func test_authoritative_attack_gate_consumes_the_same_limb_capacity()->bool:
	var ranged_sim=Simulator.create(3,1,91)
	var archer=ranged_sim.world.add_entity("hero","궁수",Vector2i.ZERO,100,[],"human")
	var distant=ranged_sim.world.add_entity("melee_enemy","표적",Vector2i(2,0),100,[],"goblin")
	var ranged_melee=MeleeSystem.new(ranged_sim.world,ranged_sim.damage)
	check(ranged_melee.can_attack_with_weapon(archer.id,distant.id,"BOW"),
		"healthy actor can use a two-handed ranged weapon")
	check_eq(ranged_sim.world.body_states[archer.id].transition_part_condition(
		"LEFT_ARM","DISABLED",10),"","fixture disables one arm")
	check(not ranged_melee.can_attack_with_weapon(archer.id,distant.id,"BOW"),
		"the combat gate rejects two-handed use with one arm")
	var beast_sim=Simulator.create(2,1,92)
	var beast=beast_sim.world.add_entity("hero","수인",Vector2i.ZERO,100,[],"beastkin")
	var adjacent=beast_sim.world.add_entity("melee_enemy","표적",Vector2i.RIGHT,100,[],"goblin")
	var beast_body=beast_sim.world.body_states[beast.id]
	check_eq(beast_body.transition_part_condition("LEFT_ARM","SEVERED",11),"",
		"fixture removes first arm")
	check_eq(beast_body.transition_part_condition("RIGHT_ARM","SEVERED",12),"",
		"fixture removes second arm")
	check(not MeleeSystem.new(beast_sim.world,beast_sim.damage).can_attack(beast.id,adjacent.id),
		"species claw cannot attack without an arm")
	var human_sim=Simulator.create(2,1,93)
	var human=human_sim.world.add_entity("hero","인간",Vector2i.ZERO,100,[],"human")
	var human_target=human_sim.world.add_entity("melee_enemy","표적",Vector2i.RIGHT,100,[],"goblin")
	var human_body=human_sim.world.body_states[human.id]
	human_body.transition_part_condition("LEFT_ARM","SEVERED",13)
	human_body.transition_part_condition("RIGHT_ARM","SEVERED",14)
	check(MeleeSystem.new(human_sim.world,human_sim.damage).can_attack(human.id,human_target.id),
		"generic unarmed fallback remains available without arms")
	return finish()
