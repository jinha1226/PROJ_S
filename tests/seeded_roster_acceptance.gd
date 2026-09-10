extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Roster=preload("res://playtest/seeded_roster.gd")
var failures:Array[String]=[]
func _init()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var signatures:Dictionary={}
	var population_signatures:Dictionary={}
	var enemy_signatures:Dictionary={}
	for seed_value in range(10):
		var companion:Dictionary=Roster.companion(44,seed_value)
		check(companion==Roster.companion(44,seed_value),"companion deterministic")
		signatures[str(companion)]=true
		var population:Array=Roster.population(44,seed_value)
		check(population==Roster.population(44,seed_value),"population deterministic")
		population_signatures[str(population)]=true
		var layout:Dictionary={"floor_index":1,"enemy_roster":[{"position":Vector2i(10,10),"species_id":"goblin"},{"position":Vector2i(11,10),"species_id":"goblin"}]}
		var shuffled:Dictionary=Roster.apply_layout(layout,44,seed_value)
		check(shuffled==Roster.apply_layout(layout,44,seed_value),"monsters deterministic")
		enemy_signatures[str(shuffled)]=true
	check(signatures.size()>1 and population_signatures.size()>1 and enemy_signatures.size()>1,"all three populations vary by seed")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var result:Dictionary=session.start_new_run_with_species("human",true)
	check(result.accepted,"v3 bootstrap succeeds: "+str(result.get("reason")))
	check(preload("res://sim/living_expedition_rules.gd").roster_randomized(session.sim.world),"new runs use roster v3")
	var expected:Dictionary=Roster.companion(44,20260828)
	check(session.sim.world.entities[2].species_id==expected.species and session.sim.world.entities[2].display_name==expected.name,"runtime companion uses seeded identity")
	check(session.sim.world.world_state_error().is_empty(),"randomized world validates")
	var town:Dictionary=session.town_life_command({"action":"START"})
	check(town.accepted,"randomized town population initializes")
	var population:Array=Roster.population(44,20260828)
	var found:=0
	for entity in session.sim.world.entities.values():
		if "guild_candidate" in entity.tags:
			for person in population:
				if entity.display_name==person.name and entity.species_id==person.species:found+=1
	check(found==population.size(),"runtime NPC species and composition use seed")
	var departed:Dictionary=session.depart_town()
	check(departed.accepted,"seeded roster departs into dungeon")
	if departed.accepted:
		var waited:Dictionary=session.commit_field_action(preload("res://sim/party_action_command.gd").hold(session.sim.world.party_control_actor_id()))
		check(waited.accepted,"randomized NPC and monster simulation step")
	var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(session.save_session_json())
	check(restored.accepted,"v3 save replay: "+str(restored.get("reason")))
	if restored.accepted:check(loaded.sim.snapshot()==session.sim.snapshot(),"v3 replay identical")
	print("SEEDED ROSTER: ","PASS" if failures.is_empty() else "FAIL"," ",failures)
	quit(0 if failures.is_empty() else 1)
