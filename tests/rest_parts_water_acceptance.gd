extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
const Action=preload("res://sim/party_action_command.gd")
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
const Portrait=preload("res://playtest/compact_party_portrait.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("FAIL ",label)
func _init():run.call_deferred()
func capture(s,path:String):
	if DisplayServer.get_name()=="headless":return
	root.size=Vector2i(450,800);root.content_scale_size=root.size
	var ui=preload("res://playtest/party_encounter_sandbox.gd").new()
	ui.size=Vector2(450,800);ui.initialize_for_headless_test(s,true)
	root.add_child(ui);ui.set_process(false)
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	ui.queue_free();await process_frame
func grant(s,id:int,definition:String):
	var inv=s.sim.world.inventory_of(id)
	var items:Array=inv.backpack.duplicate()
	items.append(Item.new("PART_FIXTURE",definition,1))
	s.sim.world.item_state.inventory_rows[id]=Inventory.new(items,inv.equipped)
func run():
	var s=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_procedural_run_with_species("human",15,13).accepted,"new run")
	var hero:int=s.sim.world.party_control_actor_id()
	grant(s,hero,"ESSENCE_FIRE_BOLT")
	var begin:=Time.get_ticks_usec()
	check(s.use_party_item("PART_FIXTURE",hero).accepted,"eat fire gland")
	print("PART_INGESTION_MS ",(Time.get_ticks_usec()-begin)/1000.0)
	var card:Dictionary=s.party_cards()[0]
	var portrait=Portrait.new();portrait.actor=card
	check(portrait.mobile_condition_text().contains("화상 3턴"),"HUD shows ingestion burn and turns")
	check(bool(card.consumable_harmful),"ingestion status marked harmful")
	portrait.free()
	await capture(s,"/tmp/ingestion-hud.png")
	var before:Dictionary=s.sim.snapshot()
	check(not s.use_party_item("PART_FIXTURE",hero).accepted,"cannot consume twice")
	check(s.sim.snapshot()==before,"rejected consumption preserves state")
	for i in range(4):check(s.commit_field_action(Action.hold(hero)).accepted,"advance burn duration")
	check(not str(s.party_cards()[0].consumable_status).contains("화상"),"expired burn disappears from HUD")
	s=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_procedural_run_with_species("human",15,13).accepted,"water run")
	hero=s.sim.world.party_control_actor_id()
	grant(s,hero,"PART_WATER_SAC")
	check(s.use_party_item("PART_FIXTURE",hero).accepted,"learn water spray")
	var rejection_snapshot:Dictionary=s.sim.snapshot()
	check(not s.commit_field_action(Action.skill_at(hero,"WATER_SAC",Vector2i(-1,-1))).accepted,"invalid floor target rejected")
	check(s.sim.snapshot()==rejection_snapshot,"invalid spray spends no resources or time")
	var target:=Vector2i(-1,-1)
	for xy in s.skill_reach_cells(hero,"WATER_SAC").cells:
		var p:=Vector2i(xy[0],xy[1])
		if s.sim.world.occupying_entities_at(p).is_empty() and s.sim.world.tile_at(p).terrain in ["floor","stone_floor"] and s.FieldTurns.assess(s.sim,Action.skill_at(hero,"WATER_SAC",p)).accepted:
			target=p;break
	check(target!=Vector2i(-1,-1),"empty floor target available")
	if target!=Vector2i(-1,-1):
		var original_terrain:String=s.sim.world.tile_at(target).terrain
		var action=Action.skill_at(hero,"WATER_SAC",target)
		check(Action.wire_error(action.to_dict()).is_empty(),"ground command wire")
		var result:Dictionary=s.commit_field_action(action)
		check(result.accepted,"spray empty floor: "+str(result.get("reason")))
		check(s.sim.world.tile_at(target).wetness>0,"water creates authoritative wetness")
		check(s.sim.world.tile_at(target).terrain==original_terrain,"underlying floor remains intact")
		check(s.sim.world.world_state_error().is_empty(),"water event audit: "+s.sim.world.world_state_error())
		check(Session.SimulatorScript.from_snapshot(s.sim.snapshot())!=null,"wet floor save restores")
		await capture(s,"/tmp/water-spray-floor.png")
	var cell:={"terrain_id":"floor","visibility_state":"VISIBLE","wetness":80,"surface_id":"WATER"}
	check(Tiles.tile_spec(cell,Vector2i.ZERO,1).sprite_key=="water","wet floor uses water art")
	cell.wetness=0;cell.surface_id="NONE"
	check(Tiles.tile_spec(cell,Vector2i.ZERO,1).sprite_key!="water","dry floor restores art")
	cell.wetness=80;cell.visibility_state="MEMORY"
	check(Tiles.tile_spec(cell,Vector2i.ZERO,1).sprite_key!="water","memory does not reveal current wetness")
	cell.visibility_state="VISIBLE";cell.surface_id="ICE"
	check(Tiles.tile_spec(cell,Vector2i.ZERO,1).sprite_key!="water","ice is not drawn as water")
	print("REST PARTS WATER: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
