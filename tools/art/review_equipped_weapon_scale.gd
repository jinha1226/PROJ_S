extends SceneTree
const Art=preload("res://playtest/fantasy_pawn_assets.gd")
class Board extends Node2D:
	func _draw():
		draw_rect(Rect2(0,0,960,480),Color("303941"))
		var ids:=["WEAPON_SHORT_SWORD","WEAPON_HAND_AXE","WEAPON_BOW","WEAPON_CROSSBOW","WEAPON_MACE","WEAPON_SPEAR"]
		for i in range(ids.size()):
			var spec:=Art.actor_spec({"species_id":"human","equipment_visual":{"weapon_definition_id":ids[i]}})
			for row in range(2):
				var bounds:=Rect2(20+i*154,35+row*220,128,128)
				if row==1:Art.draw_actor(self,spec,bounds)
				else:
					draw_texture_rect(spec.body_texture,bounds,false)
					draw_texture_rect(spec.weapon_texture,Art.Legacy.fit(spec.weapon_texture,Rect2(bounds.position+bounds.size*Vector2(.67,.40),bounds.size*Vector2(.30,.53))),false)
				# Native 40px size is more useful than only a magnified preview.
				var small:=Rect2(65+i*154,175+row*220,40,40)
				if row==1:Art.draw_actor(self,spec,small)
				else:
					draw_texture_rect(spec.body_texture,small,false)
					draw_texture_rect(spec.weapon_texture,Art.Legacy.fit(spec.weapon_texture,Rect2(small.position+small.size*Vector2(.67,.40),small.size*Vector2(.30,.53))),false)
			draw_string(ThemeDB.fallback_font,Vector2(20+i*154,233),ids[i].trim_prefix("WEAPON_"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
		draw_string(ThemeDB.fallback_font,Vector2(8,18),"BEFORE",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
		draw_string(ThemeDB.fallback_font,Vector2(8,252),"AFTER 1.6x",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
func _init():run.call_deferred()
func run():
	root.size=Vector2i(960,480);root.content_scale_size=root.size
	root.add_child(Board.new())
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/weapon-size-review.png")
	quit()
