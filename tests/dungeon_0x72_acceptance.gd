extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Assets=preload("res://playtest/dungeon_0x72_assets.gd")
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	root.size=Vector2i(390,844)
	for key in Assets.RECTS:
		check(Assets.texture(key).get_size()==Assets.RECTS[key].size,"native atlas region "+key)
		check(Rect2(Vector2.ZERO,Assets.ATLAS.get_size()).encloses(Assets.RECTS[key]),"atlas bounds "+key)
	for key in Assets.EXTRA:
		check(Rect2(Vector2.ZERO,Assets.EXTENDED.get_size()).encloses(Assets.EXTRA[key]),"extension bounds "+key)
	check(Assets.texture("knight_m_idle_anim_f0")==Assets.texture("knight_m_idle_anim_f0"),"textures are cached")
	for species in Assets.BODIES:
		check(Assets.actor_spec({"species_id":species}).body_texture!=null,"species "+species)
	check(not Tiles.tile_spec({"visibility_state":"UNSEEN"},Vector2i.ZERO,1).visible,"unseen terrain remains hidden")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(session.town_life_command({"action":"START"}).accepted,"town starts")
	check(session.depart_town().accepted,"dungeon departure")
	var hero:int=session.sim.world.party_control_actor_id()
	var before:Dictionary=session.sim.snapshot()
	session.observe_party_ui(15,true,19,true)
	check(session.sim.snapshot()==before,"observation preserves simulation")
	var detail:Dictionary=session.inspect_party_member(hero)
	var first:Dictionary=Assets.actor_spec(detail)
	check(first.asset_family=="0X72_DUNGEON_II","main actor uses 0x72")
	check(session.equip_inventory_item("START_HAND_AXE_001","MAIN_HAND").accepted,"equip axe")
	var second:Dictionary=Assets.actor_spec(session.inspect_party_member(hero))
	check(second.weapon_texture==Assets.item("WEAPON_HAND_AXE") and second.weapon_texture!=first.weapon_texture,"equipped weapon switches actual sprite")
	var bare:Dictionary=Assets.actor_spec({"species_id":"human","equipment_visual":{}})
	check(bare.weapon_texture==null and bare.offhand_texture==null,"empty hands have no equipment icon")
	var shield:Dictionary=Assets.actor_spec({"species_id":"human","equipment_visual":{"off_hand_definition_id":"SHIELD_WOOD"}})
	check(shield.off_hand_definition_id=="SHIELD_WOOD" and shield.offhand_texture==null,"shield overlay connected")
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	for i in range(6):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/0x72-dungeon-mobile.png")
	ui._open_hero_detail_tab("ITEM")
	for i in range(4):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/0x72-inventory-mobile.png")
	ui.queue_free();await process_frame
	check(session.sim.world.world_state_error().is_empty(),"world remains valid")
	print("0X72 ASSETS: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
