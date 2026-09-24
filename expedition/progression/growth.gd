extends RefCounted
## Adapted from legacy GrowthBuildState and rebuilt/progression.gd.
const AXES = {"MELEE":"근접","RANGED":"원거리","MAGIC":"마법","DEFENSE":"방어"}
const STATS = {"STR":"근력","DEX":"민첩","INT":"지능"}
const MAX_LEVEL = 21
const MAX_RANK = 10

static func create() -> Dictionary:
	return {"xp":0,"level":1,"points":0,"stat_points":0,"ranks":{"MELEE":0,"RANGED":0,"MAGIC":0,"DEFENSE":0},"stats":{"STR":0,"DEX":0,"INT":0}}

static func threshold(level: int) -> int:
	return 100*(level-1)*(level-1)

static func gain(actor: Dictionary, amount: int) -> int:
	var g: Dictionary = actor.growth
	var before: int = g.level
	g.xp = mini(threshold(MAX_LEVEL),g.xp+maxi(0,amount))
	while g.level < MAX_LEVEL and g.xp >= threshold(g.level+1):
		g.level += 1; g.points += 1
		if g.level % 3 == 0: g.stat_points += 1
		actor.max_hp += 4; actor.hp = mini(actor.max_hp,actor.hp+4)
	return g.level-before

static func spend(actor: Dictionary, id: String, stat: bool = false) -> bool:
	var g: Dictionary = actor.growth
	var pool := "stat_points" if stat else "points"
	var rows: Dictionary = g.stats if stat else g.ranks
	if not rows.has(id) or g[pool] <= 0 or (not stat and rows[id] >= MAX_RANK): return false
	g[pool] -= 1; rows[id] += 1; return true

static func power(actor: Dictionary, axis: String, base: int) -> int:
	var attribute: String = {"MELEE":"STR","RANGED":"DEX","MAGIC":"INT"}[axis]
	return int(round((base+actor.growth.stats[attribute]*2)*(1.0+actor.growth.ranks[axis]*0.08)))

static func incoming(actor: Dictionary, amount: int) -> int:
	return maxi(1,int(round(amount*(1.0-actor.growth.ranks.DEFENSE*0.04))))
