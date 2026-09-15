extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Simulator=preload("res://sim/simulator.gd")
const Specs=preload("res://sim/consumable_catalog.gd")
const Effects=preload("res://sim/consumable_effects.gd")
const Mystery=preload("res://sim/mystery_consumables.gd")
const Utility=preload("res://playtest/consumable_utility_service.gd")
const Item=preload("res://sim/item_instance.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Action=preload("res://sim/party_action_command.gd")
var failures:Array[String]=[]
class FailingSession:
	extends "res://playtest/party_playtest_session.gd"
	func _advance_item_action_time()->Dictionary:
		preload("res://sim/consumable_effects.gd").status(sim.world,sim.world.party_control_actor_id(),"HASTE")
		preload("res://sim/mystery_consumables.gd").known(sim.world,"POTION_MYSTERY_HASTE")
		return {"accepted":false,"reason":"injected_failure"}
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func give(s,id:String):
	var w=s.sim.world;var actor:int=w.party_control_actor_id();var inv=w.inventory_of(actor)
	var items:Array=inv.backpack.duplicate();items.append(Item.new("EXP_"+id,id,2))
	w.item_state.inventory_rows[actor]=Inventory.new(items,inv.equipped)
func run():
	check(preload("res://sim/item_registry.gd").registry_error().is_empty(),"item registry")
	check(preload("res://sim/item_catalog_registry.gd").registry_error().is_empty(),"catalog registry")
	check(Specs.DROP_IDS.size()==18,"18 drop types")
	check(Specs.DROP_IDS.filter(func(id):return Specs.definition(id).negative).size()==6,"six negative types")
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var baseline:Dictionary=s.sim.snapshot()
	for id in Specs.DROP_IDS:
		s.sim=Simulator.from_snapshot(baseline);s.command_journal.clear()
		if s.sim==null:check(false,"baseline restore");break
		var actor:int=s.sim.world.party_control_actor_id();give(s,id)
		if id=="SCROLL_MYSTERY_IDENTIFY":give(s,"POTION_MYSTERY_HASTE")
		var unknown_options:Array=Utility.options(s,"EXP_"+id)
		if id.begins_with("POTION_"):
			check(not unknown_options.is_empty() and str(unknown_options[0].label)=="직접 마시기","unknown potion exposes use mode without revealing effect "+id)
		else:check(unknown_options.is_empty(),"unknown scroll does not expose targeting "+id)
		var row:Dictionary=s.protagonist_inventory().backpack_rows.filter(func(r):return r.definition_id==id)[0]
		check(row.use_kind=="UNIDENTIFIED" and row.compact_stat_text=="미감정","hidden "+id)
		var before_hp:int=s.sim.world.entities[actor].health
		var result:Dictionary=s.use_inventory_item("EXP_"+id)
		check(result.get("accepted",false),"use "+id+" "+str(result.get("reason","")))
		if not result.get("accepted",false):continue
		check(Mystery.known(s.sim.world,id),"identification "+id)
		check(s._journal_wire_error(JSON.parse_string(JSON.stringify(s.command_journal))).is_empty(),"selection journal wire "+id)
		var error:String=s.sim.world.world_state_error();check(error.is_empty(),"audit "+id+" "+error)
		var snap=s.sim.snapshot();check(snap!=null and Simulator.from_snapshot(snap)!=null,"snapshot "+id)
		if id=="POTION_MYSTERY_POISON":check(s.sim.world.entities[actor].health<before_hp,"poison hurts")
		if id=="SCROLL_MYSTERY_IDENTIFY":check(Mystery.known(s.sim.world,"POTION_MYSTERY_HASTE"),"identify other item")
		if id=="POTION_MYSTERY_HASTE":
			var w=s.sim.world
			check(preload("res://sim/field_action_timing.gd").duration(w,actor,"MELEE",100)<100,"haste action time")
			for delta in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				var action=Action.move_to(actor,w.entities[actor].position+delta)
				if s.FieldTurns.assess(s.sim,action).accepted:
					check(s.commit_field_action(action).accepted,"haste move");break
			for n in range(7):
				var held:Dictionary=s.commit_field_action(Action.hold(actor))
				if not held.accepted:check(false,"expiry turn "+str(held.reason));break
			check(Effects.status(w,actor,"HASTE")==null,"haste expires")
			error=w.world_state_error();check(error.is_empty(),"expired history "+error)
	var failed=FailingSession.new();give(failed,"POTION_MYSTERY_HASTE")
	var before:Dictionary=failed.sim.snapshot()
	check(not failed.use_inventory_item("EXP_POTION_MYSTERY_HASTE").accepted,"failed response rejects")
	check(failed.sim.snapshot()==before,"rollback quantity effects time")
	check(not Mystery.known(failed.sim.world,"POTION_MYSTERY_HASTE"),"rollback identification cache")
	check(Effects.status(failed.sim.world,failed.sim.world.party_control_actor_id(),"HASTE")==null,"rollback effect cache")
	print("EXPANDED CONSUMABLES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
