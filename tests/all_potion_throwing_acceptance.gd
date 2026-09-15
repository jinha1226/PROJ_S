extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Utility=preload("res://playtest/consumable_utility_service.gd")
const Effects=preload("res://sim/consumable_effects.gd")
const Item=preload("res://sim/item_instance.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Action=preload("res://sim/party_action_command.gd")

const POTIONS=["POTION_HEALING_MINOR","POTION_HEALING","POTION_HEALING_GREATER","POTION_UNSPECIFIED",
	"POTION_MYSTERY_HEAL","POTION_MYSTERY_MANA","POTION_MYSTERY_HASTE","POTION_MYSTERY_ARMOR",
	"POTION_MYSTERY_REGEN","POTION_MYSTERY_CLEANSE","POTION_MYSTERY_POISON","POTION_MYSTERY_SLOW","POTION_MYSTERY_WEAK"]

var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func give(s,definition_id:String,instance_id:String)->void:
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var inv=w.inventory_of(hero)
	var items:Array=inv.backpack.filter(func(existing):return existing!=null)
	while items.size()>=Inventory.BACKPACK_CAPACITY:items.pop_back()
	items.append(Item.new(instance_id,definition_id,1 if definition_id.begins_with("ESSENCE_") else 2))
	w.item_state.inventory_rows[hero]=Inventory.new(items,inv.equipped)
func run()->void:
	for definition_id in POTIONS:
		var option_session=Session.new(44,20260828,Session.REGRESSION_SCENARIO_ID)
		var option_hero:int=option_session.sim.world.party_control_actor_id()
		var instance_id:String="THROW_OPTIONS_"+str(definition_id)
		give(option_session,str(definition_id),instance_id)
		var option_rows:Array=Utility.options(option_session,instance_id,option_hero)
		check(not option_rows.is_empty() and option_rows[0].selection=={"target_id":option_hero},"drink option "+str(definition_id))
	# A harmful potion can be thrown at an ally; only the selected target receives its original effect.
	var s=Session.new(44,20260828,Session.REGRESSION_SCENARIO_ID)
	var w=s.sim.world;var party=w.party_encounter;var hero:int=w.party_control_actor_id()
	var companion:int=party.party_member_ids[1]
	if companion not in party.active_party_member_ids:party.active_party_member_ids.append(companion)
	party.member(companion).presence="GROUPED"
	var weak_id:="THROW_WEAK"
	give(s,"POTION_MYSTERY_WEAK",weak_id)
	var options:Array=Utility.options(s,weak_id,hero)
	var target_option:Dictionary={}
	for row in options:
		if int(row.selection.get("target_id",-1))==companion:target_option=row;break
	check(not target_option.is_empty() and str(target_option.label).begins_with("투척"),"visible ally is throwable target")
	if not target_option.is_empty():
		var quantity:int=w.inventory_of(hero).item(weak_id).quantity
		var used:Dictionary=s.use_party_item(weak_id,hero,target_option.selection)
		check(used.get("accepted",false),"throw weak potion "+str(used.get("reason","")))
		w=s.sim.world
		check(Effects.status(w,companion,"WEAK")!=null,"thrown potion affects selected target")
		check(Effects.status(w,hero,"WEAK")==null,"thrower does not receive target effect")
		var remaining=w.inventory_of(hero).item(weak_id)
		check(remaining!=null and remaining.quantity==quantity-1,"throw consumes exactly one potion")
		check(w.world_state_error().is_empty(),"throw history validates "+w.world_state_error())
		check(Session.SimulatorScript.from_snapshot(s.sim.snapshot())!=null,"throw survives snapshot restore")
	# Damage a real enemy through the canonical field action path, then heal that enemy by throwing a normal potion.
	s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.town_life_command({"action":"START"});s.depart_town()
	w=s.sim.world;hero=w.party_control_actor_id()
	var heal_target:=-1
	for turn in range(80):
		for enemy_id in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(enemy_id):continue
			if s.FieldTurns.assess(s.sim,Action.melee(hero,enemy_id)).accepted:heal_target=enemy_id;break
		if heal_target>0:break
		var goals:Array[Vector2i]=[]
		for enemy_id in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(enemy_id):continue
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:goals.append(w.entities[enemy_id].position+delta)
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		if not route.get("found",false) or route.path.size()<2:break
		if not s.commit_field_action(Action.move_to(hero,route.path[1])).accepted:break
		w=s.sim.world
	check(heal_target>0,"reachable enemy for healing throw")
	if heal_target>0:
		var struck:Dictionary=s.commit_field_action(Action.melee(hero,heal_target));w=s.sim.world
		check(struck.get("accepted",false) and w.is_autonomous_target(heal_target),"enemy survives canonical injury")
		if w.is_autonomous_target(heal_target):
			var hp_before:int=w.entities[heal_target].health
			var heal_id:="THROW_NORMAL_HEAL"
			give(s,"POTION_HEALING_GREATER",heal_id)
			var healed:Dictionary=s.use_party_item(heal_id,hero,{"target_id":heal_target})
			w=s.sim.world
			check(healed.get("accepted",false),"throw normal healing potion "+str(healed.get("reason","")))
			check(w.entities[heal_target].health>hp_before,"normal healing potion heals hit target")
			check(w.world_state_error().is_empty(),"healing throw history validates "+w.world_state_error())
	# Spend real MP, then route a mana potion through the same targeted activation event.
	s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true);w=s.sim.world;hero=w.party_control_actor_id()
	give(s,"ESSENCE_ECHO_SENSE","TEST_ESSENCE_ECHO_SENSE")
	check(s.bind_ability_item(hero,"TEST_ESSENCE_ECHO_SENSE").accepted,"bind skill for mana fixture")
	check(s.commit_field_action(Action.skill(hero,"ECHO_SENSE",hero)).accepted,"spend mana through real skill")
	w=s.sim.world;var mana_before:int=w.party_encounter.member(hero).energy
	give(s,"POTION_MYSTERY_MANA","TEST_THROW_MANA")
	var mana_result:Dictionary=s.use_party_item("TEST_THROW_MANA",hero,{"target_id":hero})
	w=s.sim.world
	check(mana_result.get("accepted",false),"targeted mana potion "+str(mana_result.get("reason","")))
	check(w.party_encounter.member(hero).energy>mana_before,"mana potion restores selected target MP")
	check(w.world_state_error().is_empty(),"mana throw history validates "+w.world_state_error())
	print("ALL POTION THROWING: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
