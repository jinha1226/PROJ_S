extends SceneTree
## Inspect real runtime monster specs at 32px on the approved dungeon floor.
const Art=preload("res://playtest/fantasy_pawn_assets.gd")
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
class Board extends Node2D:
	func _draw()->void:
		draw_rect(Rect2(0,0,640,420),Color("#252d31"))
		for y in range(12):
			for x in range(20):
				var row:={"terrain_id":"wall" if x==0 or y==0 or x==19 or y==11 else "floor","visibility_state":"VISIBLE"}
				var n:={"S":{"terrain_id":"floor","visibility_state":"VISIBLE"}} if y==0 else {}
				var tile:=Tiles.tile_spec(row,Vector2i(x,y),1,n)
				draw_texture_rect(tile.texture,Rect2(x*32,y*32,32,32),false)
		var i:=0
		for species in Art.MONSTERS:
			var position:=Vector2(64+i%4*144,52+i/4*104)
			var spec:=Art.actor_spec({"species_id":species})
			Art.draw_actor(self,spec,Rect2(position+Vector2(30,0),Vector2(32,32)))
			Art.draw_actor(self,spec,Rect2(position+Vector2(20,42),Vector2(48,48)))
			draw_string(ThemeDB.fallback_font,position+Vector2(-12,38),species,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE)
			i+=1
		draw_string(ThemeDB.fallback_font,Vector2(18,408),"Runtime monster art: 32px / 48px",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
func _init()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(640,420);root.content_scale_size=Vector2i(640,420)
	var board:=Board.new();board.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	root.add_child(board)
	for i in range(3):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/fantasy-monsters-runtime.png")
	quit()
