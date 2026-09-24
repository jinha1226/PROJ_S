extends RefCounted
## Camp: rest, the spell slots prepared there and the books read into them.
const CombatStats = preload("res://expedition/combat/combat_stats.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Mastery = preload("res://expedition/progression/mastery.gd")
const Spells = preload("res://expedition/spells/spells.gd")
## How many spells a caster may hold ready at once, chosen at camp.
const PREPARED_SLOTS := 5

static func can_camp(s) -> String:
	if s.phase != "EXPLORE": return "지금은 불가"
	if not s.floor_state.safe(s): return "적이 보임"
	var needed: int = s.alive().size()
	if s.food < needed: return "식량 %d 필요" % needed
	return ""

static func camp(s) -> bool:
	if not s.can_camp().is_empty(): return false
	s.auto.running = false
	s.food -= s.alive().size()
	for actor in s.alive():
		actor.hp = mini(actor.max_hp,actor.hp+ceili(actor.max_hp*0.5))
		s.stress(actor,-30)
		for id in actor.cooldowns: actor.cooldowns[id] = 0
	s.phase = "CAMP"; s.intents.clear()
	s.message("야영 · 식량 -%d" % s.alive().size()); return true

static func end_camp(s) -> bool:
	if s.phase != "CAMP": return false
	s.phase = "EXPLORE"
	for actor in s.alive(): actor.ap = s.action_budget(actor)
	s.floor_state.observe(s); return true

static func prepare_spell(s, index: int, id: String, on: bool) -> bool:
	if s.phase != "CAMP" or index < 0 or index >= s.party.size(): return false
	var actor: Dictionary = s.party[index]
	if id not in actor.spells or Spells.definition(id).is_empty(): return false
	if on:
		if id in actor.prepared: return true
		if actor.prepared.size() >= PREPARED_SLOTS: return false
		actor.prepared.append(id)
	else:
		actor.prepared.erase(id)
	return true

## Learning is a camp's work and nothing else's: the book has to be in the bag
## and the school one rank short of the spell's level. Rank rises by casting,
## so nothing is ever unlocked on its own.
static func learn_spell(s, index: int, id: String) -> bool:
	if index < 0 or index >= s.party.size(): return false
	var actor: Dictionary = s.party[index]
	if not Spells.learnable(s,actor,id).is_empty(): return false
	actor.spells.append(id)
	s.message(str(CombatStats.content.spells[id].name)+" 획득")
	return true

## A book found in the dungeon. It stays in the bag and can be read again.
static func grant_book(s, book_id: String) -> bool:
	var row: Dictionary = Spells.book(book_id)
	if row.is_empty() or s.party.is_empty(): return false
	if book_id not in s.party[0].books: s.party[0].books.append(book_id)
	s.message(str(row.name)+" 획득")
	return true

## Which grade a floor gives up: 중급서 from the third floor down, 고급서 from
## the sixth. `top` takes the best the depth allows — what a boss carries.
static func book_tier(s, key: int, top: bool = false) -> int:
	var depths: Dictionary = CombatStats.content.loot.books.tier_depth
	var allowed: Array = []
	for tier in depths:
		if s.depth >= int(depths[tier]): allowed.append(int(tier))
	if allowed.is_empty(): allowed = [1]
	allowed.sort()
	if top: return int(allowed[allowed.size()-1])
	return int(allowed[Hexaco.sample(s.seed_value,key,"book_tier",allowed.size())])

## Any school's book, not only the hero's: this is how a run goes multi-school.
static func random_book(s, key: int, top: bool = false) -> String:
	var schools: Array = Mastery.AXES.slice(5)
	return "%s_%d" % [str(schools[Hexaco.sample(s.seed_value,key,"book_school",schools.size())]),s.book_tier(key,top)]
