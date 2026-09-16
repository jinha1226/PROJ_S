extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const Drops=preload("res://sim/species_drop_registry.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_procedural_run_with_species("human",15,13).accepted,"new run")
	var hero:int=s.sim.world.party_control_actor_id();var acquired:=""
	# No grants, teleportation, health edits or debug kills: ordinary gameplay journal.
	for turn in range(90):
		var w=s.sim.world
		for row in s.ground_items_at_protagonist():
			if row.definition_id in Drops.EARLY_PARTS.values():
				if s.pickup_ground_item(row.instance_id).accepted:acquired=row.instance_id
		if not acquired.is_empty():break
		var action=null
		for id in w.party_encounter.enemy_ids:
			if s.FieldTurns.assess(s.sim,Action.melee(hero,id)).accepted:action=Action.melee(hero,id);break
		if action==null:
			var best:Dictionary={}
			for row in w.item_state.ground_items.rows:
				if row.item.definition_id not in Drops.EARLY_PARTS.values():continue
				var route:Dictionary=s.sim.pathfinder.find_path(hero,row.position)
				if route.get("found",false) and route.path.size()>1 and (best.is_empty() or route.path.size()<best.path.size()):best=route
			if best.is_empty():
				for id in w.party_encounter.enemy_ids:
					if not w.is_autonomous_target(id) or w.entities[id].species_id not in Drops.EARLY_PARTS:continue
					for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
						var route:Dictionary=s.sim.pathfinder.find_path(hero,w.entities[id].position+delta)
						if route.get("found",false) and route.path.size()>1 and (best.is_empty() or route.path.size()<best.path.size()):best=route
			if not best.is_empty():action=Action.move_to(hero,best.path[1])
		if action==null:break
		var result:Dictionary=s.commit_field_action(action)
		if not result.accepted:print("STOP ",turn," ",result.reason);break
	check(not acquired.is_empty(),"naturally killed monster drops collectible part")
	if not acquired.is_empty():
		var used:Dictionary=s.use_party_item(acquired,hero)
		check(used.accepted,"eat real dropped part: "+str(used.get("reason")))
		check(s.sim.world.item_owner(acquired).kind=="NONE","part consumed")
		check(s.sim.world.party_encounter.member(hero).bound_ability_ids.size()==1,"one binding from part")
	var before:Dictionary=s.sim.snapshot();var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"full death/drop/eat gameplay replay: "+str(loaded.get("reason")))
	if loaded.accepted:check(restored.sim.snapshot()==before,"exact full gameplay replay")
	print("ELEMENTAL DROP REPLAY: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
