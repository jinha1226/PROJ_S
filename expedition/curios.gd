extends RefCounted
## Content defines tool requirements, odds and outcomes; this is the only executor.
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/exploration_curios.json"))

static func definition(feature: Dictionary) -> Dictionary:
	return content.curios.get(feature.get("curio_id",""),{})

static func error(s, point: Vector2i, option: String) -> String:
	if not s.floor_mode or s.phase != "BATTLE": return "조사 불가"
	var feature: Dictionary = s.floor_state.features.get(point,{})
	var def := definition(feature)
	if def.is_empty() or not s.floor_state.visible.has(point): return "시야 밖"
	if feature.used: return "조사 완료"
	var actor: Dictionary = s.party[s.selected]
	if actor.hp <= 0 or actor.ap <= 0: return "행동 불가"
	if not s.combat_enemies().is_empty(): return "주변에 적 있음"
	if actor.pos != point and not s.melee_reach(actor.pos,point): return "거리 초과"
	if not def.options.has(option): return "선택 불가"
	var choice: Dictionary = def.options[option]
	if int(s.exploration_tools.get(choice.get("tool",""),0)) < int(choice.get("cost",0)): return "도구 부족"
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
	if choice.has("tool"): s.add_stock("tool:"+str(choice.tool),-int(choice.cost))
	var loot: int = s.loot_scaled(int(outcome.get("loot",0)))
	s.loot += loot; s.add_stock("food",int(outcome.get("food",0)))
	if outcome.has("damage"): s.damage(actor,int(outcome.damage),999,"IMPACT")
	if outcome.has("stress"): s.stress(actor,int(outcome.stress))
	if loot > 0: s.message("전리품 %d 획득" % loot)
	if int(outcome.get("food",0)) > 0: s.message("식량 %d 획득" % int(outcome.food))
	if int(outcome.get("stress",0)) != 0: s.message("스트레스 %+d" % int(outcome.stress))
	if loot == 0 and int(outcome.get("food",0)) == 0: s.message(def.name+" · 빈손")
	actor.ap -= 1; s.check_battle_end(); s.finish_player_action()
	return true
