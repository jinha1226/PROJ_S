extends RefCounted

## Salvage belongs to a specific canonical death and expedition, never a roll
## performed while drawing the UI. Unclaimed bundles remain on their death tile.
const LABELS:={"TIMBER":"목재", "STONE":"석재", "HERBS":"약초"}

static func caches(world,layout:Dictionary)->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	var party=world.party_encounter
	if party==null or party.expedition_cycle.phase!="DUNGEON":return rows
	var bounds:Rect2i=preload("res://sim/base_resource_cache_rules.gd")._floor_bounds(layout,world)
	var expedition:int=party.expedition_cycle.expedition_index
	var departure_id:=-1
	for event in world.events:
		if event.type=="town.expedition_departed":departure_id=int(event.id)
	for event in world.events:
		if event.type!="entity.died" or event.id<=departure_id \
				or event.target_id not in party.enemy_ids or not bounds.has_point(event.position):continue
		var enemy=world.entities.get(event.target_id)
		if enemy==null:continue
		var resource:String={"goblin":"TIMBER","kobold":"STONE", "rat":"HERBS"}.get(
			str(enemy.species_id),["TIMBER","STONE","HERBS"][posmod(int(enemy.id),3)])
		rows.append({"cache_id":"LOOT_EXP%d_DEATH%d"%[expedition,int(event.id)],
			"resource_id":resource,"amount":1,"source":"MONSTER",
			"source_death_event_id":int(event.id),
			"position":[event.position.x,event.position.y]})
	return rows

static func item_row(cache:Dictionary)->Dictionary:
	var label:String=LABELS.get(str(cache.resource_id),"물자")
	return {"instance_id":"BASE/"+str(cache.cache_id),"resource_cache_id":str(cache.cache_id),
		"definition_id":str(cache.resource_id),"resource_id":str(cache.resource_id),
		"quantity":int(cache.available_amount),"label":label,"display_name":label+" · 거점 건설 재료",
		"category":"MATERIAL","empty":false,"position":cache.position.duplicate()}
