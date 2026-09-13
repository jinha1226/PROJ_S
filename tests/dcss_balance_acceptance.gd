extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Weapons=preload("res://sim/weapon_registry.gd")
const Attack=preload("res://sim/weapon_attack_rules.gd")
const Profiles=preload("res://sim/combat_profile_registry.gd")
const Enemies=preload("res://sim/enemy_perception_registry.gd")
const Items=preload("res://sim/item_registry.gd")
const Species=preload("res://sim/species_catalog_registry.gd")
const Simulator=preload("res://sim/simulator.gd")
const DcssEnemies=preload("res://sim/dcss_enemy_registry.gd")
const Finds=preload("res://sim/dcss_equipment_finds.gd")
const WorldItems=preload("res://sim/world_item_operations.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func round_trip(s,label:String):
	var encoded:String=s.save_session_json()
	check(not encoded.is_empty(),label+" serializes")
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(encoded)
	check(loaded.get("accepted",false),label+" replay "+str(loaded.get("reason","")))
	if loaded.get("accepted",false):check(s.sim.snapshot()==restored.sim.snapshot(),label+" exact snapshot")
func expanded_registry():
	check(DcssEnemies.DEFINITIONS.size()==6,"six early-game species registered")
	var seen:Dictionary={}
	for seed in range(80):
		for floor in [1,2]:
			for group in range(1,8):
				var sid:=DcssEnemies.spawn_species(floor,seed,group,0)
				check(sid==DcssEnemies.spawn_species(floor,seed,group,0),"deterministic spawn")
				seen[sid]=true
				if sid.begins_with("dcss_"):check(int(DcssEnemies.DEFINITIONS[sid].hd)<=(1 if floor==1 else 2),"no deep monster in early floor")
	check(seen.size()==8,"eight low-HD species actually eligible across two floors")
	check(Finds.candidates(1).size()>=5 and Finds.candidates(2).size()>Finds.candidates(1).size(),"expanded depth-filtered weapon finds")
	# All added monsters must create real entity/body/inventory/profile authority.
	var fixture=Simulator.create(20,20,44)
	for tile in fixture.world.tiles:tile.terrain="stone_floor"
	var cursor:=0
	for row in DcssEnemies.DEFINITIONS.values():
		var e=fixture.world.add_entity("melee_enemy",row.display_name,Vector2i(2+cursor%8,2+cursor/8),row.max_health,["party_enemy"],row.species_id,"enemy",row.loadout_id)
		check(e!=null,"spawn "+row.species_id)
		if e==null:continue
		cursor+=1
		var profile:Dictionary=Profiles.profile(fixture.world.combatant_states[e.id].combat_profile_id)
		check(profile==row.combat_profile,"species-specific combat "+row.species_id)
		var wid:=WorldItems.equipped_weapon_id(fixture.world,e.id)
		var spec:=Attack.build_attack_spec(wid,0,int(profile.power),int(profile.accuracy_milli),150,2,{"STR":5,"DEX":5,"INT":5})
		check(not spec.is_empty() and int(spec.raw_damage)>0,"real basic attack "+row.species_id)
		if row.loadout_id.is_empty():check(int(spec.attack_time)==100,"natural attack period "+row.species_id)
	var wearer=fixture.world.add_entity("hero","장비 검증",Vector2i(1,1),120,[],"human","party")
	var equipped_count:=0
	for wid in Weapons.ids():
		if not wid.begins_with("DCSS_") or wid.begins_with("DCSS_NATURAL_"):continue
		var granted:=WorldItems.commit_grant(fixture.world,wearer.id,"WEAPON_"+wid,1,wearer.position,"BALANCE_UNIT")
		check(granted.get("accepted",false),"real inventory grant "+wid)
		if not granted.get("accepted",false):continue
		var instance:String=granted.instance_id
		var preview:=WorldItems.preview_equip(fixture.world,wearer.id,instance,"MAIN_HAND")
		if preview.get("accepted",false):
			var equipped:=WorldItems.commit_equip(fixture.world,wearer.id,instance,"MAIN_HAND",wearer.position)
			check(equipped.get("accepted",false) and WorldItems.equipped_weapon_id(fixture.world,wearer.id)==wid,"real equip authority "+wid)
			equipped_count+=1
			var unequipped:=WorldItems.commit_unequip(fixture.world,wearer.id,"MAIN_HAND",wearer.position)
			check(unequipped.get("accepted",false),"unequip before dropping "+wid)
		else:check(preview.get("reason")=="item_requirements_not_met","heavy weapon has real stat restriction "+wid+" "+str(preview.get("reason")))
		var dropped:=WorldItems.commit_drop(fixture.world,wearer.id,instance,wearer.position)
		check(dropped.get("accepted",false),"new weapon drops to ground "+wid)
	check(equipped_count>=4,"starter-compatible added weapons actually equip")
	var audit:String=fixture.world.world_state_error();check(audit.is_empty(),"all monster fixture audit "+audit)
	if audit.is_empty():
		var restored=Simulator.from_snapshot(fixture.snapshot())
		check(restored!=null and restored.snapshot()==fixture.snapshot(),"all new monster snapshots decode exactly")

func run():
	expanded_registry()
	var rows:Array=[]
	# Check the intended neutral combat outputs, not just edited JSON literals.
	for row in [["SHORT_SWORD",25,100],["THRUSTING_SWORD",35,120],["HAND_AXE",35,130],["MACE",40,140],["SPEAR",30,110],["BOW",40,140],["CROSSBOW",80,190]]:
		var spec:Dictionary=Attack.build_attack_spec(row[0],0,24,300,120,0,{"STR":5,"DEX":5,"INT":5})
		check(not spec.is_empty(),str(row[0])+" spec valid")
		if spec.is_empty():continue
		check(int(spec.raw_damage)==row[1],str(row[0])+" neutral raw damage")
		check(int(spec.attack_time)+int(spec.reload_time)==row[2],str(row[0])+" total attack and reload delay")
		check(int(spec.hit_chance_milli)<950,str(row[0])+" no permanent accuracy cap")
		rows.append({"weapon":row[0],"raw_damage":spec.raw_damage,"cycle_time":int(spec.attack_time)+int(spec.reload_time),"hit_chance":spec.hit_chance_milli})
	check(Enemies.profile("goblin").max_health==40 and Enemies.profile("kobold").max_health==35,"DCSS mean HP ratios")
	check(Profiles.profile("party-goblin-v1").armor_flat==0 and Profiles.profile("party-kobold-v1").armor_flat==4,"natural armor distinction")
	check(Species.base_stats("elf").INT>Species.base_stats("human").INT,"elf intelligence specialization")
	check(Items.definition("ARMOR_PLATE").bonuses.armor_flat>Items.definition("ARMOR_LEATHER").bonuses.armor_flat,"heavy armor protects more")
	check(Items.definition("ARMOR_PLATE").bonuses.dodge_milli<Items.definition("ARMOR_LEATHER").bonuses.dodge_milli,"heavy armor has evasion cost")
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.sim!=null,"real session created")
	if s.sim==null:quit(1);return
	var world=s.sim.world;var hero:int=world.party_control_actor_id()
	check(world.item_state.ground_items.rows.any(func(r):return str(r.item.definition_id).begins_with("WEAPON_DCSS_")),"expanded weapons exist on real floor")
	check(world.party_encounter.enemy_ids.any(func(id):return str(world.entities[id].species_id).begins_with("dcss_")),"expanded monsters exist on real floor")
	for enemy_id in world.party_encounter.enemy_ids:
		var e=world.entities[enemy_id]
		check(e.max_health==Enemies.profile(e.species_id).max_health,"actual spawn HP "+str(e.id))
		if e.species_id=="goblin":check(world.item_state.inventory(enemy_id).equipped_item("ARMOR")==null,"goblin no padded armor")
	round_trip(s,"new balance")
	var attacked:=false
	for turn in range(50):
		var command=null;var best:Dictionary={}
		hero=s.sim.world.party_control_actor_id()
		for enemy_id in s.sim.world.party_encounter.enemy_ids:
			if not s.sim.world.is_autonomous_target(enemy_id):continue
			if s.FieldTurns.assess(s.sim,Action.melee(hero,enemy_id)).get("accepted",false):command=Action.melee(hero,enemy_id);break
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var path:Dictionary=s.sim.pathfinder.find_path(hero,s.sim.world.entities[enemy_id].position+direction)
				if path.get("found",false) and path.path.size()>1 and (best.is_empty() or path.path.size()<best.path.size()):best=path
		if command==null and not best.is_empty():command=Action.move_to(hero,best.path[1])
		if command==null:break
		var result:Dictionary=s.commit_field_action(command)
		check(result.get("accepted",false),"real field action "+str(result.get("reason","")))
		if not result.get("accepted",false):break
		if command.type=="MELEE":attacked=true;break
	check(attacked,"actual melee reachable and accepted")
	check(s.sim.world.world_state_error().is_empty(),"full world audit")
	round_trip(s,"combat balance")
	var previous:Dictionary=JSON.parse_string(s.save_session_json())
	for entity in previous.snapshot.entities:entity.tags.erase(Session.BALANCE_TAG)
	var before:Dictionary=s.sim.snapshot()
	var rejected:Dictionary=s.load_session_json(JSON.stringify(previous))
	check(not rejected.get("accepted",false) and rejected.get("reason")=="balance_version_changed","old balance rejected explicitly")
	check(s.sim.snapshot()==before,"rejected old save preserves current session")
	print("DCSS_BALANCE_SAMPLES ",JSON.stringify(rows))
	print("DCSS_BALANCE_ACCEPTANCE ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
