extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/darkness_stress_rules.gd")
const Vision=preload("res://sim/vision_rules.gd")
const Fixture=preload("res://tests/test_darkness_stage5.gd")
const Simulator=preload("res://sim/simulator.gd")
const Command=preload("res://sim/sim_command.gd")
const Supplies=preload("res://playtest/expedition_supply_presenter.gd")
const ItemOps=preload("res://sim/world_item_operations.gd")
const Torch=preload("res://sim/torch_rules.gd")
const Index=preload("res://sim/darkness_event_index.gd")
const Action=preload("res://sim/party_action_command.gd")
var errors:Array[String]=[]
class SupplySession:
	extends RefCounted
	var sim
	func town_market_stock()->Array:return [{"definition_id":"TORCH"}]
func _init():call_deferred("run")
func check(value:bool,label:String):
	if not value:errors.append(label);printerr("FAIL ",label)
func run():
	var full:=Rules.project(0,0,500,[{"elapsed":2500,"illumination":120}])
	var split:Dictionary={"exposure":0,"remainder":0,"stress":0}
	var total:=0
	for i in range(250):
		split=Rules.project(split.exposure,split.remainder,500,[{"elapsed":10,"illumination":120}]);total+=int(split.stress)
	check(total==full.stress and split.exposure==full.exposure and split.remainder==full.remainder,"partition invariant beyond cap")
	check(Rules.project(2000,0,500,[{"elapsed":100,"illumination":120}]).stress==6,"stress continues at exposure cap")
	check(Rules.project(2000,0,1000,[{"elapsed":100,"illumination":120}]).stress==0,"darkness immunity")
	check(Rules.project(400,0,500,[{"elapsed":100,"illumination":900}]).exposure==300,"light decays exposure gradually")
	check(Rules.project(0,0,500,[{"elapsed":300,"illumination":120}]).stress==0,"grace boundary")
	var fixture=Fixture.new();var s=fixture._dark_session(752);var w=s.sim.world;var hero:int=w.party_control_actor_id()
	check(s.enable_darkness_rules().accepted,"activate explicit version boundary")
	for i in range(4):check(s._advance_item_action_time().accepted,"v2 dark wait")
	check(Rules.state(w,hero).exposure==400,"v2 exposure after grace")
	var stress_before:int=w.party_encounter.member(hero).stress
	check(s._advance_item_action_time().accepted,"additional dark wait")
	check(w.party_encounter.member(hero).stress>stress_before,"safe idle recovery cannot cancel darkness stress")
	var latest=Index.latest(w,hero)
	var tampered:Dictionary=latest.data.duplicate(true);tampered.stress_delta+=1
	check(not Rules.event_error(tampered,{"exposure_after":tampered.exposure_before,"remainder_after":tampered.remainder_before},latest.magnitude).is_empty(),"tampered stress rejected")
	check(w.world_state_error().is_empty(),"v2 full history audit: "+w.world_state_error())
	var snap=w.snapshot();var restored=Simulator.from_snapshot(snap)
	check(restored!=null,"v2 snapshot loads")
	if restored!=null:
		restored.world.vision_scenario_id=w.vision_scenario_id
		check(Rules.state(restored.world,hero)==Rules.state(w,hero),"derived exposure index rebuild")
		check(s.sim.step(Command.wait_for(100,hero)).accepted,"original next wait")
		check(restored.step(Command.wait_for(100,hero)).accepted,"restored next wait")
		check(restored.snapshot()==s.sim.snapshot(),"v2 deterministic snapshot continuation")
	var torch:String=fixture._give_torch(s)
	check(ItemOps.commit_equip(w,hero,torch,"OFF_HAND",w.entities[hero].position,0).accepted,"torch equips")
	var proxy=SupplySession.new();proxy.sim=s.sim
	check(Supplies.rows(proxy)[0].carried==1,"equipped torch counted once")
	# Unit sample at a real lit torch: expiry must split bright and dark time.
	check(ItemOps.commit_torch_event(w,hero,torch,w.entities[hero].position,Torch.EVENT_IGNITED,Torch.FUEL_DURATION,0).accepted,"torch ignites")
	var sample:=Rules.begin_sample(w);var start:int=w.world_time
	w.world_time=start+1100;Rules.checkpoint(w,sample)
	var segments:Array=sample.segments[hero]
	check(segments.size()==2 and segments[0].elapsed==1000 and segments[1].elapsed==100,"torch expiry segments")
	check(segments[0].illumination>=700 and segments[1].illumination<180,"expiry light bands")
	# Checkpoint integrates the old location first, then samples the new light.
	var moving:Dictionary={"time":w.world_time-75,"current":{hero:{"base":900,"lights":[]}},"segments":{}}
	Rules.checkpoint(w,moving)
	w.world_time+=25;Rules.checkpoint(w,moving)
	check(moving.segments[hero]==[{"elapsed":75,"illumination":900},{"elapsed":25,"illumination":120}],"intermediate light change preserves elapsed bands")
	# State-query index is stable on idle and invalidates after history rollback.
	var cache:Dictionary=Index.sync(w);var scanned:int=cache.count
	for i in range(100):Rules.state(w,hero)
	check(Index.sync(w).count==scanned,"idle query adds no events")
	var temporary=w.emit_event(Index.EXPOSURE,hero,-1,w.entities[hero].position,0,-1,{"exposure_after":99})
	check(Index.latest(w,hero)==temporary,"index sees appended event")
	w.events.pop_back()
	check(Index.latest(w,hero)!=temporary,"index rebuilds after history truncation")
	var cycle=w.party_encounter.expedition_cycle
	w.vision_scenario_id=""
	cycle.phase="DUNGEON"
	for floor_index in [1,2,3]:
		cycle.floor_index=floor_index
		var light:Dictionary=Vision.lighting_for_world(w)
		check(int(light.ambient_level)=={1:900,2:400,3:120}[floor_index],"production floor light %d"%floor_index)
	cycle.phase="TOWN"
	# Production town is bright, independently of its previous dungeon floor.
	check(Vision.lighting_for_world(w).ambient_level==900,"town stays bright")
	check_replay_and_combat()
	print("DARKNESS V2: ",errors)
	quit(0 if errors.is_empty() else 1)

func check_replay_and_combat():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var restored=Session.new()
	check(restored.load_session_json(s.save_session_json()).accepted,"legacy session loads without migration")
	check(restored.sim.snapshot()==s.sim.snapshot() and not Rules.enabled(restored.sim.world),"legacy replay stays exact")
	check(s.enable_darkness_rules().accepted,"record migration after legacy history")
	var hero:int=s.sim.world.party_control_actor_id()
	for i in range(120):
		var w=s.sim.world
		if w.entities[hero].health<w.entities[hero].max_health:break
		var goals:Array[Vector2i]=[]
		for id in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(id):continue
			for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(w.entities[id].position+d)
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		var action=Action.move_to(hero,route.path[1]) if route.get("found",false) and route.path.size()>1 else Action.hold(hero)
		if not s.commit_field_action(action).accepted:check(false,"combat approach accepted");break
	check(s.sim.world.entities[hero].health<s.sim.world.entities[hero].max_health,"real combat damage exercised")
	var seen:Dictionary={};var count:=0
	for event in s.sim.world.events:
		if event.type!="party.morale_changed":continue
		for id in event.data.source_event_ids:
			var key:String=str(event.actor_id)+":"+str(id)
			check(not seen.has(key),"morale source applied once per member")
			seen[key]=true;count+=1
	check(count>0,"combat morale sources exercised")
	check(s.sim.world.world_state_error().is_empty(),"combat world audit")
	var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"v2 session journal replay: "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"v2 session replay exact")
