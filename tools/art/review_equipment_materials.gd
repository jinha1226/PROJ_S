extends SceneTree
const Art=preload("res://playtest/fantasy_pawn_assets.gd")
const SETS=[
	["CLOTH","ARMOR_CLOTH_ROBE","HELMET_CLOTH"],
	["LEATHER","ARMOR_LEATHER","HELMET_LEATHER"],
	["PADDED","ARMOR_PADDED","HELMET_PADDED"],
	["CHAIN","ARMOR_CHAIN","HELMET_CHAIN"],
	["PLATE","ARMOR_PLATE","HELMET_PLATE"],
]
class Board extends Node2D:
	func _draw():
		draw_rect(Rect2(0,0,1080,1160),Color("303941"))
		var species:=["human","elf","dwarf","orc","beastkin","goblin"]
		for col in range(6):
			draw_string(ThemeDB.fallback_font,Vector2(35+col*178,25),species[col],HORIZONTAL_ALIGNMENT_LEFT,-1,16)
			for row in range(SETS.size()):
				var set:Array=SETS[row]
				var spec:=Art.actor_spec({"species_id":species[col],"equipment_visual":{"armor_definition_id":set[1],"head_definition_id":set[2]}})
				Art.draw_actor(self,spec,Rect2(23+col*178,48+row*222,128,128))
				Art.draw_actor(self,spec,Rect2(67+col*178,180+row*222,40,40))
		for row in range(SETS.size()):
			draw_string(ThemeDB.fallback_font,Vector2(8,44+row*222),SETS[row][0],HORIZONTAL_ALIGNMENT_LEFT,-1,12)
func _init():run.call_deferred()
func run():
	root.size=Vector2i(1080,1160)
	root.content_scale_size=root.size
	root.add_child(Board.new())
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/equipment-materials-review.png")
	quit()
