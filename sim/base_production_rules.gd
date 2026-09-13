extends RefCounted

## Finished goods stay at the base until claimed. No inventory is generated
## while reading the overview, and cancelled work never produces output.
const RECIPES := {
	"HEALING_POTION": {"label":"회복 물약", "facility_id":"CLINIC",
		"cost":{"HERBS":2}, "definition_id":"POTION_HEALING",
		"quantity":1, "work_steps":8, "stock_limit":6},
}

static func ready_stock(events:Array)->Dictionary:
	var stock:Dictionary={}
	for id in RECIPES:stock[id]=0
	for event in events:
		if event.type not in ["base.production_completed","base.production_claimed"]:continue
		var id:=str(event.data.get("recipe_id",""))
		if stock.has(id):
			stock[id]+=int(event.data.get("quantity",0)) * (1 if event.type=="base.production_completed" else -1)
	return stock

static func overview(world,buildings:Array,stock:Dictionary,work:Dictionary)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	var ready:Dictionary=preload("res://sim/settlement_work_rules.gd").index(world).ready
	var town:bool=world.party_encounter.expedition_cycle.phase=="TOWN"
	for id in RECIPES:
		var recipe:Dictionary=RECIPES[id]
		var built:=preload("res://sim/base_settlement_rules.gd").type_built(buildings,recipe.facility_id)
		var pending:=0
		for job in preload("res://sim/settlement_work_rules.gd").active(preload("res://sim/settlement_work_rules.gd").index(world).state):
			if str(job.get("recipe_id",""))==str(id) and not bool(job.get("cancel_requested",false)):pending+=1
		var message:="제조 가능"
		if not town:message="거점에서 제조할 수 있습니다"
		elif not built:message="진료소를 먼저 건설하세요"
		elif not work.is_empty():message="진행 중인 작업을 먼저 마치세요"
		elif int(ready[id])+pending>=int(recipe.stock_limit):message="진행 중 주문과 완성품이 보관 한도에 도달했습니다"
		elif not preload("res://sim/base_progression_rules.gd").can_afford(stock,recipe.cost):
			message="제조 가능" if preload("res://sim/settlement_work_rules.gd").index(world).state.enabled else "약초가 부족합니다"
		result.append({"recipe_id":id,"label":recipe.label,"facility_id":recipe.facility_id,
			"cost":recipe.cost.duplicate(),"quantity":recipe.quantity,"ready":ready[id],"pending":pending,
			"stock_limit":recipe.stock_limit,"can_produce":message=="제조 가능",
			"can_claim":town and int(ready[id])>0,"message":message})
	return result
