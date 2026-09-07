extends RefCounted
## Adapter to production B1 injury rules. No invented fire or bleeding ticks.
const Body=preload("res://sim/body_state.gd")
const Injury=preload("res://sim/body_injury_system.gd")
const Functions=preload("res://sim/body_function_rules.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
const AttackRules=preload("res://sim/weapon_attack_rules.gd")
var enabled:bool=true
var bodies:Dictionary={}
var event_id:int=0
var physical_hits:int=0
var unsupported_fire_hits:int=0
var elemental_hits:int=0
var weapons:Dictionary={}
var limb_errors:Dictionary={}

func reset(actors:Array,seed:int)->void:
	bodies.clear();limb_errors.clear();event_id=0;physical_hits=0;unsupported_fire_hits=0;elemental_hits=0
	for actor in actors:
		bodies[int(actor.id)]=Body.create(int(actor.id),str(actor.species_id),Body.world_body_seed(seed,int(actor.id),str(actor.species_id)))

func weapon_for(actor:Dictionary,kind:String):
	var weapon=definition("UNARMED_STRIKE" if kind=="SHOVE" else str(actor.get("weapon_id","SHORT_SWORD")))
	if enabled and kind=="ATTACK" and not limb_error(actor,weapon).is_empty():return definition("UNARMED_STRIKE")
	return weapon

func definition(id:String):
	if not weapons.has(id):weapons[id]=Weapons.definition(id)
	return weapons[id]

func limb_error(actor:Dictionary,weapon)->String:
	var body=bodies.get(int(actor.id))
	if body==null:return "invalid_body_state"
	var key:String="%d:%d:%s"%[body.entity_id,body.revision,weapon.weapon_id]
	if not limb_errors.has(key):limb_errors[key]=Functions.weapon_use_error(body,weapon)
	return str(limb_errors[key])

func use_error(actor:Dictionary,kind:String)->String:
	if not enabled or kind not in ["ATTACK","STRIKE","SHOVE"]:return ""
	return limb_error(actor,weapon_for(actor,kind))

func basic_power(actor:Dictionary)->int:
	var weapon=weapon_for(actor,"ATTACK")
	if enabled and str(weapon.weapon_id)!=str(actor.get("weapon_id","SHORT_SWORD")):
		# Lab power is a pre-resolved rank-0 baseline. Remove the equipped
		# weapon contribution and use the real fallback weapon calculation.
		var equipped=definition(str(actor.get("weapon_id","SHORT_SWORD")))
		var spec:Dictionary=AttackRules.build_attack_spec(str(weapon.weapon_id),0,maxi(0,int(actor.power)-int(equipped.base_damage)),0,0,0)
		return int(spec.normal_final_damage)
	return int(actor.power)

func plan(source:Dictionary,target:Dictionary,kind:String,amount:int,seed:int,now:int)->Dictionary:
	if not enabled or amount<=0:return {"accepted":true,"skip":true}
	var body=bodies.get(int(target.id))
	var weapon=weapon_for(source,kind)
	var key:String=("active-body-v1|%d|%d|%d|%d|%d|%s"%[seed,now,event_id+1,source.id,target.id,kind]).sha256_text()
	# Apply to a copy first, so an invalid injury cannot half-spend energy/HP.
	var copy=Body.from_dict(body.to_dict()) if body!=null else null
	var element:String="FIRE" if kind=="FIREBOLT" else ("ELECTRIC" if kind=="ELECTRIC" else "")
	var result:Dictionary=Injury.apply_element(copy,element,amount,key,int(target.id),event_id+1) if not element.is_empty() else Injury.apply(copy,weapon,amount,int(target.armor),key,int(target.id),event_id+1)
	if not result.accepted:return result
	return {"accepted":true,"skip":false,"body":copy,"result":result,"target":int(target.id),"element":element}

func commit(plan:Dictionary)->void:
	if plan.get("unsupported_fire",false):unsupported_fire_hits+=1
	if plan.get("skip",false):return
	bodies[int(plan.target)]=plan.body;event_id+=1
	if str(plan.get("element","")).is_empty():physical_hits+=1
	else:elemental_hits+=1

func summary()->Dictionary:
	var wounds:int=0;var disabled:int=0;var severed:int=0;var blood_lost:int=0
	for body in bodies.values():
		wounds+=body.wounds.size();blood_lost+=int(body.body_scalars.blood_capacity)-int(body.current_blood)
		for part in body.parts:
			if part.condition=="DISABLED":disabled+=1
			elif part.condition=="SEVERED":severed+=1
	return {"physical_hits":physical_hits,"elemental_hits":elemental_hits,"unsupported_fire_hits":unsupported_fire_hits,"wounds":wounds,"disabled":disabled,"severed":severed,"blood_lost":blood_lost}
