extends "res://tests/test_case.gd"

const Grid=preload("res://playtest/party_grid_view.gd")
const Overlay=preload("res://playtest/melee_vfx_overlay.gd")


func test_melee_vfx_right_is_target_local_broken_slash_and_holds_local_clock()->bool:
	var fixture:=_fixture(Vector2i.RIGHT);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	var time_scale_before:=Engine.time_scale
	var actors_before:=grid._actors.duplicate(true)
	var hero_before:=grid.actor_draw_spec(grid._actors[0])
	var target_before:=grid.actor_draw_spec(grid._actors[1])
	check(overlay.play(Vector2i(7,7),Vector2i(8,7)),"right melee VFX starts")
	var started:=int(overlay.active_effects()[0].started_at_ms)
	var params:=overlay.parameter_spec()
	var contact:=started+int(params.contact_at_ms)
	var hold_a:Dictionary=overlay.effect_draw_specs(contact)[0]
	var hold_b:Dictionary=overlay.effect_draw_specs(contact+int(params.hit_stop_ms)-1)[0]
	check_eq([hold_a.primitive,hold_a.slash_glyph,hold_a.draw_connector],
		["BROKEN_SLASH","",false],
		"slash is target-local Node2D feedback and owns no connector or ASCII glyph")
	check(hold_a.hit_stop_active and hold_b.hit_stop_active \
		and hold_a.visual_elapsed_ms==hold_b.visual_elapsed_ms,
		"only the overlay visual clock is clamped at contact")
	check(int(params.hit_stop_ms)>=40 and int(params.hit_stop_ms)<=70,
		"local hit stop stays in the requested window")
	check(Vector2(hold_a.line_to).x>Vector2(hold_a.line_from).x,
		"right strike line follows the mapped target direction")
	_check_target_local_broken_slash(grid,hold_a,Vector2i(7,7),Vector2i(8,7),
		"right")
	check(params.has("slash_local_length_ratio") and params.has("slash_bend_ratio") \
		and not params.has("slash_span_ratio"),
		"target-local slash length and bend are independently adjustable")
	check(is_equal_approx(float(params.slash_width_px),1.0) \
			and not bool(params.slash_antialiased),
		"target-cell slash is an exact one-pixel terminal stroke at every map scale")
	check_eq([grid._actors,grid.actor_draw_spec(grid._actors[0]).glyph,
		grid.actor_draw_spec(grid._actors[1]).glyph,Engine.time_scale],
		[actors_before,hero_before.glyph,target_before.glyph,time_scale_before],
		"VFX changes neither logical actors, glyphs, nor Engine time")
	grid.free();return finish()


func test_melee_vfx_left_uses_only_bounded_dot_colon_star_particles()->bool:
	var fixture:=_fixture(Vector2i.LEFT);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	check(overlay.play(Vector2i(7,7),Vector2i(6,7)),"left melee VFX starts")
	var effect:=overlay.active_effects()[0];var params:=overlay.parameter_spec()
	var sample_time:=int(effect.started_at_ms)+int(params.contact_at_ms) \
		+int(params.hit_stop_ms)+24
	var spec:Dictionary=overlay.effect_draw_specs(sample_time)[0]
	check(Vector2(spec.line_to).x<Vector2(spec.line_from).x,
		"left strike reverses the mapped line")
	_check_target_local_broken_slash(grid,spec,Vector2i(7,7),Vector2i(6,7),
		"left")
	check(spec.particle_count>=3 and spec.particle_count<=6,
		"impact emits three to six particles")
	check(spec.particles.all(func(row):return str(row.glyph) in [".",":","*"]),
		"particles use only the requested visual glyph alphabet")
	check(int(params.particle_visible_total_ms)>=390 \
			and int(params.particle_visible_total_ms)<=430,
		"debris readable lifetime stays in the requested window")
	grid.free();return finish()


func test_melee_vfx_up_flashes_only_exact_target_background()->bool:
	var fixture:=_fixture(Vector2i.UP);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	var target_actor:=grid._actors[1].duplicate(true)
	var target_style:=grid.actor_draw_spec(grid._actors[1])
	check(overlay.play(Vector2i(7,7),Vector2i(7,6)),"up melee VFX starts")
	var effect:=overlay.active_effects()[0];var params:=overlay.parameter_spec()
	var sample_time:=int(effect.started_at_ms)+int(params.contact_at_ms)
	var flashes:=overlay.background_flash_specs(sample_time)
	check_eq(flashes.size(),1,"one target owns one background flash")
	check_eq([flashes[0].target_grid_pos,flashes[0].rect],
		[Vector2i(7,6),grid.world_cell_rect(Vector2i(7,6))],
		"flash uses the exact target cell rect from PartyGridView")
	var slash_spec:Dictionary=overlay.effect_draw_specs(sample_time)[0]
	check(Vector2(slash_spec.line_to).y<Vector2(slash_spec.line_from).y,
		"up strike line follows the mapped target direction")
	_check_target_local_broken_slash(grid,slash_spec,Vector2i(7,7),Vector2i(7,6),
		"up")
	check_eq([grid._actors[1],grid.actor_draw_spec(grid._actors[1]).glyph,
		grid.actor_draw_spec(grid._actors[1]).color_hex],
		[target_actor,target_style.glyph,target_style.color_hex],
		"background flash never changes target glyph, color, or position")
	grid.free();return finish()


func test_melee_vfx_down_shake_is_visual_capped_and_mapping_neutral()->bool:
	var fixture:=_fixture(Vector2i.DOWN);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	var mapping:=grid.mapping_signature();var time_scale_before:=Engine.time_scale
	check(overlay.play(Vector2i(7,7),Vector2i(7,8)),"down melee VFX starts")
	var effect:=overlay.active_effects()[0];var params:=overlay.parameter_spec()
	var started:=int(effect.started_at_ms);var contact:=int(params.contact_at_ms)
	var shake:=overlay.shake_offset_px(started+contact+10)
	var slash_spec:Dictionary=overlay.effect_draw_specs(started)[0]
	check(Vector2(slash_spec.line_to).y>Vector2(slash_spec.line_from).y,
		"down strike line follows the mapped target direction")
	_check_target_local_broken_slash(grid,slash_spec,Vector2i(7,7),Vector2i(7,8),
		"down")
	check(shake.length()>0.0 and shake.length()<=2.0 \
		and float(params.shake_strength_px)>=1.0 and float(params.shake_strength_px)<=2.0,
		"screen shake remains a one-to-two pixel visual offset")
	check(int(params.shake_duration_ms)>=50 and int(params.shake_duration_ms)<=100 \
		and overlay.shake_offset_px(started+contact+int(params.shake_duration_ms))==Vector2.ZERO,
		"shake ends inside the requested duration")
	check_eq([grid.mapping_signature(),grid.pixel_to_world_cell(
		grid.world_to_pixel_center(Vector2i(7,8))),Engine.time_scale],
		[mapping,Vector2i(7,8),time_scale_before],
		"shake changes neither hit mapping nor global time")
	grid.free();return finish()


func test_melee_vfx_rapid_consecutive_effects_are_independent_and_bounded()->bool:
	var fixture:=_fixture(Vector2i.RIGHT);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	check(overlay.play(Vector2i(7,7),Vector2i(8,7)) \
		and overlay.play(Vector2i(7,7),Vector2i(6,7)),
		"rapid consecutive hits both start")
	check_eq(overlay.active_effect_count(),2,"rapid hits are not coalesced")
	var effects:=overlay.active_effects();var params:=overlay.parameter_spec()
	var sample:=maxi(int(effects[0].started_at_ms),int(effects[1].started_at_ms)) \
		+int(params.contact_at_ms)
	var specs:=overlay.effect_draw_specs(sample)
	check_eq([specs[0].target_grid_pos,specs[1].target_grid_pos],
		[Vector2i(8,7),Vector2i(6,7)],"rapid hits preserve independent targets")
	check(overlay.shake_offset_px(sample).length()<=2.0,
		"combined rapid shake is capped instead of summed")
	for effect in overlay._effects:
		effect.first_drawn=true;effect.live_elapsed_ms=int(params.effect_duration_ms)
	overlay._process(0.0)
	check(overlay.active_effect_count()==0 and not overlay.is_processing(),
		"overlay disables processing after the last bounded effect")
	grid.free();return finish()


func test_melee_vfx_live_clock_waits_for_first_draw_and_caps_slow_frames()->bool:
	var fixture:=_fixture(Vector2i.RIGHT);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	check(overlay.play(Vector2i(7,7),Vector2i(8,7)),"live-clock melee starts")
	var params:=overlay.parameter_spec()
	overlay._process(1.0)
	var before_draw:=overlay.active_effects()[0]
	check(overlay.active_effect_count()==1 and not bool(before_draw.first_drawn) \
		and float(before_draw.live_elapsed_ms)==0.0,
		"one-second pre-draw stall cannot consume the first visible VFX frame")
	overlay._effects[0].first_drawn=true
	overlay._process(1.0)
	var after_slow_frame:=overlay.active_effects()[0]
	check(float(after_slow_frame.live_elapsed_ms)<=float(params.max_live_frame_advance_ms) \
		and overlay.active_effect_count()==1,
		"slow rendered frame advances only the configured bounded local clock")
	var first_spec:=overlay.effect_draw_specs()[0]
	check(not bool(first_spec.line_visible) and not bool(first_spec.flash_visible) \
		and int(first_spec.particle_count)==0,
		"first bounded live frame preserves the readable attacker wind-up")
	overlay._effects[0].live_elapsed_ms=int(params.contact_at_ms)
	var contact_spec:=overlay.effect_draw_specs()[0]
	check(bool(contact_spec.line_visible) and bool(contact_spec.flash_visible) \
		and int(contact_spec.particle_count)>=3 and overlay.shake_offset_px().length()>0.0,
		"slash, flash, debris, and subtle shake synchronize at arm contact")
	grid.free();return finish()


func test_melee_vfx_readable_hold_fade_and_bidirectional_last_visible_bounds()->bool:
	var fixture:=_fixture(Vector2i.RIGHT);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	check(overlay.play(Vector2i(7,7),Vector2i(8,7)) \
		and overlay.play(Vector2i(8,7),Vector2i(7,7)),
		"hero hit and enemy counter-hit both start as independent product pairs")
	var effects:=overlay.active_effects();var params:=overlay.parameter_spec()
	check_eq([effects[0].attacker_grid_pos,effects[0].target_grid_pos,
		effects[1].attacker_grid_pos,effects[1].target_grid_pos],
		[Vector2i(7,7),Vector2i(8,7),Vector2i(8,7),Vector2i(7,7)],
		"opposing attacks preserve canonical attacker and target direction")
	check(int(params.slash_visible_total_ms)>=250 and int(params.slash_visible_total_ms)<=280 \
		and int(params.flash_visible_total_ms)>=190 and int(params.flash_visible_total_ms)<=215 \
		and int(params.particle_visible_total_ms)>=390 and int(params.particle_visible_total_ms)<=430,
		"central parameters expose the requested slash, flash, and debris totals")
	var started:=int(effects[0].started_at_ms)
	var hold_last:=_effect_sequence_spec(overlay,
		started+int(params.hit_stop_ms)-1,int(effects[0].sequence))
	var slash_last:=_effect_sequence_spec(overlay,
		started+int(params.slash_visible_total_ms)-1,int(effects[0].sequence))
	var slash_after:=_effect_sequence_spec(overlay,
		started+int(params.slash_visible_total_ms),int(effects[0].sequence))
	var flash_last:=_effect_sequence_spec(overlay,
		started+int(params.flash_visible_total_ms)-1,int(effects[0].sequence))
	var flash_after:=_effect_sequence_spec(overlay,
		started+int(params.flash_visible_total_ms),int(effects[0].sequence))
	var debris_last:=_effect_sequence_spec(overlay,
		started+int(params.particle_visible_total_ms)-1,int(effects[0].sequence))
	var every_effect_clears_at_own_bound:=true
	for effect in effects:
		var own_end:=int(effect.started_at_ms)+int(params.effect_duration_ms)
		every_effect_clears_at_own_bound=every_effect_clears_at_own_bound \
			and _effect_sequence_spec(overlay,own_end,int(effect.sequence)).is_empty()
	check(bool(hold_last.hit_stop_active) and float(hold_last.line_opacity)==1.0,
		"slash owns a brief fully bright hold before fading")
	check(bool(slash_last.line_visible) \
			and float(slash_last.line_opacity)>=float(params.slash_afterimage_opacity) \
			and not bool(slash_after.line_visible),
		"slash afterimage remains readable through its last bounded millisecond")
	check(bool(flash_last.flash_visible) and not bool(flash_after.flash_visible),
		"cell flash ends exactly at its configured readable bound")
	check(int(debris_last.particle_count)>=3 and every_effect_clears_at_own_bound,
		"debris persists to the final effect frame and then clears")
	grid.free();return finish()


func test_melee_vfx_empty_direction_produces_no_effect()->bool:
	var fixture:=_fixture(Vector2i.RIGHT);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	check(not overlay.play(Vector2i(7,7),Vector2i(7,7)),
		"empty attack direction is rejected")
	check(not overlay.play(Vector2i(7,7),Vector2i(9,7)),
		"non-melee distance cannot invent a slash")
	check(overlay.active_effect_count()==0 and overlay.effect_draw_specs().is_empty() \
		and not overlay.is_processing(),"invalid pair produces no draw or process work")
	grid.free();return finish()


func test_melee_vfx_multiple_adjacent_actors_selects_passed_target_only()->bool:
	var grid:=Grid.new();grid.size=Vector2(345,345)
	var cells:=_visible_cells()
	var positions:=[Vector2i(7,7),Vector2i(8,7),Vector2i(6,7),Vector2i(7,6),Vector2i(7,8)]
	for index in range(positions.size()):
		for cell in cells:
			if cell.position==[positions[index].x,positions[index].y]:
				cell.actors.append({"entity_id":index+1,"faction_id":"party" if index==0 else "enemy",
					"species_id":"human" if index==0 else "goblin",
					"roster_slot":0 if index==0 else -1,"is_protagonist":index==0})
	grid.set_observation({"width":15,"height":15,"cells":cells});grid._ensure_melee_vfx()
	var mapping:=grid.mapping_signature();var actors:=grid._actors.duplicate(true)
	check(grid.melee_vfx.play(Vector2i(7,7),Vector2i(7,6)),
		"explicit upper target starts amid four adjacent actors")
	var effect:=grid.melee_vfx.active_effects()[0];var params:=grid.melee_vfx.parameter_spec()
	var sample:=int(effect.started_at_ms)+int(params.contact_at_ms)
	var specs:=grid.melee_vfx.effect_draw_specs(sample)
	var flashes:=grid.melee_vfx.background_flash_specs(sample)
	check_eq([specs[0].target_grid_pos,flashes[0].target_grid_pos,flashes[0].rect],
		[Vector2i(7,6),Vector2i(7,6),grid.world_cell_rect(Vector2i(7,6))],
		"VFX uses the passed pair and never searches adjacent occupants")
	check_eq([grid._actors,grid.mapping_signature()],[actors,mapping],
		"multi-target presentation leaves actors and mapping untouched")
	grid.free();return finish()


func test_attacker_weapon_swing_is_tile_local_and_8_direction_safe()->bool:
	for direction in [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),
			Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]:
		var fixture:=_fixture(direction);var grid:PartyGridView=fixture.grid
		var overlay:MeleeVfxOverlay=grid.melee_vfx
		var mapping:=grid.mapping_signature();var hit:=grid.actor_hit_rect(1)
		check(overlay.play(Vector2i(7,7),Vector2i(7,7)+direction),
			"%s swing starts"%direction)
		var effect:=overlay.active_effects()[0];var params:=overlay.parameter_spec()
		var started:=int(effect.started_at_ms)
		var windup:Dictionary=grid.actor_glyph_draw_spec(1,started+int(params.contact_at_ms)-1)
		var contact:Dictionary=grid.actor_glyph_draw_spec(1,started+int(params.contact_at_ms)+24)
		var settled:Dictionary=grid.actor_glyph_draw_spec(1,started+int(params.swing_duration_ms))
		var swing:Dictionary=contact.weapon_swing
		check(str(windup.weapon_swing.phase)=="WIND_UP" and str(swing.phase)=="SWING" \
				and not bool(settled.weapon_swing.active),
			"%s owns wind-up, swing, and bounded settle"%direction)
		check(contact.limb_segments.is_empty() and windup.limb_segments.is_empty() \
				and settled.limb_segments.is_empty(),
			"%s swing never recreates artificial arms or legs"%direction)
		check_eq([str(windup.glyph),str(contact.glyph),str(settled.glyph)],
			["@","@","@"],"%s swing never replaces the actor glyph"%direction)
		var weapon_travel:=Vector2(contact.equipment.weapon_center).distance_to(
			Vector2(windup.equipment.weapon_center))
		check(contact.equipment.weapon_swing_active and weapon_travel>=1.0 \
				and Rect2(contact.cell_rect).has_point(Vector2(contact.equipment.weapon_center)),
			"%s equipped weapon owns a visible tile-local attack arc (%s px)"%[direction,weapon_travel])
		check_eq([grid.mapping_signature(),grid.actor_hit_rect(1),
			grid.actor_in_world_cell(Vector2i(7,7))],[mapping,hit,1],
			"%s weapon animation is mapping and authority neutral"%direction)
		grid.free()
	return finish()


func test_attacker_swing_overlap_miss_fov_and_life_state_are_safe()->bool:
	var fixture:=_fixture(Vector2i.RIGHT);var grid:PartyGridView=fixture.grid
	var overlay:MeleeVfxOverlay=grid.melee_vfx
	check(overlay.play(Vector2i(7,7),Vector2i(8,7)) \
		and overlay.play(Vector2i(7,7),Vector2i(7,6)),
		"rapid swings coexist without replacing impact effects")
	var newest:=overlay.attacker_swing_draw_spec(Vector2i(7,7),
		int(overlay.active_effects()[1].started_at_ms)+20)
	check_eq([overlay.active_effect_count(),Vector2(newest.direction)],
		[2,Vector2.UP],"latest same-attacker pose wins without coalescing effects")
	grid.melee_vfx.clear()
	check_eq(grid.play_effects([{"effect_id":"miss-arm","event_id":90,"kind":"MISS",
		"actor_id":1,"target_id":2,"world_position":[8,7]}]),1,
		"canonical miss row remains playable")
	var miss_effect:=overlay.active_effects()[0]
	check(not bool(miss_effect.draw_impact) and bool(overlay.attacker_swing_draw_spec(
		Vector2i(7,7),int(miss_effect.started_at_ms)+20).active),
		"miss animates the equipped weapon without inventing target impact")
	grid.melee_vfx.clear()
	check_eq(grid.play_effects([{"effect_id":"historical-miss-arm","event_id":91,
		"kind":"MISS","actor_id":-1,"target_id":2,"attacker_grid_pos":[7,7],
		"target_grid_pos":[8,7],"world_position":[8,7]}]),1,
		"product miss result leaf uses its canonical historical position pair")
	check(not bool(overlay.active_effects()[0].draw_impact) and bool(
		overlay.attacker_swing_draw_spec(Vector2i(7,7),
		int(overlay.active_effects()[0].started_at_ms)+20).active),
		"historical MISS animates even though the result leaf owns no actor id")
	grid._actors[0]["life_state"]="DOWNED"
	check(not bool(grid.actor_draw_spec(grid._actors[0],false,
		int(miss_effect.started_at_ms)+20).get("weapon_swing",{}).get("active",false)),
		"downed attacker cannot display a standing swing")
	grid.free()

	var hidden_fixture:=_fixture(Vector2i.RIGHT);var hidden_grid:PartyGridView=hidden_fixture.grid
	var hidden_cells:=_visible_cells()
	for cell in hidden_cells:
		if cell.position==[7,7]:
			cell.visibility_state="UNSEEN";cell.actors.append({"entity_id":1,
				"faction_id":"party","species_id":"human","is_protagonist":true})
		elif cell.position==[8,7]:cell.actors.append({"entity_id":2,
			"faction_id":"enemy","species_id":"goblin"})
	hidden_grid.set_observation({"width":15,"height":15,"cells":hidden_cells})
	check(not hidden_grid.melee_vfx.play(Vector2i(7,7),Vector2i(8,7)) \
		and hidden_grid.melee_vfx.active_effect_count()==0,
		"unseen attacker cannot leak through arm or impact animation")
	hidden_grid.free();return finish()


func _fixture(direction:Vector2i)->Dictionary:
	var grid:=Grid.new();grid.size=Vector2(345,345)
	var cells:=_visible_cells();var target:=Vector2i(7,7)+direction
	for cell in cells:
		if cell.position==[7,7]:
			cell.actors.append({"entity_id":1,"faction_id":"party","species_id":"human",
				"roster_slot":0,"is_protagonist":true,"equipment_visual":{
					"weapon_id":"SHORT_SWORD","armor_definition_id":""}})
		elif cell.position==[target.x,target.y]:
			cell.actors.append({"entity_id":2,"faction_id":"enemy","species_id":"goblin"})
	grid.set_observation({"width":15,"height":15,"cells":cells})
	grid._ensure_melee_vfx()
	return {"grid":grid}


func _check_target_local_broken_slash(grid:PartyGridView,spec:Dictionary,
		attacker:Vector2i,target:Vector2i,label:String)->void:
	var line_from:=Vector2(spec.line_from)
	var line_to:=Vector2(spec.line_to)
	var attacker_rect:=grid.world_cell_rect(attacker)
	var target_rect:=grid.world_cell_rect(target)
	check(not bool(spec.get("draw_connector",true)) and not bool(spec.get(
		"spans_actor_centers",true)) and spec.slash_segments.size()==2,
		"%s slash declares two local strokes and no connector"%label)
	check(target_rect.has_point(line_from) and target_rect.has_point(line_to) \
		and spec.slash_segments.all(func(segment):return target_rect.has_point(
			Vector2(segment.from)) and target_rect.has_point(Vector2(segment.to))),
		"%s every slash endpoint stays inside the target cell"%label)
	check(not attacker_rect.has_point(line_from) and not attacker_rect.has_point(line_to),
		"%s slash never reaches into the attacker cell"%label)

func _effect_sequence_spec(overlay:MeleeVfxOverlay,sample_time_ms:int,
		sequence:int)->Dictionary:
	for spec in overlay.effect_draw_specs(sample_time_ms):
		if int(spec.sequence)==sequence:return spec
	return {}


func _visible_cells()->Array:
	var cells:Array=[]
	for y in range(15):
		for x in range(15):
			cells.append({"position":[x,y],"terrain_id":"floor",
				"visibility_state":"VISIBLE","actors":[]})
	return cells
