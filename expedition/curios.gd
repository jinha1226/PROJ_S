extends RefCounted
## Floor curios yield food and occasional parts or supplies without tools.
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/exploration_curios.json"))

static func definition(feature: Dictionary) -> Dictionary:
	return content.curios.get(feature.get("curio_id",""),{})

static func error(s, point: Vector2i, option: String) -> String:
	if s.phase != "EXPLORE": return "조사 불가"
	var feature: Dictionary = s.floor_state.features.get(point,{})
	var def: Dictionary = definition(feature)
	if def.is_empty() or not s.floor_state.visible.has(point): return "시야 밖"
	if feature.used: return "조사 완료"
	var actor: Dictionary = s.party[s.selected]
	if actor.hp <= 0 or actor.ap <= 0: return "행동 불가"
	if not s.party_enemies().is_empty(): return "주변에 적 있음"
	if actor.pos != point and not s.melee_reach(actor.pos,point): return "거리 초과"
	if not def.options.has(option): return "선택 불가"
	return ""

static func resolve(s, point: Vector2i, option: String) -> bool:
	if not error(s,point,option).is_empty(): return false
	var feature: Dictionary = s.floor_state.features[point]
	var def: Dictionary = definition(feature)
	var choice: Dictionary = def.options[option]
	var actor: Dictionary = s.party[s.selected]
	var key: int = s.depth*10000+point.y*100+point.x
	var roll: int = s.Hexaco.sample(s.seed_value,key,"curio",100)
	var outcome: Dictionary = choice.success if roll < int(choice.chance) else choice.get("failure",{})
	feature.used = true
	var food_value: Variant = outcome.get("food",0)
	var got_food: int = int(food_value[0])+s.Hexaco.sample(s.seed_value,key,"curio_amount",int(food_value[1])-int(food_value[0])+1) if food_value is Array else int(food_value)
	s.food += got_food
	if outcome.has("damage"): s.damage(actor,int(outcome.damage),999,"IMPACT")
	if outcome.has("stress"): s.stress(actor,int(outcome.stress))
	var bonus: int = s.Hexaco.sample(s.seed_value,key,"curio_bonus",100)
	var part_ids: Array = s.Abilities.droppable()
	if bonus < int(outcome.get("part_chance",0)) and not part_ids.is_empty():
		s.grant_part(part_ids[s.Hexaco.sample(s.seed_value,key,"curio_part",part_ids.size())])
	elif bonus < int(outcome.get("part_chance",0))+int(outcome.get("supply_chance",0)):
		s.grant_supply(s.Hexaco.sample(s.seed_value,key,"curio_supply",s.supplies.size()))
	if outcome.get("item",false):
		if bonus < 50 and not part_ids.is_empty(): s.grant_part(part_ids[s.Hexaco.sample(s.seed_value,key,"curio_part",part_ids.size())])
		else: s.grant_supply(s.Hexaco.sample(s.seed_value,key,"curio_supply",s.supplies.size()))
	if got_food > 0: s.message("식량 %d 획득" % got_food)
	s.score += 5
	actor.ap -= 1; s.check_battle_end(); s.finish_player_action()
	return true
