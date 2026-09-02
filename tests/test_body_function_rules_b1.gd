extends "res://tests/test_case.gd"

const BodyState=preload("res://sim/body_state.gd")
const FunctionRules=preload("res://sim/body_function_rules.gd")
const WeaponRegistry=preload("res://sim/weapon_registry.gd")


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
