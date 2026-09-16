extends SceneTree
const Assets=preload("res://playtest/fantasy_pawn_assets.gd")
const Fixed=preload("res://playtest/fixed_front_topdown_assets.gd")
const Items=preload("res://playtest/pixel24_item_assets.gd")
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func settle()->void:
	for i in range(6):await process_frame
func capture(path:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run()->void:
	root.size=Vector2i(450,800);root.content_scale_size=Vector2i(450,800)
	for collection in [Assets.BODIES,Assets.ICONS,Assets.MONSTERS]:
		for id in collection:
			var im:Image=collection[id].get_image()
			check(im.get_size()==Vector2i(128,128),"runtime size "+id)
			check(im.get_pixel(0,0).a==0 and im.get_pixel(127,127).a==0,"transparent exterior "+id)
			check(im.get_used_rect().get_area()>500,"foreground retained "+id)
	for species in Assets.BODIES:
		var spec:=Fixed.actor_layer_spec({"species_id":species})
		check(spec.asset_family==Assets.FAMILY and not spec.supports_walk,"pawn species "+species)
		check(spec.visual_cell_ratio<=1.0,"pawn fits one tile "+species)
	check(Fixed.body_texture("generic_humanoid")==Fixed.body_texture("human"),"generic humanoid alias")
	check(Fixed.actor_layer_spec({"species_id":"shadow_beast"}).asset_family=="0X72_DUNGEON_II","uncovered monster preserved")
	for species in Assets.MONSTERS:
		var monster:=Fixed.actor_layer_spec({"species_id":species})
		check(monster.body_texture==Assets.MONSTERS[species] and monster.monster_sprite,
			"dedicated monster art "+species)
		check(monster.species_id==species and monster.visual_cell_ratio<=1.0,
			"monster identity and one-cell footprint "+species)
	for species in preload("res://sim/dcss_enemy_registry.gd").DEFINITIONS:
		check(Fixed.actor_layer_spec({"species_id":species}).asset_family==Assets.FAMILY,
			"registered dungeon spawn has art "+species)
	check(Fixed.body_texture("dcss_orc")==Fixed.body_texture("orc"),"dungeon orc uses approved orc base")
	var shield:=Fixed.actor_layer_spec({"species_id":"elf","equipment_visual":{
		"weapon_definition_id":"WEAPON_HAND_AXE","off_hand_definition_id":"SHIELD_WOOD"}})
	check(shield.weapon_texture==Assets.ICONS.axe and shield.offhand_texture==Assets.ICONS.shield,"equipment attachments use icons")
	for id in Assets.ITEM_IDS:
		check(Items.texture_for_id(id)==Assets.ICONS[Assets.ITEM_IDS[id]],"inventory mapping "+id)
	check(Items.texture_for_id("POTION_POISON")==Assets.Legacy.item("POTION_POISON"),"uncovered potion preserved")
	var wall:={"terrain_id":"wall","visibility_state":"VISIBLE"}
	var floor_cell:={"terrain_id":"floor","visibility_state":"VISIBLE"}
	check(Tiles.tile_spec(wall,Vector2i.ZERO,1,{"S":floor_cell}).sprite_key=="wall_04","south face exposed")
	check(Tiles.tile_spec(wall,Vector2i.ZERO,1,{"S":{"terrain_id":"floor","visibility_state":"UNSEEN"}}).sprite_key=="wall_00","hidden neighbors do not reveal wall shape")
	for mask in range(16):
		var neighbors:={}
		for i in range(4):
			if mask & (1<<i):neighbors[["N","E","S","W"][i]]=floor_cell
		var spec:=Tiles.tile_spec(wall,Vector2i.ZERO,1,neighbors)
		check(spec.texture!=null and spec.texture.get_size()==Vector2(64,64),"wall connectivity %d"%mask)
	check(not Tiles.tile_spec({"visibility_state":"UNSEEN"},Vector2i.ZERO,1).visible,"unseen tiles hidden")
	check(Tiles.tile_spec({"terrain_id":"floor","visibility_state":"MEMORY"},Vector2i.ZERO,1).visible,"remembered floor retained")
	check(Tiles.tile_spec({"terrain_id":"lava","visibility_state":"VISIBLE"},Vector2i.ZERO,1).sprite_key=="lava","hazard art preserved")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human",false)
	ui._refresh();await settle()
	var before:Dictionary=session.sim.snapshot()
	var hero:int=session.sim.world.party_control_actor_id()
	var projected:Dictionary={}
	for actor in ui.grid._actors:
		if int(actor.get("entity_id",-1))==hero:projected=actor
	var spec:Dictionary=ui.grid.fixed_front_actor_render_spec(projected)
	check(spec.get("asset_family")==Assets.FAMILY,"live map uses new family")
	check(spec.get("visible",false),"live protagonist rendered")
	check(session.sim.snapshot()==before,"render inspection does not mutate simulation")
	await capture("/tmp/fantasy-pawns-game.png")
	ui._open_hero_detail_tab("ITEM");await settle()
	await capture("/tmp/fantasy-pawns-inventory.png")
	ui.queue_free();await process_frame
	print("FANTASY PAWNS: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
