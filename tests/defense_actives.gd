extends SceneTree
## The five guard actives (zones spec §4), the one-largest damage cut, and the
## monster side: taunted monsters, self-cast actives, a player-only taunt.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	stance(); taunt(); curl(); shed(); thorns(); wall(); monsters()
	print("Defense actives: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Hero at c, ally at c+(0,1), a fresh alert foe at c+(1,0) with no part.
func duo() -> Dictionary:
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.alert = true; foe.charging = false; foe.cooldowns = {}
	s.floor_state.observe(s); s.phase = "BATTLE"
	for actor in s.party: actor.ap = 2; actor.cooldowns = {}
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

func stance() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SHIELD_STANCE"])
	var before: int = int(Stats.stats(s,d.hero).sh)
	check(Abilities.execute(s,d.hero,"SHIELD_STANCE",d.hero.pos) and d.hero.statuses.has("shield_stance"),"방패 자세 takes the stance")
	check(int(Stats.stats(s,d.hero).sh) == mini(50,before+40),"막기 +40, capped at fifty")
	check(Statuses.blocks(d.hero,"MOVE") and not Statuses.blocks(d.hero,"ATTACK"),"the stance holds the feet, not the arms")
	check(int(d.hero.cooldowns.SHIELD_STANCE) == 5,"cooldown four (+1)")

func taunt() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["HOB_TAUNT"])
	var far: Dictionary = s.enemies[1]
	far.hp = 30; far.max_hp = 30; far.pos = d.c+Vector2i(4,2); far.statuses = {}
	check(Abilities.execute(s,d.hero,"HOB_TAUNT",d.hero.pos),"도발 goes off")
	check(int(d.foe.statuses.get("taunted",0)) == int(s.time)+200 and int(d.foe.status_power.taunted) == int(d.hero.id),"a foe within three is taunted by the hero")
	check(not far.statuses.has("taunted"),"a foe farther than three is not")
	check(MonsterAI.taunter_of(s,d.foe).id == d.hero.id,"the monster knows who taunted it")
	d = duo(); s = d.s; slot(d.hero,["HOB_TAUNT"]); d.foe.boss = true
	Abilities.execute(s,d.hero,"HOB_TAUNT",d.hero.pos)
	check(int(d.foe.statuses.get("taunted",0)) == int(s.time)+100,"a boss is taunted for half the time")
	d = duo(); s = d.s
	d.foe.pos = d.c+Vector2i(0,2)   # beside the ally, two from the hero
	d.foe.statuses = {"taunted":s.time+200}; d.foe.status_power = {"taunted":int(d.hero.id)}
	var ally_hp: int = d.ally.hp
	var gap: int = MonsterAI.distance(d.foe.pos,d.hero.pos)
	MonsterAI.turn(s,d.foe)
	check(d.ally.hp == ally_hp and MonsterAI.distance(d.foe.pos,d.hero.pos) < gap,"a taunted monster walks past the ally toward the taunter")
	d = duo(); s = d.s
	d.foe.part_id = "HOB_TAUNT"
	check(not Abilities.legal(s,d.foe,"HOB_TAUNT",d.foe.pos),"a monster never taunts (player-only)")

func curl() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["BEETLE_CURL"])
	check(Abilities.execute(s,d.hero,"BEETLE_CURL",d.hero.pos) and d.hero.iron_guard,"몸 말기 curls up")
	d.hero.guarded = true
	check(Abilities.reduction(d.hero) == 75,"the largest cut wins, not the sum")
	var hp: int = d.hero.hp
	s.damage(d.hero,40,int(d.foe.id),"IMPACT")
	check(d.hero.hp == hp-10,"forty becomes ten")
	d.hero.iron_guard = false
	check(Abilities.reduction(d.hero) == 50,"엄호 alone halves")
	d.hero.damage_cut = 40
	check(Abilities.reduction(d.hero) == 50,"a smaller cut does not stack on a larger one")
	d.hero.guarded = false
	check(Abilities.reduction(d.hero) == 40,"damage_cut stands alone")

func shed() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SERPENT_SHED"])
	d.hero.statuses = {"poison":s.time+300,"slow":s.time+300,"bleed":s.time+300}
	check(Abilities.execute(s,d.hero,"SERPENT_SHED",d.hero.pos),"허물 벗기 goes off")
	check(not d.hero.statuses.has("poison") and not d.hero.statuses.has("slow") and not d.hero.statuses.has("bleed"),"every harmful status is shed")
	check(int(d.hero.statuses.get("immune",0)) == int(s.time)+100,"and a round of immunity follows")
	Statuses.apply(s,d.hero,"confuse",200)
	check(not d.hero.statuses.has("confuse"),"nothing harmful takes while immune")

func thorns() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["THORN_ARMOUR"])
	check(Abilities.execute(s,d.hero,"THORN_ARMOUR",d.hero.pos) and d.hero.statuses.has("thorns"),"가시 갑옷 goes on")
	var foe_hp: int = d.foe.hp; var hp: int = d.hero.hp
	s.damage(d.hero,20,int(d.foe.id),"IMPACT")
	check(d.foe.hp == foe_hp-6 and d.hero.hp < hp,"an adjacent attacker takes thirty percent back")
	d.foe.pos = d.c+Vector2i(3,0); foe_hp = d.foe.hp
	s.damage(d.hero,20,int(d.foe.id),"IMPACT")
	check(d.foe.hp == foe_hp,"a distant attacker takes nothing back")

func wall() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SKELETON_WALL"])
	var ac: int = int(Stats.stats(s,d.ally).ac)
	check(Abilities.execute(s,d.hero,"SKELETON_WALL",d.hero.pos),"방패벽 goes up")
	check(d.hero.statuses.has("shield_wall") and d.ally.statuses.has("shield_wall"),"on the wearer and the adjacent ally")
	check(int(Stats.stats(s,d.ally).ac) == ac+3,"armour +3")
	check(not d.foe.statuses.has("shield_wall"),"never on a foe")

func monsters() -> void:
	var d := duo(); var s = d.s
	d.foe.part_id = "BEETLE_CURL"
	MonsterAI.turn(s,d.foe)
	check(d.foe.iron_guard,"a monster in contact curls up on its own")
	d = duo(); s = d.s
	d.foe.part_id = "SHIELD_STANCE"; d.foe.pos = d.c+Vector2i(5,0); d.foe.hp = 40; s.floor_state.observe(s)
	MonsterAI.turn(s,d.foe)
	check(not d.foe.statuses.has("shield_stance"),"a healthy monster out of contact keeps its stance for later")
