extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Old=preload("res://playtest/campaign_world_map.gd")
const Rules=preload("res://sim/room_transition_rules.gd")
const Sim=preload("res://sim/simulator.gd")
const State=preload("res://sim/round_combat_state.gd")
const Perception=preload("res://sim/enemy_perception_registry.gd")
const Field=preload("res://sim/field_turn_rules.gd")
var failures:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func place(w,id:int,p:Vector2i):
	var old:Vector2i=w.entities[id].position;w.entities[id].position=p;w.reindex_entity_occupancy(id,old,p)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var p=w.party_encounter;var hero:int=p.protagonist_id
	var state:Dictionary=p.nine_room_floor
	var before:Dictionary=s.sim.snapshot();var journal:Array=s.command_journal.duplicate(true)
	for i in range(10):s.observe_party_ui(8,true,8);s.room_status();s.visible_room_minimap();s.round_preview()
	check(before==s.sim.snapshot() and journal==s.command_journal,"observations preserve authority RNG journal")
	var unseen:=Vector2i(16,11)
	check(not Perception.has_line_of_sight(w,Vector2i(15,11),unseen),"adjacent rooms block sight")
	check(not s.sim.pathfinder.find_path(hero,unseen).get("found",false),"path cannot cross room")
	check(not s.sim.movement.assess_move(hero,unseen).accepted,"ordinary move cannot cross room")
	for cell in Field.visible_cells(w).keys():
		var parts:PackedStringArray=str(cell).split(":")
		check(Rules.current(w,Vector2i(int(parts[0]),int(parts[1]))),"FOV stays in current room")
	check(s.visible_room_minimap().rooms.size()==1,"only start room disclosed")
	# A first-floor stairs fixture checks the existing authoritative floor API.
	var stairs:int=-1
	for room in state.floors[0].rooms:
		if room.role=="STAIRS":stairs=room.room_id
	check(stairs>=0,"stairs exists")
	state.active_room_id=stairs
	var key:="1:%d"%stairs
	if key not in state.visited:state.visited.append(key)
	place(w,hero,s._map_layout.transition_portal_position);p.group_anchor=w.entities[hero].position;p.round_combat=State.fresh()
	var hp:int=w.entities[hero].health;var ids:Array=w.entities.keys();var items:Dictionary=w.item_state.inventory_rows[hero].to_dict()
	var floor_result:Dictionary=s.advance_campaign_floor()
	check(floor_result.accepted,"floor1 to2 "+str(floor_result.get("reason","")))
	if floor_result.accepted:
		check(state.floor_index==2 and state.active_room_id==4,"new floor start room")
		check(w.entities[hero].health==hp,"floor preserves HP")
		check(w.item_state.inventory_rows[hero].to_dict()==items,"floor preserves bag")
		check(w.party_encounter.enemy_ids.size()==24,"both floor rosters preserved")
		var error:String=w.world_state_error();check(error.is_empty(),"floor audit "+error)
		if error.is_empty():
			var snap:Dictionary=s.sim.snapshot();var clone=Sim.from_snapshot(snap);check(clone!=null,"floor restore")
			if clone!=null:check(clone.snapshot()==snap,"floor restore exact")
	# Explicit legacy generator remains attached to its old save/replay path.
	s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.reset_party(44,20260828,Session.DUO_SCENARIO_ID,Old.generate(44),false,"human",true,true,true,false,false,true)
	check(not s.room_enabled(),"legacy room gate off")
	var saved:String=s.save_session_json();var loaded=Session.new();var result:Dictionary=loaded.load_session_json(saved)
	check(result.accepted,"legacy save loads "+str(result.get("reason","")))
	if result.accepted:check(not loaded.room_enabled() and loaded.sim.snapshot()==s.sim.snapshot(),"legacy generator exact replay")
	print("NINE_ROOM_COMPATIBILITY ","PASS" if failures.is_empty() else failures);quit(0 if failures.is_empty() else 1)
