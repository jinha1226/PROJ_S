extends SceneTree
## §2.4 and §4: a long press on a monster shows its stats and essence; the npc
## popup shows level and worn essences instead of a mastery.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
const Icons = preload("res://expedition/art/soulstone_icons.gd")
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
	npc.essences = {"ORC_CLEAVER":1}; npc.equipped_abilities = ["ORC_CLEAVER"]; npc.build_role = "MELEE"
	scene.Popups.show_npc(scene,npc)
	for _i in range(3): await process_frame
	check(label(scene,"NpcLevel") != null and label(scene,"NpcLevel").text == "Lv.%d · 근접" % int(npc.level),"the NPC header shows its level and role")
	check(scene.modal_content.find_child("StoneName",true,false).text == Essences.title("ORC_CLEAVER") and scene.modal_content.find_child("StoneEffect",true,false).text == EssenceTab.effect_line("ORC_CLEAVER",npc),"before recruitment the card shows the actual stone name and effect")
	scene.details_popup.hide()
	# Distant inspection must not become distant recruitment or spend a turn.
	var c := Fixture.arena(s,8); npc.pos = c+Vector2i(3,0); npc.state = "MET"; npc.partner = -1
	s.npcs = [npc]; s.floor_state.observe(s); s.MobileEffects.enable(s,s.MobileEffects.PROFILE)
	npc.level = 2; npc.equipped_abilities = ["GOBLIN_SHIV/pierced","GOBLIN_SHIV/cut"]; npc.essences = {"GOBLIN_SHIV/pierced":1,"GOBLIN_SHIV/cut":1}
	var time_before: int = s.time; var roll_before: int = s.roll_serial
	for viewport in [Vector2i(320,568),Vector2i(390,844)]:
		root.size = viewport; scene.refresh(); await process_frame
		scene.on_cell(npc.pos)
		for _i in range(4): await process_frame
		check(scene.details_popup.visible and scene.modal_content.find_children("NpcStone_*","PanelContainer",true,false).size() == 2,"a visible distant NPC can be inspected with both stones")
		var stone_card: Node = scene.modal_content.find_children("NpcStone_*","PanelContainer",true,false)[0]
		check(stone_card.find_children("*","TextureRect",true,false)[0].texture == Icons.stone_icon(str(npc.equipped_abilities[0])),"NPC stone cards use the coloured soulstone icon")
		check(scene.find_child("ProposeButton",true,false).disabled and not s.propose(npc).accepted and s.time == time_before and s.roll_serial == roll_before,"distant inspection cannot recruit or advance the world")
		check(scene.details_popup.size.x <= scene.get_viewport_rect().size.x and scene.details_popup.size.y <= scene.get_viewport_rect().size.y,"NPC inspection stays inside the mobile viewport (popup %s, viewport %s)" % [scene.details_popup.size,scene.get_viewport_rect().size])
		check(scene.modal_content.find_child("StoneStats",true,false).text == EssenceTab.stat_line("GOBLIN_SHIV/pierced",npc),"NPC stone rewards use the actor's current combat profile")
		scene.details_popup.hide()
	npc.pos = c+Vector2i.RIGHT; s.floor_state.observe(s); s.pending_offer = npc.id
	scene.Popups.update_offer_popup(scene)
	for _i in range(3): await process_frame
	check(scene.offer_popup.visible and scene.offer_content.find_children("OfferNpcStone_*","PanelContainer",true,false).size() == 2 and scene.offer_content.find_child("OfferNpcLevel",true,false).text == "Lv.2 · 공격","an NPC's own offer also reveals its full build before acceptance (red stone → 공격)")
	scene.offer_popup.hide(); s.pending_offer = -1
	scene.details_popup.hide(); scene.queue_free(); await process_frame
	print("Inspect UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
