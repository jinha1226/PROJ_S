extends SceneTree
## Monster signature parts: catalog shape, basic parts (PUSH/GUARD) as catalog
## entries, passives, enemy telegraphs, town-only equipping, drops and snapshots.
const Session = preload("res://expedition/session.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Passives = preload("res://expedition/passives.gd")
const Builder = preload("res://expedition/encounter_builder.gd")
const MonsterAI = preload("res://expedition/monster_ai.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	catalog()
	basic_parts()
	bag()
	species()
	passives()
	telegraph()
	await ui()
	print("Parts: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## The parts tab, the equip chooser, the battle buttons and the bag detail.
func ui() -> void:
	var scene = load("res://expedition/main.tscn").instantiate()
	# Solo floor run, the shipped configuration: one member, two part slots.
	var s = Session.new(731,false,false,true,1)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(4): await process_frame
	scene.show_character(0,"파츠")
	for frame in range(4): await process_frame
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("파츠 슬롯"))
	check(not heading.is_empty() and heading[0].text == "파츠 슬롯 0 / 2","empty slots heading")
	var cards: Array = scene.modal_content.find_children("PartSlot*","PanelContainer",true,false)
	check(cards.size() == 2,"two slot cards")
	var buttons: Array = scene.modal_content.find_children("*","Button",true,false)
	check(buttons.filter(func(b): return b.text == "장착").size() == 2,"empty slots offer 장착")
	scene.CharacterUI.replace(scene,0)
	for frame in range(3): await process_frame
	var picks: Array = scene.item_detail.find_children("*","Button",true,false).map(func(b): return b.text)
	check("밀치기 ×1" in picks and "엄호 ×1" in picks,"chooser lists the bag with counts")
	scene.item_popup.hide()
	check(s.equip_part(0,0,"PUSH"),"equip through the session")
	scene.show_character(0,"파츠")
	for frame in range(4): await process_frame
	heading = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("파츠 슬롯"))
	check(heading[0].text == "파츠 슬롯 1 / 2","heading counts equipped parts")
	buttons = scene.modal_content.find_children("*","Button",true,false)
	check(buttons.any(func(b): return b.text == "해제") and buttons.any(func(b): return b.text == "교체"),"equipped slot offers 해제 and 교체")
	scene.details_popup.hide()
	# The floor battle is automatic, so an empty slot no longer shows as a
	# battle button: the parts tab above is where it reads 빈 슬롯.
	s.depart(); scene.refresh()
	for frame in range(3): await process_frame
	check(scene.skill_buttons.is_empty() and s.phase == "BATTLE","the floor HUD offers no per-slot skill buttons")
	# Bag: the parts category exists and the detail offers per-member slot buttons only in town.
	scene.inventory_filter = "파츠"; scene.show_supplies()
	for frame in range(3): await process_frame
	check(scene.inventory_slots.all(func(slot): return slot.row.is_empty() or slot.row.category == "파츠"),"parts filter")
	scene.show_item_detail("GUARD"); await process_frame
	var detail: Array = scene.item_detail.find_children("*","Button",true,false)
	check(detail.any(func(b): return b.text.ends_with("1번 장착") and b.disabled),"equip buttons are disabled outside town")
	scene.item_popup.hide(); scene.details_popup.hide()
	scene.queue_free(); await process_frame

## Every definition carries the part fields and a rule the schema accepts.
func catalog() -> void:
	for id in Abilities.DEFINITIONS:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		for key in ["species","passive","enemy","allies_hit","tile_wet"]:
			check(def.has(key),"%s has field %s" % [id,key])
		check(def.effect in ["DAMAGE","SHIELD","HEAL","LUNGE","PUSH","GUARD"],"%s effect known" % id)
		check(def.target in ["ENEMY","SELF","ALLY"],"%s target known" % id)
		check(int(def.enemy.get("prep",-1)) >= 0 and int(def.enemy.get("prep",-1)) <= 2,"%s prep in 0..2" % id)
		check(Rules.catalog().has(id),"%s in the derived rule catalog" % id)
		check(Rules.valid(Abilities.default_rule(id)),"%s default rule valid" % id)
	check(not Abilities.DEFINITIONS.has("drop") and not "drop" in Abilities.DEFINITIONS.PUSH,"drop field removed")
	check(Rules.skill("GUARD").targets == ["ALLY"] and Rules.skill("GUARD").conditions == ["ALLY_LETHAL"],"guard advertises ally/lethal")
	check(Rules.skill("PUSH").targets == ["NEAREST","LOWEST_HP"] and "CHARGING" in Rules.skill("PUSH").conditions,"push advertises enemy targets")
	check(Rules.skill("IRON_HIDE").targets == ["SELF"] and Rules.skill("IRON_HIDE").conditions == ["ALWAYS","HP","STATUS","DANGER"],"self skills advertise self conditions")
	check(Rules.skill("NOPE").is_empty(),"unknown skill is empty")
	check(Rules.defaults().is_empty(),"no rules before equipping")
	check(Abilities.default_rule("GUARD").target == "ALLY" and Abilities.default_rule("GUARD").when == "ALLY_LETHAL","guard default rule")
	check(Abilities.default_rule("PUSH").target == "NEAREST" and Abilities.default_rule("PUSH").when == "CHARGING","push default rule")
	check(Abilities.badge("PUSH") == Abilities.DEFINITIONS.PUSH.short and Abilities.badge("ATTACK") == "공격","badges from catalog and basics")

## 밀치기·엄호 run through the catalog path and need a slot.
func basic_parts() -> void:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]; var ally: Dictionary = s.party[1]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0
	foe.pos = c+Vector2i(1,0); ally.pos = c+Vector2i(0,1)
	s.floor_state.observe(s); s.selected = 0
	# Companions keep no actions so their turns cannot disturb the case.
	for actor in s.party: actor.ap = 0
	hero.ap = 3
	check(hero.equipped_abilities == ["",""] and hero.rules.is_empty(),"floor party starts with empty slots and no rules")
	check(not s.act("PUSH",foe.pos),"push needs a slot")
	check(not s.act("GUARD",ally.pos),"guard needs a slot")
	check(not s.Tactics.choose(s,hero).kind in ["PUSH","GUARD"],"tactics offer no unequipped basics")
	hero.equipped_abilities = ["PUSH","GUARD"]
	hero.rules = [Abilities.default_rule("PUSH"),Abilities.default_rule("GUARD")]
	var before: Vector2i = foe.pos
	check(s.act("PUSH",foe.pos) and foe.pos == before+Vector2i(1,0) and hero.ap == 2,"push moves the foe one cell and costs an action")
	check(s.act("GUARD",ally.pos) and hero.guarded and ally.protected_by == hero.id,"guard covers the adjacent ally")
	check(not s.act("GUARD",foe.pos) and not s.act("GUARD",hero.pos),"guard rejects foes and self")
	var legacy = Session.new(731,true,true)
	check(legacy.party[0].equipped_abilities == ["PUSH","GUARD"] and legacy.party[0].rules.size() == 2,"non-floor modes start with the basics equipped")

## Parts are items: town-only slots, one bag for the party, snapshot rules.
func bag() -> void:
	var s = Session.new(731,true,true,true,3)
	check(s.parts_bag == {"PUSH":1,"GUARD":1},"floor session starts with the two basics in the bag")
	check(s.stock("part:PUSH") == 1 and s.price("part:GUARD") == 10,"basics are shop goods")
	var bank: int = s.bank
	check(s.buy("part:GUARD") and s.parts_bag.GUARD == 2 and s.bank == bank-10,"buying a basic adds to the bag")
	check(s.refund("part:GUARD") and s.parts_bag.GUARD == 1 and s.bank == bank,"refund returns it")
	check(not s.provision_stock().has("part:PUSH") and s.provision_sale_value() == 0,"parts are never liquidated")
	check(not s.equip_part(0,2,"PUSH") and not s.equip_part(0,0,"BOMB") and not s.equip_part(0,0,"NOPE"),"bad slot, empty bag and unknown id refused")
	check(s.equip_part(0,0,"PUSH") and s.party[0].equipped_abilities[0] == "PUSH" and s.parts_bag.PUSH == 0,"equip takes the part from the bag")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "PUSH","equip adds the default rule")
	check(not s.equip_part(0,1,"PUSH"),"same part twice on one member refused")
	check(not s.equip_part(1,0,"PUSH"),"bag empty for the second member")
	s.parts_bag.PUSH = 1
	check(s.equip_part(1,0,"PUSH"),"another member may hold the same part")
	check(s.equip_part(0,0,"GUARD") and s.parts_bag.PUSH == 1 and s.party[0].equipped_abilities[0] == "GUARD","replacing returns the old part")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "GUARD","replacing swaps the rule")
	check(s.unequip_part(0,0) and s.party[0].equipped_abilities[0] == "" and s.parts_bag.GUARD == 1 and s.party[0].rules.is_empty(),"unequip empties the slot and the rule")
	check(not s.unequip_part(0,0),"empty slot cannot be unequipped")
	check(s.equip_part(0,0,"PUSH") and s.equip_part(0,1,"GUARD"),"both slots")
	s.depart()
	check(not s.equip_part(0,0,"PUSH") and not s.unequip_part(0,1),"slots are locked outside town")
	# Drops and the snapshot rule.
	Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	check(foe.part_id == Abilities.species_part(foe.species_id),"floor monsters carry their species part")
	var tries := 0; var got := false
	for enemy in s.enemies:
		enemy.hp = 0; s.roll_part(enemy); tries += 1
		if s.parts_bag.get(enemy.part_id,0) > 0: got = true
	check(got,"some monster in the roster drops its part (%d tried)" % tries)
	var carried: Dictionary = s.parts_bag.duplicate(true)
	s.loot = 10; s.objective.state = "CARRIED"
	for enemy in s.enemies: enemy.hp = 0
	s.floor_state.observe(s)
	check(s.abandon() and s.parts_bag == carried,"abandon keeps found parts")
	check(s.result.has("parts") and not s.result.has("essences"),"result reports parts")
	s.refit(); s.depart(); Fixture.arena(s,8)
	var kept: Dictionary = s.parts_bag.duplicate(true)
	s.parts_bag["HOB_CLUB"] = int(s.parts_bag.get("HOB_CLUB",0))+3
	s.damage(s.party[0],999,999,"IMPACT"); s.damage(s.party[1],999,999,"IMPACT"); s.damage(s.party[2],999,999,"IMPACT"); s.check_battle_end()
	check(s.result.reason == "DEFEAT" and s.parts_bag == kept,"defeat restores the bag snapshot")
	# Test loadout.
	var t = Session.new(731,false,false,true)
	check(t.grant_test_loadout() and t.log_lines[-1].begins_with("시험 로드아웃 · 파츠"),"test loadout grants parts")
	for id in Abilities.DEFINITIONS: check(t.parts_bag.get(id,0) >= 1,"loadout has "+id)
	var snapshot: Dictionary = t.parts_bag.duplicate(true)
	check(t.grant_test_loadout() and t.parts_bag == snapshot,"loadout is idempotent")
	t.depart(); check(not t.grant_test_loadout(),"loadout refused outside town")

## One part per species on the roster, every passive kind known.
func species() -> void:
	for row in Builder.table():
		var id: String = Abilities.species_part(row.species_id)
		check(not id.is_empty(),"%s has a signature part" % row.species_id)
		if id.is_empty(): continue
		var owners: Array = Abilities.DEFINITIONS.keys().filter(func(k): return Abilities.DEFINITIONS[k].species == row.species_id)
		check(owners.size() == 1,"%s has exactly one part" % row.species_id)
		var def: Dictionary = Abilities.DEFINITIONS[id]
		check(def.passive.kind in Passives.KINDS,"%s passive kind known" % id)
		check(int(def.enemy.prep) == 1,"%s floor-1 prep is 1" % id)
		check(int(def.damage) <= 14,"%s damage within the floor-1 cap" % id)
		check(int(def.passive.value) >= 1 and int(def.passive.value) <= 3,"%s passive value 1..3" % id)

## Two-member floor arena: hero at c, ally at c+(0,1), foe at c+(1,0), all fresh.
func duel() -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	Fixture.equip_basics(s)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0
	foe.pos = c+Vector2i(1,0); foe.part_id = ""
	s.party[1].pos = c+Vector2i(0,1); s.party[2].pos = c+Vector2i(-3,-3)
	s.light = 90; s.floor_state.observe(s); s.selected = 0
	for actor in s.party: actor.ap = 0
	s.party[0].ap = 3
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"far":s.party[2],"foe":foe}

## Gives a monster a part together with the species it belongs to: a passive
## only applies to the species that owns the part.
func give_part(foe: Dictionary, id: String) -> void:
	foe.part_id = id
	foe.species_id = str(Abilities.DEFINITIONS[id].species)

func passives() -> void:
	# PACK: +1 per adjacent living ally of the attacker.
	var d := duel(); var s = d.s
	give_part(d.foe,"RAT_GNAW")
	var second: Dictionary = s.enemies[1]; second.hp = 30; second.max_hp = 30; second.pos = d.c+Vector2i(2,0); second.alert = true
	var third: Dictionary = s.enemies[2]; third.hp = 30; third.max_hp = 30; third.pos = d.c+Vector2i(2,1); third.alert = true
	check(Passives.outgoing(s,d.foe,d.hero,7) == 9,"pack adds one per adjacent ally (two)")
	second.hp = 0
	check(Passives.outgoing(s,d.foe,d.hero,7) == 8,"dead allies do not count")
	# RETALIATE: adjacent attacker takes 2 after the hit; no chain.
	d = duel(); s = d.s
	d.hero.equipped_abilities = ["LIZARD_TAIL","GUARD"]
	var foe_hp: int = d.foe.hp
	s.damage(d.hero,5,d.foe.id,"IMPACT")
	check(d.foe.hp == foe_hp-2,"retaliate returns two to the adjacent attacker")
	give_part(d.foe,"LIZARD_TAIL"); foe_hp = d.foe.hp; var hero_hp: int = d.hero.hp
	s.damage(d.hero,5,d.foe.id,"IMPACT")
	check(d.foe.hp == foe_hp-2 and d.hero.hp < hero_hp,"retaliation itself is not retaliated")
	d.foe.pos = d.c+Vector2i(3,0); foe_hp = d.foe.hp
	s.damage(d.hero,5,d.foe.id,"IMPACT")
	check(d.foe.hp == foe_hp,"no retaliation at range")
	# Only a defender who survived the hit strikes back.
	d = duel(); s = d.s
	d.hero.equipped_abilities = ["LIZARD_TAIL","GUARD"]
	d.hero.hp = 1; foe_hp = d.foe.hp
	s.damage(d.hero,5,d.foe.id,"IMPACT")
	check(d.hero.hp <= 0 and d.foe.hp == foe_hp,"a slain defender does not retaliate")
	# DIRTY: +3 against targets under half health.
	d = duel(); s = d.s; give_part(d.foe,"KOBOLD_SLING")
	d.hero.hp = ceili(d.hero.max_hp/2.0)
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"dirty needs strictly under half")
	d.hero.hp -= 1
	check(Passives.outgoing(s,d.foe,d.hero,7) == 10,"dirty adds three under half")
	# AMBUSHER: +3 against a target with no adjacent living ally.
	d = duel(); s = d.s; give_part(d.foe,"GOBLIN_SHIV")
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"ally adjacent: no ambush bonus")
	check(Passives.outgoing(s,d.foe,d.far,7) == 10,"isolated target: ambush bonus")
	# THICK_HIDE: -1, never below 1.
	d = duel(); s = d.s; give_part(d.foe,"HOB_CLUB")
	check(Passives.incoming(s,d.foe,5) == 4 and Passives.incoming(s,d.foe,1) == 1,"thick hide subtracts one, floor one")
	# BLOODLUST: +3 when the attacker is under half.
	d = duel(); s = d.s; give_part(d.foe,"ORC_CLEAVER")
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"bloodlust off at full health")
	d.foe.hp = 14
	check(Passives.outgoing(s,d.foe,d.hero,7) == 10,"bloodlust on under half")
	# REGEN: +2 at round start, capped.
	d = duel(); s = d.s; give_part(d.foe,"GNOLL_SPEAR"); d.foe.hp = 20
	Passives.round_start(s,d.foe)
	check(d.foe.hp == 22,"regen heals two")
	d.foe.hp = 29; Passives.round_start(s,d.foe)
	check(d.foe.hp == 30,"regen never exceeds max")
	# AMPHIBIOUS: +3 on wet or water.
	d = duel(); s = d.s; give_part(d.foe,"RIVER_RAT_SPLASH")
	check(Passives.outgoing(s,d.foe,d.hero,7) == 7,"dry: no bonus")
	s.tile(d.foe.pos).wet = 40
	check(Passives.outgoing(s,d.foe,d.hero,7) == 10,"wet: bonus")
	# Hooks are wired: an equipped part's passive changes a real hit, and round start regenerates.
	d = duel(); s = d.s; d.hero.equipped_abilities = ["HOB_CLUB","GUARD"]
	hero_hp = d.hero.hp
	s.damage(d.hero,6,d.foe.id,"IMPACT")
	check(d.hero.hp == hero_hp-5,"equipped thick hide applies inside damage()")
	give_part(d.foe,"GNOLL_SPEAR"); d.foe.hp = 20
	# A monster far outside the fight is on the roster but not in it: no regen.
	var distant: Dictionary = s.enemies[1]
	var spot := Vector2i(-1,-1)
	for y in range(1,s.BOARD_SIDE-1):
		for x in range(1,s.BOARD_SIDE-1):
			var p := Vector2i(x,y)
			if maxi(absi(p.x-d.c.x),absi(p.y-d.c.y)) >= 20 and s.tile(p).terrain != "wall" and s.at(p).is_empty(): spot = p; break
		if spot != Vector2i(-1,-1): break
	check(spot != Vector2i(-1,-1),"a far cell exists for the distant monster")
	distant.hp = 20; distant.max_hp = 30; distant.alert = false; distant.pos = spot
	give_part(distant,"GNOLL_SPEAR")
	check(not s.combat_enemies().any(func(e): return e.id == distant.id),"the distant monster is not in the fight")
	s.act("WAIT",d.hero.pos); s.act("WAIT",d.hero.pos); s.act("WAIT",d.hero.pos)
	check(d.foe.hp >= 22,"regen runs at round start for monsters")
	check(distant.hp == 20,"a monster outside the fight does not regenerate")
	# A passive belongs to the species: a boss trial boss carries a part for its
	# drop only, so it grants no passive.
	var trial = Session.new(731,true,true); trial.depart()
	var boss: Dictionary = trial.enemies[0]
	check(not str(boss.get("part_id","")).is_empty(),"the boss carries a droppable part")
	check(Passives.of(boss).is_empty(),"a part that is not the species part grants no passive")

func telegraph() -> void:
	# Hobgoblin in contact: announces, resolves next round, cools down.
	var d := duel(); var s = d.s
	give_part(d.foe,"HOB_CLUB"); d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.foe.cast_id == "HOB_CLUB" and d.foe.cast_cell == d.hero.pos,"in contact the part is announced first")
	check(s.intents.size() == 1 and s.intents[0].kind == "HOB_CLUB" and int(s.intents[0].damage) == 14 and s.intents[0].cell == d.hero.pos,"intent carries the part and its damage")
	check(s.Rules.lethal_threat(s,d.hero) >= 14,"lethal threat reads the announced damage")
	var hp: int = d.hero.hp
	MonsterAI.turn(s,d.foe)
	check(not d.foe.charging and s.intents.is_empty(),"resolved on the next turn")
	check(d.hero.hp == hp-s.Growth.incoming(d.hero,14+s.floor_state.enemy_bonus(s.light)),"club lands for its damage plus the darkness bonus")
	check(int(d.foe.cooldowns.HOB_CLUB) == 4,"cooldown set (3 + 1)")
	check(int(s.battle_stats.enemy_parts.get("HOB_CLUB",0)) == 1,"enemy skill use counted")
	MonsterAI.turn(s,d.foe)
	check(not d.foe.charging and int(d.foe.cooldowns.HOB_CLUB) == 3,"on cooldown the role attack runs and the cooldown ticks")
	# Interrupt by push: cooldown consumed, one round of recovery.
	d = duel(); s = d.s; give_part(d.foe,"HOB_CLUB"); d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	check(s.act("PUSH",d.foe.pos),"hero pushes the charging foe")
	check(not d.foe.charging and s.intents.is_empty() and d.foe.cast_recovery == 1 and int(d.foe.cooldowns.HOB_CLUB) == 3,"push cancels the part and burns its cooldown")
	check(s.battle_stats.interrupts == 1,"interrupt counted")
	# Only 밀치기 breaks a part charge; an ordinary hit leaves it standing (spec §2.2).
	# The caster role's own spell is still broken by damage — tests/monster_roles.gd "damage interrupts spell".
	d = duel(); s = d.s; give_part(d.foe,"HOB_CLUB"); d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	hp = d.hero.hp
	check(s.act("ATTACK",d.foe.pos) and d.foe.charging and s.intents.size() == 1 and s.battle_stats.interrupts == 0,"a hit leaves the part charge standing")
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp < hp and int(s.battle_stats.enemy_parts.get("HOB_CLUB",0)) == 1,"the club still resolves after its owner was hit")
	# Target steps away: a radius-0 part misses.
	d = duel(); s = d.s; give_part(d.foe,"HOB_CLUB"); d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	d.hero.pos = d.c+Vector2i(-1,0); hp = d.hero.hp
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp == hp and s.log_lines[-1].contains("빗나갔습니다"),"an empty announced cell is a miss")
	# Area part spares the caster's own side.
	d = duel(); s = d.s; give_part(d.foe,"ORC_CLEAVER"); d.foe.cooldowns = {}
	var mate: Dictionary = s.enemies[1]; mate.hp = 30; mate.max_hp = 30; mate.alert = true; mate.pos = d.c+Vector2i(1,1); mate.part_id = ""
	MonsterAI.turn(s,d.foe)
	var ring: Array = Abilities.cells(s,d.foe,"ORC_CLEAVER",d.hero.pos)
	check(ring.size() >= 2 and s.intents.size() == ring.size(),"an area part announces every cell it will hit")
	check(s.intents.all(func(i): return i.kind == "ORC_CLEAVER" and int(i.damage) == 11),"every announced cell carries the part and its damage")
	check(s.Rules.lethal_threat(s,d.ally) >= 11,"the ally in the ring is threatened, not only the centre")
	var ally_hp: int = d.ally.hp; var mate_hp: int = mate.hp; hp = d.hero.hp
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp < hp and d.ally.hp < ally_hp and mate.hp == mate_hp,"cleave hits both members in the square and no fellow monster")
	# A telegraphed lunge never stabs a fellow monster who took the cell.
	d = duel(); s = d.s; give_part(d.foe,"GOBLIN_SHIV"); d.foe.cooldowns = {}
	d.foe.pos = d.c+Vector2i(2,0); s.floor_state.observe(s)
	MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.foe.cast_id == "GOBLIN_SHIV" and d.foe.cast_cell == d.hero.pos,"the shiv is announced on the hero's cell")
	var cell: Vector2i = d.foe.cast_cell
	d.hero.pos = d.c+Vector2i(-2,0)
	var comrade: Dictionary = s.enemies[1]
	comrade.hp = 30; comrade.max_hp = 30; comrade.alert = true; comrade.pos = cell; comrade.part_id = ""
	s.floor_state.observe(s)
	MonsterAI.turn(s,d.foe)
	check(comrade.hp == 30,"the announced cell's new occupant is a fellow monster and takes nothing")
	check(s.log_lines[-1].contains("빗나갔습니다"),"a lunge onto one's own side is a miss")
	check(int(s.battle_stats.enemy_parts.get("GOBLIN_SHIV",0)) == 1,"the use is still counted")
	# A prep 0 part fires at once; a longer charge keeps its announcement until the count runs out.
	# (DEFINITIONS is a const dictionary and read-only at runtime, so prep comes from the catalog.)
	d = duel(); s = d.s; give_part(d.foe,"HEAVY_STRIKE"); d.foe.cooldowns = {}
	hp = d.hero.hp; MonsterAI.turn(s,d.foe)
	check(int(Abilities.DEFINITIONS.HEAVY_STRIKE.enemy.prep) == 0 and d.hero.hp < hp and not d.foe.charging,"prep 0 resolves immediately")
	d = duel(); s = d.s; give_part(d.foe,"HOB_CLUB"); d.foe.cooldowns = {}
	hp = d.hero.hp; MonsterAI.turn(s,d.foe)
	d.foe.cast_left = 2
	MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.hero.hp == hp and s.intents.size() == 1 and d.foe.cast_left == 1,"a two-round charge is still announced after one more turn")
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp < hp,"it resolves once the count runs out")
	# Caster role keeps its spell when the part is on cooldown; the part goes first when both are ready.
	d = duel(); s = d.s; give_part(d.foe,"KOBOLD_SLING"); d.foe.cooldowns = {}; d.foe.role = "CASTER"; d.foe.cast_cooldown = 0
	d.foe.pos = d.c+Vector2i(3,0); s.floor_state.observe(s)
	MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.foe.cast_id == "KOBOLD_SLING","part before role spell")
	# Player use is immediate and grows with the melee axis.
	d = duel(); s = d.s; d.hero.equipped_abilities = ["HOB_CLUB","GUARD"]; d.hero.cooldowns = {}
	var foe_hp: int = d.foe.hp
	check(s.act("HOB_CLUB",d.foe.pos) and d.foe.hp == foe_hp-s.Growth.power(d.hero,"MELEE",14) and d.hero.ap == 2 and int(d.hero.cooldowns.HOB_CLUB) == 4,"player club is immediate, scaled and cooled")
