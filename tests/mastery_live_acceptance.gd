extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const State=preload("res://sim/growth_build_state.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Weapon=preload("res://sim/weapon_attack_rules.gd")
const Fixtures=preload("res://tests/test_party_auto_explore.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var state=State.new();state.xp_total=State.RegistryScript.xp_floor_for_level(6)
	for axis in State.Mastery.IDS:
		var purchase:Dictionary=state.commit_spend_mastery_point(axis)
		check(purchase.accepted,"invest "+axis)
		if purchase.accepted:state=purchase.state
	check(state.mastery_points_available()==1,"one point each level, four spent")
	var wire:Dictionary=JSON.parse_string(JSON.stringify(state.to_dict()))
	check(State.wire_error(wire).is_empty(),"mastery wire validates")
	check(State.from_dict(wire).mastery_ranks==state.mastery_ranks,"mastery JSON round trip")
	check(State.from_dict_unchecked(wire).mastery_ranks==state.mastery_ranks,"rollback decoder retains mastery")
	wire.mastery_ranks.MELEE=20
	check(not State.wire_error(wire).is_empty(),"overspent forged wire rejected")
	var bare:=State.new().to_dict();bare.erase("mastery_ranks")
	check(State.from_dict(bare)!=null,"pre-mastery rank-zero migration")
	var base:Dictionary=Weapon.build_attack_spec("SHORT_SWORD",0,10,100,0,0,null,true)
	var trained:Dictionary=Weapon.build_attack_spec("SHORT_SWORD",10,10,100,0,0,null,true)
	check(trained.raw_damage>base.raw_damage,"melee multiplier affects damage before armor")
	var fixture=Fixtures.new();var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	for id in session.sim.world.party_encounter.enemy_ids:
		var hidden:Vector2i=fixture._hidden_passable_cell(session,id)
		if hidden.x>=0:session.sim.world.entities[id].position=hidden
		session.sim.world.party_encounter.enemy_busy_rows[id]=1000000000
	check(session.field_turns_active(),"test uses real campaign engine")
	var world=session.sim.world;var party=world.party_encounter
	party.protagonist_growth.xp_total=State.RegistryScript.xp_floor_for_level(3)
	check(session.mastery_status().points==2,"level THREE immediately has two unspent points")
	var before_time:int=world.world_time;var before_journal:int=session.command_journal.size()
	var invested:Dictionary=session.spend_mastery_point("DEFENSE")
	check(invested.accepted,"live facade commits mastery: "+str(invested.reason))
	check(world.world_time==before_time and session.command_journal.size()==before_journal+1,"zero time journaled investment")
	check(world.world_state_error().is_empty(),"live mastery state validates: "+world.world_state_error())
	var restored=Session.SimulatorScript.from_snapshot(session.sim.snapshot())
	check(restored!=null and restored.world.party_encounter.protagonist_growth.mastery_ranks.DEFENSE==1,"world snapshot keeps allocated points")
	var memento:Dictionary=world.rollback_memento(false)
	party.protagonist_growth.mastery_ranks.DEFENSE=2
	check(session.sim.restore_rollback_memento(memento),"restore mastery memento")
	check(session.mastery_status().ranks.DEFENSE==1,"rank rollback exact")
	world=session.sim.world;party=world.party_encounter
	root.size=Vector2i(360,800)
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	ui._open_hero_detail_tab("SKILL");await process_frame
	check(ui.mastery_panel.is_visible_in_tree() and ui.mastery_panel.rows.size()==4,"existing character tab exposes four-axis UI")
	check(ui.mastery_panel.summary.text.contains("남은 포인트"),"points shown in real UI")
	check(not ui.mastery_panel.rows.MELEE.button.disabled,"level THREE investment button enabled in safety")
	var threat_id:int=party.enemy_ids[0]
	var saved_position:Vector2i=world.entities[threat_id].position
	var threat_cell:Vector2i=fixture._visible_empty_cell(session,session._auto_explore_fog_snapshot())
	world.entities[threat_id].position=threat_cell;party.revision+=1
	ui._refresh_open_member_detail()
	check(ui.mastery_panel.rows.MELEE.button.disabled and ui.mastery_panel.summary.text.contains("주변 적"),"visible threat explains level THREE lock")
	world.entities[threat_id].position=saved_position;party.revision+=1
	ui._refresh_open_member_detail()
	check(not ui.mastery_panel.rows.MELEE.button.disabled,"safety restores investment without another level-up or reopening")
	ui.mastery_panel.preview("MELEE")
	check(ui.mastery_panel.confirm.visible,"investment preview requires confirmation")
	ui.mastery_panel.commit()
	check(session.mastery_status().ranks.MELEE==1,"UI commits to campaign, not demo")
	ui.mastery_panel.confirm.hide()
	ui._open_hero_detail_tab("STATUS")
	ui._refresh_open_member_detail()
	await process_frame
	var before_summary:String=ui.find_child("StatusCombatSummary",true,false).text
	check(session.equip_inventory_item("START_HAND_AXE_001","MAIN_HAND").accepted,"change weapon with status open")
	ui._refresh()
	await process_frame
	check(ui.member_detail_modal.visible and ui.member_detail_current_tab=="STATUS","refresh preserves open status tab")
	check(ui.find_child("StatusCombatSummary",true,false).text!=before_summary,"open status combat numbers update without reopening")
	var summary_node=ui.find_child("StatusCombatSummary",true,false)
	ui._refresh_open_member_detail()
	check(ui.find_child("StatusCombatSummary",true,false)==summary_node,"unchanged frame does not rebuild modal")
	if DisplayServer.get_name()!="headless":
		for i in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/living-world-mastery-360.png")
	ui.queue_free();await process_frame
	world=session.sim.world;party=world.party_encounter
	var hero_id:int=party.protagonist_id
	var enemy_id:int=party.enemy_ids[0]
	var origin:Vector2i=world.entities[hero_id].position
	var target_position:=Vector2i(-1,-1)
	for direction in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		var path:Dictionary=session.sim.pathfinder.find_path(hero_id,origin+direction)
		if path.found:target_position=origin+direction;break
	check(target_position.x>=0,"adjacent attack fixture")
	if target_position.x>=0:
		world.entities[enemy_id].position=target_position
		var blocked:Dictionary=session.spend_mastery_point("MAGIC")
		check(not blocked.accepted,"visible threat prevents investment")
		var attack:Dictionary=session.strike_enemy(enemy_id)
		check(attack.accepted,"trained attack executes: "+str(attack.reason))
		check(session.sim.world.world_state_error().is_empty(),"trained combat history validates: "+session.sim.world.world_state_error())
	earned_point_replay()
	print("MASTERY LIVE: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func earned_point_replay()->void:
	# Real kill XP, not a debug grant, proves the save journal can reconstruct
	# the budget and the zero-time investment in order.
	var session=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var party=session.sim.world.party_encounter
	var hero_id:int=party.protagonist_id;var enemy_id:int=party.enemy_ids[0]
	for i in range(16):
		if session.party_status().safe_phase!="GROUPED":break
		var hero=session.sim.world.entities[hero_id];var enemy=session.sim.world.entities[enemy_id]
		var delta:Vector2i=enemy.position-hero.position
		if not session.commit_exploration(Command.move_to(hero_id,hero.position+Vector2i(signi(delta.x),signi(delta.y)))).accepted:break
	if session.party_status().safe_phase=="CONTACT":session.enter_solo_combat()
	for i in range(40):
		if str(session.sim.world.combatant_states[enemy_id].life_state)=="DEAD":break
		var hero=session.sim.world.entities[hero_id];var enemy=session.sim.world.entities[enemy_id]
		var delta:Vector2i=enemy.position-hero.position
		var result:Dictionary=session.commit_direct_solo_action(hero_id,"MELEE",[],enemy_id) if maxi(absi(delta.x),absi(delta.y))<=1 \
			else session.commit_direct_solo_action(hero_id,"MOVE",[hero.position.x+signi(delta.x),hero.position.y+signi(delta.y)])
		if not result.accepted:break
	check(session.mastery_status().points==1,"first real kill awards level-up mastery point")
	var spent:Dictionary=session.spend_mastery_point("MAGIC")
	check(spent.accepted,"earned point spent after combat: "+str(spent.reason))
	var loaded=Session.new();var result:Dictionary=loaded.load_session_json(session.save_session_json())
	check(result.accepted,"mastery journal replay accepted: "+str(result.reason))
	if result.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"earned mastery exact replay")
