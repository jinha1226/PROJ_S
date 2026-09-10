extends SceneTree

## Regression: a solo expedition started from town life carries the whole
## resident roster in party_member_ids. CONTACT must still enter combat through
## the one-member product path instead of freezing in ENCOUNTER_PREVIEW.

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const SimCommand=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func _check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)

func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	_check(bool(session.town_life_command({"action":"START"}).get("accepted",false)),"town life starts")
	_check(bool(session.depart_town().get("accepted",false)),"solo expedition departs")
	var world=session.sim.world;var state=world.party_encounter;var hero:int=int(state.protagonist_id)
	_check(state.party_member_ids.size()>1 and state.active_party_member_ids.size()==3 and hero in state.active_party_member_ids,
		"the first expedition departs with two companions from the inn (active %s)"%str(state.active_party_member_ids))
	var ui=Sandbox.new();ui.size=Vector2(390,800);ui.initialize_for_headless_test(session,true)
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(390,800);root.add_child(ui);ui.set_process(false)
	for i in range(3):await process_frame
	var reached_contact:=false
	for round in range(300):
		var phase:=str(session.party_status().get("safe_phase",""))
		if phase!="GROUPED":reached_contact=true;break
		var goal:=Vector2i(-1,-1);var best_len:=9999
		for id in state.enemy_ids:
			if not world.is_unresolved_enemy(int(id)):continue
			var ep:Vector2i=world.entities[int(id)].position
			for dd in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var q:Dictionary=session.sim.pathfinder.find_path(hero,ep+dd)
				if bool(q.get("found",false)) and q.path.size()<best_len:best_len=q.path.size();goal=ep+dd
		if goal==Vector2i(-1,-1):break
		var raw:Dictionary=session.sim.pathfinder.find_path(hero,goal)
		# Tap the next cell through the UI so the product contact settlement runs.
		# Once adjacent, wait in place: under the awareness rule the enemy opens
		# the contact when it notices the hero.
		if bool(raw.get("found",false)) and raw.path.size()>=2:
			ui.grid.world_cell_pressed.emit(raw.path[1])
		else:ui._on_explore(Vector2i.ZERO)
		await process_frame;await process_frame
	_check(reached_contact,"walking toward the nearest enemy makes contact")
	ui._refresh();await process_frame
	var phase_after:=str(session.party_status().get("safe_phase",""))
	_check(phase_after=="ENGAGED","contact is settled into combat by the next refresh (phase %s)"%phase_after)
	_check(str(session.party_status().get("view_mode",""))=="COMBAT","view switches to COMBAT")
	_check(ui.hero_turn_waiting() or phase_after!="ENGAGED","HERO_TURN waits for the first hero decision")
	var saved:String=session.save_session_json();var loaded=Session.new()
	var load_result:Dictionary=loaded.load_session_json(saved)
	_check(bool(load_result.get("accepted",false)),"solo deployment journal reloads: %s"%str(load_result.get("reason","")))
	if bool(load_result.get("accepted",false)):_check(loaded.sim.snapshot()==session.sim.snapshot(),"solo deployment replays exactly")
	if failures.is_empty():print("PASS solo contact engages");quit(0)
	else:printerr("FAIL solo contact engages: %d failures"%failures.size());quit(1)
