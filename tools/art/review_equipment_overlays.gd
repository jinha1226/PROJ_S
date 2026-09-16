extends SceneTree
const Art=preload("res://playtest/fantasy_pawn_assets.gd")
class Board extends Node2D:
	func _draw():
		draw_rect(Rect2(0,0,1000,930),Color("303941"))
		var species:=["human","elf","dwarf","orc","beastkin","goblin"]
		for column in range(6):
			draw_string(ThemeDB.fallback_font,Vector2(35+column*164,24),species[column],HORIZONTAL_ALIGNMENT_LEFT,-1,16)
			for row in range(4):
				var gear:={}
				if row in [1,3]:gear.armor_definition_id="ARMOR_LEATHER"
				if row in [2,3]:gear.head_definition_id="HELMET_IRON"
				var spec:=Art.actor_spec({"species_id":species[column],"equipment_visual":gear})
				Art.draw_actor(self,spec,Rect2(16+column*164,48+row*220,128,128))
				Art.draw_actor(self,spec,Rect2(58+column*164,179+row*220,40,40))
		for row in range(4):
			draw_string(ThemeDB.fallback_font,Vector2(8,44+row*220),["BASE","SHARED ARMOR","SHARED HELMET (PREVIEW)","BOTH"][row],HORIZONTAL_ALIGNMENT_LEFT,-1,12)
func _init():run.call_deferred()
func run():
	root.size=Vector2i(1000,930)
	root.content_scale_size=root.size
	root.add_child(Board.new())
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/equipment-overlays-review.png")
	quit()
