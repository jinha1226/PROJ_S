extends RefCounted
const Specs=preload("res://sim/consumable_catalog.gd")
const Effects=preload("res://sim/consumable_effects.gd")
const Mystery=preload("res://sim/mystery_consumables.gd")
const Ops=preload("res://sim/world_item_operations.gd")
const Runtime=preload("res://sim/abilities/monster_ability_runtime.gd")
static func safe_cell(w,p:Vector2i)->bool:
	if not w.in_bounds(p) or not w.occupying_entities_at(p).is_empty():return false
	var terrain:String=w.tile_at(p).terrain
	return preload("res://sim/terrain_registry.gd").definition(terrain).get("passable",false) and terrain not in ["lava","deep_water","shallow_water","water"] and w.tile_at(p).fire==0 and w.tile_at(p).temperature<=400 and w.tile_at(p).smoke_amount==0
static func selection_valid(s:Dictionary)->bool:
	if s.is_empty():return true
	if s.size()!=1:return false
	if s.has("target_id"):return (s.target_id is int or s.target_id is float) and s.target_id==int(s.target_id) and s.target_id>0
	if s.has("item_id"):return s.item_id is String and not s.item_id.is_empty()
	if s.has("cell"):return s.cell is Array and s.cell.size()==2 and s.cell.all(func(x):return (x is int or x is float) and x==int(x))
	return false
static func cells(w,actor:int,visible:bool=true)->Array:
	var result:Array=[];var origin:Vector2i=w.entities[actor].position
	for y in range(origin.y-5,origin.y+6):
		for x in range(origin.x-5,origin.x+6):
			var p:=Vector2i(x,y)
			if p==origin or not w.in_bounds(p) or not w.occupying_entities_at(p).is_empty():continue
			if not safe_cell(w,p):continue
			if not preload("res://sim/combat_kernel.gd").sees(origin,p,w.combat_sight_blocked):continue
			if visible and not preload("res://sim/party_perception_registry.gd").field_visible(w,origin,p):continue
			result.append([x,y])
	return result
static func enemies(w,actor:int,radius:int)->Array:
	var result:Array=[]
	for id in w.party_encounter.enemy_ids:
		if Runtime.alive(w,id) and w.is_autonomous_target(id) and Runtime.distance(w.entities[actor].position,w.entities[id].position)<=radius and preload("res://sim/party_perception_registry.gd").field_visible(w,w.entities[actor].position,w.entities[id].position):result.append(id)
	return result
static func options(session,instance:String,actor_id:int=-1)->Array:
	var w=session.sim.world;var actor:int=session.consumable_actor_id() if actor_id==-1 else actor_id
	var owner:int=preload("res://sim/party_bag_rules.gd").owner(w,instance)
	var inventory=w.inventory_of(owner)
	var item=inventory.item(instance) if inventory!=null else null
	if item==null or not Mystery.has(item.definition_id) or not Mystery.known(w,item.definition_id):return []
	return _options(session,instance,actor)
static func _options(session,instance:String,actor_id:int=-1)->Array:
	var w=session.sim.world;var actor:int=session.consumable_actor_id() if actor_id==-1 else actor_id
	var owner:int=preload("res://sim/party_bag_rules.gd").owner(w,instance)
	var inventory=w.inventory_of(owner)
	var item=inventory.item(instance) if inventory!=null else null
	if item==null:return []
	var effect:String=Specs.definition(item.definition_id).effect;var result:Array=[]
	if effect=="POISON":result.append({"label":"직접 마시기","selection":{"target_id":actor}})
	if effect in ["SEAL","POISON"]:
		for id in enemies(w,actor,5):result.append({"label":("투척 · " if effect=="POISON" else "봉인 · ")+str(w.entities[id].display_name),"selection":{"target_id":id}})
	if effect=="BLINK":
		var origin:Vector2i=w.entities[actor].position
		for p in cells(w,actor):
			result.append({"label":"이동 (%+d, %+d)"%[p[0]-origin.x,p[1]-origin.y],"selection":{"cell":p}})
	if effect=="IDENTIFY":
		var seen:Dictionary={}
		for row in session.protagonist_inventory().backpack_rows:
			if row.instance_id==instance or row.get("identified",true) or seen.has(row.definition_id):continue
			seen[row.definition_id]=true;result.append({"label":str(row.label),"selection":{"item_id":str(row.instance_id)}})
	return result
static func use(session,instance:String,selection:Dictionary)->Dictionary:
	var w=session.sim.world;var actor:int=session.consumable_actor_id();var hero=w.entities[actor]
	var item=w.inventory_of(actor).item(instance)
	if item==null or not selection_valid(selection):return session._rejection_dto("invalid_item_selection")
	var id:String=item.definition_id;var d:Dictionary=Specs.definition(id);var effect:String=d.effect
	var was_known:bool=Mystery.known(w,id);var choices:=_options(session,instance)
	if effect in ["BLINK","SEAL","IDENTIFY","POISON"]:
		if not selection.is_empty() and not choices.any(func(r):return r.selection==selection):return {"accepted":false,"reason":"invalid_target","message":"선택할 수 없는 대상입니다."}
		if selection.is_empty() and not choices.is_empty():selection=choices[0].selection.duplicate(true)
		if choices.is_empty() and was_known:return {"accepted":false,"reason":"no_target","message":"사용할 대상이 없습니다."}
	elif not selection.is_empty():return session._rejection_dto("invalid_item_selection")
	var destination:Vector2i=hero.position
	if effect=="BLINK" and selection.has("cell"):destination=Vector2i(selection.cell[0],selection.cell[1])
	if effect=="TELEPORT":
		var available:=cells(w,actor,false)
		if not available.is_empty():
			var roll:int=("%d/%d/%s"%[w.seed,w.events.size(),instance]).sha256_buffer()[0]%available.size()
			destination=Vector2i(available[roll][0],available[roll][1])
		elif was_known:return {"accepted":false,"reason":"no_destination","message":"이동할 빈칸이 없습니다."}
	var rollback:Dictionary=session.sim.capture_rollback_memento(false);var journal:int=session.command_journal.size();var start:int=w.events.size()
	var consumed:Dictionary=Ops.commit_use(w,actor,instance,hero.position,session.ITEM_ACTION_TIME_COST)
	if not consumed.get("accepted",false):return consumed
	var target:int=int(selection.get("target_id",actor))
	var source=w.emit_event("consumable.activated",actor,target,hero.position,0,int(consumed.event_id),{"schema_version":1,"definition_id":id,"selection":selection})
	var ok:bool=source!=null
	if ok:
		match effect:
			"HASTE","ARMOR","REGEN","POISON","SLOW","WEAK","CONFUSION":ok=Effects.add(w,actor,target,effect,source.id)
			"CLEANSE":ok=w.emit_event("consumable.cleansed",actor,actor,hero.position,0,source.id,{"schema_version":1})!=null
			"BLINK","TELEPORT":
				if destination!=hero.position:ok=session.sim.movement.commit_preflighted_move(actor,destination,str(w.tile_at(destination).terrain),1,source.id)!=null
			"SEAL":
				if selection.has("target_id"):ok=Effects.add(w,actor,target,effect,source.id)
			"FEAR":
				for enemy in enemies(w,actor,4):ok=ok and Effects.add(w,actor,enemy,effect,source.id)
			"NOISE":
				for enemy in w.party_encounter.enemy_ids:
					if Runtime.alive(w,enemy) and Runtime.distance(hero.position,w.entities[enemy].position)<=10:ok=ok and Effects.add(w,actor,enemy,effect,source.id)
			"PUSH":
				for enemy in enemies(w,actor,2):
					var origin:Vector2i=w.entities[enemy].position
					var delta:=Vector2i(signi(origin.x-hero.position.x),signi(origin.y-hero.position.y))
					var landing:Vector2i=origin
					for n in range(2):
						var p:Vector2i=landing+delta
						if not safe_cell(w,p) or not w.diagonal_step_terrain_allowed(landing,p):break
						landing=p
					if landing!=origin:ok=ok and session.sim.movement.commit_preflighted_move(enemy,landing,str(w.tile_at(landing).terrain),1,source.id)!=null
			"MAP":ok=w.emit_event("consumable.map",actor,actor,hero.position,10,source.id,{"schema_version":1,"floor":w.party_encounter.expedition_cycle.floor_index,"generation":w.party_encounter.expedition_cycle.expedition_index})!=null
			"IDENTIFY":
				if selection.has("item_id"):
					var owner:int=preload("res://sim/party_bag_rules.gd").owner(w,selection.item_id)
					var selected=w.inventory_of(owner).item(selection.item_id) if owner!=-1 else null
					ok=selected!=null and w.emit_event("item.identified",actor,actor,hero.position,0,source.id,{"schema_version":1,"definition_id":selected.definition_id})!=null
	if ok and not was_known:ok=w.emit_event("item.identified",actor,actor,w.event_by_id(int(consumed.event_id)).position,0,int(consumed.event_id),{"schema_version":1,"definition_id":id})!=null
	w.party_encounter.revision+=1;session._clear_draft()
	var error:String=w.runtime_step_postcondition_error(start) if ok else "effect_failed"
	var advanced:Dictionary=session._advance_item_action_time() if error.is_empty() else {"accepted":false,"reason":error}
	if not advanced.get("accepted",false):
		session._rollback_session_transaction(rollback,journal)
		return {"accepted":false,"reason":str(advanced.get("reason","effect_failed")),"message":"사용을 완료하지 못해 소모하지 않았습니다."}
	while session.command_journal.size()>journal:session.command_journal.pop_back()
	session.command_journal.append({"kind":"item","operation":{"action":"USE","instance_id":instance,"slot":"","selection":selection}})
	session._deployment_plan.clear();session._invalidate_explored_presentation_cache()
	return session._feedback_dto({"accepted":true,"reason":"ok","message":str(d.name)+" · "+str(d.text),"inventory":session.protagonist_inventory(),"visual_effects":advanced.get("visual_effects",[]),"time_cost":session.ITEM_ACTION_TIME_COST})
