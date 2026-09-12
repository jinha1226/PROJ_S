extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
const Torch=preload("res://sim/torch_rules.gd")
const Ops=preload("res://sim/world_item_operations.gd")
const Awareness=preload("res://sim/enemy_awareness_state.gd")
const Portrait=preload("res://playtest/compact_party_portrait.gd")
const Action=preload("res://sim/party_action_command.gd")
var errors:Array[String]=[]
var enemy_completed:=false
var ui_completed:=false
class EventFixture:
	extends RefCounted
	var events:Array=[]
	var torch_event_cache:Dictionary={}
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)

func place(world,id:int,pos:Vector2i)->void:
	var old:Vector2i=world.entities[id].position
	world.entities[id].position=pos
	world.reindex_entity_occupancy(id,old,pos)

func enemy_routes()->void:
	# Deliberately isolated geometry/forecast fixture, not a saved campaign.
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var world=session.sim.world;var party=world.party_encounter
	var hero:int=world.party_control_actor_id();var center:=Vector2i(10,10)
	for y in range(5,18):
		for x in range(5,18):world.tile_at(Vector2i(x,y)).terrain="stone_floor"
	for id in world.entities:place(world,id,Vector2i(1+int(id)%5,1+int(id)/5))
	place(world,hero,center);party.group_anchor=center;party.member(hero).presence="DEPLOYED"
	var ids:Array=session.sim.party_coordinator._stream_enemy_ids()
	check(ids.size()>=3,"fixture has three monsters")
	if ids.size()<3:return
	ids=ids.slice(0,3)
	for i in range(ids.size()):
		var id:int=ids[i];place(world,id,center+Vector2i(2+i,0))
		var awareness=Awareness.new(id,world.entities[id].position)
		awareness.awareness_state="HUNTING";awareness.last_known_target_position=center
		party.enemy_awareness_rows[id]=awareness
	var board:={"focus_target_id":hero,"claims":{}}
	var diagonal:=false
	for round in range(6):
		for id in ids:
			var forecast:Dictionary=session.sim.party_coordinator.forecast_enemy_action(id,board)
			check(forecast==session.sim.party_coordinator.forecast_enemy_action(id,board),"forecast deterministic")
			if forecast.action_type!="MOVE":continue
			var next:=Vector2i(forecast.destination[0],forecast.destination[1])
			var delta:Vector2i=next-world.entities[id].position
			diagonal=diagonal or delta.x!=0 and delta.y!=0
			check(session.sim.movement.assess_move(id,next).accepted,"flank move obeys occupancy and corners")
			place(world,id,next)
	var slots:Dictionary={}
	for id in ids:
		var pos:Vector2i=world.entities[id].position
		check(maxi(absi(pos.x-center.x),absi(pos.y-center.y))==1,"queued monster reaches attack ring")
		slots[pos]=true
	check(slots.size()==3 and diagonal,"three distinct surrounding slots, including diagonal movement")
	# A narrow corridor cannot magically permit passing through the front actor.
	for y in range(5,18):
		for x in range(5,18):world.tile_at(Vector2i(x,y)).terrain="wall" if y!=10 else "stone_floor"
	for i in range(ids.size()):place(world,ids[i],center+Vector2i(1+i,0))
	var blocked:Dictionary=session.sim.party_coordinator.forecast_enemy_action(ids[1],board)
	check(blocked.action_type=="HOLD","single-cell corridor respects blockage")
	enemy_completed=true

func reference_latest(world,id:String):
	for i in range(world.events.size()-1,-1,-1):
		var event=world.events[i]
		if event.type in [Torch.EVENT_IGNITED,Torch.EVENT_EXTINGUISHED] and str(event.data.get("instance_id",""))==id:return event
	return null

func torch_index()->void:
	var world=EventFixture.new()
	world.events.append({"id":1,"type":Torch.EVENT_IGNITED,"data":{"instance_id":"torch"}})
	for i in range(10000):world.events.append({"id":i+2,"type":"action.hold","data":{}})
	check(Torch._latest_event(world,"torch")==reference_latest(world,"torch"),"index matches full scan")
	var begun:=Time.get_ticks_usec()
	for i in range(100):reference_latest(world,"torch")
	var scan_us:=Time.get_ticks_usec()-begun;begun=Time.get_ticks_usec()
	for i in range(100):Torch._latest_event(world,"torch")
	print("TORCH_LOOKUP 100 calls / 10001 events scan_us=",scan_us," indexed_us=",Time.get_ticks_usec()-begun)
	world.events.append({"id":10002,"type":Torch.EVENT_EXTINGUISHED,"data":{"instance_id":"torch"}})
	check(Torch._latest_event(world,"torch").type==Torch.EVENT_EXTINGUISHED,"append extinguishes")
	world.events.resize(1)
	check(Torch._latest_event(world,"torch").type==Torch.EVENT_IGNITED,"truncation resets index")
	world.events[0]={"id":1,"type":Torch.EVENT_EXTINGUISHED,"data":{"instance_id":"torch"}}
	check(Torch._latest_event(world,"torch").type==Torch.EVENT_EXTINGUISHED,"same-length replacement resets index")
	check(Torch._latest_event(EventFixture.new(),"torch")==null,"worlds do not share cache")

func loot_ui()->void:
	var session=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var world=session.sim.world;var hero:int=world.party_control_actor_id()
	var pos:Vector2i=world.entities[hero].position
	var grant:Dictionary=Ops.commit_grant(world,hero,"POTION_HEALING",1,pos,"LOOT_UI_TEST")
	check(grant.get("accepted",false),"canonical grant")
	check(Ops.commit_drop(world,hero,str(grant.instance_id),pos,0).accepted,"canonical drop underfoot")
	var second:Dictionary=Ops.commit_grant(world,hero,"TORCH",1,pos,"LOOT_UI_TEST")
	check(second.get("accepted",false) and Ops.commit_drop(world,hero,str(second.instance_id),pos,0).accepted,"second ground item")
	var away:=Vector2i(-1,-1)
	for direction in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
		if session.sim.movement.assess_move(hero,pos+direction).accepted:
			away=pos+direction;break
	check(away!=Vector2i(-1,-1) and session.commit_field_action(Action.move_to(hero,away)).accepted,"step away from loot through canonical movement")
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
	var ui=Shell.new();ui.initialize_for_headless_test(session,false);root.add_child(ui);ui.set_process(false)
	await process_frame;await process_frame
	var approach_time:int=world.world_time
	ui._on_cell(pos)
	check(world.entities[hero].position==pos and world.world_time==approach_time+100,"touching loot tile performs exactly one move")
	var before:int=world.world_time;var events:int=world.events.size()
	ui._pickup_pending_ground_item_if_reached()
	check(world.world_time==before and world.events.size()==events,"arrival adds no hidden pickup turns")
	check(session.ground_item_count_at_protagonist()==2 and not ui.product_pickup_button.disabled,"loot remains and pickup enables")
	ui._on_product_pickup()
	check(session.ground_item_count_at_protagonist()==1,"explicit button acquires only one ground item")
	check(world.world_time==before+100,"one item uses one canonical turn")
	ui._on_product_pickup()
	check(session.ground_item_count_at_protagonist()==0 and world.world_time==before+200,"second press handles remaining item")
	ui._refresh();await process_frame
	check(ui.product_pickup_button.disabled,"empty tile disables pickup")
	var detail:Dictionary=session.inspect_party_member(hero)
	ui._update_member_status_window(detail)
	var summary=ui.find_child("StatusCombatSummary",true,false)
	check(summary!=null and "공격력" in summary.text and "블록율" in summary.text,"status card exposes four combat stats")
	var card=ui.cards.get_child(0)
	check(card.get_script()==Portrait and card.combat_labels().size()==2,"live portrait displays two combat lines")
	check(card.actor.combat_stats==detail.combat_stats,"portrait and status share current combat numbers")
	ui._open_member_detail(hero)
	for i in range(3):await process_frame
	var displayed=ui.find_child("StatusCombatSummary",true,false)
	check(displayed!=null and displayed.is_visible_in_tree() and displayed.size.y>=48,"status stats have real visible height, not just a hidden DTO")
	ui._close_member_detail()
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(3):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mobile-combat-stats.png")
		ui._open_member_detail(hero)
		for i in range(3):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/mobile-combat-status.png")
		ui._close_member_detail()
	for count in [1,2,4]:
		var probe=Portrait.new();probe.actor=card.actor;probe.party_count=count
		probe.size=Vector2(360.0/count,84)
		check(probe.portrait_layout_spec().name_position.y>70,"name remains below combat lines at mobile widths")
		probe.free()
	ui.queue_free();await process_frame
	ui_completed=true

func run()->void:
	enemy_routes();torch_index();await loot_ui()
	var torch_tests=load("res://tests/test_torch_stage3.gd")
	for name in ["test_torch_registry_equip_ignite_and_dynamic_light","test_torch_save_load_and_journal_replay_are_exact"]:
		var test=torch_tests.new()
		check(test.call(name)==true,"torch regression %s: %s"%[name,test.errors])
	check(enemy_completed and ui_completed,"all fixtures completed")
	print("MOBILE COMBAT LOOT TORCH: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
