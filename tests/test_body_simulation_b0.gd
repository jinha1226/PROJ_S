extends "res://tests/test_case.gd"

const Registry = preload("res://sim/body_template_registry.gd")
const BodyState = preload("res://sim/body_state.gd")
const Resolver = preload("res://sim/body_damage_resolver.gd")


func test_registry_exact_players_parts_layers_and_fallback_are_strict() -> bool:
	check_eq(Registry.registry_error(),"","body registry validates")
	check_eq(Registry.player_species_ids(),["beastkin","dwarf","elf","human","orc"],
		"body registry has exact player set")
	for template_id in Registry.template_ids():
		var template:=Registry.template_definition(template_id)
		check_eq(template.parts.map(func(row):return str(row.part_id)),
			Registry.PART_IDS,"%s uses canonical six parts"%template_id)
		for part in template.parts:
			check_eq(part.layers,Registry.LAYER_IDS,"%s/%s uses three layers"%[
				template_id,part.part_id])
	check_eq(Registry.template_for_species("unknown").template_id,"generic_humanoid",
		"non-player seam has an explicit fallback")
	var malformed:=Registry.template_definition("human");malformed["future_key"]=1
	check_eq(Registry.template_error(malformed),"invalid_body_template_keys",
		"unknown template keys are rejected")
	return finish()


func test_body_state_seeded_generation_round_trip_and_strict_malformed_rejection() -> bool:
	var first=BodyState.create(7,"human",12345)
	var same=BodyState.create(7,"human",12345)
	var different=BodyState.create(7,"human",12346)
	check(first!=null and same!=null and different!=null,"seeded bodies create")
	if first==null or same==null or different==null:return finish()
	check_eq(first.to_dict(),same.to_dict(),"same species and seed are byte-equivalent")
	check(first.body_scalars!=different.body_scalars,"different seed varies body scalars")
	check(Registry.scalars_within_template(first.body_scalars,
		Registry.template_for_species("human")),"variation stays within template bounds")
	var wire:Dictionary=first.to_dict()
	check_eq(BodyState.validation_error_for(wire),"","canonical wire validates")
	var restored=BodyState.from_dict(wire)
	check(restored!=null,"canonical wire restores")
	if restored!=null:check_eq(restored.to_dict(),wire,"body wire round trip is exact")
	var unknown:=wire.duplicate(true);unknown["future"]=1
	check_eq(BodyState.validation_error_for(unknown),"invalid_body_state_keys",
		"unknown body keys reject")
	var duplicate:=wire.duplicate(true);duplicate.parts.append(duplicate.parts[0].duplicate(true))
	check_eq(BodyState.validation_error_for(duplicate),"invalid_body_part_rows",
		"duplicate body parts reject")
	var wound_row:={"wound_id":"1","part_id":"TORSO","layer_id":"SKIN",
		"form":"SLASH","severity":1,"bleeding":1,"depth":1,"source_event_id":"9"}
	var duplicate_wounds:=wire.duplicate(true)
	duplicate_wounds.wounds=[wound_row.duplicate(true),wound_row.duplicate(true)]
	check_eq(BodyState.validation_error_for(duplicate_wounds),"invalid_body_wound_rows",
		"duplicate wounds reject")
	var bad_source:=wire.duplicate(true);bad_source.wounds=[wound_row.duplicate(true)]
	bad_source.wounds[0].source_event_id="-1"
	check_eq(BodyState.validation_error_for(bad_source),"invalid_body_wound_rows",
		"invalid wound source event rejects")
	var bool_integer:=wire.duplicate(true);bool_integer.revision=true
	check_eq(BodyState.validation_error_for(bool_integer),"invalid_body_state_scalar",
		"bool-as-int rejects")
	var float_integer:=wire.duplicate(true);float_integer.revision=0.0
	check_eq(BodyState.validation_error_for(float_integer),"invalid_body_state_scalar",
		"float-as-int rejects")
	var unsafe:=wire.duplicate(true);unsafe.entity_id=9007199254740992
	check_eq(BodyState.validation_error_for(unsafe),"invalid_body_entity_id",
		"unsafe JSON integer rejects")
	var canonical_large:=wire.duplicate(true);canonical_large.entity_id="9007199254740992"
	check_eq(BodyState.validation_error_for(canonical_large),"",
		"canonical decimal string safely preserves a large int64")
	return finish()


func test_resolver_is_pure_deterministic_integer_and_forms_are_distinct() -> bool:
	var body=BodyState.create(7,"human",12345)
	var template:=Registry.template_for_species("human")
	var armor:={"slash_protection":5,"pierce_protection":5,
		"impact_padding":5,"rigidity":5}
	var before:Dictionary=body.to_dict()
	var slash:=Resolver.resolve(body,template,"TORSO",
		{"form":"SLASH","base_force":120,"penetration":25,
		"contact_size":20,"stagger_force":20},armor)
	var pierce:=Resolver.resolve(body,template,"TORSO",
		{"form":"PIERCE","base_force":120,"penetration":25,
		"contact_size":20,"stagger_force":20},armor)
	var impact:=Resolver.resolve(body,template,"TORSO",
		{"form":"IMPACT","base_force":120,"penetration":25,
		"contact_size":20,"stagger_force":20},armor)
	check_eq(body.to_dict(),before,"resolver does not mutate BodyState")
	check_eq(Resolver.resolve(body,template,"TORSO",
		{"form":"SLASH","base_force":120,"penetration":25,
		"contact_size":20,"stagger_force":20},armor),slash,
		"same input resolves identically")
	var float_packet:={"form":"SLASH","base_force":120.0,"penetration":25,
		"contact_size":20,"stagger_force":20}
	check_eq(Resolver.resolve(body,template,"TORSO",float_packet,armor).reason,
		"invalid_attack_packet","float attack input rejects")
	check(int(slash.bleed)>int(impact.bleed),"slash bleeds more than impact")
	check(int(pierce.depth)>int(slash.depth),"pierce reaches deeper than slash")
	check(int(impact.shock)>int(slash.shock) \
		and int(impact.fracture)>int(slash.fracture),
		"impact produces more shock and fracture than slash")
	for result in [slash,pierce,impact]:
		for key in ["damage","bleed","depth","shock","fracture","vital_risk"]:
			check(result[key] is int,"%s result is integer"%key)
	return finish()


func test_runtime_body_fields_cannot_launder_unknown_keys_tags_or_coerced_wounds() -> bool:
	var invalid_seed=BodyState.create(7,"human",12345)
	invalid_seed.body_seed=-1
	check_eq(invalid_seed.validation_error(),"invalid_body_seed",
		"runtime body seed mutation rejects")
	var extra_part=BodyState.create(7,"human",12345)
	extra_part.parts[0]["future"]=1
	check_eq(extra_part.validation_error(),"invalid_body_part_rows",
		"runtime part unknown keys reject")
	var vital=BodyState.create(7,"human",12345)
	vital.parts[0].vital_tags=[]
	check_eq(vital.validation_error(),"invalid_body_part_rows",
		"runtime vital tag mutation rejects")
	var coerced=BodyState.create(7,"human",12345)
	coerced.wounds.append({"wound_id":true,"part_id":"TORSO","layer_id":"SKIN",
		"form":"SLASH","severity":1,"bleeding":1,"depth":1,"source_event_id":"9"})
	check_eq(coerced.validation_error(),"invalid_body_wound_rows",
		"runtime bool/string wound identifiers reject without coercion")
	return finish()


func test_armor_can_zero_damage_and_species_differences_stay_on_declared_axes() -> bool:
	var attack:={"form":"IMPACT","base_force":120,"penetration":25,
		"contact_size":20,"stagger_force":20}
	var no_armor:={"slash_protection":0,"pierce_protection":0,
		"impact_padding":0,"rigidity":0}
	var full_armor:={"slash_protection":500,"pierce_protection":500,
		"impact_padding":500,"rigidity":500}
	var human=BodyState.create(1,"human",88)
	var blocked:=Resolver.resolve(human,Registry.template_for_species("human"),
		"TORSO",attack,full_armor)
	check_eq([blocked.damage,blocked.deflected],[0,true],
		"sufficient armor can fully deflect without minimum damage")
	var dwarf=BodyState.create(2,"dwarf",88)
	var dwarf_changed:Array=[]
	for scalar_id in Registry.SCALAR_IDS:
		if dwarf.body_scalars[scalar_id]!=human.body_scalars[scalar_id]:dwarf_changed.append(scalar_id)
	check_eq(dwarf_changed,["bone_fracture_threshold"],
		"dwarf generated body differs only on the bone axis")
	var human_impact:=Resolver.resolve(human,Registry.template_for_species("human"),
		"LEFT_ARM",attack,no_armor)
	var dwarf_impact:=Resolver.resolve(dwarf,Registry.template_for_species("dwarf"),
		"LEFT_ARM",attack,no_armor)
	check_eq([dwarf_impact.damage,dwarf_impact.bleed,dwarf_impact.depth,dwarf_impact.shock],
		[human_impact.damage,human_impact.bleed,human_impact.depth,human_impact.shock],
		"dwarf changes no non-bone outcome")
	check(int(dwarf_impact.fracture)<int(human_impact.fracture),
		"dwarf difference appears on the bone axis")
	var orc=BodyState.create(3,"orc",88)
	var orc_changed:Array=[]
	for scalar_id in Registry.SCALAR_IDS:
		if orc.body_scalars[scalar_id]!=human.body_scalars[scalar_id]:orc_changed.append(scalar_id)
	check_eq(orc_changed,["blood_capacity","shock_threshold","soft_tissue_cushioning"],
		"orc generated body differs only on soft tissue, blood and shock axes")
	var orc_impact:=Resolver.resolve(orc,Registry.template_for_species("orc"),
		"LEFT_ARM",attack,no_armor)
	check_eq([orc_impact.depth,orc_impact.fracture],
		[human_impact.depth,human_impact.fracture],
		"orc changes no skin-depth or bone outcome")
	check(orc_impact.damage!=human_impact.damage or orc_impact.bleed!=human_impact.bleed \
		or orc_impact.shock!=human_impact.shock,
		"orc difference appears on soft-tissue/blood/shock axes")
	return finish()
