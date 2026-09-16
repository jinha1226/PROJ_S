extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Simulator=preload("res://sim/simulator.gd")
const Runtime=preload("res://sim/abilities/monster_ability_runtime.gd")
const Action=preload("res://sim/party_action_command.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
const Drops=preload("res://sim/species_drop_registry.gd")
const Generator=preload("res://playtest/procedural_campaign_floor.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	check(Drops.registry_error().is_empty(),"drop registry")
	for seed in range(1,31):
		var floor:Dictionary=Generator.generate(seed,7);var species:Array=[]
		for row in floor.enemy_roster:species.append(row.species_id)
		for kind in Drops.EARLY_PARTS:check(kind in species,"elemental source on floor %d %s"%[seed,kind])
	for kind in Drops.EARLY_PARTS:
		var hits:=0
		for death in range(1,101):
			var rolls:Array=Drops.rolls_for(15,death,kind,Drops.ELEMENTAL_RULESET_ID)
			check(rolls==Drops.rolls_for(15,death,kind,Drops.ELEMENTAL_RULESET_ID),"stable part roll")
			for row in rolls:
				if row.definition_id==Drops.EARLY_PARTS[kind]:hits+=1
		check(hits>60 and hits<100,"common but not guaranteed part "+kind)
	var s=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_procedural_run_with_species("human",15,13).accepted,"new elemental run")
	if not failures.is_empty():quit(1);return
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var actual_species:Array=[]
	for enemy in w.party_encounter.enemy_ids:actual_species.append(w.entities[enemy].species_id)
	for kind in Drops.EARLY_PARTS:check(kind in actual_species,"native species survives bootstrap "+kind)
	# Logged positioning fixture: every traversed tile records canonical movement.
	var best:Dictionary={};var target:=-1
	for enemy in w.party_encounter.enemy_ids:
		if w.entities[enemy].species_id not in Drops.EARLY_PARTS:continue
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var cell:Vector2i=w.entities[enemy].position+delta
			if not preload("res://sim/party_perception_registry.gd").field_visible(w,cell,w.entities[enemy].position):continue
			var route:Dictionary=s.sim.pathfinder.find_path(hero,cell)
			if route.get("found",false) and route.path.size()>1 and (best.is_empty() or route.path.size()<best.path.size()):best=route;target=enemy
	check(target>0,"reachable native monster")
	if target<0:quit(1);return
	for cell in best.path.slice(1):
		var terrain:String=w.tile_at(cell).terrain
		check(s.sim.movement.commit_preflighted_move(hero,cell,terrain,int(preload("res://sim/terrain_registry.gd").definition(terrain).move_time_cost))!=null,"logged move")
	w.party_encounter.group_anchor=w.entities[hero].position
	check(w.world_state_error().is_empty(),"fixture state valid: "+w.world_state_error())
	var baseline:Dictionary=s.sim.snapshot()
	for pair in [["WATER_SAC","PART_WATER_SAC","environment.water_applied"],["COLD_GLAND","PART_COLD_GLAND","environment.cold_applied"],["ARC_GLAND","PART_ARC_GLAND","environment.electric_arc"],["FIREBOLT","ESSENCE_FIRE_BOLT","environment.heat_applied"]]:
		s.sim=Simulator.from_snapshot(baseline);w=s.sim.world
		var inventory=w.inventory_of(hero);var items:Array=inventory.backpack.duplicate();var instance:String="TEST_"+pair[0]
		items.append(Item.new(instance,pair[1],1));w.item_state.inventory_rows[hero]=Inventory.new(items,inventory.equipped)
		var bound:Dictionary=s.bind_ability_item(hero,instance)
		check(bound.accepted,"eat part: "+str(bound.get("reason")))
		check(w.inventory_of(hero).item(instance)==null,"one part consumed")
		check(Runtime.passive(w,hero,pair[0]) and pair[0] in w.party_encounter.member(hero).active_skill_ids(),"passive and active simultaneously")
		check(s.ability_binding_rows(hero)[0].mode=="BOTH","both effects shown")
		check(not s.set_ability_mode(hero,pair[0],"PASSIVE").accepted,"no mode selection")
		var query_before:Dictionary=s.sim.snapshot()
		var suggestion=preload("res://sim/abilities/elemental_ability_ai.gd").suggest(w,hero)
		if pair[0] in ["WATER_SAC","ARC_GLAND"]:check(suggestion!=null and suggestion.skill_id==pair[0],"AI selects usable elemental skill")
		if pair[0]=="COLD_GLAND":check(suggestion==null,"AI avoids freezing dry floor")
		check(s.sim.snapshot()==query_before,"AI preview is read-only")
		var passive_baseline:Dictionary=s.sim.snapshot()
		var passive_start:int=w.events.size()
		var passive_event:String="ability.passive_triggered" if pair[0]=="FIREBOLT" else pair[2]
		for turn in range(8):
			if not Runtime.alive(w,target):break
			var melee:Dictionary=s.commit_field_action(Action.melee(hero,target))
			if not melee.accepted:break
			if w.events.slice(passive_start).any(func(e):return e.type==passive_event):break
		check(w.events.slice(passive_start).any(func(e):return e.type==passive_event),"original attack triggers environment passive "+pair[0])
		check(w.world_state_error().is_empty(),"passive world valid: "+w.world_state_error())
		s.sim=Simulator.from_snapshot(passive_baseline);w=s.sim.world
		var before:Dictionary=s.sim.snapshot();var energy:int=w.party_encounter.member(hero).energy
		check(not s.commit_field_action(Action.skill(hero,pair[0],hero)).accepted,"invalid target rejected")
		check(s.sim.snapshot()==before,"rejection consumes nothing")
		var start:int=w.events.size()
		var cast:Dictionary=s.commit_field_action(Action.skill(hero,pair[0],target))
		check(cast.accepted,"cast "+pair[0]+" "+str(cast.get("reason")))
		check(w.events.slice(start).any(func(e):return e.type==pair[2]),"real environment impulse "+pair[0])
		check(w.party_encounter.member(hero).energy<energy,"MP cost")
		check(w.world_state_error().is_empty(),"cast world valid: "+w.world_state_error())
		var restored=Simulator.from_snapshot(s.sim.snapshot())
		check(restored!=null,"restore elemental snapshot")
		if restored!=null:
			check(restored.snapshot()==s.sim.snapshot(),"exact elemental snapshot")
			var a=s.FieldTurns.step(s.sim,Action.hold(hero));var b=s.FieldTurns.step(restored,Action.hold(hero))
			check(a.accepted and b.accepted and s.sim.snapshot()==restored.snapshot(),"deterministic continuation")
	# Composition uses the same environmental impulses as the tested casts.
	s.sim=Simulator.from_snapshot(baseline);w=s.sim.world
	var step:int=w.step_index+1;w.begin_step(step)
	var position:Vector2i=w.entities[target].position;var source:int=w.events[-1].id
	check(Runtime.elemental_impulse(s.sim,"WATER",position,80,source),"combo water")
	check(Runtime.elemental_impulse(s.sim,"COLD",position,1800,source),"combo cold")
	check(s.sim.environment.process_tick(step),"phase change tick")
	check(w.tile_at(position).surface_id=="ICE","water and cold actually freeze")
	check(s.sim.environment.apply_heat(position,4000,source,step),"heat into ice")
	check(s.sim.environment.process_tick(step),"melting tick")
	check(w.tile_at(position).surface_id!="ICE","heat melts ice")
	s.sim=Simulator.from_snapshot(baseline);w=s.sim.world;w.begin_step(w.step_index+1)
	position=w.entities[target].position;source=w.events[-1].id
	var ai=preload("res://sim/abilities/elemental_ability_ai.gd")
	check(not ai.arc_reaches_ally(w,position,45),"dry separated caster avoids conduction")
	check(Runtime.elemental_impulse(s.sim,"WATER",position,80,source),"conductive target")
	check(Runtime.elemental_impulse(s.sim,"WATER",w.entities[hero].position,80,source),"conductive ally path")
	check(ai.arc_reaches_ally(w,position,45),"AI detects friendly fire on wet path")
	var hp:int=w.entities[hero].health
	check(Runtime.elemental_impulse(s.sim,"ELECTRIC",position,45,source),"conductive discharge")
	check(w.entities[hero].health<hp,"wet path conducts to caster too")
	print("ELEMENTAL PARTS: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
