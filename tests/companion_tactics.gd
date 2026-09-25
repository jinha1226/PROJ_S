extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Utility = preload("res://expedition/ai/utility.gd")
const PartsCandidates = preload("res://expedition/ai/parts_candidates.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
var checks := 0
func check(value: bool, reason: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(reason)
func _initialize() -> void:
	call_deferred("exercise")
## The best `rule_ready` grade any candidate of this part earns right now: the
## number the rule order survives as once the parts compete instead of pre-empt.
func grade(s, actor: Dictionary, kind: String) -> float:
	var pool: Array = PartsCandidates.candidates(s,actor)
	var ctx: Dictionary = Utility.context(s,actor,pool)
	var best := 0.0
	for o in pool:
		if str(o.kind) == kind: best = maxf(best,float(Utility.inputs(s,actor,o,ctx).rule_ready))
	return best
func arena():
	var s = Session.new(731,true,true); s.depart()
	for cell in s.tiles: cell.terrain = "stone"; cell.fire = 0
	for enemy in s.enemies: enemy.hp = 0
	Fixture.equip_basics(s)
	s.party[0].pos = Vector2i(1,1); s.party[1].pos = Vector2i(3,4)
	s.enemies[0].hp = 30; s.enemies[0].pos = Vector2i(4,4); s.enemies[0].cooldown = 20
	s.selected = 1
	s.floor_state.observe(s)
	# The companion under test fights as a 거리형: it strikes what is beside it
	# and steps off a telegraphed cell, which is what these rule checks assume.
	s.party[1].stance = "SKIRMISHER"
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
	# 엄호 needs a covered ally: the leader steps in beside the boss and is one
	# hit from death, which is the rule's only condition.
	s.party[0].pos = Vector2i(4,3); s.party[0].hp = 4
	check(s.Tactics.choose(s,ally).kind == "GUARD","guard condition and priority")
	s.party[0].hp = 55
	check(s.Tactics.choose(s,ally).kind != "GUARD","a healthy leader needs no cover")
	s.set_tactic(1,"GUARD","MANUAL"); s.set_tactic(1,"PUSH","OFFENSE")
	s.intents = [{"id":boss.id,"cell":ally.pos,"damage":16}]
	check(s.Tactics.choose(s,ally).kind == "PUSH","a matched skill policy outranks the stance")
	s.set_tactic(1,"PUSH","MANUAL")
	check(s.Tactics.choose(s,ally).kind == "MOVE","with no rule matched the 거리형 leaves the telegraphed cell")
	s = arena(); ally = s.party[1]
	turn = s.round_number
	check(not s.update_rule(1,1,"target","NEAREST"),"ally skill rejects enemy target")
	check(not s.update_rule(1,0,"threshold",101),"invalid threshold rejected")
	check(s.update_rule(1,0,"enabled",false),"auto skill off")
	# 엄호's only condition: the leader beside the ally must be about to die.
	s.party[0].pos = Vector2i(4,3)
	check(s.Tactics.choose(s,ally).kind == "ATTACK","unmet ally condition skips rule")
	s.party[0].hp = 4
	check(s.Tactics.choose(s,ally).kind == "GUARD","lethal condition applies to the ally target")
	check(ally.rules.size() == 2 and not s.Rules.catalog().has("ATTACK"),"basic attack removed from skill rules")
	check(not s.reorder_rule(1,2,-1),"basic attack cannot be reordered ahead of skills")
	s.update_rule(1,0,"enabled",true); s.update_rule(1,0,"when","ALWAYS")
	# 설계 §1 4단계(Task 3): 파츠는 선점하지 않고 같은 풀에서 경쟁한다. 규칙 순위는
	# `rule_ready` 등급(순위마다 −2%)으로만 남고 한 라운드 룩어헤드가 그 위에 얹히므로,
	# "먼저 맞는 규칙"은 무엇을 눌렀는지가 아니라 어느 쪽 등급이 높은지로 확인한다.
	check(grade(s,ally,"PUSH") > grade(s,ally,"GUARD"),"first matching skill grades highest")
	# 그리고 그 등급 위에서 룩어헤드가 결정한다: 엄호는 4 피해를 대신 받아 4 HP
	# 리더를 실제로 살리고(`la_lethal_saved`), 밀치기는 보스를 여전히 리더에게 닿는
	# 칸으로 밀 뿐이다 — 살린 목숨이 규칙 순위를 이긴다.
	check(s.Tactics.choose(s,ally).kind == "GUARD","a life the lookahead saves outranks the rule order")
	s.reorder_rule(1,1,-1)
	check(grade(s,ally,"GUARD") > grade(s,ally,"PUSH"),"skill reordering still applies")
	check(s.round_number == turn,"all editor changes are free")
	s.reorder_rule(1,0,1)
	s.update_rule(1,1,"enabled",false)
	s.update_rule(1,0,"when","STATUS"); s.update_rule(1,0,"status","WET"); s.update_rule(1,0,"subject","SELF")
	s.tile(ally.pos).wet = 50
	check(s.Tactics.choose(s,ally).kind == "PUSH","shared status condition on the actor's own tile")
	s.tile(ally.pos).wet = 0
	check(s.Tactics.choose(s,ally).kind == "ATTACK","unmet skills fall back to basic attack")
	var other: Dictionary = s.enemies[0].duplicate(true)
	other.id = 99; other.pos = Vector2i(3,3); other.hp = 3
	s.enemies.append(other)
	# The leader steps back out of contact: while a 돌격형 stands on a foe that
	# foe is the party's target, and the tie-break below is what is under test.
	s.party[0].pos = Vector2i(1,1); s.party[0].hp = 55
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
	s.party[0].pos = Vector2i(3,3)
	turn = s.round_number
	check(s.reserve_action(1,"GUARD",s.party[0].pos),"reserve companion guard")
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
	check(s.reserve_action(1,"GUARD",s.party[0].pos),"reserve before cancel")
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
	# The live HUD exposes compact party state and the same prediction data.
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = Session.new(731,true,true,true,2)
	scene.session.depart()
	root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	var ui_s = scene.session
	Fixture.arena(ui_s,8); Fixture.equip_basics(ui_s)
	ui_s.party[1].stance = "CHARGER"
	ui_s.floor_state.observe(ui_s); scene.refresh()
	for frame in range(3): await process_frame
	check(ui_s.party.size() == 2 and scene.portrait_buttons.size() == 2,"leader and companion have two compact cards")
	check(scene.skill_buttons.is_empty(),"auto battle HUD has no manual skill row")
	check(scene.board.companion_previews.size() == 1,"board receives companion prediction")
	var header: Node = scene.find_child("TopHUD",true,false)
	check(header.get_children().slice(1).map(func(c): return str(c.name)) == ["Location","FoodLabel","ExpeditionMenu"],"floor header is compact")
	check(scene.find_child("FoodLabel",true,false).text == "식량 2","food is visible beside depth")
	header.get_node("ExpeditionMenu").pressed.emit(); await process_frame
	check(scene.details_popup.visible and scene.modal_content.get_children().map(func(c): return c.text) == ["기록","가방","닫기"],"menu holds only direct actions")
	scene.details_popup.hide()
	var nav: Node = scene.find_child("BottomActions",true,false)
	check(nav != null and nav.find_child("CampButton",true,false) != null and nav.find_child("RetreatToggle",true,false) != null,"footer carries camp and retreat")
	check(scene.wait_button != null and scene.wait_button.get_parent() == nav,"wait is in the footer")
	check(scene.wait_button.size.x >= 44 and scene.wait_button.size.y >= 44,"wait remains touchable")
	var marker: Array = scene.board.movement_previews()
	check(marker.size() <= 1,"each companion has at most one movement marker")
	ui_s.selected = 0
	var choices: Array = ui_s.movement_cells(1)
	check(not choices.is_empty(),"companion has legal movement cells")
	if not choices.is_empty():
		check(ui_s.reserve_action(1,"MOVE",choices[0]),"companion movement can be reserved")
		scene.refresh()
		check(scene.board.companion_previews.any(func(row): return row.actor == 1 and row.cell == choices[0]),"board shows reserved destination")
		ui_s.cancel_reservation(1)
	check(ui_s.party[1].reservation.is_empty(),"reservation clears without an action")
	scene.select_actor(1)
	check(ui_s.selected == 1 and scene.reservation_actor == -1,"portrait selects the companion")
	scene.show_character(1,"상태")
	check(scene.tactics_actor == 1 and scene.details_popup.visible,"companion sheet opens")
	scene.show_character(1,"파츠")
	check(scene.modal_content.find_child("EssenceSlots",true,false).get_child_count() == 10,"companion has an essence grid")
	scene.details_popup.hide()
	for viewport in [Vector2i(390,844),Vector2i(430,844),Vector2i(412,915)]:
		root.size = viewport; scene.refresh()
		for frame in range(3): await process_frame
		check(scene.get_global_rect().encloses(scene.root_layout.get_global_rect()),"party HUD fits %s" % viewport)
		for id in ["FoodLabel","CampButton","RetreatToggle","AutoToggle"]:
			var control: Control = scene.find_child(id,true,false)
			check(control != null and scene.get_global_rect().encloses(control.get_global_rect()),"%s fits %s" % [id,viewport])
	await portrait_hold(scene,ui_s)
	await rule_editor(scene,ui_s)
	await preview_markers(scene,ui_s)
	recruited_preview()
	scene.queue_free(); await process_frame
	print("Companion tactics: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

## A solo run that recruits someone still telegraphs that companion's next
## action, even in manual play where its AP is spent between its turns.
func recruited_preview() -> void:
	var s = Session.new_run(64)
	var c: Vector2i = Fixture.arena(s,6)
	var ally: Dictionary = s.make_actor(1001,"동료",false)
	ally.pos = c+Vector2i(2,1); ally.ap = 0; s.party.append(ally)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.pos = c+Vector2i(1,0); foe.alert = true
	s.floor_state.observe(s)
	check(not s.companions and s.manual_mode,"the run started solo and is played by hand")
	var previews: Array = s.companion_previews()
	check(previews.size() == 1 and previews[0].actor == ally.id,"the recruit's next action is previewed")
	check(s.companion_previews() == previews,"the preview is read-only")

## The portrait is a two-gesture control: a tap selects, a hold opens the sheet.
func portrait_hold(scene, ui_s) -> void:
	root.size = Vector2i(390,844); scene.refresh()
	for frame in range(3): await process_frame
	scene.details_popup.hide()
	var hold := InputEventScreenTouch.new(); hold.index = 0; hold.pressed = true
	hold.position = scene.portrait_buttons[0].get_global_rect().get_center()
	scene._input(hold); scene.portrait_gesture.started -= 601; scene.portrait_gesture.tick(scene)
	hold.pressed = false; scene._input(hold)
	await process_frame
	check(scene.details_popup.visible,"holding a portrait opens the character window")
	check(scene.character_tab == "상태","on the status tab")
	check(ui_s.round_number >= 1 and ui_s.phase != "CAMP","and it costs no time")
	scene.details_popup.hide(); await process_frame
	check(not scene.details_popup.visible,"and closes again")

## The rule editor the character sheet embeds: it still edits the live actor.
func rule_editor(scene, ui_s) -> void:
	scene.show_character(0,"파츠")
	await process_frame
	check(scene.details_popup.visible and scene.character_tab == "영혼석","the rule editor lives in the essence tab")
	check(scene.details_popup.size.y <= root.size.y,"and fits the viewport")
	scene.change_basic_target("LOWEST_HP")
	await process_frame
	check(ui_s.party[0].basic_target == "LOWEST_HP","the sheet changes the basic target")
	scene.tactics_expanded = 0; scene.show_tactics()
	scene.change_tactic_rule(0,"when","HP")
	await process_frame
	check(ui_s.party[0].rules[0].when == "HP","and the rule condition")
	check(scene.details_popup.size.y <= root.size.y,"the expanded editor still fits")
	scene.change_tactic_rule(0,"when","STATUS")
	await process_frame
	check(ui_s.party[0].rules[0].when == "STATUS","and changes it back")
	scene.show_character(1,"영혼석")
	await process_frame
	check(scene.tactics_actor == 1 and scene.character_tab == "영혼석","the companion has its own essence tab")
	check(scene.details_popup.size.y <= root.size.y,"which fits the viewport too")
	scene.details_popup.hide(); await process_frame

## What the board draws ahead of a companion: one marker, on the cell the
## prediction names, and inside the screen.
func preview_markers(scene, ui_s) -> void:
	ui_s.selected = 0
	scene.refresh()
	for frame in range(3): await process_frame
	var previews: Array = scene.board.companion_previews
	var moves: Array = scene.board.movement_previews()
	check(moves.size() <= previews.size(),"a marker never outnumbers the predictions")
	for row in moves:
		check(previews.any(func(p): return p.actor == row.actor and p.cell == row.cell),"each marker sits on its own prediction")
		check(ui_s.inside(row.cell) and row.cell != row.from,"and names a real cell to move to")
		check(row.has("sprite"),"and carries the pawn to draw there")
	var rect: Rect2 = scene.board.preview_rect(ui_s.party[1])
	check(scene.board.get_rect().size.x >= rect.end.x,"the companion badge stays inside the board")
	check(rect.position.x >= 0 and rect.position.y >= 0,"and does not run off its top left")

func eight_way_checks() -> void:
	var s = Session.new(731,true); s.depart()
	for cell in s.tiles: cell.terrain = "stone"; cell.fire = 0; cell.wet = 0
	for enemy in s.enemies: enemy.hp = 0
	Fixture.equip_basics(s)
	var hero: Dictionary = s.party[0]
	var boss: Dictionary = s.enemies[0]
	hero.pos = Vector2i(2,2); boss.hp = 100; boss.pos = Vector2i(5,5); boss.recovery = 99
	s.floor_state.observe(s)
	check(s.DIRECTIONS.all(func(d): return hero.pos+d in s.movement_cells()),"all eight adjacent movement cells")
	check(Vector2i(3,3) in s.attack_cells(),"diagonal attack range shown")
	var turn: int = s.round_number
	check(s.auto_attack() and hero.pos == Vector2i(3,3) and s.round_number == turn+1,"attack button approaches one diagonal step")
	var approached := false
	for _step in range(4):
		if s.melee_reach(hero.pos,boss.pos): approached = true; break
		if not s.auto_attack(): break
	check(approached or s.melee_reach(hero.pos,boss.pos),"attack button reaches melee range")
	var hp: int = boss.hp
	check(s.auto_attack() and boss.hp < hp,"attack button attacks instead of moving when in range")
	hero.pos = Vector2i(2,2); boss.pos = Vector2i(3,3)
	s.tile(Vector2i(3,2)).terrain = "wall"
	turn = s.round_number
	check(Vector2i(3,3) in s.attack_cells() and not s.attack_preview(boss.pos).is_empty(),"diagonal attack passes one-wall corner")
	s.tile(Vector2i(2,3)).terrain = "wall"
	turn = s.round_number
	check(Vector2i(3,3) in s.attack_cells() and not s.attack_preview(boss.pos).is_empty(),"two-wall corner also permits diagonal attack")
	check(not s.can_step(Vector2i(2,2),Vector2i(3,3)),"occupied diagonal destination stays blocked")
	check(s.round_number == turn,"attack previews do not consume a turn")
	s.tile(Vector2i(3,2)).terrain = "stone"
	s.tile(Vector2i(2,3)).terrain = "stone"
	boss.pos = Vector2i(3,3); boss.hp = 100
	hero.ap = 1; s.floor_state.observe(s)
	check(s.act("PUSH",boss.pos) and boss.pos == Vector2i(4,4),"diagonal push uses matching diagonal displacement")
	hero.pos = Vector2i(1,1); boss.pos = Vector2i(6,6)
	for direction in s.DIRECTIONS: s.tile(hero.pos+direction).terrain = "wall"
	turn = s.round_number
	check(not s.auto_attack() and s.round_number == turn,"unreachable auto attack does not consume turn")
