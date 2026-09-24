extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func run() -> void:
	var s = Session.new(901,false,false,true,1)
	s.depart(); Fixture.arena(s,10); s.manual_mode = true
	var hero: Dictionary = s.party[0]
	# The port's own spells belong to no book: nothing teaches them any more.
	for id in ["bolt","blast","blink","confuse","mend","cone"]:
		check(not s.learn_spell(0,id),"no book teaches the relic "+id)
		hero.spells.append(id)
	s.phase = "CAMP"
	check(s.prepare_spell(0,"bolt",true) and s.prepare_spell(0,"mend",true) and s.prepare_spell(0,"blink",true),"prepare three spells")
	check(s.prepare_spell(0,"blast",true) and s.prepare_spell(0,"confuse",true),"prepare five spells")
	check(not s.prepare_spell(0,"cone",true),"sixth spell refused")
	s.phase = "EXPLORE"
	var foe: Dictionary = s.enemies[0]
	foe.hp = 100; foe.max_hp = 100; foe.pos = hero.pos+Vector2i(2,0); foe.alert = true; foe.ready_at = 1000
	s.floor_state.observe(s)
	var before: int = foe.hp
	check(s.cast("bolt",foe.pos),"bolt cast")
	check(foe.hp < before or hero.mp == 15,"bolt damages or fails after spending 3 MP")
	hero.hp = 20; hero.mp = 18
	check(s.cast("mend",hero.pos),"mend cast")
	check(hero.hp > 20 or hero.mp == 12,"mend heals or fails after spending 6 MP")
	s.phase = "CAMP"
	s.grant_gear({"type":"bow"}); s.grant_gear({"type":"shield"})
	check(s.equip_gear(0,{"type":"bow"}),"equip bow at camp")
	check(not s.equip_gear(0,{"type":"shield"}),"two-handed bow rejects shield")
	check(s.unequip_gear(0,"weapon"),"unequip bow")
	check(s.equip_gear(0,{"type":"shield"}),"equip shield after bow removed")
	s.grant_gear({"type":"sword"})
	var scene = load("res://expedition/main.tscn").instantiate()
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene)
	await process_frame
	scene.inventory_filter = "장비"; scene.show_supplies(); await process_frame
	check(scene.inventory_slots.any(func(slot): return slot.row.get("category","") == "장비" and slot.row.get("label","") == "장검"),"bag equipment tab shows named gear")
	var sword_row: Dictionary = scene.inventory_rows().filter(func(row): return row.get("label","") == "장검")[0]
	scene.show_item_detail(sword_row.id); await process_frame
	var equip_button: Button = scene.item_detail.find_children("*","Button",true,false).filter(func(entry): return entry.text.contains("장착"))[0]
	check(not equip_button.disabled,"bag can equip gear at camp")
	equip_button.pressed.emit(); await process_frame
	check(str(hero.gear.weapon.get("type","")) == "sword","bag equips the selected sword")
	check(scene.inventory_rows().any(func(row): return row.get("id","") == "equipped:0:weapon" and row.get("category","") == "장비"),"equipment tab also shows worn gear")
	scene.show_item_detail("equipped:0:weapon"); await process_frame
	var unequip_button: Button = scene.item_detail.find_children("*","Button",true,false).filter(func(entry): return entry.text == "해제")[0]
	unequip_button.pressed.emit(); await process_frame
	check(hero.gear.weapon.is_empty() and s.gear_bag.any(func(item): return item.get("type","") == "sword"),"equipped gear can return to bag at camp")
	scene.queue_free(); await process_frame
	s.phase = "EXPLORE"
	check(not s.unequip_gear(0,"shield"),"gear change unavailable outside camp")
	print("Model B spells and gear: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
