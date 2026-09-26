extends RefCounted
## The codex (2026-09-26 codex spec): what the player has met and gathered,
## kept across runs in one file. Only a real run records; every note marks the
## session dirty and `flush` writes it at the few moments the spec names.
const Essences = preload("res://expedition/progression/essences.gd")
const Subtypes = preload("res://expedition/progression/subtypes.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const VERSION := 1
const SECTIONS := ["monsters","stones","unrands","tips","affixes"]
static var path := "user://codex.json"

static func empty() -> Dictionary:
	return {"version":VERSION,"runs":0,"deepest":0,"monsters":{},"stones":{},"unrands":{},"tips":{},"affixes":{}}

static func bad_path() -> String:
	return path.get_basename()+".bad.json"

## An empty codex for no file; a broken file is moved aside, never overwritten.
static func read() -> Dictionary:
	if not FileAccess.file_exists(path): return empty()
	var parser := JSON.new()
	var valid: bool = parser.parse(FileAccess.get_file_as_string(path)) == OK
	var parsed: Variant = parser.data if valid else null
	if not parsed is Dictionary:
		if FileAccess.file_exists(bad_path()): DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path()))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(bad_path()))
		return empty()
	var data := empty()
	for key in parsed: data[key] = parsed[key]
	for key in SECTIONS:
		if not data[key] is Dictionary: data[key] = {}
		for id in data[key].keys():
			if not data[key][id] is Dictionary: data[key].erase(id)
			elif data[key][id].has("variants") and not data[key][id].variants is Array: data[key][id].variants = []
	for key in ["runs","deepest"]:
		if not (data[key] is int or data[key] is float): data[key] = 0
		data[key] = maxi(0,int(data[key]))
	return data

static func write(data: Dictionary) -> bool:
	var pending: String = path+".tmp"
	var file := FileAccess.open(pending,FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data,"\t")); file.flush()
	var ok: bool = file.get_error() == OK
	file.close()
	if not ok: return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(pending),ProjectSettings.globalize_path(path)) == OK

static func monster_key(enemy: Dictionary) -> String:
	if bool(enemy.get("boss",false)): return "boss:"+str(enemy.get("boss_kind",""))
	return str(enemy.get("species_id",""))

## A stone's codex key: its canonical id without the variant element.
static func stone_key(id: String) -> String:
	var canonical: String = Essences.canonical(id)
	return "" if canonical.is_empty() else canonical.get_slice("@",0)

static func recording(s) -> bool:
	return s != null and bool(s.records_codex)

static func entry(s, section: String, key: String, fresh: Dictionary) -> Dictionary:
	var book: Dictionary = s.codex.get_or_add(section,{})
	if not book.has(key): book[key] = fresh; s.codex_dirty = true
	return book[key]

static func add_variant(s, row: Dictionary, element: String) -> void:
	if element.is_empty(): return
	if not row.get("variants",[]) is Array: row.variants = []
	var list: Array = row.get_or_add("variants",[])
	if element in list: return
	list.append(element); s.codex_dirty = true

static func note_seen(s, enemy: Dictionary) -> void:
	var key := monster_key(enemy)
	if not recording(s) or key.is_empty() or key == "boss:": return
	var row := entry(s,"monsters",key,{"seen":true,"kills":0,"variants":[]})
	if not bool(row.get("seen",false)): row.seen = true; s.codex_dirty = true
	add_variant(s,row,str(enemy.get("variant_element","")))

static func note_kill(s, enemy: Dictionary) -> void:
	var key := monster_key(enemy)
	if not recording(s) or key.is_empty() or key == "boss:": return
	var row := entry(s,"monsters",key,{"seen":true,"kills":0,"variants":[]})
	row.seen = true
	row.kills = int(row.get("kills",0))+1; s.codex_dirty = true
	add_variant(s,row,str(enemy.get("variant_element","")))

static func note_stone(s, id: String) -> void:
	var key := stone_key(id)
	if not recording(s) or key.is_empty(): return
	var row := entry(s,"stones",key,{"found":0,"absorbed":false,"variants":[]})
	row.found = int(row.get("found",0))+1; s.codex_dirty = true
	add_variant(s,row,Essences.variant_element(Essences.canonical(id)))

static func note_absorb(s, id: String) -> void:
	var key := stone_key(id)
	if not recording(s) or key.is_empty() or s.codex_test_stones.has(Essences.canonical(id)): return
	var row := entry(s,"stones",key,{"found":0,"absorbed":false,"variants":[]})
	if not bool(row.get("absorbed",false)): row.absorbed = true; s.codex_dirty = true

static func note_unrand(s, id: String) -> void:
	if not recording(s) or id.is_empty(): return
	var row := entry(s,"unrands",id,{"found":0})
	row.found = int(row.get("found",0))+1; s.codex_dirty = true

static func note_affix(s, id: String) -> void:
	if not recording(s) or not effects.has(id) or str(effects[id].get("gear_kind","")) != "affix": return
	var row := entry(s,"affixes",id,{"found":0})
	row.found = int(row.get("found",0))+1; s.codex_dirty = true

static func note_run_end(s) -> void:
	if not recording(s) or s.codex_run_ended: return
	s.codex_run_ended = true
	s.codex.runs = int(s.codex.get("runs",0))+1
	s.codex.deepest = maxi(int(s.codex.get("deepest",0)),int(s.depth))
	s.codex_dirty = true

static func flush(s) -> void:
	if not recording(s) or not bool(s.codex_dirty): return
	if write(s.codex): s.codex_dirty = false

const Forms = preload("res://expedition/combat/forms.gd")
const Encounters = preload("res://expedition/level/encounter_builder.gd")
const BossAI = preload("res://expedition/actors/boss_ai.gd")
const ZONE_OF_BOSS := {"chief":1,"golem":2,"eater":3,"fallen":4}
const FORM_HINT := {"SLASH":"베기로 마무리","IMPACT":"타격으로 마무리","PIERCE":"찌르기로 마무리"}
static var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/stone_effects.json")).get("effects",{})

static func monster_list() -> Array:
	var rows: Array = Encounters.table().duplicate()
	rows.sort_custom(func(a,b): return int(a.get("zone",9)) < int(b.get("zone",9)) if int(a.get("zone",9)) != int(b.get("zone",9)) else str(a.species_id) < str(b.species_id))
	var list: Array = rows.map(func(r): return {"key":str(r.species_id),"zone":int(r.get("zone",0)),"boss":false})
	for kind in BossAI.KINDS: list.append({"key":"boss:"+str(kind),"zone":int(ZONE_OF_BOSS.get(kind,0)),"boss":true})
	return list

static func species_stone(species_id: String) -> String:
	for id in Essences.content.rows:
		if str(Essences.content.rows[id].get("species","")) == species_id: return str(id)
	return ""

static func monster_entry(data: Dictionary, key: String) -> Dictionary:
	var row: Dictionary = data.get("monsters",{}).get(key,{})
	var zone := 0
	for m in monster_list():
		if m.key == key: zone = int(m.zone)
	if not bool(row.get("seen",false)): return {"key":key,"known":false,"zone":zone}
	var result := {"key":key,"known":true,"zone":zone,"kills":int(row.get("kills",0)),"variants":row.get("variants",[]),"parts":[]}
	if key.begins_with("boss:"):
		var kind: String = key.trim_prefix("boss:")
		result.name = BossAI.NAMES.get(kind,"타락한 모험가")
		result.body_line = ""; result.effect_text = ""
		result.role = "보스"; result.active_text = BossAI.HINTS.get(kind,"")
		return result
	var species: Dictionary = Encounters.species(key)
	result.name = str(species.get("display_name",key))
	result.body_line = Forms.body_line({"enemy":true,"species_id":key})
	var base := species_stone(key)
	result.role = str(Essences.ROLES.get(Essences.role(base),""))
	result.effect_text = str(effects.get(Essences.row(base).get("effect",""),{}).get("text","")) if not base.is_empty() else ""
	result.active_text = str(Essences.Abilities.definition(base).get("description","")) if not base.is_empty() else ""
	for i in range(Forms.PARTS.size()):
		var id: String = "%s/%s" % [base,Forms.PARTS[i]]
		if base.is_empty() or not Essences.has(id): continue
		result.parts.append({"id":id,"name":str(Essences.row(id).get("part_name","")),"form":Forms.FORMS[i],
			"found":int(data.get("stones",{}).get(id,{}).get("found",0)) > 0})
	return result

static func stone_list() -> Array:
	var list: Array = []
	for m in monster_list():
		if m.boss: continue
		var base := species_stone(str(m.key))
		for part in Forms.PARTS:
			var id: String = "%s/%s" % [base,part]
			if not base.is_empty() and Essences.has(id): list.append(id)
	for id in Essences.content.rows:
		if not Essences.content.rows[id].has("parts") and Essences.has(str(id)): list.append(str(id))
	return list

static func stone_entry(data: Dictionary, key: String) -> Dictionary:
	var row: Dictionary = data.get("stones",{}).get(key,{})
	var info: Dictionary = Essences.row(key)
	var species: String = str(info.get("species",""))
	species = {"goblin_chief":"boss:chief","furnace_golem":"boss:golem","soul_eater":"boss:eater"}.get(species,species)
	var known: bool = bool(data.get("monsters",{}).get(species,{}).get("seen",false))
	var part := Essences.part_of(key)
	var form: String = Forms.FORMS[Forms.PARTS.find(part)] if part in Forms.PARTS else ""
	var effect: Dictionary = effects.get(str(info.get("effect","")),{})
	var title: String = str(info.get("part_name",""))
	if title.is_empty(): title = Essences.title(key)
	var description: String = str(effect.get("text",""))
	if description.is_empty():
		var stats := Essences.stats(key); var parts: PackedStringArray = []
		for stat in stats: parts.append("%s +%d" % [Equipment.PROP_NAMES.get(str(stat),str(stat)),int(stats[stat])])
		description = " · ".join(parts)
	return {"key":key,"found":int(row.get("found",0)) > 0,"absorbed":bool(row.get("absorbed",false)),"species_known":known,
		"name":title if known or int(row.get("found",0)) > 0 else "???",
		"text":description,"keywords":effect.get("keywords",[]),"subtype":Subtypes.of(str(info.get("effect",""))),
		"group":str(Subtypes.GROUP.get(Subtypes.of(str(info.get("effect",""))),Essences.role(key))),
		"hint":str(FORM_HINT.get(form,""))}

static func completion(data: Dictionary) -> Dictionary:
	var monsters := monster_list(); var stones := stone_list()
	var unrands: Array = unrand_ids()
	return {"monsters":[monsters.filter(func(m): return bool(data.get("monsters",{}).get(m.key,{}).get("seen",false))).size(),monsters.size()],
		"stones":[stones.filter(func(id): return int(data.get("stones",{}).get(id,{}).get("found",0)) > 0).size(),stones.size()],
		"unrands":[unrands.filter(func(id): return int(data.get("unrands",{}).get(id,{}).get("found",0)) > 0).size(),unrands.size()]}

## The fixed artefacts' ids, empty until `data/content/unrands.json` exists.
static func unrand_ids() -> Array:
	if not FileAccess.file_exists("res://data/content/unrands.json"): return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/unrands.json"))
	if not parsed is Dictionary: return []
	return parsed.get("rows",[]).map(func(row): return str(row.id))

static func unrand_entry(data: Dictionary, id: String) -> Dictionary:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/unrands.json"))
	for row in parsed.get("rows",[]):
		if str(row.id) != id: continue
		var found: bool = int(data.get("unrands",{}).get(id,{}).get("found",0)) > 0
		var type: String = str(row.type)
		return {"key":id,"found":found,"slot":Equipment.SLOT_NAMES.get(Equipment.slot({"type":type}),""),
			"name":str(row.name) if found else "???","text":Equipment.description(row) if found else ""}
	return {}

## Public base equipment and discovered options. Unknown artefacts keep only their slot.
static func item_rows(data: Dictionary) -> Array:
	var result: Array = []
	for group in ["weapons","offhands","armours","rings"]:
		var rows: Array = []
		for id in Equipment.content.get(group,{}):
			var info: Dictionary = Equipment.content[group][id]
			var bits: PackedStringArray = []
			for pair in [["form","형태"],["damage","공격"],["delay","지연"],["range","사거리"],["hands","손"],["ac","방어"],["ev_penalty","회피 감소"],["enc","무게"],["block","막기"],["sh","막기"],["spell","주문력"],["stat","효과"],["value","수치"]]:
				if not info.has(pair[0]): continue
				var value: String = str(info[pair[0]])
				if pair[0] == "form": value = str(Forms.NAMES.get(value,value))
				if pair[0] == "stat": value = str(Essences.ELEMENTS.get(value,{"power":"주문력","ev":"회피"}.get(value,value)))
				bits.append("%s %s" % [pair[1],value])
			rows.append({"key":id,"name":str(info.get("name",id)),"text":" · ".join(bits)})
		result.append({"group":group,"rows":rows})
	var affixes: Array = []
	for id in effects:
		if str(effects[id].get("gear_kind","")) != "affix" or int(data.get("affixes",{}).get(id,{}).get("found",0)) <= 0: continue
		affixes.append({"key":id,"name":str(effects[id].name),"text":str(effects[id].text),"subtype":Subtypes.of(str(id)),"keywords":effects[id].get("keywords",[])})
	result.append({"group":"affixes","rows":affixes})
	result.append({"group":"unrands","rows":unrand_ids().map(func(id): return unrand_entry(data,str(id)))})
	return result
