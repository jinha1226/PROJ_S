extends RefCounted

const State=preload("res://sim/body_state.gd")
const Injury=preload("res://sim/body_injury_system.gd")
const Functions=preload("res://sim/body_function_rules.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
const PART_NAMES={"HEAD":"머리","TORSO":"몸통","LEFT_ARM":"왼팔","RIGHT_ARM":"오른팔","LEFT_LEG":"왼다리","RIGHT_LEG":"오른다리"}

static func create(id:int,seed:int,enemy:bool):
	return State.create(id+1,"goblin" if enemy else "human",
		State.world_body_seed(seed,id+1,"goblin" if enemy else "human"))

static func sync(actor:Dictionary)->void:
	var body=actor.body
	var function:Dictionary=Functions.appraisal(body)
	actor.skin=int(body.body_scalars.skin_toughness)
	actor.bone=int(body.body_scalars.bone_fracture_threshold)
	actor.blood=int(100*body.current_blood/int(body.body_scalars.blood_capacity))
	actor.move_factor=100 if function.usable_leg_count==2 else 160 if function.usable_leg_count==1 else 250
	actor.attack_factor=100 if function.usable_arm_count==2 else 75 if function.usable_arm_count==1 else 35

static func hit(source:Dictionary,target:Dictionary,damage:int,armor:int,serial:int,seed:int,weapon_id:String="")->Dictionary:
	var weapon=Weapons.definition(weapon_id if not weapon_id.is_empty() else "SHORT_SWORD" if int(source.attack_factor)>35 else "UNARMED_STRIKE")
	var commitment:=("%d|%d|%d|%d"%[seed,serial,source.id,target.id]).sha256_text()
	var result:Dictionary=Injury.apply(target.body,weapon,damage,armor,commitment,int(target.id)+1,serial)
	sync(target)
	return result

static func heal(actor:Dictionary)->void:
	var body=actor.body
	body.current_blood=mini(int(body.body_scalars.blood_capacity),body.current_blood+int(body.body_scalars.blood_capacity)/5)
	body.shock=maxi(0,body.shock-100)
	# Potions restore blood/HP, but do not regrow or silently repair disabled limbs.
	body.revision+=1
	sync(actor)

static func description(actor:Dictionary)->String:
	var body=actor.body
	var lines:Array[String]=["HP %d/%d · 스트레스 %d"%[actor.hp,actor.max_hp,actor.stress],
		"피부 질김 %d · 뼈 강도 %d"%[actor.skin,actor.bone],
		"혈액 %d/%d (%d%%) · 충격 %d"%[body.current_blood,body.body_scalars.blood_capacity,actor.blood,body.shock]]
	for part in body.parts:
		var integrity:int=1000
		for layer in part.layers:integrity=mini(integrity,int(layer.integrity))
		var condition:String={"FUNCTIONAL":"기능 정상","DISABLED":"기능 상실","SEVERED":"절단"}[part.condition]
		lines.append("%s: %s · 조직 %d%%"%[PART_NAMES[part.part_id],condition,integrity/10])
	lines.append("상처 %d개 · 이동 비용 %d%% · 공격력 %d%%"%[body.wounds.size(),actor.move_factor,actor.attack_factor])
	return "\n".join(lines)
