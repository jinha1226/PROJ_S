extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Action=preload("res://sim/party_action_command.gd")
const AbilityPanel=preload("res://playtest/ability_loadout_mockup.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(value:bool,label:String):
	if not value:failures.append(label);printerr("FAIL ",label)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"town")
	check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"quest")
	check(s.guild_tutorial_command({"action":"SUPPORT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"essence")
	var hero:int=s.sim.world.party_control_actor_id()
	var rows:Array=s.ability_binding_item_rows(hero)
	check(not rows.is_empty(),"real inventory essence")
	if rows.is_empty():quit(1);return
	check(s.bind_ability_item(hero,str(rows[0].instance_id)).accepted,"bind")
	check(s.set_ability_mode(hero,"FIREBOLT","PASSIVE").accepted,"passive mode")
	check("FIREBOLT" not in s.sim.world.party_encounter.member(hero).active_skill_ids(),"passive removes cast button")
	check(not s.set_ability_mode(hero,"FIREBOLT","BOTH").accepted,"exclusive modes")
	check(not s.set_ability_mode(hero,"BLOOD_SIPHON","PASSIVE").accepted,"unbound rejection")
	var panel=AbilityPanel.new();root.add_child(panel)
	panel.mode_action=func(id,mode):return s.set_ability_mode(hero,id,mode)
	panel.configure(hero,s.ability_binding_rows(hero),s.ability_binding_item_rows(hero))
	check(panel.find_child("AbilityModeACTIVE",true,false)!=null,"mode UI exists")
	panel.find_child("AbilityModeACTIVE",true,false).pressed.emit()
	check("FIREBOLT" in s.sim.world.party_encounter.member(hero).active_skill_ids(),"UI switches active")
	panel.find_child("AbilityModePASSIVE",true,false).pressed.emit()
	check("FIREBOLT" not in s.sim.world.party_encounter.member(hero).active_skill_ids(),"UI switches passive")
	panel.queue_free();await process_frame
	var restored=Session.new();var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"mode replay "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"mode snapshot equality")
	check(s.depart_town().accepted,"depart")
	check(not s.set_ability_mode(hero,"FIREBOLT","ACTIVE").accepted,"cannot swap modes during field combat")
	var triggered:=false
	for turn in range(100):
		var command=null;var best:Dictionary={}
		for enemy_id in s.sim.world.party_encounter.enemy_ids:
			if not s.sim.world.is_autonomous_target(enemy_id):continue
			if s.FieldTurns.assess(s.sim,Action.melee(hero,enemy_id)).accepted:
				command=Action.melee(hero,enemy_id);break
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var path:Dictionary=s.sim.pathfinder.find_path(hero,s.sim.world.entities[enemy_id].position+direction)
				if path.get("found",false) and path.path.size()>1 and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if command==null and not best.is_empty():command=Action.move_to(hero,best.path[1])
		if command==null:break
		var before:int=s.sim.world.events.size()
		var result:Dictionary=s.commit_field_action(command)
		if not result.accepted:print("field stopped ",result);break
		for event in s.sim.world.events.slice(before):
			if event.type=="ability.passive_triggered":
				triggered=true
				check(result.get("visual_effects",[]).any(func(v):return v.get("kind")=="ENV_IGNITE" or v.get("effect_kind")=="ENV_IGNITE"),"visible passive flame")
				var children:Array=s.sim.world.events.slice(before).filter(func(e):return e.type=="combat.fire_damage" and e.cause_id==event.id)
				check(children.size()==1,"one real fire damage child")
		if triggered:break
	check(triggered,"natural melee triggers passive")
	var audit:String=s.sim.world.world_state_error();check(audit.is_empty(),"full state audit "+audit)
	loaded=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"combat replay "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"combat replay equality")
	var legacy:Dictionary=JSON.parse_string(s.save_session_json())
	for body_row in legacy.snapshot.body_states:body_row.current_blood=0
	loaded=restored.load_session_json(JSON.stringify(legacy))
	check(loaded.accepted,"retired blood field does not block legacy journal replay")
	print("MONSTER DUAL MODE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
