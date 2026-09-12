extends SceneTree
const Assets=preload("res://playtest/dungeon_0x72_assets.gd")
var errors:Array[String]=[]
class MotionProbe extends "res://playtest/party_grid_view.gd":
	var draws:=0
	func _draw()->void:draws+=1
class Probe extends Control:
	var flipped:=false
	var tex:Texture2D
	func _draw()->void:
		Assets.draw_actor(self,{"body_texture":tex,"flip_h":flipped},Rect2(40,40,32,32))
func _init()->void:run.call_deferred()
func run()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(128,128)
	viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var probe:=Probe.new()
	var pixels:=Image.create(16,16,false,Image.FORMAT_RGBA8);pixels.fill(Color.RED)
	probe.tex=ImageTexture.create_from_image(pixels);viewport.add_child(probe)
	for flipped in [false,true]:
		probe.flipped=flipped;probe.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		var rect:=viewport.get_texture().get_image().get_used_rect()
		if rect!=Rect2i(40,40,32,32):errors.append("Facing %s shifted to %s"%[flipped,rect])
	viewport.queue_free()
	var motion:=MotionProbe.new();root.add_child(motion)
	await process_frame;await RenderingServer.frame_post_draw
	motion.set_process(false)
	var before:=motion.draws
	motion._camera_settle={"started_at_ms":Time.get_ticks_msec()-100,"duration_ms":1,"from_offset_px":Vector2(32,0)}
	motion._process(0.0)
	await process_frame;await RenderingServer.frame_post_draw
	if motion.draws<=before:errors.append("Expired camera must redraw its final endpoint")
	if not motion._camera_settle.is_empty():errors.append("Expired camera not cleared")
	motion.queue_free()
	print("SPRITE ALIGNMENT: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
