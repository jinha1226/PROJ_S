class_name PartyActiveSkillService
extends RefCounted

## Campaign adapter for the pure prototype assessment model. It contains no UI
## state and never mutates during assessment.
const Registry=preload("res://sim/abilities/active_skill_registry.gd")
const Effects=preload("res://sim/abilities/active_effect_model.gd")
const ActorStats=preload("res://sim/actor_stat_rules.gd")
const CombatProfiles=preload("res://sim/combat_profile_registry.gd")
const Affinities=preload("res://sim/species_hazard_affinity_registry.gd")
const Terrain=preload("res://sim/terrain_registry.gd")
const PartyPerception=preload("res://sim/party_perception_registry.gd")
const CampaignStream=preload("res://sim/campaign_encounter_stream.gd")
const MoraleModel=preload("res://sim/party_morale_model.gd")

const RULESET_ID := "party-active-skills-v1"
const ACTION_TIMES := {"STRIKE":100,"SHOVE":100,"FIREBOLT":120,"MEND":120,"FIREBALL":120}
const ENABLED_SKILLS := ["STRIKE","SHOVE","FIREBOLT","MEND","FIREBALL"]

static func assess(world,actor_id:int,skill_id:String,target_id:int,allow_busy:bool=false,
		in_transaction:bool=false, ground_position:Vector2i=Vector2i(-1,-1))->Dictionary:
	var rejected:={"accepted":false,"reason":"active_skill_unavailable",
		"message":"지금은 기술을 사용할 수 없습니다.","skill_id":skill_id,
		"actor_id":actor_id,"target_id":target_id,"cost":0,"action_time":0}
	if world==null or world.party_encounter==null:return rejected
	var state=world.party_encounter
	if state.expedition_cycle!=null and str(state.expedition_cycle.phase)=="TOWN":
		return _reject(rejected,"active_skill_combat_required","전투 중에만 사용할 수 있습니다.")
	if (state.safe_phase!="ENGAGED" and not preload("res://sim/field_turn_rules.gd").active(world)) \
			or not world.is_settled() and not in_transaction:
		return _reject(rejected,"active_skill_combat_required","전투 중에만 사용할 수 있습니다.")
	if actor_id not in state.active_party_member_ids or not state.member_rows.has(actor_id) \
			or not world.entities.has(actor_id):
		return _reject(rejected,"active_skill_actor_inactive","활성 파티원이 아닙니다.")
	var member=state.member(actor_id)
	if member.presence!="DEPLOYED" or not world.can_act(actor_id,world.world_time):
		return _reject(rejected,"active_skill_actor_incapacitated","행동할 수 없는 파티원입니다.")
	if not allow_busy and member.busy_until>world.world_time:
		return _reject(rejected,"active_skill_actor_busy","아직 다음 행동을 준비 중입니다.")
	# Anxious (600+) and panicked members cannot focus on an active skill; basic
	# attacks and movement stay available so the pressure reads as "pull back".
	if MoraleModel.stress_band(int(member.stress),str(member.mental_mode)) in ["ANXIOUS","PANIC"]:
		return _reject(rejected,"active_skill_actor_anxious","불안해서 기술에 집중할 수 없습니다.")
	if skill_id not in ENABLED_SKILLS or skill_id not in member.active_skill_ids():
		return _reject(rejected,"active_skill_not_equipped","장착하지 않은 기술입니다.")
	if skill_id=="FIREBALL":
		var definition:=Registry.definition(skill_id)
		if target_id!=-1 or not world.in_bounds(ground_position):
			return _reject(rejected,"active_skill_target_invalid","물이나 바닥을 선택하세요.")
		var origin:Vector2i=world.entities[actor_id].position
		if maxi(absi(origin.x-ground_position.x),absi(origin.y-ground_position.y))>int(definition.range):
			return _reject(rejected,"active_skill_out_of_range","사거리 밖입니다.")
		if not preload("res://sim/enemy_perception_registry.gd").has_line_of_sight(world,origin,ground_position) \
				or PartyPerception.visible_party_members(world,state,ground_position).is_empty():
			return _reject(rejected,"active_skill_target_hidden","보이는 칸을 선택하세요.")
		if member.energy<int(definition.cost):
			return _reject(rejected,"active_skill_energy_insufficient","기력이 부족합니다.")
		return {"accepted":true,"reason":"ok","message":"환경 시험용 화염구",
			"skill_id":skill_id,"actor_id":actor_id,"target_id":-1,"cost":int(definition.cost),
			"action_time":preload("res://sim/field_action_timing.gd").duration(world,actor_id,skill_id,120),
			"damage":0,"healing":0,"destination":ground_position,"ruleset_id":RULESET_ID}
	if not world.entities.has(target_id) or not world.combatant_states.has(target_id):
		return _reject(rejected,"active_skill_target_invalid","대상을 선택하세요.")
	var ally_skill:=skill_id=="MEND"
	if ally_skill and (target_id not in state.active_party_member_ids \
			or state.member(target_id)==null or state.member(target_id).presence!="DEPLOYED"):
		return _reject(rejected,"active_skill_target_invalid","활성 파티원을 선택하세요.")
	if not ally_skill and (target_id not in CampaignStream.active_enemy_ids(world) \
			or not world.is_autonomous_target(target_id)):
		return _reject(rejected,"active_skill_target_invalid","전투 중인 적을 선택하세요.")
	if str(world.combatant_states[target_id].life_state)!="ACTIVE":
		return _reject(rejected,"active_skill_target_incapacitated","쓰러진 대상에게 사용할 수 없습니다.")
	var actors:Array=[_actor(world,actor_id),_actor(world,target_id,skill_id=="MEND")]
	var blocked:Dictionary={}
	var origin:Vector2i=world.entities[actor_id].position
	var destination:Vector2i=world.entities[target_id].position
	for y in range(maxi(0,mini(origin.y,destination.y)-1),
		mini(world.height,maxi(origin.y,destination.y)+2)):
		for x in range(maxi(0,mini(origin.x,destination.x)-1),
			mini(world.width,maxi(origin.x,destination.x)+2)):
			var cell:=Vector2i(x,y)
			if not bool(Terrain.definition(str(world.tile_at(cell).terrain)).get(
					"passable",false)):
				blocked[cell]=true
	if skill_id=="SHOVE":
		var delta:=destination-origin
		var landing:=destination+Vector2i(signi(delta.x),signi(delta.y))
		for occupant in world.occupying_entities_at(landing):
			if int(occupant.id) not in [actor_id,target_id]:actors.append(_actor(world,int(occupant.id)))
	var caster:=_actor(world,actor_id);caster.skills=member.active_skill_ids()
	caster.energy=member.energy
	var target:=_actor(world,target_id,skill_id=="MEND")
	var result:Dictionary=Effects.assess(skill_id,caster,target,actors,blocked,
		Rect2i(Vector2i.ZERO,Vector2i(world.width,world.height)))
	if not bool(result.get("accepted",false)):
		return _reject(rejected,_reason_code(str(result.get("reason",""))),
			str(result.get("reason","기술을 사용할 수 없습니다.")))
	if PartyPerception.visible_party_members(world,state,
			world.entities[target_id].position).is_empty():
		return _reject(rejected,"active_skill_target_hidden","보이지 않는 대상입니다.")
	var definition:=Registry.definition(skill_id)
	var stats:=ActorStats.for_entity(world,actor_id)
	var baseline:=ActorStats.for_species("human")
	var stat_id:="STR" if skill_id in ["STRIKE","SHOVE"] else "INT"
	var scale:=1 if skill_id=="SHOVE" else 2
	var bonus:=(int(stats.get(stat_id,5))-int(baseline.get(stat_id,5)))*scale
	if int(result.damage)>0:
		var raw:=maxi(1,int(definition.power)+bonus)
		if str(definition.element)=="PHYSICAL":raw=maxi(1,raw-int(target.armor))
		var resistance:=clampi(int(target.resistances.get(
			str(definition.element),0)),-25,75)
		result.damage=maxi(1,roundi(raw*(1.0-resistance/100.0)))
	if int(result.healing)>0:
		result.healing=mini(maxi(0,int(target.max_hp)-int(target.hp)),
			mini(recoverable_damage(world,target_id),maxi(1,int(definition.power)+bonus)))
		if int(result.healing)<=0:
			return _reject(rejected,"active_skill_no_recoverable_damage",
				"응급 치유 가능한 피해가 없습니다.")
	result.reason="ok";result.message="사용할 수 있습니다."
	result.actor_id=actor_id
	result.action_time=preload("res://sim/field_action_timing.gd").duration(world,actor_id,skill_id,int(ACTION_TIMES[skill_id]))
	result["ruleset_id"]=RULESET_ID
	return result

static func recoverable_damage(world,target_id:int)->int:
	if world==null or not world.entities.has(target_id):return 0
	var credit:=0;var remainder:=0
	for event in world.events:
		if int(event.target_id)!=target_id:continue
		if event.type in ["combat.physical_damage","combat.fire_damage",
				"combat.electric_damage"]:
			var applied:=int(event.data.get("applied_health_damage",event.magnitude))
			var numerator:=remainder+applied
			credit+=numerator/2;remainder=numerator%2
		elif event.type in ["health.restored","opening.health_restored"]:
			credit=maxi(0,credit-int(event.magnitude))
		elif event.type in ["entity.recovered","town.body_restored"]:
			credit=0;remainder=0
	return mini(credit,
		maxi(0,int(world.entities[target_id].max_health)-int(world.entities[target_id].health)))

static func action_data(assessment:Dictionary)->Dictionary:
	return {"schema_version":1,"ruleset_id":RULESET_ID,
		"skill_id":str(assessment.skill_id),"cost":int(assessment.cost),
		"action_time":int(assessment.action_time),"damage":int(assessment.damage),
		"healing":int(assessment.healing),
		"destination":[assessment.destination.x,assessment.destination.y]}

static func _actor(world,entity_id:int,include_recoverable:bool=false)->Dictionary:
	var entity=world.entities.get(entity_id)
	if entity==null:return {}
	var combatant=world.combatant_states.get(entity_id)
	var profile:=CombatProfiles.profile(str(combatant.combat_profile_id)) \
		if combatant!=null else {}
	var equipment:Dictionary=world.equipment_modifiers(entity_id)
	var totals:Dictionary=equipment.get("totals",{}) if equipment is Dictionary else {}
	var affinity=Affinities.affinity_for(str(entity.species_id))
	var assessment_team:="PARTY" if world.party_encounter!=null \
		and entity_id in world.party_encounter.active_party_member_ids else "ENEMY"
	return {"id":entity_id,"team":assessment_team,"position":entity.position,
		"hp":int(entity.health),"max_hp":int(entity.max_health),"energy":0,
		"skills":[],"armor":int(profile.get("armor_flat",0))+int(totals.get("armor_flat",0)),
		"resistances":{"FIRE":int(affinity.fire_tolerance)},"recoverable":
		(recoverable_damage(world,entity_id) if include_recoverable else 0),
		"life_state":str(combatant.life_state) \
		if combatant!=null else "DEAD"}

static func _reason_code(message:String)->String:
	return {"기력이 부족합니다.":"active_skill_energy_insufficient",
		"대상 진영이 맞지 않습니다.":"active_skill_wrong_team",
		"사거리 밖입니다.":"active_skill_out_of_range",
		"벽에 가려져 있습니다.":"active_skill_no_line_of_sight",
		"밀어낼 빈칸이 없습니다.":"active_skill_shove_blocked",
		"밀어낼 칸에 다른 인물이 있습니다.":"active_skill_shove_occupied",
		"모서리를 통과해 밀 수 없습니다.":"active_skill_shove_corner_blocked",
		"응급 치유 가능한 피해가 없습니다.":"active_skill_no_recoverable_damage"}.get(
		message,"active_skill_rejected")

static func _reject(base:Dictionary,reason:String,message:String)->Dictionary:
	var result:=base.duplicate(true);result.reason=reason;result.message=message
	return result
