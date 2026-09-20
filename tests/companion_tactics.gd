extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(value: bool, reason: String) -> void:
	if not value: failures += 1; push_error(reason)
func _initialize() -> void:
	call_deferred("exercise")
func arena():
	var s = Session.new(731,true,true); s.depart()
	for cell in s.tiles: cell.terrain = "stone"; cell.fire = 0
	s.party[0].pos = Vector2i(1,1); s.party[1].pos = Vector2i(3,4)
	s.enemies[0].pos = Vector2i(4,4); s.enemies[0].cooldown = 20
	s.selected = 1
	return s
func exercise() -> void:
	var s = arena()
	var ally: Dictionary = s.party[1]
	var boss: Dictionary = s.enemies[0]
	var turn: int = s.round_number
	check(s.set_tactic(1,"PUSH","MANUAL"),"manual policy accepted")
	check(not s.set_tactic(1,"PUSH","bad"),"invalid policy rejected")
	check(s.round_number == turn,"setting policy consumes no time")
	check(s.Tactics.choose(s,ally).kind == "ATTACK","manual skill not used automatically")
	s.set_tactic(1,"PUSH","PROTECT")
	boss.charging = true; boss.fuse = 2
	s.intents = [{"id":boss.id,"cell":s.party[0].pos,"damage":16}]
	check(s.Tactics.choose(s,ally).kind == "PUSH","protect interrupts ally threat")
	s.selected = 0; turn = s.round_number
	var hp: int = boss.hp
	var serial: int = s.serial
	var preview: Array = s.companion_previews()
	check(preview.size() == 1 and preview[0].actor == 1 and preview[0].kind == "PUSH","companion skill is previewed before action")
	check(preview == s.companion_previews() and s.selected == 0 and s.serial == serial and boss.hp == hp and s.round_number == turn,"preview is deterministic and read-only")
	s.set_tactic(1,"PUSH","MANUAL")
	check(s.companion_previews()[0].kind != "PUSH","policy change updates prediction")
	s.set_tactic(1,"PUSH","PROTECT")
	s.act("WAIT",s.party[0].pos)
	check(boss.pos == Vector2i(5,4) and s.intents.is_empty(),"companion actually pushes and cancels warning")
	check(s.round_number == turn+1 and s.selected == 0,"one world tick without recursion")
	s = arena(); ally = s.party[1]; boss = s.enemies[0]
	s.party[0].pos = Vector2i(6,4)
	s.set_tactic(1,"PUSH","OFFENSE"); s.tile(Vector2i(5,4)).fire = 30
	check(s.Tactics.choose(s,ally).kind != "PUSH","do not push foe toward vulnerable ally")
	s.party[0].pos = Vector2i(1,1)
	check(s.Tactics.choose(s,ally).kind == "PUSH","offense uses burning landing")
	s.set_tactic(1,"PUSH","MANUAL"); s.set_tactic(1,"GUARD","DANGER")
	ally.priority = "GUARD"
	check(s.Tactics.choose(s,ally).kind == "GUARD","guard condition and priority")
	s.intents = [{"id":boss.id,"cell":ally.pos,"damage":16}]
	check(s.Tactics.choose(s,ally).kind == "MOVE","escape takes precedence over skill policy")
	var scene = load("res://expedition/main.tscn").instantiate()
	root.size = Vector2i(390,844); root.add_child(scene); scene.depart()
	for frame in range(5): await process_frame
	check(scene.session.party.size() == 2,"two-member active prototype")
	check(scene.board.companion_previews.size() == 1,"board receives next action")
	check(scene.board.get_rect().size.x >= scene.board.preview_rect(scene.session.party[1]).end.x,"badge stays inside screen")
	scene.select_actor(1)
	check(scene.board.companion_previews[0].actor == 0,"preview follows control switch")
	check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"two-member mobile layout fits")
	scene.show_tactics()
	await process_frame
	check(scene.details_popup.visible,"tactics settings opens")
	scene.queue_free(); await process_frame
	print("Companion tactics: %d failures" % failures)
	quit(1 if failures else 0)
