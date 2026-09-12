extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Assets=preload("res://playtest/kenney_dungeon_assets.gd")
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	root.size=Vector2i(390,844)
	for index in range(132):
		check(Assets.texture(index).get_size()==Vector2(16,16),"native atlas cell "+str(index))
	check(Assets.texture(88)==Assets.texture(88),"textures are cached")
	for species in Assets.BODIES:
		check(Assets.actor_spec({"species_id":species}).body_texture!=null,"species "+species)
	check(not Tiles.tile_spec({"visibility_state":"UNSEEN"},Vector2i.ZERO,1).visible,"unseen terrain remains hidden")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(session.town_life_command({"action":"START"}).accepted,"town starts")
	check(session.depart_town().accepted,"dungeon departure")
	var hero:int=session.sim.world.party_control_actor_id()
	var before:Dictionary=session.sim.snapshot()
	var observation:Dictionary=session.observe_party_ui(15,true,19,true)
	check(session.sim.snapshot()==before,"observation preserves simulation")
	var detail:Dictionary=session.inspect_party_member(hero)
	var first:Dictionary=Assets.actor_spec(detail)
	check(first.asset_family=="KENNEY_TINY_DUNGEON","main actor uses Kenney")
	check(session.equip_inventory_item("START_HAND_AXE_001","MAIN_HAND").accepted,"equip axe")
	var second:Dictionary=Assets.actor_spec(session.inspect_party_member(hero))
	check(second.weapon_texture==Assets.item("WEAPON_HAND_AXE") and second.weapon_texture!=first.weapon_texture,"equipped weapon switches actual sprite")
	var bare:Dictionary=Assets.actor_spec({"species_id":"human","equipment_visual":{}})
	check(bare.weapon_texture==null and bare.offhand_texture==null,"empty hands have no equipment icon")
	var shield:Dictionary=Assets.actor_spec({"species_id":"human","equipment_visual":{"off_hand_definition_id":"SHIELD_WOOD"}})
	check(shield.offhand_texture==Assets.item("SHIELD_WOOD"),"shield overlay connected")
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	for i in range(6):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/kenney-dungeon-mobile.png")
	ui._open_hero_detail_tab("ITEM")
	for i in range(4):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/kenney-inventory-mobile.png")
	ui.queue_free();await process_frame
	check(session.sim.world.world_state_error().is_empty(),"world remains valid")
	print("KENNEY ASSETS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
