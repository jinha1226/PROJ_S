extends SceneTree
## Headless difficulty probe. Diagnostic, not a pass/fail test.
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const Stage=preload("res://sim/stage_counterplay.gd")
const Rules=preload("res://sim/round_combat_rules.gd")
const Rooms=preload("res://sim/room_transition_rules.gd")
const MAX_ROUNDS:=40

func arg(name:String,default:String)->String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s="%name):return a.substr(name.length()+3)
	return default

func _init():call_deferred("run")

func route(s,target:int)->bool:
	# Travel through discovered rooms only; breadth-first over the 3x3 graph.
	var w=s.sim.world;var s_floor:Dictionary=w.party_encounter.nine_room_floor
	var edges:Array=Rooms.current_floor(w).portals.map(func(p):return [int(p.a),int(p.b)])
	var prev:Dictionary={int(s_floor.active_room_id):-1};var todo:Array=[int(s_floor.active_room_id)]
	for a in todo:
		for e in edges:
			var b:int=e[1] if e[0]==a else (e[0] if e[1]==a else -1)
			if b>=0 and not prev.has(b):prev[b]=a;todo.append(b)
	if not prev.has(target):return false
	var path:Array=[];var cur:int=target
	while cur!=-1:path.push_front(cur);cur=prev[cur]
	for id in path.slice(1):
		if not s.request_room_travel(id,int(w.party_encounter.nine_room_floor.revision)).accepted:return false
		if Rules.active(w):return id==target
	return true

func nearest_enemy(w,id:int)->int:
	var best:=-1;var best_d:=999
	for e in Stage.enemies(w):
		var d:int=Rooms.distance(w.entities[id].position,w.entities[e].position)
		if d<best_d:best=e;best_d=d
	return best

func act(s,policy:String)->void:
	var w=s.sim.world;var id:int=Rules.current_actor(w)
	if id>=0 and id in w.party_encounter.active_party_member_ids:
		var target:int=nearest_enemy(w,id)
		var acted:=false
		if target>=0 and policy=="charge":
			# Deviation from brief: `round_move_options`/`Action.attack` don't exist.
			# Legal move cells come from Rules.reachable_cells(w) (current actor's
			# PLANNING-phase move set); the melee constructor is Action.melee.
			var best:Vector2i=w.entities[id].position;var best_d:int=Rooms.distance(best,w.entities[target].position)
			for cell in Rules.reachable_cells(w):
				var d:int=Rooms.distance(cell,w.entities[target].position)
				if d<best_d:best=cell;best_d=d
			if best!=w.entities[id].position:s.stage_round_action(Action.move_to(id,best))
			if Rooms.distance(w.entities[id].position,w.entities[target].position)<=1:
				s.stage_round_action(Action.melee(id,target));acted=true
		if not acted:s.stage_round_action(Action.hold(id))
	# Deviation from brief: `stage_round_action` only edits the plan; the
	# acceptance tests (srpg_party_turns_acceptance.gd) always follow it with
	# confirm_round/resume_round to actually execute the turn and move the
	# cursor to the next actor (ally or AI-controlled).
	var r:Dictionary=w.party_encounter.round_combat
	if r.phase=="INTERRUPTED":s.resume_round(r.round_id,r.plan_revision)
	else:s.confirm_round(r.round_id,r.plan_revision)

func run():
	var room:int=int(arg("room","7"));var seeds:int=int(arg("seeds","10"));var policy:String=arg("policy","charge")
	print("seed,room,outcome,rounds,hp_lost,waves")
	for seed in range(1,seeds+1):
		var s=Session.new(seed,20260828,Session.DUO_SCENARIO_ID,"human",true)
		s.start_new_run_with_species("human",true,true);s.town_life_command({"action":"START"});s.depart_town()
		var w=s.sim.world
		if not route(s,room):print("%d,%d,unreachable,0,0,0"%[seed,room]);continue
		var hp0:int=0
		for id in w.party_encounter.active_party_member_ids:hp0+=w.entities[id].health
		# Deploy in place: confirm the deployment round without moving.
		var r:Dictionary=w.party_encounter.round_combat
		if r.phase=="DEPLOYMENT":s.confirm_round(r.round_id,r.plan_revision)
		var rounds:=0;var ticks:=0
		# ticks caps individual actions (not full round cycles) so a stuck
		# policy loop still terminates the probe with a "timeout" outcome.
		while Rules.active(w) and not Stage.cleared(w) and rounds<MAX_ROUNDS and ticks<MAX_ROUNDS*40 and w.party_encounter.safe_phase!="PARTY_DEFEATED":
			var before:int=int(Stage.current(w).get("turn",0));act(s,policy);ticks+=1
			if int(Stage.current(w).get("turn",0))>before:rounds+=1
		var hp1:int=0
		for id in w.party_encounter.active_party_member_ids:hp1+=w.entities[id].health
		var outcome:String
		if w.party_encounter.safe_phase=="PARTY_DEFEATED":outcome="defeat"
		elif Stage.cleared(w):outcome="cleared"
		else:outcome="timeout"
		print("%d,%d,%s,%d,%d,%d"%[seed,room,outcome,rounds,hp0-hp1,int(Stage.current(w).get("waves",0))])
	quit(0)
