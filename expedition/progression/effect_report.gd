extends RefCounted
## What each stone did in a fight (legibility spec §1): procs, the damage and
## healing done while it ran. Party members only; percent modifiers are not
## credited.
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")

static func note(s, owner_id: int, effect: String, field: String, amount: int) -> void:
	if effect.is_empty() or amount <= 0 or not s.party.any(func(a): return int(a.id) == owner_id): return
	var member: Dictionary = s.member_stats(owner_id)
	if member.is_empty(): return
	var row: Dictionary = member.get_or_add("effects",{}).get_or_add(effect,{"procs":0,"damage":0,"heal":0})
	row[field] = int(row.get(field,0))+amount

static func top(rows: Dictionary, n: int) -> Array:
	var list: Array = []
	for effect in rows:
		var r: Dictionary = rows[effect]
		if int(r.get("procs",0)) == 0 and int(r.get("damage",0)) == 0 and int(r.get("heal",0)) == 0: continue
		list.append({"effect":str(effect),"procs":int(r.get("procs",0)),"damage":int(r.get("damage",0)),"heal":int(r.get("heal",0))})
	list.sort_custom(func(a,b):
		var x: int = a.damage+a.heal; var y: int = b.damage+b.heal
		if x != y: return x > y
		if a.procs != b.procs: return a.procs > b.procs
		return a.effect < b.effect)
	return list.slice(0,n)

static func line(entry: Dictionary) -> String:
	var name: String = str(EffectEngine.content.effects.get(str(entry.effect),{}).get("name",entry.effect))
	var bits: Array = [name+(" ×%d" % int(entry.procs) if int(entry.procs) > 0 else "")]
	if int(entry.get("damage",0)) > 0: bits.append("피해 %d" % int(entry.damage))
	if int(entry.get("heal",0)) > 0: bits.append("회복 %d" % int(entry.heal))
	return " · ".join(bits)
