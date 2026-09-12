class_name TorchRules
extends RefCounted

## Deterministic hand-torch rules.  Fuel is derived from the canonical torch
## events and world time, so snapshots and replay need no presentation-only
## mutable clock.
const RULESET_ID := "hand-torch-v1"
const DEFINITION_ID := "TORCH"
const EQUIP_SLOT := "OFF_HAND"
const FUEL_DURATION := 2000
const LIGHT_BRIGHTNESS := 1000
const LIGHT_RADIUS := 6
const ACTION_TIME_COST := 100
const EVENT_IGNITED := "torch.ignited"
const EVENT_EXTINGUISHED := "torch.extinguished"

static func is_torch_item(item) -> bool:
	return item != null and str(item.definition_id) == DEFINITION_ID

static func state(world, instance_id: String) -> Dictionary:
	return _state_for_item(world,instance_id,_item_in_world(world,instance_id) if world!=null else null)

static func _state_for_item(world,instance_id:String,item)->Dictionary:
	var result := {"instance_id": instance_id, "is_torch": false, "lit": false,
		"depleted": false, "fuel_remaining": FUEL_DURATION, "fuel_capacity": FUEL_DURATION,
		"ignited_at": -1, "last_event_id": -1, "source_event_type": ""}
	if world == null or instance_id.is_empty(): return result
	if not is_torch_item(item): return result
	result.is_torch = true
	var latest = _latest_event(world, instance_id)
	if latest == null: return result
	result.last_event_id = int(latest.id)
	result.source_event_type = str(latest.type)
	if str(latest.type) == EVENT_IGNITED:
		var fuel_at_ignite := clampi(int(latest.data.get("fuel_remaining", FUEL_DURATION)), 0, FUEL_DURATION)
		var elapsed := maxi(0, int(world.world_time) - int(latest.world_time))
		var remaining := maxi(0, fuel_at_ignite - elapsed)
		result.fuel_remaining = remaining
		result.ignited_at = int(latest.world_time)
		result.lit = remaining > 0
		result.depleted = remaining == 0
	else:
		result.fuel_remaining = clampi(int(latest.data.get("fuel_remaining", FUEL_DURATION)), 0, FUEL_DURATION)
		result.depleted = result.fuel_remaining == 0
	return result

static func equipped_torch(world, entity_id: int):
	if world == null or world.item_state == null: return null
	var inventory = world.item_state.inventory(entity_id)
	if inventory == null: return null
	var instance_id := str(inventory.equipped.get(EQUIP_SLOT, ""))
	if instance_id.is_empty(): return null
	var item = inventory._item_ref(instance_id)
	return item if is_torch_item(item) else null

static func equipped_torch_state(world, entity_id: int) -> Dictionary:
	var item = equipped_torch(world, entity_id)
	return _state_for_item(world, str(item.instance_id),item) if item != null else {
		"instance_id":"", "is_torch":false, "lit":false, "depleted":false,
		"fuel_remaining":0, "fuel_capacity":FUEL_DURATION, "ignited_at":-1,
		"last_event_id":-1, "source_event_type":""}

static func active_light_sources(world) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null or world.item_state == null: return result
	var entity_ids: Array = world.item_state.inventory_rows.keys(); entity_ids.sort()
	for raw_id in entity_ids:
		var entity_id := int(raw_id)
		if not world.entities.has(entity_id): continue
		var item = equipped_torch(world, entity_id)
		if item == null: continue
		var torch_state := _state_for_item(world, str(item.instance_id),item)
		if not bool(torch_state.get("lit", false)): continue
		var position: Vector2i = world.entities[entity_id].position
		result.append({"position":[position.x, position.y], "brightness":LIGHT_BRIGHTNESS,
			"radius":LIGHT_RADIUS, "instance_id":str(item.instance_id),
			"entity_id":entity_id})
	return result

static func action_error(world, entity_id: int, instance_id: String, action: String) -> String:
	if world == null or not world.entities.has(entity_id): return "item_actor_missing"
	var inventory = world.item_state.inventory(entity_id) if world.item_state != null else null
	if inventory == null: return "item_actor_missing"
	var item = inventory._item_ref(instance_id)
	if not is_torch_item(item): return "torch_item_missing"
	if str(inventory.equipped.get(EQUIP_SLOT, "")) != instance_id:
		return "torch_not_equipped_off_hand"
	var torch_state := state(world, instance_id)
	if action == "IGNITE":
		if bool(torch_state.get("lit", false)): return "torch_already_lit"
		if int(torch_state.get("fuel_remaining", 0)) <= 0: return "torch_fuel_empty"
	elif action == "EXTINGUISH":
		if not bool(torch_state.get("lit", false)): return "torch_not_lit"
	else:
		return "unknown_torch_action"
	return ""

static func event_payload(instance_id: String, fuel_remaining: int, time_cost: int) -> Dictionary:
	return {"schema_version":1, "ruleset_id":RULESET_ID, "instance_id":instance_id,
		"fuel_remaining":clampi(fuel_remaining, 0, FUEL_DURATION), "time_cost":maxi(0, time_cost)}

static func _item_in_world(world, instance_id: String):
	var owner:Dictionary = world.item_owner(instance_id)
	if str(owner.get("kind", "NONE")) == "ENTITY":
		var inventory = world.item_state.inventory(int(owner.entity_id))
		return inventory._item_ref(instance_id) if inventory != null else null
	if str(owner.get("kind", "NONE")) == "GROUND":
		var ground = world.ground_item(instance_id)
		return ground
	return null

static func _latest_event(world, instance_id: String):
	# Derived per-world index. Fuel still depends on current canonical time;
	# rollback/replay invalidates the index when its prefix is no longer present.
	var cache:Dictionary=world.torch_event_cache
	var count:int=world.events.size()
	if cache.is_empty() or int(cache.get("count",0))>count \
			or (int(cache.get("count",0))>0 and cache.get("tail")!=world.events[int(cache.count)-1]):
		cache={"count":0,"tail":null,"latest":{}}
	for index in range(int(cache.count),count):
		var event=world.events[index]
		if str(event.type) in [EVENT_IGNITED,EVENT_EXTINGUISHED]:
			cache.latest[str(event.data.get("instance_id",""))]=event
	cache.count=count;cache.tail=world.events[-1] if count>0 else null
	world.torch_event_cache=cache
	return cache.latest.get(instance_id)
