extends SceneTree
## Per-stone spell ownership, permanent choices, migration and mobile access.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Tab = preload("res://expedition/ui/screens/essence_tab.gd")
const Hud = preload("res://expedition/ui/screens/floor_hud.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	catalog(); ownership(); growth(); migration(); casting()
	await ui_access()
	print("Stone magic: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func catalog() -> void:
	var linked: Array = []
	var count := 0
	for id in Essences.catalog():
		var raw: Array = Essences.row(id).spells
		var spells := Essences.spell_catalog(id)
		check(raw.size() == spells.size(),"every linked spell exists and is unique: "+str(id))
		if not spells.is_empty(): count += 1
		for spell in spells:
			check(str(spell) in Spells.schooled(),"linked spell has an implemented shape: "+str(spell))
			check(Essences.spell_catalog(str(id)+"@fire") == spells,"variants retain the part's explicit spell list")
			if spell not in linked: linked.append(spell)
	check(count == 31 and linked.size() == 50,"all fifty existing spells are distributed over thirty-one related stones")
	check(Essences.spell_catalog("RAT_GNAW").is_empty(),"unrelated physical stones gain no hidden school spells")
	check("fire_3" in Essences.spell_catalog("FIRE_CALLER/cut") and "fire_3" not in Essences.spell_catalog("FIRE_CALLER/broken"),"hand attacks and bone specializes in charges/walls")
	check("ice_6" in Essences.spell_catalog("WATER_WAVE/cut") and "hex_3" in Essences.spell_catalog("SPIDER_WEB/pierced"),"water grants an ice wall, spider a binding curse")
	for part in ["cut","broken","pierced"]:
		check(str(Essences.row("GRAVEKEEPER/"+part).active) == "BONE_CALL","every gravekeeper stone includes actual skeleton summoning")

func ownership() -> void:
	var s = Session.new_run(711); Fixture.arena(s); s.phase = "CAMP"
	var hero: Dictionary = s.party[0]; hero.level = 10
	var ids := ["FIRE_CALLER/cut","FIRE_CALLER/broken","FIRE_CALLER/pierced","FROST_IMP/pierced","GOBLIN_HEXER/pierced","GNOLL_SUMMONER/pierced"]
	var selected := ["fire_3","fire_6","fire_9","ice_8","hex_9","summon_9"]
	for i in range(ids.size()):
		s.grant_part(ids[i]); check(s.absorb_essence(0,ids[i]).is_empty(),"absorbed linked stone: "+ids[i])
		check(s.choose_essence_spell(0,ids[i],selected[i]),"chooses own linked spell: "+selected[i])
	check(hero.prepared == selected,"all six independent chosen spells are active in absorption order")
	var before: Dictionary = hero.essence_spells.duplicate()
	check(not s.choose_essence_spell(0,ids[1],"fire_9") and hero.essence_spells == before,"same school cannot choose another part's spell")
	check(not s.choose_essence_spell(0,"WRAITH","hex_1") and hero.essence_spells == before,"an unowned stone cannot select a spell")
	s.phase = "BATTLE"
	check(not s.choose_essence_spell(0,ids[0],"fire_1") and hero.essence_spells == before,"battle cannot modify selection")
	hero.sealed = {ids[1]:9999}; Essences.sync_spells(hero)
	check(hero.prepared.size() == 5 and "fire_6" not in hero.prepared and hero.essence_spells == before,"a seal suspends exactly that stone's spell and preserves its choice")
	hero.sealed.clear(); Essences.sync_spells(hero)
	check(hero.prepared == selected,"unsealing restores all six choices")
	s.grant_part("SOUL_EATER"); s.phase = "CAMP"
	check(s.absorb_essence(0,"SOUL_EATER") == "영혼석 가득 참" and hero.prepared == selected,"seventh stone cannot change spell ownership")

func growth() -> void:
	var s = Session.new_run(712); Fixture.arena(s); s.phase = "CAMP"
	var hero: Dictionary = s.party[0]
	s.grant_part("SPIDER_WEB/pierced")
	check(s.absorb_essence(0,"SPIDER_WEB/pierced").is_empty() and hero.prepared.is_empty(),"a high-level spell stays locked while the stone's passive applies")
	check(not s.choose_essence_spell(0,"SPIDER_WEB/pierced","hex_3"),"locked binding cannot be selected early")
	s.gain_level_xp(hero,260)
	check(hero.level == 3 and hero.prepared == ["hex_3"],"level-up automatically readies a previously locked stone's first spell")
	check(Essences.school_slotted(hero,"hex"),"a linked curse gets school support without changing stone stats")
	hero.sealed = {"SPIDER_WEB/pierced":9999}; Essences.sync_spells(hero)
	check(not Essences.school_slotted(hero,"hex") and hero.prepared.is_empty(),"a sealed link provides no school support or prepared spell")

func migration() -> void:
	var actor := {"level":6,"essences":{"FIRE_CALLER/cut":1,"FIRE_CALLER/broken":1},"equipped_abilities":["FIRE_CALLER/cut","FIRE_CALLER/broken"],"essence_spells":{"FIRE_CALLER/cut":"fire_3","FIRE_CALLER/broken":"fire_3"}}
	Essences.sync_spells(actor)
	check(actor.prepared == ["fire_3","fire_1"],"migration preserves a valid hand choice and repairs an unlinked bone choice")
	actor.essence_spells["FIRE_CALLER/broken"] = "fire_6"; Essences.sync_spells(actor)
	check(actor.prepared == ["fire_3","fire_6"],"repeated synchronization never merges part choices")

func casting() -> void:
	var s = Session.new_run(713); var c := Fixture.arena(s)
	var hero: Dictionary = s.party[0]; hero.level = 10; s.phase = "CAMP"
	s.grant_part("WATER_WAVE/cut"); s.absorb_essence(0,"WATER_WAVE/cut")
	check(s.choose_essence_spell(0,"WATER_WAVE/cut","ice_6"),"a non-caster water stone selects its real wall spell")
	s.phase = "EXPLORE"; hero.ap = 1; hero.mp = 99
	var target := c+Vector2i(2,0)
	check(Spells.can_cast(s,hero,"ice_6",target),"the linked wall is usable through ordinary spell targeting")
	# Resolve the same shape the cast uses, independent of a random failure roll.
	Spells.shaped_cast(s,hero,"ice_6",target,Spells.definition("ice_6"))
	check(Spells.cells(s,hero,"ice_6",target).any(func(p): return int(s.tile(p).get("wall_until",0)) > s.time),"the stone's spell produces an actual temporary wall")
	check(not Spells.can_cast(s,hero,"fire_9",target),"ungranted spells remain unusable")

func frames(n: int) -> void:
	for i in range(n): await process_frame

func ui_access() -> void:
	var s = Session.new_run(714); Fixture.arena(s); s.phase = "CAMP"
	var hero: Dictionary = s.party[0]; hero.level = 10
	var ids := ["FIRE_CALLER/cut","FIRE_CALLER/broken","FIRE_CALLER/pierced","FROST_IMP/pierced","GOBLIN_HEXER/pierced","GNOLL_SUMMONER/pierced"]
	var selected := ["fire_3","fire_6","fire_9","ice_8","hex_9","summon_9"]
	for i in range(ids.size()):
		s.grant_part(ids[i]); s.absorb_essence(0,ids[i]); s.choose_essence_spell(0,ids[i],selected[i])
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false); await frames(4)
	Hud.show_manual_skills(scene); await frames(3)
	check(scene.modal_content.find_children("Spell_*","Button",true,false).size() == 6 and scene.modal_content.find_child("Spell_summon_9",true,false) != null,"the skills menu includes the sixth spell beyond five HUD shortcuts")
	scene.details_popup.hide(); s.grant_part("WATER_WAVE/cut")
	scene.show_supplies(); scene.show_item_detail("WATER_WAVE/cut"); await frames(3)
	check(scene.item_detail.find_child("EssenceSpellPreview_ice_6",true,false) != null,"inventory previews linked spells before irreversible absorption")
	scene.item_popup.hide()
	hero.level = 1
	Tab.pick_spell(scene,0,"FIRE_CALLER/cut"); await frames(3)
	check(not scene.item_detail.find_child("EssenceSpell_fire_1",true,false).disabled and scene.item_detail.find_child("EssenceSpell_fire_3",true,false).disabled,"picker shows a later spell with its level and disables it")
	scene.item_popup.hide(); hero.level = 10
	for size in [Vector2i(320,568),Vector2i(390,844),Vector2i(430,932)]:
		root.size = size; scene.refresh(); await frames(4)
		check(scene.root_layout.get_global_rect().end.x <= scene.get_viewport_rect().size.x+1,"six spells do not widen the five-button HUD: "+str(size))
		scene.tactics_actor = 0
		for id in ids:
			Tab.slot_detail(scene,0,id); await frames(3)
			check(scene.item_popup.size.x <= scene.get_viewport_rect().size.x and scene.item_popup.size.y <= scene.get_viewport_rect().size.y,"stone spell details fit the mobile viewport: "+str(size)+" "+id+" "+str(scene.item_popup.size))
			scene.item_popup.hide()
		Tab.pick_spell(scene,0,"FIRE_CALLER/pierced"); await frames(3)
		check(scene.item_popup.size.x <= scene.get_viewport_rect().size.x and scene.item_popup.size.y <= scene.get_viewport_rect().size.y,"spell picker fits mobile viewport: "+str(size))
		scene.item_popup.hide()
	scene.queue_free(); await frames(1)
