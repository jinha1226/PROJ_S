extends SceneTree

const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const TerrainRegistry=preload("res://sim/terrain_registry.gd")

var errors:Array[String]=[]


func _init()->void:
	call_deferred("_run")


func _run()->void:
	var hit_case:Dictionary=await _exercise_product_bump(44,0)
	var miss_case:Dictionary=await _exercise_product_bump(4,1)
	_check(bool(hit_case.get("hit",false)),"seed 44 product bump owns the HIT swing")
	_check(bool(miss_case.get("miss",false)),"seed 4/wait 1 product bump owns the MISS swing")
	for row in [hit_case,miss_case]:
		_check(bool(row.get("drawn",false)),
			"%s bump survives refresh and owns at least one drawn weapon frame"%row.get("label","case"))
		_check(bool(row.get("enemy_swing",false)),
			"%s same-turn enemy counterattack owns an independent swing"%row.get("label","case"))
		_check(bool(row.get("mapping_neutral",false)),
			"%s VFX changes neither mapping nor logical hit rectangle"%row.get("label","case"))
	if errors.is_empty():print("PASS product bump melee VFX smoke")
	else:
		for error in errors:printerr("FAIL product bump melee VFX smoke -- "+error)
	quit(1 if not errors.is_empty() else 0)


func _exercise_product_bump(world_seed:int,exploration_waits:int)->Dictionary:
	var session=Session.new(world_seed,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	for _wait in range(exploration_waits):
		_check(bool(session.commit_exploration_direction(Vector2i.ZERO).accepted),
			"seed %d exploration wait is accepted"%world_seed)
	_check(bool(session.commit_exploration_direction(Vector2i.RIGHT).accepted),
		"seed %d solo fixture reaches contact"%world_seed)
	var sandbox=Sandbox.new();sandbox.size=Vector2(360,640)
	sandbox.initialize_for_headless_test(session,true);root.add_child(sandbox)
	await process_frame
	sandbox.size=Vector2(360,640);sandbox._refresh()
	var status:Dictionary=session.party_status()
	_check(str(status.get("safe_phase",""))=="ENGAGED",
		"seed %d product facade enters combat"%world_seed)
	var hero:=int(status.protagonist_id);var enemy:=int(status.visible_enemy_ids[0])
	var hero_position:Vector2i=session.sim.world.entities[hero].position
	_check(_relocate_with_move_events(session.sim,enemy,hero_position+Vector2i.RIGHT),
		"seed %d enemy is canonically adjacent for bump input"%world_seed)
	sandbox._refresh();sandbox.grid.size=sandbox.grid.custom_minimum_size
	var mapping:Array=sandbox.grid.mapping_signature()
	var hero_hit:Rect2=sandbox.grid.actor_hit_rect(hero)
	sandbox.grid.melee_vfx.clear();sandbox._on_product_direction(Vector2i.RIGHT)
	await process_frame;await process_frame
	var hero_effect:Dictionary={};var enemy_swing:=false
	for effect in sandbox.grid.melee_vfx.active_effects():
		if Vector2i(effect.attacker_grid_pos)==hero_position:hero_effect=effect
		elif Vector2i(effect.attacker_grid_pos)==hero_position+Vector2i.RIGHT:enemy_swing=true
	var drawn:=false
	if not hero_effect.is_empty():
		var actor_spec:Dictionary=sandbox.grid.actor_glyph_draw_spec(hero)
		var swing:Dictionary=actor_spec.get("weapon_swing",{})
		if bool(swing.get("active",false)):
			var params:Dictionary=sandbox.grid.melee_vfx.parameter_spec()
			var settled:Dictionary=sandbox.grid.actor_glyph_draw_spec(hero,
				int(hero_effect.started_at_ms)+int(params.swing_duration_ms))
			var travel:=Vector2(actor_spec.equipment.weapon_center).distance_to(
				Vector2(settled.equipment.weapon_center))
			drawn=travel>=2.0 and int(hero_effect.get("rendered_frames",0))>=1
	var result:={"label":"HIT" if world_seed==44 else "MISS",
		"hit":not hero_effect.is_empty() and bool(hero_effect.get("draw_impact",true)),
		"miss":not hero_effect.is_empty() and not bool(hero_effect.get("draw_impact",true)),
		"drawn":drawn,"enemy_swing":enemy_swing,
		"mapping_neutral":sandbox.grid.mapping_signature()==mapping \
			and sandbox.grid.actor_hit_rect(hero)==hero_hit}
	sandbox.queue_free();await process_frame
	return result


func _check(condition:bool,message:String)->void:
	if not condition:errors.append(message)


func _relocate_with_move_events(sim,entity_id:int,target:Vector2i)->bool:
	for _attempt in range(64):
		var current:Vector2i=sim.world.entities[entity_id].position
		if current==target:return true
		var delta:=target-current;var moved:=false
		for direction_value in [Vector2i(signi(delta.x),signi(delta.y)),
				Vector2i(signi(delta.x),0),Vector2i(0,signi(delta.y))]:
			var direction:=Vector2i(direction_value)
			if direction==Vector2i.ZERO:continue
			var destination:Vector2i=current+direction
			if maxi(absi(destination.x-target.x),absi(destination.y-target.y)) \
					>=maxi(absi(current.x-target.x),absi(current.y-target.y)):continue
			var assessment=sim.movement.assess_move(entity_id,destination)
			if not bool(assessment.accepted):continue
			var definition:Dictionary=TerrainRegistry.definition(str(assessment.terrain_id))
			if sim.movement.commit_preflighted_move(entity_id,destination,
					str(assessment.terrain_id),int(definition.move_time_cost))==null:return false
			moved=true;break
		if not moved:return false
	return false
