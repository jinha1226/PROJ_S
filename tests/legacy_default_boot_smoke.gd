extends SceneTree

# Verify the real project entry point, including exported PCK runs. Merely
# instantiating the legacy UI would miss an accidental Model B deployment.
func _init()->void:run.call_deferred()

func run()->void:
	var path:String=ProjectSettings.get_setting("application/run/main_scene", "")
	var packed=load(path)
	if packed==null:printerr("FAIL project entry point missing");quit(1);return
	var router=packed.instantiate()
	root.add_child(router);current_scene=router
	for i in range(10):await process_frame
	var scene=current_scene
	if scene==null or scene.scene_file_path!="res://playtest/party_encounter_sandbox.tscn":
		printerr("FAIL default build did not open legacy: ",scene.scene_file_path if scene!=null else "null")
		quit(1);return
	if scene.session==null or scene.session.sim==null or scene.starting_job_button==null:
		printerr("FAIL legacy default missing session or starting job picker")
		quit(1);return
	print("LEGACY_DEFAULT_BOOT: PASS")
	quit(0)
