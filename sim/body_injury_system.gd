class_name BodyInjurySystem
extends RefCounted

const RULESET_ID:="body-injury-b1-v1"
const MAX_SMALL_VALUE:=2147483647
const BodyRegistryScript=preload("res://sim/body_template_registry.gd")
const CombatRulesScript=preload("res://sim/body_combat_rules.gd")
const ResolverScript=preload("res://sim/body_damage_resolver.gd")


static func assess(body,weapon,raw_damage:int,armor_flat:int,
		commitment_hash:String,target_id:int)->Dictionary:
	var rejected:={"accepted":false,"reason":"invalid_body_injury_input"}
	if body==null or not body.has_method("validation_error") \
			or not body.validation_error().is_empty() or target_id!=body.entity_id \
			or weapon==null or not weapon.has_method("validation_error") \
			or not weapon.validation_error().is_empty() or raw_damage<=0 \
			or armor_flat<0 or commitment_hash.length()!=64:
		return rejected.duplicate(true)
	var part_id:String=CombatRulesScript.select_part(body,commitment_hash,target_id)
	var attack:Dictionary=CombatRulesScript.attack_packet(weapon,raw_damage)
	var armor:Dictionary=CombatRulesScript.armor_packet(armor_flat)
	var template:Dictionary=BodyRegistryScript.template_definition(str(body.template_id))
	if part_id.is_empty() or attack.is_empty() or armor.is_empty() or template.is_empty():
		return rejected.duplicate(true)
	var resolution:Dictionary=ResolverScript.resolve(body,template,part_id,attack,armor)
	if not bool(resolution.get("accepted",false)):
		return {"accepted":false,"reason":str(resolution.get("reason","body_resolution_failed"))}
	var part_index:int=BodyRegistryScript.PART_IDS.find(part_id)
	var layer_damage:Dictionary={};var projected_integrity:Dictionary={}
	var resolution_keys:={"SKIN":"damage","SOFT_TISSUE":"depth","BONE":"fracture"}
	for layer_index in range(BodyRegistryScript.LAYER_IDS.size()):
		var layer_id:String=BodyRegistryScript.LAYER_IDS[layer_index]
		var current:int=int(body.parts[part_index].layers[layer_index].integrity)
		var requested:int=int(int(resolution[resolution_keys[layer_id]]) \
			* CombatRulesScript.layer_loss_milli(layer_id)/1000)
		var applied:int=mini(current,maxi(0,requested))
		layer_damage[layer_id]=applied;projected_integrity[layer_id]=current-applied
	var current_condition:String=body.part_condition(part_id)
	var projected_condition:String=current_condition
	if part_id in body.LIMB_PART_IDS and current_condition!="SEVERED":
		var severed:bool=str(resolution.form)==CombatRulesScript.sever_form()
		for layer_id in CombatRulesScript.sever_zero_layers():
			severed=severed and int(projected_integrity[layer_id])==0
		if severed:projected_condition="SEVERED"
		elif current_condition=="FUNCTIONAL":
			for layer_id in CombatRulesScript.disable_zero_layers():
				if int(projected_integrity[layer_id])==0:
					projected_condition="DISABLED";break
	var layer_total:int=0
	for value in layer_damage.values():layer_total+=int(value)
	var mutated:bool=layer_total>0 or int(resolution.bleed)>0 or int(resolution.shock)>0 \
		or projected_condition!=current_condition
	var creates_wound:bool=layer_total>0 or int(resolution.bleed)>0 \
		or int(resolution.depth)>0 or int(resolution.fracture)>0
	# Capacity is part of preflight so the caller never commits canonical HP and
	# events only to discover that the parallel body ledger cannot accept them.
	if mutated and body.revision>=MAX_SMALL_VALUE:
		return {"accepted":false,"reason":"body_injury_capacity_exhausted"}
	if creates_wound and (body.wounds.size()>=MAX_SMALL_VALUE \
			or not body.wounds.is_empty() and int(body.wounds[-1].wound_id)>=MAX_SMALL_VALUE):
		return {"accepted":false,"reason":"body_injury_capacity_exhausted"}
	return {"accepted":true,"reason":"","ruleset_id":RULESET_ID,
		"body_combat_ruleset_id":CombatRulesScript.RULESET_ID,"target_id":target_id,
		"weapon_id":str(weapon.weapon_id),"part_id":part_id,
		"attack_packet":attack,"armor_packet":armor,"resolution":resolution,
		"layer_damage":layer_damage,"projected_integrity":projected_integrity,
		"condition_before":current_condition,"condition_after":projected_condition,
		"creates_wound":creates_wound,"mutated":mutated}.duplicate(true)


static func apply(body,weapon,raw_damage:int,armor_flat:int,
		commitment_hash:String,target_id:int,source_event_id:int)->Dictionary:
	var plan:Dictionary=assess(body,weapon,raw_damage,armor_flat,commitment_hash,target_id)
	if not bool(plan.get("accepted",false)):return plan
	if source_event_id<=0:return {"accepted":false,"reason":"invalid_injury_source_event"}
	if not bool(plan.mutated):
		return {"accepted":true,"reason":"","mutated":false,"plan":plan}.duplicate(true)
	if body.revision>=MAX_SMALL_VALUE \
			or bool(plan.creates_wound) and body.wounds.size()>=MAX_SMALL_VALUE:
		return {"accepted":false,"reason":"body_injury_capacity_exhausted"}
	var wound_id:=-1
	if bool(plan.creates_wound):
		wound_id=1 if body.wounds.is_empty() else int(body.wounds[-1].wound_id)+1
		if wound_id<=0 or wound_id>MAX_SMALL_VALUE:
			return {"accepted":false,"reason":"body_injury_capacity_exhausted"}
	var part_index:int=BodyRegistryScript.PART_IDS.find(str(plan.part_id))
	for layer_index in range(BodyRegistryScript.LAYER_IDS.size()):
		var layer_id:String=BodyRegistryScript.LAYER_IDS[layer_index]
		body.parts[part_index].layers[layer_index].integrity=int(plan.projected_integrity[layer_id])
	var resolution:Dictionary=plan.resolution
	body.current_blood=maxi(0,body.current_blood-int(resolution.bleed))
	body.shock=mini(MAX_SMALL_VALUE,body.shock+int(resolution.shock))
	if bool(plan.creates_wound):
		var deepest_layer:String="SKIN"
		for layer_id in ["SOFT_TISSUE","BONE"]:
			if int(plan.layer_damage[layer_id])>0:deepest_layer=layer_id
		body.wounds.append({"wound_id":wound_id,"part_id":str(plan.part_id),
			"layer_id":deepest_layer,"form":str(resolution.form),
			"severity":mini(MAX_SMALL_VALUE,int(resolution.damage)+int(resolution.depth)
				+int(resolution.fracture)),"bleeding":mini(MAX_SMALL_VALUE,int(resolution.bleed)),
			"depth":mini(MAX_SMALL_VALUE,int(resolution.depth)),
			"source_event_id":source_event_id})
	if str(plan.condition_after)!=str(plan.condition_before):
		body.parts[part_index].condition=str(plan.condition_after)
		body.parts[part_index].condition_source_event_id=source_event_id
	body.revision+=1
	var error:String=body.validation_error()
	if not error.is_empty():return {"accepted":false,"reason":error}
	return {"accepted":true,"reason":"","mutated":true,"wound_id":wound_id,
		"part_id":str(plan.part_id),"condition":str(plan.condition_after),
		"plan":plan}.duplicate(true)
