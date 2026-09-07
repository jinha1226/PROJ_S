extends SceneTree

const Session=preload("res://playtest/party_playtest_session.gd")
const Sandbox=preload("res://playtest/party_encounter_sandbox.gd")
const Talents=preload("res://sim/personal_talent_rules.gd")
const Stats=preload("res://sim/actor_stat_rules.gd")
const Defense=preload("res://sim/combat_defense_rules.gd")
const Melee=preload("res://sim/systems/melee_combat_system.gd")
var failures:Array[String]=[]

func _init()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:failures.append(message);printerr("FAIL ",message)

func run()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(session.sim!=null,"human campaign initializes")
	if session.sim==null:quit(1);return
	var world=session.sim.world
	check(world.world_state_error().is_empty(),"human traveller identity validates")
	var talent_ids:Dictionary={}
	for entity in world.entities.values():
		if entity.kind not in ["hero","companion"]:continue
		var talent:=Talents.for_entity(entity)
		check(entity.species_id=="human" and entity.max_health==120,"shared human baseline")
		check(not talent.is_empty(),"each person receives a talent")
		check(entity.tags.filter(func(t):return str(t).begins_with(Talents.TAG_PREFIX)).size()==1,
			"exactly one talent per person")
		talent_ids[entity.id]=talent.get("id","")
	for i in range(64):talent_ids[Talents.generated_id(str(i),1)]=true
	for id in Talents.IDS:check(talent_ids.has(id),"seed variation includes "+id)
	check(session.base_return().accepted,"new party reaches base")
	for row in session.recruitable_companions():
		check(row.species_id=="human","guild candidate is human")
		check(not Talents.for_entity(world.entities[row.entity_id]).is_empty(),"guild candidate talent")
	var restored=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
	var loaded:Dictionary=restored.load_session_json(session.save_session_json())
	check(loaded.accepted,"new talent save replays: "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==session.sim.snapshot(),"talent save exact")
	# Explicit pre-talent sparse-camp fixture retains its elf traveller and stats.
	var legacy=Session.new(1,2,Session.SOLO_FIXTURE_SCENARIO_ID)
	check(legacy.reset_party(44,20260828,Session.DUO_SCENARIO_ID,{},true,"human",true,false),"old sparse camp fixture")
	var old_save:=legacy.save_session_json()
	loaded=restored.load_session_json(old_save)
	check(loaded.accepted,"pre-talent save loads: "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==legacy.sim.snapshot(),"old identity and balance retained")
	# Every published effect feeds the actual shared stat/defense consumers.
	var companion=world.entities[world.party_encounter.active_party_member_ids[1]]
	var original_tags:Array[String]=companion.tags.duplicate()
	for id in Talents.IDS:
		companion.tags.assign(original_tags.filter(func(t):return not str(t).begins_with(Talents.TAG_PREFIX)))
		companion.tags.append(Talents.TAG_PREFIX+id)
		var definition:Dictionary=Talents.DEFINITIONS[id]
		var stats:=Stats.for_entity(world,companion.id)
		for key in Stats.STAT_IDS:
			check(int(stats[key])==int(Stats.for_species("human")[key])+int(definition.stats.get(key,0)),id+" stat effect")
		var melee=Melee.new(world,session.sim.damage)
		var profile=session.CombatProfileRegistryScript.profile(world.combatant_states[companion.id].combat_profile_id)
		var snapshot:Dictionary=melee._protagonist_defense_snapshot(companion.id,profile)
		check(not snapshot.is_empty(),"companion uses shared defense")
		for key in definition.combat:
			check(int(world.equipment_modifiers(companion.id).totals[key])>=int(definition.combat[key]),id+" combat effect")
		check(session.inspect_party_member(companion.id).personal_talent.id==id,"inspect talent matches authority")
	companion.tags=original_tags
	# Actual scene startup, no picker interaction or test initialization shortcut.
	root.size=Vector2i(360,640)
	var ui=Sandbox.new();root.add_child(ui)
	await process_frame;await process_frame
	check(ui.session.base_overview().phase=="TOWN","launch begins in base")
	check(not ui.species_picker_modal.visible,"species picker never remains visible")
	ui._open_member_detail(ui.session.sim.world.party_encounter.protagonist_id)
	check(ui.find_child("StatusPersonalTalent",true,false)!=null,"visible talent in status")
	ui.queue_free();await process_frame
	print("Human talents MVP: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
