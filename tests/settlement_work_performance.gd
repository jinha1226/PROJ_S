extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/settlement_work_rules.gd")
const Service=preload("res://playtest/settlement_work_service.gd")
var rows:Array=[]
func _init()->void:run.call_deferred()
func percentile(values:Array,p:float)->float:
	var copy:=values.duplicate();copy.sort();return float(copy[mini(copy.size()-1,int(copy.size()*p))])
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	s.start_new_run_with_species("human",true,true)
	s.town_life_command({"action":"START","frontier":true})
	var world=s.sim.world;var ids:Array=world.party_encounter.member_rows.keys();ids.sort()
	var available_ids:Array=[]
	for id in ids:
		if Service.available(s,int(id)) or (world.combatant_states.has(id) and world.combatant_states[id].life_state=="ACTIVE"):
			available_ids.append(int(id))
	# Synthetic company and order counts isolate scheduler pressure. They are not
	# assertions that the player can order 32 simultaneous clinic upgrades.
	for id in available_ids.slice(0,12):
		if id in s.company_member_ids():continue
		world.emit_event("town.company_joined",world.party_encounter.protagonist_id,id,world.party_encounter.group_anchor,1,-1,{"entity_id":str(id)})
		world.party_encounter.member(id).presence="RECRUITABLE"
		world.party_encounter.member(id).stress=0
		for emotion in ["FEAR","ANGER","SADNESS","GUILT"]:world.party_encounter.member(id).emotion_state.set_channel(emotion,0)
	world.emit_event("base.resource_gathered",world.party_encounter.protagonist_id,-1,world.party_encounter.group_anchor,1000,-1,
		{"resource_id":"HERBS","amount":1000,"expedition_index":0})
	var original_members:Array=s.company_member_ids()
	for residents in [1,4,12]:
		for orders in [0,8,32]:
			var before:=Rules.state(world);var value:=Rules.empty_state();value.enabled=true
			Service.sync_residents(s,value)
			var chosen:Array=original_members.slice(0,residents)
			for row in value.residents.values():row.job_id=-1
			# Make omitted company members unavailable to the tick sync through a
			# lightweight facade; world and all production validators remain real.
			var facade=Facade.new(s,chosen)
			for n in range(orders):
				var data:Dictionary={"cost":{"HERBS":2},"gold_cost":0,"work_steps":100000,
					"target_worker":-1,"type_id":"LODGE","tile_origin":[11,2],"footprint":[3,2],"recipe_id":"HEALING_POTION"}
				Service.new_job(world,value,"PRODUCE",data)
			for id in before.jobs:
				var old:Dictionary=before.jobs[id].duplicate(true);old.state="CANCELLED";old.worker_id=-1;old.slot=[];old.materials_reserved=false
				if not value.jobs.has(id):value.jobs[id]=old
			var error:=Service.persist(world,before,value)
			if not error.is_empty():printerr("FAIL setup ",error);quit(1);return
			Rules.path_searches=0
			var samples:Array=[];var first:Array=[];var last:Array=[]
			var event_start:int=world.events.size();var memory_start:int=Performance.get_monitor(Performance.MEMORY_STATIC)
			for tick in range(10000):
				var started:=Time.get_ticks_usec()
				var r:=Service.commit(facade,{"version":2,"action":"TICK"})
				var duration:float=(Time.get_ticks_usec()-started)/1000.0
				if not r.get("accepted",false):printerr("FAIL tick ",r);quit(1);return
				samples.append(duration)
				if tick<1000:first.append(duration)
				if tick>=9000:last.append(duration)
			var row:Dictionary={"residents":residents,"actual_residents":chosen.size(),"orders":orders,
				"p50_ms":percentile(samples,0.5),"p95_ms":percentile(samples,0.95),"max_ms":percentile(samples,1.0),
				"first_p95_ms":percentile(first,0.95),"last_p95_ms":percentile(last,0.95),
				"events":world.events.size()-event_start,"path_searches":Rules.path_searches,"ui_rebuilds":0,
				"memory_delta_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC))-memory_start}
			rows.append(row);print("SETTLEMENT_PERF ",JSON.stringify(row))
		var file:=FileAccess.open("res://docs/settlement-performance.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"seed":44,"ticks_per_case":10000,
			"fixture":"synthetic long-running production orders on real world; public commit including runtime validation and journal; no rendered UI", "rows":rows},"\t"));file.close()
	print("SETTLEMENT_PERFORMANCE PASS");quit()
class Facade extends RefCounted:
	var source
	var ids:Array
	var sim
	var scenario_id
	const DUO_SCENARIO_ID="DUO_AUTOBATTLE_V1"
	var command_journal:Array=[]
	const TOWN_SHRINE_COST=15
	func _init(s,chosen:Array)->void:source=s;ids=chosen;sim=s.sim;scenario_id=s.scenario_id
	func company_member_ids()->Array:return ids
	func town_life_enabled()->bool:return true
	func private_home_available()->bool:return true
	func town_gold()->int:return source.town_gold()
	func _base_lodge_recovery()->int:return source._base_lodge_recovery()
