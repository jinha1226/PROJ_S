extends "res://tests/test_case.gd"

const BodyState=preload("res://sim/body_state.gd")
const CombatRules=preload("res://sim/body_combat_rules.gd")
const InjurySystem=preload("res://sim/body_injury_system.gd")
const WeaponRegistry=preload("res://sim/weapon_registry.gd")


func _commitment_for_limb(body)->String:
	for index in range(1000):
		var candidate:=("injury-test-%d"%index).sha256_text()
		if CombatRules.select_part(body,candidate,body.entity_id) in body.LIMB_PART_IDS:
			return candidate
	return ""


func test_body_combat_registry_packets_and_hit_location_are_data_driven()->bool:
	check_eq(CombatRules.registry_error(),"","body combat registry validates")
	check_eq(CombatRules.hit_locations().map(func(row):return [row.part_id,row.weight]),[
		["HEAD",100],["TORSO",350],["LEFT_ARM",150],["RIGHT_ARM",150],
		["LEFT_LEG",125],["RIGHT_LEG",125]],"hit weights are explicit JSON data")
	var body=BodyState.create(7,"human",11)
	var commitment:="f".repeat(64)
	var first:=CombatRules.select_part(body,commitment,7)
	check_eq(CombatRules.select_part(body,commitment,7),first,
		"body location lane is deterministic")
	var sword=WeaponRegistry.definition("SHORT_SWORD")
	check_eq(CombatRules.attack_packet(sword,16),{"form":"SLASH","base_force":55,
		"penetration":25,"contact_size":10,"stagger_force":20},
		"reference damage reproduces the authored packet")
	check_eq(CombatRules.attack_packet(sword,32).base_force,110,
		"raw attack power scales force without changing contact geometry")
	check_eq(CombatRules.attack_packet(sword,100000),{},
		"scaled packets cannot overflow the resolver contract")
	check_eq(CombatRules.armor_packet(3),{"slash_protection":30,
		"pierce_protection":30,"impact_padding":30,"rigidity":30},
		"legacy flat armor has one explicit body projection")
	return finish()


func test_slash_accumulation_disables_then_permanently_severs_a_limb()->bool:
	var body=BodyState.create(8,"human",12)
	var weapon=WeaponRegistry.definition("HAND_AXE")
	var commitment:=_commitment_for_limb(body)
	check(not commitment.is_empty(),"fixture finds a deterministic limb lane")
	if commitment.is_empty():return finish()
	var part_id:=CombatRules.select_part(body,commitment,body.entity_id)
	var first:=InjurySystem.apply(body,weapon,1000,0,commitment,body.entity_id,101)
	check(first.accepted and first.mutated,"catastrophic slash commits a wound")
	check_eq([first.part_id,body.part_condition(part_id),body.revision,body.wounds.size()],
		[part_id,"DISABLED",1,1],"first blow destroys load-bearing tissue and disables")
	var second:=InjurySystem.apply(body,weapon,1000,0,commitment,body.entity_id,102)
	check(second.accepted and second.mutated,"follow-up slash commits")
	check_eq([body.part_condition(part_id),body.revision,body.wounds.size()],
		["SEVERED",2,2],"all-zero slash makes permanent limb loss")
	var part_index:int=body.LIMB_PART_IDS.find(part_id)+2
	check_eq(body.parts[part_index].layers.map(func(layer):return layer.integrity),[0,0,0],
		"severed row has no hidden tissue")
	check_eq([body.wounds[0].source_event_id,body.wounds[1].source_event_id],[101,102],
		"each injury preserves its causal event")
	var wire:Dictionary=body.to_dict();var restored=BodyState.from_dict(
		JSON.parse_string(JSON.stringify(wire)))
	check(restored!=null and restored.to_dict()==wire,
		"wounds and permanent loss survive exact JSON round trip")
	return finish()


func test_impact_never_severs_and_full_protection_prevents_a_tissue_wound()->bool:
	var body=BodyState.create(9,"human",13)
	var mace=WeaponRegistry.definition("MACE")
	var commitment:=_commitment_for_limb(body)
	var impact:=InjurySystem.apply(body,mace,1000,0,commitment,body.entity_id,201)
	check(impact.accepted and impact.mutated,"catastrophic impact commits")
	check(body.part_condition(str(impact.part_id))!="SEVERED",
		"impact can disable but cannot sever")
	var protected=BodyState.create(10,"human",14)
	var blocked:=InjurySystem.apply(protected,WeaponRegistry.definition("UNARMED_STRIKE"),
		12,100,("blocked").sha256_text(),protected.entity_id,202)
	check(blocked.accepted and blocked.mutated,"absorbed impact may still transmit shock")
	check_eq(protected.parts.map(func(part):return part.layers.map(
		func(layer):return layer.integrity)),[
		[1000,1000,1000],[1000,1000,1000],[1000,1000,1000],
		[1000,1000,1000],[1000,1000,1000],[1000,1000,1000]],
		"full protection prevents all tissue loss")
	check(protected.shock>0 and protected.wounds.is_empty() and protected.revision==1,
		"transmitted shock is systemic and does not invent a zero-severity wound")
	var saturated=BodyState.create(11,"human",15)
	saturated.revision=2147483647
	var rejected:=InjurySystem.assess(saturated,mace,12,0,
		("capacity").sha256_text(),saturated.entity_id)
	check_eq([rejected.accepted,rejected.reason],[false,"body_injury_capacity_exhausted"],
		"capacity exhaustion rejects during preflight before HP may commit")
	return finish()
