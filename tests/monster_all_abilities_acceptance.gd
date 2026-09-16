extends SceneTree
const Session=preload("res://playtest/party_playtest_session.gd")
const Simulator=preload("res://sim/simulator.gd")
const Catalog=preload("res://sim/abilities/monster_ability_catalog.gd")
const Runtime=preload("res://sim/abilities/monster_ability_runtime.gd")
const Defs=preload("res://sim/abilities/monster_ability_definitions.gd")
const Action=preload("res://sim/party_action_command.gd")
const Inventory=preload("res://sim/inventory_state.gd")
const Item=preload("res://sim/item_instance.gd")
var failures:Array[String]=[]
func _init():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func equip(s,row,passive:bool):
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var inv=w.inventory_of(hero);var items:Array=inv.backpack.duplicate()
	items.append(Item.new("ALL_"+str(row.ability_id),str(row.essence_id),1))
	w.item_state.inventory_rows[hero]=Inventory.new(items,inv.equipped)
	# Isolate established ability behavior from the three-turn ingestion penalty.
	# Real consumption, periodic damage and expiry are covered by corpse_parts_growth_acceptance.
	var result:Dictionary=s.bind_ability_item(hero,"ALL_"+str(row.ability_id),false)
	check(result.accepted,"bind "+str(row.ability_id)+" "+str(result.get("reason")))
	var id:String="FIREBOLT" if row.ability_id=="FIRE_GLAND" else str(row.ability_id)
	if passive:
		# Battle fixture: mode UI and journal replay are tested separately.
		w.party_encounter.member(hero).passive_ability_ids.append(id)
		w.emit_event("party.ability_mode_changed",hero,hero,w.entities[hero].position,0,-1,{"schema_version":1,"ability_id":id,"mode":"PASSIVE"})
	return id
func nearest(s)->int:
	var w=s.sim.world;var hero:int=w.party_control_actor_id();var best:=-1;var dist:=999
	for id in w.party_encounter.enemy_ids:
		if not w.is_autonomous_target(id):continue
		if s.FieldTurns.assess(s.sim,Action.melee(hero,id)).accepted:return id
		var d:int=Runtime.distance(w.entities[hero].position,w.entities[id].position)
		if d<dist:best=id;dist=d
	return best
func approach(s)->bool:
	var w=s.sim.world;var hero:int=w.party_control_actor_id()
	var best:Dictionary={}
	for enemy in w.party_encounter.enemy_ids:
		if not w.is_autonomous_target(enemy):continue
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if not preload("res://sim/party_perception_registry.gd").field_visible(w,w.entities[enemy].position+delta,w.entities[enemy].position):continue
			var p:Dictionary=s.sim.pathfinder.find_path(hero,w.entities[enemy].position+delta)
			if p.get("found",false) and p.path.size()>1 and (best.is_empty() or p.path.size()<best.path.size()):best=p
	if best.is_empty():print("no fixture path, hero=",w.entities[hero].position);return false
	# Logged fixture positioning: no HP, life-state, or attack-result injection.
	for cell in best.path.slice(1):
		var terrain:String=w.tile_at(cell).terrain
		var cost:int=preload("res://sim/terrain_registry.gd").definition(terrain).move_time_cost
		if s.sim.movement.commit_preflighted_move(hero,cell,terrain,cost)==null:return false
	w.party_encounter.group_anchor=w.entities[hero].position
	var assessed:Dictionary=s.FieldTurns.assess(s.sim,Action.melee(hero,nearest(s)))
	if not assessed.accepted:print("fixture assessment ",assessed," hero ",w.entities[hero].position," enemy ",w.entities[nearest(s)].position," member ",w.party_encounter.member(hero).presence," canact ",w.can_act(hero,w.world_time)," active ",w.party_encounter.active_party_member_ids)
	return assessed.accepted
func run():
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"town")
	check(s.depart_town().accepted,"depart")
	check(approach(s),"logged adjacent fixture")
	if not failures.is_empty():quit(1);return
	var baseline:Dictionary=s.sim.snapshot()
	for row in Catalog.DATA.definitions:
		if row.ability_id=="FIRE_GLAND":continue # Covered by monster_dual_mode_acceptance.
		s.sim=Simulator.from_snapshot(baseline)
		if s.sim==null:check(false,"restore baseline");break
		var id:String=equip(s,row,false);var w=s.sim.world;var hero:int=w.party_control_actor_id()
		var target:int=hero if Defs.definition(id).target=="SELF" else nearest(s)
		if id=="HUNTER_LEAP":
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var cell:Vector2i=w.entities[hero].position+delta
				var move=s.sim.movement.assess_move(hero,cell)
				if move.accepted and Runtime.distance(cell,w.entities[target].position)==2:
					s.sim.movement.commit_preflighted_move(hero,cell,str(move.terrain_id),int(preload("res://sim/terrain_registry.gd").definition(move.terrain_id).move_time_cost))
					w.party_encounter.group_anchor=cell;break
		if id=="REGENERATIVE_TISSUE" and w.entities[hero].health==w.entities[hero].max_health:
			# An enemy attack supplies canonical recoverable damage.
			for n in range(3):s.commit_field_action(Action.hold(hero))
		var before:int=w.events.size();var energy:int=w.party_encounter.member(hero).energy
		var result=s.FieldTurns.step(s.sim,Action.skill(hero,id,target))
		check(result.accepted,"cast "+id+" "+str(result.reason))
		if result.accepted:
			check(w.party_encounter.member(hero).energy==energy-int(Defs.definition(id).cost),"cost "+id)
			check(w.events.slice(before).any(func(e):return e.type=="ability.cast" and e.data.skill_id==id),"real cast "+id)
			var tail:Array=w.events.slice(before)
			var effect:String=str(Defs.definition(id).effect)
			if effect in ["DAMAGE","EXECUTE","ACID","SIPHON","DISCHARGE"]:
				check(tail.any(func(e):return e.type=="ability.impact" and e.data.ability_id==id),"active impact "+id)
			if effect=="LEAP":check(tail.any(func(e):return e.type=="action.move" and w.event_by_id(e.cause_id)!=null and w.event_by_id(e.cause_id).type=="ability.cast"),"actual leap displacement")
			if effect in ["HIDE","SHELL","STONE","VEIL","ECHO","DEEP"]:check(Runtime.status(w,hero,effect)!=null,"active persistent status "+id)
			if effect in ["SHELL","STONE"]:check(Runtime.anchored(w,hero),"stance locks movement "+id)
			if effect=="FROST":check(tail.any(func(e):return e.type=="ability.status" and e.data.status=="FROST_ZONE"),"persistent frost zone")
			if effect=="POISON":check(tail.any(func(e):return e.type=="combat.physical_damage" and w.event_by_id(e.cause_id).type=="ability.impact"),"poison tick damages")
			if effect=="REGENERATE":check(tail.any(func(e):return e.type=="health.restored" and e.data.kind=="MONSTER_ABILITY"),"regeneration heals")
			var err:String=w.world_state_error();check(err.is_empty(),"audit "+id+" "+err)
			if err.is_empty():
				var restored=Simulator.from_snapshot(s.sim.snapshot())
				check(restored!=null,"snapshot "+id)
				if restored!=null:check(restored.snapshot()==s.sim.snapshot(),"snapshot equality "+id)
				if restored!=null and Runtime.alive(w,hero):
					var original_next=s.FieldTurns.step(s.sim,Action.hold(hero))
					var restored_next=s.FieldTurns.step(restored,Action.hold(hero))
					check(original_next.accepted and restored_next.accepted,"post-load turn "+id)
					check(restored.snapshot()==s.sim.snapshot(),"post-load deterministic continuation "+id)
		print("ACTIVE CHECKED ",id)
		# Isolated passive fixture uses the same ordinary attack/actor turn seam.
		s.sim=Simulator.from_snapshot(baseline)
		id=equip(s,row,true);w=s.sim.world;hero=w.party_control_actor_id();target=nearest(s)
		check(id not in w.party_encounter.member(hero).active_skill_ids(),"passive excludes cast "+id)
		if id in ["HIDE_PLATING","CARAPACE","STONE_SKELETON"]:
			check(Runtime.armor(w,hero,"IMPACT")>0,"passive armor "+id)
		elif id=="THROWING_INSTINCT":check(Runtime.accuracy_bonus(w,hero,"SHORT_BOW")>0 or Runtime.accuracy_bonus(w,hero,"BOW")>0,"ranged accuracy")
		elif id in ["ECHO_SENSE","DEEP_EYE"]:check(not Runtime.markers(w).is_empty(),"sense markers "+id)
		else:
			var passive_start:int=w.events.size()
			for n in range(3):
				if not Runtime.alive(w,target):break
				var hit=s.FieldTurns.step(s.sim,Action.melee(hero,target))
				check(hit.accepted,"passive turn "+id)
			if id in ["PREDATOR_NERVE","HUNTER_LEAP","CAUSTIC_BLOOD","FROST_SILK","CHARGE_ORGAN","VENOM_FANG","BLOOD_SIPHON"]:
				check(w.events.slice(passive_start).any(func(e):return str(e.type).begins_with("ability.") and e.data.get("ability_id")==id),"passive actually triggered "+id)
		var err:String=w.world_state_error();check(err.is_empty(),"passive audit "+id+" "+err)
		print("PASSIVE CHECKED ",id)
	print("ALL MONSTER ABILITIES ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
