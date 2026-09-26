extends SceneTree
## The bestiary (zones §2): thirty species in four zones, their families,
## roles and variants, and the two stat formulas (§3).
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Bestiary = preload("res://expedition/progression/bestiary.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	table()
	formulas()
	parts()
	actives()
	print("Bestiary: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func table() -> void:
	var rows: Array = Bestiary.table()
	check(rows.size() == 30,"thirty base species")
	var variants := 0
	for row in rows:
		var id: String = str(row.species_id)
		var zone: int = int(row.get("zone",0))
		check(zone >= 1 and zone <= 4,"%s has a zone" % id)
		check(str(row.get("family","")) in Bestiary.FAMILIES,"%s has a family" % id)
		check(str(row.get("role","")) in Bestiary.ROLES,"%s has a role" % id)
		check(int(row.min_depth) == zone*3-2 and int(row.max_depth) == zone*3,"%s appears on its zone's three floors" % id)
		for element in row.get("variants",[]):
			check(str(element) in ["fire","ice","air","poison","will","bleed"],"%s variant %s is an element" % [id,element])
		variants += row.get("variants",[]).size()
	check(variants == 59,"fifty-nine variants (%d)" % variants)
	var sizes := {1:8,2:7,3:8,4:7}
	for zone in sizes:
		var ids: Array = Bestiary.in_zone(zone)
		check(ids.size() == sizes[zone],"zone %d holds %d species" % [zone,sizes[zone]])
		var roles: Dictionary = {}
		for id in ids: roles[str(Bestiary.species(id).role)] = true
		check(roles.size() == 6,"zone %d shows all six roles" % zone)
	check(Bestiary.species("storm_bat").role == "PACK","the storm bat is a pack animal now")
	check(Bestiary.species("dcss_frilled_lizard").role == "BERSERK" and Bestiary.species("dcss_hobgoblin").role == "GUARD","the two re-roled species")
	check(Bestiary.species("dcss_river_rat").family == "rat" and Bestiary.species("dcss_hobgoblin").family == "goblin","families regroup old species")
	check(Bestiary.species("nope").is_empty(),"an unknown species is empty")

func formulas() -> void:
	check(Bestiary.zone_of(1) == 1 and Bestiary.zone_of(3) == 1 and Bestiary.zone_of(4) == 2 and Bestiary.zone_of(12) == 4 and Bestiary.zone_of(15) == 4,"three floors a zone, four zones")
	check(Bestiary.floor_percent(1) == 100 and Bestiary.floor_percent(2) == 110 and Bestiary.floor_percent(3) == 120 and Bestiary.floor_percent(4) == 100,"ten percent a floor inside a zone")
	var rat: Dictionary = Bestiary.monster_stats("dcss_rat",1)
	check(int(rat.hp) == 18 and int(rat.attack) == 6 and int(rat.range) == 1,"a first-floor rat: 30×0.6 HP, 8×0.8 attack")
	var shield: Dictionary = Bestiary.monster_stats("goblin_shield",3)
	check(int(shield.hp) == 50 and int(shield.attack) == 7 and int(shield.ac) == 3 and int(shield.sh) == 20,"a guard on floor three: ×1.2 then ×1.4 HP, armour 3, block 20")
	var orc: Dictionary = Bestiary.monster_stats("dcss_orc",4)
	check(int(orc.hp) == 77 and int(orc.attack) == 18 and int(orc.ac) == 1,"an orc on floor four: zone two")
	var archer: Dictionary = Bestiary.monster_stats("skeleton_archer",12)
	check(int(archer.range) == 4 and int(archer.attack_percent) == 390,"deep archers reach four; actives scale by 26×1.2/8")
	var ambush: Dictionary = Bestiary.monster_stats("goblin",1)
	check(int(ambush.ev) == 7,"an ambusher dodges four more")
	check(Bestiary.essence_stats("MELEE","") == {"atk":4,"hp":8},"광폭: 공격력 4, 최대 HP 8")
	check(Bestiary.essence_stats("TANK","") == {"hp":20,"ac":3},"수호: 최대 HP 20, 방어 3")
	check(Bestiary.essence_stats("MAGIC","fire") == {"spell":4,"mp":8},"술사: 주문력 4, 최대 MP 8")
	check(Bestiary.essence_stats("MAGIC","hex") == Bestiary.essence_stats("MAGIC","fire"),"every caster stone is the same, whatever its school")
	check(Bestiary.essence_stats("MAGIC","") == {"spell":4,"mp":8},"a caster with no school too")
	check(Bestiary.essence_stats("SUPPORT") == {"hp":10,"mp":6},"support base pools")
	var total := 0
	for role in Bestiary.ROLE_POINTS:
		var keys: Array = (Bestiary.ROLE_POINTS[role] as Dictionary).keys()
		check(keys.size() == 2 and keys.all(func(k): return str(k) in ["atk","hp","spell","mp","speed","dodge","ac"]),"%s stones give two fight numbers, no attribute points" % role)
		total += 1
	check(total == 5,"five roles priced")

func parts() -> void:
	for row in Bestiary.table():
		var id: String = str(row.species_id)
		var part: String = Abilities.species_part(id)
		check(not part.is_empty(),"%s has its active" % id)
		if part.is_empty(): continue
		check(Essences.has(part) and Essences.family(part) == str(row.family) and Essences.role(part) in Essences.ROLES,"%s stone carries the family and role" % id)
		check(Essences.row(part).stats == Bestiary.essence_stats(Essences.role(part),Essences.school(part)),"%s stone stats come from the role formula" % id)
		check(Essences.school(part).is_empty() == (str(row.role) != "CASTER" and id != "storm_bat"),"%s gives a spell exactly when it should" % id)
		for element in row.get("variants",[]):
			check(Abilities.has("%s@%s" % [part,element]) and Essences.has("%s@%s" % [part,element]),"%s@%s exists" % [part,element])
	check(not Essences.row("GHOUL_CLAW@bleed").stats.has("res_bleed"),"a bleed variant adds no resistance")
	check(int(Essences.row("ORE_SLAM@fire").stats.get("res_fire",0)) == 10,"a fire variant adds fire resistance ten")
	check(Essences.row("STORM_BAT").role == "RANGED" and Essences.school("STORM_BAT") == "air","the storm bat stone is pack but still sparks")

## Hero at c, a fresh foe beside at c+(1,0).
func arena(ids: Array) -> Dictionary:
	var s = Session.new(731,false,false,true,1); s.depart(); s.manual_mode = true
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 40; foe.max_hp = 40; foe.pos = c+Vector2i(1,0); foe.part_id = ""; foe.species_id = ""; foe.res = {}; foe.statuses = {}; foe.sh = 0; foe.ev = 0
	var hero: Dictionary = s.party[0]
	hero.level = maxi(1,ids.size()); hero.equipped_abilities = ids.duplicate(); hero.essences = {}
	for id in ids: hero.essences[id] = 1
	hero.cooldowns = {}; hero.ap = 2
	s.floor_state.observe(s); s.phase = "BATTLE"
	return {"s":s,"c":c,"hero":hero,"foe":foe}

func actives() -> void:
	var f := arena(["LEECH_LATCH"]); var s = f.s
	f.hero.hp = 20
	var foe_hp: int = f.foe.hp
	check(Abilities.execute(s,f.hero,"LEECH_LATCH",f.foe.pos),"달라붙기 lands")
	check(f.hero.hp == 20+(foe_hp-f.foe.hp),"and heals what it took")
	f = arena(["ORC_THROW"]); s = f.s; f.foe.pos = f.c+Vector2i(2,0); s.floor_state.observe(s)
	check(Abilities.execute(s,f.hero,"ORC_THROW",f.foe.pos) and f.foe.pos == f.c+Vector2i(3,0),"도끼 투척 pushes one cell away")
	f = arena(["TOAD_SPIT"]); s = f.s
	check(Abilities.execute(s,f.hero,"TOAD_SPIT",f.foe.pos) and f.foe.statuses.has("poison"),"독침 poisons")
	f = arena(["SPIDER_WEB"]); s = f.s; foe_hp = f.foe.hp
	check(Abilities.execute(s,f.hero,"SPIDER_WEB",f.foe.pos) and f.foe.statuses.has("bind") and f.foe.hp == foe_hp,"거미줄 binds without a wound")
	f = arena(["SKELETON_VOLLEY"]); s = f.s; foe_hp = f.foe.hp
	var one: int = Abilities.power(s,f.hero,Abilities.definition("SKELETON_VOLLEY"),"SKELETON_VOLLEY")
	check(Abilities.execute(s,f.hero,"SKELETON_VOLLEY",f.foe.pos) and foe_hp-f.foe.hp == 2*one,"연사 strikes twice")
	f = arena(["GHOUL_CLAW"]); s = f.s
	check(Abilities.execute(s,f.hero,"GHOUL_CLAW",f.foe.pos) and f.foe.statuses.has("bleed"),"할퀴기 bleeds")
	f = arena(["VAMPIRE_BITE"]); s = f.s; f.foe.pos = f.c+Vector2i(2,0); f.hero.hp = 20; s.floor_state.observe(s)
	foe_hp = f.foe.hp
	check(Abilities.execute(s,f.hero,"VAMPIRE_BITE",f.foe.pos) and s.melee_reach(f.hero.pos,f.foe.pos),"흡혈 물기 closes in")
	check(f.hero.hp == 20+(foe_hp-f.foe.hp)/2+(foe_hp-f.foe.hp)*15/100,"and drinks half, and the stone's own fifteen percent")
	f = arena(["ORE_SLAM@bleed"]); s = f.s
	check(Abilities.execute(s,f.hero,"ORE_SLAM@bleed",f.foe.pos) and f.foe.statuses.has("bleed") and f.foe.statuses.has("slow"),"a bleed variant bleeds on top of its own status")
	var w := arena(["WATER_WAVE"]); s = w.s
	var ally: Dictionary = s.make_actor(50,"동료",false); ally.pos = w.c+Vector2i(3,1); ally.hp = 30; ally.max_hp = 30
	s.party.append(ally)
	w.foe.pos = w.c+Vector2i(3,0); s.floor_state.observe(s)
	var ally_hp: int = ally.hp
	check(Abilities.execute(s,w.hero,"WATER_WAVE",w.foe.pos),"해일 breaks")
	check(int(s.tile(w.c+Vector2i(3,0)).wet) >= 100 and ally.hp < ally_hp,"it wets the ground and sweeps allies too")
