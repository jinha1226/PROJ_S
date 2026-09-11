extends RefCounted

const Loader=preload("res://sim/json_content_loader.gd")
const Growth=preload("res://game/rebuilt/progression.gd")
static var ITEMS:Dictionary=Loader.load_document("res://data/content/rebuilt_equipment.json").items
const Functions=preload("res://sim/body_function_rules.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
static var _cache:Dictionary={}

static func initialise(actor:Dictionary)->void:
	actor.gear={"weapon":"SHORT_SWORD","armor":"CLOTH" if actor.team=="enemy" else "LEATHER","shield":"NO_SHIELD"}
	Growth.initialise(actor)

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
	var key:Array=[actor.body.part_condition("LEFT_ARM"),actor.body.part_condition("RIGHT_ARM"),actor.power,actor.attack_factor,actor.gear.values(),actor.growth.ranks.values()]
	if _cache.has(identity) and _cache[identity].key==key:return _cache[identity].value
	var id:=effective_weapon(actor)
	var w:Dictionary=ITEMS[id]
	var a:Dictionary=ITEMS[actor.gear.armor]
	var s:Dictionary=ITEMS[actor.gear.shield] if usable_shield(actor) else ITEMS.NO_SHIELD
	var burden:=int(a.burden)+int(s.burden)
	var base:=maxi(1,(int(actor.power)+int(w.damage))*int(actor.attack_factor)/100)
	var result:Dictionary={"weapon":id,"body":w.body,"skill":w.skill,
		"base_damage":base,"damage":Growth.scale(actor,w.skill,base),
		"accuracy":int(w.accuracy),
		"delay":int(w.delay)+burden*2,
		"protection":int(a.protection),
		"evasion":0,
		"block":int(s.block),
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
	if not actor.get("gear") is Dictionary:return false
	if actor.gear.size()!=3:return false
	for slot in ["weapon","armor","shield"]:
		var id:Variant=actor.gear.get(slot)
		if not id is String or not ITEMS.has(id) or ITEMS[id].slot!=slot:return false
	return Growth.valid(actor.get("growth"))

static func description(actor:Dictionary)->String:
	var values:=stats(actor)
	var lines:Array[String]=["%s / %s / %s"%[ITEMS[actor.gear.weapon].label,ITEMS[actor.gear.armor].label,ITEMS[actor.gear.shield].label],
		"피해 %d · 기본 명중 %d%% · 공격 시간 %d"%[values.damage,values.accuracy,values.delay],
		"보호 %d · 회피 %d · 방패 %d%%"%[values.protection,values.evasion,values.block]]
	if values.weapon!=actor.gear.weapon:lines.append("부상으로 무기 사용 불가 → 맨손")
	lines.append("숙련 피해 감소 %d%%"%[Growth.reduction(actor)/10])
	return "\n".join(lines)
