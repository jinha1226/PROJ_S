extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Corpses=preload("res://playtest/monster_corpse_visuals.gd")
const Effects=preload("res://sim/consumable_effects.gd")
const Parts=preload("res://sim/part_ingestion_rules.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
const Growth=preload("res://sim/growth_build_state.gd")
const Action=preload("res://sim/party_action_command.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func grant(s,id:int,definition:String,instance:String):
	var bag=s.sim.world.inventory_of(id);var items:Array=bag.backpack.duplicate()
	items.append(Item.new(instance,definition,1))
	s.sim.world.item_state.inventory_rows[id]=Inventory.new(items,bag.equipped)
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var w=s.sim.world;var party=w.party_encounter;var hero:int=party.protagonist_id
	var ally:=-1
	for id in party.active_party_member_ids:
		if id!=hero:ally=id;break
	check(ally>0,"companion fixture")
	if ally<0:quit(1);return
	party.protagonist_growth.xp_total=Growth.RegistryScript.xp_floor_for_level(3)
	party.member(ally).growth_xp=Growth.RegistryScript.xp_floor_for_level(2)
	check(s.mastery_status(hero).points==2 and s.mastery_status(ally).points==1,"independent budgets")
	check(s.select_field_actor(ally).accepted,"select companion for default mastery target")
	check(s.mastery_status().points==1,"default budget follows selected companion")
	check(s.spend_mastery_point("MELEE").accepted,"default investment spends selected companion point")
	check(s.mastery_status(hero).points==2 and s.mastery_status(hero).ranks.MELEE==0,"companion spending leaves hero untouched")
	check(not s.spend_mastery_point("MAGIC",ally).accepted,"cannot borrow hero points")
	check(s.spend_mastery_point("DEFENSE",hero).accepted,"hero spends own point")
	check(s.mastery_status(ally).ranks.DEFENSE==0,"hero spending leaves companion untouched")
	check(w.world_state_error().is_empty(),"independent mastery world audit: "+w.world_state_error())
	var restored=Session.SimulatorScript.from_snapshot(s.sim.snapshot())
	check(restored!=null,"independent mastery snapshot")
	if restored!=null:check(restored.world.party_encounter.member(ally).mastery_ranks.MELEE==1 and restored.world.party_encounter.protagonist_growth.mastery_ranks.DEFENSE==1,"snapshot preserves distinct allocations")
	var panel=preload("res://playtest/mastery_panel.gd").new();root.add_child(panel)
	panel.refresh(s,hero);panel.preview("MAGIC");panel.refresh(s,ally)
	check(panel.pending.is_empty() and not panel.confirm.visible,"character switch cancels previous investment")
	panel.commit();check(s.mastery_status(hero).points==1,"stale confirmation cannot spend hero point")
	panel.queue_free()
	grant(s,hero,"ESSENCE_FIRE_BOLT","PART_TEST")
	var unknown:Dictionary=s._item_presentation_row(w.inventory_of(hero).item("PART_TEST"),"",false,ally)
	check(unknown.label=="???" and not unknown.ability_preview.has("active"),"before eating name and effects hidden")
	check(s.protagonist_inventory(ally).backpack_rows.any(func(r):return r.instance_id=="PART_TEST"),"companion sees shared bag")
	var ate:Dictionary=s.use_party_item("PART_TEST",ally)
	check(ate.accepted,"shared bag feeds selected companion: "+str(ate.get("reason")))
	check(s.part_effect_preview(ally,"FIREBOLT").identified and not s.part_effect_preview(hero,"FIREBOLT").identified,"knowledge belongs to consumer")
	check(Effects.status(w,ally,"BURN")!=null and Effects.status(w,hero,"BURN")==null,"only consumer burns")
	check(ate.has("ability_preview") and not str(ate.ability_preview.get("passive","")).is_empty() and not str(ate.ability_preview.get("active","")).is_empty(),"acquisition reports passive and active")
	check(w.world_state_error().is_empty(),"part world audit: "+w.world_state_error())
	var burned=Session.SimulatorScript.from_snapshot(s.sim.snapshot())
	check(burned!=null and Effects.status(burned.world,ally,"BURN")!=null,"save preserves remaining burn")
	# Canonical field time exercises burn damage and expiry, including a load mid-effect.
	var field=Session.new(44,1,Session.DUO_SCENARIO_ID,"human",true)
	check(field.start_procedural_run_with_species("human",15,13).accepted,"field fixture")
	var fw=field.sim.world;var fid:int=fw.party_control_actor_id()
	grant(field,fid,"ESSENCE_FIRE_BOLT","BURN_TEST")
	check(field.bind_ability_item(fid,"BURN_TEST").accepted,"field fire gland")
	for i in range(4):
		var turn:Dictionary=field.commit_field_action(Action.hold(fid))
		check(turn.accepted,"burn turn accepted: "+str(turn.get("reason")))
	check(fw.events.any(func(e):return e.type=="consumable.pulse" and e.data.effect=="BURN"),"burn deals real periodic damage")
	check(Effects.status(fw,fid,"BURN")==null,"burn expires after 300 time")
	check(fw.world_state_error().is_empty(),"burn damage audit: "+fw.world_state_error())
	var binding_tests=preload("res://tests/test_ability_binding.gd").new()
	for method in binding_tests.get_method_list():
		if str(method.name).begins_with("test_"):binding_tests.call(method.name)
	for error in binding_tests.errors:check(false,"binding regression: "+error)
	legacy_and_new_replay()
	corpse_after_real_kill()
	print("CORPSE PARTS GROWTH: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func legacy_and_new_replay():
	for enabled in [false,true]:
		var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
		check(s.town_life_command({"action":"START"}).accepted,"replay town")
		check(s.guild_tutorial_command({"action":"ACCEPT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"replay quest")
		check(s.guild_tutorial_command({"action":"SUPPORT","quest_id":"GUILD_TUTORIAL_BIND"}).accepted,"replay part")
		var id:int=s.sim.world.party_control_actor_id();var rows:Array=s.ability_binding_item_rows(id)
		if rows.is_empty():check(false,"replay part supplied");continue
		s._part_ingestion_enabled=enabled
		check(s.use_party_item(rows[0].instance_id,id).accepted,"replay eat")
		var wire:Dictionary=JSON.parse_string(s.save_session_json())
		if not enabled:wire.journal[-1].erase("part_ingestion")
		var loaded=Session.new();var result:Dictionary=loaded.load_session_json(JSON.stringify(wire))
		check(result.accepted,"legacy/new party-use replay: "+str(result.get("reason")))
		if result.accepted:check(loaded.sim.snapshot()==s.sim.snapshot(),"legacy/new replay exact snapshot")

func corpse_after_real_kill():
	var s=Session.new(44,20260828,Session.SOLO_FIXTURE_SCENARIO_ID)
	var w=s.sim.world;var hero:int=w.party_encounter.protagonist_id;var enemy:int=w.party_encounter.enemy_ids[0]
	for i in range(16):
		if s.party_status().safe_phase!="GROUPED":break
		var delta:Vector2i=w.entities[enemy].position-w.entities[hero].position
		if not s.commit_exploration(Command.move_to(hero,w.entities[hero].position+Vector2i(signi(delta.x),signi(delta.y)))).accepted:break
	if s.party_status().safe_phase=="CONTACT":s.enter_solo_combat()
	for i in range(40):
		if w.combatant_states[enemy].life_state=="DEAD":break
		var delta:Vector2i=w.entities[enemy].position-w.entities[hero].position
		var result:Dictionary=s.commit_direct_solo_action(hero,"MELEE",[],enemy) if maxi(absi(delta.x),absi(delta.y))<=1 else s.commit_direct_solo_action(hero,"MOVE",[w.entities[hero].position.x+signi(delta.x),w.entities[hero].position.y+signi(delta.y)])
		if not result.accepted:break
	check(w.combatant_states[enemy].life_state=="DEAD","real kill corpse fixture")
	var position:Vector2i=w.entities[enemy].position;var key:="%d:%d"%[position.x,position.y]
	var visible:={key:true};var terrain:String=w.tile_at(position).terrain
	var rows:=Corpses.project(w,[enemy],visible)
	check(rows.has(key),"dead monster projects at canonical death location")
	if not rows.has(key):return
	var observation:Dictionary=s.observe_party_world()
	var cell:Dictionary={}
	for row in observation.cells:
		if row.position==[position.x,position.y]:cell=row;break
	check(not cell.get("corpses",[]).is_empty(),"real observation includes fallen body")
	var grid=preload("res://playtest/party_grid_view.gd").new();root.add_child(grid)
	grid.set_observation(observation)
	check(not grid._cells.get(key,{}).get("corpses",[]).is_empty(),"grid retains corpse drawing payload")
	if not cell.get("ground_items",[]).is_empty():check(grid.ground_item_draw_spec(position).occupied_corner,"loot goes beside body")
	grid.queue_free()
	check(rows[key][0].stage=="BODY" and rows[key][0].species_id==w.entities[enemy].species_id,"corpse retains species identity")
	check(Corpses.project(w,[enemy],{}).is_empty() and Corpses.project(w,[],visible).is_empty(),"no hidden or previous-floor corpse leak")
	var time:int=w.world_time;w.world_time+=Corpses.BONES_AFTER
	check(Corpses.project(w,[enemy],visible)[key][0].stage=="BONES","30 turns leaves bones")
	check(w.tile_at(position).terrain==terrain,"corpse aging never mutates terrain")
	w.world_time=time
