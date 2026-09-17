extends SceneTree
func _initialize():
	var world=load("res://game/crawl/world.gd").new(44)
	print("CRAWL_START ",world.floor_name()," actors=",world.actors.size())
	print("VALIDATION ",world.validation_error(world.save_data()))
	quit()
