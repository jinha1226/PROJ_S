extends SceneTree
## Six permanent absorptions: inventory entry, honest effects, details and mobile fit.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
const Summary = preload("res://expedition/ui/screens/essence_summary.gd")
const Effects = preload("res://expedition/progression/stone_effects.gd")
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
func open_bag(scene, id: String) -> void:
	scene.item_popup.hide(); scene.details_popup.hide()
	scene.inventory_filter = "파츠"; scene.show_supplies(); scene.show_item_detail(Essences.canonical(id))
	await frames(3)
func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await frames(4)
	s.phase = "CAMP"
	var hero: Dictionary = s.party[0]
	s.grant_part("RAT_GNAW"); s.grant_part("RAT_GNAW"); s.grant_part("SPIDER_WEB")
	scene.show_character(0,"영혼석"); await frames(4)
	var tabs: Array = scene.modal_content.find_child("CharacterTabs",true,false).get_children().map(func(b): return b.text)
	check(tabs == ["상태","성격","기억","영혼석"],"four folio tabs")
	var grid: GridContainer = scene.modal_content.find_child("EssenceSlots",true,false)
	check(grid != null and grid.columns == 3 and grid.get_child_count() == 6,"six slots in two rows of three")
	check(button(scene,"EssenceSlot0").disabled and button(scene,"EssenceSlot1").disabled,"empty and locked slots cannot open a chooser")
	check(button(scene,"EssenceSlot1").text == "Lv.2","a locked slot shows its opening level")
	check(scene.modal_content.find_child("EssenceBag",true,false) == null and scene.modal_content.find_children("EssenceAbsorb_*","Button",true,false).is_empty(),"no bag stones in the folio")
	check(scene.modal_content.find_child("EssenceSets",true,false) == null,"inactive combos do not show progress rows")
	await open_bag(scene,"RAT_GNAW")
	var absorb := button(scene,"BagAbsorb0")
	check(absorb != null and not absorb.disabled,"inventory offers absorption at camp")
	if absorb != null: absorb.pressed.emit()
	await frames(3)
	check(Essences.absorbed(hero,"RAT_GNAW") and hero.equipped_abilities[0] == Essences.canonical("RAT_GNAW"),"inventory absorption applies the stone immediately")
	check(int(s.parts_bag[Essences.canonical("RAT_GNAW")]) == 1,"exactly one copy consumed")
	await open_bag(scene,"RAT_GNAW")
	check(button(scene,"BagAbsorb0").disabled and button(scene,"BagAbsorb0").text.contains("이미 흡수함"),"duplicates are disabled")
	await open_bag(scene,"SPIDER_WEB")
	check(button(scene,"BagAbsorb0").disabled and button(scene,"BagAbsorb0").text.contains("가득 참"),"a full row disables absorption")
	s.gain_level_xp(hero,65); s.phase = "BATTLE"
	await open_bag(scene,"SPIDER_WEB")
	check(button(scene,"BagAbsorb0").disabled,"battle still prevents absorption into a free slot")
	s.phase = "CAMP"
	await open_bag(scene,"SPIDER_WEB")
	check(not button(scene,"BagAbsorb0").disabled,"level two opens room for another absorption")
	button(scene,"BagAbsorb0").pressed.emit(); await frames(3)
	scene.item_popup.hide(); scene.details_popup.hide(); scene.show_character(0,"영혼석"); await frames(4)
	var sets: Node = scene.modal_content.find_child("EssenceSets",true,false)
	check(sets != null and sets.find_children("*","Label",true,false).any(func(l): return l.text.begins_with("지원 ·")),"only the active support bonus shows")
	check(sets != null and not sets.find_children("*","Label",true,false).any(func(l): return l.text.contains("다음") or l.text.contains("구간") or l.text.contains("2/")),"no next threshold or progress copy")
	var overview: Node = scene.modal_content.find_child("EssenceSummary",true,false)
	check(overview != null and overview.get_index() > sets.get_index(),"the combined summary follows actual combos")
	check(scene.modal_content.find_child("EssenceSummaryStats",true,false).text.contains("최대 HP +20"),"fixed stats sum both absorbed stones")
	check(scene.modal_content.find_child("EssenceSummaryPassives",true,false).text == Summary.TEXT.RAT_GNAW+"\n"+Summary.TEXT.SPIDER_WEB,"all absorbed passives are briefly summarized")
	button(scene,"EssenceSlot0").pressed.emit(); await frames(3)
	check(scene.item_detail.find_child("EssenceUnequip",true,false) == null and scene.item_detail.find_children("EssencePick_*","Button",true,false).is_empty(),"details offer neither removal nor replacement")
	check(scene.item_detail.find_children("*","Label",true,false).any(func(l): return l.text == EssenceTab.effect_line("RAT_GNAW")),"details retain exact conditions and numbers")
	scene.item_popup.hide(); s.gain_level_xp(hero,999999)
	for id in ["FIRE_CALLER","FROST_IMP","GOBLIN_SHIV","KOBOLD_SLING"]:
		s.grant_part(id); check(s.absorb_essence(0,id).is_empty(),"automatically fills a remaining slot: "+id)
	check(hero.equipped_abilities.size() == 6 and hero.essences.size() == 6,"level ten still has six permanent stones")
	s.grant_part("BEETLE_CURL")
	await open_bag(scene,"BEETLE_CURL")
	check(button(scene,"BagAbsorb0").disabled,"a seventh stone is disabled at maximum capacity")
	EssenceTab.pick_spell(scene,0,"FIRE_CALLER"); await frames(3)
	var options: Array = scene.item_detail.find_children("EssenceSpell_*","Button",true,false)
	check(options.size() == Essences.spell_catalog("FIRE_CALLER").size(),"spells keep their character-level progression")
	if not options.is_empty():
		var chosen: String = str(options[-1].name).trim_prefix("EssenceSpell_")
		options[-1].pressed.emit(); await frames(3)
		check(chosen in hero.prepared,"spell selection survives permanent stones")
	scene.item_popup.hide()
	for viewport in [Vector2i(320,568),Vector2i(390,844),Vector2i(430,932)]:
		root.size = viewport; await frames(3)
		scene.show_character(0,"영혼석"); await frames(4)
		var logical: Vector2 = scene.get_viewport_rect().size
		check(scene.details_popup.size.x <= logical.x and scene.details_popup.size.y <= logical.y,"folio fits mobile "+str(viewport))
		var folio: Control = scene.modal_content.find_child("CharacterFolio",true,false)
		var slots: Control = scene.modal_content.find_child("EssenceSlots",true,false)
		check(slots.get_global_rect().position.x >= folio.get_global_rect().position.x and slots.get_global_rect().end.x <= folio.get_global_rect().end.x,"six cells do not stretch horizontally")
	scene.show_character(0,"파츠"); await frames(3)
	check(scene.character_tab == "영혼석","the old tab alias remains compatible")
	# Every concrete passive has deliberately authored compact copy.
	for id in Essences.catalog():
		var effect: String = Effects.effect_of(str(id))
		if effect.is_empty(): continue
		check(Summary.TEXT.has(effect) and not str(Summary.TEXT[effect]).is_empty(),"summary coverage: "+effect)
	var repeated := {"equipped_abilities":["RAT_GNAW","RAT_GNAW@ice"]}
	check(Summary.passives(repeated) == Summary.TEXT.RAT_GNAW,"variants do not duplicate a once-only passive")
	repeated.sealed = {Essences.canonical("RAT_GNAW"):9}
	check(Summary.stats(repeated).contains("냉기 저항 +10%"),"unsealed variant stats remain visible")
	repeated.sealed[Essences.canonical("RAT_GNAW@ice")] = 9
	check(Summary.passives(repeated).is_empty() and Summary.stats(repeated).is_empty(),"sealed effects are excluded from applied totals")
	scene.queue_free(); await process_frame
	print("Essence UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
