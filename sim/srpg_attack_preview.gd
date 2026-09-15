extends RefCounted
const Rules=preload("res://sim/round_combat_rules.gd")
const Rooms=preload("res://sim/room_transition_rules.gd")
const Kernel=preload("res://sim/combat_kernel.gd")
const Targeting=preload("res://sim/weapon_attack_rules.gd")
static func cells(w,id:int,origin:Vector2i)->Array[Vector2i]:
	var result:Array[Vector2i]=[]
	var weapon_id:String=Rules.Items.equipped_weapon_id(w,id)
	var weapon=Rules.Weapons.definition(weapon_id)
	var reach:int=int(weapon.range_max) if weapon!=null else 1
	var occupants:Dictionary={}
	for y in range(origin.y-reach,origin.y+reach+1):
		for x in range(origin.x-reach,origin.x+reach+1):
			var position:=Vector2i(x,y)
			if w.combat_solid(position):occupants[position]="SOLID"
	for entity_id in w.entities:
		if int(entity_id)!=id and w.occupies_tile(int(entity_id)):
			occupants[w.entities[entity_id].position]="ALLY" if w.party_encounter.member(int(entity_id))!=null else "ENEMY"
	var visible:=Rules.Field.visible_cells(w)
	for y in range(origin.y-reach,origin.y+reach+1):
		for x in range(origin.x-reach,origin.x+reach+1):
			var target:=Vector2i(x,y)
			if target==origin or not Rooms.same_room(w,origin,target) or not visible.has("%d:%d"%[x,y]):continue
			if not Kernel.sees(origin,target,w.combat_solid,maxi(1,ceili(Vector2(target-origin).length()))):continue
			if weapon!=null and not Targeting.targeting_error(origin,target,weapon_id,occupants).is_empty():continue
			result.append(target)
	return result
