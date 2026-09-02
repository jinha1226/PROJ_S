extends "res://tests/test_case.gd"

const Overlay=preload("res://playtest/party_map_overlay.gd")

func test_full_map_preserves_coordinates_and_returns_detached_specs()->bool:
	var overlay=Overlay.new();overlay.set_observation(_observation(48,48,[
		_cell(0,0,"VISIBLE","wall"),_cell(47,47,"MEMORY","stone_floor")]))
	check_eq(overlay.cell_draw_spec(Vector2i.ZERO).glyph,"#","northwest exact wall")
	check_eq(overlay.cell_draw_spec(Vector2i(47,47)).glyph,".","southeast exact floor")
	check_eq(overlay.cell_draw_spec(Vector2i(24,24)).glyph,"","unknown remains blank")
	var detached:=overlay.cell_draw_spec(Vector2i.ZERO);detached.glyph="X"
	check_eq(overlay.cell_draw_spec(Vector2i.ZERO).glyph,"#","draw spec detached")
	var contract:=overlay.overlay_spec()
	check(contract.uses_world_coordinates and not contract.uses_sector_folding,
		"large overlay does not fold the dungeon into sectors")
	overlay.free();return finish()

func test_expanded_product_map_preserves_ninety_six_coordinate_edges()->bool:
	var overlay=Overlay.new();overlay.set_observation(_observation(96,96,[
		_cell(0,0,"VISIBLE","wall"),_cell(95,95,"MEMORY","stone_floor")]))
	check_eq(overlay.cell_draw_spec(Vector2i.ZERO).glyph,"#","96-map northwest wall")
	check_eq(overlay.cell_draw_spec(Vector2i(95,95)).glyph,".","96-map southeast floor")
	check_eq(overlay.cell_draw_spec(Vector2i(96,95)).glyph,"","96-map bounds stay exact")
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var layout:Dictionary=overlay.layout_spec(viewport_size)
		var slot:Vector2=layout.cell_size;var font_size:=int(layout.font_size)
		check_eq([layout.world_width,layout.world_height],[96,96],
			"%s expanded overlay dimensions"%viewport_size)
		check(Overlay.CodingFontBold.get_height(font_size)<=slot.y+0.01 \
			and Overlay.CodingFontBold.get_string_size("#",HORIZONTAL_ALIGNMENT_LEFT,
					-1,font_size).x<=slot.x+0.01,
			"%s 96-map glyphs fit their square cells"%viewport_size)
	overlay.free();return finish()

func test_priority_and_semantic_glyph_palette_contract()->bool:
	var overlay=Overlay.new();overlay.set_observation(_observation(48,48,[
		_cell(1,1,"VISIBLE","stone_floor","HERO"),
		_cell(2,1,"VISIBLE","stone_floor","ENEMY"),
		_cell(3,1,"MEMORY","stone_floor","EXIT"),
		_cell(4,1,"VISIBLE","wall"),_cell(5,1,"MEMORY","stone_floor")]))
	var expected:=[["@",Overlay.HERO_INK,"HERO"],["!",Overlay.THREAT_INK,"THREAT"],
		[">",Overlay.EXIT_INK,"EXIT"],["#",Overlay.WALL_VISIBLE_INK,"STRUCTURE"],
		[".",Overlay.MEMORY_INK,"PASSABLE"]]
	for index in range(expected.size()):
		var spec:=overlay.cell_draw_spec(Vector2i(index+1,1))
		check_eq([spec.glyph,spec.color,spec.role],expected[index],"semantic ink %d"%index)
	overlay.free();return finish()

func test_fog_ingestion_strips_live_memory_and_rich_payloads()->bool:
	var hidden_enemy:=_cell(8,8,"MEMORY","stone_floor","ENEMY")
	hidden_enemy.merge({"actors":[{"is_enemy":true}],"hazard":{"fire":99},
		"target_id":7,"direction":[1,0]})
	var unseen_exit:=_cell(9,8,"UNSEEN","stone_floor","EXIT")
	var known_exit:=_cell(10,8,"MEMORY","stone_floor","EXIT")
	var overlay=Overlay.new();overlay.set_observation(_observation(48,48,
		[hidden_enemy,unseen_exit,known_exit]))
	check_eq(overlay.cell_draw_spec(Vector2i(8,8)).glyph,".","memory enemy becomes terrain")
	check_eq(overlay.cell_draw_spec(Vector2i(9,8)).glyph,"","unseen exit omitted")
	check_eq(overlay.cell_draw_spec(Vector2i(10,8)).glyph,">","known static exit retained")
	var stored:Dictionary=overlay._cells["8:8"];var keys:Array=stored.keys();keys.sort()
	check_eq(keys,["marker","terrain_id","visibility_state"],"only compact scalars retained")
	check_eq(stored.marker,"","remembered actor marker stripped at ingestion")
	var contract:=overlay.overlay_spec()
	check(not contract.leaks_memory_actor and not contract.leaks_hazard \
		and not contract.leaks_target and not contract.leaks_direction,"fog leak contract")
	overlay.free();return finish()

func test_mobile_layouts_fit_and_keep_readable_square_world_cells()->bool:
	var overlay=Overlay.new();overlay.set_observation(_observation(48,48,[]))
	for viewport_size in [Vector2(360,640),Vector2(450,800)]:
		var layout:=overlay.layout_spec(viewport_size);var panel:Rect2=layout.panel_rect
		var map_rect:Rect2=layout.map_rect;var cell:Vector2=layout.cell_size
		check(panel.position.x>=0.0 and panel.position.y>=0.0 \
			and panel.end.x<=viewport_size.x and panel.end.y<=viewport_size.y,
			"%s panel stays on screen"%viewport_size)
		check(map_rect.position.x>=panel.position.x and map_rect.position.y>=panel.position.y \
			and map_rect.end.x<=panel.end.x and map_rect.end.y<=panel.end.y,
			"%s map stays inside folio"%viewport_size)
		check(absf(cell.x-cell.y)<0.01 and cell.x>=6.0,"%s square readable cells"%viewport_size)
		check(int(layout.font_size)>=5,"%s readable bundled font"%viewport_size)
	overlay.free();return finish()

func test_open_close_toggle_are_trigger_independent_and_signal_once()->bool:
	var overlay=Overlay.new();var opened_events:Array[String]=[];var reasons:Array[String]=[]
	overlay.opened.connect(func():opened_events.append("OPEN"))
	overlay.closed.connect(func(reason:String):reasons.append(reason))
	check(not overlay.visible,"overlay starts dormant")
	overlay.open();overlay.open()
	check(overlay.visible and opened_events.size()==1,"open is idempotent")
	overlay.toggle()
	check(not overlay.visible and reasons==["TOGGLE"],"second trigger closes")
	overlay.toggle()
	var back:=InputEventKey.new();back.keycode=KEY_ESCAPE;back.pressed=true
	overlay._unhandled_key_input(back)
	overlay.open();overlay.close("API");overlay.close("API")
	check_eq([opened_events.size(),reasons],[3,["TOGGLE","BACK","API"]],
		"back and API close each signal once")
	check(bool(overlay.overlay_spec().trigger_independent),"no trigger placement dependency")
	overlay.free();return finish()

func test_outside_press_closes_while_inside_press_only_consumes()->bool:
	var overlay=Overlay.new();overlay.size=Vector2(360,640);var reasons:Array[String]=[]
	overlay.closed.connect(func(reason:String):reasons.append(reason))
	var inside:=InputEventMouseButton.new();inside.button_index=MOUSE_BUTTON_LEFT
	inside.pressed=true;inside.position=overlay.layout_spec().panel_rect.get_center()
	overlay.open();overlay._gui_input(inside)
	check(overlay.visible,"inside panel press keeps folio open")
	var outside:=InputEventScreenTouch.new();outside.pressed=true;outside.position=Vector2(2,2)
	overlay._gui_input(outside)
	check(not overlay.visible and reasons==["OUTSIDE"],"outside touch dismisses")
	overlay.free();return finish()

func test_renderer_is_idle_font_only_dark_fantasy_ascii()->bool:
	var overlay=Overlay.new();var contract:=overlay.overlay_spec()
	check_eq(contract.primitive,"FULL_ASCII_CARTOGRAPHY","full-map ASCII primitive")
	check_eq(contract.visual_family,"DARK_FANTASY_IRON_FOLIO","dark-fantasy family")
	check_eq(contract.font_path,"res://assets/fonts/LivingWorldMonoKR.ttf","Korean mono font")
	check(not contract.uses_images and not contract.uses_textures and not contract.per_frame_process,
		"no image/texture/per-frame renderer")
	var source:=FileAccess.get_file_as_string("res://playtest/party_map_overlay.gd")
	check("draw_texture" not in source and "TextureRect" not in source \
		and "ImageTexture" not in source and "func _process(" not in source,
		"product source remains idle code-drawn typography")
	overlay.free();return finish()

func _observation(width:int,height:int,cells:Array)->Dictionary:
	return {"width":width,"height":height,"cells":cells}

func _cell(x:int,y:int,state:String,terrain_id:String,marker:String="")->Dictionary:
	return {"position":[x,y],"visibility_state":state,"terrain_id":terrain_id,"marker":marker}
