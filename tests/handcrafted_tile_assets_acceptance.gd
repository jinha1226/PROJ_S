extends SceneTree
const Art=preload("res://playtest/handcrafted_tile_assets.gd")
const Layer=preload("res://playtest/tactical_board_layer.gd")
const ProjectionRules=preload("res://playtest/tactical_board_projection.gd")
var failures:Array=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init()->void:call_deferred("run")
func run()->void:
	for biome in range(3):
		check(Art.obstacle(biome).get_size()==Vector2(64,64),"native obstacle size")
		for column in [0,1,2,3,5]:
			var texture:Texture2D=Art.tile(biome,column)
			check(texture.get_size()==Vector2(64,32),"native diamond size")
			check(texture==Art.tile(biome,column),"cached texture identity")
			var pixels:Image=texture.get_image()
			check(pixels.get_pixel(0,0).a==0,"source margins excluded")
			check(pixels.get_pixel(32,16).a>0.9,"opaque floor center")
		check(Art.tile(biome,0).get_image().get_data()!=Art.tile(biome,1).get_image().get_data(),"floor variety")
		for x in range(8):
			for y in range(8):
				var p:=Vector2i(x,y)
				check(Art.variant(p,biome) in [0,1,2,3],"floor never selects obstacle or water")
	for column in [0,3]:check(Art.wall(column).get_size()==Vector2(32,48),"wall pixel density")
	var layer=Layer.new();root.add_child(layer)
	var viewport:=Rect2(0,0,390,400)
	for theme in ["dungeon","cave","forest"]:
		var rows:Dictionary={}
		for y in range(8):
			for x in range(8):
				var p:=Vector2i(x,y)
				rows[p]={"position":p,"polygon":ProjectionRules.polygon(p,viewport,8,true),"visibility_state":"MEMORY" if x==7 else "VISIBLE","terrain":{"terrain_id":"shallow_water" if y==4 else "stone_floor"},"tile_spec":{"visible":true,"is_wall":x==2 and y==2}}
		layer.synchronize(rows,viewport,Vector2i.ZERO,8,theme)
		await process_frame
		check(layer.biome==Art.biome_index(theme),"theme bound to renderer")
		check(layer.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"nearest pixel sampling")
	layer.queue_free();await process_frame
	print("HANDCRAFTED_TILE_ASSETS ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
