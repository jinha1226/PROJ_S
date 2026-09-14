extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Old=preload("res://playtest/campaign_world_map.gd")
const Action=preload("res://sim/party_action_command.gd")
const Rules=preload("res://sim/room_transition_rules.gd")
const Perf=preload("res://sim/perf_probe.gd")
func _init():call_deferred("run")
func percentile(values:Array,p:float)->float:
	if values.is_empty():return -1.0
	var sorted:Array=values.duplicate();sorted.sort();return float(sorted[mini(sorted.size()-1,ceili(sorted.size()*p)-1)])/1000.0
func sample(legacy:bool)->Dictionary:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	if legacy:s.reset_party(44,20260828,Session.DUO_SCENARIO_ID,Old.generate(44),false,"human",true,true,true,false,false,true)
	var w=s.sim.world;var hero:int=w.party_encounter.protagonist_id;var origin:Vector2i=w.entities[hero].position;var goal:=Vector2i(-1,-1)
	for d in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
		var p:Vector2i=origin+d
		if not s.sim.movement.assess_move(hero,p).accepted or not Rules.portal_at(w,p).is_empty():continue
		if w.party_encounter.enemy_ids.any(func(id):return Rules.actor_active(w,id) and Rules.distance(w.entities[id].position,p)<=7):continue
		goal=p;break
	if goal==Vector2i(-1,-1):return {"error":"no safe comparison pair"}
	var dormant:Dictionary={}
	for id in w.party_encounter.enemy_ids:dormant[id]=w.entities[id].position
	var input:Array=[];var frame:Array=[];var mem:Array=[];var transitions:Array=[]
	var builds:int=Rules.Generator.generation_count
	Perf.enabled=true;Perf.reset()
	for i in range(100):
		var begun:=Time.get_ticks_usec();var result:Dictionary=s.commit_field_action(Action.move_to(hero,goal if i%2==0 else origin));input.append(Time.get_ticks_usec()-begun)
		if not result.accepted or s.round_active():return {"error":"comparison entered combat","step":i,"reason":result.get("reason","")}
		begun=Time.get_ticks_usec();s.observe_party_ui(8 if not legacy else 15,true,8 if not legacy else 15);frame.append(Time.get_ticks_usec()-begun)
		if i%10==0:mem.append(OS.get_static_memory_usage())
	var unchanged:=true
	for id in dormant:
		if dormant[id]!=w.entities[id].position:unchanged=false
	var report:Dictionary={"legacy":legacy,"generation_during100moves":Rules.Generator.generation_count-builds,"world":[w.width,w.height],"steps":100,"input_p50_ms":percentile(input,0.5),"input_p95_ms":percentile(input,0.95),"observation_p50_ms":percentile(frame,0.5),"observation_p95_ms":percentile(frame,0.95),"memory_every10":mem,"inactive_enemy_positions_unchanged":unchanged,"active_enemy_count":s.sim.party_coordinator._stream_enemy_ids().size(),"enemy_count":w.party_encounter.enemy_ids.size(),"probe_counts":Perf.counts.duplicate(),"probe_totals_usec":Perf.totals.duplicate(),"audit":w.world_state_error()}
	Perf.enabled=false;return report
func run():
	var report:Dictionary={"godot":Engine.get_version_info().string,"os":OS.get_name(),"cpu":OS.get_processor_name(),"processors":OS.get_processor_count(),"baseline":sample(true),"nine_room":sample(false),"note":"Headless input/observation CPU timing; browser frame timing and transition visuals measured separately. Public save snapshots are not made in this workload; cached tile rollback is retained."}
	var file=FileAccess.open("res://docs/plans/nine-room-dungeon-performance.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("NINE_ROOM_PERFORMANCE ",JSON.stringify(report))
	quit(1 if report.baseline.has("error") or report.nine_room.has("error") else 0)
