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
	eight_way_checks()
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
	check(preview.size() == 1 and preview[0].actor == 1 and preview[0].kind == "PUSH","companion is previewed before action")
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
	check(scene.session.party.size() == 2,"leader and one companion")
	check(scene.board.companion_previews.size() == 1,"board receives companion action")
	var header: Node = scene.root_layout.get_child(0)
	check(header.find_children("*","Button",true,false).is_empty(),"HUD has no character or resource buttons")
	var nav: Node = scene.root_layout.get_child(scene.root_layout.get_child_count()-1)
	check(nav.get_child(2).text == "상태","status replaces exploration in footer")
	nav.get_child(2).pressed.emit()
	check(scene.details_popup.visible and scene.character_tab == "상태","footer status opens character window")
	scene.details_popup.hide()
	check(not scene.find_children("*","Label",true,false).any(func(l): return l.text.contains("8방향 이동 /") or l.text.contains("폭발 후 탈진 틈")),"persistent control and boss strategy hints removed")
	check(scene.wait_button.get_parent() == scene.root_layout.get_child(scene.root_layout.get_child_count()-1),"wait is in bottom navigation row")
	check(scene.wait_button.size.x >= 44 and scene.wait_button.size.y >= 44,"wait has mobile touch target")
	var moves: Array = scene.board.movement_previews()
	check(moves.size() == 1 and moves[0].cell == scene.board.companion_previews[0].cell,"automatic move marker uses predicted destination")
	var reserved_cell: Vector2i = scene.session.movement_cells(1)[0]
	check(scene.session.reserve_action(1,"MOVE",reserved_cell),"reserve move for board marker")
	scene.refresh()
	moves = scene.board.movement_previews()
	check(moves.size() == 1 and moves[0].reserved and moves[0].cell == reserved_cell,"reserved move marker uses reserved destination")
	scene.session.cancel_reservation(1); scene.refresh()
	for frame in range(3): await process_frame
	check(scene.board.get_rect().size.x >= scene.board.preview_rect(scene.session.party[1]).end.x,"badge stays inside screen")
	scene.select_actor(1)
	check(scene.session.selected == 0 and scene.reservation_actor == 1,"portrait starts reservation without switching control")
	check(scene.board.companion_previews[0].actor == 1,"companion preview retains same actor")
	var ui_turn: int = scene.session.round_number
	scene.choose_skill(1,1)
	check(scene.session.party[1].reservation.kind == "GUARD" and scene.session.round_number == ui_turn,"companion skill click queues without advancing time")
	check(scene.reservation_actor == -1 and scene.session.selected == 0,"reservation returns input to leader")
	check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"two-member mobile layout fits")
	check(scene.portrait_buttons.size() == 2 and scene.skill_buttons.size() == 4,"two portraits and four skill slots")
	check(scene.board.movement_previews().is_empty(),"guard preview does not leave stale move marker")
	scene.wait_button.pressed.emit()
	check(scene.session.round_number == ui_turn+1 and scene.session.selected == 0,"companion advances world only once")
	check(scene.session.party[1].reservation.is_empty() and scene.session.party[1].last_action == "직접 예약","companion executes one reserved action")
	scene.show_tactics()
	await process_frame
	check(scene.details_popup.visible,"tactics settings opens")
	check(scene.character_tab == "숙련","rule editor is embedded in mastery tab")
	scene.show_character(1,"상태")
	check(scene.tactics_actor == 1 and scene.session.selected == 0,"per-character status does not switch control")
	scene.show_character(0,"숙련")
	scene.change_basic_target("LOWEST_HP")
	check(scene.session.party[0].basic_target == "LOWEST_HP","UI changes independent basic target")
	scene.tactics_expanded = 0; scene.show_tactics()
	scene.change_tactic_rule(0,"when","HP")
	await process_frame
	check(scene.session.party[0].rules[0].when == "HP","UI editor changes common rule")
	check(scene.details_popup.size.y <= root.size.y,"expanded editor fits mobile viewport")
	scene.change_tactic_rule(0,"when","STATUS")
	await process_frame
	for viewport in [Vector2i(390,844),Vector2i(430,844),Vector2i(412,915)]:
		root.size = viewport
		for frame in range(3): await process_frame
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"new HUD fits portrait viewport %s" % viewport)
		check(scene.details_popup.size.y <= root.size.y,"character mastery fits viewport")
		scene.select_actor(1)
		for frame in range(3): await process_frame
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"reservation UI fits portrait viewport %s" % viewport)
		scene.select_actor(0)
	scene.details_popup.hide()
	ui_turn = scene.session.round_number
	scene.advance_attack_button.pressed.emit()
	check(scene.session.round_number == ui_turn+1 and scene.session.selected == 0,"footer attack executes one hero action")
	scene.queue_free(); await process_frame
	print("Companion tactics: %d failures" % failures)
	quit(1 if failures else 0)

func eight_way_checks() -> void:
	var s = Session.new(731,true); s.depart()
	for cell in s.tiles: cell.terrain = "stone"; cell.fire = 0; cell.wet = 0
	var hero: Dictionary = s.party[0]
	var boss: Dictionary = s.enemies[0]
	hero.pos = Vector2i(2,2); boss.pos = Vector2i(5,5); boss.recovery = 99
	check(s.movement_cells().size() == 8,"all eight adjacent movement cells")
	check(Vector2i(3,3) in s.attack_cells(),"diagonal attack range shown")
	var turn: int = s.round_number
	check(s.auto_attack() and hero.pos == Vector2i(3,3) and s.round_number == turn+1,"attack button approaches one diagonal step")
	check(s.auto_attack() and hero.pos == Vector2i(4,4),"attack button reaches diagonal melee range")
	var hp: int = boss.hp
	check(s.auto_attack() and boss.hp < hp and hero.pos == Vector2i(4,4),"attack button attacks instead of moving when in range")
	hero.pos = Vector2i(2,2); boss.pos = Vector2i(3,3)
	s.tile(Vector2i(3,2)).terrain = "wall"
	turn = s.round_number
	check(Vector2i(3,3) not in s.attack_cells() and not s.act("ATTACK",boss.pos),"diagonal attack cannot cut wall corner")
	check(not s.can_step(Vector2i(2,2),Vector2i(3,3)),"diagonal movement cannot cut wall corner")
	check(s.round_number == turn,"invalid diagonal action is free")
	s.tile(Vector2i(3,2)).terrain = "stone"
	check(s.act("PUSH",boss.pos) and boss.pos == Vector2i(4,4),"diagonal push uses matching diagonal displacement")
	hero.pos = Vector2i(1,1); boss.pos = Vector2i(6,6)
	for direction in s.DIRECTIONS: s.tile(hero.pos+direction).terrain = "wall"
	turn = s.round_number
	check(not s.auto_attack() and s.round_number == turn,"unreachable auto attack does not consume turn")
