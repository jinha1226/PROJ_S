extends "res://tests/test_case.gd"

const Session=preload("res://playtest/party_playtest_session.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
const AbilityBindingRules=preload("res://sim/abilities/ability_binding_rules.gd")
const PartyEncounter=preload("res://sim/party_encounter_state.gd")


func _grant_ability_item(session,instance_id:String)->int:
	var world=session.sim.world
	var hero:=int(world.party_encounter.protagonist_id)
	var current=world.item_state.inventory_rows[hero]
	var rows:Array=[]
	for value in current.backpack:rows.append(value)
	rows.append(Item.new(instance_id,"ESSENCE_FIRE_BOLT",1))
	world.item_state.inventory_rows[hero]=Inventory.new(rows,current.equipped)
	return hero


func test_slot_capacity_and_canonical_duplicate_rules()->bool:
	check_eq(AbilityBindingRules.slot_limit(0),0,"level zero has no opened slot")
	check_eq(AbilityBindingRules.slot_limit(1),1,"level one opens one slot")
	check_eq(AbilityBindingRules.slot_limit(2),2,"level two opens two slots")
	check_eq(AbilityBindingRules.slot_limit(5),5,"level five opens five slots")
	check_eq(AbilityBindingRules.slot_limit(6),6,"level six opens six slots")
	check_eq(AbilityBindingRules.slot_limit(7),6,"level seven keeps six slots")
	check_eq(AbilityBindingRules.canonical_id("FIRE_BOLT"),"FIREBOLT","content alias canonicalizes")
	check_eq(AbilityBindingRules.binding_ids_error(["FIREBOLT","STRIKE"]),
		"","distinct canonical bindings validate")
	check_eq(AbilityBindingRules.binding_ids_error(["FIREBOLT","FIREBOLT"]),
		"duplicate_ability_binding","duplicate binding is rejected")
	check_eq(AbilityBindingRules.binding_ids_error(["FIRE_BOLT"]),
		"invalid_ability_binding_id","alias is not persisted")
	return finish()


func test_bind_consumes_item_persists_and_replays()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var hero:=_grant_ability_item(session,"ABILITY_BIND_01")
	var world=session.sim.world
	check_eq(world.world_state_error(),"","ability fixture is valid")
	var rows:Array=session.ability_binding_rows(hero)
	check_eq(rows.size(),6,"binding DTO exposes six slots")
	check_eq(rows[0].state,"EMPTY","first level slot is empty")
	check_eq(rows[1].state,"LOCKED","second slot is locked at level one")
	var item_rows:Array=session.ability_binding_item_rows(hero)
	check_eq(item_rows.size(),1,"stored ability item is exposed")
	var assessment:Dictionary=session.ability_binding_assessment(hero,"ABILITY_BIND_01")
	check(bool(assessment.accepted),"binding assessment accepts a stored ability item")
	check_eq(assessment.effect_preview.ability_id,"FIREBOLT","assessment exposes canonical effect")
	var result:Dictionary=session.bind_ability_item(hero,"ABILITY_BIND_01")
	check(bool(result.accepted),"binding commit succeeds: "+str(result.get("reason")))
	check_eq(world.party_encounter.member(hero).bound_ability_ids,["FIREBOLT"],
		"binding is persistent on the character")
	check(world.inventory_of(hero).item("ABILITY_BIND_01")==null,
		"binding consumes the acquisition item")
	check_eq(world.item_owner("ABILITY_BIND_01").kind,"NONE","consumed item has no owner")
	check_eq(count_events(world.events,"party.ability_bound"),1,"binding emits one canonical event")
	check_eq(world.world_state_error(),"","bound state passes world audit")
	var encoded:Dictionary=JSON.parse_string(session.save_session_json())
	check_eq(encoded.snapshot.party_encounter.member_rows[0].bound_ability_ids,["FIREBOLT"],
		"bound ability is present in the saved character row")
	check_eq(encoded.journal[-1].kind,"ability","binding journal is serialized")
	var restored_state=PartyEncounter.from_dict(encoded.snapshot.party_encounter)
	check(restored_state!=null,"saved party state restores")
	if restored_state!=null:
		check_eq(restored_state.member(hero).bound_ability_ids,["FIREBOLT"],
			"restored party state keeps exactly one bound ability")
	return finish()


func test_duplicate_and_removal_are_safe_rejections()->bool:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var hero:=_grant_ability_item(session,"ABILITY_BIND_02")
	check(session.bind_ability_item(hero,"ABILITY_BIND_02").accepted,"fixture ability binds")
	_grant_ability_item(session,"ABILITY_BIND_03")
	var before:Dictionary=session.sim.snapshot()
	var duplicate:Dictionary=session.ability_binding_assessment(hero,"ABILITY_BIND_03")
	check(not bool(duplicate.accepted),"duplicate ability is refused before consumption")
	check_eq(duplicate.reason,"ability_already_bound","duplicate rejection is explicit")
	check_eq(session.sim.snapshot(),before,"duplicate assessment is pure")
	var removal:Dictionary=session.ability_removal_assessment(hero,0)
	check(not bool(removal.accepted),"removal remains locked while policy is undefined")
	check_eq(removal.reason,"ability_removal_policy_undefined","removal policy is explicit")
	check_eq(session.sim.snapshot(),before,"locked removal is non-destructive")
	return finish()
