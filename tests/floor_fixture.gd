extends RefCounted
## Layout-independent test arenas for the procedural floor.
static func arena(s, half: int = 8) -> Vector2i:
	var c := Vector2i(s.BOARD_SIDE/2,s.BOARD_SIDE/2)
	for y in range(maxi(1,c.y-half),mini(s.BOARD_SIDE-1,c.y+half+1)):
		for x in range(maxi(1,c.x-half),mini(s.BOARD_SIDE-1,c.x+half+1)):
			var cell: Dictionary = s.tile(Vector2i(x,y))
			cell.terrain = "stone"; cell.fire = 0; cell.wet = 0
	for enemy in s.enemies: enemy.hp = 0
	for p in s.floor_state.features.keys():
		if maxi(absi(p.x-c.x),absi(p.y-c.y)) <= half: s.floor_state.features.erase(p)
	s.party[0].pos = c
	for i in range(1,s.party.size()): s.party[i].pos = c+Vector2i(0,i)
	s.floor_state.observe(s)
	return c

static func beside(s, p: Vector2i) -> Vector2i:
	for d in s.DIRECTIONS:
		var cell: Vector2i = p+d
		if s.inside(cell) and s.tile(cell).terrain != "wall" and s.melee_reach(cell,p) and s.at(cell).is_empty(): return cell
	return Vector2i(-1,-1)

## Equips the two basics on every member with their default rules, the
## pre-parts starting state most suites assume.
static func equip_basics(s) -> void:
	var abilities = load("res://expedition/items/abilities.gd")
	for actor in s.party:
		actor.equipped_abilities = ["PUSH","GUARD"]
		actor.rules = [abilities.default_rule("PUSH"),abilities.default_rule("GUARD")]

## One rules-driven round, the same call the game's auto button makes. The
## expedition bots fight through this instead of pressing auto_attack.
static func fight_round(s) -> bool:
	return s.auto_step()

## The manual rules' one player action, chosen by the same companion utility.
static func hero_turn(s) -> bool:
	var hero: Dictionary = s.party[0]
	hero.ap = 1
	var choice: Dictionary = s.Tactics.choose(s,hero)
	return s.submit(str(choice.get("kind","WAIT")),choice.get("cell",hero.pos))
