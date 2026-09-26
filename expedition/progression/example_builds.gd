extends RefCounted
## Arena-only loadouts. No bag, discovery or persistent codex writes.
const Essences = preload("res://expedition/progression/essences.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/example_builds.json"))

static func build(id: String) -> Dictionary:
	for row in data.get("builds",[]):
		if str(row.id) == id: return row
	return {}

static func party(id: String) -> Dictionary:
	for row in data.get("parties",[]):
		if str(row.id) == id: return row
	return {}

static func apply(s, actor: Dictionary, id: String) -> bool:
	var b := build(id)
	if b.is_empty(): return false
	var gained: int = int(b.get("level",10))-int(actor.get("level",1))
	actor.level = int(b.get("level",10))
	# Match normal level growth, without generating level-up logs or run events.
	actor.max_hp = int(actor.get("max_hp",0))+4*gained
	actor.max_mp = int(actor.get("max_mp",0))+2*gained
	actor.level_xp = maxi(0,(int(actor.level)-1)*(int(actor.level)-1)*65)
	actor.essences = {}; actor.essence_spells = {}; actor.equipped_abilities = []; actor.rules = []
	actor.sealed = {}; actor.cooldowns = {}; actor.reservation = {}
	Essences.sync_slots(actor)
	for i in range(b.stones.size()):
		var stone: String = str(b.stones[i])
		actor.essences[stone] = 1
		Essences.put(actor,i,stone)
	for stone in b.stones:
		var choices := Essences.spell_choices(actor,str(stone))
		if not choices.is_empty(): actor.essence_spells[str(stone)] = str(choices.back())
	Essences.sync_spells(actor)
	actor.gear = {}
	var gear := Equipment.worn(actor)
	for slot in ["weapon","offhand","armour"]:
		var type: String = str(b.get(slot,""))
		gear[slot] = {} if type.is_empty() else {"type":type,"tier":"base","enchant":0}
	if Equipment.hands(gear.weapon) == 2: gear.offhand = {}
	for i in range(mini(2,b.get("rings",[]).size())):
		gear["ring%d" % (i+1)] = {"type":str(b.rings[i]),"tier":"base","enchant":0}
	actor.stance = str(b.get("stance","CHARGER"))
	if s != null:
		StatSheet.refresh_pools(s,actor)
		actor.hp = int(actor.max_hp); actor.mp = int(actor.get("max_mp",0))
	return true
