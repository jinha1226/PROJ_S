extends SceneTree
## Monster signature parts: catalog shape, basic parts (PUSH/GUARD) as catalog
## entries, passives, enemy telegraphs, camp-only equipping and drops.
const Session = preload("res://expedition/run/session.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Families = preload("res://expedition/combat/families.gd")
const Rules = preload("res://expedition/ai/tactic_rules.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Passives = preload("res://expedition/combat/passives.gd")
const Builder = preload("res://expedition/level/encounter_builder.gd")
const MonsterAI = preload("res://expedition/actors/monster_ai.gd")
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
	telegraph()
	await ui()
	print("Parts: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## The parts tab, the equip chooser, the battle buttons and the bag detail.
func ui() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	# Solo floor run, the shipped configuration: one member, two part slots.
	var s = Session.new_run(731)
	s.parts_bag = {"RAT_GNAW":1,"GOBLIN_SHIV":1}
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await process_frame
	for frame in range(4): await process_frame
	s.phase = "CAMP"
	scene.show_character(0,"파츠")
	for frame in range(4): await process_frame
	var heading: Array = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("영혼석 슬롯"))
	check(not heading.is_empty() and heading[0].text == "영혼석 슬롯 0 / 1","empty slots heading")
	var cards: Array = scene.modal_content.find_children("EssenceSlot*","Button",true,false)
	check(cards.size() == 10,"ten essence slot cells")
	scene.find_child("EssenceSlot0",true,false).pressed.emit()
	for frame in range(3): await process_frame
	check(scene.item_detail.find_children("*","Label",true,false).any(func(l): return l.text == "흡수한 영혼석 없음"),"chooser only lists absorbed essences")
	check(scene.modal_content.find_children("EssenceAbsorb_*","Button",true,false).size() >= 2,"the tab offers bag absorption")
	scene.item_popup.hide()
	check(s.equip_part(0,0,"RAT_GNAW"),"equip through the session")
	scene.show_character(0,"파츠")
	for frame in range(4): await process_frame
	heading = scene.modal_content.find_children("*","Label",true,false).filter(func(l): return l.text.begins_with("영혼석 슬롯"))
	check(heading[0].text == "영혼석 슬롯 1 / 1","heading counts equipped essences")
	scene.find_child("EssenceSlot0",true,false).pressed.emit()
	await process_frame
	check(scene.item_detail.find_child("EssenceUnequip",true,false) != null,"equipped slot offers removal")
	scene.details_popup.hide()
	# The floor battle is automatic, so an empty slot no longer shows as a
	# battle button: the parts tab above is where it reads 빈 슬롯.
	s.phase = "BATTLE"; scene.refresh()
	for frame in range(3): await process_frame
	check(scene.skill_buttons.is_empty() and s.phase == "BATTLE","the floor HUD offers no per-slot skill buttons")
	# Bag: the parts category exists and equipping is limited to camp.
	scene.inventory_filter = "파츠"; scene.show_supplies()
	for frame in range(3): await process_frame
	check(scene.inventory_slots.all(func(slot): return slot.row.is_empty() or slot.row.category == "파츠"),"parts filter")
	scene.show_item_detail("GOBLIN_SHIV"); await process_frame
	var detail: Array = scene.item_detail.find_children("*","Button",true,false)
	check(detail.any(func(b): return b.text.contains("흡수") and b.disabled),"absorption is disabled outside camp")
	scene.item_popup.hide(); scene.details_popup.hide()
	scene.queue_free(); await process_frame

## Every definition carries the part fields and a rule the schema accepts.
func catalog() -> void:
	for id in Abilities.DEFINITIONS:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		for key in ["species","passive","enemy","allies_hit","tile_wet"]:
			check(def.has(key),"%s has field %s" % [id,key])
		check(def.effect in ["DAMAGE","SHIELD","HEAL","LUNGE","PUSH","GUARD","STANCE","TAUNT","CLEANSE","WARD_ALLIES","THORNS","MARK","FURNACE","DEVOUR"],"%s effect known" % id)
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
## 밀치기·엄호 are basic actions every member has: no slot, no stone.
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
	check(hero.equipped_abilities == [""] and hero.rules.is_empty(),"floor party starts with an empty slot and no rules")
	check(Abilities.holds(hero,"PUSH") and Abilities.holds(hero,"GUARD"),"every member holds push and guard")
	check(not Essences.has("PUSH") and not Essences.has("GUARD") and "PUSH" not in Abilities.droppable(),"the basics are not soul stones and drop from nothing")
	check(not Abilities.holds(foe,"PUSH"),"a monster pushes only if push is its own part")
	var before: Vector2i = foe.pos
	check(s.act("PUSH",foe.pos) and foe.pos == before+Vector2i(1,0) and hero.ap == 2,"push moves the foe one cell and costs an action")
	check(s.act("GUARD",ally.pos) and hero.guarded and ally.protected_by == hero.id,"guard covers the adjacent ally")
	check(not s.act("GUARD",foe.pos) and not s.act("GUARD",hero.pos),"guard rejects foes and self")
	var legacy = Session.new(731,true,true)
	check(legacy.party[0].equipped_abilities == [""] and legacy.parts_bag.is_empty(),"legacy constructor starts with an empty slot and bag")
	check(not Abilities.has("HEAVY_STRIKE") and not Abilities.has("FIELD_DRESSING") and not Abilities.has("THROWING_KNIFE") and not Abilities.has("LUNGE"),"the four trial parts are gone")

func bag() -> void:
	var s = Session.new(731,true,true,true,3); s.depart()
	check(s.parts_bag.is_empty(),"a run starts with an empty bag: 밀치기·엄호 are basic actions")
	check(not s.has_method("buy") and not s.has_method("price"),"parts have no shop API")
	s.grant_part("GOBLIN_CHIEF")
	check(s.parts_bag.GOBLIN_CHIEF == 1,"parts can be gained in the dungeon")
	s.grant_part("GOBLIN_CHIEF")
	check(s.parts_bag.GOBLIN_CHIEF == 2,"new parts stack in the bag")
	s.parts_bag.erase("GOBLIN_CHIEF")
	check(s.parts_bag.get("GOBLIN_CHIEF",0) == 0,"unowned parts stay absent")
	s.parts_bag["RAT_GNAW"] = 1; s.parts_bag["GOBLIN_SHIV"] = 1
	s.phase = "CAMP"
	check(not s.equip_part(0,1,"RAT_GNAW") and not s.equip_part(0,0,"GOBLIN_CHIEF") and not s.equip_part(0,0,"NOPE"),"closed slot, empty bag and unknown id refused")
	check(s.equip_part(0,0,"RAT_GNAW") and s.party[0].equipped_abilities[0] == "RAT_GNAW" and s.parts_bag.RAT_GNAW == 0,"equip absorbs the part from the bag")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "RAT_GNAW","equip adds the default rule")
	s.gain_level_xp(s.party[0],65)
	check(not s.equip_part(0,1,"RAT_GNAW"),"same part twice on one member refused")
	check(not s.equip_part(1,0,"RAT_GNAW"),"bag empty for the second member")
	s.parts_bag.RAT_GNAW = 1
	check(s.equip_part(1,0,"RAT_GNAW"),"another member may hold the same part")
	check(s.equip_part(0,0,"GOBLIN_SHIV") and s.parts_bag.get("RAT_GNAW",0) == 0 and int(s.party[0].essences.RAT_GNAW) == 1 and s.party[0].equipped_abilities[0] == "GOBLIN_SHIV","replacing keeps the old part absorbed")
	check(s.party[0].rules.size() == 1 and s.party[0].rules[0].skill == "GOBLIN_SHIV","replacing swaps the rule")
	check(s.unequip_part(0,0) and s.party[0].equipped_abilities[0] == "" and s.parts_bag.get("GOBLIN_SHIV",0) == 0 and s.party[0].rules.is_empty(),"unequip empties the slot without returning a part")
	check(not s.unequip_part(0,0),"empty slot cannot be unequipped")
	check(s.equip_part(0,0,"RAT_GNAW") and s.equip_part(0,1,"GOBLIN_SHIV"),"both slots use absorbed essences")
	s.phase = "BATTLE"
	check(not s.equip_part(0,0,"RAT_GNAW") and not s.unequip_part(0,1),"slots are locked in a fight")
	# Drops stay with the run across floors and after defeat.
	Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	check(foe.part_id == Abilities.species_part(foe.species_id),"floor monsters carry their species part")
	var tries := 0; var got := false
	for enemy in s.enemies:
		enemy.hp = 0; s.roll_part(enemy); tries += 1
		if s.parts_bag.get(enemy.part_id,0) > 0: got = true
	check(got,"some monster in the roster drops its part (%d tried)" % tries)
	var carried: Dictionary = s.parts_bag.duplicate(true)
	for enemy in s.enemies: enemy.hp = 0
	s.floor_state.observe(s)
	s.party[0].pos = s.floor_state.layout.stairs
	check(s.descend() and s.parts_bag == carried,"descent keeps found parts")
	check(s.depth == 2 and s.floor_state.layout.theme_id == "F1_RUINS","descent makes next floor in the zone")
	s.parts_bag["ORE_SLAM"] = int(s.parts_bag.get("ORE_SLAM",0))+3
	var fallen_bag: Dictionary = s.parts_bag.duplicate(true)
	s.damage(s.party[0],999,999,"IMPACT"); s.check_battle_end()
	check(s.phase == "DEFEAT" and s.parts_bag == fallen_bag,"defeat ends the run without rolling back the bag")
	# Test loadout.
	var t = Session.new(731,false,false,true)
	check(t.grant_test_loadout() and t.log_lines[-1].begins_with("시험 로드아웃 · 영혼석"),"test loadout grants essences")
	for id in Essences.content.rows: check(t.parts_bag.get(id,0) >= 1,"loadout has "+id)
	var snapshot: Dictionary = t.parts_bag.duplicate(true)
	check(t.grant_test_loadout() and t.parts_bag == snapshot,"loadout is idempotent")
	t.depart(); check(t.grant_test_loadout() and t.parts_bag == snapshot,"loadout stays idempotent during the run")

## One part per species on the roster, every passive kind known.
func species() -> void:
	for row in Builder.table():
		var id: String = Abilities.species_part(row.species_id)
		check(not id.is_empty(),"%s has a signature part" % row.species_id)
		if id.is_empty(): continue
		var owners: Array = Abilities.DEFINITIONS.keys().filter(func(k): return Abilities.DEFINITIONS[k].species == row.species_id)
		check(owners.size() == 1,"%s has exactly one part" % row.species_id)
		var def: Dictionary = Abilities.DEFINITIONS[id]
		check(str(row.get("family","")) in Families.PASSIVES,"%s family passive known" % id)
		check(int(def.enemy.prep) in [0,1,2],"%s prep is bounded" % id)
		check(int(def.damage) <= 24,"%s damage stays within the active cap" % id)
		check(Abilities.has(id),"%s signature ability exists" % id)

## Two-member floor arena: hero at c, ally at c+(0,1), foe at c+(1,0), all fresh.
func duel() -> Dictionary:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	Fixture.equip_basics(s)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0
	foe.pos = c+Vector2i(1,0); foe.part_id = ""
	s.party[1].pos = c+Vector2i(0,1); s.party[2].pos = c+Vector2i(-3,-3)
	s.floor_state.observe(s); s.selected = 0
	for actor in s.party: actor.ap = 0
	s.party[0].ap = 3
	return {"s":s,"c":c,"hero":s.party[0],"ally":s.party[1],"far":s.party[2],"foe":foe}

## Gives a monster a part together with the species it belongs to: a passive
## only applies to the species that owns the part.
func give_part(foe: Dictionary, id: String) -> void:
	foe.part_id = id
	foe.species_id = str(Abilities.DEFINITIONS[id].species)

func telegraph() -> void:
	# Hobgoblin in contact: announces, resolves next round, cools down.
	var d := duel(); var s = d.s
	give_part(d.foe,"ORE_SLAM"); d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	check(d.foe.charging and d.foe.cast_id == "ORE_SLAM" and d.foe.cast_cell == d.hero.pos,"in contact the part is announced first")
	check(s.intents.size() == 1 and s.intents[0].kind == "ORE_SLAM" and int(s.intents[0].damage) == 14 and s.intents[0].cell == d.hero.pos,"intent carries the part and its damage")
	check(s.Rules.lethal_threat(s,d.hero) >= 14,"lethal threat reads the announced damage")
	var hp: int = d.hero.hp
	MonsterAI.turn(s,d.foe)
	check(not d.foe.charging and s.intents.is_empty(),"resolved on the next turn")
	check(d.hero.hp == hp-14,"club lands for its announced damage")
	check(int(d.foe.cooldowns.ORE_SLAM) == 4,"cooldown set (3 + 1)")
	check(int(s.battle_stats.enemy_parts.get("ORE_SLAM",0)) == 1,"enemy skill use counted")
	MonsterAI.turn(s,d.foe)
	check(not d.foe.charging and int(d.foe.cooldowns.ORE_SLAM) == 3,"on cooldown the role attack runs and the cooldown ticks")
	# Interrupt by push: cooldown consumed, one round of recovery.
	d = duel(); s = d.s; give_part(d.foe,"ORE_SLAM"); d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	check(s.act("PUSH",d.foe.pos),"hero pushes the charging foe")
	check(not d.foe.charging and s.intents.is_empty() and d.foe.cast_recovery == 1 and int(d.foe.cooldowns.ORE_SLAM) == 3,"push cancels the part and burns its cooldown")
	check(s.battle_stats.interrupts == 1,"interrupt counted")
	# Only 밀치기 breaks a part charge; an ordinary hit leaves it standing (spec §2.2).
	# The caster role's own spell is still broken by damage — tests/monster_roles.gd "damage interrupts spell".
	d = duel(); s = d.s; give_part(d.foe,"ORE_SLAM"); d.foe.cooldowns = {}
	MonsterAI.turn(s,d.foe)
	hp = d.hero.hp
	check(s.act("ATTACK",d.foe.pos) and d.foe.charging and s.intents.size() == 1 and s.battle_stats.interrupts == 0,"a hit leaves the part charge standing")
	MonsterAI.turn(s,d.foe)
	check(d.hero.hp < hp and int(s.battle_stats.enemy_parts.get("ORE_SLAM",0)) == 1,"the club still resolves after its owner was hit")
	# Target steps away: a radius-0 part misses.
	d = duel(); s = d.s; give_part(d.foe,"ORE_SLAM"); d.foe.cooldowns = {}
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
	# An immediate defensive part resolves without announcing a damaging cell.
	d = duel(); s = d.s; give_part(d.foe,"BEETLE_CURL"); d.foe.cooldowns = {}
	Abilities.resolve(s,d.foe,"BEETLE_CURL",d.foe.pos)
	check(int(Abilities.DEFINITIONS.BEETLE_CURL.enemy.prep) == 0 and bool(d.foe.iron_guard),"prep 0 defensive part resolves immediately")
	d = duel(); s = d.s; give_part(d.foe,"ORE_SLAM"); d.foe.cooldowns = {}
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
	d = duel(); s = d.s; d.hero.equipped_abilities = ["ORE_SLAM","GUARD"]; d.hero.cooldowns = {}
	var foe_hp: int = d.foe.hp
	check(s.act("ORE_SLAM",d.foe.pos) and d.foe.hp == foe_hp-Abilities.power(s,d.hero,Abilities.DEFINITIONS.ORE_SLAM,"ORE_SLAM") and d.hero.ap == 2 and int(d.hero.cooldowns.ORE_SLAM) == 4,"player club is immediate, scaled and cooled")
