extends SceneTree
## Actual runtime texture/mapping preview. No simulation changes.
const Tiles=preload("res://playtest/topdown_tile_assets.gd")
const Pawns=preload("res://playtest/fantasy_pawn_assets.gd")
class Board extends Node2D:
	const UNIT=32
	func walkable(p:Vector2i)->bool:
		return Rect2i(1,1,7,6).has_point(p) or Rect2i(11,5,8,7).has_point(p) \
			or Rect2i(7,3,6,2).has_point(p) or Rect2i(11,3,2,4).has_point(p)
	func row(p:Vector2i)->Dictionary:
		return {"terrain_id":"floor" if walkable(p) else "wall","visibility_state":"VISIBLE"}
	func _draw()->void:
		draw_rect(Rect2(0,0,640,550),Color("#252c30"))
		for y in range(13):
			for x in range(20):
				var p:=Vector2i(x,y)
				var n:={"N":row(p+Vector2i.UP),"E":row(p+Vector2i.RIGHT),
					"S":row(p+Vector2i.DOWN),"W":row(p+Vector2i.LEFT)}
				var data:=row(p)
				if p==Vector2i(9,3):data.terrain_id="door_closed"
				if p==Vector2i(17,10):data.feature_id="floor_transition_portal"
				var spec:=Tiles.tile_spec(data,p,1,n)
				draw_texture_rect(spec.texture,Rect2(Vector2(p)*UNIT,Vector2.ONE*UNIT),false)
		var i:=0
		for species in Pawns.BODIES:
			var actor:={"species_id":species,"equipment_visual":{
				"weapon_definition_id":"WEAPON_SHORT_SWORD" if i%2==0 else "WEAPON_BOW"}}
			var pos:=Vector2(2+i%3*2,2+i/3*2)*UNIT
			Pawns.draw_actor(self,Pawns.actor_spec(actor),Rect2(pos,Vector2.ONE*UNIT))
			i+=1
		i=0
		for icon in Pawns.ICONS.values():
			draw_texture_rect(icon,Rect2(16+i*38,446,32,32),false);i+=1
		draw_string(ThemeDB.fallback_font,Vector2(16,512),
			"Runtime tiles / 32px pawns / transparent inventory icons",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
func _init()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(640,550);root.content_scale_size=Vector2i(640,550)
	var board:=Board.new();board.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	root.add_child(board)
	for i in range(3):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/fantasy-pawns-connections.png")
	quit()
