extends SceneTree
## Role combos at 2, 4 and 6 stones (2026-09-26 spec §3): only the highest
## bracket reached is on, 무리 lends its best bracket to the whole party, and
## the final boss's `set_boost` lifts a combo one bracket.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const TagSets = preload("res://expedition/progression/tag_sets.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const ELEMENTS := ["fire","ice","air","poison","bleed"]
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	brackets(); pack(); berserk(); ambush(); guard(); archer(); caster(); boost(); listing()
	StoneEffects.force = -1
	print("Role combos: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func duo() -> Dictionary:
	StoneEffects.force = 99
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0
	s.floor_state.observe(s)
	s.effects.clear()
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

## `count` stones of one base: the base and its variants, one element each so
## no element set switches on.
func stones(base: String, count: int) -> Array:
	var result: Array = [base]
	for element in ELEMENTS:
		if result.size() >= count: break
		result.append(base+"@"+element)
	return result.slice(0,count)

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func hit(s, from: Dictionary, to: Dictionary, amount: int, form: String = "SLASH") -> int:
	var before: int = int(to.hp)
	s.Reactions.begin_action(s)
	s.damage(to,amount,int(from.id),form)
	return before-int(to.hp)

func procs(s, text: String) -> int:
	return s.effects.filter(func(e): return str(e.get("kind","")) == "PROC" and str(e.get("text","")) == text).size()

func brackets() -> void:
	var expected := {0:0,1:0,2:2,3:2,4:4,5:4,6:6,7:6,10:6}
	for count in expected: check(TagSets.bracket_of(count) == int(expected[count]),"%d stones reach bracket %d" % [count,int(expected[count])])
	var actor := {"level":6,"essences":{},"equipped_abilities":stones("LIZARD_TAIL",3)}
	check(TagSets.count(actor,"BERSERK") == 3 and TagSets.bracket(actor,"BERSERK") == 2,"three stones are the two bracket")
	check(TagSets.counts(actor).get("fire",0) == 1 and TagSets.level(actor,"fire") == 0,"one of an element is no element set")
	check(TagSets.bracket({"enemy":true,"part_id":"LIZARD_TAIL"},"BERSERK") == 0,"a monster wears no combo")

func pack() -> void:
	var d := duo(); var s = d.s
	var ally_hp: int = int(d.ally.max_hp)
	slot(d.hero,stones("RIVER_RAT_SPLASH",2))
	check(hit(s,d.hero,d.foe,20) == 22,"무리 2: attack +10%")
	check(hit(s,d.ally,d.foe,20) == 22,"for the whole party")
	slot(d.ally,stones("RIVER_RAT_SPLASH",1))
	slot(d.hero,stones("RIVER_RAT_SPLASH",4))
	check(StoneEffects.pack_bracket(s,d.ally) == 4,"the party takes the best bracket among it")
	check(hit(s,d.hero,d.foe,20) == 24 and hit(s,d.ally,d.foe,20) == 24,"무리 4: attack +20%, not +30%")
	StatSheet.refresh_pools(s,d.ally)
	check(int(d.ally.max_hp) == (ally_hp+10)*120/100,"and the companions' max HP +20%")
	slot(d.hero,stones("RIVER_RAT_SPLASH",6)); StatSheet.refresh_pools(s,d.ally)
	check(hit(s,d.hero,d.foe,20) == 26,"무리 6: attack +30%")
	check(int(d.ally.max_hp) == ally_hp+10,"the four bracket's HP is not the six's")
	d.hero.hp = 20; d.ally.hp = 20; d.foe.hp = 3
	hit(s,d.hero,d.foe,5)
	check(int(d.hero.hp) == 20+int(d.hero.max_hp)*5/100 and int(d.ally.hp) == 20+int(d.ally.max_hp)*5/100,"a kill heals the party five percent")
	check(hit(s,d.foe,d.hero,20) == 20,"a monster borrows nothing from the party")

func berserk() -> void:
	var d := duo(); var s = d.s
	var expected := {2:23,4:26,6:30}
	for count in expected:
		slot(d.hero,stones("LIZARD_TAIL",count))
		check(hit(s,d.hero,d.foe,20) == int(expected[count]),"광폭 %d: %d from twenty" % [count,int(expected[count])])
	check(hit(s,d.ally,d.foe,20) == 20,"광폭 is the wearer's own")
	slot(d.hero,stones("LIZARD_TAIL",4))
	check(StoneEffects.speed(s,d.hero) == 0,"광폭 4 waits for the wound")
	d.hero.hp = int(d.hero.max_hp)/2
	check(StoneEffects.speed(s,d.hero) == 20,"광폭 4: at half, a fifth quicker")
	slot(d.hero,stones("LIZARD_TAIL",6))
	check(StoneEffects.speed(s,d.hero) == 0,"not at six")
	d.hero.hp = 20; d.foe.hp = 3
	hit(s,d.hero,d.foe,5)
	check(int(d.hero.hp) == 20+int(d.hero.max_hp)*10/100,"광폭 6: a kill heals ten percent")

func ambush() -> void:
	var d := duo(); var s = d.s
	d.foe.hp = 399
	var expected := {2:10,4:20,6:30}
	for count in expected:
		slot(d.hero,stones("SPIDER_WEB",count))
		check(StoneEffects.crit_chance(s,d.hero,d.foe) == int(expected[count]),"기습 %d: %d%% critical" % [count,int(expected[count])])
	slot(d.hero,stones("SPIDER_WEB",2))
	check(StoneEffects.crit_percent(d.hero) == 150,"기습 2 keeps the plain critical")
	slot(d.hero,stones("SPIDER_WEB",4))
	check(StoneEffects.crit_percent(d.hero) == 200,"기습 4: critical damage +50%p")
	slot(d.hero,stones("SPIDER_WEB",6))
	check(StoneEffects.crit_percent(d.hero) == 200,"기습 6 as well")
	d.foe.hp = 400
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 100,"기습 6: a full foe is always a critical")
	check(hit(s,d.hero,d.foe,10) == 20 and procs(s,"치명타!") == 1,"even when the roll would fail")

func guard() -> void:
	var d := duo(); var s = d.s
	var expected := {2:[3,0],4:[6,10],6:[10,20]}
	for count in expected:
		slot(d.hero,stones("HOB_TAUNT",count))
		var bonus: Dictionary = TagSets.stat_bonus(d.hero)
		check(int(bonus.get("ac",0)) == int(expected[count][0]) and int(bonus.get("sh",0)) == int(expected[count][1]),"수호 %d: armour %d, block %d" % [count,int(expected[count][0]),int(expected[count][1])])
	check(not TagSets.stat_bonus(d.ally).has("ac"),"the armour is the wearer's")
	check(hit(s,d.foe,d.ally,20) == 17,"수호 6: an ally beside takes fifteen percent less")
	slot(d.hero,stones("HOB_TAUNT",4))
	check(hit(s,d.foe,d.ally,20) == 20,"not at four")

func archer() -> void:
	var d := duo(); var s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	var bow: int = int(Stats.content.weapons.bow.range)
	d.foe.pos = d.c+Vector2i(3,0)
	slot(d.hero,stones("TOAD_SPIT",2))
	check(int(Stats.stats(s,d.hero).range) == bow+1 and hit(s,d.hero,d.foe,20) == 20,"사수 2: one farther")
	slot(d.hero,stones("TOAD_SPIT",4))
	check(int(Stats.stats(s,d.hero).range) == bow and hit(s,d.hero,d.foe,20) == 25,"사수 4: ranged damage +25%")
	slot(d.hero,stones("TOAD_SPIT",6))
	check(hit(s,d.hero,d.foe,20) == 28,"사수 6: ranged damage +40%")
	d.foe.pos = d.c+Vector2i(1,0)
	check(hit(s,d.hero,d.foe,20) == 20,"not point-blank")
	d.foe.pos = d.c+Vector2i(3,0)
	StoneEffects.force = 0
	s.Reactions.begin_action(s)
	StoneEffects.after_hit(s,d.foe,d.hero,"physical",5)
	check(procs(s,"연사!") == 1,"사수 6: a ranged hit may loose another")
	StoneEffects.after_hit(s,d.foe,d.hero,"physical",5)
	check(procs(s,"연사!") == 1,"once an action")

func caster() -> void:
	var d := duo(); var s = d.s
	var expected := {2:15,4:30,6:50}
	for count in expected:
		slot(d.hero,stones("GOBLIN_HEXER",count))
		check(StoneEffects.spell_percent(s,d.hero) == int(expected[count]),"술사 %d: spell power +%d%%" % [count,int(expected[count])])
	slot(d.hero,stones("GOBLIN_HEXER",2))
	var power: int = int(Stats.stats(s,d.hero).power)
	var before: int = int(d.foe.hp)
	Spells.shaped_cast(s,d.hero,"fire_1",d.foe.pos,Spells.definition("fire_1"))
	var spell: int = int(Spells.definition("fire_1").power)
	check(before-int(d.foe.hp) == (spell+Spells.mind_bonus(s,d.hero)+power)*115/100,"and a spell hits that much harder")
	slot(d.hero,stones("GOBLIN_HEXER",4))
	d.hero.mp = 0
	Passives.round_start(s,d.hero)
	check(int(d.hero.mp) == 2,"술사 4: two MP a round")
	slot(d.hero,stones("GOBLIN_HEXER",6))
	d.hero.mp = 0
	Passives.round_start(s,d.hero)
	check(int(d.hero.mp) == 0,"not at six")
	d.hero.gear.armour = {"type":"plate","enchant":0}
	check(Spells.failure(s,d.hero,"hex_1") == 0,"술사 6: no spell fails")
	slot(d.hero,stones("GOBLIN_HEXER",4))
	check(Spells.failure(s,d.hero,"hex_1") > 0,"at four a heavy coat still spoils a spell")

func boost() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,stones("LIZARD_TAIL",2))
	d.hero.set_boost = true
	check(TagSets.bracket(d.hero,"BERSERK") == 4,"set_boost: two reads as four")
	slot(d.hero,stones("LIZARD_TAIL",4))
	check(TagSets.bracket(d.hero,"BERSERK") == 6,"four as six")
	slot(d.hero,stones("LIZARD_TAIL",6))
	check(TagSets.bracket(d.hero,"BERSERK") == 6,"six stays six")
	slot(d.hero,stones("LIZARD_TAIL",1))
	check(TagSets.bracket(d.hero,"BERSERK") == 0,"one stone is still nothing")
	d.hero.set_boost = false
	slot(d.hero,stones("LIZARD_TAIL",2))
	check(TagSets.bracket(d.hero,"BERSERK") == 2,"without it two stays two")

func listing() -> void:
	var actor := {"level":6,"essences":{},"equipped_abilities":stones("LIZARD_TAIL",3)+["HOB_TAUNT@fire"]}
	var rows: Array = TagSets.active(actor)
	var berserk: Array = rows.filter(func(r): return str(r.tag) == "BERSERK")
	check(berserk.size() == 1 and int(berserk[0].count) == 3 and int(berserk[0].next) == 4 and int(berserk[0].level) == 2,"the list shows the count, the next bracket and the one on")
	check(str(berserk[0].text) == str(TagSets.ROLE_TEXT.BERSERK[2]),"and the words of the bracket on")
	var guard: Array = rows.filter(func(r): return str(r.tag) == "GUARD")
	check(guard.size() == 1 and int(guard[0].level) == 0 and int(guard[0].next) == 2,"a lone stone shows how far the first bracket is")
	check(rows.any(func(r): return str(r.tag) == "fire" and int(r.level) == 2),"element sets stay in the list")
	for role in TagSets.ROLE_TEXT: check(TagSets.ROLE_TEXT[role].has(2) and TagSets.ROLE_TEXT[role].has(4) and TagSets.ROLE_TEXT[role].has(6),"%s has three brackets" % role)
