extends "res://tests/test_case.gd"

const Simulator=preload("res://sim/simulator.gd")
const Command=preload("res://sim/sim_command.gd")
const WorldState=preload("res://sim/world_state.gd")
const BodyStateScript=preload("res://sim/body_state.gd")


func test_add_entity_creates_deterministic_body_without_consuming_rng()->bool:
	var sim=Simulator.create(8,8,20260902)
	var rng_before:int=sim.world.rng.state
	var rows:=[
		["hero","인간",Vector2i(0,0),"human"],
		["companion","엘프",Vector2i(1,0),"elf"],
		["companion","드워프",Vector2i(2,0),"dwarf"],
		["companion","오크",Vector2i(3,0),"orc"],
		["companion","수인",Vector2i(4,0),"beastkin"],
		["melee_enemy","고블린",Vector2i(5,0),"goblin"],
		["obstacle","미지정",Vector2i(6,0),""],
		["goblin","기본 고블린",Vector2i(7,0),""]]
	for row in rows:
		var entity=sim.world.add_entity(row[0],row[1],row[2],100,[],row[3])
		check(entity!=null,"%s entity creates"%row[1])
		if entity==null:continue
		var body=sim.world.body_states.get(entity.id)
		var expected_species:String=str(row[3]) if not str(row[3]).is_empty() \
			else ("goblin" if str(row[0])=="goblin" else "generic_humanoid")
		check(body!=null,"%s body creates atomically"%row[1])
		if body!=null:
			check_eq([body.entity_id,body.species_id,body.body_seed],
				[entity.id,expected_species,BodyStateScript.world_body_seed(
					sim.world.seed,entity.id,expected_species)],"%s body identity"%row[1])
	check_eq(sim.world.rng.state,rng_before,"roster body generation consumes no command RNG")
	check_eq(sim.world.world_state_error(),"","all generated bodies satisfy world invariants")
	var detached=sim.world.body_of(1)
	check(detached!=null and detached!=sim.world.body_states[1],"body facade is detached")
	if detached!=null:
		detached.shock=99
		check_eq(sim.world.body_states[1].shock,0,"facade cannot mutate authority")
	return finish()


func test_rejected_entity_creation_never_leaves_a_body_row()->bool:
	var sim=Simulator.create(4,4,7)
	var first=sim.world.add_entity("hero","선점",Vector2i(1,1),100,[],"human")
	check(first!=null,"fixture entity exists")
	var before:=[sim.world.entities.size(),sim.world.combatant_states.size(),
		sim.world.body_states.size(),sim.world._next_entity_id,sim.world.rng.state]
	check(sim.world.add_entity("melee_enemy","겹침",Vector2i(1,1),100,[],"goblin")==null,
		"occupied spawn rejects")
	check_eq([sim.world.entities.size(),sim.world.combatant_states.size(),
		sim.world.body_states.size(),sim.world._next_entity_id,sim.world.rng.state],before,
		"rejection leaves entity, body, allocator and RNG untouched")
	sim.world.body_states[sim.world._next_entity_id]=BodyStateScript.create(
		sim.world._next_entity_id,"human",1)
	check(sim.world.add_entity("hero","중복 육체",Vector2i(2,1),100,[],"human")==null,
		"foreign body row blocks atomic adoption")
	check_eq([sim.world.entities.size(),sim.world.combatant_states.size(),
		sim.world._next_entity_id],[before[0],before[1],before[3]],
		"duplicate body row creates no partial entity")
	return finish()


func test_snapshot_v10_body_rows_are_strict_sorted_and_hard_cut()->bool:
	var sim=Simulator.create(5,5,414)
	var human=sim.world.add_entity("hero","인간",Vector2i(1,1),100,[],"human")
	var goblin=sim.world.add_entity("melee_enemy","고블린",Vector2i(2,1),40,[],"goblin")
	var wire:Dictionary=sim.snapshot()
	check_eq([wire.snapshot_version,wire.body_ruleset_id,wire.body_combat_ruleset_id,
		wire.body_state_schema_id],[10,"body-simulation-b1-v1","body-combat-b1-v1",
		"body-state-v2"],"v10 declares body and injury authority")
	check_eq(wire.body_states.map(func(row):return row.entity_id),
		[str(human.id),str(goblin.id)],"body rows use canonical entity order")
	var json_wire:Dictionary=JSON.parse_string(JSON.stringify(wire))
	check_eq(WorldState.snapshot_restore_error(json_wire),"",
		"v10 JSON body wire passes checked decode")
	var restored=Simulator.from_snapshot(json_wire)
	check(restored!=null,"v10 JSON snapshot restores")
	if restored!=null:check_eq(restored.snapshot(),wire,"v10 body snapshot round trip is exact")
	var legacy:=wire.duplicate(true);legacy.snapshot_version=9
	check_eq(WorldState.snapshot_restore_error(legacy),"unsupported_snapshot_version",
		"v9 snapshot is a deliberate hard cut")
	var missing:=wire.duplicate(true);missing.body_states.pop_back()
	check_eq(WorldState.snapshot_restore_error(missing),"body_entity_set_mismatch",
		"missing body row rejects")
	var unsorted:=wire.duplicate(true);unsorted.body_states.reverse()
	check_eq(WorldState.snapshot_restore_error(unsorted),"duplicate_or_unsorted_body_states",
		"unsorted body rows reject")
	var species_forgery:=wire.duplicate(true);species_forgery.body_states[0].species_id="orc"
	check(WorldState.snapshot_restore_error(species_forgery)!="",
		"body species cannot diverge from its entity")
	var seed_forgery:=wire.duplicate(true);seed_forgery.body_states[0].body_seed="1"
	check_eq(WorldState.snapshot_restore_error(seed_forgery),"body_seed_entity_mismatch",
		"body variation identity cannot be forged")
	var scalar_forgery:=wire.duplicate(true)
	var toughness:=int(scalar_forgery.body_states[0].body_scalars.skin_toughness)
	scalar_forgery.body_states[0].body_scalars.skin_toughness=toughness-1 \
		if toughness>30 else toughness+1
	check_eq(WorldState.snapshot_restore_error(scalar_forgery),"body_scalar_seed_mismatch",
		"seed-derived body scalars cannot be forged within template bounds")
	return finish()


func test_rollback_restores_body_exactly_and_rejects_stale_revision()->bool:
	var sim=Simulator.create(4,4,77)
	var hero=sim.world.add_entity("hero","복원",Vector2i(1,1),100,[],"human")
	var before:Dictionary=sim.snapshot()
	var memento:Variant=sim.capture_rollback_memento()
	check(memento is Dictionary,"settled world captures body memento")
	if not memento is Dictionary:return finish()
	check_eq([memento.schema_version,memento.body_rows.size()],[4,1],
		"rollback v4 carries one body row per entity")
	sim.world.body_states[hero.id].shock=300
	sim.world.body_states[hero.id].revision=1
	check(sim.restore_rollback_memento(memento),"body mutation restores")
	check_eq(sim.snapshot(),before,"rollback restores exact body and full snapshot")
	var stale:Dictionary=sim.capture_rollback_memento()
	sim.world.body_states[hero.id].revision+=1
	check(not sim.world.rollback_memento_is_current(stale),
		"body revision invalidates a captured authorization memento")
	return finish()


func test_environmental_damage_remains_outside_melee_body_injury_scope()->bool:
	var sim=Simulator.create(2,1,9)
	var actor=sim.world.add_entity("hero","시험",Vector2i.ZERO,100,[],"human")
	sim.world.tile_at(Vector2i.ZERO).flammability=100
	var body_before:Dictionary=sim.world.body_states[actor.id].to_dict()
	var health_before:int=actor.health
	var result=sim.step(Command.ignite(Vector2i.ZERO,70,actor.id))
	check(result.accepted,"existing damage command commits")
	check(actor.health<health_before,"legacy HP damage remains active")
	check_eq(sim.world.body_states[actor.id].to_dict(),body_before,
		"the first injury slice only projects canonical melee physical hits")
	return finish()
