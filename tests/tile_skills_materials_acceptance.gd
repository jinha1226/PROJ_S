extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Generator=preload("res://playtest/procedural_campaign_floor.gd")
const Action=preload("res://sim/party_action_command.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
const Defs=preload("res://sim/abilities/monster_ability_definitions.gd")
const Skills=preload("res://sim/abilities/party_active_skill_service.gd")
const Terrain=preload("res://sim/terrain_registry.gd")
var errors:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("FAIL ",label)
func grant(s,id:String):
	var hero:int=s.sim.world.party_control_actor_id()
	var inv=s.sim.world.inventory_of(hero)
	var items:Array=inv.backpack.duplicate();items.append(Item.new("TILE_TEST",id,1))
	s.sim.world.item_state.inventory_rows[hero]=Inventory.new(items,inv.equipped)
	check(s.bind_ability_item(hero,"TILE_TEST").accepted,"bind "+id)
func empty_cell(s,hero:int,skill:String)->Vector2i:
	for xy in s.skill_reach_cells(hero,skill).cells:
		var p:=Vector2i(xy[0],xy[1])
		if s.sim.world.occupying_entities_at(p).is_empty() and s.FieldTurns.assess(s.sim,Action.skill_at(hero,skill,p)).accepted:return p
	return Vector2i(-1,-1)
func run():
	for seed in range(1,51):
		var old:Dictionary=Generator.generate(seed,7)
		var map:Dictionary=Generator.generate(seed,8)
		check(map==Generator.generate(seed,8),"material seed reproducible")
		check(map.enemy_roster==old.enemy_roster and map.entry_position==old.entry_position and map.exit_position==old.exit_position,"materials preserve geometry/spawns")
		var reachable:Dictionary=Generator.distances(map.terrain,map.entry_position)
		check(reachable.size()==Generator.distances(old.terrain,old.entry_position).size(),"materials preserve connectivity")
		for kind in map.material_positions:
			check(not map.material_positions[kind].is_empty(),"material guaranteed "+kind)
			for p in map.material_positions[kind]:check(map.terrain[p.y*64+p.x]==kind,"material is simulation terrain")
		check(old.material_positions.wood_floor.is_empty(),"legacy generator unchanged")
	var s=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_procedural_run_with_species("human",15,13).accepted,"new material run")
	var hero:int=s.sim.world.party_control_actor_id()
	var baseline:Dictionary=s.sim.snapshot()
	for pair in [["FIREBOLT","ESSENCE_FIRE_BOLT","environment.heat_applied"],["WATER_SAC","PART_WATER_SAC","environment.water_applied"],["COLD_GLAND","PART_COLD_GLAND","environment.cold_applied"],["ARC_GLAND","PART_ARC_GLAND","environment.electric_arc"],["FROST_SILK","ESSENCE_FROST_SILK","environment.cold_applied"]]:
		s.sim=Session.SimulatorScript.from_snapshot(baseline)
		grant(s,pair[1])
		var skill:String=pair[0];var cell:=empty_cell(s,hero,skill)
		check(cell!=Vector2i(-1,-1),"empty target "+skill)
		if cell==Vector2i(-1,-1):continue
		var before:Dictionary=s.sim.snapshot()
		check(not s.commit_field_action(Action.skill_at(hero,skill,Vector2i(-1,-1))).accepted,"invalid tile rejected")
		check(s.sim.snapshot()==before,"rejection preserves MP/time")
		var first:int=s.sim.world.events.size()
		var cast:Dictionary=s.commit_field_action(Action.skill_at(hero,skill,cell))
		check(cast.accepted,"ground cast "+skill+str(cast.get("reason")))
		check(s.sim.world.events.slice(first).any(func(e):return e.type==pair[2] and e.position==cell),"ground impulse "+skill)
		if skill=="FROST_SILK":check(s.sim.world.events.slice(first).any(func(e):return e.type=="ability.status" and e.data.status=="FROST_ZONE" and e.position==cell),"fixed ground frost zone")
		check(s.sim.world.world_state_error().is_empty(),"ground audit "+skill+": "+s.sim.world.world_state_error())
		var restored=Session.SimulatorScript.from_snapshot(s.sim.snapshot())
		check(restored!=null,"ground snapshot restores "+skill)
		if restored!=null:
			check(s.FieldTurns.step(s.sim,Action.hold(hero)).accepted and s.FieldTurns.step(restored,Action.hold(hero)).accepted,"ground continuation")
			check(s.sim.snapshot()==restored.snapshot(),"ground deterministic continuation "+skill)
	# Self skills must wait for tile input, and only accept their owner's cell.
	s.sim=Session.SimulatorScript.from_snapshot(baseline)
	grant(s,"ESSENCE_HIDE_PLATING")
	var origin:Vector2i=s.sim.world.entities[hero].position
	var reach:Dictionary=s.skill_reach_cells(hero,"HIDE_PLATING")
	check(reach.target=="TILE" and reach.cells==[[origin.x,origin.y]],"self skill highlights own tile")
	var ui=preload("res://playtest/party_encounter_sandbox.gd").new()
	ui.initialize_for_headless_test(s,true);root.add_child(ui);ui.set_process(false)
	ui._on_manual_skill_selected(hero,"HIDE_PLATING","피부 경화")
	check(ui._battle_target_mode=="ACTIVE_SKILL","self skill waits for tile input")
	check(not s.FieldTurns.assess(s.sim,Action.skill_at(hero,"HIDE_PLATING",origin+Vector2i.RIGHT)).accepted,"self skill rejects other cell")
	ui._on_cell(origin)
	check(ui._battle_target_mode.is_empty(),"own tile casts self skill")
	check(preload("res://sim/abilities/monster_ability_runtime.gd").status(s.sim.world,hero,"HIDE")!=null,"self status applied")
	ui.queue_free()
	# Compare every monster skill's tile and actor assessment on a valid, adjacent enemy.
	s.sim=Session.SimulatorScript.from_snapshot(baseline)
	var w=s.sim.world;var best:Dictionary={};var target:=-1
	for enemy in w.party_encounter.enemy_ids:
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var p:Vector2i=w.entities[enemy].position+delta
			if not preload("res://sim/party_perception_registry.gd").field_visible(w,p,w.entities[enemy].position):continue
			var route:Dictionary=s.sim.pathfinder.find_path(hero,p)
			if route.get("found",false) and route.path.size()>1 and (best.is_empty() or route.path.size()<best.path.size()):best=route;target=enemy
	check(target>0,"enemy fixture reachable")
	if target>0:
		for cell in best.path.slice(1):
			var terrain:String=w.tile_at(cell).terrain
			check(s.sim.movement.commit_preflighted_move(hero,cell,terrain,int(Terrain.definition(terrain).move_time_cost))!=null,"logged fixture move")
		w.party_encounter.group_anchor=w.entities[hero].position
		var combat:Dictionary=s.sim.snapshot()
		var ids:Array=Defs.SKILLS.keys();ids.append("FIREBOLT")
		for id in ids:
			s.sim=Session.SimulatorScript.from_snapshot(combat);w=s.sim.world
			var item_id:String="PART_"+id if id in ["WATER_SAC","COLD_GLAND","ARC_GLAND"] else "ESSENCE_FIRE_BOLT" if id=="FIREBOLT" else "ESSENCE_"+id
			grant(s,item_id)
			var self_skill:bool=Defs.definition(id).get("target")=="SELF"
			var actor_target:int=hero if self_skill else target
			var cell:Vector2i=w.entities[actor_target].position
			check(Action.wire_error(Action.skill_at(hero,id,cell).to_dict()).is_empty(),"tile wire "+id)
			var old_assessment:Dictionary=Skills.assess(w,hero,id,actor_target)
			var new_assessment:Dictionary=s.FieldTurns.assess(s.sim,Action.skill_at(hero,id,cell))
			check(old_assessment.accepted==new_assessment.accepted,"tile assessment matches actor "+id)
			if not new_assessment.accepted:continue # Full-health regeneration remains invalid.
			check(s.commit_field_action(Action.skill_at(hero,id,cell)).accepted,"occupied tile commit "+id)
			check(w.world_state_error().is_empty(),"occupied tile audit "+id+": "+w.world_state_error())
	print("TILE SKILLS MATERIALS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
