extends RefCounted
const Life=preload("res://sim/town_life_rules.gd")
static func enabled(session)->bool:
	if session==null or session.sim==null or session.sim.world==null or session.sim.world.party_encounter==null:return false
	var hero=session.sim.world.entities.get(session.sim.world.party_encounter.protagonist_id)
	return hero!=null and "frontier_campaign" in hero.tags
static func objective(session)->String:
	var world=session.sim.world
	if session.company_member_ids().size()>1:return "첫 공동체 완성 · 주민과 휴식하고 창고·숙소를 정비하세요."
	for id in world.party_encounter.active_party_member_ids:
		if id!=world.party_encounter.protagonist_id and "expedition_companion" in world.entities[id].tags:
			return "생존자와 입구로 귀환하세요 · 메뉴에서 피난처 귀환"
	return "숲길 초입의 생존자에게 식량을 나누고 동행을 수락하세요."
static func region(floor_index:int)->String:
	return "변방 숲길 · 옛 유적" if floor_index==1 else "폐광"
