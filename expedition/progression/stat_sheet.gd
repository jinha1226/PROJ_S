extends RefCounted
## Every number a fight reads, each with where it came from: the species, the
## gear, the essences and their sets. A monster carries its own numbers.
const Essences = preload("res://expedition/progression/essences.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
static var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/combat.json"))
const KEYS := ["str","dex","int","con","atk","hp","spell","mp","speed","dodge","ac","ev","sh","res_fire","res_ice","res_air","res_poison","res_will"]
const NAMES := {"str":"근력","dex":"민첩","int":"정신","con":"체력","atk":"공격력","hp":"최대 HP","spell":"주문력","mp":"최대 MP",
	"speed":"행동 속도","dodge":"회피율","ac":"방어","ev":"회피","sh":"막기",
	"res_fire":"화염 저항","res_ice":"냉기 저항","res_air":"전기 저항","res_poison":"독 저항","res_will":"의지 저항"}
const RES := ["fire","ice","air","poison","will"]
const RES_CAP := 80
## 행동 속도 in percent: every delay shrinks by it, forty at most.
const SPEED_CAP := 40
const BLOCK_CAP := 50
const SHIELD_BLOCK := 15
const CON_BASE := 10
const HP_PER_CON := 3
## What a monster's mind is taken to be when a spell asks.
const MONSTER_MIND := 12

static func species_row(actor: Dictionary) -> Dictionary:
	return combat.species.get(str(actor.get("species_id","human")),combat.species.human)

static func sheet(s, actor: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in KEYS: result[key] = {"total":0,"parts":[]}
	if bool(actor.get("enemy",false)):
		add(result,"ac","몬스터",int(actor.get("ac",0)))
		add(result,"ev","몬스터",int(actor.get("ev",3)))
		add(result,"sh","몬스터",int(actor.get("sh",0)))
		add(result,"int","몬스터",int(actor.get("int",MONSTER_MIND)))
		var res: Dictionary = actor.get("res",{})
		for element in RES: add(result,"res_"+element,"몬스터",int(res.get(element,0)))
		effects(result,actor)
		finish(result)
		return result
	var spec := species_row(actor)
	add(result,"str","종족",int(spec.str)); add(result,"dex","종족",int(spec.dex))
	add(result,"int","종족",int(spec.int)); add(result,"con","종족",int(spec.get("con",CON_BASE)))
	add(result,"str","물약",int(actor.get("str_bonus",0)))
	gear(result,actor)
	for id in Essences.equipped(actor):
		var values: Dictionary = Essences.stats(id)
		for key in values:
			if key in KEYS: add(result,key,Essences.title(id),int(values[key]))
	var sets: Dictionary = TagSets.stat_bonus(actor)
	for key in sets:
		if key in KEYS: add(result,key,"세트",int(sets[key]))
	effects(result,actor)
	# Dexterity lends evasion: one point for every three.
	add(result,"ev","민첩",total_of(result,"dex")/3)
	finish(result)
	return result

## What the headline effects put on the sheet (방패병's block).
static func effects(result: Dictionary, actor: Dictionary) -> void:
	var bonus: Dictionary = StoneEffects.stat_bonus(actor)
	for key in bonus:
		if key in KEYS: add(result,key,"대표 효과",int(bonus[key]))

static func gear(result: Dictionary, actor: Dictionary) -> void:
	var worn: Dictionary = actor.get("gear",{})
	var armour: Dictionary = worn.get("armour",{})
	var armour_def: Dictionary = combat.armours.get(str(armour.get("type","")),{})
	if not armour_def.is_empty():
		var armour_name: String = str(armour_def.get("name","갑옷"))
		add(result,"ac",armour_name,int(armour_def.ac)+int(armour.get("enchant",0)))
		add(result,"ev",armour_name,-int(armour_def.ev_penalty))
	if not worn.get("shield",{}).is_empty(): add(result,"sh","방패",SHIELD_BLOCK)
	var ring: Dictionary = worn.get("ring",{})
	var ring_def: Dictionary = combat.rings.get(str(ring.get("type","")),{})
	if ring_def.is_empty(): return
	var stat: String = str(ring_def.stat)
	if stat == "ev": add(result,"ev",str(ring_def.name),int(ring_def.value))
	elif stat in RES: add(result,"res_"+stat,str(ring_def.name),int(ring_def.value))

static func add(result: Dictionary, key: String, from: String, amount: int) -> void:
	if amount != 0: result[key].parts.append({"from":from,"value":amount})

static func total_of(result: Dictionary, key: String) -> int:
	var total := 0
	for part in result[key].parts: total += int(part.value)
	return total

static func finish(result: Dictionary) -> void:
	for key in KEYS:
		var total := total_of(result,key)
		if key.begins_with("res_"): total = mini(RES_CAP,total)
		if key == "speed": total = mini(SPEED_CAP,total)
		result[key].total = total

static func value(s, actor: Dictionary, key: String) -> int:
	return int(sheet(s,actor)[key].total)

## Only what essences and sets add: what the pools and the old auto path read.
static func bonus(actor: Dictionary, key: String) -> int:
	var total := 0
	for id in Essences.equipped(actor): total += int(Essences.stats(id).get(key,0))
	return total+int(TagSets.stat_bonus(actor).get(key,0))

## Brings max HP and MP in line with the essences worn now: the stones' flat
## HP and MP, then the percent the headline effect and 무리 4 lend on top.
## Only the change since the last call is applied, so level-ups and potions
## stay where they are.
static func refresh_pools(s, actor: Dictionary) -> void:
	if bool(actor.get("enemy",false)): return
	var old: Dictionary = actor.get("pool_bonus",{})
	var hp_bonus: int = bonus(actor,"hp")
	hp_bonus += (int(actor.max_hp)-int(old.get("hp",0))+hp_bonus)*StoneEffects.hp_percent(s,actor)/100
	var mp_bonus: int = bonus(actor,"mp")
	var hp_change: int = hp_bonus-int(old.get("hp",0))
	var mp_change: int = mp_bonus-int(old.get("mp",0))
	actor.max_hp = maxi(1,int(actor.max_hp)+hp_change)
	if int(actor.hp) > 0: actor.hp = clampi(int(actor.hp)+maxi(0,hp_change),1,int(actor.max_hp))
	actor.max_mp = maxi(0,int(actor.get("max_mp",0))+mp_change)
	actor.mp = clampi(int(actor.get("mp",0))+maxi(0,mp_change),0,int(actor.max_mp))
	actor.pool_bonus = {"hp":hp_bonus,"mp":mp_bonus}

## The old auto-battle path: a base number plus two per essence point of the
## attribute the axis reads.
static func legacy_power(actor: Dictionary, axis: String, base: int) -> int:
	var key: String = {"MELEE":"str","RANGED":"dex","MAGIC":"int"}.get(axis,"str")
	return base+2*bonus(actor,key)
