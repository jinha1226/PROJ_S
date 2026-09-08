class_name BaseProgressionRules
extends RefCounted

const RULESET_ID := "small-base-progression-v1"
const RESOURCE_IDS := ["TIMBER", "STONE", "HERBS"]
const FACILITY_IDS := ["STORAGE", "LODGE", "CLINIC"]
const MAX_LEVEL := 3
const STARTER_STOCK := {"TIMBER":4, "STONE":2, "HERBS":2}
const FACILITY_LABELS := {
	"STORAGE":"창고", "LODGE":"숙소", "CLINIC":"진료소"}
const UPGRADE_COSTS := {
	"STORAGE":{2:{"TIMBER":8,"STONE":5,"HERBS":0},
		3:{"TIMBER":14,"STONE":10,"HERBS":0}},
	"LODGE":{2:{"TIMBER":6,"STONE":3,"HERBS":2},
		3:{"TIMBER":12,"STONE":8,"HERBS":5}},
	"CLINIC":{2:{"TIMBER":4,"STONE":4,"HERBS":6},
		3:{"TIMBER":8,"STONE":8,"HERBS":12}},
}
const STORAGE_CAPACITY := {1:8, 2:12, 3:18}
const LODGE_STRESS_RECOVERY := {1:300, 2:450, 3:650}
const CLINIC_GOLD_COST := {1:25, 2:20, 3:15}
const CLINIC_POTION_STOCK := {1:4, 2:5, 3:6}
const TRADE_PRICES := {"TIMBER":2, "STONE":3, "HERBS":4}


static func facility_levels(events:Array)->Dictionary:
	var result := {"STORAGE":1, "LODGE":1, "CLINIC":1}
	for event in events:
		if str(event.type)!="base.facility_upgraded":continue
		var facility_id:=str(event.data.get("facility_id",""))
		if facility_id in FACILITY_IDS:
			result[facility_id]=maxi(int(result[facility_id]),
				int(event.data.get("to_level",1)))
	return result


static func secured_stock(events:Array,current_expedition_index:int,
		current_phase:String)->Dictionary:
	var result:Dictionary=STARTER_STOCK.duplicate(true)
	for event in events:
		match str(event.type):
			"base.resource_gathered":
				var expedition_index:=int(event.data.get("expedition_index",0))
				if expedition_index<current_expedition_index or (expedition_index \
						==current_expedition_index and current_phase=="TOWN"):
					var resource_id:=str(event.data.get("resource_id",""))
					if resource_id in RESOURCE_IDS:
						result[resource_id]+=int(event.data.get("amount",0))
			"base.facility_upgraded":
				for resource_id in RESOURCE_IDS:
					result[resource_id]-=int(event.data.get("cost",{}).get(
						resource_id,0))
			"base.resource_sold":
				var resource_id:=str(event.data.get("resource_id",""))
				if resource_id in RESOURCE_IDS:
					result[resource_id]-=int(event.data.get("amount",0))
			"base.building_constructed","base.work_ordered":
				for resource_id in RESOURCE_IDS:
					result[resource_id]-=int(event.data.get("cost",{}).get(
						resource_id,0))
			"base.work_cancelled":
				for resource_id in RESOURCE_IDS:
					result[resource_id]+=int(event.data.get("cost",{}).get(resource_id,0))
	return result


static func carried(events:Array,expedition_index:int,phase:String)->Dictionary:
	var result := {"TIMBER":0, "STONE":0, "HERBS":0}
	if phase!="DUNGEON":return result
	for event in events:
		if str(event.type)!="base.resource_gathered" \
				or int(event.data.get("expedition_index",0))!=expedition_index:
			continue
		var resource_id:=str(event.data.get("resource_id",""))
		if resource_id in RESOURCE_IDS:
			result[resource_id]+=int(event.data.get("amount",0))
	return result


static func total_resources(stock:Dictionary)->int:
	var result:=0
	for resource_id in RESOURCE_IDS:result+=int(stock.get(resource_id,0))
	return result


static func cost(facility_id:String,next_level:int)->Dictionary:
	return UPGRADE_COSTS.get(facility_id,{}).get(next_level,{}).duplicate(true)


static func can_afford(stock:Dictionary,price:Dictionary)->bool:
	for resource_id in RESOURCE_IDS:
		if int(stock.get(resource_id,0))<int(price.get(resource_id,0)):return false
	return true


static func effect_text(facility_id:String,level:int)->String:
	match facility_id:
		"STORAGE":return "원정 운반 한도 %d"%int(STORAGE_CAPACITY[level])
		"LODGE":return "휴식 스트레스 회복 %d"%int(LODGE_STRESS_RECOVERY[level])
		"CLINIC":return "치료비 %d골드 · 회복 물약 재고 %d"%[
			int(CLINIC_GOLD_COST[level]),int(CLINIC_POTION_STOCK[level])]
	return ""
