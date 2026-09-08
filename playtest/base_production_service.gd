extends RefCounted

const Rules=preload("res://sim/base_production_rules.gd")
const Items=preload("res://sim/world_item_operations.gd")

static func assess(session,recipe_id:String)->Dictionary:
	for row in session.base_overview().get("production",[]):
		if row.recipe_id!=recipe_id:continue
		if not row.can_produce:return {"accepted":false,"reason":"base_production_unavailable","message":row.message}
		var recipe:Dictionary=Rules.RECIPES[recipe_id]
		for building in session.base_overview().settlement.buildings:
			if building.type_id==recipe.facility_id:
				return {"accepted":true,"type_id":recipe.facility_id,"cost":recipe.cost.duplicate(),
					"tile_origin":building.tile_origin.duplicate(),"footprint":building.footprint.duplicate(),
					"recipe_id":recipe_id,"work_steps":recipe.work_steps}
	return {"accepted":false,"reason":"base_recipe_unavailable"}

static func complete(world,job:Dictionary):
	var recipe:Dictionary=Rules.RECIPES[str(job.recipe_id)]
	return world.emit_event("base.production_completed",int(job.worker_id),-1,
		world.party_encounter.group_anchor,int(recipe.quantity),int(job.order_id),
		{"recipe_id":str(job.recipe_id),"definition_id":recipe.definition_id,"quantity":recipe.quantity})

static func claim(session,recipe_id:String)->Dictionary:
	var world=session.sim.world
	if int(Rules.ready_stock(world.events).get(recipe_id,0))<1:
		return {"accepted":false,"reason":"base_production_empty","message":"완성된 물약이 없습니다."}
	var hero_id:int=world.party_control_actor_id()
	if not world.can_act(hero_id,world.world_time):return {"accepted":false,"reason":"base_worker_missing"}
	var rollback:Variant=session.sim.capture_rollback_memento()
	if not rollback is Dictionary:return {"accepted":false,"reason":"snapshot_unavailable"}
	var recipe:Dictionary=Rules.RECIPES[recipe_id]
	var result:=Items.commit_grant(world,hero_id,str(recipe.definition_id),1,
		world.entities[hero_id].position,"BASE_PRODUCTION")
	if not bool(result.get("accepted",false)):
		result["message"]="가방 공간을 확인하세요. 완성품은 거점에 보관됩니다."
		return result
	var event=world.emit_event("base.production_claimed",hero_id,-1,
		world.party_encounter.group_anchor,1,-1,{"recipe_id":recipe_id,"quantity":1})
	world.party_encounter.revision+=1
	var error:String=world.world_state_error()
	if event==null or not error.is_empty():
		session.sim.restore_rollback_memento(rollback)
		return {"accepted":false,"reason":"base_production_claim_failed" if error.is_empty() else error}
	session.command_journal.append({"kind":"base_work","operation":{"action":"CLAIM","recipe_id":recipe_id}})
	return {"accepted":true,"reason":"ok","message":"회복 물약 1개를 가방에 넣었습니다."}
