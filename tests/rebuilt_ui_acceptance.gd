extends SceneTree

const Game=preload("res://game/rebuilt/game.gd")
var failures:Array[String]=[]

func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)

func _init()->void:run.call_deferred()

func run()->void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(360,800)
	var game=Game.new();game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(game);game.save_allowed=false
	game.world=game.World.new();game.refresh(false)
	await process_frame;await process_frame
	check(game.board.size.y>=180 and game.board.get_global_rect().end.x<=360,"mobile board fits")
	check(game.growth_button.get_global_rect().end.x<=360 and game.growth_button.get_global_rect().end.y<=800,"mobile dock fits")
	check(game.hp_gauge.value==game.world.hero().hp and game.mp_gauge.value==game.world.hero().mp,"legacy gauges read new world")
	check(game.auto_button.get_meta("visual_family")==game.DarkSkin.VISUAL_FAMILY,"existing action skin reused")
	game.world.auto_explore=true;game.timer.start();game.targeting="SHOOT"
	game.show_status();await process_frame;await process_frame
	check(not game.world.auto_explore and game.timer.is_stopped() and game.targeting.is_empty(),"opening panel cancels travel and targeting")
	check(game.gear_dialog.tabs.current_tab==3 and game.gear_dialog.body_text.text.contains("혈액"),"status opens live body tab")
	check(game.gear_dialog.size.x<=360,"character dialog fits mobile width")
	game.gear_dialog.hide();game.show_character(1)
	check(game.gear_dialog.tabs.current_tab==1,"bag opens equipment directly")
	var index:int=game.world.inventory.find("BOW")
	game.gear_dialog.equipment.select(index)
	game.gear_dialog.equip_button.pressed.emit()
	check(game.world.hero().gear.weapon=="BOW" and not game.shot_button.disabled,"equipment signal updates action availability")
	game.gear_dialog.hide();game.begin_target("SHOOT")
	check(game.targeting=="SHOOT" and game.shot_button.text=="취소","shoot action starts target mode")
	game.show_menu()
	check(game.targeting.is_empty() and game.menu_dialog.visible,"menu cancels targeting")
	game.menu_dialog.hide()
	game.world.hero().bound_abilities=["FIREBOLT"];game.world.hero().mp=0;game.refresh(false)
	check(game.fire_button.disabled,"MP shortage disables spell")
	game.world.hero().mp=20;game.refresh(false)
	check(not game.fire_button.disabled,"MP recovery refreshes spell availability")
	game.world.Growth.gain(game.world.hero(),100);game.refresh(false)
	check(game.growth_button.text.contains("1P"),"earned point appears on dock")
	game.show_equipment();game.gear_dialog.preview_invest(3)
	await process_frame;await process_frame
	check(game.gear_dialog.confirm.size.x<=360 and game.gear_dialog.confirm.dialog_text.contains("보호"),"defense preview fits and reports equipment values")
	game.gear_dialog.confirm.canceled.emit();game.gear_dialog.confirm.hide();game.gear_dialog.hide()
	check(game.world.hero().growth.ranks.DEFENSE==0 and game.world.hero().growth.points==1,"defense preview does not mutate rank or budget")
	game.world.hero().hp-=5;game.refresh(false)
	check(game.hp_gauge.value==game.world.hero().hp,"damage refreshes gauge")
	game.show_party();await process_frame;await process_frame
	check(game.party_dialog.size.x<=360,"party body details fit mobile width")
	game.party_dialog.hide()
	game.save_timer.stop();game.queue_free();await process_frame
	print("REBUILT UI: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
