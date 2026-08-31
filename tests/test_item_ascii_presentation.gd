extends "res://tests/test_case.gd"

const Style=preload("res://playtest/ascii_visual_style.gd")
const Grid=preload("res://playtest/party_grid_view.gd")
const Mono:FontFile=preload("res://assets/fonts/LivingWorldMonoKR.ttf")
const MonoBold:FontFile=preload("res://assets/fonts/LivingWorldMonoKRBold.ttf")


func test_item_glyph_palette_and_bundled_font_contract()->bool:
	var expected:={"WEAPON":")","ARMOR":"[","POTION":"!","SCROLL":"?",
		"ACCESSORY":"=","MATERIAL":"*"}
	var colors:Array[String]=[]
	for kind in expected:
		var spec:Dictionary=Style.item_presentation_spec(kind)
		check(spec.visible and spec.glyph==expected[kind],"%s owns approved item glyph"%kind)
		check(not spec.draw_image and not spec.draw_texture and spec.ink_family=="RELIC",
			"%s remains code-drawn dark-fantasy ink"%kind)
		check(Color(str(spec.color_hex)).get_luminance()>
			Color(str(spec.underlay_hex)).get_luminance()+0.12,
			"%s glyph separates from its local dark underlay"%kind)
		colors.append(str(spec.color_hex))
	check_eq(colors.duplicate().reduce(func(unique:Array,value:String):
		if value not in unique:unique.append(value)
		return unique,[]).size(),expected.size(),"item roles have restrained distinct inks")
	check_eq(Style.item_presentation_spec({"category":"WEAPON"}).glyph,")",
		"presentation category resolves without item authority")
	check_eq(Style.item_presentation_spec({"use_kind":"SCROLL"}).glyph,"?",
		"consumable subtype resolves without item identity")
	check(not Style.item_presentation_spec("%").visible,"unapproved glyph is never rendered")
	var glyphs:=[")","[","!","?","=","*","»","~","<"]
	for font in [Mono,MonoBold]:
		for glyph in glyphs:
			check(font.has_char(glyph.unicode_at(0)),
				"bundled %s supports '%s'"%[font.resource_path.get_file(),glyph])
	return finish()


func test_ground_items_draw_visible_after_features_before_actors_and_preserve_mapping()->bool:
	var visible_weapon:={"position":[23,24],"terrain_id":"floor",
		"visibility_state":"VISIBLE","ground_item_glyph":")","actors":[]}
	var occupied_potion:={"position":[24,24],"terrain_id":"floor",
		"visibility_state":"VISIBLE","ground_items":[{"presentation_kind":"POTION",
			"instance_id":"MUST_NOT_ENTER_GRID"}],"actors":[{"entity_id":77,
			"is_protagonist":true,"faction_id":"party","position":[24,24]}]}
	var observation:={"width":48,"height":48,"cells":[visible_weapon,occupied_potion]}
	var grid=Grid.new();grid.size=Vector2(360,360)
	grid.set_observation(observation);grid.set_hero_centered_view(Vector2i(24,24),15,77)
	var mapping:=grid.mapping_signature();var actor_hit:=grid.actor_hit_rect(77)
	var weapon:=grid.ground_item_draw_spec(Vector2i(23,24))
	var potion:=grid.ground_item_draw_spec(Vector2i(24,24))
	check(weapon.visible and weapon.glyph==")" and not weapon.occupied_corner,
		"unoccupied item uses its full cell-center ASCII glyph")
	check(potion.visible and potion.glyph=="!" and potion.occupied_corner,
		"actor-occupied item becomes a small corner mark")
	for spec in [weapon,potion]:
		check(Rect2(spec.cell_rect).encloses(Rect2(spec.text_rect)),
			"item ink remains inside its logical cell")
		check_eq([spec.draw_after,spec.draw_before],
			[["GROUND_FEATURES","GROUND_HAZARDS"],["ACTORS"]],
			"item layer sits behind actors and above ground cues")
		check(not spec.changes_hit_rect and spec.mouse_filter=="IGNORE" \
			and not spec.draw_image and spec.texture_free,
			"item creates no input surface, image, or texture")
	check_eq([grid.mapping_signature(),grid.actor_hit_rect(77)],[mapping,actor_hit],
		"item projection preserves world-pixel mapping and actor hit authority")
	# The observation array remains caller-owned; mutating it cannot inject a new
	# glyph because the grid retained only the approved detached scalar.
	occupied_potion.ground_items[0].presentation_kind="SCROLL"
	occupied_potion.ground_items[0].instance_id="LEAKED"
	check_eq(grid.ground_item_draw_spec(Vector2i(24,24)).glyph,"!",
		"grid item presentation is detached from caller aliases")
	check(not grid._cells["24:24"].has("ground_items") \
		and not grid._cells["24:24"].has("instance_id"),
		"item authority and identity never enter the grid cache")
	grid.free();return finish()


func test_memory_unseen_offscreen_and_unknown_items_emit_no_marker_or_payload()->bool:
	var cells:=[
		{"position":[24,24],"terrain_id":"floor","visibility_state":"VISIBLE",
			"ground_item_glyph":"=","actors":[]},
		{"position":[23,24],"terrain_id":"floor","visibility_state":"MEMORY",
			"ground_items":[{"presentation_kind":"WEAPON","instance_id":"SECRET_A"}],"actors":[]},
		{"position":[25,24],"terrain_id":"floor","visibility_state":"UNSEEN",
			"ground_item_glyph":"!","actors":[]},
		{"position":[24,23],"terrain_id":"floor","visibility_state":"VISIBLE",
			"ground_item_glyph":"%","actors":[]},
		{"position":[40,40],"terrain_id":"floor","visibility_state":"VISIBLE",
			"ground_item_glyph":"*","actors":[]},
	]
	var grid=Grid.new();grid.size=Vector2(450,450)
	grid.set_observation({"width":48,"height":48,"cells":cells})
	grid.set_hero_centered_view(Vector2i(24,24),15)
	check(grid.ground_item_draw_spec(Vector2i(24,24)).visible,"visible accessory renders")
	for position in [Vector2i(23,24),Vector2i(25,24),Vector2i(24,23),Vector2i(40,40)]:
		var spec:=grid.ground_item_draw_spec(position)
		check(not spec.visible and spec.glyph.is_empty(),
			"hidden/offscreen/unapproved %s emits no item marker"%position)
	check_eq(grid.ground_item_draw_specs().size(),1,
		"only the one approved visible in-viewport item reaches the draw pass")
	check_eq([grid._cells["23:24"].ground_item_glyph,
		grid._cells["25:24"].ground_item_glyph],["",""],
		"memory and unseen item presence is erased at ingestion")
	grid.free();return finish()
