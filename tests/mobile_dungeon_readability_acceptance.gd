extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Floor=preload("res://playtest/four_zone_floor.gd")
const Assets=preload("res://playtest/dcss_item_assets.gd")
const ItemAssets=preload("res://playtest/pixel24_item_assets.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	for seed in range(20):
		for depth in [1,2]:
			var map:=Floor.generate(depth,seed)
			check(map.width==48 and map.height==48 and map.regions.size()==4,"four regions")
			check(map==Floor.generate(depth,seed),"determinism")
			check(preload("res://playtest/living_floor_design.gd").connectivity_error(map).is_empty(),"reachable floor landmarks")
			var seen:=preload("res://playtest/compact_campaign_floor.gd").flood(map.terrain,48,48,map.entry_position)
			for row in map.runtime_enemy_roster:check(seen.has(row.position),"reachable encounter")
			check(map.planned_enemy_count<=13,"bounded enemy population")
	for id in Assets.FILES:check(Assets.texture_for_id(id)!=null,"asset "+id)
	var WorldAssets=preload("res://playtest/dcss_world_assets.gd")
	for species in WorldAssets.BODIES:
		var actor_spec:=WorldAssets.actor_spec({"species_id":species})
		check(actor_spec.body_texture!=null and actor_spec.asset_family=="DCSS_CC0","actor art "+species)
	for terrain_id in WorldAssets.TERRAIN:
		var tile:=preload("res://playtest/topdown_tile_assets.gd").tile_spec({"terrain_id":terrain_id,"visibility_state":"VISIBLE"},Vector2i(4,5),1)
		check(tile.texture!=null and tile.asset_family=="DCSS_CC0","terrain art "+terrain_id)
	check(not WorldAssets.tile_spec({"visibility_state":"UNSEEN"},Vector2i.ZERO,1).visible,"unseen remains hidden")
	check(ItemAssets.texture_for_id("WEAPON_DCSS_MISSING")==null,"no silent fake weapon mapping")
	check(ItemAssets.texture_for_row({"visual_icon_key":"MYSTERY_POTION_2","definition_id":"POTION_MYSTERY_POISON"})==Assets.texture_for_id("MYSTERY_POTION_2"),"unknown appearance authority")
	root.size=Vector2i(390,844)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var ui=Shell.new();ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false)
	ui.show_species_picker_for_new_run();ui._commit_species_picker("human",false);ui._refresh()
	var w=s.sim.world
	check(w.width==104 and w.height==48,"product uses compact two-floor world")
	check(w.party_encounter.active_party_member_ids.size()==1,"solo start")
	var first:int=-1
	for entity in w.entities.values():
		if "first_companion_candidate" in entity.tags:first=entity.id;break
	check(first>0,"first companion generated")
	if first>0:
		check(Visitors._ration(w,first).is_empty(),"first companion needs food")
		check(w.entities[first].position.distance_to(w.entities[w.party_control_actor_id()].position)<=7,"first companion near entrance")
		var Action=preload("res://sim/party_action_command.gd")
		for x in range(6,9):
			var moved:Dictionary=s.commit_field_action(Action.move_to(w.party_control_actor_id(),Vector2i(x,24)))
			check(moved.get("accepted",false),"walk to recruit "+str(moved.get("reason","")))
		check(Visitors.assess(s,first).get("can_aid",false),"aid available after walking")
		var aided:=Visitors.interact(s,{"action":"AID","entity_id":str(first)})
		check(aided.get("accepted",false),"aid commits "+str(aided.get("reason","")))
		var joined:=Visitors.interact(s,{"action":"ACCEPT","entity_id":str(first)})
		check(joined.get("accepted",false),"recruit commits "+str(joined.get("reason","")))
		check(w.party_encounter.active_party_member_ids.size()==2,"explicit recruitment adds one companion")
		ui._refresh()
	check(ui.event_label.get_theme_font_size("font_size")==16,"product log font")
	for n in range(8):await process_frame
	check(ui.event_surface.size.y>=84,"three-line log budget")
	check(ui.grid.size.y>=200,"game viewport remains usable")
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.get("accepted",false),"new layout save replay "+str(loaded.get("reason","")))
	if loaded.get("accepted",false):check(restored.sim.snapshot()==s.sim.snapshot(),"recruitment replay exact snapshot")
	check(w.world_state_error().is_empty(),"world audit")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mobile-dungeon-readability.png")
		ui.hide()
		var gallery:=GridContainer.new();gallery.columns=4;gallery.position=Vector2(8,8);gallery.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;root.add_child(gallery)
		for entry in [["소검","WEAPON_SHORT_SWORD"],["단검","WEAPON_DCSS_DAGGER"],["철퇴","WEAPON_MACE"],["손도끼","WEAPON_HAND_AXE"],["창","WEAPON_SPEAR"],["활","WEAPON_BOW"],["쇠뇌","WEAPON_CROSSBOW"],["가죽 갑옷","ARMOR_LEATHER"],["판금 갑옷","ARMOR_PLATE"],["방패","SHIELD_WOOD"],["식량","FOOD_RATION"],["정수","ESSENCE_UNSPECIFIED"],["물약 1","MYSTERY_POTION_0"],["물약 2","MYSTERY_POTION_1"],["스크롤 1","MYSTERY_SCROLL_0"],["스크롤 2","MYSTERY_SCROLL_1"]]:
			var box:=VBoxContainer.new();gallery.add_child(box)
			var texture:=TextureRect.new();texture.custom_minimum_size=Vector2(88,88);texture.texture=ItemAssets.texture_for_id(entry[1]);texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;box.add_child(texture)
			var label:=Label.new();label.text=entry[0];label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_override("font",preload("res://assets/fonts/Galmuri14.ttf"));label.add_theme_font_size_override("font_size",14);box.add_child(label)
		for n in range(4):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/dcss-item-gallery.png")
		gallery.queue_free()
	ui.queue_free();await process_frame
	print("MOBILE DUNGEON READABILITY: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
