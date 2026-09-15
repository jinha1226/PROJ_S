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
		var party_id:int=s.sim.world.party_encounter.protagonist_id
		var visible_position:Vector2i=s.sim.world.entities[party_id].position
		for event_type in ["item.equipped","action.melee_attack",
				"combat.physical_damage","status.applied","item.used"]:
			var hidden_event:={"type":event_type,"actor_id":npc_id,"target_id":npc_id,
				"instigator_id":npc_id,"position":unseen}
			check(unseen!=Vector2i(-1,-1) and not s._log_event_currently_visible(hidden_event),
				"offscreen NPC %s event is hidden"%event_type)
			check(not s._is_important_log_event(hidden_event),
				"offscreen NPC %s never enters the indexed log"%event_type)
			var visible_event:Dictionary=hidden_event.duplicate(true)
			visible_event.position=visible_position
			check(s._log_event_currently_visible(visible_event),
				"visible NPC %s event remains readable"%event_type)
		var party_target_event:={"type":"action.melee_attack","actor_id":npc_id,
			"target_id":party_id,"instigator_id":npc_id,"position":unseen}
		check(s._log_event_currently_visible(party_target_event),
			"an NPC attack involving a party member remains readable")
		if seed==40:
			check(s.sim.world.events.any(func(e):return e.type=="item.granted" and e.data.get("definition_id")=="WEAPON_DCSS_CLUB"),"low dex NPC receives compatible club")
			var saved:String=s.save_session_json();var clone=Session.new()
			var loaded:Dictionary=clone.load_session_json(saved)
			check(loaded.accepted,"startup journal replay: "+str(loaded.get("reason","")))
			if loaded.accepted:check(s.sim.snapshot()==clone.sim.snapshot(),"replay state exact")
	print("TOWN_DEPARTURE_RANDOMIZED ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
