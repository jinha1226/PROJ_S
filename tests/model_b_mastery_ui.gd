extends SceneTree
const Session = preload("res://expedition/run/session.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = Session.new_run(7701)
	scene.session.party[0].skill_xp.sword = 10
	root.size = Vector2i(320,640)
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	scene.show_character(0,"숙련")
	await process_frame
	var grid: GridContainer = scene.find_child("MasteryGrid",true,false)
	check(grid != null and grid.columns == 5 and grid.get_child_count() == 10,"ten masteries in five columns")
	if grid != null:
		for axis in scene.CharacterUI.Mastery.AXES:
			var icon: Button = grid.find_child("MasteryIcon_"+axis,true,false)
			var bar: ProgressBar = grid.find_child("MasteryXP_"+axis,true,false)
			check(icon != null,"mastery icon "+axis)
			check(bar != null and bar.size.y >= 8,"XP bar sits below icon: "+axis)
			if icon != null:
				var glyphs: Array = icon.find_children("*","Control",true,false).filter(func(child): return child.get_script() != null and str(child.get_script().resource_path).ends_with("mastery_glyph.gd"))
				check(glyphs.size() == 1 and icon.get_global_rect().encloses(glyphs[0].get_global_rect()),"drawn glyph fits mastery icon: "+axis)
				var physical_scale: float = float(root.size.x)/scene.get_viewport_rect().size.x
				check(icon.size.x*physical_scale >= 44 and icon.get_global_rect().end.x <= scene.get_viewport_rect().size.x,"mastery icon fits a 320px touch screen: "+axis)
	check(grid.find_child("MasteryXP_sword",true,false).value == 10,"XP bar reflects current sword progress")
	check(not scene.modal_content.find_children("*","Label",true,false).any(func(entry): return str(entry.text).contains("사용으로 성장")),"mastery view has no explanatory growth sentence")
	scene.show_mastery_detail(0,"ice")
	await process_frame
	for level in range(1,11):
		var row: Node = scene.find_child("MasteryLevel%d" % level,true,false)
		check(row != null and row.find_children("*","Label",true,false).any(func(n): return str(n.text).contains("위력")),"unimplemented axis shows numeric growth at Lv%d" % level)
	check(scene.find_child("MasteryBack",true,false) != null,"detail has back button")
	scene.queue_free()
	await process_frame
	print("Model B mastery UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
