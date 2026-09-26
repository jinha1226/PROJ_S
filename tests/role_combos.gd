extends SceneTree
## Every highest-only role bracket, through combat hooks as well as direct readers.
const Fixture = preload("res://tests/followup_fixture.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Sets = preload("res://expedition/progression/tag_sets.gd")
const Effects = preload("res://expedition/progression/stone_effects.gd")
const Pools = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Spells = preload("res://expedition/spells/spells.gd")
var checks := 0
var failures := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(why)
func _initialize() -> void: call_deferred("run")
func stones(base: String, count: int) -> Array:
	var result: Array = [Essences.canonical(base)]
	for element in ["fire","ice","air","poison","bleed"]:
		if result.size() >= count: break
		result.append(Essences.canonical(base+"@"+element))
	return result.slice(0,count)
func slot(actor: Dictionary, base: String, count: int) -> void:
	actor.equipped_abilities = stones(base,count); actor.essences = {}
	for id in actor.equipped_abilities: actor.essences[id] = 1
func run() -> void:
	Effects.force = 99
	for count in range(11): check(Sets.bracket_of(count) == (6 if count >= 6 else 4 if count >= 4 else 2 if count >= 2 else 0),"bracket %d" % count)
	var bases := {"TANK":"SERPENT_SHED","MELEE":"GNOLL_SPEAR","RANGED":"TOAD_SPIT","MAGIC":"FROST_IMP","SUPPORT":"SPIDER_WEB"}
	var d := Fixture.reset(); var s = d.s
	for role in bases:
		for count in [1,2,3,4,5,6]:
			slot(d.hero,bases[role],count)
			check(Sets.count(d.hero,role) == count,"%s counted at %d" % [role,count])
			check(Sets.bracket(d.hero,role) == Sets.bracket_of(count),"%s highest-only bracket at %d" % [role,count])
			check(Sets.active(d.hero).any(func(r): return r.tag == role and r.count == count),"%s listed with its count" % role)
		for count in [1,2,4,6]:
			slot(d.hero,bases[role],count); d.hero.set_boost = true
			check(Sets.bracket(d.hero,role) == (0 if count == 1 else 4 if count == 2 else 6),"%s boss boost %d" % [role,count])
			d.hero.set_boost = false
	for count in [2,4,6]:
		d = Fixture.reset(s); slot(d.hero,"SERPENT_SHED",count)
		var bonus := Sets.stat_bonus(d.hero)
		check(int(bonus.ac) == {2:2,4:5,6:6}[count] and int(bonus.get("sh",0)) == {2:0,4:10,6:12}[count],"tank armour/block %d" % count)
		check(Effects.incoming(s,d.ally,100,d.foe) == (90 if count == 6 else 100),"tank adjacent protection %d" % count)
		d.ally.pos = Vector2i(3,6)
		check(Effects.incoming(s,d.ally,100,d.foe) == 100,"tank protection needs adjacency")
		d = Fixture.reset(s); slot(d.hero,"GNOLL_SPEAR",count)
		check(Effects.outgoing(s,d.hero,d.foe,100,"physical") == {2:112,4:125,6:130}[count],"melee attack %d" % count)
		check(Effects.crit_chance(s,d.hero,d.foe) == {2:0,4:8,6:10}[count],"melee critical %d" % count)
		check(Effects.crit_percent(d.hero) == 150,"melee never scales critical multiplier")
		d.foe.hp = d.foe.max_hp
		check(Effects.crit_chance(s,d.hero,d.foe) == {2:0,4:8,6:10}[count],"fresh target no longer guarantees a critical")
		check(Effects.outgoing(s,d.ally,d.foe,100,"physical") == 100,"melee affects only the wearer")
		d.hero.hp = 20; d.foe.hp = 0
		Effects.on_kill(s,d.hero,d.foe,{"primary":true})
		check(d.hero.hp == (25 if count == 6 else 20),"melee kill recovery %d" % count)
		check(Effects.speed(s,d.hero) == 0,"melee has no wounded speed bonus")
		d = Fixture.reset(s); slot(d.hero,"TOAD_SPIT",count); d.hero.gear.weapon = {"type":"bow"}; d.foe.pos = Vector2i(6,3)
		check(Stats.stats(s,d.hero).range == 6+(1 if count == 2 else 0),"ranged range %d" % count)
		check(Effects.outgoing(s,d.hero,d.foe,100,"physical") == {2:100,4:120,6:125}[count],"ranged damage %d" % count)
		d.foe.pos = Vector2i(4,3)
		check(Effects.outgoing(s,d.hero,d.foe,100,"physical") == 100,"ranged bonus excludes contact")
		d = Fixture.reset(s); slot(d.hero,"FROST_IMP",count)
		check(Effects.spell_percent(s,d.hero) == {2:12,4:25,6:30}[count],"magic power %d" % count)
		Effects.round_start(s,d.hero)
		check(d.hero.mp == (2 if count == 4 else 0),"only magic four restores MP")
		d.hero.gear.armour = {"type":"plate"}
		check(Effects.sure_casting(d.hero) == (count == 6),"magic failure exemption %d" % count)
		check(Spells.failure(s,d.hero,"ice_10") == 0 if count == 6 else Spells.failure(s,d.hero,"ice_10") > 0,"casting honours magic bracket")
		d = Fixture.reset(s); slot(d.hero,"SPIDER_WEB",count); slot(d.ally,"SPIDER_WEB",count)
		check(Effects.support_bracket(s,d.hero) == count and Effects.support_bracket(s,d.ally) == count,"support shared highest bracket")
		check(Effects.outgoing(s,d.hero,d.foe,100,"physical") == {2:100,4:108,6:110}[count],"support attack applies once")
		d.ally.hp = 1
		check(Effects.heal(s,d.ally,10,d.hero) == {2:12,4:13,6:14}[count],"support outgoing healing %d" % count)
		check(Effects.status_ticks(d.hero,"ward",100,s) == {2:120,4:130,6:140}[count],"support ward duration %d" % count)
		check(Effects.status_ticks(d.hero,"burn",100,s) == 100,"support never extends harmful effects")
		check(Effects.hp_percent(s,d.ally) == 0,"support lends no maximum HP bonus")
	d = Fixture.reset(s); slot(d.hero,"SPIDER_WEB",6); slot(d.ally,"SPIDER_WEB",4)
	check(Effects.outgoing(s,d.ally,d.foe,100,"physical") == 110,"party takes six over four")
	check(Effects.support_bracket(s,d.foe) == 0,"enemy borrows no party combo")
	d.ally.statuses = {"bleed":200,"weak":400}; Effects.force = 0
	Effects.round_start(s,d.hero)
	check(not d.ally.statuses.has("weak") and d.ally.statuses.has("bleed"),"cleanse removes one longest harmful status")
	d.ally.pos = Vector2i(3,6); Effects.round_start(s,d.hero)
	check(d.ally.statuses.has("bleed"),"cleanse needs adjacency")
	d.ally.pos = Vector2i(3,4); Effects.force = 25; Effects.round_start(s,d.hero)
	check(d.ally.statuses.has("bleed"),"cleanse is below twenty-five percent")
	Effects.force = -1
	print("Role combos: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
