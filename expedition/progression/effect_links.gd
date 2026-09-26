extends RefCounted
## The status tab's link card (legibility spec §3): the member's effects, and
## its weapon's form, grouped by a shared keyword and told in order — what
## applies it, then what uses it.
const EffectEngine = preload("res://expedition/progression/effect_engine.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const Equipment = preload("res://expedition/items/equipment.gd")
const FORM_WORD := {"SLASH":"출혈","IMPACT":"골절","PIERCE":"급소 노출"}
const FORM_TEXT := {"SLASH":"명중하면 출혈 (피부가 무를수록 잘 걸림)","IMPACT":"명중하면 골절 (뼈가 약할수록 잘 걸림)","PIERCE":"명중하면 급소 노출"}
const SIDE_ORDER := {"setup":0,"both":1,"payoff":2,"with":3}
const SIDE_NAMES := {"setup":"거는 쪽","both":"둘 다","payoff":"쓰는 쪽","with":"함께"}
const STATUS_WORDS := ["출혈","골절","기절","빙결","급소 노출","화상","중독","속박","약화","표식","혼란"]

static func groups(actor: Dictionary) -> Array:
	var by_word: Dictionary = {}
	var order := 0
	var gear := Equipment.worn(actor.duplicate(true))
	for item in [gear.weapon,gear.offhand]:
		if item.is_empty(): continue
		var form: String = str(Equipment.definition(item).get("form",""))
		if not FORM_WORD.has(form): continue
		by_word.get_or_add(str(FORM_WORD[form]),[]).append({"side":"setup","name":"%s(%s)" % [Equipment.title(item),Forms.form_name(form)],"text":str(FORM_TEXT[form])+(" · 추가 부상 절반 확률" if item == gear.offhand else ""),"order":order})
		order += 1
	for id in EffectEngine.effects(actor):
		var effect: Dictionary = EffectEngine.content.effects.get(id,{})
		for word in effect.get("keywords",[]):
			var side: String = str(effect.get("roles",{}).get(str(word),"with"))
			var lines: Array = by_word.get_or_add(str(word),[])
			if lines.any(func(l): return l.name == str(effect.get("name",id))): continue
			lines.append({"side":side,"name":str(effect.get("name",id)),"text":str(effect.get("text","")),"order":order})
		order += 1
	var result: Array = []
	for word in by_word:
		var lines: Array = by_word[word]
		if lines.size() < 2: continue
		lines.sort_custom(func(a,b): return int(SIDE_ORDER[a.side]) < int(SIDE_ORDER[b.side]) if a.side != b.side else int(a.order) < int(b.order))
		result.append({"keyword":str(word),"lines":lines.map(func(l): return {"side":l.side,"name":l.name,"text":l.text})})
	result.sort_custom(func(a,b): return a.lines.size() > b.lines.size() if a.lines.size() != b.lines.size() else a.keyword < b.keyword)
	return result
