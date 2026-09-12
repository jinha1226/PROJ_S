extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Weapon=preload("res://sim/weapon_attack_rules.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(session.town_life_command({"action":"START"}).accepted,"start town")
	check(session.depart_town().accepted,"depart to first floor")
	var world=session.sim.world;var hero:int=world.party_control_actor_id()
	var found:=false
	for row in session.ground_items_at_protagonist():
		if str(row.instance_id)=="GROUND_START_FIREBOLT":found=true
	check(found,"firebolt essence is underfoot on floor one")
	if not found:quit(1);return
	var attack_before:int=session._member_combat_stats(hero).attack_power
	var known_before:bool="FIREBOLT" in world.party_encounter.member(hero).active_skill_ids()
	check(not known_before,"no firebolt before binding")
	check(session.pickup_ground_item("GROUND_START_FIREBOLT").accepted,"normal pickup")
	check(session.bind_ability_item(hero,"GROUND_START_FIREBOLT").accepted,"normal binding")
	check("FIREBOLT" in world.party_encounter.member(hero).active_skill_ids(),"binding adds active skill")
	check(session._member_combat_stats(hero).attack_power==attack_before,"active firebolt does not pretend to buff normal attacks")
	check(world.item_owner("GROUND_START_FIREBOLT").kind=="NONE","binding consumes essence")
	check(session.equip_inventory_item("START_HAND_AXE_001","MAIN_HAND").accepted,"equip comparison axe through inventory")
	check(session._member_combat_stats(hero).attack_power!=attack_before,"actual status attack changes with weapon")
	var saved:String=session.save_session_json()
	var restored=Session.new()
	check(restored.load_session_json(saved).accepted and restored.sim.snapshot()==session.sim.snapshot(),"drop pickup and binding replay exactly")
	# Read-only isolated comparisons: no XP or ranks are injected into the run.
	var stats:={"STR":5,"DEX":5,"INT":5}
	var dagger:Dictionary=Weapon.build_attack_spec("SHORT_SWORD",0,20,0,0,0,stats,true)
	var sword:Dictionary=Weapon.build_attack_spec("HAND_AXE",0,20,0,0,0,stats,true)
	var trained:Dictionary=Weapon.build_attack_spec("HAND_AXE",5,20,0,0,0,stats,true)
	check(not dagger.is_empty() and not sword.is_empty() and not trained.is_empty(),"comparison weapons resolve")
	if not dagger.is_empty() and not sword.is_empty() and not trained.is_empty():
		check(dagger.raw_damage!=sword.raw_damage,"weapon type affects raw attack")
		check(trained.raw_damage>sword.raw_damage,"melee mastery affects raw attack")
		print("ATTACK_COMPARE dagger=",dagger.raw_damage," axe=",sword.raw_damage," axe_rank5=",trained.raw_damage)
	var growth=preload("res://sim/growth_build_state.gd").new("human")
	var base:int=growth.mastery_scale("MAGIC",32)
	growth.mastery_ranks.MAGIC=5
	check(growth.mastery_scale("MAGIC",32)>base,"magic mastery scales firebolt base power")
	print("FIREBOLT_COMPARE rank0=",base," rank5=",growth.mastery_scale("MAGIC",32))
	print("STARTING ABILITY DROP: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
