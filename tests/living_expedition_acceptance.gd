extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Living=preload("res://sim/living_expedition_rules.gd")
const Explorer=preload("res://sim/systems/independent_explorer_system.gd")
const Population=preload("res://sim/town_population_rules.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
const Maps=preload("res://playtest/campaign_world_map.gd")
const FloorMap=preload("res://playtest/campaign_floor_map.gd")
const Floors=preload("res://playtest/living_floor_design.gd")
const Growth=preload("res://sim/growth_build_registry.gd")
const Command=preload("res://sim/sim_command.gd")
var failures:Array[String]=[]

class FixedProfile:
	extends RefCounted
	var values:Dictionary
	func _init(c:int,e:int)->void:values={"C":c,"E":e}
	func value(id:String)->int:return int(values.get(id,500))

func _init()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL ",message)

func run()->void:
	check(Growth.picker_species_ids()==["human","elf","dwarf","orc","beastkin"],
		"new-run picker exposes exactly five playable species")
	check(Explorer.choose(FixedProfile.new(100,100),65,3,1,0)=="FIGHT",
		"bold healthy explorer pursues a nearby enemy")
	check(Explorer.choose(FixedProfile.new(900,900),65,3,1,0)=="RETURN",
		"cautious explorer retreats at the same health and distance")
	check(Explorer.choose(FixedProfile.new(100,100),100,99,0,0)=="RETURN",
		"an explorer without supplies returns")
	for floor_index in [1,2]:
		var layout:=Floors.apply(FloorMap.generate(floor_index,44),floor_index)
		check(not layout.is_empty(),"living floor %d exists"%floor_index)
		if not layout.is_empty():
			check(Floors.connectivity_error(layout).is_empty(),
				"floor %d entry, exits, portals, supplies, visitors, landmarks connect: %s"%[
				floor_index,Floors.connectivity_error(layout)])
	var legacy=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	check(not Living.enabled(legacy.sim.world),"legacy constructor does not opt in")
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID)
	var selected:Dictionary=session.start_new_run_with_species("orc",true)
	check(selected.get("accepted",false),"orc living campaign starts: "+str(selected.get("reason")))
	if not selected.get("accepted",false):_finish();return
	var hero=session.sim.world.entities[session.sim.world.party_encounter.protagonist_id]
	check(hero.species_id=="orc" and Living.enabled(session.sim.world),
		"selected species and living version persist in canonical world")
	var growth:Dictionary=session.protagonist_growth_build()
	check(not growth.get("personal_talent",{}).is_empty() \
		and not growth.get("species_fixed_trait",{}).is_empty(),
		"personal talent coexists with fixed species trait")
	var skill_categories:Array=[]
	for row in session._member_skill_summary(hero.id).get("skills",[]):skill_categories.append(row.category)
	check("종족 특성" in skill_categories and "개인 재능" in skill_categories,
		"inspector reports both trait families")
	check(session.town_life_command({"action":"START"}).get("accepted",false),
		"new campaign enters persistent town")
	var species_seen:Dictionary={};var personality_seen:Dictionary={}
	for resident in session.town_life_overview().get("residents",[]):
		var id:=int(resident.entity_id);var entity=session.sim.world.entities.get(id)
		if entity==null:continue
		species_seen[entity.species_id]=true
		var member=session.sim.world.party_encounter.member(id)
		if member!=null and member.personality_profile!=null:
			personality_seen[JSON.stringify(member.personality_profile.to_dict())]=true
	check(species_seen.size()==5 and personality_seen.size()>5,
		"town population has persistent species and personality variety")
	var departed:=session.depart_town()
	check(departed.get("accepted",false),"town departure creates physical expedition: "+str(departed.get("reason")))
	var encoded:=session.save_session_json();var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(encoded)
	check(not encoded.is_empty() and restored.get("accepted",false),
		"living campaign save replays: "+str(restored.get("reason")))
	if restored.get("accepted",false):check(loaded.sim.snapshot()==session.sim.snapshot(),
		"living save/load replay is exact")
	if departed.get("accepted",false):_check_physical_expedition(session)
	_check_command_only_living_replay()
	_check_recruited_visitor_reward_eligibility()
	_check_player_contact_scheduler_boundary()
	check(not Living.enabled(legacy.sim.world),"living run does not mutate legacy world")
	_finish()

func _check_command_only_living_replay()->void:
	var session=Session.new(91,20260828,Session.DUO_SCENARIO_ID)
	var started:Dictionary=session.start_new_run_with_species("elf",true)
	check(started.get("accepted",false),"clean replay fixture starts")
	if not started.get("accepted",false):return
	check(session.town_life_command({"action":"START"}).get("accepted",false),
		"clean replay fixture enters town")
	check(session.depart_town().get("accepted",false),"clean replay fixture departs town")
	for ignored in range(3):
		var waited:Dictionary=session.commit_exploration(
			Command.wait(session.sim.world.party_control_actor_id()))
		check(waited.get("accepted",false),"clean living cadence command succeeds")
		if not waited.get("accepted",false):return
	var living_events:Array=session.sim.world.events.filter(func(event):return event.type in [
		"action.move","population.patrol","population.rested"] \
		and (event.type=="population.patrol" or Living.independent(
		session.sim.world,event.actor_id)))
	check(not living_events.is_empty(),"command-only run records autonomous living activity")
	var encoded:=session.save_session_json();var loaded=Session.new()
	var restored:Dictionary=loaded.load_session_json(encoded)
	check(restored.get("accepted",false) and loaded.sim.snapshot()==session.sim.snapshot(),
		"save/load remains exact after autonomous living cadence")

func _check_recruited_visitor_reward_eligibility()->void:
	# Isolated ledger seam: a former visitor keeps its identity tag after joining.
	# Reward eligibility must therefore use membership at the death event, not the tag.
	var session=Session.new(117,20260828,Session.DUO_SCENARIO_ID)
	if not session.start_new_run_with_species("dwarf",true).get("accepted",false):return
	session.town_life_command({"action":"START"});session.depart_town()
	var world=session.sim.world;var rows:Array=Population.locations(world)
	var enemies:Array=preload("res://sim/campaign_encounter_stream.gd").current_floor_enemy_ids(world)
	check(not rows.is_empty() and not enemies.is_empty(),"reward seam has visitor and enemy")
	if rows.is_empty() or enemies.is_empty():return
	var visitor_id:int=int(rows[0].entity_id);var enemy_id:int=int(enemies[0])
	var state=world.party_encounter;var hero_id:int=world.party_control_actor_id()
	var step:int=int(world.step_index)+1;world.begin_step(step)
	var recruited=world.emit_event("party.companion_recruited",hero_id,visitor_id,
		world.entities[hero_id].position,0,-1,{"operation":"RECRUIT"})
	state.active_party_member_ids.append(visitor_id);state.active_party_member_ids.sort()
	state.member(visitor_id).presence="GROUPED"
	var death=world.emit_event("entity.died",visitor_id,enemy_id,
		world.entities[enemy_id].position,0,-1,{"damage_type":"physical"})
	check(recruited!=null and death!=null and session.sim.party_coordinator._award_canonical_enemy_deaths(state),
		"recruited former visitor can reconcile a canonical enemy reward")
	check(death!=null and death.id in state.protagonist_progression.processed_source_death_event_ids,
		"persistent independent tag does not suppress recruited-member XP")
	world.finish_step()

func _check_player_contact_scheduler_boundary()->void:
	var session=Session.new(131,20260828,Session.DUO_SCENARIO_ID)
	if not session.start_new_run_with_species("beastkin",true).get("accepted",false):return
	session.town_life_command({"action":"START"});session.depart_town()
	var world=session.sim.world
	for row in Population.locations(world):
		var visitor=world.entities.get(int(row.entity_id))
		if visitor!=null and "visitor_returned" not in visitor.tags:
			visitor.tags.append("visitor_returned")
	var enemies:Array=preload("res://sim/campaign_encounter_stream.gd").current_floor_enemy_ids(world)
	if enemies.is_empty():return
	var enemy_id:int=int(enemies[0]);var enemy=world.entities[enemy_id]
	var hero=world.entities[world.party_control_actor_id()];var adjacent:=Vector2i(-1,-1)
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var candidate:Vector2i=hero.position+direction
		if world.in_bounds(candidate) and world.blocking_entity_at(candidate)==null \
				and str(world.tile_at(candidate).terrain)!="wall":adjacent=candidate;break
	if adjacent==Vector2i(-1,-1):return
	enemy.position=adjacent
	var health_before:int=int(hero.health);var event_start:int=world.events.size()
	var busy_before:int=int(world.party_encounter.enemy_busy_rows.get(enemy_id,-1))
	var step:int=int(world.step_index)+1;world.begin_step(step)
	check(Explorer.process_tick(session.sim,step),"neutral scheduler boundary evaluates")
	world.finish_step()
	var stolen:Array=world.events.slice(event_start).filter(
		func(event):return event.type=="action.melee_attack" and event.actor_id==enemy_id)
	check(stolen.is_empty() and hero.health==health_before \
			and int(world.party_encounter.enemy_busy_rows.get(enemy_id,-1))==busy_before,
		"without an adjacent neutral, established contact scheduler retains the enemy turn")

func _check_physical_expedition(session)->void:
	var world=session.sim.world;var party=world.party_encounter
	var lifecycle_id:int=-1
	var rows:Array=Population.locations(world)
	check(not rows.is_empty(),"neutral explorers arrive on floor")
	for row in rows:
		var id:=int(row.entity_id);var entity=world.entities.get(id)
		check(entity!=null and Living.present(world,id),"visitor is one physical canonical entity")
		check(id not in party.active_party_member_ids,"visitor never autojoins player faction")
		if entity==null:continue
		var position:=Vector2i(int(row.position[0]),int(row.position[1]))
		check(entity.position==position and entity in world.occupying_entities_at(position),
			"population row and occupancy share exact position")
		var detail:Dictionary=session.inspect_party_member(id)
		check(detail.get("logical_position",[])==[position.x,position.y],
			"visitor inspector reports physical coordinates")
		var before_time:int=int(world.world_time);var before_events:int=world.events.size()
		session.inspect_party_member(id);Visitors.assess(session,id)
		check(world.world_time==before_time and world.events.size()==before_events,
			"inspection and activity rendering are pure")
	var resting_id:=int(rows[0].entity_id)
	world.entities[resting_id].health=world.entities[resting_id].max_health-5
	rows[0]["state"]="REST";rows[0]["rest_until"]=0;rows[0]["fatigue"]=4
	check(Visitors._emit(world,"population.patrol",rows)!=null,
		"focused fixture records rest intent canonically")
	var cadence_start:int=world.events.size()
	var waited:Dictionary=session.commit_exploration(Command.wait(world.party_control_actor_id()))
	check(waited.get("accepted",false),"actor cadence advances living explorers: "+str(waited.get("reason")))
	var cadence_events:Array=world.events.slice(cadence_start)
	check(cadence_events.any(func(event):return event.type=="population.rested" \
		and event.actor_id==resting_id),"rest consumes supplies and records real health bookkeeping")
	check(cadence_events.any(func(event):return event.type=="action.move" \
		and Living.independent(world,event.actor_id)),"independent exploration/return uses canonical movement")
	var current_rows:Array=Population.locations(world);var needy:Dictionary={}
	for row in current_rows:
		if bool(row.get("needs_supplies",false)):needy=row;break
	check(not needy.is_empty(),"a supply-starved explorer remains aidable")
	if not needy.is_empty():_check_aid_and_return(session,current_rows,needy)
	rows=Population.locations(world)
	var present_row:Dictionary={}
	for candidate_row in rows:
		if Living.present(world,int(candidate_row.entity_id)):
			present_row=candidate_row;break
	if not present_row.is_empty():
		var visitor_id:=int(present_row.entity_id);var visitor=world.entities[visitor_id]
		lifecycle_id=visitor_id
		var active_enemies:Array=preload(
			"res://sim/campaign_encounter_stream.gd").current_floor_enemy_ids(world)
		check(not active_enemies.is_empty(),"current floor has canonical enemy entities")
		if active_enemies.is_empty():return
		var enemy_id:=int(active_enemies[0]);var enemy=world.entities[enemy_id]
		var adjacent:=Vector2i(-1,-1)
		for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
			var candidate:Vector2i=visitor.position+direction
			if world.in_bounds(candidate) and world.blocking_entity_at(candidate)==null \
					and str(world.tile_at(candidate).terrain)!="wall":adjacent=candidate;break
		check(adjacent!=Vector2i(-1,-1),"reciprocal combat has an adjacent real tile")
		if adjacent!=Vector2i(-1,-1):
			enemy.position=adjacent
			var member=world.party_encounter.member(visitor_id)
			member.busy_until=world.world_time+1000
			world.party_encounter.enemy_busy_rows[enemy_id]=world.world_time
			var autonomous_step:int=int(world.step_index)+1
			world.begin_step(autonomous_step)
			var autonomous_start:int=world.events.size()
			check(Explorer.process_tick(session.sim,autonomous_step),
				"autonomous retaliation cadence succeeds")
			check(Explorer.process_tick(session.sim,autonomous_step),
				"repeated same-time cadence is harmless")
			world.finish_step()
			var autonomous_attacks:Array=world.events.slice(autonomous_start).filter(
				func(event):return event.type=="action.melee_attack" and event.actor_id==enemy_id)
			check(autonomous_attacks.size()==1,
				"shared enemy busy clock permits exactly one autonomous retaliation")
			member.busy_until=world.world_time
			var processed:int=int(world.step_index)+1;world.begin_step(processed)
			var npc_health:int=int(visitor.health);var enemy_health:int=int(enemy.health)
			var before_attack_count:int=world.events.size()
			check(Explorer.attack(session.sim,visitor_id,enemy_id,processed),
				"independent explorer uses canonical weapon attack")
			check(world.events.size()>before_attack_count,
				"independent weapon attack emits a canonical action/result chain")
			var after_npc_count:int=world.events.size()
			check(Explorer.attack(session.sim,enemy_id,visitor_id,processed),
				"enemy can retaliate against the same physical neutral entity")
			check(world.events.size()>after_npc_count,
				"enemy retaliation emits a canonical action/result chain")
			world.finish_step()
			check(visitor.health<=npc_health and enemy.health<=enemy_health,
				"reciprocal combat applies canonical outcomes without healing")
			var attacks:Array=world.events.filter(func(event):return event.step_index==processed \
				and event.type=="action.melee_attack")
			check(attacks.size()==2,"reciprocal combat owns exactly two requested actions, got %d"%attacks.size())
	check(world.world_state_error().is_empty(),"physical neutral occupancy validates: "+world.world_state_error())
	if lifecycle_id>0:_check_visitor_lifecycle(session,lifecycle_id)

func _check_visitor_lifecycle(session,visitor_id:int)->void:
	var world=session.sim.world;var visitor=world.entities.get(visitor_id)
	if visitor==null:return
	var enemy_id:=-1
	for candidate in preload("res://sim/campaign_encounter_stream.gd").current_floor_enemy_ids(world):
		if world.combatant_states[int(candidate)].life_state=="ACTIVE":enemy_id=int(candidate);break
	check(enemy_id>0,"lifecycle fixture has an active canonical enemy")
	if enemy_id<1:return
	var enemy=world.entities[enemy_id];var adjacent:=Vector2i(-1,-1)
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var candidate:Vector2i=visitor.position+direction
		if world.in_bounds(candidate) and world.blocking_entity_at(candidate)==null \
				and str(world.tile_at(candidate).terrain)!="wall":adjacent=candidate;break
	if adjacent==Vector2i(-1,-1):return
	enemy.position=adjacent;visitor.health=1
	for ignored in range(16):
		if world.combatant_states[visitor_id].life_state!="ACTIVE":break
		var step:int=int(world.step_index)+1;world.begin_step(step)
		Explorer.attack(session.sim,enemy_id,visitor_id,step);world.finish_step()
	check(world.combatant_states[visitor_id].life_state=="DOWNED",
		"canonical enemy damage persists independent visitor DOWNED state")
	if world.combatant_states[visitor_id].life_state!="DOWNED":return
	var finisher_step:int=int(world.step_index)+1;world.begin_step(finisher_step)
	check(Explorer.attack(session.sim,enemy_id,visitor_id,finisher_step),
		"canonical enemy can finish a downed independent visitor")
	world.finish_step()
	var sync_step:int=int(world.step_index)+1;world.begin_step(sync_step)
	check(Explorer.process_tick(session.sim,sync_step),"dead visitor state synchronizes")
	world.finish_step()
	var row_state:=""
	for row in Population.locations(world):
		if int(row.entity_id)==visitor_id:row_state=str(row.get("state",""));break
	check(world.combatant_states[visitor_id].life_state=="DEAD" and row_state=="DEAD",
		"dead state persists in combat and readable population records")

func _check_aid_and_return(session,rows:Array,needy:Dictionary)->void:
	var world=session.sim.world;var id:=int(needy.entity_id);var entity=world.entities[id]
	var hero=world.entities[world.party_control_actor_id()];var destination:=Vector2i(-1,-1)
	for direction in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		var candidate:Vector2i=hero.position+direction
		if world.in_bounds(candidate) and world.blocking_entity_at(candidate)==null \
				and str(world.tile_at(candidate).terrain)!="wall":destination=candidate;break
	check(destination!=Vector2i(-1,-1),"aid has a real adjacent destination")
	if destination==Vector2i(-1,-1):return
	var previous:Vector2i=entity.position;entity.position=destination
	check(world.emit_event("population.arrived",id,-1,destination,0,-1,
		{"from":[previous.x,previous.y],"to":[destination.x,destination.y]})!=null,
		"visitor relocation is an explicit causal placement event")
	for row in rows:
		if int(row.entity_id)==id:row["position"]=[destination.x,destination.y]
	check(Visitors._emit(world,"population.patrol",rows)!=null,"aid fixture updates physical row")
	var player_before:=_item_quantity(world,world.party_control_actor_id(),"FOOD_RATION")
	var npc_before:=_item_quantity(world,id,"FOOD_RATION")
	var aided:Dictionary=Visitors.interact(session,{"action":"AID","entity_id":str(id)})
	check(aided.get("accepted",false),"AID completes a real inventory transfer: "+str(aided.get("reason")))
	check(_item_quantity(world,world.party_control_actor_id(),"FOOD_RATION")<player_before \
		and _item_quantity(world,id,"FOOD_RATION")>npc_before,
		"AID removes player food and gives it to the intended NPC")
	var waited:Dictionary=session.commit_exploration(Command.wait(world.party_control_actor_id()))
	check(waited.get("accepted",false),"aided explorer gets a due return action")
	for ignored in range(24):
		if "visitor_returned" in entity.tags:break
		waited=session.commit_exploration(Command.wait(world.party_control_actor_id()))
		if not waited.get("accepted",false):break
	check("visitor_returned" in entity.tags and entity not in world.occupying_entities_at(entity.position),
		"returned state persists without leaving a physical blocker")

func _item_quantity(world,id:int,definition_id:String)->int:
	var total:=0;var inventory=world.item_state.inventory(id)
	if inventory!=null:
		for item in inventory.backpack:
			if item.definition_id==definition_id:total+=int(item.quantity)
	return total

func _finish()->void:
	print("---- Living expedition acceptance: %d failed ----"%failures.size())
	quit(1 if not failures.is_empty() else 0)
