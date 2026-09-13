extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Simulator=preload("res://sim/simulator.gd")
const Effects=preload("res://sim/consumable_effects.gd")
const Mystery=preload("res://sim/mystery_consumables.gd")
const Utility=preload("res://playtest/consumable_utility_service.gd")
const Runtime=preload("res://sim/abilities/monster_ability_runtime.gd")
const Action=preload("res://sim/party_action_command.gd")
const Item=preload("res://sim/item_instance.gd")
const Inventory=preload("res://sim/inventory_state.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func give(s,id:String):
	var w=s.sim.world;var actor:int=w.party_control_actor_id();var inv=w.inventory_of(actor)
	var rows:Array=inv.backpack.duplicate();rows.append(Item.new("TACTIC_"+id,id,2))
	w.item_state.inventory_rows[actor]=Inventory.new(rows,inv.equipped)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var actor:int=s.sim.world.party_control_actor_id()
	for n in range(80):
		var w=s.sim.world
		if w.entities[actor].health<w.entities[actor].max_health and not Utility.enemies(w,actor,2).is_empty():break
		var goals:Array[Vector2i]=[]
		for enemy in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(enemy):continue
			for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(w.entities[enemy].position+d)
		var path:Dictionary=s.sim.pathfinder.find_path_to_any(actor,goals)
		var action=Action.move_to(actor,path.path[1]) if path.get("found",false) and path.path.size()>1 else Action.hold(actor)
		check(s.commit_field_action(action).accepted,"canonical approach")
	check(not Utility.enemies(s.sim.world,actor,2).is_empty(),"nearby enemy fixture")
	var baseline:Dictionary=s.sim.snapshot()
	for effect in ["REGEN","ARMOR","WEAK","SLOW","POISON","PUSH","FEAR","SEAL","NOISE","CONFUSION","BLINK","TELEPORT","MAP"]:
		s.sim=Simulator.from_snapshot(baseline);s.command_journal.clear()
		var w=s.sim.world;var start:int=w.events.size()
		var id:String=("POTION_MYSTERY_" if effect in ["REGEN","ARMOR","WEAK","SLOW","POISON"] else "SCROLL_MYSTERY_")+effect
		give(s,id)
		var origin:Vector2i=w.entities[actor].position
		var result:Dictionary=s.use_inventory_item("TACTIC_"+id)
		check(result.get("accepted",false),"tactical use "+effect+" "+str(result.get("reason","")))
		if not result.get("accepted",false):continue
		if effect=="REGEN":check(w.events.slice(start).any(func(e):return e.type=="consumable.pulse" and e.data.effect=="REGEN"),"regeneration ticks")
		if effect=="ARMOR":check(Effects.armor(w,actor)==5,"armor modifier")
		if effect=="WEAK":check(Effects.accuracy(w,actor)==-200 and Effects.armor(w,actor)==-3,"weakness modifiers")
		if effect=="SLOW":check(preload("res://sim/field_action_timing.gd").duration(w,actor,"MELEE",100)>100,"slow timing")
		if effect=="POISON":
			check(w.events.slice(start).any(func(e):return e.type=="consumable.pulse" and e.data.effect=="POISON"),"poison ticks")
			var choices:=Utility.options(s,"TACTIC_"+id).filter(func(row):return int(row.selection.get("target_id",actor))!=actor)
			check(not choices.is_empty(),"known poison throw targets")
			if not choices.is_empty():
				var throw:Dictionary=s.use_inventory_item("TACTIC_"+id,true,choices[0].selection)
				check(throw.accepted,"throw poison "+str(throw.get("reason","")))
				check(Effects.status(w,int(choices[0].selection.target_id),"POISON")!=null,"enemy poisoned")
			give(s,"POTION_MYSTERY_CLEANSE")
			check(s.use_inventory_item("TACTIC_POTION_MYSTERY_CLEANSE").accepted,"cleanse")
			check(Effects.status(w,actor,"POISON")==null,"cleanse clears poison")
		if effect=="PUSH":check(w.events.slice(start).any(func(e):return e.type=="action.move" and e.cause_id>0 and w.event_by_id(e.cause_id).type=="consumable.activated"),"actual push displacement")
		if effect=="FEAR":
			var statuses:Array=w.events.slice(start).filter(func(e):return e.type=="consumable.status" and e.data.effect=="FEAR")
			check(not statuses.is_empty(),"fear affects nearby enemies")
			if not statuses.is_empty():
				var forecast:Dictionary=s.sim.party_coordinator.forecast_enemy_action(statuses[0].target_id)
				check(forecast.reason=="fear_retreat","fear changes enemy decision")
		if effect=="SEAL":
			var statuses:Array=w.events.slice(start).filter(func(e):return e.type=="consumable.status" and e.data.effect=="SEAL")
			check(not statuses.is_empty(),"seal targets enemy")
			if not statuses.is_empty():check(Effects.skill_blocked(w,statuses[0].target_id),"seal blocks skills")
		if effect=="CONFUSION":check(Effects.skill_blocked(w,actor) and Effects.accuracy(w,actor)==-250,"confusion penalty")
		if effect in ["BLINK","TELEPORT"]:check(w.entities[actor].position!=origin,"actual teleport "+effect)
		if effect=="MAP":
			var memory:Dictionary=s._explored_cells_from_hero_history(actor,w.entities[actor].position)
			for y in range(origin.y-10,origin.y+11):
				for x in range(origin.x-10,origin.x+11):
					if w.in_bounds(Vector2i(x,y)):check(memory.has(Vector2i(x,y)),"map reveals radius memory")
		var error:String=w.world_state_error();check(error.is_empty(),"tactical audit "+effect+" "+error)
		var snap=s.sim.snapshot();check(snap!=null and Simulator.from_snapshot(snap)!=null,"tactical snapshot "+effect)
	print("CONSUMABLE TACTICS ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
