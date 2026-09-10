extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const Hooks=preload("res://sim/guild_tutorial_events.gd")
var errors:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"injury town start")
	for id in ["GUILD_TUTORIAL_INJURY","GUILD_TUTORIAL_TREAT"]:
		check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":id}).accepted,"injury acceptance")
	check(s.depart_town().accepted,"injury departure")
	var hero:int=s.sim.world.party_control_actor_id()
	for i in range(120):
		var w=s.sim.world
		if s.guild_tutorial_progress().quests[8].completed or w.entities[hero].health<=0:break
		var goals:Array[Vector2i]=[]
		for id in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(id):continue
			for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(w.entities[id].position+d)
		var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
		var action=Action.move_to(hero,route.path[1]) if route.get("found",false) and route.path.size()>1 else Action.hold(hero)
		var result:Dictionary=s.commit_field_action(action)
		if not result.accepted:check(false,"injury turn: "+str(result.get("reason","")));break
	check(s.guild_tutorial_progress().quests[8].completed,"actual enemy attack produces limb tutorial")
	check(not Hooks.injured_parts(s.sim.world.body_states[hero]).is_empty(),"real limb damage exists")
	check(s.sim.world.world_state_error().is_empty(),"injury world audit")
	var loaded=Session.new();var result:Dictionary=loaded.load_session_json(s.save_session_json())
	check(result.accepted,"injury journal replay: "+str(result.get("reason","")))
	if result.accepted:check(loaded.sim.snapshot()==s.sim.snapshot(),"injury snapshot exact")
	# Treatment adapter fixture: tissue is injured directly, as in existing clinic
	# tests; this tests real clinic restoration, not a full injured retreat route.
	var clinic=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(clinic.town_life_command({"action":"START"}).accepted,"clinic town")
	check(clinic.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_TREAT"}).accepted,"clinic accept")
	var body=clinic.sim.world.body_states[hero]
	for part in body.parts:
		if part.part_id=="LEFT_ARM":part.layers[0].integrity=600
	body.revision+=1
	clinic.sim.world.emit_event("guild.tutorial_limb_injured",hero,hero,clinic.sim.world.entities[hero].position,1,-1,{"part_id":"LEFT_ARM","condition":"FUNCTIONAL"})
	var treatment:Dictionary=clinic.treat_town_clinic(hero)
	check(treatment.accepted,"clinic treats damaged limb: "+str(treatment.get("reason","")))
	check(clinic.guild_tutorial_progress().quests[9].completed,"successful clinic marks limb quest")
	check(Hooks.injured_parts(body).is_empty(),"clinic tissue restored")
	print("GUILD LIMBS: ",errors);quit(0 if errors.is_empty() else 1)
