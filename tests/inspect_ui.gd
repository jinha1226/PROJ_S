extends SceneTree
## §2.4 and §4: a long press on a monster shows its stats and essence; the npc
## popup shows level and worn essences instead of a mastery.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Forms = preload("res://expedition/combat/forms.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func label(scene, node_name: String) -> Label:
	return scene.modal_content.find_child(node_name,true,false)

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	for _i in range(4): await process_frame
	var foe: Dictionary = s.enemies.filter(func(e): return Essences.has(str(e.get("part_id",""))))[0]
	var hero: Dictionary = s.party[0]
	var cell: Vector2i = hero.pos+Vector2i(1,0)
	if not s.is_free(cell): cell = hero.pos+Vector2i(0,1)
	foe.pos = cell; foe.res = {"fire":25}
	s.floor_state.observe(s)
	check(s.floor_state.visible.has(cell),"the monster stands in sight")
	scene.inspect_cell(cell)
	for _i in range(3): await process_frame
	check(scene.details_popup.visible and label(scene,"EnemyInfo") != null,"a long press opens the monster's card")
	var sheet: Dictionary = StatSheet.sheet(s,foe)
	check(label(scene,"EnemyDefence") != null and label(scene,"EnemyDefence").text == "방어 %d   회피 %d   막기 %d" % [int(sheet.ac.total),int(sheet.ev.total),int(sheet.sh.total)],"defence numbers from the stat sheet")
	check(label(scene,"EnemyBody") != null and label(scene,"EnemyBody").text == Forms.body_line(foe),"the monster card shows attack form and body steps")
	check(label(scene,"EnemyResist") != null and label(scene,"EnemyResist").text.contains("%d%%" % int(sheet.res_fire.total)),"its resistance is listed")
	check(label(scene,"EnemyEssence") != null and label(scene,"EnemyEssence").text == "영혼석 · "+Essences.title(str(foe.part_id)),"its essence is named")
	scene.details_popup.hide()
	foe.res = {}
	scene.inspect_cell(cell)
	for _i in range(3): await process_frame
	check(label(scene,"EnemyResist") == null,"no resistance line when every resistance is zero")
	scene.details_popup.hide()
	var npc: Dictionary = s.roster[0]
	npc.essences = {"ORC_CLEAVER":1}; npc.equipped_abilities = ["ORC_CLEAVER"]
	scene.Popups.show_npc(scene,npc)
	for _i in range(3): await process_frame
	check(label(scene,"NpcLevel") != null and label(scene,"NpcLevel").text == "Lv.%d · 영혼석 %s" % [int(npc.level),Essences.title("ORC_CLEAVER")],"the npc line shows level and essences")
	scene.details_popup.hide(); scene.queue_free(); await process_frame
	print("Inspect UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
