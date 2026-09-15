extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Items=preload("res://sim/world_item_operations.gd")
var failures:Array=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func run():
	for seed in [40,41,44]:
		var s=Session.new(seed,20260828,Session.DUO_SCENARIO_ID,"human",true)
		check(s.start_new_run_with_species("human",true,true).accepted,"select species")
		check(s.town_life_command({"action":"START"}).accepted,"journalled town start")
		var result:Dictionary=s.depart_town()
		check(result.accepted,"departure seed %d: %s"%[seed,result.get("reason","")])
		if not result.accepted:continue
		check(s.sim.world.party_encounter.expedition_cycle.phase=="DUNGEON","entered dungeon")
		check(Items.equipped_requirements_error(s.sim.world).is_empty(),"all NPC equipment legal")
		check(s.sim.world.world_state_error().is_empty(),"world audit")
		var hidden_equipment_events:=0
		for event in s.sim.world.events:
			if event.type not in ["item.equipped","item.unequipped"] \
					or s.sim.world.party_encounter.member(int(event.actor_id))!=null:continue
			var visible:bool=s.FieldRules.visible_cells(s.sim.world).has(
				"%d:%d"%[event.position.x,event.position.y])
			if not visible:
				hidden_equipment_events+=1
				check(not s._is_important_log_event(event),
					"offscreen NPC equipment event stays out of player log")
		var visible_cells:Dictionary=s.FieldRules.visible_cells(s.sim.world)
		var unseen:=Vector2i(-1,-1)
		for y in range(s.sim.world.height):
			for x in range(s.sim.world.width):
				if not visible_cells.has("%d:%d"%[x,y]):unseen=Vector2i(x,y);break
			if unseen!=Vector2i(-1,-1):break
		var npc_id:int=s.sim.world.party_encounter.enemy_ids[0]
		check(unseen!=Vector2i(-1,-1) and not s._log_event_currently_visible({
			"type":"item.equipped","actor_id":npc_id,"position":unseen}),
			"synthetic offscreen NPC equipment event is hidden")
		if seed==40:
			check(s.sim.world.events.any(func(e):return e.type=="item.granted" and e.data.get("definition_id")=="WEAPON_DCSS_CLUB"),"low dex NPC receives compatible club")
			var saved:String=s.save_session_json();var clone=Session.new()
			var loaded:Dictionary=clone.load_session_json(saved)
			check(loaded.accepted,"startup journal replay: "+str(loaded.get("reason","")))
			if loaded.accepted:check(s.sim.snapshot()==clone.sim.snapshot(),"replay state exact")
	print("TOWN_DEPARTURE_RANDOMIZED ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
