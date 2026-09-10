extends SceneTree
const Assets=preload("res://playtest/fixed_front_topdown_assets.gd")
const Directions=preload("res://playtest/human_directional_assets.gd")
const WorldIcons=preload("res://playtest/pixel24_world_effect_assets.gd")
const Portrait=preload("res://playtest/compact_party_portrait.gd")
const SPECIES:=["human","elf","dwarf","orc","beastkin","kobold","slime","beetle"]
var failures:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func run():
	root.size=Vector2i(800,860);root.content_scale_size=root.size
	var canvas:=Control.new();root.add_child(canvas);canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(func():
		canvas.draw_rect(Rect2(0,0,800,860),Color("#161c24"))
		for row in range(SPECIES.size()):
			for i in range(8):
				var spec:Dictionary=Assets.actor_layer_spec({"species_id":SPECIES[row],"facing":Directions.DIRECTIONS[i]})
				canvas.draw_texture_rect(spec.body_texture,Rect2(120+i*80,10+row*78,72,72),false)
		for i in range(WorldIcons.CELLS.size()):
			WorldIcons.draw_icon(canvas,WorldIcons.CELLS.keys()[i],Rect2(10+(i%12)*64,660+(i/12)*64,60,60))
	)
	for row in range(SPECIES.size()):
		var hashes:Dictionary={}
		for i in range(8):
			var spec:Dictionary=Assets.actor_layer_spec({"species_id":SPECIES[row],"facing":Directions.DIRECTIONS[i]})
			check(spec.uses_sprite and not spec.fixed_front,"direction supported "+SPECIES[row])
			check(spec.direction_index==i,"eight-way mapping "+SPECIES[row])
			var texture:Texture2D=spec.body_texture
			check(texture.get_size()==Vector2(24,24),"native 24x24 "+SPECIES[row])
			var image:=texture.get_image()
			check(not image.get_used_rect().has_point(Vector2i.ZERO),"transparent margin "+SPECIES[row])
			hashes[image.get_data().hex_encode().sha256_text()]=true
		check(hashes.size()==8,"eight distinct frames "+SPECIES[row])
		var label:=Label.new();label.text=SPECIES[row];label.position=Vector2(8,30+row*78);canvas.add_child(label)
	for size_x in [90,160,380]:
		var portrait=Portrait.new();portrait.size=Vector2(size_x,64);portrait.actor={"health":60,"max_health":120,"energy":3,"max_energy":12,"stress":800}
		for meter in portrait.resource_meter_specs():check(Rect2(Vector2.ZERO,portrait.size).encloses(meter.rect),"meter bounds %d"%size_x)
		check(portrait.resource_meter_specs()[0].ratio==0.5,"HP proportion")
		check(portrait.resource_meter_specs()[1].ratio==0.25,"MP proportion")
		check(portrait.resource_meter_specs()[2].ratio==0.8,"stress proportion")
		portrait.free()
	check(WorldIcons.FEATURES.get_size()==Vector2(96,96),"16 native feature tiles")
	check(WorldIcons.PROPS.get_size()==Vector2(96,48),"8 native prop tiles")
	for i in range(5):await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var capture:=root.get_texture().get_image()
		capture.save_png("/tmp/eight-way-runtime-preview.png")
	canvas.queue_free();await process_frame
	print("EIGHT WAY VISUAL: ",failures)
	quit(0 if failures.is_empty() else 1)
