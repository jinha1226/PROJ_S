extends SceneTree

## Per-actor battle scheduler acceptance: one action per due actor, canonical
## time stops at the next event, reservations are free until executed, and the
## journal replays exactly. UI checks use the single-screen sandbox.

const Session=preload("res://playtest/party_playtest_session.gd")
const SimCommand=preload("res://sim/sim_command.gd")
const WORLD_SEED:=44
const PERSONALITY_SEED:=20260828
var failures:Array[String]=[]

func _init()->void:call_deferred("_run")

func _check(value:bool,message:String)->void:
	if not value:failures.append(message)

func _check_eq(got:Variant,expected:Variant,message:String)->void:
	if got!=expected:failures.append("%s (expected %s, got %s)"%[message,str(expected),str(got)])

func _new_engaged_duo():
	var session=Session.new(WORLD_SEED,PERSONALITY_SEED,Session.DUO_SCENARIO_ID)
	if session.sim==null:
		_check(false,"DUO session did not initialize");return null
	var state=session.sim.world.party_encounter
	var hero_id:=int(state.protagonist_id)
	var best:Dictionary={}
	for enemy_id_value in state.enemy_ids:
		var enemy_id:=int(enemy_id_value)
		if not session.sim.world.is_unresolved_enemy(enemy_id):continue
		var enemy_position:Vector2i=session.sim.world.entities[enemy_id].position
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var path:Dictionary=session.find_exploration_path(hero_id,enemy_position+delta)
			if bool(path.get("found",false)) and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if not best.is_empty() and best.path.size()<=4:break
	if best.is_empty():
		_check(false,"normal generated DUO map has no route to an encounter");return null
	for value in best.path.slice(1):
		var step:Dictionary=session.commit_exploration(SimCommand.move_to(hero_id,value))
		if not bool(step.get("accepted",false)):
			_check(false,"normal route step rejected: %s"%str(step.get("reason","")));return null
		if str(session.party_status().get("safe_phase",""))=="CONTACT":break
	# Awareness rule: an enemy that noticed the party opens the contact on its
	# next step. Give it up to three turns after the walk.
	for wait_turn in range(3):
		if str(session.party_status().get("safe_phase",""))!="GROUPED":break
		if not bool(session.commit_exploration(SimCommand.wait(hero_id)).get("accepted",false)):break
	_check_eq(session.party_status().get("safe_phase",""),"CONTACT","generated route reaches contact")
	if str(session.party_status().get("safe_phase",""))!="CONTACT":return null
	var companion_id:=int(state.party_member_ids[1])
	var preview:Dictionary=session.preview_deployment("LINE",[companion_id])
	_check(bool(preview.get("accepted",false)),"normal deployment preview accepts companion")
	if not bool(preview.get("accepted",false)):return null
	var committed:Dictionary=session.commit_deployment()
	_check(bool(committed.get("accepted",false)),"normal deployment enters combat")
	_check_eq(session.party_status().get("safe_phase",""),"ENGAGED","generated deployment enters ENGAGED")
	return session
const Clock=preload("res://playtest/autonomous_battle_clock.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")

func _run()->void:
	_clock_checks()
	var session=_new_engaged_duo()
	if session==null:quit(1);return
	var flow=session.individual_battle
	# A stale journal command cannot advance the clock or emit a partial action.
	var untouched:String=JSON.stringify(session.sim.snapshot())
	_check(not flow.commit({"actor_id":"999","at":"0"}).get("accepted",false),"stale next-event command rejected")
	_check_eq(JSON.stringify(session.sim.snapshot()),untouched,"stale event leaves world unchanged")
	var journal_start:int=session.command_journal.size()
	var actor_steps:=0;var ticks:=0;var max_usec:=0
	var costs:Array=[]
	var actors:Dictionary={}
	for index in range(65):
		var next:Dictionary=flow.next_event()
		if next.is_empty():break
		var started:=Time.get_ticks_usec()
		var result:Dictionary=flow.commit()
		var cost:=Time.get_ticks_usec()-started;costs.append(cost)
		max_usec=maxi(max_usec,cost)
		_check(result.get("accepted",false),"individual commit accepted: "+str(result.get("reason","")))
		if not result.get("accepted",false):break
		_check_eq(session.sim.world.world_time,int(next.at),"canonical time stops at next event, never at longest party cost")
		var roots:=0
		for id in result.get("event_ids",[]):
			var event=session.sim.world.event_by_id(int(id))
			if event.type not in ["action.move","action.melee_attack","action.hold","action.skill"]:continue
			var cause=session.sim.world.event_by_id(int(event.cause_id))
			if cause!=null and cause.type=="action.skill":continue
			roots+=1;_check_eq(event.actor_id,int(next.actor_id),"only due actor acts")
		if int(next.actor_id)>0:
			actor_steps+=1;actors[int(next.actor_id)]=true
			_check_eq(roots,1,"one action per individual event")
		else:
			ticks+=1;_check_eq(roots,0,"status/environment ticks never run an enemy batch")
	_check(actor_steps>=6 and ticks>=2 and actors.size()>=3,"real ally/enemy/environment events exercised")
	_check(session.command_journal.size()>journal_start,"individual steps journaled")
	_check_eq(session.sim.world.world_state_error(),"","full canonical audit after individual combat")
	var saved:String=session.save_session_json()
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(saved)
	_check(loaded.get("accepted",false),"individual journal replays: "+str(loaded.get("reason","")))
	if loaded.get("accepted",false):
		_check_eq(restored.sim.snapshot(),session.sim.snapshot(),"replay is deterministic")
	costs.sort()
	print("INDIVIDUAL actors=%d ticks=%d distinct=%d median_commit_us=%d max_commit_us=%d phase=%s"%[
		actor_steps,ticks,actors.size(),int(costs[costs.size()/2]) if not costs.is_empty() else 0,
		max_usec,session.sim.world.party_encounter.safe_phase])
	await _reservation_and_ui()
	for failure in failures:printerr("FAIL ",failure)
	print("PASS individual battle acceptance" if failures.is_empty() else "FAIL individual battle: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)

func _clock_checks()->void:
	var clock=Clock.new()
	_check_eq(clock.advance(0.05,1000,false),1010.0,"clock advances continuously")
	clock.paused=true
	_check_eq(clock.advance(0.05,1000,false),1010.0,"pause preserves partial gauge")
	clock.paused=false
	_check_eq(clock.advance(0.05,1000,true),1010.0,"targeting/hold preserves partial gauge")
	_check_eq(clock.advance(0.05,1000,false),1020.0,"resume has no added full cooldown")

func _reservation_and_ui()->void:
	var session=_new_engaged_duo()
	if session==null:return
	var flow=session.individual_battle;var party=session.sim.world.party_encounter
	var companion:int=party.party_member_ids[1];var enemy:int=party.contact_enemy_id
	if enemy<=0:enemy=int(session.party_status().visible_enemy_ids[0])
	# Approach through canonical individual actions until FIREBOLT is in range.
	for index in range(20):
		if flow.assessment(companion,"FIREBOLT",enemy).get("accepted",false):break
		var step:Dictionary=flow.commit()
		if not step.get("accepted",false):break
	var before_time:int=session.sim.world.world_time
	var energy:int=party.member(companion).energy
	var reserved:Dictionary=flow.reserve(companion,"FIREBOLT",enemy)
	_check(reserved.get("accepted",false),"reserve skill: "+str(reserved.get("reason","")))
	if not reserved.get("accepted",false):return
	_check_eq(party.member(companion).energy,energy,"reservation is free until executed")
	_check_eq(session.sim.world.world_time,before_time,"reservation does not advance time")
	_check(flow.cancel(companion).get("accepted",false),"reservation can be cancelled")
	_check_eq(party.member(companion).energy,energy,"cancel needs no energy refund")
	_check(flow.reserve(companion,"FIREBOLT",enemy).get("accepted",false),"reservation can be replaced")
	var save:String=session.save_session_json();var loaded=Session.new()
	var load_result:Dictionary=loaded.load_session_json(save)
	_check(load_result.get("accepted",false),"pending reservation saves/replays: "+str(load_result.get("reason","")))
	if load_result.get("accepted",false):_check_eq(loaded.individual_battle.queued(companion),flow.queued(companion),"queue survives restore")
	root.size=Vector2i(360,640);root.content_scale_size=Vector2i(360,640)
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,true);ui.battle_mode="AUTO";root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	var portrait=ui.cards.find_child("MemberCard%d"%companion,true,false)
	_check(ui.find_child("BattleTimelineBar",true,false)==null and ui.find_child("PortraitBattleMode",true,false)==null,
		"single-screen combat has no turn clock or mode toggle")
	_check(ui.hero_skill_row!=null and ui.hero_skill_row.visible \
		and ui.hero_skill_row.find_child("ActorSkill_%d_STRIKE"%int(party.protagonist_id),true,false)!=null,
		"hero skill row sits above the portraits")
	ui.autonomous_battle_clock.paused=true
	var frozen:int=session.sim.world.world_time
	ui._tick_autonomous_battle(1)
	_check_eq(session.sim.world.world_time,frozen,"pause stops actual combat")
	ui.autonomous_battle_clock.paused=false
	for index in range(40):
		ui._tick_autonomous_battle(0.05)
		if flow.queued(companion).is_empty():break
	_check(flow.queued(companion).is_empty(),"queued action consumed at actor readiness")
	_check_eq(party.member(companion).energy,energy-3,"reserved FIREBOLT spends energy once")
	_check(party.member(companion).busy_until>session.sim.world.world_time,"caster has its own cooldown after casting")
	_check(str(flow.assessment(companion,"FIREBOLT",enemy).get("reason",""))!="active_skill_actor_busy",
		"busy alone never rejects a future reservation (the previous target may have died)")
	var available:=false
	for row in session.active_skill_rows(companion):
		if str(row.skill_id)=="FIREBOLT":available=bool(row.can_select)
	_check(available,"skill button remains available during caster cooldown")
	_check_eq(party.member(companion).energy,energy-3,"future reservation does not spend twice")
	flow.cancel(companion)
	_check(ui.cards.find_child("MemberCard%d"%companion,true,false)==portrait,"portrait node survives automatic actions")
	ui.queue_free();await process_frame
