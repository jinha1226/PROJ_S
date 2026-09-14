extends RefCounted
const State=preload("res://sim/round_combat_state.gd")
const Field=preload("res://sim/field_turn_rules.gd")
const Effects=preload("res://sim/consumable_effects.gd")
const Abilities=preload("res://sim/abilities/monster_ability_runtime.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
const Items=preload("res://sim/world_item_operations.gd")
const ROUND_TIME:=100
const BASE_MOVE:=3
const TAG:="round_planned_combat_v1"

static func enabled(w)->bool:
	return Field.enabled(w) and TAG in w.entities[w.party_encounter.protagonist_id].tags

static func active(w)->bool:
	return enabled(w) and w.party_encounter.round_combat.phase!="EXPLORATION"

static func initiative(w,id:int)->int:
	# Harmonic mean of three independent action rates, not DEX or injury delay.
	var m=w.party_encounter.member(id)
	var rates:Dictionary=m.action_speeds if m!=null else {"MOVE":100,"ATTACK":100,"CAST":100}
	var bonus:=Effects.rate(w,id)
	var weapon=Weapons.definition(Items.equipped_weapon_id(w,id))
	var attack_base:int=maxi(1,int(weapon.attack_time)+int(weapon.reload_time)) if m!=null and weapon!=null else 100
	var move_rate:=maxi(25,int(rates.MOVE)+bonus)
	var attack_rate:=maxi(25,int(rates.ATTACK)+bonus)
	var cast_rate:=maxi(25,int(rates.CAST)+bonus)
	var total:=10000/move_rate+100*attack_base/attack_rate+10000/cast_rate
	return maxi(1,30000/maxi(1,total))

static func order(w,ids:Array)->Array:
	var result:Array=ids.map(func(id):return str(id))
	result.sort_custom(func(a,b):
		var left:=initiative(w,int(a));var right:=initiative(w,int(b))
		return left>right if left!=right else int(a)<int(b))
	return result

static func move_budget(w,id:int)->int:
	var m=w.party_encounter.member(id)
	var rate:int=maxi(25,int(m.action_speeds.MOVE)+Effects.rate(w,id)) if m!=null else maxi(25,100+Effects.rate(w,id))
	var base:=clampi(BASE_MOVE*rate/100,1,6)
	var enemy_role:Dictionary=preload("res://sim/stage_enemy_rules.gd").profile(w,id)
	if not enemy_role.is_empty():base=clampi(int(enemy_role.move)*rate/100,1,6)
	var injury:int=preload("res://sim/body_penalty_rules.gd").current(w,id).move_milli
	var delay:=maxi(0,Abilities.move_delay(w,id))
	return maxi(1,base*1000*100/(injury*(100+delay)))

static func terrain_cost(w,cell:Vector2i)->int:
	return maxi(1,ceili(float(preload("res://sim/terrain_registry.gd").definition(w.tile_at(cell).terrain).move_time_cost)/100.0))

static func relevant_enemies(w)->Array:
	var result:Array=[]
	for id in w.party_encounter.enemy_ids:
		if not preload("res://sim/room_transition_rules.gd").actor_active(w,id):continue
		if not w.is_unresolved_enemy(id):continue
		var a=w.party_encounter.enemy_awareness(id)
		# Party enemy awareness stores only party pursuit, not unrelated NPC fights.
		if Field.visible(w,id) or a!=null and a.awareness_state in ["ALERT","HUNTING","SEARCHING"]:result.append(id)
	return result

static func engaged(w)->bool:
	return Field.active(w) and w.party_encounter.safe_phase!="PARTY_DEFEATED" and not relevant_enemies(w).is_empty()
