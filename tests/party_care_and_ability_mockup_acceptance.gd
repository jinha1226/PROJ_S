extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Care=preload("res://sim/party_recovery_rules.gd")
const Portrait=preload("res://playtest/compact_party_portrait.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func settle()->void:
	for i in range(4):await process_frame
func run()->void:
	root.size=Vector2i(390,800);root.content_scale_size=Vector2i(390,800)
	var legacy=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	legacy.sim.world.entities[legacy.sim.world.party_encounter.protagonist_id].tags.erase(Care.TAG)
	var migrated=Session.new()
	var migration:Dictionary=migrated.load_session_json(legacy.save_session_json())
	check(migration.accepted and Care.enabled(migrated.sim.world),"old field save enables care after old replay")
	var migrated_again=Session.new()
	check(migrated_again.load_session_json(migrated.save_session_json()).accepted,"migration marker itself replays")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var world=session.sim.world;var hero:int=world.party_control_actor_id()
	var ally:int=world.party_encounter.active_party_member_ids[1]
	var bag:Array=session.protagonist_inventory().backpack_rows
	check(not bag.is_empty(),"fixture has droppable item")
	if not bag.is_empty():
		var id:String=bag[0].instance_id
		var dropped:Dictionary=session.drop_inventory_item(id)
		check(dropped.accepted,"field item action advances through field scheduler: "+str(dropped.get("reason")))
		var picked:Dictionary=session.pickup_ground_item(id)
		check(picked.accepted,"item on controlled actor cell can be picked up: "+str(picked.get("reason")))
		var loaded=Session.new()
		var result:Dictionary=loaded.load_session_json(session.save_session_json())
		check(result.accepted,"item actions replay: "+str(result.get("reason")))
		if result.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"item save snapshot matches")
	var ui=Sandbox.new();ui.initialize_for_headless_test(session,false);root.add_child(ui)
	await settle()
	check(ui.hero_skill_row.get_child_count()==1,"one full-width skill bar")
	check(ui.hero_skill_row.get_child(0).get_child_count()==3,"three active slots including empties")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/lw-party-hud.png")
	ui._open_member_detail(ally,"SKILL");await settle()
	check(ui.member_detail_skill_tab.text.contains("이능"),"ability tab replaces mastery label")
	var mock=ui.member_ability_window
	check(mock.visible and mock.slot_grid.get_child_count()==6 and mock.slot_grid.columns==2,"six-slot two-column in-game mockup")
	var before:Dictionary=session.sim.snapshot()
	mock._select(4);mock._equip(mock.owned.back());mock._toggle_mode()
	check(session.sim.snapshot()==before,"mock equipment never changes real character")
	check(mock.get_global_rect().end.x<=390,"mock fits mobile width")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/lw-ability-mockup.png")
	ui._close_member_detail();await settle()
	ui._open_member_detail(ally);await settle()
	check(ui.member_status_window.find_child("StatusRecoveryStats",true,false)!=null,"HP and MP recovery stats displayed")
	ui._close_member_detail();await settle()
	# Pure recovery fixture: injured companion, full-health leader, depleted MP.
	world.entities[ally].health-=3
	world.party_encounter.member(ally).energy-=2
	check(ui._rest_needed(),"rest considers companion HP/MP")
	var old_hp:int=world.entities[ally].health;var old_mp:int=world.party_encounter.member(ally).energy
	world.party_encounter.safe_recovery_turns=0
	for id in world.party_encounter.enemy_ids:
		var awareness=world.party_encounter.enemy_awareness(id)
		if awareness!=null:awareness.awareness_state="UNAWARE"
	world.combatant_states[ally].status_rows.clear()
	var recovered:Dictionary=Care.apply(session,world.events.size(),500)
	check(recovered.accepted and world.entities[ally].health>old_hp,"full leader does not prevent companion HP recovery")
	check(world.party_encounter.member(ally).energy>old_mp,"MP recovery rate affects actual recovery")
	var hp_after:int=world.entities[ally].health
	Care.apply(session,world.events.size(),50)
	check(world.entities[ally].health==hp_after,"fast small actions do not grant extra pulse")
	check(session.sim.movement.allows_occupied_diagonal_flanks(ally),"AI companion shares controlled diagonal flank rule")
	var diagonal_checked:=false
	var origin:Vector2i=world.entities[ally].position
	for delta in [Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]:
		var target:Vector2i=origin+delta
		if not world.in_bounds(target) or not world.diagonal_step_terrain_allowed(origin,target):continue
		if not session.sim.movement._terrain_passable(target):continue
		var flank:=origin+Vector2i(delta.x,0)
		var projection:Dictionary={"%d:%d"%[flank.x,flank.y]:hero}
		check(session.sim.pathfinder._can_step(ally,origin,target,projection),"companion path permits diagonal beside party member")
		diagonal_checked=true;break
	check(diagonal_checked,"fixture exercises an actual diagonal edge")
	# Four portraits at a 360px viewport still keep the name below the art.
	for i in range(4):
		var portrait=Portrait.new();portrait.size=Vector2(88,72)
		var layout:Dictionary=portrait.portrait_layout_spec()
		check(layout.name_position.y>layout.portrait.end.y and layout.stats_x>=layout.portrait.end.x,"four-party portrait geometry")
		portrait.free()
	ui.queue_free();await process_frame
	print("PARTY CARE / ABILITY MOCKUP: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
