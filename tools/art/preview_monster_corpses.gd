extends SceneTree
class Board extends Node2D:
	const Art=preload("res://playtest/fantasy_pawn_assets.gd")
	const Corpse=preload("res://playtest/monster_corpse_visuals.gd")
	const Tiles=preload("res://playtest/topdown_tile_assets.gd")
	func _draw():
		for y in range(12):
			for x in range(20):
				var tile:=Tiles.tile_spec({"terrain_id":"floor","visibility_state":"VISIBLE"},Vector2i(x,y),1)
				draw_texture_rect(tile.texture,Rect2(x*32,y*32,32,32),false)
		var index:=0
		for species in ["goblin","fire_lizard","frost_spider","water_slime","electric_eel","dcss_rat"]:
			var origin:=Vector2(30+(index%3)*208,42+(index/3)*154)
			draw_string(ThemeDB.fallback_font,origin+Vector2(0,-10),species,HORIZONTAL_ALIGNMENT_LEFT,-1,14)
			Art.draw_actor(self,Art.actor_spec({"species_id":species}),Rect2(origin,Vector2(40,40)))
			Corpse.draw(self,{"species_id":species,"stage":"BODY","angle":45.0,"waist_bend":24.0},Rect2(origin+Vector2(57,0),Vector2(40,40)))
			Corpse.draw(self,{"species_id":species,"stage":"BONES"},Rect2(origin+Vector2(115,0),Vector2(40,40)))
			Corpse.draw(self,{"species_id":species,"stage":"BODY","angle":-45.0,"waist_bend":24.0},Rect2(origin+Vector2(52,52),Vector2(32,32)))
			index+=1
		draw_string(ThemeDB.fallback_font,Vector2(24,362),"Alive / fallen + blood / bones after 30 turns. Lower row: 32px.",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
func _init():run.call_deferred()
func run():
	root.size=Vector2i(640,384);root.content_scale_size=Vector2i(640,384)
	var board:=Board.new();board.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;root.add_child(board)
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/monster-corpses-runtime.png")
	quit()
