extends RefCounted
## Stable human identities. Occupation is not a combat class or a race.
const PEOPLE := [
	{"name":"레아","job":"정찰자","explores":true,"weapon":"WEAPON_BOW"},
	{"name":"도윤","job":"호위꾼","explores":true,"weapon":"WEAPON_SPEAR"},
	{"name":"마렌","job":"채집가","explores":true,"weapon":"WEAPON_MACE"},
	{"name":"이안","job":"유적 조사원","explores":true,"weapon":"WEAPON_SHORT_SWORD"},
	{"name":"세린","job":"약초꾼","explores":true,"weapon":"WEAPON_SPEAR"},
	{"name":"유나","job":"보물 사냥꾼","explores":true,"weapon":"WEAPON_BOW"},
	{"name":"로웬","job":"운반꾼","explores":true,"weapon":"WEAPON_MACE"},
	{"name":"하린","job":"견습 모험가","explores":true,"weapon":"WEAPON_SHORT_SWORD"},
	{"name":"올가","job":"여관 주인","explores":false,"weapon":"WEAPON_MACE"},
	{"name":"브람","job":"대장장이","explores":false,"weapon":"WEAPON_MACE"},
	{"name":"미나","job":"치유사","explores":false,"weapon":"WEAPON_SHORT_SWORD"},
	{"name":"테오","job":"상인","explores":false,"weapon":"WEAPON_SHORT_SWORD"},
	{"name":"리사","job":"요리사","explores":false,"weapon":"WEAPON_MACE"},
	{"name":"고든","job":"창고 관리인","explores":false,"weapon":"WEAPON_SPEAR"},
]
const FLOOR_COUNT := 8
const PATROL_INTERVAL := 400

static func identity(name:String)->Dictionary:
	for row in PEOPLE:
		if row.name==name:return row.duplicate(true)
	return {"name":name,"job":"모험가","explores":true,"weapon":"WEAPON_SHORT_SWORD"}

static func town_activity(name:String,id:int,visit:int,profile)->Dictionary:
	var person:=identity(name)
	var places:={"여관 주인":["여관 손님 맞이",[12,4],"INN","여관"],"대장장이":["장비 수선",[12,10],"ARMORY","대장간"],
		"치유사":["환자 돌보기",[2,11],"CLINIC","치유소"],"상인":["물자 거래",[6,10],"MARKET","시장"],
		"요리사":["식사 준비",[11,4],"INN","여관 주방"],"창고 관리인":["물자 정리",[2,5],"STORAGE","보관소"]}
	if places.has(person.job):
		var activity:Array=places[person.job]
		return {"label":activity[0],"location":activity[3],"tile":activity[1],"facility_id":activity[2]}
	# Adventurers gather at the inn between expeditions; civic workers remain
	# at their own workplaces. The roster and map use this same projection.
	var routines:=[{"label":"여관에서 휴식","location":"여관","tile":[13,5]},
		{"label":"원정 물자 꾸리는 중","location":"여관","tile":[11,5]},
		{"label":"장비 점검 중","location":"여관","tile":[12,6]},
		{"label":"원정 이야기 중","location":"여관","tile":[10,5]}]
	var offset:=1 if profile!=null and profile.value("X")>=500 else 0
	var result:Dictionary=routines[posmod(id+visit+offset,4)].duplicate(true)
	result.facility_id="INN"
	result.tile=[int(result.tile[0])+posmod(id,2),int(result.tile[1])+posmod(id/2,2)]
	return result

static func locations(world)->Array:
	var cycle=world.party_encounter.expedition_cycle
	if cycle.phase!="DUNGEON":return []
	for index in range(world.events.size()-1,-1,-1):
		var event=world.events[index]
		if event.type not in ["population.floor_arrived","population.patrol"]:continue
		if int(event.data.get("floor_index",0))==int(cycle.floor_index) \
			and int(event.data.get("expedition_index",0))==int(cycle.expedition_index):
			return event.data.rows.duplicate(true)
	return []

static func interaction_error(value:Variant)->String:
	if not value is Dictionary:return "invalid_population_command"
	var keys:Array=value.keys();keys.sort()
	if keys!=["action","entity_id"] or value.get("action") not in ["GREET","AID","HEAL","ACCEPT"]:
		return "invalid_population_command"
	var id:Variant=value.get("entity_id")
	return "" if id is String and id.is_valid_int() and int(id)>0 and str(int(id))==id else "invalid_population_actor"
