extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Visitors=preload("res://playtest/dungeon_visitors_service.gd")
const Population=preload("res://sim/town_population_rules.gd")
const Shell=preload("res://playtest/party_encounter_sandbox.gd")
var errors:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	root.size=Vector2i(390,844)
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.start_new_run_with_species("human",true,true).accepted,"living solo bootstrap")
	check(s.town_life_command({"action":"START"}).accepted,"population initialized")
	check(s.depart_town().accepted,"dungeon entry")
	var restored=Session.new()
	var loaded:Dictionary=restored.load_session_json(s.save_session_json())
	check(loaded.accepted,"dungeon population bootstrap replays: "+str(loaded.get("reason","")))
	if loaded.accepted:check(restored.sim.snapshot()==s.sim.snapshot(),"bootstrap replay matches")
	var world=s.sim.world;var party=world.party_encounter
	var rows:Array=Population.locations(world)
	check(rows.size()>=3,"independent explorers spawned")
	if rows.size()<3:quit(1);return
	var hero:int=party.protagonist_id
	var id:int=int(rows[2].entity_id)
	# Controlled fixture isolates service rules from navigation and random combat.
	world.entities[id].position=world.entities[hero].position+Vector2i.RIGHT
	rows[2].position=[world.entities[id].position.x,world.entities[id].position.y]
	rows[2].state="REST"
	Visitors._emit(world,"population.patrol",rows)
	var before:Dictionary=s.sim.snapshot()
	var view:Dictionary=Visitors.assess(s,id)
	check(s.sim.snapshot()==before,"assessment is read only")
	check(view.can_aid and not view.can_join,"hungry resting NPC needs aid first")
	var adjacent:Vector2i=world.entities[id].position
	world.entities[id].position+=Vector2i(4,0)
	check(not Visitors.assess(s,id).can_aid,"distant NPC cannot receive aid")
	world.entities[id].position=adjacent
	check(not Visitors.interact(s,{"action":"ACCEPT","entity_id":str(id)}).accepted,"no free recruitment")
	var food:String=Visitors._ration(world,hero)
	var count:int=world.item_state.inventory(hero).item(food).quantity
	check(Visitors.interact(s,{"action":"AID","entity_id":str(id)}).accepted,"food aid accepted")
	check(world.item_state.inventory(hero).item(food).quantity==count-1,"exactly one ration consumed")
	check(id not in party.active_party_member_ids,"aid does not auto join")
	check(Visitors.assess(s,id).can_join,"aid guarantees offer")
	check(not Visitors.interact(s,{"action":"AID","entity_id":str(id)}).accepted,"duplicate aid rejected")
	var ui=Shell.new();ui.initialize_for_headless_test(s,false);root.add_child(ui);ui.set_process(false)
	ui._open_member_detail(id)
	check(ui.member_detail_candidate_action.text=="동행 수락" and not ui.member_detail_candidate_action.disabled,"detail UI exposes acceptance")
	for i in range(4):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/expedition-aid-offer.png")
	ui._on_member_detail_candidate_action()
	ui.queue_free();await process_frame
	check(id in party.active_party_member_ids and party.member(id).presence=="DEPLOYED","canonical field companion linked")
	check(not Visitors.interact(s,{"action":"ACCEPT","entity_id":str(id)}).accepted,"duplicate recruitment rejected")
	rows=Population.locations(world)
	var injured:int=int(rows[0].entity_id)
	world.entities[injured].position=world.entities[hero].position+Vector2i.DOWN
	check(not Visitors.assess(s,injured).can_heal and not Visitors.assess(s,injured).can_join,"healthy resting NPC is not a free recruit")
	world.entities[injured].health-=40
	rows[0].state="REST";Visitors._emit(world,"population.patrol",rows)
	view=Visitors.assess(s,injured)
	check(view.can_heal,"injured resting NPC accepts potion")
	var potion:String=Visitors._healing_item(world,hero)
	count=world.item_state.inventory(hero).item(potion).quantity
	var hp:int=world.entities[injured].health;var hero_hp:int=world.entities[hero].health
	check(Visitors.interact(s,{"action":"HEAL","entity_id":str(injured)}).accepted,"healing aid accepted")
	check(world.entities[injured].health>hp and world.entities[hero].health==hero_hp,"recipient heals, not donor")
	check(world.item_state.inventory(hero).item(potion).quantity==count-1,"one potion consumed")
	check(Visitors.interact(s,{"action":"ACCEPT","entity_id":str(injured)}).accepted,"second companion joins")
	rows=Population.locations(world)
	var third:int=int(rows[0].entity_id)
	world.entities[third].position=world.entities[hero].position+Vector2i.UP
	world.entities[third].health-=40;rows[0].state="REST";Visitors._emit(world,"population.patrol",rows)
	check(Visitors.interact(s,{"action":"HEAL","entity_id":str(third)}).accepted,"aid allowed with full party")
	check(not Visitors.assess(s,third).can_join,"full party blocks join")
	check(Visitors.assess(s,third).helped,"full party keeps aid credit")
	check(world.world_state_error().is_empty(),"world invariant after recruitment: "+world.world_state_error())
	var returned:Dictionary=s.base_return()
	check(returned.accepted,"return ends expedition: "+str(returned.get("reason",""))+" / "+world.world_state_error())
	check(id not in party.active_party_member_ids and injured not in party.active_party_member_ids,"temporary companions released on return")
	check(world.world_state_error().is_empty(),"world invariant after return: "+world.world_state_error())
	print("EXPEDITION AID: ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
