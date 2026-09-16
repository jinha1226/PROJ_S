extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Map=preload("res://playtest/deterministic_dungeon_map.gd")
const Action=preload("res://sim/party_action_command.gd")
const Campaign=preload("res://playtest/campaign_world_map.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func touch(point:Vector2,pressed:bool):
	var event:=InputEventScreenTouch.new();event.position=point;event.pressed=pressed;root.push_input(event,true)
func run():
	var s=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true);s.rescue_new_runs=true
	check(s.start_procedural_run_with_species("human",15,20260829).accepted,"start")
	var hero:int=s.sim.world.party_control_actor_id();var opening=s.sim.world.party_encounter.opening_event
	var npc:int=opening.npc_entity_id
	var path:Array=Map._shortest_cardinal_path(s._map_layout,s.sim.world.entities[hero].position,opening.spawn_position)
	for i in range(1,path.size()-1):check(s.commit_field_action(Action.move_to(hero,path[i])).accepted,"approach")
	var ui=preload("res://playtest/party_encounter_sandbox.gd").new()
	root.size=Vector2i(390,844);ui.initialize_for_headless_test(s,true);root.add_child(ui);ui.set_process(false)
	for i in range(5):await process_frame
	ui._open_member_detail(npc)
	for i in range(5):await process_frame
	check(not ui.member_detail_subtitle.visible,"no species role life subtitle")
	check(ui.member_detail_candidate_action.text=="물약 주기" and not ui.member_detail_candidate_action.disabled,"detail offers potion")
	var hp:int=s.sim.world.entities[npc].health;var time:int=s.sim.world.world_time
	var point:Vector2=ui.member_detail_candidate_action.get_global_rect().get_center()
	touch(point,true);touch(point,false)
	for i in range(8):await process_frame
	check(s.opening_event_status().choice=="GAVE_POTION","touch gives potion")
	check(s.sim.world.entities[npc].health>hp,"NPC health increases")
	check(s.sim.world.world_time==time+100,"gift spends one turn")
	check(not ui.member_detail_modal.visible and not ui.grid.modal_open and not ui._product_gift_pending,"input unlocked after gift")
	check(s.commit_field_action(Action.hold(hero)).accepted,"next turn accepted")
	var saved:String=s.save_session_json()
	check(s.load_session_json(saved).accepted,"gift and following turn replay")
	ui.queue_free();await process_frame
	# High-affinity personalities previously rolled back the entire gift on join.
	for personality in [13,14,15]:
		check(s.start_procedural_run_with_species("human",15,personality).accepted,"join fixture")
		hero=s.sim.world.party_control_actor_id();opening=s.sim.world.party_encounter.opening_event;npc=opening.npc_entity_id
		path=Map._shortest_cardinal_path(s._map_layout,s.sim.world.entities[hero].position,opening.spawn_position)
		for i in range(1,path.size()-1):check(s.commit_field_action(Action.move_to(hero,path[i])).accepted,"join approach")
		var gift:Dictionary=s.commit_opening_event_choice("GIVE_POTION")
		check(gift.accepted and gift.get("immediate_recruitment",{}).get("joined",false),"gift joins high-affinity NPC")
		check(not s.commit_opening_event_choice("GIVE_POTION").accepted,"duplicate gift rejected")
		check(s.commit_field_action(Action.hold(hero)).accepted,"joined companion next turn")
		var before:Dictionary=s.sim.snapshot()
		check(s.load_session_json(s.save_session_json()).accepted,"joined companion replay")
		check(s.sim.snapshot()==before,"joined companion exact replay")
	# Prior procedural saves keep their original deterministic behavior rules.
	check(s.reset_party(15,13,s.DUO_SCENARIO_ID,Campaign.generate(15,1,true,true,true,5),true,"human",true,true,true,true,true,true,true),"v5 fixture")
	check(not s.allows_companions(),"v5 companion policy retained")
	check(s.commit_field_action(Action.hold(s.sim.world.party_control_actor_id())).accepted,"v5 turn")
	var old_snapshot:Dictionary=s.sim.snapshot()
	check(s.load_session_json(s.save_session_json()).accepted,"v5 save accepted")
	check(s.sim.snapshot()==old_snapshot,"v5 exact replay")
	# Reach stairs while live monsters remain; no debug kills or relocation.
	var layout:Dictionary=Campaign.generate(15,1,true,true,true)
	var portal:Vector2i=layout.entry_position+Vector2i.RIGHT
	layout.transition_portal_position=portal;layout.exit_position=portal
	layout.campaign_floors[1].transition_portal_position=portal;layout.campaign_floors[1].exit_position=portal
	check(s.reset_party(15,1,s.DUO_SCENARIO_ID,layout,false,"human",true,true,true,true,true,true,true),"stairs fixture")
	hero=s.sim.world.party_control_actor_id()
	check(s.run_progress().exit.open and not s._field_floor_cleared(),"stairs visible before floor clear")
	check(s.commit_field_action(Action.move_to(hero,portal)).accepted,"walk to stairs")
	check(s.floor_transition_assessment().accepted,"stairs available with monsters alive")
	check(s.advance_campaign_floor().accepted,"enter floor two without killing monsters")
	check(s.expedition_cycle_status().floor_index==2,"second floor entered")
	check(s.sim.world.world_state_error().is_empty(),"transition world valid")
	# Isolated perception projection: visibility must respect walls, not facing at close range.
	var world=s.sim.world;var party=world.party_encounter;var enemy:int=party.enemy_ids[0]
	var origin:Vector2i=world.entities[hero].position
	world.entities[enemy].position=origin+Vector2i(2,0)
	world.tile_at(origin+Vector2i.RIGHT).terrain="stone_floor";world.tile_at(origin+Vector2i(2,0)).terrain="stone_floor"
	var board=preload("res://sim/enemy_squad_blackboard.gd")
	check(hero in board.visible_party_ids(world,enemy),"close target detected")
	check(s.sim.party_coordinator._update_enemy_awareness(enemy,world.step_index),"awareness update")
	check(party.enemy_awareness(enemy).awareness_state=="HUNTING","close target immediately hunted")
	world.tile_at(origin+Vector2i.RIGHT).terrain="wall"
	check(hero not in board.visible_party_ids(world,enemy),"wall blocks close detection")
	# Spending is allowed at a settled combat decision; points and rank still enforced.
	world.tile_at(origin+Vector2i.RIGHT).terrain="stone_floor"
	party.protagonist_growth.xp_total=s.GrowthBuildRegistryScript.xp_floor_for_level(3)
	check(s.mastery_spend_assessment(hero).accepted,"mastery does not require safety")
	var panel=preload("res://playtest/mastery_panel.gd").new();root.add_child(panel);panel.refresh(s,hero)
	check(not panel.rows.MELEE.button.disabled,"mastery UI remains enabled near enemies")
	panel.queue_free();await process_frame
	print("FIELD FEEDBACK: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
