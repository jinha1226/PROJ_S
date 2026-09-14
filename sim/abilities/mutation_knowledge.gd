extends RefCounted
## Run-local, party-shared knowledge, derived only from successful consumption.
const Catalog=preload("res://sim/abilities/monster_ability_catalog.gd")
const Binding=preload("res://sim/abilities/ability_binding_rules.gd")
const KEY:="consumed_part_knowledge_v1"

static func special(id:String)->bool:
	return not Catalog.for_item(id).is_empty()

static func known(world,id:String)->bool:
	var cache:Dictionary=world.get_meta(KEY,{})
	if cache.is_empty() or int(cache.cursor)>world.events.size() or int(cache.cursor)>0 and cache.tail!=world.events[int(cache.cursor)-1]:
		cache={"cursor":0,"tail":null,"items":{}}
	for i in range(int(cache.cursor),world.events.size()):
		var event=world.events[i]
		if event.type=="party.monster_meat_eaten" and event.data.has("definition_id"):
			cache.items[str(event.data.definition_id)]=true
	cache.cursor=world.events.size();cache.tail=world.events[-1] if not world.events.is_empty() else null
	world.set_meta(KEY,cache)
	return cache.items.has(id)

static func decorate(world,row:Dictionary)->Dictionary:
	var id:=str(row.get("definition_id",""))
	if not special(id):return row
	var result:=row.duplicate(true)
	var revealed:=known(world,id)
	result["special_part"]=true;result["consumed_before"]=revealed
	result["usable"]=true;result["purpose"]="";result["compact_stat_text"]=""
	result["reward_family"]="";result["requirement_text"]=""
	result["effect_preview"]={}
	if revealed:
		var ability:=preload("res://sim/item_reward_rules.gd").ability_for_item(id)
		result.effect_preview=Binding.effect_preview(ability)
	return result
