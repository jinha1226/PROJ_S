extends "res://tests/test_case.gd"

const Frame=preload("res://playtest/ascii_ui_frame.gd")
const Gauge=preload("res://playtest/ascii_gauge.gd")

func test_palette_is_oxidized_iron_bone_and_restrained_state_ink()->bool:
	check(Frame.BLACK.get_luminance()<Frame.SURFACE.get_luminance() \
		and Frame.SURFACE.get_luminance()<Frame.INK.get_luminance(),
		"black iron field and aged bone text retain hierarchy")
	check(Frame.PARCHMENT.get_luminance()>Frame.BONE_DIM.get_luminance() \
		and Frame.BRASS_DARK.get_luminance()<Frame.BRASS.get_luminance(),
		"parchment title and tarnished brass tiers are distinct")
	check(Frame.DANGER==Color("#a74343") and Frame.JADE==Color("#5f8a66") \
		and Frame.CYAN==Color("#4f9aa3"),
		"blood moss and oxidized cyan remain restrained semantic accents")
	return finish()

func test_frame_uses_heavy_iron_grammar_and_vertical_light_hierarchy()->bool:
	var frame=Frame.new();frame.size=Vector2(336,120)
	frame.configure("인물",Frame.CYAN,Frame.BLACK,false)
	var spec:Dictionary=frame.frame_spec()
	check_eq([spec.primitive,spec.visual_family,spec.frame_material],
		["FIXED_CELL_GLYPHS","DARK_FANTASY_IRON_FOLIO","OXIDIZED_BLACK_IRON"],
		"frame material contract")
	check_eq(spec.boundary_glyphs,"┏━┓┃┗┛","heavy fortress-like box grammar")
	check("┫" in str(spec.title_text) and "┣" in str(spec.title_text) \
		and "인물" in str(spec.title_text),"title is cut into the top iron rail")
	check(spec.top_edge_color!=spec.side_edge_color \
		and spec.side_edge_color!=spec.bottom_edge_color,
		"top side and bottom edges have restrained depth hierarchy")
	check_eq(spec.font_path,"res://assets/fonts/LivingWorldMonoKR.ttf","Korean mono font preserved")
	check(bool(spec.right_edge_inside) and bool(spec.bottom_edge_inside),"frame remains clipped-safe")
	frame.free();return finish()

func test_danger_frame_changes_only_semantic_edge_without_layout_cost()->bool:
	var frame=Frame.new();frame.size=Vector2(180,80)
	frame.configure("위험",Frame.CYAN,Frame.BLACK,true);frame.danger_edge=true
	var danger:Dictionary=frame.frame_spec();frame.danger_edge=false
	var calm:Dictionary=frame.frame_spec()
	check(danger.danger_edge and danger.right_edge_color!=calm.right_edge_color,
		"danger uses a dried-blood right rail")
	check_eq(danger.content_inset,calm.content_inset,"danger adds no ornamental layout cost")
	check_eq(danger.font_size,9,"compact frame legibility is unchanged")
	frame.free();return finish()

func test_gauge_separates_bone_labels_ink_fill_and_iron_empty_cells()->bool:
	var gauge=Gauge.new();gauge.size=Vector2(220,28)
	gauge.configure("HP",37,100,10,Frame.JADE)
	var spec:Dictionary=gauge.gauge_spec()
	check_eq([spec.primitive,spec.visual_family,spec.material],
		["DOS_TEXT_GAUGE","DARK_FANTASY_BONE_GAUGE","ETCHED_IRON"],
		"gauge material contract")
	check_eq([spec.filled_columns,spec.empty_columns],[3,7],"integer fill projection unchanged")
	check_eq([spec.filled_glyph,spec.empty_glyph],["#","."],"classic DOS glyph grammar retained")
	check(spec.segment_colors.label!=spec.segment_colors.empty \
		and spec.segment_colors.fill==Frame.JADE.to_html(),
		"bone labels, moss fill and iron track are separate inks")
	check(not spec.uses_texture and not spec.uses_image and not spec.per_frame_process,
		"gauge remains pure cached text drawing")
	check_eq(spec.font_size,14,"compact gauge font does not shrink")
	gauge.free();return finish()

func test_semantic_vital_gauges_color_only_the_filled_hash_cells()->bool:
	var expected:={"HP":Gauge.HP_FILL,"MP":Gauge.MP_FILL,"XP":Gauge.XP_FILL}
	for role in expected:
		var gauge=Gauge.new();gauge.size=Vector2(220,28)
		gauge.configure_semantic(role,50,100,10,Frame.YELLOW)
		var spec:Dictionary=gauge.gauge_spec()
		check_eq(spec.semantic_role,role,"%s semantic role is explicit"%role)
		check_eq(spec.segment_colors.fill,expected[role].to_html(),
			"%s filled # uses its semantic ink"%role)
		check_eq(spec.segment_colors.label,Gauge.AGED_BONE.to_html(),
			"%s label keeps aged-bone ink"%role)
		check_eq(spec.segment_colors.empty,Gauge.EMPTY_IRON.to_html(),
			"%s empty cells keep iron ink"%role)
		check_eq(spec.segment_colors.value,Gauge.AGED_BONE.to_html(),
			"%s value keeps aged-bone ink"%role)
		gauge.free()
	return finish()

func test_rail_buttons_keep_touch_geometry_and_gain_iron_material_contract()->bool:
	var button=Button.new();button.custom_minimum_size=Vector2(44,44)
	Frame.apply_rail_button(button,Frame.BRASS,true,false)
	check(bool(button.get_meta("ascii_rail",false)) \
		and str(button.get_meta("visual_family",""))=="DARK_FANTASY_IRON_RAIL",
		"button publishes the iron rail role")
	check_eq(button.custom_minimum_size,Vector2(44,44),"theme never reduces touch target")
	check_eq(button.get_theme_color("font_color"),Frame.BRASS,"selected command uses tarnished brass")
	check(button.get_theme_stylebox("normal") is StyleBoxFlat \
		and button.get_theme_stylebox("hover") is StyleBoxFlat,
		"rail stays code-drawn and texture-free")
	button.free();return finish()

func test_theme_sources_contain_no_texture_or_image_dependencies()->bool:
	var frame_source:=FileAccess.get_file_as_string("res://playtest/ascii_ui_frame.gd")
	var gauge_source:=FileAccess.get_file_as_string("res://playtest/ascii_gauge.gd")
	for forbidden in ["TextureRect","ImageTexture","draw_texture"]:
		check(forbidden not in frame_source and forbidden not in gauge_source,
			"theme source excludes %s"%forbidden)
	return finish()
