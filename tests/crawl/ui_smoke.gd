extends SceneTree
var failures=0
func _initialize()->void:call_deferred("run")
func test(value:bool,name:String)->void:
	if not value:failures+=1;printerr("FAIL UI ",name)
func run()->void:
	var scene=load("res://game/crawl/game.tscn").instantiate();root.add_child(scene)
	await process_frame
	scene.dialog.hide()
	test(scene.world.floor_id=="D1","default Model B")
	for dimensions in [Vector2i(360,800),Vector2i(450,800),Vector2i(390,844),Vector2i(800,450)]:
		root.size=dimensions
		await process_frame
		test(scene.board.size.x>0 and scene.board.size.y>=250,"board visible "+str(dimensions))
		scene.bag();await process_frame;test(scene.content.get_child_count()>=9,"bag contents")
		scene.growth();await process_frame;test(scene.content.get_child_count()>=14,"growth contents")
		scene.faith();await process_frame;test(scene.content.get_child_count()>=7,"faith contents")
		scene.dialog.hide()
	scene.world.hero().hp-=10;scene.command("WAIT");scene.save()
	var data=JSON.parse_string(FileAccess.get_file_as_string(scene.SAVE))
	test(data is Dictionary and scene.world.validation_error(data).is_empty(),"UI writes validated save")
	print("MODEL_B_UI failures=",failures)
	scene.queue_free();await process_frame;quit(0 if failures==0 else 1)
