extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Simulator=preload("res://sim/simulator.gd")
const Mystery=preload("res://sim/mystery_consumables.gd")
const Catalog=preload("res://sim/item_catalog_registry.gd")
const Drops=preload("res://sim/species_drop_registry.gd")
const Item=preload("res://sim/item_instance.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Assets=preload("res://playtest/dungeon_0x72_assets.gd")
const Action=preload("res://sim/party_action_command.gd")
const RECOVERY_IDS=["POTION_MYSTERY_HEAL","POTION_MYSTERY_MANA","SCROLL_MYSTERY_HEAL","SCROLL_MYSTERY_MANA"]
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func give(s,id:String):
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var inv=w.inventory_of(hero)
	var items:Array=inv.backpack.duplicate();items.append(Item.new("TEST_"+id,id,2 if Mystery.has(id) else 1))
	w.item_state.inventory_rows[hero]=Inventory.new(items,inv.equipped)
func recovery_tests():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var hero:int=s.sim.world.party_control_actor_id()
	give(s,"ESSENCE_ECHO_SENSE")
	check(s.bind_ability_item(hero,"TEST_ESSENCE_ECHO_SENSE").accepted,"bind echo")
	check(s.commit_field_action(Action.skill(hero,"ECHO_SENSE",hero)).accepted,"spend MP through actual skill")
	for n in range(120):
		if s.sim.world.entities[hero].health<s.sim.world.entities[hero].max_health:break
		var w=s.sim.world;var goals:Array[Vector2i]=[]
		for enemy in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(enemy):continue
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:goals.append(w.entities[enemy].position+delta)
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		var action=Action.move_to(hero,route.path[1]) if route.get("found",false) and route.path.size()>1 else Action.hold(hero)
		var moved:Dictionary=s.commit_field_action(action)
		check(moved.accepted,"actual enemy damage")
		if not moved.accepted:break
	check(s.sim.world.entities[hero].health<s.sim.world.entities[hero].max_health,"injured fixture")
	var baseline:Dictionary=s.sim.snapshot()
	for id in RECOVERY_IDS:
		s.sim=Simulator.from_snapshot(baseline)
		check(s.sim!=null,"restore recovery baseline")
		if s.sim==null:return
		give(s,id)
		var w=s.sim.world;var hp:int=w.entities[hero].health;var mp:int=w.party_encounter.member(hero).energy
		var d:Dictionary=Catalog.definition(id);var start:int=w.events.size()
		var expected:int=mini(int(d.effect_power),w.entities[hero].max_health-hp if d.effect_kind=="HEAL" else 12-mp)
		var result:Dictionary=s.use_inventory_item("TEST_"+id)
		check(result.accepted,"actual recovery "+id+" "+str(result.get("reason")))
		if not result.accepted:continue
		check(expected>0 and int(result.get("healed_amount" if d.effect_kind=="HEAL" else "energy_amount",0))==expected,"clamped effect "+id)
		var effects:Array=w.events.slice(start).filter(func(e):return e.type==("health.restored" if d.effect_kind=="HEAL" else "item.energy_restored") and e.actor_id==hero)
		check(effects.size()==1 and effects[0].magnitude==expected,"one effect event "+id)
		var error:String=w.world_state_error();check(error.is_empty(),"effect audit "+id+" "+error)
		check(Simulator.from_snapshot(s.sim.snapshot())!=null,"effect snapshot "+id)
func run():
	check(Catalog.registry_error().is_empty(),"catalog "+Catalog.registry_error())
	var seen:Dictionary={}
	for death in range(1,501):
		var rolls:=Drops.rolls_for(44,death,"goblin")
		check(rolls==Drops.rolls_for(44,death,"goblin"),"stable drops")
		for row in rolls:
			if Mystery.has(row.definition_id):seen[row.definition_id]=true
		for row in Drops.rolls_for(44,death,"goblin",Drops.PRE_MYSTERY_RULESET_ID):
			check(not Mystery.has(row.definition_id),"legacy drops unchanged")
	check(seen.size()>12,"expanded mystery supplies drop")
	var appearances:Dictionary={}
	for seed_value in range(20):
		var stub={"seed":seed_value}
		check(Mystery.appearance(stub,Mystery.IDS[0])!=Mystery.appearance(stub,Mystery.IDS[1]),"potion bijection")
		check(Mystery.appearance(stub,Mystery.IDS[2])!=Mystery.appearance(stub,Mystery.IDS[3]),"scroll bijection")
		appearances[Mystery.appearance(stub,Mystery.IDS[0])]=true
	check(appearances.size()>2,"new seed changes appearance")
	for id in RECOVERY_IDS:
		var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
		check(s.town_life_command({"action":"START"}).accepted,"start")
		check(s.depart_town().accepted,"depart")
		give(s,id)
		var row:Dictionary=s.protagonist_inventory().backpack_rows.filter(func(r):return r.definition_id==id)[0]
		check(not row.identified and row.use_kind=="UNIDENTIFIED" and row.heal_amount==0 and row.energy_amount==0,"hidden effect "+id)
		var icon:String=row.visual_icon_key
		var result:Dictionary=s.use_inventory_item("TEST_"+id)
		check(result.accepted,"unknown usable at full resource "+id+" "+str(result.get("reason")))
		if not result.accepted:continue
		check(Mystery.known(s.sim.world,id),"identified "+id)
		row=s.protagonist_inventory().backpack_rows.filter(func(r):return r.definition_id==id)[0]
		check(row.identified and row.visual_icon_key==icon and row.quantity==1,"remaining copy identified; appearance stable")
		var before:Dictionary=s.sim.snapshot()
		result=s.use_inventory_item("TEST_"+id)
		check(not result.accepted and result.reason=="resource_full","known full resource protected")
		check(before==s.sim.snapshot(),"rejected use unchanged")
		var error:String=s.sim.world.world_state_error();check(error.is_empty(),"world audit "+error)
		var restored=Simulator.from_snapshot(s.sim.snapshot())
		check(restored!=null,"restore identified state")
		if restored!=null:check(Mystery.known(restored.world,id),"knowledge survives snapshot")
	for key in ["ARMOR_PADDED","ARMOR_LEATHER","ARMOR_CLOTH_ROBE","ARMOR_CHAIN","ARMOR_PLATE","FOOD_RATION","MAGIC_STONE","ESSENCE_FIRE_GLAND","MYSTERY_SCROLL_0","MYSTERY_SCROLL_1","MYSTERY_POTION_0","MYSTERY_POTION_1"]:
		check(Assets.item(key)!=null,"icon "+key)
	check(Assets.item("MYSTERY_SCROLL_0")!=Assets.item("MYSTERY_SCROLL_1"),"distinct scroll glyphs")
	recovery_tests()
	print("MYSTERY CONSUMABLES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
