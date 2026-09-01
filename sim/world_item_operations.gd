class_name WorldItemOperations
extends RefCounted

# Entity-addressed transaction layer of the guide 5.4. `ItemInventoryOperations`
# stays the pure single-inventory kernel underneath; this layer owns the world
# scope: which entity, which ground, which weapon runtime row, the global item
# invariant, revision +1, the canonical event and the atomic swap into the world.
#
# Every commit follows the fixed order:
#   validate input -> clone WorldItemState -> mutate only the clone
#   -> global item invariant -> revision exactly +1 -> event -> atomic swap.
# A rejection never touches the live world, so nothing has to be rolled back.

const InventoryOperationsScript=preload("res://sim/item_inventory_operations.gd")
const ItemScript=preload("res://sim/item_instance.gd")
const RegistryScript=preload("res://sim/item_registry.gd")
const WeaponRegistryScript=preload("res://sim/weapon_registry.gd")
const RuntimeScript=preload("res://sim/weapon_runtime_state.gd")

const EVENT_TYPES:={"PICKUP":"item.picked_up","DROP":"item.dropped","EQUIP":"item.equipped",
	"UNEQUIP":"item.unequipped","DISCARD":"item.discarded","TRANSFER":"item.transferred"}


static func preview_pickup(world,entity_id:int,instance_id:String,position:Vector2i)->Dictionary:
	return _preview(_plan_pickup(world,entity_id,instance_id,position))


static func commit_pickup(world,entity_id:int,instance_id:String,position:Vector2i,
		time_cost:int=0)->Dictionary:
	return _commit(world,_plan_pickup(world,entity_id,instance_id,position),"PICKUP",
		entity_id,-1,position,instance_id,"",time_cost)


static func preview_drop(world,entity_id:int,instance_id:String,position:Vector2i)->Dictionary:
	return _preview(_plan_drop(world,entity_id,instance_id,position))


static func commit_drop(world,entity_id:int,instance_id:String,position:Vector2i,
		time_cost:int=0)->Dictionary:
	return _commit(world,_plan_drop(world,entity_id,instance_id,position),"DROP",
		entity_id,-1,position,instance_id,"",time_cost)


static func preview_equip(world,entity_id:int,instance_id:String,slot:String)->Dictionary:
	return _preview(_plan_equip(world,entity_id,instance_id,slot))


static func commit_equip(world,entity_id:int,instance_id:String,slot:String,
		position:Vector2i,time_cost:int=0)->Dictionary:
	return _commit(world,_plan_equip(world,entity_id,instance_id,slot),"EQUIP",
		entity_id,-1,position,instance_id,slot,time_cost)


static func preview_unequip(world,entity_id:int,slot:String)->Dictionary:
	return _preview(_plan_unequip(world,entity_id,slot))


static func commit_unequip(world,entity_id:int,slot:String,position:Vector2i,
		time_cost:int=0)->Dictionary:
	return _commit(world,_plan_unequip(world,entity_id,slot),"UNEQUIP",
		entity_id,-1,position,"",slot,time_cost)


static func preview_discard(world,entity_id:int,instance_id:String)->Dictionary:
	return _preview(_plan_discard(world,entity_id,instance_id))


static func commit_discard(world,entity_id:int,instance_id:String,position:Vector2i,
		time_cost:int=0)->Dictionary:
	return _commit(world,_plan_discard(world,entity_id,instance_id),"DISCARD",
		entity_id,-1,position,instance_id,"",time_cost)


static func preview_transfer(world,from_entity_id:int,to_entity_id:int,
		instance_id:String)->Dictionary:
	return _preview(_plan_transfer(world,from_entity_id,to_entity_id,instance_id))


static func commit_transfer(world,from_entity_id:int,to_entity_id:int,instance_id:String,
		position:Vector2i,time_cost:int=0)->Dictionary:
	return _commit(world,_plan_transfer(world,from_entity_id,to_entity_id,instance_id),
		"TRANSFER",from_entity_id,to_entity_id,position,instance_id,"",time_cost)


static func preview_use(world,entity_id:int,instance_id:String)->Dictionary:
	return _preview(_plan_use(world,entity_id,instance_id))


static func commit_use(world,entity_id:int,instance_id:String,position:Vector2i,
		time_cost:int=0)->Dictionary:
	var plan:=_plan_use(world,entity_id,instance_id)
	if not bool(plan.get("accepted",false)):return plan
	return _commit_planned(world,plan,"item.used",entity_id,entity_id,position,
		{"instance_id":instance_id,"definition_id":str(plan.definition_id),
			"use_kind":str(plan.use_kind),"time_cost":int(time_cost)})


static func commit_use_without_event(world,entity_id:int,instance_id:String)->Dictionary:
	# The opening event records its own causal chain (opening.potion_given ->
	# opening.health_restored), so it consumes the stack without a second
	# item.used leaf. The state transaction is otherwise identical.
	var plan:=_plan_use(world,entity_id,instance_id)
	if not bool(plan.get("accepted",false)):return plan
	var next=plan.item_state
	reconcile_weapon_runtime_rows(next)
	var result:=plan.duplicate();result.erase("item_state")
	return _swap(world,next,result)


static func commit_grant(world,entity_id:int,definition_id:String,quantity:int,
		position:Vector2i,reason:String)->Dictionary:
	# Creation is distinct from cross-container movement: it consumes the world
	# allocator and introduces one permanent instance directly into an owner bag.
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var definition=RegistryScript.definition(definition_id)
	if definition==null or quantity<1 or quantity>int(definition.stack_limit) \
			or reason.is_empty():
		return _rejected("invalid_item_grant")
	var next=world.item_state.clone()
	var instance_id:String=next.instance_id_for(next.next_item_instance_id)
	next.next_item_instance_id+=1
	var added:=InventoryOperationsScript.commit_insert_instance(next.inventory(entity_id),
		ItemScript.new(instance_id,definition_id,quantity))
	if not bool(added.get("accepted",false)):return _rejected(str(added.reason))
	next.inventory_rows[entity_id]=added.inventory
	var plan:=_accepted({"item_state":next,"instance_id":instance_id,
		"definition_id":definition_id,"quantity":quantity})
	return _commit_planned(world,plan,"item.granted",entity_id,entity_id,position,
		{"instance_id":instance_id,"definition_id":definition_id,"quantity":quantity,
			"reason":reason})


static func commit_spawn_ground(world,definition_id:String,quantity:int,
		position:Vector2i,actor_id:int=-1,cause_id:int=-1,reason:String="WORLD_DROP")->Dictionary:
	if world==null or world.item_state==null or not world.in_bounds(position):
		return _rejected("invalid_item_world_context")
	if actor_id!=-1 and not world.entities.has(actor_id):return _rejected("item_actor_missing")
	if cause_id!=-1 and world.event_by_id(cause_id)==null:return _rejected("item_cause_missing")
	var definition=RegistryScript.definition(definition_id)
	if definition==null or quantity<1 or quantity>int(definition.stack_limit) \
			or reason.is_empty():
		return _rejected("invalid_ground_item_spawn")
	var next=world.item_state.clone()
	var instance_id:String=next.instance_id_for(next.next_item_instance_id)
	next.next_item_instance_id+=1
	next.ground_items.rows.append({"position":position,
		"item":ItemScript.new(instance_id,definition_id,quantity)})
	next.ground_items._sort_rows()
	var plan:=_accepted({"item_state":next,"instance_id":instance_id,
		"definition_id":definition_id,"quantity":quantity})
	return _commit_planned(world,plan,"item.spawned_on_ground",actor_id,-1,position,
		{"instance_id":instance_id,"definition_id":definition_id,"quantity":quantity,
			"reason":reason},cause_id)


# --- weapon authority (guide 4.3) -------------------------------------------
# The equipped MAIN_HAND instance is the only weapon authority. Ammo counts live
# on the entity row and reload state on the weapon instance row, so a loaded
# crossbow keeps its load wherever the instance goes.

static func equipped_weapon_id(world,entity_id:int)->String:
	var main=_main_hand_ref(world,entity_id)
	if main==null:return "UNARMED"
	var definition=RegistryScript.definition(main.definition_id)
	if definition==null or str(definition.weapon_id).is_empty():return "UNARMED"
	return str(definition.weapon_id)


static func main_hand_instance_id(world,entity_id:int)->String:
	var main=_main_hand_ref(world,entity_id)
	return str(main.instance_id) if main!=null else ""


static func weapon_is_loaded(world,entity_id:int)->bool:
	var runtime=world.item_state.weapon_runtime(main_hand_instance_id(world,entity_id)) \
		if world!=null and world.item_state!=null else null
	return runtime!=null and runtime.loaded


static func attack_error(world,entity_id:int)->String:
	var weapon=WeaponRegistryScript.definition(equipped_weapon_id(world,entity_id))
	if weapon==null:return "unknown_equipped_weapon"
	if weapon.ammo_kind=="NONE":return ""
	var pool=world._ammo_pool_ref(entity_id)
	if pool==null or pool.amount(weapon.ammo_kind)<int(weapon.ammo_cost):return "ammo_empty"
	if weapon.reload_required and not weapon_is_loaded(world,entity_id):return "reload_required"
	return ""


static func commit_attack_consumption(world,entity_id:int)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var error:=attack_error(world,entity_id)
	if not error.is_empty():return _rejected(error)
	var weapon_id:=equipped_weapon_id(world,entity_id)
	var weapon=WeaponRegistryScript.definition(weapon_id)
	var result:={"weapon_id":weapon_id,"ammo_kind":str(weapon.ammo_kind),
		"ammo_remaining":0,"reload_required":false}
	# A weapon with neither ammo nor a load consumes nothing, so it must not move
	# the revision: invariant 13 counts state changes, not calls.
	if weapon.ammo_kind=="NONE" and not weapon.reload_required:return _accepted(result)
	var next=world.item_state.clone()
	if weapon.ammo_kind!="NONE":
		var pool=next.ammo_pool(entity_id)
		if pool==null:return _rejected("ammo_empty")
		pool.amounts[weapon.ammo_kind]=pool.amount(weapon.ammo_kind)-int(weapon.ammo_cost)
		result.ammo_remaining=pool.amount(weapon.ammo_kind)
	if weapon.reload_required:
		var runtime=next.weapon_runtime(main_hand_instance_id(world,entity_id))
		if runtime==null:return _rejected("missing_weapon_runtime_row")
		runtime.loaded=false;result.reload_required=true
	return _swap(world,next,result)


static func commit_reload(world,entity_id:int)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var weapon_id:=equipped_weapon_id(world,entity_id)
	var weapon=WeaponRegistryScript.definition(weapon_id)
	if weapon==null:return _rejected("unknown_equipped_weapon")
	if not weapon.reload_required:return _rejected("weapon_does_not_reload")
	var instance_id:=main_hand_instance_id(world,entity_id)
	var runtime=world.item_state.weapon_runtime(instance_id)
	if runtime==null:return _rejected("missing_weapon_runtime_row")
	if runtime.loaded:return _rejected("already_loaded")
	var pool=world._ammo_pool_ref(entity_id)
	if pool==null or pool.amount(weapon.ammo_kind)<int(weapon.ammo_cost):
		return _rejected("ammo_empty")
	var next=world.item_state.clone()
	next.weapon_runtime(instance_id).loaded=true
	return _swap(world,next,{"weapon_id":weapon_id,"reload_time":int(weapon.reload_time)})


# --- plans (pure) ------------------------------------------------------------

static func _plan_pickup(world,entity_id:int,instance_id:String,position:Vector2i)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var next=world.item_state.clone()
	var result:=InventoryOperationsScript.commit_pickup(next.inventory(entity_id),
		next.ground_items,instance_id,position,_bounds(world))
	if not bool(result.get("accepted",false)):return _rejected(str(result.reason))
	next.inventory_rows[entity_id]=result.inventory;next.ground_items=result.ground
	return _accepted({"item_state":next,"instance_id":instance_id})


static func _plan_drop(world,entity_id:int,instance_id:String,position:Vector2i)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var next=world.item_state.clone()
	var result:=InventoryOperationsScript.commit_drop(next.inventory(entity_id),
		next.ground_items,instance_id,position,_bounds(world))
	if not bool(result.get("accepted",false)):return _rejected(str(result.reason))
	next.inventory_rows[entity_id]=result.inventory;next.ground_items=result.ground
	return _accepted({"item_state":next,"instance_id":instance_id})


static func _plan_equip(world,entity_id:int,instance_id:String,slot:String)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var next=world.item_state.clone()
	var result:=InventoryOperationsScript.commit_equip(next.inventory(entity_id),
		instance_id,slot)
	if not bool(result.get("accepted",false)):return _rejected(str(result.reason))
	next.inventory_rows[entity_id]=result.inventory
	return _accepted({"item_state":next,"instance_id":instance_id,"slot":slot,
		"replaced_instance_id":str(result.get("replaced_instance_id",""))})


static func _plan_unequip(world,entity_id:int,slot:String)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var next=world.item_state.clone()
	var result:=InventoryOperationsScript.commit_unequip(next.inventory(entity_id),slot)
	if not bool(result.get("accepted",false)):return _rejected(str(result.reason))
	next.inventory_rows[entity_id]=result.inventory
	return _accepted({"item_state":next,"instance_id":str(result.instance_id),"slot":slot})


static func _plan_discard(world,entity_id:int,instance_id:String)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var next=world.item_state.clone()
	var result:=InventoryOperationsScript.commit_discard(next.inventory(entity_id),instance_id)
	if not bool(result.get("accepted",false)):return _rejected(str(result.reason))
	next.inventory_rows[entity_id]=result.inventory
	return _accepted({"item_state":next,"instance_id":instance_id})


static func _plan_use(world,entity_id:int,instance_id:String)->Dictionary:
	var guard:=_guard(world,entity_id)
	if not guard.is_empty():return _rejected(guard)
	var next=world.item_state.clone()
	var result:=InventoryOperationsScript.commit_use(next.inventory(entity_id),instance_id)
	if not bool(result.get("accepted",false)):return _rejected(str(result.reason))
	next.inventory_rows[entity_id]=result.inventory
	return _accepted({"item_state":next,"instance_id":instance_id,
		"definition_id":str(result.definition_id),"use_kind":str(result.use_kind)})


static func _plan_transfer(world,from_entity_id:int,to_entity_id:int,
		instance_id:String)->Dictionary:
	var guard:=_guard(world,from_entity_id)
	if not guard.is_empty():return _rejected(guard)
	guard=_guard(world,to_entity_id)
	if not guard.is_empty():return _rejected(guard)
	if from_entity_id==to_entity_id:return _rejected("item_transfer_same_entity")
	var next=world.item_state.clone()
	var source=next.inventory(from_entity_id)
	var moved=source.item(instance_id)
	if moved==null:return _rejected("inventory_item_missing")
	# The destination is filled first so a full bag rejects before the source row
	# is touched at all. An equipped source instance leaves its slot inside the
	# same transaction, exactly as corpse looting will need in C.
	var added:=InventoryOperationsScript.commit_insert_instance(
		next.inventory(to_entity_id),moved)
	if not bool(added.get("accepted",false)):return _rejected(str(added.reason))
	for slot in source.equipped:
		if str(source.equipped[slot])==instance_id:source.equipped[slot]=""
	var removed:=InventoryOperationsScript.commit_discard(source,instance_id)
	if not bool(removed.get("accepted",false)):return _rejected(str(removed.reason))
	next.inventory_rows[from_entity_id]=removed.inventory
	next.inventory_rows[to_entity_id]=added.inventory
	return _accepted({"item_state":next,"instance_id":instance_id,
		"from_entity_id":from_entity_id,"to_entity_id":to_entity_id})


# --- commit machinery --------------------------------------------------------

static func _commit(world,plan:Dictionary,action:String,actor_id:int,target_id:int,
		position:Vector2i,instance_id:String,slot:String,time_cost:int)->Dictionary:
	if not bool(plan.get("accepted",false)):return plan
	return _commit_planned(world,plan,str(EVENT_TYPES[action]),actor_id,target_id,position,
		{"action":action,"instance_id":str(plan.get("instance_id",instance_id)),
			"slot":slot,"time_cost":int(time_cost)})


static func _commit_planned(world,plan:Dictionary,event_type:String,actor_id:int,
		target_id:int,position:Vector2i,data:Dictionary,cause_id:int=-1)->Dictionary:
	var next=plan.item_state
	reconcile_weapon_runtime_rows(next)
	var invariant:=_global_invariant_error(world,next)
	if not invariant.is_empty():return _rejected(invariant)
	next.revision=world.item_state.revision+1
	var payload:={"schema_version":1}
	payload.merge(data,true)
	var event=world.emit_event(event_type,actor_id,target_id,position,0,cause_id,payload)
	if event==null:return _rejected("item_event_failed")
	world.item_state=next
	var result:=plan.duplicate();result.erase("item_state")
	result["event_id"]=int(event.id);result["revision"]=int(next.revision)
	return result


static func _swap(world,next,extra:Dictionary)->Dictionary:
	# Ammo and reload transactions carry no item event of their own: the melee
	# action event and the equipment journal already record them.
	var invariant:=_global_invariant_error(world,next)
	if not invariant.is_empty():return _rejected(invariant)
	next.revision=world.item_state.revision+1
	world.item_state=next
	var result:=extra.duplicate(true);result["revision"]=int(next.revision)
	return _accepted(result)


static func _global_invariant_error(world,next)->String:
	var error:String=next.validation_error(world.width,world.height)
	if not error.is_empty():return error
	return next.world_membership_error(world.combatant_states.keys(),world._death_event_ids())


static func reconcile_weapon_runtime_rows(next)->void:
	# Invariant 9: exactly one runtime row per reload-required weapon instance and
	# none for anything else. Ownership moves never rewrite an existing row, so a
	# loaded crossbow keeps its load through drop, pickup, transfer and loot.
	var required:={}
	for entity_id in next.inventory_rows:
		for value in next.inventory_rows[entity_id].backpack:
			if _needs_runtime_row(str(value.definition_id)):required[str(value.instance_id)]=true
	for row in next.ground_items.rows:
		if _needs_runtime_row(str(row.item.definition_id)):required[str(row.item.instance_id)]=true
	for instance_id in next.weapon_runtime_rows.keys():
		if not required.has(instance_id):next.weapon_runtime_rows.erase(instance_id)
	for instance_id in required:
		if not next.weapon_runtime_rows.has(instance_id):
			next.weapon_runtime_rows[instance_id]=RuntimeScript.new(str(instance_id),false)


static func _needs_runtime_row(definition_id:String)->bool:
	var definition=RegistryScript.definition(definition_id)
	if definition==null or definition.category!="WEAPON":return false
	var weapon=WeaponRegistryScript.definition(str(definition.weapon_id))
	return weapon!=null and weapon.reload_required


static func _main_hand_ref(world,entity_id:int):
	# Read-only combat fast path: no clone, because the caller only reads the
	# definition id. Gameplay and UI use the detached facade in SimWorldState.
	if world==null or world.item_state==null:return null
	var inventory=world.item_state.inventory(entity_id)
	if inventory==null:return null
	var instance_id:=str(inventory.equipped.get("MAIN_HAND",""))
	return null if instance_id.is_empty() else inventory._item_ref(instance_id)


static func _guard(world,entity_id:int)->String:
	if world==null or world.item_state==null or world.width<=0 or world.height<=0:
		return "invalid_item_world_context"
	if not world.entities.has(entity_id) or world.item_state.inventory(entity_id)==null:
		return "item_actor_missing"
	return ""


static func _bounds(world)->Rect2i:
	return Rect2i(Vector2i.ZERO,Vector2i(world.width,world.height))


static func _preview(plan:Dictionary)->Dictionary:
	var result:=plan.duplicate()
	if result.get("item_state")!=null:result["item_state"]=result.item_state.to_dict()
	result["preview"]=true
	return result.duplicate(true)


static func _accepted(extra:Dictionary={})->Dictionary:
	var result:={"accepted":true,"reason":"ok","preview":false}
	result.merge(extra,true);return result


static func _rejected(reason:String)->Dictionary:
	return {"accepted":false,"reason":reason,"preview":false}
