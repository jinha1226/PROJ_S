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
	s = arena(); ally = s.party[1]
	turn = s.round_number
	check(not s.update_rule(1,1,"target","NEAREST"),"self skill rejects enemy target")
	check(not s.update_rule(1,0,"threshold",101),"invalid threshold rejected")
	check(s.update_rule(1,0,"enabled",false),"auto skill off")
	s.update_rule(1,1,"when","HP"); s.update_rule(1,1,"threshold",50)
	ally.hp = 55
	check(s.Tactics.choose(s,ally).kind == "ATTACK","unmet HP condition skips rule")
	ally.hp = 20
	check(s.Tactics.choose(s,ally).kind == "GUARD","HP condition applies to self target")
	check(ally.rules.size() == 2 and not s.Rules.SKILLS.has("ATTACK"),"basic attack removed from skill rules")
	check(not s.reorder_rule(1,2,-1),"basic attack cannot be reordered ahead of skills")
	s.update_rule(1,0,"enabled",true); s.update_rule(1,0,"when","ALWAYS")
	check(s.Tactics.choose(s,ally).kind == "PUSH","first matching skill wins")
	s.reorder_rule(1,1,-1)
	check(s.Tactics.choose(s,ally).kind == "GUARD","skill reordering still applies")
	check(s.round_number == turn,"all editor changes are free")
	s.update_rule(1,1,"enabled",false)
	s.update_rule(1,0,"when","STATUS"); s.update_rule(1,0,"status","WET")
	s.tile(ally.pos).wet = 50
	check(s.Tactics.choose(s,ally).kind == "GUARD","shared status condition")
	s.tile(ally.pos).wet = 0
	check(s.Tactics.choose(s,ally).kind == "ATTACK","unmet skills fall back to basic attack")
	var other: Dictionary = s.enemies[0].duplicate(true)
	other.id = 99; other.pos = Vector2i(3,3); other.hp = 3
	s.enemies.append(other)
	check(s.set_basic_target(1,"LOWEST_HP"),"basic target setting accepted")
	check(s.Tactics.choose(s,ally).cell == other.pos,"basic attack selects lowest HP in reach")
	other.pos = Vector2i(6,6)
	check(s.Tactics.choose(s,ally).cell == s.enemies[0].pos,"unreachable priority target does not prevent attack")
	check(not s.set_basic_target(1,"SELF") and not s.set_basic_target(-1,"NEAREST"),"invalid basic settings rejected")
	check(s.party[0].basic_target == "NEAREST" and s.round_number == turn,"basic settings are independent and free")
	s.enemies[0].pos = Vector2i(5,4)
	check(s.Tactics.choose(s,ally).kind == "MOVE","no attack target falls back to approach")
	s.enemies.clear()
	check(s.Tactics.choose(s,ally).kind == "WAIT","no enemies falls back to wait")
	s = arena(); s.selected = 0; ally = s.party[1]
	turn = s.round_number
	check(s.reserve_action(1,"GUARD",ally.pos),"reserve companion guard")
	check(s.selected == 0 and s.round_number == turn and not ally.get("guarded",false),"reservation does not switch control or execute")
	check(s.companion_previews()[0].get("reserved",false),"reserved action is previewed")
	check(s.reserve_action(1,"ATTACK",s.enemies[0].pos),"reservation can be replaced")
	check(not s.reserve_action(1,"MOVE",Vector2i(7,7)) and ally.reservation.kind == "ATTACK","invalid reservation preserves previous order")
	s.act("WAIT",s.party[0].pos)
	check(ally.reservation.is_empty() and ally.last_action == "직접 예약" and s.round_number == turn+1,"reservation executes once on leader action")
	check(s.reserve_action(1,"ATTACK",s.enemies[0].pos),"reserve attack again")
	s.enemies[0].pos = Vector2i(6,6)
	check(not s.companion_previews()[0].get("reserved",false),"invalidated target falls back to automatic action")
	s.act("WAIT",s.party[0].pos)
	check(ally.reservation.is_empty(),"invalidated reservation is consumed")
	check(s.reserve_action(1,"GUARD",ally.pos),"reserve before cancel")
	s.cancel_reservation(1)
	check(ally.reservation.is_empty(),"explicit cancellation")
	check(s.reserve_action(1,"MOVE",ally.pos+Vector2i(0,1)),"adjacent movement can be reserved")
	s.party[0].pos = ally.reservation.cell
	check(not s.companion_previews()[0].get("reserved",false),"occupied destination invalidates movement reservation")
	s = arena(); s.selected = 0; ally = s.party[1]
	check(s.reserve_action(1,"PUSH",s.enemies[0].pos),"manual-only skills can be reserved")
	s.enemies[0].pos = Vector2i(3,3)
	check(s.companion_previews()[0].cell == Vector2i(3,3),"reservation tracks same enemy within reach")
	s.enemies[0].hp = 0
	check(not s.companion_previews()[0].get("reserved",false),"dead target invalidates reservation")
	var scene = load("res://expedition/main.tscn").instantiate()
	root.size = Vector2i(390,844); root.add_child(scene); scene.depart()
	for frame in range(5): await process_frame
	check(scene.session.party.size() == 2,"two-member active prototype")
	check(scene.board.companion_previews.size() == 1,"board receives next action")
	check(scene.board.get_rect().size.x >= scene.board.preview_rect(scene.session.party[1]).end.x,"badge stays inside screen")
	scene.select_actor(1)
	check(scene.session.selected == 0 and scene.reservation_actor == 1,"portrait starts reservation without switching control")
	check(scene.board.companion_previews[0].actor == 1,"companion preview retains same actor")
	var ui_turn: int = scene.session.round_number
	scene.choose_skill(1,1)
	check(scene.session.party[1].reservation.kind == "GUARD" and scene.session.round_number == ui_turn,"companion skill click queues without advancing time")
	check(scene.reservation_actor == -1 and scene.session.selected == 0,"reservation returns input to leader")
	check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"two-member mobile layout fits")
	scene.show_tactics()
	await process_frame
	check(scene.details_popup.visible,"tactics settings opens")
	scene.change_basic_target("LOWEST_HP")
	check(scene.session.party[0].basic_target == "LOWEST_HP","UI changes independent basic target")
	scene.tactics_expanded = 0; scene.show_tactics()
	scene.change_tactic_rule(0,"when","HP")
	await process_frame
	check(scene.session.party[0].rules[0].when == "HP","UI editor changes common rule")
	check(scene.details_popup.size.y <= root.size.y,"expanded editor fits mobile viewport")
	scene.change_tactic_rule(0,"when","STATUS")
	await process_frame
	scene.queue_free(); await process_frame
	print("Companion tactics: %d failures" % failures)
	quit(1 if failures else 0)
