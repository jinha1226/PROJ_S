extends RefCounted
## One texture per garment. Coordinates refer to the unchanged 128px species canvas.
const LEATHER=preload("res://assets/fantasy_pawns_v1/equipment/leather.png")
const HELMET=preload("res://assets/fantasy_pawns_v1/equipment/iron_helmet.png")
const ARMORS={
	"ARMOR_CLOTH_ROBE":preload("res://assets/fantasy_pawns_v1/equipment/cloth_armor.png"),
	"ARMOR_LEATHER":LEATHER,
	"ARMOR_PADDED":preload("res://assets/fantasy_pawns_v1/equipment/padded_armor.png"),
	"ARMOR_CHAIN":preload("res://assets/fantasy_pawns_v1/equipment/chain_armor.png"),
	"ARMOR_PLATE":preload("res://assets/fantasy_pawns_v1/equipment/plate_armor.png"),
}
const HELMETS={
	"HELMET_CLOTH":preload("res://assets/fantasy_pawns_v1/equipment/cloth_helmet.png"),
	"HELMET_LEATHER":preload("res://assets/fantasy_pawns_v1/equipment/leather_helmet.png"),
	"HELMET_PADDED":preload("res://assets/fantasy_pawns_v1/equipment/padded_helmet.png"),
	"HELMET_CHAIN":preload("res://assets/fantasy_pawns_v1/equipment/chain_helmet.png"),
	"HELMET_PLATE":HELMET,
	"HELMET_IRON":HELMET,
}
const FIT={
	"human":[Rect2(25,56,77,65),Rect2(31,8,66,65),57,43,84,74],
	"elf":[Rect2(31,60,65,61),Rect2(33,8,61,65),59,43,84,75],
	"dwarf":[Rect2(21,59,85,62),Rect2(35,18,58,55),57,35,93,78],
	"orc":[Rect2(17,54,94,67),Rect2(31,8,66,65),56,34,94,73],
	"beastkin":[Rect2(29,59,68,62),Rect2(33,20,62,55),58,40,88,75],
	"goblin":[Rect2(34,68,59,53),Rect2(40,27,48,53),68,43,83,81],
}
const BEARD=[Vector2(37,49),Vector2(43,45),Vector2(51,51),Vector2(64,53),Vector2(76,50),Vector2(84,46),Vector2(90,50),Vector2(93,62),Vector2(91,73),Vector2(87,80),Vector2(81,84),Vector2(77,92),Vector2(70,93),Vector2(65,98),Vector2(59,97),Vector2(55,92),Vector2(50,92),Vector2(44,84),Vector2(39,81),Vector2(37,73),Vector2(33,66),Vector2(34,56)]

static func target(rect:Rect2,bounds:Rect2)->Rect2:
	return Rect2(bounds.position+rect.position/128.0*bounds.size,rect.size/128.0*bounds.size)

static func fragment(canvas:CanvasItem,body:Texture2D,points:Array,bounds:Rect2,tint:Color)->void:
	var positions:=PackedVector2Array()
	var uv:=PackedVector2Array()
	for point:Vector2 in points:
		uv.append(point/128.0)
		positions.append(bounds.position+point/128.0*bounds.size)
	canvas.draw_polygon(positions,PackedColorArray([tint]),uv,body)

static func draw_body(canvas:CanvasItem,spec:Dictionary,bounds:Rect2,tint:Color)->void:
	var species:=str(spec.get("body_key",""))
	var body:Texture2D=spec.body_texture
	if not FIT.has(species):
		canvas.draw_texture_rect(body,bounds,false,tint)
		return
	var fit:Array=FIT[species]
	var armor:Texture2D=ARMORS.get(str(spec.get("armor_definition_id","")))
	if armor!=null:
		# Replace only the covered tunic region; sample the original head/neck over it.
		canvas.draw_texture_rect(armor,target(fit[0],bounds),false,tint)
		fragment(canvas,body,[Vector2.ZERO,Vector2(128,0),Vector2(128,fit[2]),Vector2(fit[4],fit[2]),Vector2(fit[4]-3,fit[5]),Vector2(fit[3]+3,fit[5]),Vector2(fit[3],fit[2]),Vector2(0,fit[2])],bounds,tint)
		if species=="dwarf":fragment(canvas,body,BEARD,bounds,tint)
	else:
		canvas.draw_texture_rect(body,bounds,false,tint)
	# Head slot is not yet authoritative: this key is also used by the fit-review fixture.
	var helmet:Texture2D=HELMETS.get(str(spec.get("head_definition_id","")))
	if helmet!=null:
		canvas.draw_texture_rect(helmet,target(fit[1],bounds),false,tint)
