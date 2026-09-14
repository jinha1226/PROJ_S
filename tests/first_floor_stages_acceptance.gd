extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Stages=preload("res://sim/first_floor_stages.gd")
const Rooms=preload("res://sim/room_transition_rules.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
const Population=preload("res://sim/town_population_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array=[]
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func walk(s,target:Vector2i)->bool:
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	for step in range(40):
		if w.entities[hero].position==target:return true
		var route:Dictionary=s.sim.pathfinder.find_path(hero,target)
		if not route.get("found",false) or route.path.size()<2:return false
		if not s.commit_field_action(Action.move_to(hero,route.path[1])).accepted:return false
	return false
func run():
	check(Stages.CONTENT.rooms.size()==9,"nine unique authored rooms")
	var names:Dictionary={}
	for spec in Stages.CONTENT.rooms:
		names[spec.id]=true
		check(spec.rows.size()==8 and spec.rows.all(func(row):return row.length()==8),"8x8 "+spec.id)
		for cell in spec.enemy_cells:check(spec.rows[cell[1]][cell[0]]!="#","enemy is on walkable tile "+spec.id)
		for drop in spec.loot:
			check(spec.rows[drop.cell[1]][drop.cell[0]]!="#","loot on floor")
			check(preload("res://sim/item_registry.gd").has(drop.item),"real item definition")
	check(names.size()==9,"unique room identity")
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.sim!=null,"bootstrap");if s.sim==null:quit(1);return
	check(s.start_new_run_with_species("human",true,true).accepted,"species selection")
	check(s.town_life_command({"action":"START"}).accepted,"town start")
	check(s.depart_town().accepted,"departure")
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(w.party_encounter.party_member_ids.size()==2,"only hero and one NPC exist in roster")
	var npcs:Array=Population.locations(w)
	check(npcs.size()==1,"one dungeon NPC")
	if npcs.size()!=1:quit(1);return
	var npc:int=int(npcs[0].entity_id)
	check(w.entities[npc].position==Stages.npc_position(),"NPC waits in authored event room")
	check(not Rooms.actor_active(w,npc),"NPC hidden outside event room")
	check(walk(s,Vector2i(14,11)),"walk to eastern doorway")
	check(s.request_room_exit(hero,"F1_R4_R5",w.party_encounter.nine_room_floor.revision).accepted,"enter event room")
	check(walk(s,Stages.npc_position()+Vector2i.LEFT),"walk beside NPC")
	for i in range(10):check(s.commit_field_action(Action.hold(hero)).accepted,"wait in event room")
	check(w.entities[npc].position==Stages.npc_position(),"event NPC never wanders away")
	check(Visitors.assess(s,npc).can_aid,"aid offer available")
	check(Visitors.interact(s,{"action":"AID","entity_id":str(npc)}).accepted,"share one ration")
	check(Visitors.interact(s,{"action":"ACCEPT","entity_id":str(npc)}).accepted,"same NPC joins")
	check(w.party_encounter.active_party_member_ids.size()==2,"two member party after event")
	check(Population.locations(w).is_empty(),"no duplicate world NPC after recruitment")
	check(not Visitors.interact(s,{"action":"ACCEPT","entity_id":str(npc)}).accepted,"cannot recruit twice")
	var saved:String=s.save_session_json();var clone=Session.new();var loaded:Dictionary=clone.load_session_json(saved)
	check(loaded.accepted,"recruitment save replay "+str(loaded.get("reason","")))
	if loaded.accepted:check(s.sim.snapshot()==clone.sim.snapshot(),"all rooms loot and event state preserved")
	check(w.world_state_error().is_empty(),"world audit")
	print("FIRST_FLOOR_STAGES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
