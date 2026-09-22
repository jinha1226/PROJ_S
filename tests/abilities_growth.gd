extends SceneTree
const Session = preload("res://expedition/session.gd")
var failures := 0
func check(ok: bool, why: String) -> void:
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("exercise")
func arena():
	var s = Session.new(731,true,true); s.depart()
	for cell in s.tiles: cell.terrain = "stone"; cell.fire = 0; cell.wet = 0
	return s
func exercise() -> void:
	var dropped := 0
	for seed_value in range(30):
		var s = Session.new(seed_value,true,true); s.depart()
		var enemy: Dictionary = s.enemies[0]
		s.log_lines.clear()
		s.damage(enemy,999,0,"SLASH")
		check(s.log_lines[0].contains("쓰러졌습니다"),"lethal damage and defeat are logged before XP and drops")
		var count: int = s.essences.get("SHOCKWAVE",0)
		dropped += count
		check(s.party[0].growth.xp == 100 and s.party[1].growth.xp == 100,"shared XP without last-hit competition")
		check(s.party[0].growth.level == 2 and s.party[0].max_hp == 59,"level increases base HP")
		s.roll_essence(enemy); s.damage(enemy,999,0,"SLASH")
		check(s.essences.get("SHOCKWAVE",0) == count and s.party[0].growth.xp == 100,"death cannot reward twice")
	check(dropped > 0 and dropped < 30,"seeded drop includes both success and failure")
	var s = arena()
	s.essences = {"SHOCKWAVE":2,"BOMB":1,"IRON_HIDE":1}
	check(not s.consume_essence(0,"SHOCKWAVE"),"cannot eat in battle")
	s.phase = "EXPLORE"
	check(s.consume_essence(1,"SHOCKWAVE") and s.essences.SHOCKWAVE == 1,"selected companion consumes exactly one")
	check("SHOCKWAVE" not in s.party[0].learned_abilities,"learning is per-character")
	check(not s.consume_essence(1,"SHOCKWAVE") and s.essences.SHOCKWAVE == 1,"duplicate does not consume")
	check(s.equip_ability(1,0,"SHOCKWAVE") and not s.equip_ability(1,1,"SHOCKWAVE"),"two slots without duplicate equip")
	check(not s.equip_ability(0,0,"BOMB") and not s.equip_ability(1,2,"SHOCKWAVE"),"unlearned and invalid slots rejected")
	check(s.consume_essence(0,"BOMB") and s.equip_ability(0,0,"BOMB"),"hero can equip acquired skill")
	s.reset_rules(1)
	check(s.party[1].rules.any(func(r): return r.skill == "SHOCKWAVE"),"reset retains acquired rule")
	s.phase = "BATTLE"
	# Two cells away: inside the shockwave radius but out of contact, so the
	# default guard rules stay silent and the acquired skill decides.
	s.party[0].pos = Vector2i(0,0); s.party[1].pos = Vector2i(3,3); s.enemies[0].pos = Vector2i(5,3); s.enemies[0].recovery = 20
	check(s.Tactics.choose(s,s.party[1]).kind == "SHOCKWAVE","companion AI can select acquired skill")
	check(s.reserve_action(1,"SHOCKWAVE",s.party[1].pos),"acquired skill can be reserved")
	var hp: int = s.enemies[0].hp
	s.act("WAIT",s.party[0].pos)
	check(s.enemies[0].hp < hp and s.party[1].cooldowns.SHOCKWAVE == 3,"reserved skill executes once and cooldown starts")
	check(not s.reserve_action(1,"SHOCKWAVE",s.party[1].pos),"cooldown blocks reservation")
	s.party[1].cooldowns.clear(); s.party[0].pos = Vector2i(2,3)
	check(s.Tactics.choose(s,s.party[1]).kind != "SHOCKWAVE","AI avoids area friendly fire")
	s.party[0].pos = Vector2i(1,1); s.enemies[0].pos = Vector2i(4,1); s.party[1].pos = Vector2i(7,7)
	hp = s.enemies[0].hp
	check(s.act("BOMB",s.enemies[0].pos) and s.enemies[0].hp < hp,"direct bomb has real damage")
	s.phase = "EXPLORE"
	check(s.consume_essence(1,"IRON_HIDE") and s.equip_ability(1,1,"IRON_HIDE"),"iron hide can be acquired")
	s.phase = "BATTLE"; s.selected = 1
	check(s.Abilities.execute(s,s.party[1],"IRON_HIDE",s.party[1].pos),"iron hide executes")
	hp = s.party[1].hp; s.damage(s.party[1],16,100,"IMPACT")
	check(s.party[1].hp == hp-4,"iron hide mitigates real damage")
	s.phase = "EXPLORE"
	s.Growth.gain(s.party[0],400)
	check(s.party[0].growth.level == 3 and s.party[0].growth.stat_points == 1,"stat point every three levels")
	check(s.spend_growth(0,"STR",true) and not s.spend_growth(0,"STR",true),"stat budget enforced")
	check(s.spend_growth(0,"MELEE") and s.Growth.power(s.party[0],"MELEE",18) > 18,"mastery affects power")
	check(s.spend_growth(0,"DEFENSE") and s.Growth.incoming(s.party[0],100) == 96,"defense affects incoming damage")
	check(not s.spend_growth(0,"INVALID") and not s.spend_growth(-1,"MELEE"),"invalid growth choices rejected")
	var scene = load("res://expedition/main.tscn").instantiate(); root.size = Vector2i(390,844); root.add_child(scene)
	scene.session = s; scene.refresh()
	for tab in ["이능","숙련","상태"]:
		scene.show_character(1,tab)
		for frame in range(3): await process_frame
		check(scene.details_popup.size.y <= root.size.y and scene.details_popup.size.x <= root.size.x,"character tab fits mobile: "+tab)
		var labels: Array = scene.modal_content.find_children("*","Label",true,false)
		if tab == "숙련": check(not labels.any(func(l): return l.text == "스킬 사용 순서"),"mastery has no ability ordering")
		if tab == "이능": check(scene.modal_content.find_children("EquippedAbility*","PanelContainer",true,false).size() == 2,"ability tab shows only two equipped cards")
		check(not scene.modal_content.find_children("*","Button",true,false).any(func(b): return b.text == "가방"),"character window has no bag tab")
	scene.show_essences(); await process_frame
	scene.confirm_essence(0,"SHOCKWAVE"); await process_frame
	check(scene.details_popup.visible,"consumption requires recipient confirmation")
	scene.inventory_filter = "전체"; scene.show_supplies()
	for frame in range(3): await process_frame
	check(scene.inventory_slots.size() >= 12,"inventory displays grid slots")
	for slot in scene.inventory_slots:
		check(slot.size.x >= 44 and slot.size.y >= 44,"inventory touch targets")
	scene.show_item_detail("supply:0")
	await process_frame
	check(scene.item_popup.visible and scene.item_popup.size.x <= root.size.x,"item detail popup fits")
	check(scene.item_popup.get_parent() == scene.details_popup and scene.item_popup.transient and scene.item_popup.exclusive,"item details belong above inventory modal")
	scene.item_popup.hide(); scene.inventory_filter = "이능"; scene.show_supplies()
	check(scene.inventory_slots.all(func(slot): return slot.row.is_empty() or slot.row.category == "이능"),"category filter contains only essences")
	for viewport in [Vector2i(360,800),Vector2i(390,844),Vector2i(430,844)]:
		root.size = viewport; scene.show_supplies()
		for frame in range(3): await process_frame
		check(scene.details_popup.size.x <= root.size.x and scene.details_popup.size.y <= root.size.y,"inventory fits mobile viewport")
	var supply_test = arena()
	supply_test.party[1].hp = 20; supply_test.enemies[0].recovery = 30
	var turn: int = supply_test.round_number
	check(supply_test.use_supply(0,Vector2i(-1,-1),1),"shared potion can target companion")
	check(supply_test.party[1].hp == 40 and supply_test.selected == 0 and supply_test.round_number == turn+1 and supply_test.supplies[0] == 1,"recipient healing keeps leader and consumes one turn and item")
	supply_test.party[1].hp = supply_test.party[1].max_hp
	check(not supply_test.use_supply(0,Vector2i(-1,-1),1) and supply_test.supplies[0] == 1,"invalid recipient effect does not consume")
	check(not supply_test.use_supply(0,Vector2i(-1,-1),99),"invalid recipient rejected")
	scene.queue_free(); await process_frame
	print("Abilities and growth: %d failures" % failures); quit(1 if failures else 0)
