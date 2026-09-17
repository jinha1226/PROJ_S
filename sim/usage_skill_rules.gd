class_name UsageSkillRules
extends RefCounted

# The committed action ledger is the authority. It is already saved and rolled
# back by WorldState; presentation and targeting never write training state.
const IDS := ["SWORD", "SPEAR", "BLUNT", "AXE", "RANGED", "FIRE", "ICE", "AIR",
	"HEX", "SUMMON", "ARMOUR", "DODGING", "STEALTH", "UNARMED"]
const LABELS := {"SWORD":"검", "SPEAR":"창", "BLUNT":"둔기", "AXE":"도끼",
	"RANGED":"활", "FIRE":"화염", "ICE":"냉기", "AIR":"대기", "HEX":"주술",
	"SUMMON":"소환", "ARMOUR":"갑옷", "DODGING":"회피", "STEALTH":"은신", "UNARMED":"맨손"}
const SCHOOLS := {"FIREBOLT":"FIRE", "FIREBALL":"FIRE", "COLD_GLAND":"ICE",
	"FROST_SILK":"ICE", "ARC_GLAND":"AIR", "CHARGE_ORGAN":"AIR", "MEND":"HEX",
	"WATER_SAC":"HEX", "CAUSTIC_BLOOD":"HEX", "SHADOW_VEIL":"STEALTH",
	"ECHO_SENSE":"HEX", "DEEP_EYE":"HEX", "REGENERATIVE_TISSUE":"HEX"}
const JOBS := ["FIGHTER", "RANGER", "MAGE"]
const JOB_LABELS := {"FIGHTER":"전사 · 무기/갑옷", "RANGER":"궁수 · 활/회피", "MAGE":"마법사 · 화염탄/지팡이"}
const MARKER := "progression.usage_initialized"
const POINTS_PER_USE := 20
const USES_PER_OPPONENT := 3

static func enabled(world, before_id:int = 9223372036854775807)->bool:
	if world == null or world.party_encounter == null:return false
	for event in world.events:
		if event.id >= before_id:break
		if event.type == MARKER:return true
	return false

static func initialize(world, job:String="FIGHTER")->bool:
	if job not in JOBS:return false
	if enabled(world):return true
	var hero:int = world.party_encounter.protagonist_id
	var inventory=world.item_state.inventory_rows[hero]
	var stats:Dictionary=preload("res://sim/actor_stat_rules.gd").for_entity(world,hero)
	var candidates:Array=["LEGACY_MAIN_HAND", "START_MACE_001"]
	if job=="RANGER":candidates=["START_BOW_001", "START_CROSSBOW_001"]
	elif job=="MAGE":
		inventory.backpack.append(preload("res://sim/item_instance.gd").new("START_JOB_STAFF", "WEAPON_DCSS_STAFF"))
		candidates=["START_JOB_STAFF", "LEGACY_MAIN_HAND"]
	for item_id in candidates:
		var item=inventory.item(item_id)
		if item==null:continue
		var definition=preload("res://sim/item_registry.gd").definition(item.definition_id)
		if preload("res://sim/actor_stat_rules.gd").requirements_error(stats,definition.requirements).is_empty():
			inventory.equipped["MAIN_HAND"]=item_id;break
	var armor_id:String="ARMOR_CLOTH_ROBE" if job=="MAGE" else "ARMOR_LEATHER"
	inventory.backpack.append(preload("res://sim/item_instance.gd").new("START_JOB_ARMOR", armor_id))
	var armor=preload("res://sim/item_registry.gd").definition(armor_id)
	if preload("res://sim/actor_stat_rules.gd").requirements_error(stats,armor.requirements).is_empty():inventory.equipped["ARMOR"]="START_JOB_ARMOR"
	inventory._sort_backpack()
	if job=="MAGE":world.party_encounter.member(hero).bound_ability_ids.append("FIREBOLT")
	var weapon_id:String=preload("res://sim/world_item_operations.gd").equipped_weapon_id(world,hero)
	var weapon:Dictionary=preload("res://sim/weapon_registry.gd").definition_dict(weapon_id)
	var initial_skill:String=str(weapon.get("proficiency_id","UNARMED")) if job!="MAGE" else "FIRE"
	return world.emit_event(MARKER, hero, -1, world.entities[hero].position, 0, -1,
		{"schema_version":1, "ruleset_id":"legacy-use-skills-v1", "job":job, "initial_skill":initial_skill}) != null

static func starting_job(world)->String:
	for event in world.events:
		if event.type==MARKER:return str(event.data.job)
	return "FIGHTER"

static func totals(world, before_id:int = 9223372036854775807)->Dictionary:
	var cache:Dictionary=world.get_meta("legacy_usage_skills",{})
	var tail=world.events.back() if not world.events.is_empty() else null
	if int(cache.get("count",-1))==world.events.size() and cache.get("tail") == tail:
		return (cache.history.get(before_id,cache.totals) as Dictionary).duplicate(true)
	var history := {}
	var result := {}
	for id in IDS:result[id] = 0
	if not enabled(world):return result
	var hero:int = world.party_encounter.protagonist_id
	var counts := {}
	var dead := {}
	var active := false
	var threats := {}
	var threat_positions := {}
	for event in world.events:
		history[event.id]=result.duplicate(true)
		if event.type == MARKER:
			active = true
			result[str(event.data.initial_skill)]=20
			result["ARMOUR" if event.data.job=="FIGHTER" else "DODGING"]=20
			continue
		if event.type == "entity.died":dead[event.target_id] = true
		if not active:continue
		if event.type == "action.move" and threats.has(event.actor_id):threat_positions[event.actor_id]=event.position
		if event.type == "enemy.awareness_changed" and event.target_id == hero:
			threat_positions[event.actor_id]=event.position
			if str(event.data.get("to_state", "")) in ["UNAWARE", "RETURNING"]:threats.erase(event.actor_id)
			if str(event.data.get("to_state", "")) in ["ALERT", "SUSPICIOUS", "SEARCHING", "HUNTING"]:
				threats[event.actor_id] = event.world_time
				if str(event.data.get("to_state", "")) == "SUSPICIOUS":_credit(result, counts, "STEALTH", event.actor_id)
		if event.type == "party.contact_reported":
			threats[event.target_id] = event.world_time
			threat_positions[event.target_id]=event.position
		if event.type == "action.melee_attack" and event.actor_id in world.party_encounter.enemy_ids and event.target_id == hero:
			threats[event.actor_id] = event.world_time
			if not threat_positions.has(event.actor_id):threat_positions[event.actor_id]=event.position
		if event.type == "action.melee_attack":
			# Misses and parries are genuine attempts. A queued attack on an
			# already dead target (OVERKILL_SKIP) is not a training opportunity.
			if str(event.data.get("outcome", "")) == "OVERKILL_SKIP":continue
			if event.actor_id == hero and event.target_id in world.party_encounter.enemy_ids \
					and not dead.has(event.target_id):
				var weapon_id := str(event.data.get("weapon_id", "UNARMED"))
				if weapon_id in ["DCSS_STAFF", "DCSS_QUARTERSTAFF"]:continue
				var weapon:Dictionary = preload("res://sim/weapon_registry.gd").definition_dict(weapon_id)
				_credit(result, counts, str(weapon.get("proficiency_id", "UNARMED")), event.target_id)
			elif event.target_id == hero and event.actor_id in world.party_encounter.enemy_ids \
					and not dead.has(event.actor_id):
				_credit(result, counts, "DODGING", event.actor_id)
				# Only recorded armour can train armour, not an empty equipment slot.
				if int(event.data.get("equipment_armor_flat", 0)) > 0:
					_credit(result, counts, "ARMOUR", event.actor_id)
		elif event.type in ["action.skill", "ability.cast"] and event.actor_id == hero:
			var school := str(SCHOOLS.get(str(event.data.get("skill_id", "")), ""))
			# Ground/self skills train only during a real encounter. Direct
			# hostile casts use their actual opponent, not a synthetic tile id.
			var opponent:int = event.target_id if event.target_id in world.party_encounter.enemy_ids else -1
			if opponent < 0:
				for id in threats:
					if not dead.has(id) and event.world_time - int(threats[id]) <= 500 and (threat_positions.get(id,event.position) as Vector2i).distance_to(event.position)<=7:
						opponent = id;break
			if opponent > 0 and not dead.has(opponent):_credit(result, counts, school, opponent)
	world.set_meta("legacy_usage_skills",{"count":world.events.size(),"tail":tail,"totals":result,"history":history})
	return (history.get(before_id,result) as Dictionary).duplicate(true)

static func _credit(result:Dictionary, counts:Dictionary, skill:String, opponent:int)->void:
	if not result.has(skill):return
	var key := "%s:%d" % [skill, opponent]
	if int(counts.get(key, 0)) >= USES_PER_OPPONENT:return
	counts[key] = int(counts.get(key, 0)) + 1
	result[skill] = int(result[skill]) + POINTS_PER_USE

static func rank(world, skill:String, before_id:int = 9223372036854775807)->int:
	return rank_for_points(int(totals(world, before_id).get(skill, 0)))

static func floor_for_rank(value:int)->int:return 10 * value * (value + 1)

static func rank_for_points(points:int)->int:
	var value := 0
	while value < 20 and floor_for_rank(value + 1) <= points:value += 1
	return value

static func rows(world)->Array:
	var points := totals(world)
	var result:Array = []
	for id in IDS:
		var value := rank_for_points(int(points[id]))
		var effect := "피해 +%d%%" % (8 * value)
		if id in ["FIRE", "ICE", "AIR", "HEX", "SUMMON"]:effect = "위력 +%d%%" % (10 * value)
		elif id == "ARMOUR":effect = "회피 페널티 완화 %d" % (5 * value)
		elif id == "DODGING":effect = "회피 +%d" % (15 * value)
		elif id == "STEALTH":effect = "은신 +%d" % (20 * value)
		if id == "SUMMON":effect = "현재 소환 능력 없음"
		result.append({"skill_id":id, "label":LABELS[id], "rank":value,
			"training_total":points[id], "training_current":int(points[id])-floor_for_rank(value),
			"training_required":floor_for_rank(value+1)-floor_for_rank(value),
			"training_mode":"USE", "training_mode_label":"사용 성장", "raw_weight":1,
			"effect_label":effect})
	return result

static func scale(world, actor:int, ability:String, value:int, before_id:int=9223372036854775807)->int:
	if not enabled(world) or actor != world.party_encounter.protagonist_id:return value
	var school := str(SCHOOLS.get(ability, ""))
	if school.is_empty():return value
	return maxi(0, (value * (1000 + 100 * rank(world, school, before_id)) + 500) / 1000)

static func marker_error(world,event)->String:
	var keys:Array=event.data.keys();keys.sort()
	if world.party_encounter==null or event.actor_id!=world.party_encounter.protagonist_id or event.target_id!=-1 or event.cause_id!=-1 or event.magnitude!=0 or event.step_index!=0 or event.world_time!=0:
		return "usage_skill_marker_invalid"
	if keys!=["initial_skill","job","ruleset_id","schema_version"] or event.data.schema_version!=1 or event.data.ruleset_id!="legacy-use-skills-v1" or event.data.job not in JOBS or event.data.initial_skill not in IDS or (event.data.job=="MAGE" and event.data.initial_skill!="FIRE") or enabled(world,event.id):return "usage_skill_marker_invalid"
	return ""
