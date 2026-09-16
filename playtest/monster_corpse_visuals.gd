extends RefCounted
## Presentation derived from canonical deaths; never changes terrain or occupancy.
const BONES_AFTER=3000
const Art=preload("res://playtest/fantasy_pawn_assets.gd")
static func project(world,enemy_ids:Array,visible:Dictionary)->Dictionary:
	var result:Dictionary={}
	var deaths:Dictionary=preload("res://sim/runtime_history_index.gd").sync(world).deaths
	for id in enemy_ids:
		var death=deaths.get(int(id));var entity=world.entities.get(int(id))
		if death==null or entity==null:continue
		var key:="%d:%d"%[death.position.x,death.position.y]
		if not visible.has(key):continue
		if not result.has(key):result[key]=[]
		result[key].append({"entity_id":int(id),"species_id":str(entity.species_id),
			"stage":"BONES" if world.world_time-death.world_time>=BONES_AFTER else "BODY",
			"angle":45.0 if int(id)%2==0 else -45.0,"waist_bend":24.0})
	return result

static func draw(canvas:CanvasItem,row:Dictionary,rect:Rect2)->void:
	var center:=rect.get_center()+Vector2(0,rect.size.y*0.12)
	var scale:float=rect.size.x
	if row.stage=="BONES":
		# Small skull and rib/limb pile; no atlas tile can be mistaken for a door.
		var ink:=Color("423c32");var bone:=Color("c8baa0")
		for pair in [[Vector2(-.22,.08),Vector2(.22,-.06)],[Vector2(-.18,-.12),Vector2(.17,.17)]]:
			canvas.draw_line(center+pair[0]*scale,center+pair[1]*scale,ink,maxf(2,scale*.10),true)
			canvas.draw_line(center+pair[0]*scale,center+pair[1]*scale,bone,maxf(1,scale*.055),true)
		canvas.draw_circle(center+Vector2(-.10,-.13)*scale,scale*.12,ink)
		canvas.draw_circle(center+Vector2(-.10,-.13)*scale,scale*.09,bone)
		for x in [-.13,-.065]:canvas.draw_circle(center+Vector2(x,-.14)*scale,scale*.022,ink)
		return
	canvas.draw_colored_polygon(PackedVector2Array([
		center+Vector2(-.34,.02)*scale,center+Vector2(-.20,-.12)*scale,
		center+Vector2(.18,-.08)*scale,center+Vector2(.35,.07)*scale,
		center+Vector2(.13,.19)*scale,center+Vector2(-.26,.16)*scale]),Color("612626c8"))
	var texture:Texture2D=Art.body_texture(str(row.species_id))
	if texture==null:return
	var angle:float=deg_to_rad(float(row.angle))
	# Two joined quads hinge at the waist, preserving the source UVs and silhouette.
	var waist_left:=Vector2(-.40,0).rotated(angle)*scale+center
	var waist_right:=Vector2(.40,0).rotated(angle)*scale+center
	var top:=Vector2(0,-.44).rotated(angle)*scale
	var bottom:=Vector2(0,.30).rotated(angle+deg_to_rad(float(row.waist_bend)))*scale
	var colors:=PackedColorArray([Color("afa49c")])
	canvas.draw_polygon(PackedVector2Array([waist_left+top,waist_right+top,waist_right,waist_left]),colors,
		PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,.58),Vector2(0,.58)]),texture)
	canvas.draw_polygon(PackedVector2Array([waist_left,waist_right,waist_right+bottom,waist_left+bottom]),colors,
		PackedVector2Array([Vector2(0,.58),Vector2(1,.58),Vector2(1,1),Vector2(0,1)]),texture)
