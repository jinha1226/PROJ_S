extends SceneTree
const Session = preload("res://expedition/run/session.gd")
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
		check(s.log_lines.size() >= 2 and s.log_lines[0].contains("피해를 주었습니다") and s.log_lines[1].contains("쓰러졌습니다"),"damage and defeat use separate log lines before XP and drops")
		var count: int = s.parts_bag.get(enemy.part_id,0)
		dropped += count
		check(int(s.party[0].level_xp) == 18+s.depth*8 and int(s.party[1].level_xp) == 18+s.depth*8,"shared XP without last-hit competition")
		check(int(s.party[0].level) == 1 and s.party[0].max_hp == 55,"one floor kill does not skip a level")
		s.roll_part(enemy); s.damage(enemy,999,0,"SLASH")
		check(s.parts_bag.get(enemy.part_id,0) == count and int(s.party[0].level_xp) == 18+s.depth*8,"death cannot reward twice")
	check(dropped == 30,"the first of a species always drops (%d of 30)" % dropped)
	var s = arena()
	s.phase = "CAMP"
	s.gain_level_xp(s.party[1],65)
	s.parts_bag = {"WATER_WAVE":2,"GOBLIN_AIM":1,"FURNACE_HEART":1}
	check(s.equip_part(1,0,"WATER_WAVE") and s.parts_bag.WATER_WAVE == 1,"equipping takes exactly one soul stone from the bag")
	check(not s.equip_part(1,1,"WATER_WAVE"),"the same stone cannot fill both slots")
	check(not s.equip_part(0,0,"NOPE") and not s.equip_part(1,2,"WATER_WAVE"),"unknown stone and invalid slot rejected")
	check(s.equip_part(0,0,"GOBLIN_AIM"),"hero can equip a stone from the shared bag")
	s.reset_rules(1)
	check(s.party[1].rules.any(func(r): return r.skill == "WATER_WAVE"),"reset retains acquired rule")
	s.phase = "BATTLE"
	for foe in s.enemies: foe.hp = 0
	s.party[0].pos = Vector2i(0,0); s.party[1].pos = Vector2i(3,3); s.enemies[0].pos = Vector2i(4,3); s.enemies[0].hp = 100; s.enemies[0].recovery = 20
	s.floor_state.observe(s)
	check(s.reserve_action(1,"WATER_WAVE",s.enemies[0].pos),"acquired stone can be reserved")
	var hp: int = s.enemies[0].hp
	s.act("WAIT",s.party[0].pos)
	check(s.enemies[0].hp < hp and int(s.party[1].cooldowns.get("WATER_WAVE",0)) > 0,"reserved wave executes and starts cooldown")
	check(not s.reserve_action(1,"WATER_WAVE",s.enemies[0].pos),"cooldown blocks reservation")
	s.party[0].pos = Vector2i(1,1); s.enemies[0].pos = Vector2i(4,1); s.party[1].pos = Vector2i(7,7)
	s.floor_state.observe(s)
	hp = s.enemies[0].hp
	check(s.act("GOBLIN_AIM",s.enemies[0].pos) and s.enemies[0].hp < hp,"direct aimed shot deals damage")
	s.phase = "CAMP"
	check(s.equip_part(1,1,"FURNACE_HEART"),"furnace heart can be equipped")
	s.phase = "BATTLE"; s.selected = 1
	check(s.Abilities.execute(s,s.party[1],"FURNACE_HEART",s.party[1].pos),"furnace armour activates")
	hp = s.party[1].hp; s.damage(s.party[1],20,100,"IMPACT")
	check(s.party[1].hp == hp-12,"furnace armour mitigates forty percent")
	s.phase = "CAMP"
	s.gain_level_xp(s.party[0],65*1+65*4)
	check(int(s.party[0].level) == 3 and s.party[0].equipped_abilities.size() == 3,"three levels, three slots")
	check(not s.has_method("spend_growth"),"no points to spend any more")
	s.parts_bag["ORC_CLEAVER"] = 1
	var strength: int = int(s.StatSheet.value(s,s.party[0],"str"))
	var attack: int = int(s.StatSheet.value(s,s.party[0],"atk"))
	check(s.equip_part(0,2,"ORC_CLEAVER") and int(s.StatSheet.value(s,s.party[0],"atk")) == attack+4 and int(s.StatSheet.value(s,s.party[0],"str")) == strength,"an essence raises attack, not strength")
	check(s.Abilities.power(s,s.party[0],s.Abilities.definition("ORE_SLAM"),"ORE_SLAM") == int(s.Abilities.definition("ORE_SLAM").damage)+maxi(0,strength-10)/2,"a part's blow still reads strength")
	check(not s.equip_part(0,5,"ORC_CLEAVER") and not s.equip_part(-1,0,"ORC_CLEAVER"),"invalid slots and members rejected")
	var scene = load("res://expedition/ui/main.tscn").instantiate(); root.size = Vector2i(390,844); root.add_child(scene)
	scene.session = s; scene.refresh()
	for tab in ["영혼석","상태"]:
		scene.show_character(1,tab)
		for frame in range(3): await process_frame
		check(scene.details_popup.size.y <= root.size.y and scene.details_popup.size.x <= root.size.x,"character tab fits mobile: "+tab)
		var labels: Array = scene.modal_content.find_children("*","Label",true,false)
		if tab == "영혼석": check(not labels.any(func(l): return l.text == "스킬 사용 순서"),"essence tab has no ability ordering")
		if tab == "영혼석": check(scene.modal_content.find_child("EssenceSlots",true,false).get_child_count() == 10,"essence tab shows ten slot cells")
		check(not scene.modal_content.find_children("*","Button",true,false).any(func(b): return b.text == "가방"),"character window has no bag tab")
	scene.inventory_filter = "전체"; scene.show_supplies()
	s.grant_item("healing",1,true); scene.show_supplies()
	for frame in range(3): await process_frame
	check(scene.inventory_slots.size() >= 12,"inventory displays grid slots")
	for slot in scene.inventory_slots:
		check(slot.size.x >= 44 and slot.size.y >= 44,"inventory touch targets")
	scene.show_item_detail("item:healing")
	await process_frame
	check(scene.item_popup.visible and scene.item_popup.size.x <= root.size.x,"item detail popup fits")
	check(scene.item_popup.get_parent() == scene.details_popup and scene.item_popup.transient and scene.item_popup.exclusive,"item details belong above inventory modal")
	scene.item_popup.hide(); scene.inventory_filter = "파츠"; scene.show_supplies()
	check(scene.inventory_slots.all(func(slot): return slot.row.is_empty() or slot.row.category == "파츠"),"category filter contains only parts")
	for viewport in [Vector2i(360,800),Vector2i(390,844),Vector2i(430,844)]:
		root.size = viewport; scene.show_supplies()
		for frame in range(3): await process_frame
		check(scene.details_popup.size.x <= root.size.x and scene.details_popup.size.y <= root.size.y,"inventory fits mobile viewport")
	var supply_test = arena()
	supply_test.grant_item("healing",2,true)
	supply_test.party[1].hp = 20; supply_test.enemies[0].recovery = 30
	var turn: int = supply_test.round_number
	check(supply_test.use_item("healing",Vector2i(-1,-1),1),"shared potion can target companion")
	check(supply_test.party[1].hp == 40 and supply_test.selected == 0 and supply_test.round_number == turn+1 and supply_test.bag.healing == 1,"recipient healing keeps leader and consumes one turn and item")
	supply_test.party[1].hp = supply_test.party[1].max_hp
	check(not supply_test.use_item("healing",Vector2i(-1,-1),1) and supply_test.bag.healing == 1,"invalid recipient effect does not consume")
	check(not supply_test.use_item("healing",Vector2i(-1,-1),99),"invalid recipient rejected")
	scene.queue_free(); await process_frame
	print("Abilities and growth: %d failures" % failures); quit(1 if failures else 0)
