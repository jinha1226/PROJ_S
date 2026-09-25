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
		s.grant_item(s.Consumables.random_kind(s.seed_value,key))
	if outcome.get("item",false):
		if bonus < 50 and not part_ids.is_empty(): s.grant_part(part_ids[s.Hexaco.sample(s.seed_value,key,"curio_part",part_ids.size())])
		else: s.grant_item(s.Consumables.random_kind(s.seed_value,key+1))
	if int(outcome.get("spellbook_chance",0)) > 0 and s.Hexaco.sample(s.seed_value,key,"spellbook",100) < int(outcome.spellbook_chance):
		var casters: Array = s.Essences.CASTER_BY_SCHOOL.values()
		s.grant_part(str(casters[s.Hexaco.sample(s.seed_value,key,"spell_essence",casters.size())]))
	if int(outcome.get("gear_chance",0)) > 0 and s.Hexaco.sample(s.seed_value,key,"gear",100) < int(outcome.gear_chance):
		var by_depth: Dictionary = s.CombatStats.content.loot.gear_by_depth
		var tier := 1
		for level in by_depth:
			if int(level) <= s.depth: tier = maxi(tier,int(level))
		var options: Array = by_depth[str(tier)]
		var id: String = str(options[s.Hexaco.sample(s.seed_value,key,"gear_id",options.size())])
		s.grant_gear({"type":id.trim_prefix("ring:")})
	if got_food > 0: s.message("식량 %d 획득" % got_food)
	s.score += 5
	actor.ap -= 1; s.check_battle_end()
	if s.manual_mode:
		actor.ap = 1; s.Scheduler.advance(s,100)
	else: s.finish_player_action()
	return true
