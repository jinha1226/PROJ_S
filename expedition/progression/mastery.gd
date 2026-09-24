extends RefCounted
## Ten use-based skills. XP is kept per actor, including unaffiliated NPCs.
const AXES := ["sword", "spear", "mace", "axe", "bow", "fire", "ice", "air", "hex", "summon"]
const NAMES := {"sword":"검술", "spear":"창술", "mace":"둔기술", "axe":"도끼술", "bow":"궁술", "fire":"화염술", "ice":"냉기술", "air":"기류술", "hex":"변이·제어", "summon":"소환술"}
static var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/mastery.json"))
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))

static func weapon_axis(weapon_type: String) -> String:
	match weapon_type:
		"sword", "dagger": return "sword"
		"spear": return "spear"
		"mace", "staff": return "mace"
		"axe": return "axe"
		"bow": return "bow"
	return "sword"

static func rank(actor: Dictionary, axis: String) -> int:
	var xp: int = int(actor.get("skill_xp", {}).get(axis, 0))
	var result := 0
	for level in range(1,11):
		var needed: int = required_xp(actor,axis,level)
		if xp < needed: break
		result = level
	return result

static func required_xp(actor: Dictionary, axis: String, level: int) -> int:
	var needed := 25*level*level
	if bool(actor.get("catchup_axes",{}).get(axis,false)) and level <= 2: needed = ceili(needed/2.0)
	return needed

static func next_xp(level: int) -> int:
	return 25 * (level + 1) * (level + 1)

static func bonus(axis: String, level: int) -> String:
	if axis in AXES.slice(0, 5): return "피해 +%d · 공격 시간 -%d" % [level, level * 4]
	return "위력 +%d · 실패율 -%d%%" % [level, level * 5]

static func aptitude(actor: Dictionary, axis: String) -> int:
	var spec: Dictionary = combat.species.get(str(actor.get("species_id","human")),combat.species.human)
	var key := "melee" if axis in AXES.slice(0,4) else axis
	return int(spec.get("apt",{}).get(key,100))

static func catchup(actor: Dictionary, axis: String) -> bool:
	if axis not in AXES.slice(0,5) or rank(actor,axis) > 0: return false
	if not actor.has("catchup_axes"): actor.catchup_axes = {}
	actor.catchup_axes[axis] = true
	return true

static func unlocked(actor: Dictionary, axis: String) -> Array:
	var result: Array = []
	var rows: Dictionary = content.milestones.get(axis,{})
	for level in rows:
		var entry: Dictionary = rows[level]
		if not str(entry.get("effect_id","")).is_empty() and int(level) <= rank(actor,axis):
			result.append({"level":int(level),"name":str(entry.name),"effect_id":str(entry.effect_id)})
	return result

static func fusions(actor: Dictionary) -> Array:
	var result: Array = []
	for id in content.fusions:
		var row: Dictionary = content.fusions[id]
		if rank(actor,str(row.main)) >= int(row.main_rank) and rank(actor,str(row.sub)) >= int(row.sub_rank): result.append(id)
	return result

static func add_xp(actor: Dictionary, axis: String, amount: int) -> int:
	if axis not in AXES or amount <= 0: return 0
	if not actor.has("skill_xp"): actor.skill_xp = {}
	var old_rank := rank(actor, axis)
	var apt: int = aptitude(actor,axis)
	actor.skill_xp[axis] = mini(2500, int(actor.skill_xp.get(axis, 0)) + maxi(1, amount * apt / 100))
	return rank(actor, axis) - old_rank

static func record(actor: Dictionary, enemy_id: int, axis: String) -> void:
	if axis not in AXES or enemy_id < 0: return
	if not actor.has("usage"): actor.usage = {}
	var uses: Dictionary = actor.usage.get(enemy_id, {})
	uses[axis] = int(uses.get(axis, 0)) + 1
	actor.usage[enemy_id] = uses

static func award(actors: Array, enemy_id: int, amount: int) -> void:
	var total := 0
	var entries: Array = []
	for actor in actors:
		var uses: Dictionary = actor.get("usage", {}).get(enemy_id, {})
		for axis in uses:
			var count: int = int(uses[axis]); total += count
			entries.append({"actor":actor,"axis":str(axis),"count":count,"share":0,"remainder":0})
	if total <= 0: return
	var distributed := 0
	for entry in entries:
		entry.share = amount*int(entry.count)/total
		entry.remainder = amount*int(entry.count)%total
		distributed += int(entry.share)
	entries.sort_custom(func(a,b): return int(a.remainder) > int(b.remainder) or int(a.remainder) == int(b.remainder) and (int(a.actor.id) < int(b.actor.id) or int(a.actor.id) == int(b.actor.id) and str(a.axis) < str(b.axis)))
	for i in range(amount-distributed): entries[i].share += 1
	for entry in entries: add_xp(entry.actor,str(entry.axis),int(entry.share))
	for actor in actors: actor.get("usage",{}).erase(enemy_id)
