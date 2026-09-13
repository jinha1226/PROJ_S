extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Rules=preload("res://sim/settlement_work_rules.gd")
const Service=preload("res://playtest/settlement_work_service.gd")
const Grid=preload("res://sim/base_settlement_rules.gd")
const BasePanel=preload("res://playtest/base_progress_panel.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func ticks(s,n:int)->void:
	for i in range(n):
		var r:Dictionary=s.base_work({"action":"TICK"})
		if not r.get("accepted",false):check(false,"tick "+str(r));return
func run()->void:
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).get("accepted",false),"start")
	check(s.town_life_command({"action":"START","frontier":true}).get("accepted",false),"shelter")
	var world=s.sim.world;var party=world.party_encounter
	# Controlled unit fixture supplies existing entities/resources through events.
	# Save/replay is tested separately with actual rescue/gather commands.
	var resident:=-1
	for id in party.member_rows:
		if id!=party.protagonist_id and world.combatant_states[id].life_state=="ACTIVE":resident=int(id);break
	world.emit_event("town.company_joined",party.protagonist_id,resident,party.group_anchor,1,-1,{"entity_id":str(resident)})
	party.member(resident).presence="RECRUITABLE"
	world.emit_event("base.building_constructed",party.protagonist_id,-1,party.group_anchor,1,-1,{"cost":{},"building":{"instance_id":"BLD_CLINIC_1","type_id":"CLINIC","tile_origin":[1,8],"rotation":0}})
	for resource in ["TIMBER","STONE","HERBS"]:
		world.emit_event("base.resource_gathered",party.protagonist_id,-1,party.group_anchor,80,-1,{"resource_id":resource,"amount":80,"expedition_index":0})
	var hero:int=party.protagonist_id
	for id in [hero,resident]:
		party.member(id).stress=0
		for emotion in ["FEAR","ANGER","SADNESS","GUILT"]:party.member(id).emotion_state.set_channel(emotion,0)
	var initial:Dictionary=Rules.stock(world).total
	var potion:Dictionary=s.base_work({"action":"PRODUCE","recipe_id":"HEALING_POTION"})
	var upgrade:Dictionary=s.base_work({"action":"UPGRADE","type_id":"STORAGE"})
	check(potion.get("accepted",false) and upgrade.get("accepted",false),"two orders")
	ticks(s,1)
	var active:=Rules.active(Rules.state(world));var workers:Array=[]
	for job in active:
		if int(job.worker_id)>=0:workers.append(int(job.worker_id))
	check(workers.size()==2 and workers[0]!=workers[1],"two residents simultaneously execute separate jobs")
	var position:Array=Rules.state(world).residents[str(hero)].tile.duplicate()
	ticks(s,1)
	check(Rules.state(world).residents[str(hero)].tile!=position,"canonical movement changes resident tile")
	ticks(s,160)
	check(Rules.index(world).ready.HEALING_POTION==1,"finite production completed once")
	check(Rules.index(world).levels.STORAGE==2,"upgrade complete")
	var total:Dictionary=Rules.stock(world).total
	check(int(total.HERBS)==int(initial.HERBS)-2 and int(total.TIMBER)==int(initial.TIMBER)-8 and int(total.STONE)==int(initial.STONE)-5,"both costs consumed once")
	var claim:Dictionary=s.base_work({"action":"CLAIM","recipe_id":"HEALING_POTION"})
	check(claim.get("accepted",false),"claim potion "+str(claim))
	check(not s.base_work({"action":"CLAIM","recipe_id":"HEALING_POTION"}).get("accepted",false),"no double claim")
	# Disable all labor while forcing rest: no perpetual labor or priority override.
	for kind in Rules.KINDS:check(s.base_work({"action":"PRIORITY","entity_id":resident,"kind":kind,"priority":0}).get("accepted",false),"disable "+kind)
	party.member(resident).stress=650
	ticks(s,70)
	check(int(party.member(resident).stress)<600,"mandatory lodge rest independent of labor switches")
	var rest_gold:int=s.town_gold()
	var ordered_rest:Dictionary=s.base_work({"action":"REST","entity_id":resident})
	check(ordered_rest.get("accepted",false),"rest before assignment")
	ticks(s,1)
	check(s.town_gold()==rest_gold-s.TOWN_SHRINE_COST,"rest fee reserved")
	party.active_party_member_ids.append(resident)
	check(Service.release_assigned(s).is_empty(),"release assigned resting resident")
	check(Rules.state(world).jobs[str(ordered_rest.job_id)].state=="CANCELLED","resting worker departure cancels personal job")
	check(s.town_gold()==rest_gold,"worker departure releases reserved rest gold")
	check(not s.base_work({"action":"CANCEL","job_id":str(ordered_rest.job_id)}).get("accepted",false),"cancel cannot refund departure twice")
	party.active_party_member_ids.erase(resident)
	# Cancel after physical site delivery; refund must wait for return transport.
	var next:Dictionary=s.base_work({"action":"PRODUCE","recipe_id":"HEALING_POTION"})
	var id:=str(next.job_id)
	for i in range(80):
		if Rules.state(world).jobs[id].material_location=="SITE":break
		ticks(s,1)
	check(Rules.state(world).jobs[id].material_location=="SITE","site delivered before production")
	ticks(s,1)
	check(Rules.state(world).jobs[id].state=="WORKING","site work begins only after delivery")
	var before:Dictionary=Rules.stock(world).available
	check(s.base_work({"action":"CANCEL","job_id":id}).get("accepted",false),"cancel site")
	check(Rules.stock(world).available==before,"site cancel no instant refund")
	ticks(s,100)
	check(int(Rules.stock(world).available.HERBS)==int(before.HERBS)+2,"site material returned exactly once")
	# Assignment releases only that resident, including carried bundles.
	for kind in Rules.KINDS:s.base_work({"action":"PRIORITY","entity_id":resident,"kind":kind,"priority":2})
	var queued:Dictionary=s.base_work({"action":"PRODUCE","recipe_id":"HEALING_POTION"})
	for i in range(100):
		if Rules.state(world).jobs[str(queued.job_id)].material_location=="CARRIED":break
		ticks(s,1)
	var carried:Dictionary=Rules.state(world).jobs[str(queued.job_id)]
	var worker:=int(carried.worker_id)
	if worker==hero:
		check(s.depart_town().get("accepted",false),"depart while founder carries")
	else:check(s.town_life_command({"action":"ASSIGN","entity_id":str(worker)}).get("accepted",false),"assign carrying resident")
	check(int(Rules.state(world).jobs[str(queued.job_id)].worker_id)==-1,"assignment releases worker")
	check(Rules.state(world).jobs[str(queued.job_id)].material_location=="RECOVERY","carried material stays recoverable")
	if party.expedition_cycle.phase!="TOWN":s.base_return()
	check(Rules.audit(Rules.state(world),Rules.stock(world)).is_empty(),"invariants after release")
	if s.sim.world.party_encounter.expedition_cycle.phase=="TOWN":check(s.depart_town().get("accepted",false),"clock test departure")
	var boundary_tick:int=Rules.state(s.sim.world).tick
	check(Service.expedition_advance(s,true).get("accepted",false),"zero-time confirmed action")
	check(int(Rules.state(s.sim.world).tick)==boundary_tick+1,"zero-time action advances once")
	Service.expedition_advance(s)
	check(int(Rules.state(s.sim.world).tick)==boundary_tick+1,"nested time boundary does not advance twice")
	# Short duration is a controlled clock fixture, not a gameplay-policy change.
	s.sim.world.party_encounter.expedition_cycle.closes_at_world_time=s.sim.world.world_time+100
	var auto_before:int=Rules.state(s.sim.world).tick
	var held:Dictionary=s.commit_field_action(preload("res://sim/party_action_command.gd").hold(s.sim.world.party_control_actor_id()))
	check(held.get("accepted",false),"deadline action accepted "+str(held.get("reason","")))
	check(s.sim.world.party_encounter.expedition_cycle.phase=="TOWN","deadline returns to shelter")
	check(int(Rules.state(s.sim.world).tick)==auto_before+1,"deadline action still contributes one base tick")
	check(int(Rules.state(s.sim.world).residents[str(hero)].job_id)==-1,"returning founder does not work during expedition tick")
	await mobile(s)
	print("SETTLEMENT_WORK_UNIT ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
func mobile(s)->void:
	for viewport in [Vector2i(360,640),Vector2i(390,844)]:
		root.size=viewport
		var scroll:=ScrollContainer.new();scroll.size=Vector2(viewport);root.add_child(scroll)
		var panel=BasePanel.new();scroll.add_child(panel)
		panel.configure_build_assessment(Callable(s,"base_build_assessment"))
		panel.present(s.base_overview(),false,"CLINIC")
		await process_frame;await process_frame
		var map=panel.find_child("BaseSettlementMap",true,false)
		check(map!=null,"map present "+str(viewport))
		var before:int=panel.rebuild_count;var identity:int=map.get_instance_id()
		panel.update_work(s.base_overview())
		check(panel.rebuild_count==before and panel.find_child("BaseSettlementMap",true,false).get_instance_id()==identity,"tick preserves map and scroll controls")
		var picker=panel.find_child("BasePriority%dHAUL"%s.sim.world.party_encounter.protagonist_id,true,false)
		check(picker!=null and picker.custom_minimum_size.y>=48,"priority touch target")
		var received:Array=[]
		panel.work_priority_requested.connect(func(entity_id,kind,priority):received.append([entity_id,kind,priority]))
		if picker!=null:picker.item_selected.emit(3)
		check(received.size()==1 and received[0][1]=="HAUL" and received[0][2]==3,"priority signal targets the selected resident")
		var center:Vector2=map.get_global_rect().get_center()
		var selected:Array=[]
		map.building_selected.connect(func(id):selected.append(id))
		for contact in [0,1]:
			var touch:=InputEventScreenTouch.new();touch.index=contact;touch.pressed=true
			touch.position=center+Vector2(-40 if contact==0 else 40,0)
			root.push_input(touch,true);await process_frame
		var drag:=InputEventScreenDrag.new();drag.index=1;drag.position=center+Vector2(100,0)
		root.push_input(drag,true);await process_frame
		check(map.camera.zoom>1.25,"two-finger map input zooms at "+str(viewport))
		for contact in [0,1]:
			var touch:=InputEventScreenTouch.new();touch.index=contact;touch.pressed=false
			touch.position=center+Vector2(-40 if contact==0 else 100,0)
			root.push_input(touch,true);await process_frame
		check(selected.is_empty(),"pinch release does not select a facility")
		map.camera.zoom_at(map,2.0,Vector2(100,100))
		check(map.building_rect("CLINIC").size.x>0,"facility remains selectable after zoom")
		panel._open_construction_editor();await process_frame;await process_frame
		panel._choose_build_option("MARKET");await process_frame;await process_frame
		check(panel.find_child("BasePlacementCancel",true,false)!=null or panel.find_child("BaseConstructionCancel",true,false)!=null,"placement cancel present")
		scroll.scroll_vertical=200;await process_frame
		check(scroll.scroll_vertical>0,"mobile scroll reaches resident priorities")
		var cancel=panel.find_child("BasePlacementCancel",true,false)
		if cancel!=null:cancel.pressed.emit();await process_frame;await process_frame
		check(not panel._placement_active,"cancel exits blueprint placement")
		scroll.free();await process_frame
