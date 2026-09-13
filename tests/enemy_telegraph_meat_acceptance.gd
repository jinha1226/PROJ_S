extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Plans=preload("res://sim/enemy_telegraph_rules.gd")
const Action=preload("res://sim/party_action_command.gd")
const Items=preload("res://sim/world_item_operations.gd")
const Registry=preload("res://sim/item_registry.gd")
const Assets=preload("res://playtest/dcss_item_assets.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func fixture():
	return Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
func relocate(w,id:int,p:Vector2i):
	var old:Vector2i=w.entities[id].position
	w.entities[id].position=p;w.reindex_entity_occupancy(id,old,p)
func threat(s,delta:Vector2i)->int:
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var id:int=w.party_encounter.enemy_ids[0]
	relocate(w,id,w.entities[hero].position+delta)
	w.party_encounter.enemy_awareness(id).awareness_state="HUNTING"
	w.party_encounter.enemy_awareness(id).suspicion=1000
	w.party_encounter.enemy_busy_rows[id]=w.world_time
	return id
func run():
	var s=fixture();var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var enemy:=threat(s,Vector2i.RIGHT)
	var before=s.sim.snapshot();var batch:=Plans.plans(s.sim)
	check(batch.has(enemy) and batch[enemy].action_type=="MELEE","adjacent threat announced")
	check(before==s.sim.snapshot(),"forecast never mutates authoritative state")
	check(s.turn_intent_overlays().any(func(r):return r.role=="ENEMY"),"solo HUD includes enemy warning")
	if batch.has(enemy):
		var origin:Vector2i=w.entities[hero].position
		relocate(w,hero,origin+Vector2i.DOWN)
		check(Plans.resolve(s.sim,enemy,batch[enemy]).action_type=="HOLD","sidestep avoids fixed attack cell")
		relocate(w,hero,origin)
		check(Plans.resolve(s.sim,enemy,batch[enemy]).action_type=="MELEE","staying in cell preserves attack")
		relocate(w,enemy,w.entities[enemy].position+Vector2i.RIGHT)
		check(Plans.resolve(s.sim,enemy,batch[enemy]).action_type=="HOLD","displacement interrupts attack")
	# Real field scheduler, not just a presentation prediction.
	s=fixture();w=s.sim.world;hero=w.party_control_actor_id();enemy=threat(s,Vector2i.RIGHT)
	var hp:int=w.entities[hero].health
	var moved=s.commit_field_action(Action.move_to(hero,w.entities[hero].position+Vector2i.DOWN))
	check(moved.get("accepted",false),"dodge field turn commits "+str(moved.get("reason","")))
	check(w.entities[hero].health==hp,"announced attack does not follow sidestep")
	s=fixture();w=s.sim.world;hero=w.party_control_actor_id();enemy=threat(s,Vector2i.RIGHT)
	var start:int=w.events.size()
	var held=s.commit_field_action(Action.hold(hero))
	check(held.get("accepted",false),"hold field turn commits "+str(held.get("reason","")))
	check(w.events_since(start).any(func(e):return e.type=="action.melee_attack" and e.actor_id==enemy),"announced attack actually executes")
	s=fixture();w=s.sim.world;hero=w.party_control_actor_id();enemy=threat(s,Vector2i.RIGHT)
	start=w.events.size()
	var long_turn=s.FieldTurns.step(s.sim,Action.hold(hero),300)
	check(long_turn.accepted,"long response commits")
	var attacks:int=0
	for e in w.events_since(start):
		if e.type=="action.melee_attack" and e.actor_id==enemy:attacks+=1
	check(attacks==1,"no second unannounced attack during long action")
	s=fixture();w=s.sim.world;hero=w.party_control_actor_id();enemy=threat(s,Vector2i(3,0))
	batch=Plans.plans(s.sim)
	check(batch.has(enemy) and batch[enemy].action_type=="MOVE","approach destination announced")
	if batch.has(enemy):
		var dest:Array=batch[enemy].destination
		var hero_origin:Vector2i=w.entities[hero].position
		relocate(w,hero,Vector2i(dest[0],dest[1]))
		check(Plans.resolve(s.sim,enemy,batch[enemy]).action_type=="HOLD","occupied announced destination cancels movement")
		relocate(w,hero,hero_origin)
		var result=s.commit_field_action(Action.move_to(hero,w.entities[hero].position+Vector2i.DOWN))
		check(result.get("accepted",false),"move forecast turn commits")
		check(w.entities[enemy].position==Vector2i(dest[0],dest[1]),"enemy follows announced move, not new pursuit direction")
		relocate(w,enemy,Vector2i(40,24))
		check(not Plans.plans(s.sim).has(enemy),"unseen enemy has no telegraph")
	# Death must not replace terrain; drops are a separate visual layer.
	s=fixture();w=s.sim.world;hero=w.party_control_actor_id();enemy=threat(s,Vector2i.RIGHT)
	var death_cell:Vector2i=w.entities[enemy].position
	var old_terrain:String=w.tile_at(death_cell).terrain
	var terrain_art=preload("res://playtest/dcss_world_assets.gd")
	var old_texture=terrain_art.tile_spec({"terrain_id":old_terrain,"visibility_state":"VISIBLE"},death_cell,1).texture
	var ui=preload("res://playtest/party_encounter_sandbox.gd").new()
	root.size=Vector2i(390,844);ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false);ui._refresh()
	for i in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/enemy-telegraph-before.png")
	for i in range(8):
		if not w.is_autonomous_target(enemy):break
		var hit=s.commit_field_action(Action.melee(hero,enemy))
		check(hit.get("accepted",false),"death regression attack")
	check(not w.is_autonomous_target(enemy),"fixture monster dies")
	check(w.tile_at(death_cell).terrain==old_terrain,"death preserves terrain identity")
	check(terrain_art.tile_spec({"terrain_id":w.tile_at(death_cell).terrain,"visibility_state":"VISIBLE"},death_cell,1).texture==old_texture,"death preserves ground texture")
	ui._refresh()
	for i in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/enemy-telegraph-after.png")
	ui.queue_free();await process_frame
	# Manual nutrition + acquisition, duplicates, full stomach, snapshot audit.
	s=fixture();w=s.sim.world;hero=w.party_control_actor_id()
	w.party_encounter.ration_milli=100000
	var grant:Dictionary=Items.commit_grant(w,hero,"ESSENCE_PREDATOR_NERVE",1,w.entities[hero].position,"MEAT_TEST")
	check(grant.get("accepted",false),"meat grant")
	if grant.get("accepted",false):
		var ate:Dictionary=s.use_inventory_item(str(grant.instance_id))
		check(ate.get("accepted",false),"manual meat ingestion "+str(ate.get("reason","")))
		check(w.party_encounter.ration_milli==120000,"meat restores 20 ration")
		check("PREDATOR_NERVE" in w.party_encounter.member(hero).bound_ability_ids,"meat teaches real ability")
		check(s.set_ability_mode(hero,"PREDATOR_NERVE","PASSIVE").get("accepted",false),"acquired meat ability switches to passive in safe dungeon")
		grant=Items.commit_grant(w,hero,"ESSENCE_PREDATOR_NERVE",1,w.entities[hero].position,"MEAT_TEST")
		ate=s.use_inventory_item(str(grant.instance_id))
		check(ate.get("accepted",false) and not ate.get("gains_ability",true),"duplicate is nutrition only")
		check(w.party_encounter.ration_milli==140000,"duplicate meat still nourishes")
		var error:String=w.world_state_error();check(error.is_empty(),"meat world audit "+error)
		var restored=preload("res://sim/simulator.gd").from_snapshot(s.sim.snapshot())
		check(restored!=null and restored.snapshot()==s.sim.snapshot(),"meat snapshot exact roundtrip")
		grant=Items.commit_grant(w,hero,"ESSENCE_PREDATOR_NERVE",1,w.entities[hero].position,"MEAT_TEST")
		w.party_encounter.ration_milli=preload("res://sim/party_ration_rules.gd").ration_max_milli()
		check(not s.use_inventory_item(str(grant.instance_id)).get("accepted",true),"full stomach blocks consumption")
		check(w.inventory_of(hero).item(str(grant.instance_id))!=null,"rejected meal preserves item")
	for id in Registry.ids():
		if id.begins_with("ESSENCE_"):
			check("정수" not in Registry.definition(id).label and "고기" in Registry.definition(id).label,"meat item label "+id)
			check(Assets.texture_for_id(id).resource_path.ends_with("item__food__chunk.png"),"meat icon "+id)
	check(Assets.texture_for_id("STONE").resource_path.contains("rock"),"stone loot never uses floor tile")
	print("ENEMY TELEGRAPH / MEAT: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
