extends SceneTree
## The soul stone rework (2026-09-26 spec §1–2, §6): fixed base stats by role,
## one headline effect per base species, the notices they raise, secondary
## damage staying quiet, monsters with their own species' effect, bosses none.
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const StoneEffects = preload("res://expedition/progression/stone_effects.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const Stats = preload("res://expedition/combat/combat_stats.gd")
const Rules = preload("res://expedition/combat/combat_rules.gd")
const Statuses = preload("res://expedition/combat/statuses.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Spells = preload("res://expedition/spells/spells.gd")
const Forms = preload("res://expedition/combat/forms.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	# This suite isolates stone procs; form wounds have their own suite.
	Forms.force = 99
	catalogue(); base_stats()
	rat(); lizard(); kobold(); goblin(); goblin_aim(); shield(); hobgoblin(); hexer(); orc(); thrower()
	spider(); beetle(); golem(); fire_caller(); storm_bat(); river_rat(); leech(); toad(); serpent(); water()
	gnoll(); frost(); summoner(); skeleton_wall(); volley(); ghoul(); vampire(); thorns(); wraith(); gravekeeper()
	secondary(); monsters()
	StoneEffects.force = -1
	Forms.force = -1
	print("Stone effects: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Hero at c, ally beside at c+(0,1), a fresh foe at c+(1,0) with no part.
func duo() -> Dictionary:
	StoneEffects.force = -1
	var s = Session.new(731,false,true,true,2); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""
	foe.res = {}; foe.statuses = {}; foe.sh = 0
	s.floor_state.observe(s)
	s.effects.clear()
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"foe":foe}

func slot(actor: Dictionary, ids: Array) -> void:
	actor.level = maxi(int(actor.level),ids.size())
	actor.equipped_abilities = ids.duplicate(); actor.essences = {}
	for id in ids: actor.essences[id] = 1

## What `amount` of plain blow from `from` takes off `to`.
func hit(s, from: Dictionary, to: Dictionary, amount: int, form: String = "SLASH") -> int:
	var before: int = int(to.hp)
	s.Reactions.begin_action(s)
	s.damage(to,amount,int(from.id),form)
	return before-int(to.hp)

func procs(s, text: String) -> int:
	return s.effects.filter(func(e): return str(e.get("kind","")) == "PROC" and str(e.get("text","")) == text).size()

func any_proc(s) -> bool:
	return s.effects.any(func(e): return str(e.get("kind","")) == "PROC")

func logged(s, text: String) -> bool:
	return s.log_lines.any(func(l): return str(l).contains(text))

func catalogue() -> void:
	check(StoneEffects.EFFECTS.size() == 30,"thirty headline effects")
	var bases := 0
	for id in Essences.content.rows:
		if id in ["GOBLIN_CHIEF","FURNACE_HEART","SOUL_EATER"]:
			check(StoneEffects.effect_of(id).is_empty(),"%s, a boss stone, has no headline effect" % id)
			continue
		bases += 1
		check(StoneEffects.effect_of(id) == id and StoneEffects.EFFECTS.has(id),"%s names its own headline effect" % id)
		check(not str(StoneEffects.EFFECTS[id].name).is_empty() and not str(StoneEffects.EFFECTS[id].text).is_empty(),"%s is described" % id)
		check(StoneEffects.effect_of(id+"@fire") == id,"%s's variant shares its effect" % id)
	check(bases == 30,"every base species has its stone")

func base_stats() -> void:
	check(Essences.stats("RAT_GNAW") == {"hp":10,"atk":2},"무리: HP +10, 공격력 +2")
	check(Essences.stats("LIZARD_TAIL") == {"atk":4,"hp":8},"광폭: 공격력 +4, HP +8")
	check(Essences.stats("GOBLIN_SHIV") == {"atk":3,"dodge":5},"기습: 공격력 +3, 회피 +5%")
	check(Essences.stats("HOB_TAUNT") == {"hp":20,"ac":3},"수호: HP +20, 방어 +3")
	check(Essences.stats("KOBOLD_SLING") == {"atk":3,"speed":5},"사수: 공격력 +3, 속도 +5%")
	check(Essences.stats("GOBLIN_HEXER") == {"spell":4,"mp":8},"술사: 주문력 +4, MP +8")
	check(Essences.stats("GOBLIN_SHIV@fire") == {"atk":3,"dodge":5,"res_fire":10},"a variant adds ten of its element")
	check(Essences.stats("GOBLIN_SHIV@bleed") == {"atk":3,"dodge":5},"bleeding lends no resistance")
	check(Essences.stats("GOBLIN_CHIEF") == Essences.stats("RAT_GNAW"),"a boss stone keeps its role's stats")
	for key in ["atk","hp","spell","mp","speed","dodge"]: check(key in StatSheet.KEYS and StatSheet.NAMES.has(key),"%s is on the stat sheet" % key)
	check(not ["str","dex","int","con"].any(func(k): return Essences.stats("GNOLL_SPEAR").has(k)),"no attribute points from a stone")
	var d := duo(); var s = d.s
	var damage: int = int(Stats.stats(s,d.hero).damage)
	var hp: int = int(d.hero.max_hp); var mp: int = int(d.hero.max_mp)
	slot(d.hero,["LIZARD_TAIL"]); StatSheet.refresh_pools(s,d.hero)
	check(int(Stats.stats(s,d.hero).damage) == damage+4,"공격력 adds to the weapon's damage")
	check(int(d.hero.max_hp) == hp+8,"HP adds to the pool")
	check(StatSheet.value(s,d.hero,"atk") == 4,"the sheet shows the attack")
	slot(d.hero,["GOBLIN_HEXER"]); StatSheet.refresh_pools(s,d.hero)
	check(int(d.hero.max_hp) == hp and int(d.hero.max_mp) == mp+8,"a caster stone: MP, and the HP gone again")
	check(int(Stats.stats(s,d.hero).power) == 4,"주문력 reaches the spell power")
	var delay: int = int(s.action_cost(d.hero,"ATTACK",d.foe.pos))
	slot(d.hero,["KOBOLD_SLING","TOAD_SPIT"])
	check(StatSheet.value(s,d.hero,"speed") == 10 and int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == delay*90/100,"행동 속도 cuts the action's delay")
	slot(d.hero,["KOBOLD_SLING","TOAD_SPIT","STORM_BAT","STORM_BAT@fire","KOBOLD_SLING@fire","TOAD_SPIT@fire","GOBLIN_AIM","GOBLIN_AIM@fire","ORC_THROW","ORC_THROW@fire"])
	check(StoneEffects.speed(s,d.hero) == StoneEffects.SPEED_CAP,"speed stops at forty")
	slot(d.hero,["GOBLIN_SHIV","SPIDER_WEB"])
	check(int(Stats.stats(s,d.hero).dodge) == 10,"회피 % reaches the fight")

func rat() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["RAT_GNAW"])
	check(hit(s,d.hero,d.foe,20) == 22,"쥐: one adjacent ally, ten percent more")
	d.ally.pos = d.c+Vector2i(0,4)
	check(hit(s,d.hero,d.foe,20) == 20,"no ally beside, no bonus")
	check(not any_proc(s),"a standing effect raises no notice")

func lizard() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LIZARD_TAIL"])
	StoneEffects.force = 0
	var counter: int = int(Stats.stats(s,d.hero).damage)*60/100
	var foe_hp: int = int(d.foe.hp)
	hit(s,d.foe,d.hero,5)
	check(int(d.foe.hp) == foe_hp-counter and procs(s,"반격!") == 1 and logged(s,"반격"),"도마뱀: a melee blow is answered for sixty percent")
	foe_hp = int(d.foe.hp)
	s.damage(d.hero,5,int(d.foe.id),"SLASH")
	check(int(d.foe.hp) == foe_hp and procs(s,"반격!") == 1,"once an action")
	StoneEffects.force = 99
	foe_hp = int(d.foe.hp)
	hit(s,d.foe,d.hero,5)
	check(int(d.foe.hp) == foe_hp,"no counter when the roll fails")
	StoneEffects.force = 0
	d.foe.pos = d.c+Vector2i(3,0)
	hit(s,d.foe,d.hero,5)
	check(int(d.foe.hp) == foe_hp,"a blow from range is not answered")

func kobold() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["KOBOLD_SLING"])
	d.foe.pos = d.c+Vector2i(3,0)
	check(hit(s,d.hero,d.foe,20) == 25,"코볼트: ranged damage +25%")
	d.foe.pos = d.c+Vector2i(1,0)
	check(hit(s,d.hero,d.foe,20) == 20,"not point-blank")

func goblin() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_SHIV"])
	check(hit(s,d.hero,d.foe,10) == 20 and procs(s,"기습!") == 1,"고블린: the first blow on a full foe doubles")
	check(hit(s,d.hero,d.foe,10) == 10 and procs(s,"기습!") == 1,"a wounded foe takes it plain")

func goblin_aim() -> void:
	var d := duo(); var s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	slot(d.hero,["GOBLIN_AIM"])
	check(int(Stats.stats(s,d.hero).range) == int(Stats.content.weapons.bow.range)+2,"고블린 궁수: a bow reaches two farther")
	d.hero.gear.weapon = {"type":"sword","enchant":0}
	check(int(Stats.stats(s,d.hero).range) == 1,"a sword does not")
	check(StoneEffects.range_bonus({"enemy":true,"part_id":"GOBLIN_AIM","species_id":"goblin_archer"}) == 2,"a goblin archer shoots two farther")

func shield() -> void:
	var d := duo(); var s = d.s
	var before: int = StatSheet.value(s,d.hero,"sh")
	slot(d.hero,["SHIELD_STANCE"])
	check(StatSheet.value(s,d.hero,"sh") == before+20,"방패병: block +20")
	d.hero.gear.shield = {"type":"shield"}; d.hero.max_hp = 9999; d.hero.hp = 9999
	var blocked := false
	for i in range(60):
		s.Reactions.begin_action(s)
		if bool(Rules.attack(s,d.foe,d.hero).blocked): blocked = true; break
	check(blocked and procs(s,"막음!") >= 1,"a block is announced")

func hobgoblin() -> void:
	var d := duo(); var s = d.s
	var hp: int = int(d.hero.max_hp)
	slot(d.hero,["HOB_TAUNT"]); StatSheet.refresh_pools(s,d.hero)
	check(int(d.hero.max_hp) == (hp+20)*120/100,"홉고블린: max HP +20% over the stone's own")
	slot(d.hero,[]); StatSheet.refresh_pools(s,d.hero)
	check(int(d.hero.max_hp) == hp,"and it goes with the stone")
	check(StoneEffects.hp_percent(s,{"enemy":true,"part_id":"HOB_TAUNT","species_id":"dcss_hobgoblin"}) == 20,"a hobgoblin has the fifth more too")

func hexer() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GOBLIN_HEXER"])
	check(StoneEffects.status_ticks(d.hero,"confuse",100) == 150 and StoneEffects.status_ticks(d.hero,"burn",100) == 150,"주술사: what it hangs lasts half again")
	check(StoneEffects.status_ticks(d.hero,"haste",100) == 100,"a kind status is left alone")
	Spells.strike(s,d.hero,d.foe,{"school":"fire","status":"burn","element":"physical"},0,0,100)
	check(int(d.foe.statuses.get("burn",0)) == int(s.time)+150,"and a spell carries it")

func orc() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["ORC_CLEAVER"])
	check(hit(s,d.hero,d.foe,20) == 24,"오크: attack +20%")
	check(hit(s,d.foe,d.hero,20) == 22,"and takes a tenth more")

func thrower() -> void:
	var d := duo(); var s = d.s
	d.hero.gear.weapon = {"type":"bow","enchant":0}
	slot(d.hero,["ORC_THROW"])
	d.foe.pos = d.c+Vector2i(3,0); d.foe.hp = 400; d.foe.max_hp = 400
	StoneEffects.force = 0
	s.Reactions.begin_action(s)
	var swings: int = s.effects.size()
	StoneEffects.after_hit(s,d.foe,d.hero,"physical",5)
	check(procs(s,"연사!") == 1,"오크 투척병: a ranged hit may loose another")
	StoneEffects.after_hit(s,d.foe,d.hero,"physical",5)
	check(procs(s,"연사!") == 1,"once an action")
	check(s.effects.size() > swings,"the second shot is a real attack")
	s.Reactions.begin_action(s)
	d.foe.pos = d.c+Vector2i(1,0)
	StoneEffects.after_hit(s,d.foe,d.hero,"physical",5)
	check(procs(s,"연사!") == 1,"not in melee")

func status_proc(id: String, status: String, text: String) -> void:
	var d := duo(); var s = d.s
	slot(d.hero,[id])
	d.foe.hp = 400; d.foe.max_hp = 400
	StoneEffects.force = 99
	hit(s,d.hero,d.foe,5)
	check(not d.foe.statuses.has(status) and procs(s,text) == 0,"%s: nothing when the roll fails" % id)
	StoneEffects.force = 0
	hit(s,d.hero,d.foe,5)
	check(d.foe.statuses.has(status) and procs(s,text) == 1,"%s hangs %s with a notice" % [id,status])
	d.foe.statuses.erase(status)
	hit(s,d.hero,d.foe,5,"REACTION")
	check(not d.foe.statuses.has(status),"%s: a reaction's damage carries no proc" % id)

func spider() -> void: status_proc("SPIDER_WEB","bind","속박!")

func beetle() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["BEETLE_CURL"])
	check(hit(s,d.foe,d.hero,20) == 17,"딱정벌레: fifteen percent less taken")

func golem() -> void: status_proc("ORE_SLAM","stun","기절!")

func fire_caller() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["FIRE_CALLER"])
	StoneEffects.force = 99
	check(hit(s,d.hero,d.foe,10,"fire") == 13,"화염술사: fire +30%")
	check(hit(s,d.hero,d.foe,10) == 10,"other blows plain")
	status_proc("FIRE_CALLER","burn","화상!")

func storm_bat() -> void:
	var d := duo(); var s = d.s
	var cost: int = int(s.action_cost(d.hero,"ATTACK",d.foe.pos))
	slot(d.hero,["STORM_BAT"])
	check(StoneEffects.speed(s,d.hero) == 20 and int(s.action_cost(d.hero,"ATTACK",d.foe.pos)) == cost*80/100,"폭풍 박쥐: a fifth quicker")
	check(StoneEffects.speed(s,{"enemy":true,"part_id":"STORM_BAT","species_id":"storm_bat"}) == 20,"a storm bat is quick too")

func river_rat() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["RIVER_RAT_SPLASH"])
	d.ally.pos = d.c+Vector2i(0,4)
	check(hit(s,d.hero,d.foe,20) == 20,"강쥐: dry, plain")
	s.tile(d.hero.pos).wet = 50
	check(hit(s,d.hero,d.foe,20) == 25,"standing wet, a quarter more")

func leech() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["LEECH_LATCH"])
	d.foe.hp = 400; d.foe.max_hp = 400
	var dealt: Array = []
	for i in range(6): dealt.append(hit(s,d.hero,d.foe,20))
	check(dealt == [20,23,26,29,32,32],"거머리: fifteen percent a repeated blow, sixty at most")
	check(procs(s,"+15%") == 4,"announced while it stacks")
	var other: Dictionary = s.make_actor(950,"다른 적",true)
	other.pos = d.c+Vector2i(-1,0); other.hp = 40; other.max_hp = 40; s.enemies.append(other)
	check(hit(s,d.hero,other,20) == 20 and hit(s,d.hero,d.foe,20) == 20,"another target starts over")

func toad() -> void: status_proc("TOAD_SPIT","poison","중독!")

func serpent() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SERPENT_SHED"])
	StoneEffects.force = 0
	Statuses.apply(s,d.hero,"slow",100,d.foe)
	check(not d.hero.statuses.has("slow") and procs(s,"면역!") == 1,"신전 뱀: a status shrugged off")
	Statuses.apply(s,d.hero,"haste",100,d.hero)
	check(d.hero.statuses.has("haste"),"a kind one stays")
	StoneEffects.force = 99
	Statuses.apply(s,d.hero,"slow",100,d.foe)
	check(d.hero.statuses.has("slow"),"half the time it lands")

func water() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["WATER_WAVE"])
	d.hero.hp = 10; d.ally.hp = 10
	Passives.round_start(s,d.hero)
	check(int(d.hero.hp) == 10+maxi(1,int(d.hero.max_hp)*3/100) and int(d.ally.hp) == 10+maxi(1,int(d.ally.max_hp)*3/100),"물의 정령: itself and the ally beside heal three percent")
	check(procs(s,"+%d" % maxi(1,int(d.hero.max_hp)*3/100)) >= 1,"the heal is shown")
	d.ally.pos = d.c+Vector2i(0,4); d.ally.hp = 10
	Passives.round_start(s,d.hero)
	check(int(d.ally.hp) == 10,"not an ally away")

func gnoll() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GNOLL_SPEAR"])
	check(hit(s,d.hero,d.foe,20) == 20,"놀: whole, plain")
	d.hero.hp = int(d.hero.max_hp)/2
	check(hit(s,d.hero,d.foe,20) == 27 and procs(s,"분노!") == 1,"at half, +35% and a notice")
	check(hit(s,d.hero,d.foe,20) == 27 and procs(s,"분노!") == 1,"the notice only when it turns on")

func frost() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["FROST_IMP"])
	StoneEffects.force = 99
	check(hit(s,d.hero,d.foe,10,"ice") == 13,"서리 도깨비: ice +30%")
	status_proc("FROST_IMP","freeze","빙결!")

func summoner() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GNOLL_SUMMONER"])
	check(StoneEffects.summon_extra(d.hero) == 1,"놀 소환사: one more summon")
	var before: int = Spells.summons_of(s,d.hero).size()
	Spells.shaped_cast(s,d.hero,"summon_1",d.hero.pos,Spells.definition("summon_1"))
	check(Spells.summons_of(s,d.hero).size() == before+2,"a one-hound spell brings two")
	var pet: Dictionary = Spells.summons_of(s,d.hero)[0]
	check(hit(s,pet,d.foe,10) == 15,"its summons hit half again as hard")
	slot(d.hero,[])
	check(hit(s,pet,d.foe,10) == 10,"not once the stone is off")

func skeleton_wall() -> void:
	var d := duo(); var s = d.s
	slot(d.ally,["SKELETON_WALL"])
	check(hit(s,d.foe,d.hero,20) == 18,"해골 병사: an ally beside takes ten percent less")
	check(hit(s,d.foe,d.ally,20) == 20,"not the wearer itself")
	d.ally.pos = d.c+Vector2i(0,4)
	check(hit(s,d.foe,d.hero,20) == 20,"not from afar")

func volley() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["SKELETON_VOLLEY"])
	check(StoneEffects.crit_chance(s,d.hero,d.foe) == 15 and StoneEffects.crit_percent(d.hero) == 200,"해골 궁수: 15% critical, doubled")
	StoneEffects.force = 0
	check(hit(s,d.hero,d.foe,10) == 20 and procs(s,"치명타!") == 1 and logged(s,"치명타"),"a critical doubles with a notice and a line")

func ghoul() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GHOUL_CLAW"])
	d.hero.hp = 20; d.foe.hp = 3
	var heal: int = int(d.hero.max_hp)*15/100
	hit(s,d.hero,d.foe,5)
	check(int(d.foe.hp) <= 0 and int(d.hero.hp) == 20+heal and procs(s,"+%d" % heal) == 1,"구울: a kill heals fifteen percent")

func vampire() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["VAMPIRE_BITE"])
	d.hero.hp = 20
	hit(s,d.hero,d.foe,20)
	check(int(d.hero.hp) == 23 and procs(s,"+3") == 1,"흡혈 박쥐: fifteen percent of the damage back")
	hit(s,d.hero,d.foe,4)
	check(int(d.hero.hp) == 23 and procs(s,"+0") == 0,"nothing shown under one")

func thorns() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["THORN_ARMOUR"])
	var foe_hp: int = int(d.foe.hp)
	hit(s,d.foe,d.hero,20)
	check(int(d.foe.hp) == foe_hp-6 and procs(s,"반사!") == 1,"망령 기사: thirty percent of a melee blow reflected")
	d.foe.pos = d.c+Vector2i(3,0)
	hit(s,d.foe,d.hero,20)
	check(int(d.foe.hp) == foe_hp-6,"not a ranged one")

func wraith() -> void:
	status_proc("WRAITH","weak","약화!")
	var d := duo(); var s = d.s
	slot(d.hero,["WRAITH"])
	StoneEffects.force = 99
	var near: Dictionary = s.make_actor(951,"가까운 적",true)
	near.pos = d.c+Vector2i(2,1); near.hp = 40; near.max_hp = 40; s.enemies.append(near)
	var far: Dictionary = s.make_actor(952,"먼 적",true)
	far.pos = d.c+Vector2i(5,0); far.hp = 40; far.max_hp = 40; s.enemies.append(far)
	d.foe.hp = 3
	hit(s,d.hero,d.foe,5)
	check(near.statuses.has("confuse") and not far.statuses.has("confuse") and procs(s,"혼란!") >= 1,"원혼: a kill confuses foes within two")
	check(not d.ally.statuses.has("confuse"),"never a friend")

func gravekeeper() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["GRAVEKEEPER"])
	s.start_battle()
	d.hero.hp = 10
	hit(s,d.foe,d.hero,50)
	check(int(d.hero.hp) == int(d.hero.max_hp)*30/100 and procs(s,"부활!") == 1,"묘지기: a felling blow leaves thirty percent")
	d.hero.hp = 10
	hit(s,d.foe,d.hero,50)
	check(int(d.hero.hp) <= 0,"once a fight")
	check(StoneEffects.lethal(s,{"hp":5,"max_hp":50,"statuses":{}},10) == 10,"no stone, no rising")

func secondary() -> void:
	var d := duo(); var s = d.s
	slot(d.hero,["ORC_CLEAVER","VAMPIRE_BITE","SKELETON_VOLLEY"])
	StoneEffects.force = 0
	d.hero.hp = 20
	for form in ["EXTRA","REACTION","COUNTER","RETALIATE"]:
		check(hit(s,d.hero,d.foe,10,form) == 10,"%s damage takes no effect, combo or critical" % form)
	check(int(d.hero.hp) == 20 and not any_proc(s),"no lifesteal and no notice from secondary damage")
	slot(d.hero,["LIZARD_TAIL"])
	var foe_hp: int = int(d.foe.hp)
	hit(s,d.foe,d.hero,5,"COUNTER")
	check(int(d.foe.hp) == foe_hp,"a counter is never countered")

func monsters() -> void:
	var d := duo(); var s = d.s
	d.foe.part_id = "ORC_CLEAVER"
	check(StoneEffects.effects(d.foe) == ["ORC_CLEAVER"],"a monster has its species' stone effect")
	check(hit(s,d.foe,d.hero,20) == 24,"and it works")
	d.foe.part_id = "ORC_CLEAVER@fire"
	check(StoneEffects.effects(d.foe) == ["ORC_CLEAVER"],"a variant monster the same")
	d.foe.part_id = ""; d.foe.species_id = "dcss_orc"
	check(StoneEffects.effects(d.foe) == ["ORC_CLEAVER"],"the species row finds it without a part")
	d.foe.boss = true; d.foe.part_id = "FURNACE_HEART"; d.foe.species_id = "furnace_golem"
	check(StoneEffects.effects(d.foe).is_empty(),"a boss has none")
	slot(d.hero,["GOBLIN_CHIEF","SOUL_EATER"])
	check(StoneEffects.effects(d.hero).is_empty(),"nor do the boss stones a member wears")
	slot(d.hero,["GOBLIN_SHIV","GOBLIN_SHIV@fire","RAT_GNAW"])
	check(StoneEffects.effects(d.hero) == ["GOBLIN_SHIV","RAT_GNAW"],"a member has each of its stones' effects once")
