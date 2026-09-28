extends SceneTree
const Scene = preload("res://expedition/ui/main.tscn")
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func frames() -> void:
	await process_frame; await process_frame; await process_frame
func run() -> void:
	var ui = Scene.instantiate(); root.add_child(ui); await frames()
	ui.new_run(); await frames()
	var s = ui.session; Fixture.arena(s,8); s.npcs.clear(); s.events.clear()
	s.MobileEffects.enable(s,Session.MobileEffects.PROFILE)
	s.party.append(s.make_actor(1,"브란",false)); s.party.append(s.make_actor(2,"세라",false))
	for actor in s.party: actor.level = 6; actor.equipped_abilities = []; actor.essences = {}
	s.Essences.bind(s.party[0],"FIRE_CALLER/pierced")
	s.party[2].hp = 0
	s.grant_part("FIRE_CALLER/cut",true); ui.refresh(); await frames()
	check(ui.stone_drop_card.visible and ui.popup_open(),"loot opens an exclusive card without selecting a character")
	check(ui.find_child("StoneDropTitle",true,false).text == s.Essences.title("FIRE_CALLER/cut"),"card displays the concrete stone name")
	check(ui.find_child("StoneDropStats",true,false) == null and ui.find_child("StoneDropIcon",true,false).texture != null,"card shows one effect icon and keeps fixed stats in details")
	check(ui.find_child("StoneDropEffect",true,false).text.contains("화상"),"card displays actual effect")
	check(ui.find_child("StoneDropFit_0",true,false).text.contains("연계") and ui.find_child("StoneDropFit_1",true,false).text.contains("준비 필요"),"fit is evaluated independently for hero and companion")
	check(ui.find_child("StoneDropAbsorb_2",true,false).disabled,"downed member button is disabled")
	check(not s.auto.running and not ui.navigation.active,"card stops auto exploration and navigation")
	var tick: int = s.time
	ui.on_cell(s.party[0].pos+Vector2i.RIGHT)
	check(s.time == tick,"board taps cannot move under the card")
	for dimensions in [Vector2i(320,568),Vector2i(390,844),Vector2i(430,932)]:
		ui.stone_drop_card.dismiss_preserving()
		root.size = dimensions; ui.size = Vector2(dimensions); ui.refresh(); await frames()
		var card = ui.stone_drop_card
		check(card.size.x <= dimensions.x and card.size.y <= dimensions.y,"card fits viewport %s: card=%s viewport=%s ui=%s" % [dimensions,card.size,ui.get_viewport_rect().size,ui.size])
		check(card.scroll.size.x <= card.size.x and card.content.size.x <= card.scroll.size.x,"text and three member cards never widen popup "+str(dimensions))
		check(card.scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,"mobile card scrolls only vertically")
	ui.find_child("StoneDropAbsorb_1",true,false).pressed.emit(); await frames()
	check(s.pending_stone_drops.is_empty() and s.Essences.absorbed(s.party[1],"FIRE_CALLER/cut"),"companion button permanently absorbs for that companion")
	s.grant_part("FIRE_CALLER/broken",true); s.grant_part("RAT_GNAW/cut",true); await frames()
	var old_token: int = ui.stone_drop_card.token
	ui.find_child("StoneDropKeep",true,false).pressed.emit(); await frames()
	check(s.pending_stone_drops.size() == 1 and ui.stone_drop_card.visible and ui.stone_drop_card.token != old_token,"AoE loot advances one card at a time")
	ui.stone_drop_card.choose(-2,s,old_token)
	check(s.pending_stone_drops.size() == 1,"old card callbacks cannot accept the next card")
	ui.find_child("StoneDropLeave",true,false).pressed.emit(); await frames()
	check(s.parts_bag["FIRE_CALLER/broken"] == 1 and s.parts_bag["RAT_GNAW/cut"] == 0,"keep preserves loot and leave discards only its own copy")
	s.grant_part("RAT_GNAW/broken",true); await frames(); ui.stone_drop_card.hide(); await frames()
	check(s.pending_stone_drops.is_empty() and s.parts_bag["RAT_GNAW/broken"] == 1,"closing card safely keeps loot and releases the action lock")
	# A competing modal has priority, without resolving the underlying stone.
	ui.details_popup.popup_centered(); s.grant_part("RAT_GNAW/pierced",true); await frames()
	check(not ui.stone_drop_card.visible and s.pending_stone_drops.size() == 1,"existing item modal is not replaced by loot")
	ui.details_popup.hide(); await frames()
	check(ui.stone_drop_card.visible,"queued card opens after prior modal closes")
	ui.show_arena_setup(); await frames()
	check(not ui.stone_drop_card.visible and s.pending_stone_drops.size() == 1,"changing screens hides card without accepting loot")
	ui.mode_arena_setup = false; ui.refresh(); await frames()
	check(ui.stone_drop_card.visible,"returning to run restores its outstanding choice")
	ui.new_run(); await frames()
	check(not ui.stone_drop_card.visible and s.pending_stone_drops.size() == 1,"new session cannot resolve old session's loot")
	ui.queue_free(); await frames()
	print("Stone drop UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
