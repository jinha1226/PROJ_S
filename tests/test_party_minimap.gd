extends "res://tests/test_case.gd"

const Minimap=preload("res://playtest/party_minimap.gd")
const Session=preload("res://playtest/party_playtest_session.gd")

func test_sector_mapping_is_deterministic_and_specs_are_detached()->bool:
	var minimap=Minimap.new();minimap.set_observation(_observation(48,48,[
		_cell(0,0,"VISIBLE","stone_floor"),_cell(5,5,"VISIBLE","stone_floor"),
		_cell(6,6,"VISIBLE","stone_floor"),_cell(47,47,"VISIBLE","stone_floor")]))
	check_eq([minimap.world_to_sector(Vector2i(0,0)),minimap.world_to_sector(Vector2i(5,5)),
		minimap.world_to_sector(Vector2i(6,6)),minimap.world_to_sector(Vector2i(47,47))],
		[Vector2i(0,0),Vector2i(0,0),Vector2i(1,1),Vector2i(7,7)],
		"48x48 folds into deterministic 6x6 world sectors")
	var detached:=minimap.sector_draw_spec(Vector2i.ZERO);detached.glyph="X"
	check_eq(minimap.sector_draw_spec(Vector2i.ZERO).glyph,Minimap.GLYPH_MEMORY,
		"public sector specs are detached")
	minimap.free();return finish()

func test_sector_priority_is_hero_threat_exit_wall_memory_unknown()->bool:
	var rows:Array=[_cell(0,0,"VISIBLE","stone_floor"),_cell(1,0,"VISIBLE","wall"),
		_cell(2,0,"MEMORY","stone_floor","EXIT"),
		_cell(3,0,"VISIBLE","stone_floor","ENEMY"),
		_cell(4,0,"VISIBLE","stone_floor","HERO")]
	var minimap=Minimap.new();minimap.set_observation(_observation(48,48,rows))
	check_eq(minimap.sector_draw_spec(Vector2i.ZERO).role,"HERO","hero wins mixed sector")
	rows.pop_back();minimap.set_observation(_observation(48,48,rows))
	check_eq(minimap.sector_draw_spec(Vector2i.ZERO).role,"THREAT","threat follows hero")
	rows.pop_back();minimap.set_observation(_observation(48,48,rows))
	check_eq(minimap.sector_draw_spec(Vector2i.ZERO).role,"EXIT","exit follows threat")
	rows.pop_back();minimap.set_observation(_observation(48,48,rows))
	check_eq(minimap.sector_draw_spec(Vector2i.ZERO).role,"STRUCTURE","wall follows exit")
	rows.pop_back();minimap.set_observation(_observation(48,48,rows))
	check_eq(minimap.sector_draw_spec(Vector2i.ZERO).role,"PASSABLE","passable follows wall")
	check_eq(minimap.sector_draw_spec(Vector2i(7,7)).role,"UNKNOWN","unseen stays blank")
	var visibility_tie:=[_cell(0,0,"MEMORY","stone_floor"),
		_cell(1,0,"VISIBLE","stone_floor")]
	minimap.set_observation(_observation(48,48,visibility_tie))
	var forward:=minimap.sector_draw_spec(Vector2i.ZERO)
	visibility_tie.reverse();minimap.set_observation(_observation(48,48,visibility_tie))
	var reverse:=minimap.sector_draw_spec(Vector2i.ZERO)
	check_eq([forward.glyph,forward.color,forward.visibility_state],
		[reverse.glyph,reverse.color,reverse.visibility_state],"equal priority is row-order independent")
	minimap.free();return finish()

func test_memory_strips_live_markers_and_rich_payloads_without_leaking()->bool:
	var hidden:=_cell(12,12,"MEMORY","stone_floor","ENEMY")
	hidden["actors"]=[{"is_enemy":true,"target_id":99,"direction":[1,0]}]
	hidden["fire_intensity"]=90;hidden["target_id"]=99;hidden["direction"]=[1,0]
	var minimap=Minimap.new();minimap.set_observation(_observation(48,48,[hidden]))
	var spec:Dictionary=minimap.sector_draw_spec(minimap.world_to_sector(Vector2i(12,12)))
	check_eq([spec.glyph,spec.role],[Minimap.GLYPH_MEMORY,"PASSABLE"],
		"memory enemy becomes static passable ink")
	check(not bool(spec.leaks_actor) and not bool(spec.leaks_direction) \
		and not bool(spec.leaks_target) and not bool(spec.leaks_hazard),"no live fog data")
	var stored:Dictionary=minimap._cells["12:12"];var keys:Array=stored.keys();keys.sort()
	check_eq(keys,["marker","terrain_id","visibility_state"],"only compact scalars retained")
	check_eq(stored.marker,"","memory live marker discarded at ingestion")
	minimap.free();return finish()

func test_static_exit_survives_memory_but_actor_markers_require_visibility()->bool:
	var legacy_exit:=_cell(12,12,"MEMORY","stone_floor");legacy_exit["feature_id"]="run_exit_open"
	var minimap=Minimap.new();minimap.set_observation(_observation(48,48,[legacy_exit,
		_cell(24,24,"MEMORY","stone_floor","HERO")]))
	check_eq(minimap.sector_draw_spec(minimap.world_to_sector(Vector2i(12,12))).glyph,
		Minimap.GLYPH_EXIT,"discovered static exit remains mapped")
	check_eq(minimap.sector_draw_spec(minimap.world_to_sector(Vector2i(24,24))).glyph,
		Minimap.GLYPH_MEMORY,"remembered hero never remains live")
	minimap.free();return finish()

func test_glyph_color_and_renderer_contract_matches_dark_ascii_cartography()->bool:
	var minimap=Minimap.new();minimap.set_observation(_observation(48,48,[
		_cell(0,0,"VISIBLE","stone_floor","HERO"),
		_cell(6,0,"VISIBLE","stone_floor","ENEMY"),
		_cell(12,0,"MEMORY","stone_floor","EXIT"),
		_cell(18,0,"VISIBLE","wall"),_cell(24,0,"MEMORY","stone_floor")]))
	var expected:=[[Minimap.GLYPH_HERO,Minimap.HERO_COLOR],
		[Minimap.GLYPH_THREAT,Minimap.ENEMY_COLOR],[Minimap.GLYPH_EXIT,Minimap.EXIT_COLOR],
		[Minimap.GLYPH_WALL,Minimap.WALL_VISIBLE_COLOR],[Minimap.GLYPH_MEMORY,Minimap.MEMORY_COLOR]]
	for x in range(expected.size()):
		var spec:=minimap.sector_draw_spec(Vector2i(x,0))
		check_eq([spec.glyph,spec.color],expected[x],"semantic glyph/color %d"%x)
	var contract:=minimap.cartography_spec()
	check_eq([contract.columns,contract.rows,contract.primitive,contract.background],
		[8,8,"HANGUL_SECTOR_GLYPHS","BLACK_FIELD"],"square eight-sector cartography")
	check(not contract.uses_tile_rects and not contract.uses_circles and not contract.uses_images,
		"no colored tile rect, circle or image primitive")
	check_eq(contract.font_path,"res://assets/fonts/LivingWorldMonoKR.ttf","bundled font")
	var source:=FileAccess.get_file_as_string("res://playtest/party_minimap.gd")
	check("draw_circle" not in source and source.count("draw_rect(")==1 \
		and "draw_texture" not in source,"product source has one black field and glyphs only")
	minimap.free();return finish()

func test_legacy_rich_observation_still_maps_visible_actors()->bool:
	var hero:=_cell(7,7,"VISIBLE","floor")
	hero["actors"]=[{"is_protagonist":true,"is_enemy":false,"faction_id":"party"}]
	var enemy:=_cell(14,7,"VISIBLE","floor")
	enemy["actors"]=[{"is_protagonist":false,"is_enemy":true,"faction_id":"enemy"}]
	var minimap=Minimap.new();minimap.set_observation(_observation(15,15,[hero,enemy]))
	check_eq(minimap.cell_draw_spec(Vector2i(7,7)).marker,"HERO","legacy hero marker")
	check_eq(minimap.cell_draw_spec(Vector2i(14,7)).marker,"ENEMY","legacy enemy marker")
	check_eq(minimap.sector_draw_spec(minimap.world_to_sector(Vector2i(7,7))).role,
		"HERO","legacy hero reaches sector cache")
	minimap.free();return finish()

func test_product_compact_dto_publishes_only_discovered_static_exit()->bool:
	var session=Session.new(44,20260828,Session.SOLO_COMBAT_SCENARIO_ID)
	var progress:Dictionary=session.run_progress();var exit_value:Array=progress.exit_position
	var exit_position:=Vector2i(int(exit_value[0]),int(exit_value[1]))
	var before_snapshot:Dictionary=session.sim.snapshot()
	var before_journal:Array=session.command_journal.duplicate(true)
	var unseen_dto:Dictionary=session.observe_party_ui(15).minimap
	var unseen_row:=_row_at(unseen_dto.cells,exit_position)
	check(unseen_row.is_empty() or str(unseen_row.get("marker",""))!="EXIT",
		"never-seen product exit is not published")
	# Presentation-only explored origin makes the static exit known without
	# changing world authority or the canonical command journal.
	session._cache_explored_origin(exit_position)
	var discovered_dto:Dictionary=session.observe_party_ui(15).minimap
	var discovered_row:=_row_at(discovered_dto.cells,exit_position)
	check(not discovered_row.is_empty() and str(discovered_row.marker)=="EXIT" \
		and str(discovered_row.visibility_state) in ["VISIBLE","MEMORY"],
		"discovered product exit uses the compact static marker")
	var keys:Array=discovered_row.keys();keys.sort()
	check_eq(keys,["marker","position","terrain_id","visibility_state"],
		"exit row keeps the established scalar DTO")
	var minimap=Minimap.new();minimap.set_observation(discovered_dto)
	check_eq(minimap.sector_draw_spec(minimap.world_to_sector(exit_position)).glyph,
		Minimap.GLYPH_EXIT,"product DTO reaches the ASCII cartography")
	check_eq(session.sim.snapshot(),before_snapshot,"minimap discovery leaves authority unchanged")
	check_eq(session.command_journal,before_journal,"minimap discovery leaves journal unchanged")
	minimap.free();return finish()

func test_compact_allocations_are_crisp_clipped_and_idle()->bool:
	var minimap=Minimap.new();minimap.set_observation(_observation(48,48,[]))
	for allocation in [Vector2(52,50),Vector2(66,50)]:
		minimap.size=allocation
		var slot:=Vector2(allocation.x/8.0,allocation.y/8.0)
		var font_size:=minimap._font_size_for_slot(slot)
		check(font_size>=5 and Minimap.CodingFontBold.get_height(font_size)<=slot.y+0.01,
			"%s font fits sector height"%allocation)
	check(minimap.clip_contents and not bool(minimap.cartography_spec().per_frame_process),
		"clipped and no per-frame work")
	check_eq(minimap._sectors.size(),64,"cache remains exactly 64 sectors")
	minimap.free();return finish()

func _observation(width:int,height:int,cells:Array)->Dictionary:
	return {"width":width,"height":height,"cells":cells}

func _cell(x:int,y:int,state:String,terrain_id:String,marker:String="")->Dictionary:
	return {"position":[x,y],"visibility_state":state,"terrain_id":terrain_id,"marker":marker}

func _row_at(rows:Array,position:Vector2i)->Dictionary:
	for row in rows:
		if row is Dictionary and row.get("position",[])==[position.x,position.y]:return row
	return {}
