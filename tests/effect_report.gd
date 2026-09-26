extends SceneTree
## Effect report (legibility spec §1): procs, damage and healing per stone,
## the inner effect owning nested damage, party members only.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Report = preload("res://expedition/progression/effect_report.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Forms = preload("res://expedition/combat/forms.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	StoneEffects.force = 99; Forms.force = 99
	notes(); reflection(); nesting(); outsiders(); words(); delayed(); engine_nesting(); dot()
	StoneEffects.force = -1; Forms.force = -1
	print("Effect report: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0
	s.party[1].pos = c+Vector2i(0,1)
	s.reset_battle_stats()
	return {"s":s,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = []; actor.essences = {}
	for effect in ids:
		for id in StoneEffects.Essences.catalog():
			if StoneEffects.effect_of(str(id)) == effect:
				actor.equipped_abilities.append(id); actor.essences[id] = 1; break

func row(s, actor: Dictionary, effect: String) -> Dictionary:
	return s.member_stats(actor.id).get("effects",{}).get(effect,{})

func notes() -> void:
	var d := duo()
	Report.note(d.s,int(d.hero.id),"GHOUL_CLAW","procs",1)
	Report.note(d.s,int(d.hero.id),"GHOUL_CLAW","heal",12)
	check(int(row(d.s,d.hero,"GHOUL_CLAW").procs) == 1 and int(row(d.s,d.hero,"GHOUL_CLAW").heal) == 12,"a note lands on the member's row")

func reflection() -> void:
	var d := duo()
	slot(d.ally,["THORN_ARMOUR"])
	d.s.Reactions.begin_action(d.s)
	var before: int = int(d.foe.hp)
	d.s.damage(d.ally,20,int(d.foe.id),"physical")
	check(int(row(d.s,d.ally,"THORN_ARMOUR").damage) == before-int(d.foe.hp) and before > int(d.foe.hp),"a reflection is the thorn armour's damage")
	check(int(row(d.s,d.ally,"THORN_ARMOUR").procs) >= 1,"and a proc")

func nesting() -> void:
	var d := duo()
	d.s.effect_source = {"owner":int(d.hero.id),"effect":"OUTER"}
	var was: Dictionary = d.s.effect_source
	d.s.effect_source = {"owner":int(d.hero.id),"effect":"INNER"}
	d.s.damage(d.foe,5,int(d.hero.id),"REACTION")
	d.s.effect_source = was
	d.s.damage(d.foe,3,int(d.hero.id),"REACTION")
	d.s.effect_source = {}
	check(int(row(d.s,d.hero,"INNER").damage) == 5 and int(row(d.s,d.hero,"OUTER").damage) == 3,"the inner effect owns the inner damage")

func outsiders() -> void:
	var d := duo()
	Report.note(d.s,int(d.foe.id),"X","procs",1)
	check(d.s.member_stats(d.foe.id).is_empty(),"a monster keeps no report")

func words() -> void:
	check(Report.line({"effect":"THORN_ARMOUR","procs":3,"damage":18,"heal":0}).ends_with("×3 · 피해 18"),"a proc and damage line")
	check(Report.line({"effect":"GHOUL_CLAW","procs":2,"damage":0,"heal":30}).ends_with("×2 · 회복 30"),"a heal line")
	var top: Array = Report.top({"A":{"procs":1,"damage":10,"heal":0},"B":{"procs":5,"damage":2,"heal":0},"C":{"procs":0,"damage":0,"heal":0}},5)
	check(top.size() == 2 and top[0].effect == "A","top sorts by contribution and drops idle rows")

func delayed() -> void:
	var d := duo(); d.s.effect_source = {"owner":int(d.hero.id),"effect":"GHOUL_JAW"}
	var corpse: Dictionary = d.foe.duplicate(true); corpse.max_hp = 100
	d.s.StoneEffects.EffectEngine.Code.part_special(d.s,d.hero,{"target":corpse},"GHOUL_JAW")
	d.s.effect_source = {}; d.s.time += 100
	var before: int = int(d.foe.hp)
	d.s.StoneEffects.EffectEngine.Code.delayed(d.s)
	check(int(row(d.s,d.hero,"GHOUL_JAW").damage) == before-int(d.foe.hp) and before > int(d.foe.hp),"deferred explosion retains its effect attribution")
	check(d.s.effect_source.is_empty(),"deferred attribution is restored afterward")

func engine_nesting() -> void:
	var d := duo(); d.hero.hp -= 5
	slot(d.hero,["WATER_WAVE","SPIRIT_DROP"])
	# Wave healing triggers another equipped effect; it cannot steal the outer heal.
	d.s.Reactions.begin_action(d.s)
	d.s.StoneEffects.fire(d.s,"ROUND_START",{"source":d.hero})
	check(int(row(d.s,d.hero,"WATER_WAVE").get("heal",0)) > 0,"outer healing remains credited through nested HEALED")
	check(int(row(d.s,d.hero,"SPIRIT_DROP").get("procs",0)) == 1,"nested effect gets its own proc")
	check(d.s.effect_source.is_empty(),"engine restores empty attribution after nesting")

func dot() -> void:
	var d := duo(); d.s.effect_source = {"owner":int(d.hero.id),"effect":"TOAD_SPIT"}
	d.s.Statuses.apply(d.s,d.foe,"poison",300,d.hero)
	d.s.effect_source = {}; d.s.time += 100
	d.s.Statuses.tick(d.s)
	check(int(row(d.s,d.hero,"TOAD_SPIT").get("damage",0)) > 0,"effect-applied poison retains attribution after the action")
	check(d.s.effect_source.is_empty(),"DOT context is restored")
