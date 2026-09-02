class_name BodyDamageResolver
extends RefCounted

const RegistryScript=preload("res://sim/body_template_registry.gd")
const FORMS:=["SLASH","PIERCE","IMPACT"]
const PACKET_MAX:=100000


static func resolve(body,template:Variant,part_id:String,attack:Variant,armor:Variant)->Dictionary:
	var input_error:=_input_error(body,template,part_id,attack,armor)
	if not input_error.is_empty():return {"accepted":false,"reason":input_error}.duplicate(true)
	var form:=str(attack.form)
	var force:=int(attack.base_force)*20/int(attack.contact_size)
	var penetration:=int(attack.penetration)
	var stagger_force:=int(attack.stagger_force)
	var skin:=int(body.body_scalars.skin_toughness)
	var soft:=int(body.body_scalars.soft_tissue_cushioning)
	var bone:=int(body.body_scalars.bone_fracture_threshold)
	var blood_capacity:=int(body.body_scalars.blood_capacity)
	var shock_threshold:=int(body.body_scalars.shock_threshold)
	var damage:=0;var bleed:=0;var depth:=0;var shock:=0;var fracture:=0
	var absorbed_force:=0
	match form:
		"SLASH":
			var barrier:=int(armor.slash_protection)+skin
			var exposure:=maxi(0,force+penetration/2-barrier)
			damage=exposure
			depth=maxi(0,(penetration+exposure/4-int(armor.rigidity))/2)
			bleed=(damage*3+depth*2)*1000/blood_capacity
			shock=(stagger_force+damage/4)*100/shock_threshold
			fracture=maxi(0,force/2+stagger_force/2-int(armor.impact_padding)-bone)/4
			absorbed_force=mini(force,barrier)
		"PIERCE":
			var barrier:=int(armor.pierce_protection)+int(armor.rigidity)+skin
			var drive:=maxi(0,force+penetration*2-barrier)
			damage=drive
			depth=drive/2
			bleed=(damage*2+depth)*1000/blood_capacity
			shock=(stagger_force+damage/3)*100/shock_threshold
			fracture=maxi(0,penetration+force/4-int(armor.rigidity)-bone)/3
			absorbed_force=mini(force,barrier)
		"IMPACT":
			var barrier:=int(armor.impact_padding)+soft
			var transfer:=maxi(0,force+stagger_force-barrier)
			damage=transfer/2
			depth=maxi(0,force-int(armor.impact_padding)-skin)/8
			bleed=(damage*1000/blood_capacity)/5
			shock=transfer*100/shock_threshold+stagger_force
			fracture=maxi(0,force+stagger_force/2-int(armor.impact_padding) \
				-int(armor.rigidity)/2-bone)/2
			absorbed_force=mini(force,barrier)
	var part:Dictionary=template.parts[RegistryScript.PART_IDS.find(part_id)]
	var vital_risk:=0
	if not part.vital_tags.is_empty():
		vital_risk=(depth*2+damage/4) if form=="PIERCE" else (
			bleed/2 if form=="SLASH" else shock/3)
	return {"accepted":true,"reason":"","form":form,"part_id":part_id,
		"damage":damage,"bleed":bleed,"depth":depth,"shock":shock,
		"fracture":fracture,"vital_risk":vital_risk,"deflected":damage==0,
		"absorbed_force":absorbed_force}.duplicate(true)


static func _input_error(body,template:Variant,part_id:String,attack:Variant,
		armor:Variant)->String:
	if body==null or not body.has_method("validation_error") \
			or not body.validation_error().is_empty():return "invalid_body_state"
	if not template is Dictionary or not RegistryScript.template_error(template).is_empty():
		return "invalid_body_template"
	if str(template.template_id)!=str(body.template_id):return "body_template_mismatch"
	if part_id not in RegistryScript.PART_IDS:return "unknown_body_part"
	if not attack is Dictionary:return "invalid_attack_packet"
	var attack_keys:Array=attack.keys();attack_keys.sort()
	if attack_keys!=["base_force","contact_size","form","penetration","stagger_force"] \
			or not attack.form is String or str(attack.form) not in FORMS:
		return "invalid_attack_packet"
	for key in ["base_force","penetration","contact_size","stagger_force"]:
		if not attack.get(key) is int or int(attack[key])<0 \
				or int(attack[key])>PACKET_MAX:return "invalid_attack_packet"
	if int(attack.contact_size)<=0:return "invalid_attack_packet"
	if not armor is Dictionary:return "invalid_armor_packet"
	var armor_keys:Array=armor.keys();armor_keys.sort()
	if armor_keys!=["impact_padding","pierce_protection","rigidity","slash_protection"]:
		return "invalid_armor_packet"
	for key in armor_keys:
		if not armor[key] is int or int(armor[key])<0 or int(armor[key])>PACKET_MAX:
			return "invalid_armor_packet"
	return ""
