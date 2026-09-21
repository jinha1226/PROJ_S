extends RefCounted
## Content defines tool requirements, odds and outcomes; this is the only executor.
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/exploration_curios.json"))

static func definition(feature: Dictionary) -> Dictionary:
	return content.curios.get(feature.get("curio_id",""),{})

static func error(s, point: Vector2i, option: String) -> String:
	if not s.floor_mode or s.phase != "BATTLE": return "탐험 중에만 조사할 수 있습니다."
	var feature: Dictionary = s.floor_state.features.get(point,{})
	var def := definition(feature)
	if def.is_empty() or not s.floor_state.visible.has(point): return "보이는 조사물을 선택하세요."
	if feature.used: return "이미 조사한 곳입니다."
	var actor: Dictionary = s.party[s.selected]
	if actor.hp <= 0 or actor.ap <= 0: return "지금은 행동할 수 없습니다."
	if not s.combat_enemies().is_empty(): return "주변 적을 먼저 처리하세요."
	if actor.pos != point and not s.melee_reach(actor.pos,point): return "조사물 옆으로 이동하세요."
	if not def.options.has(option): return "사용할 수 없는 선택입니다."
	var choice: Dictionary = def.options[option]
	if int(s.exploration_tools.get(choice.get("tool",""),0)) < int(choice.get("cost",0)): return "필요한 도구가 없습니다."
	return ""

static func resolve(s, point: Vector2i, option: String) -> bool:
	var reason := error(s,point,option)
	if not reason.is_empty(): return false
	var feature: Dictionary = s.floor_state.features[point]
	var def := definition(feature)
	var choice: Dictionary = def.options[option]
	var actor: Dictionary = s.party[s.selected]
	# Roll depends on this expedition and object, never on opening/closing the UI.
	var roll: int = s.Hexaco.sample(s.seed_value,s.expedition_number*10000+point.y*100+point.x,"curio",100)
	var outcome: Dictionary = choice.success if roll < int(choice.chance) else choice.get("failure",{})
	feature.used = true
	if choice.has("tool"): s.exploration_tools[choice.tool] -= int(choice.cost)
	s.loot += int(outcome.get("loot",0)); s.food += int(outcome.get("food",0))
	if outcome.has("damage"): s.damage(actor,int(outcome.damage),999,"IMPACT")
	if outcome.has("stress"): s.stress(actor,int(outcome.stress))
	s.message(def.name+" · "+str(outcome.get("text","조사를 마쳤습니다."))+" (전리품 +%d / 식량 +%d)" % [outcome.get("loot",0),outcome.get("food",0)])
	actor.ap -= 1; s.check_battle_end(); s.finish_player_action()
	return true
