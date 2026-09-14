extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func touch(point:Vector2,pressed:bool,index:int=0,cancelled:bool=false)->void:
	var event:=InputEventScreenTouch.new();event.position=point
	event.index=index;event.pressed=pressed;event.canceled=cancelled
	root.push_input(event,true)
func mouse(point:Vector2,pressed:bool,emulated:bool=false)->void:
	var event:=InputEventMouseButton.new();event.position=point
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	if emulated:event.device=InputEvent.DEVICE_ID_EMULATION
	root.push_input(event,true)
func run():
	print("PICKER: real ready path and viewport input; no direct selection callback")
	root.size=Vector2i(390,800)
	var ui=Sandbox.new();ui.size=Vector2(390,800)
	root.add_child(ui)
	for i in range(3):await process_frame
	var button=ui.species_picker_buttons.get_child(0)
	var point:Vector2=button.get_global_rect().get_center()
	var before:int=ui.session.sim.world.world_time
	touch(point,true);touch(point,false,0,true)
	check(ui.species_picker_modal.visible,"cancelled touch does not select")
	touch(point,true)
	var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=point+Vector2(0,60)
	root.push_input(drag,true);touch(point,false)
	check(ui.species_picker_modal.visible,"drag and return does not select")
	touch(point,true);touch(point,true,1);touch(point,false,1);touch(point,false)
	check(ui.species_picker_modal.visible,"second finger cancels selection")
	touch(Vector2(2,2),true);touch(Vector2(2,2),false)
	check(ui.species_picker_modal.visible,"backdrop tap does not select")
	check(ui.session.sim.world.world_time==before,"cancelled picker gestures do not advance gameplay")
	for species_button in ui.species_picker_buttons.get_children():
		ui.show_species_picker_for_new_run()
		for i in range(2):await process_frame
		point=species_button.get_global_rect().get_center()
		var species:=str(species_button.get_meta("species_id"))
		check(ui.species_picker_panel.get_global_rect().has_point(point),species+" button inside panel")
		touch(point,true);touch(point,false)
		for i in range(2):await process_frame
		check(not ui.species_picker_modal.visible,species+" closes picker")
		check(not ui.grid.modal_open,species+" unlocks map")
		check(ui.session.player_species_id==species,species+" selected identity")
		check(ui.session.sim.world.party_encounter.expedition_cycle.phase=="DUNGEON",species+" enters dungeon")
		check(ui.session.sim.world.world_state_error().is_empty(),species+" valid world")
		check(preload("res://sim/world_item_operations.gd").equipped_requirements_error(ui.session.sim.world).is_empty(),species+" legal starter equipment")
		var journal_count:int=ui.session.command_journal.size()
		touch(point,false);mouse(point,true,true);mouse(point,false,true)
		check(ui.session.command_journal.size()==journal_count,species+" no duplicate or click-through commands")
		print("PICKER: checked ",species)
	ui.show_species_picker_for_new_run()
	for i in range(3):await process_frame
	point=button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;root.push_input(motion,true)
	mouse(point,true);mouse(point,false)
	check(not ui.species_picker_modal.visible,"native mouse still selects")
	var hero:int=ui.session.sim.world.party_control_actor_id()
	var hold:Dictionary=ui.session.commit_field_action(preload("res://sim/party_action_command.gd").hold(hero))
	check(hold.get("accepted",false),"dungeon turn accepted after selection")
	ui.queue_free();await process_frame
	print("SPECIES PICKER: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
