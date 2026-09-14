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

static func individual(w)->bool:
	return enabled(w) and preload("res://sim/stage_counterplay.gd").enabled(w)

static func current_actor(w)->int:
	var r:Dictionary=w.party_encounter.round_combat
	return int(r.order[int(r.execution_cursor)]) if active(w) and int(r.execution_cursor)<r.order.size() else -1

static func attack_budget(w,id:int)->int:
	var weapon=Weapons.definition(Items.equipped_weapon_id(w,id))
	var base:int=maxi(1,int(weapon.attack_time)+int(weapon.reload_time)) if weapon!=null else 100
	var member=w.party_encounter.member(id)
	var rate:int=maxi(25,(int(member.action_speeds.ATTACK) if member!=null else 100)+Effects.rate(w,id))
	var duration:int=maxi(1,(base*100+rate-1)/rate)
	return clampi(ROUND_TIME/maxi(1,duration),1,3)

static func remaining_move(w,id:int)->int:
	return maxi(0,move_budget(w,id)-int(w.party_encounter.round_combat.slot_spent.get(str(id),0)))

static func remaining_attacks(w,id:int)->int:
	return maxi(0,attack_budget(w,id)-int(w.party_encounter.round_combat.slot_attacks.get(str(id),0)))

static func move_budget(w,id:int)->int:
	var m=w.party_encounter.member(id)
	var rate:int=maxi(25,int(m.action_speeds.MOVE)+Effects.rate(w,id)) if m!=null else maxi(25,100+Effects.rate(w,id))
	var base:=maxi(1,2*rate/100) if individual(w) else clampi(BASE_MOVE*rate/100,1,6)
	var enemy_role:Dictionary=preload("res://sim/stage_enemy_rules.gd").profile(w,id)
	if not enemy_role.is_empty():base=maxi(1,int(enemy_role.move)*rate/100) if individual(w) else clampi(int(enemy_role.move)*rate/100,1,6)
	var injury:int=preload("res://sim/body_penalty_rules.gd").current(w,id).move_milli
	var delay:=maxi(0,Abilities.move_delay(w,id))
	return clampi(base*1000*100/(injury*(100+delay)),1,3 if individual(w) else 6)

static func reachable_cells(w)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	if not individual(w) or w.party_encounter.round_combat.phase!="PLANNING":return result
	var id:=current_actor(w)
	if w.party_encounter.member(id)==null or not w.can_act(id,w.world_time) or Abilities.anchored(w,id):return result
	var budget:=remaining_move(w,id)
	var origin:Vector2i=w.entities[id].position
	var costs:Dictionary={origin:0};var pending:Array[Vector2i]=[origin]
	var visible:=Field.visible_cells(w)
	var rooms=preload("res://sim/room_transition_rules.gd")
	var terrain=preload("res://sim/terrain_registry.gd")
	while not pending.is_empty():
		var from:Vector2i=pending.pop_front()
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
			var to:Vector2i=from+direction
			if not w.in_bounds(to) or not rooms.same_room(w,origin,to) or not visible.has("%d:%d"%[to.x,to.y]):continue
			if not terrain.definition(w.tile_at(to).terrain).get("passable",false) or not w.diagonal_step_terrain_allowed(from,to):continue
			if w.occupying_entities_at(to).any(func(actor):return actor.id!=id):continue
			var cost:int=int(costs[from])+terrain_cost(w,to)
			if cost>budget or cost>=int(costs.get(to,1000)):continue
			costs[to]=cost;pending.append(to)
	for cell in costs:
		if cell!=origin:result.append(cell)
	result.sort_custom(func(a,b):return a.y<b.y if a.y!=b.y else a.x<b.x)
	return result

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
