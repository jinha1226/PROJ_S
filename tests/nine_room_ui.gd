extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.sim!=null,"product init")
	if s.sim==null:quit(1);return
	var ui=Sandbox.new();ui.size=Vector2(390,844);ui.initialize_for_headless_test(s,true)
	root.add_child(ui);ui.set_process(false);ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for viewport_size in [Vector2i(360,800),Vector2i(390,844)]:
		root.content_scale_size=viewport_size
		root.size=viewport_size;ui.size=Vector2(viewport_size);ui._request_refresh()
		for i in range(4):await process_frame
		check(ui.grid.visible_cell_count==8 and ui.grid.visible_row_count==8,"8x8 board "+str(viewport_size))
		var origin:=Vector2i(s.room_status().bounds[0],s.room_status().bounds[1])
		for y in range(8):
			for x in range(8):
				var p:=origin+Vector2i(x,y);var center:Vector2=ui.grid.world_to_pixel_center(p)
				check(Rect2(Vector2.ZERO,ui.grid.size).has_point(center),"all 64 centers inside")
				check(ui.grid.pixel_to_world_cell(center)==p,"touch projection roundtrip")
		var buttons:Array=[ui.product_wait_guard_button,ui.product_attack_button,ui.product_auto_button,ui.product_bag_button,ui.product_rest_button]
		for button in buttons:
			check(button.is_visible_in_tree(),"primary visible "+button.name)
			var r:Rect2=button.get_global_rect();check(r.position.x>=0 and r.end.x<=viewport_size.x+1 and r.end.y<=viewport_size.y+1,"primary fits "+button.name)
		ui._toggle_map_overlay();await process_frame
		check(ui.map_overlay._room_map.rooms.size()==1,"full map uses discovered rooms")
		ui._toggle_map_overlay()
		check(not ui.product_pickup_button.visible and not ui.product_tactics_button.visible and not ui.product_interact_button.visible,"five actions only")
		check(ui.product_wait_guard_button.text=="[이동]" and ui.product_auto_button.text=="[변이]","primary labels")
		var before:int=s.sim.world.world_time;ui._on_product_wait_guard();check(s.sim.world.world_time==before,"move selection costs no time")
	var w=s.sim.world;var hero:int=w.party_encounter.protagonist_id;var old:Vector2i=w.entities[hero].position
	w.entities[hero].position=Vector2i(11,14);w.reindex_entity_occupancy(hero,old,w.entities[hero].position);w.party_encounter.group_anchor=w.entities[hero].position
	check(s.request_room_exit(hero,"F1_R4_R7",int(w.party_encounter.nine_room_floor.revision)).accepted,"UI combat entry")
	ui._request_refresh()
	for i in range(4):await process_frame
	check(s.round_active(),"UI combat active")
	var room:Dictionary=s.room_status()
	check(ui.grid._room_biome==room.biome,"current room biome reaches grid DTO")
	check(ui.grid._tactical_terrain!=null,"product uses retained tactical terrain")
	if ui.grid._tactical_terrain!=null:
		check(ui.grid._tactical_terrain.biome==preload("res://playtest/handcrafted_tile_assets.gd").biome_index(room.biome),"current room biome reaches art renderer")
	check(ui.round_order_bar.global_position.y<ui.grid.global_position.y,"round order above board")
	for button in [ui.product_wait_guard_button,ui.product_attack_button,ui.product_auto_button,ui.product_bag_button,ui.product_rest_button]:
		var r:Rect2=button.get_global_rect();check(button.is_visible_in_tree() and r.end.y<=ui.size.y+1,"combat primary fits "+button.name+str(r))
	check(not ui.battle_enemy_strip.visible,"combat duplicate enemy strip hidden")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/handcrafted64-game.png")==OK,"runtime screenshot")
	ui.queue_free();await process_frame
	print("NINE_ROOM_UI ","PASS" if failures.is_empty() else failures);quit(0 if failures.is_empty() else 1)
