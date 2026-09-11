extends RefCounted

# Independent rules for this runtime, not translated DCSS source or balance data.
const ITEMS={
	"SHORT_SWORD":{"label":"단검","slot":"weapon","skill":"SWORD","damage":0,"accuracy":90,"delay":110,"minimum":70,"penetration":0,"body":"SHORT_SWORD"},
	"HAND_AXE":{"label":"손도끼","slot":"weapon","skill":"AXE","damage":4,"accuracy":78,"delay":140,"minimum":90,"penetration":0,"body":"HAND_AXE"},
	"MACE":{"label":"철퇴","slot":"weapon","skill":"BLUNT","damage":2,"accuracy":84,"delay":130,"minimum":85,"penetration":2,"body":"MACE"},
	"SPEAR":{"label":"창","slot":"weapon","skill":"SPEAR","damage":1,"accuracy":92,"delay":125,"minimum":80,"penetration":1,"body":"SPEAR"},
	"UNARMED":{"label":"맨손","slot":"weapon","skill":"UNARMED","damage":-4,"accuracy":88,"delay":90,"minimum":60,"penetration":0,"body":"UNARMED_STRIKE"},
	"CLOTH":{"label":"천옷","slot":"armor","protection":0,"burden":0},
	"LEATHER":{"label":"가죽 갑옷","slot":"armor","protection":2,"burden":2},
	"MAIL":{"label":"사슬 갑옷","slot":"armor","protection":5,"burden":8},
	"NO_SHIELD":{"label":"방패 없음","slot":"shield","block":0,"burden":0},
	"BUCKLER":{"label":"소형 방패","slot":"shield","block":12,"burden":3}}
const SKILLS=["SWORD","AXE","BLUNT","SPEAR","UNARMED","ARMOUR","DODGING","SHIELDS"]
const LABELS=["검술","도끼","둔기","창술","맨손","갑옷","회피","방패"]
const Functions=preload("res://sim/body_function_rules.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
static var _cache:Dictionary={}

static func initialise(actor:Dictionary)->void:
	actor.gear={"weapon":"SHORT_SWORD","armor":"CLOTH" if actor.team=="enemy" else "LEATHER","shield":"NO_SHIELD"}
	actor.skill_xp={}
	for skill in SKILLS:actor.skill_xp[skill]=0
	actor.training="SWORD"

static func level(actor:Dictionary,skill:String)->int:
	var xp:int=actor.skill_xp[skill]
	var value:=0
	while value<20 and xp>=(value+1)*(value+1)*20:value+=1
	return value

static func effective_weapon(actor:Dictionary)->String:
	var id:String=actor.gear.weapon
	if not Functions.weapon_use_error(actor.body,Weapons.definition(ITEMS[id].body)).is_empty():return "UNARMED"
	return id

static func usable_shield(actor:Dictionary)->bool:
	return Functions.appraisal(actor.body).off_hand_available and not Weapons.definition(ITEMS[effective_weapon(actor)].body).two_handed

static func stats(actor:Dictionary)->Dictionary:
	var identity:int=actor.body.get_instance_id()
	# Ordinary wounds do not alter weapon usability: invalidate on arm conditions,
	# not every body revision, so a hit does not rebuild all equipment rules.
	var key:Array=[actor.body.part_condition("LEFT_ARM"),actor.body.part_condition("RIGHT_ARM"),actor.power,actor.attack_factor,actor.gear.values(),actor.skill_xp.values()]
	if _cache.has(identity) and _cache[identity].key==key:return _cache[identity].value
	var id:=effective_weapon(actor)
	var w:Dictionary=ITEMS[id]
	var a:Dictionary=ITEMS[actor.gear.armor]
	var s:Dictionary=ITEMS[actor.gear.shield] if usable_shield(actor) else ITEMS.NO_SHIELD
	var skill:=level(actor,w.skill)
	var burden:=maxi(0,int(a.burden)-level(actor,"ARMOUR")/2)+maxi(0,int(s.burden)-level(actor,"SHIELDS")/2)
	var result:Dictionary={"weapon":id,"body":w.body,"skill":w.skill,
		"damage":maxi(1,(int(actor.power)+int(w.damage)+skill/2)*int(actor.attack_factor)/100),
		"accuracy":mini(99,int(w.accuracy)+skill),
		"delay":maxi(int(w.minimum),int(w.delay)-skill*3)+burden*2,
		"protection":int(a.protection)+level(actor,"ARMOUR")/5,
		"evasion":maxi(0,level(actor,"DODGING")*2-burden),
		"block":int(s.block)+level(actor,"SHIELDS") if int(s.block)>0 else 0,
		"penetration":int(w.penetration),"burden":burden}
	if _cache.size()>=512:_cache.clear()
	_cache[identity]={"key":key,"value":result}
	return result

static func can_equip(actor:Dictionary,id:String)->bool:
	if not ITEMS.has(id):return false
	var item:Dictionary=ITEMS[id]
	if item.slot=="weapon":
		var w=Weapons.definition(item.body)
		if not Functions.weapon_use_error(actor.body,w).is_empty():return false
		if w.two_handed and actor.gear.shield!="NO_SHIELD":return false
	if item.slot=="shield" and id!="NO_SHIELD" and not usable_shield(actor):return false
	return true

static func valid(actor:Dictionary)->bool:
	if not actor.get("gear") is Dictionary or not actor.get("skill_xp") is Dictionary:return false
	if actor.gear.size()!=3 or actor.skill_xp.size()!=SKILLS.size() or actor.get("training") not in SKILLS:return false
	for slot in ["weapon","armor","shield"]:
		var id:Variant=actor.gear.get(slot)
		if not id is String or not ITEMS.has(id) or ITEMS[id].slot!=slot:return false
	for skill in SKILLS:
		var xp:Variant=actor.skill_xp.get(skill)
		if not (xp is int or xp is float) or xp!=floor(xp) or xp<0 or xp>8000:return false
	return true

static func award(actor:Dictionary,amount:int)->void:
	var skill:String=actor.training
	actor.skill_xp[skill]=mini(8000,int(actor.skill_xp[skill])+amount)

static func description(actor:Dictionary)->String:
	var values:=stats(actor)
	var lines:Array[String]=["%s / %s / %s"%[ITEMS[actor.gear.weapon].label,ITEMS[actor.gear.armor].label,ITEMS[actor.gear.shield].label],
		"피해 %d · 기본 명중 %d%% · 공격 시간 %d"%[values.damage,values.accuracy,values.delay],
		"보호 %d · 회피 %d · 방패 %d%%"%[values.protection,values.evasion,values.block]]
	if values.weapon!=actor.gear.weapon:lines.append("부상으로 무기 사용 불가 → 맨손")
	for i in range(SKILLS.size()):
		var skill:String=SKILLS[i]
		lines.append("%s %d · 경험치 %d%s"%[LABELS[i],level(actor,skill),actor.skill_xp[skill]," ← 훈련" if actor.training==skill else ""])
	return "\n".join(lines)
