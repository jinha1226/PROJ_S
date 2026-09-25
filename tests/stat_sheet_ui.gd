extends SceneTree
## §4 캐릭터 화면: every stat as a number, and a tap that says where it came from.
const Session = preload("res://expedition/run/session.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const CharacterUI = preload("res://expedition/ui/screens/character_folio.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(4): await process_frame
	s.phase = "CAMP"
	var hero: Dictionary = s.party[0]
	s.parts_bag["ORC_CLEAVER"] = 1
	check(s.absorb_essence(0,"ORC_CLEAVER").is_empty() and s.equip_part(0,0,"ORC_CLEAVER"),"an orc essence is worn")
	scene.show_character(0,"상태")
	for _i in range(4): await process_frame
	for group in ["능력치","방어 수치","속성 저항"]:
		check(scene.modal_content.find_child("StatGroup_"+group,true,false) != null,"the status tab has the %s card" % group)
	var sheet: Dictionary = StatSheet.sheet(s,hero)
	for key in StatSheet.KEYS:
		var cell: Button = scene.modal_content.find_child("Stat_"+key,true,false)
		check(cell != null,"a button for "+key)
		if cell == null: continue
		var shown: String = ("%d%%" if key.begins_with("res_") else "%d") % int(sheet[key].total)
		check(cell.text.ends_with(shown),"%s shows its total %s" % [key,shown])
	var strength: Button = scene.modal_content.find_child("Stat_str",true,false)
	strength.pressed.emit()
	for _i in range(3): await process_frame
	var lines: Array = scene.item_detail.find_children("*","Label",true,false).map(func(l): return l.text)
	check(lines.any(func(t): return t.contains("합계  %d" % int(sheet.str.total))),"the breakdown ends in the total")
	check(lines.any(func(t): return t.contains("+2")),"the orc essence's +2 is listed as its own line")
	check(CharacterUI.breakdown({"total":0,"parts":[]},"res_fire") == "기본값 없음\n합계  0%","an empty resistance still says its total")
	check(not scene.modal_content.find_children("*","Label",true,false).any(func(l): return l.text.contains("숙련")),"no mastery on the status tab")
	scene.item_popup.hide(); scene.queue_free(); await process_frame
	print("Stat sheet UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
