extends SceneTree
## §4 영혼석 화면: the slot grid, 흡수 from the bag, equipping, sets and the
## caster's spell picker.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func frames(n: int) -> void:
	for _i in range(n): await process_frame

func button(scene, node_name: String) -> Button:
	var found: Array = scene.modal_content.find_children(node_name,"Button",true,false)+scene.item_detail.find_children(node_name,"Button",true,false)
	return found[0] if not found.is_empty() else null

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await frames(4)
	s.phase = "CAMP"
	var hero: Dictionary = s.party[0]
	s.parts_bag["RAT_GNAW"] = 2
	s.parts_bag["SPIDER_WEB"] = 1
	scene.show_character(0,"영혼석")
	await frames(4)
	var tabs: Array = scene.modal_content.find_child("CharacterTabs",true,false).get_children().map(func(b): return b.text)
	check(tabs == ["상태","성격","기억","영혼석"],"the folio has four tabs ending in 영혼석")
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("영혼석 슬롯"))
	check(not heading.is_empty() and heading[0].text == "영혼석 슬롯 0 / 1","level one: no essence worn, one slot")
	var grid: GridContainer = scene.modal_content.find_child("EssenceSlots",true,false)
	check(grid != null and grid.columns == 5 and grid.get_child_count() == 10,"ten slot cells in two rows of five")
	check(not button(scene,"EssenceSlot0").disabled and button(scene,"EssenceSlot1").disabled,"only the level's slots open")
	check(button(scene,"EssenceSlot1").text == "Lv.2","a locked slot names the level that opens it")
	# 흡수: a new essence, once; a second copy is for somebody else.
	var absorb: Button = button(scene,"EssenceAbsorb_"+Essences.canonical("RAT_GNAW").replace("/","_"))
	check(absorb != null and not absorb.disabled,"the bag offers 흡수 in camp")
	absorb.pressed.emit(); await frames(3)
	check(Essences.absorbed(hero,"RAT_GNAW") and int(s.parts_bag[Essences.canonical("RAT_GNAW")]) == 1,"흡수 takes one copy and learns the essence")
	check(scene.modal_content.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("이미 흡수함")),"the bag row now says it is absorbed")
	check(button(scene,"EssenceAbsorb_"+Essences.canonical("RAT_GNAW").replace("/","_")).disabled and s.absorb_essence(0,"RAT_GNAW") == "이미 흡수함" and int(s.parts_bag[Essences.canonical("RAT_GNAW")]) == 1,"a second copy is not for the same member")
	check(scene.modal_content.find_child("EssenceOwned",true,false) != null,"owned essences are listed")
	# Equip through the slot chooser.
	button(scene,"EssenceSlot0").pressed.emit(); await frames(3)
	var pick: Button = button(scene,"EssencePick_"+Essences.canonical("RAT_GNAW").replace("/","_"))
	check(pick != null and not pick.disabled,"the chooser lists the absorbed essence")
	pick.pressed.emit(); await frames(4)
	check(hero.equipped_abilities[0] == Essences.canonical("RAT_GNAW"),"the chooser equips into the slot")
	scene.item_popup.hide()
	# Not while enemies are awake.
	s.phase = "BATTLE"
	scene.show_character(0,"영혼석"); await frames(3)
	check(button(scene,"EssenceAbsorb_"+Essences.canonical("SPIDER_WEB").replace("/","_")).disabled,"흡수 is refused in battle")
	s.phase = "CAMP"
	# A second slot and a set.
	s.gain_level_xp(hero,65)
	check(Essences.slot_count(hero) == 2,"level two opens a second slot")
	check(s.absorb_essence(0,"SPIDER_WEB").is_empty() and s.equip_part(0,1,"SPIDER_WEB"),"a second support essence is worn")
	scene.show_character(0,"영혼석"); await frames(3)
	var sets: Node = scene.modal_content.find_child("EssenceSets",true,false)
	check(sets != null and sets.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("지원 2")),"the support set shows under the grid")
	# A caster essence and its spell.
	var caster: String = Essences.canonical(str(Essences.CASTER_BY_SCHOOL.fire))
	s.parts_bag[caster] = 1
	check(s.absorb_essence(0,caster).is_empty() and s.unequip_part(0,1) and s.equip_part(0,1,caster),"the fire caster essence is worn")
	EssenceTab.pick_spell(scene,0,caster); await frames(3)
	var options: Array = scene.item_detail.find_children("EssenceSpell_*","Button",true,false)
	check(options.size() == Essences.spell_choices(hero,caster).size() and options.size() > 0,"one button per allowed spell")
	var first: String = str(options[0].name).trim_prefix("EssenceSpell_")
	options[0].pressed.emit(); await frames(3)
	check(str(hero.essence_spells.get(Essences.canonical(str(caster)),"")) == first,"the picker sets the essence's spell")
	# The old tab name still opens the new tab.
	scene.show_character(0,"파츠"); await frames(3)
	check(scene.character_tab == "영혼석","파츠 opens 영혼석")
	scene.queue_free(); await process_frame
	print("Essence UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
