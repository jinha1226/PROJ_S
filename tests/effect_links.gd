extends SceneTree
## Links on the status tab (legibility spec §3): equipped effects grouped by a
## shared keyword and told in order — who applies it, who uses it.
const Links = preload("res://expedition/progression/effect_links.gd")
const Effects = preload("res://expedition/progression/effect_engine.gd")
const Essences = preload("res://expedition/progression/essences.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func member(weapon: String, ids: Array) -> Dictionary:
	var actor := {"enemy":false,"level":10,"gear":{"weapon":{"type":weapon,"enchant":0}},"equipped_abilities":ids.duplicate(),"essences":{}}
	for id in ids: actor.essences[id] = 1
	return actor

## A stone whose effect plays `side` for `word`.
func stone(word: String, side: String) -> String:
	for id in Essences.catalog():
		var effect: Dictionary = Effects.content.effects.get(str(Essences.row(str(id)).get("effect","")),{})
		if str(effect.get("roles",{}).get(word,"")) == side: return str(id)
	return ""

func group(groups: Array, word: String) -> Dictionary:
	for g in groups:
		if g.keyword == word: return g
	return {}

func run() -> void:
	check(Links.groups(member("mace",[])).is_empty(),"no stones, no links")
	var setup := stone("출혈","setup"); var payoff := stone("출혈","payoff")
	check(not setup.is_empty() and not payoff.is_empty(),"the catalogue has a bleed setup and payoff")
	var g := group(Links.groups(member("mace",[payoff,setup])),"출혈")
	check(g.lines.size() == 2 and g.lines[0].side == "setup" and g.lines[1].side == "payoff","setup is told before payoff, whatever the slot order")
	check(not str(g.lines[0].text).is_empty(),"each line carries the effect's text")
	var sword := group(Links.groups(member("sword",[payoff])),"출혈")
	check(sword.lines.size() == 2 and sword.lines[0].name.contains("베기") and sword.lines[0].side == "setup","a slashing weapon applies bleed first")
	check(group(Links.groups(member("mace",[payoff])),"출혈").is_empty(),"a lone keyword makes no group")
	# Every effect naming a status keyword says which side it plays.
	for id in Effects.content.effects:
		var e: Dictionary = Effects.content.effects[id]
		for word in e.get("keywords",[]):
			if word in Links.STATUS_WORDS: check(e.get("roles",{}).has(word),"%s says its side for %s" % [id,word])
	print("Effect links: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
