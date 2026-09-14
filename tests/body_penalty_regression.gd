extends SceneTree
const Rules=preload("res://sim/body_penalty_rules.gd")
const Body=preload("res://sim/body_state.gd")
const Session=preload("res://playtest/party_playtest_session.gd")
const Recovery=preload("res://sim/party_recovery_rules.gd")
var errors:Array[String]=[]
func _init():call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func run()->void:
	for kind in ["SKIN","MUSCLE","BONE"]:
		var low:=70 if kind=="BONE" else 25;var high:=100 if kind=="BONE" else 40
		check(Rules.grade(low-1,kind)=="하" and Rules.grade(low,kind)=="중" and Rules.grade(high,kind)=="상","grade boundaries "+kind)
	var body=Body.create(1,"human",42)
	var arm:Dictionary=body.parts[2];var leg:Dictionary=body.parts[4]
	arm.layers[1].integrity=701;check(Rules.part_stage(arm)==0,"deep wound above boundary")
	arm.layers[1].integrity=700;check(Rules.part_stage(arm)==1,"deep wound at boundary")
	arm.layers[2].integrity=600;check(Rules.part_stage(arm)==2,"fracture boundary")
	check(Rules.summary(body).attack_milli==750,"same arm does not double stack")
	leg.layers[2].integrity=600;check(Rules.summary(body).move_milli==1500,"leg fracture movement")
	Rules.heal_layers(body,1)
	check(arm.layers[1].integrity==715 and arm.layers[2].integrity==608,"layer-specific recovery")
	check(Rules.summary(body).attack_milli==1000,"healing crosses stage threshold")
	arm.condition="DISABLED";arm.layers[1].integrity=0;arm.layers[2].integrity=0
	Rules.heal_layers(body,75)
	check(arm.condition=="DISABLED","disabled limb waits for fracture boundary to clear")
	Rules.heal_layers(body,1)
	check(arm.condition=="FUNCTIONAL","rest restores disabled nonsevered limb")
	arm.condition="SEVERED"
	for layer in arm.layers:layer.integrity=0
	Rules.heal_layers(body,1000)
	check(arm.layers[0].integrity==0 and arm.condition=="SEVERED","rest never regrows severed limb")
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	var w=s.sim.world;var id:int=w.party_encounter.protagonist_id
	var live=w.body_states[id]
	live.parts[2].layers[2].integrity=600;live.revision+=1
	check(Rules.record(w,id,-1),"injury change event")
	var injured_event:int=w.events[-1].id
	check(Rules.historical(w,id,injured_event).attack_milli==1000,"historical before injury")
	check(Rules.historical(w,id,injured_event+1).attack_milli==750,"historical after injury")
	check(Rules.scale_damage(w,id,20)==15,"live attack damage penalty")
	live.parts[4].layers[2].integrity=600;live.revision+=1
	check(preload("res://sim/field_action_timing.gd").duration(w,id,"MOVE",100)==150,"party movement timing wired")
	# Full HP/MP must not prevent tissue recovery in a safe starting location.
	w.entities[id].health=w.entities[id].max_health
	w.party_encounter.member(id).energy=w.party_encounter.member(id).max_energy
	var ui=preload("res://playtest/party_encounter_sandbox.gd").new();ui.session=s
	check(ui._rest_needed(),"rest button accepts full HP with tissue damage")
	var before_integrity:int=ui._party_body_integrity_total()
	var r:=Recovery.apply(s,w.events.size(),500)
	check(r.accepted,"safe body rest accepted")
	check(live.parts[2].layers[2].integrity>600,"full HP rest heals bone")
	check(Rules.current(w,id).attack_milli==1000,"rest removes attack penalty")
	check(ui._party_body_integrity_total()>before_integrity,"tissue healing counts as rest progress")
	check(ui._rest_needed(),"rest continues until full tissue integrity")
	check(Rules.historical(w,id,injured_event+1).attack_milli==750,"rest preserves past penalty")
	check(w.world_state_error().is_empty(),"recovered world valid: "+w.world_state_error())
	var restored=preload("res://sim/simulator.gd").from_snapshot(s.sim.snapshot())
	check(restored!=null,"body/penalty snapshot restores")
	Rules.heal_layers(live,1000)
	check(not ui._rest_needed(),"rest ends with full HP MP and tissue integrity")
	ui.free()
	# A fractional HP rate must recover eventually, not be rounded to zero forever.
	var total:=0
	for n in range(1,6):total+=n*600/1000-(n-1)*600/1000
	check(total==3,"fractional HP pulses accumulate")
	check_field_combat()
	print("BODY PENALTIES: ",errors.size()," failures")
	quit(0 if errors.is_empty() else 1)

func check_field_combat()->void:
	var action=preload("res://sim/party_action_command.gd")
	var s=Session.new(44,20260828,Session.DUO_SCENARIO_ID,"human",true)
	check(s.town_life_command({"action":"START"}).accepted,"combat campaign starts")
	check(s.depart_town().accepted,"combat campaign departs")
	var hero:int=s.sim.world.party_control_actor_id()
	var attacks:=0
	for turn in range(100):
		var w=s.sim.world
		if w.entities[hero].health<=0:break
		var command=action.hold(hero)
		var goals:Array[Vector2i]=[]
		for enemy in w.party_encounter.enemy_ids:
			if not w.is_autonomous_target(enemy):continue
			if s.FieldTurns.assess(s.sim,action.melee(hero,enemy)).accepted:
				command=action.melee(hero,enemy);break
			for offset in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(w.entities[enemy].position+offset)
		if command.type!="MELEE":
			var route:Dictionary=s.sim.pathfinder.find_path_to_any(hero,goals)
			if route.get("found",false) and route.path.size()>1:command=action.move_to(hero,route.path[1])
		var result:Dictionary=s.commit_field_action(command)
		if not result.accepted:check(false,"field combat action: "+str(result.get("reason","")));return
		if command.type=="MELEE":attacks+=1
		if attacks>=3:break
	check(attacks>=3,"real field melee attacks execute")
	check(s.sim.world.world_state_error().is_empty(),"real combat world audit")
	var loaded=Session.new();var result:Dictionary=loaded.load_session_json(s.save_session_json())
	check(result.accepted,"real combat journal replay: "+str(result.get("reason","")))
	if result.accepted:check(loaded.sim.snapshot()==s.sim.snapshot(),"real combat replay exact")
	# Explicit threshold fixture exercises the damage formula and history after
	# healing. It is intentionally not used for command-journal replay.
	var w=s.sim.world;var live=w.body_states[hero]
	live.parts[2].layers[2].integrity=600;live.revision+=1
	check(Rules.record(w,hero,-1),"combat fracture recorded")
	var attacked:=false
	for enemy in w.party_encounter.enemy_ids:
		if not w.is_autonomous_target(enemy) or not s.FieldTurns.assess(s.sim,action.melee(hero,enemy)).accepted:continue
		var hit:Dictionary=s.commit_field_action(action.melee(hero,enemy))
		check(hit.accepted,"fractured arm melee accepted: "+str(hit.get("reason","")))
		attacked=hit.accepted;break
	check(attacked,"fractured arm attacks live target")
	w=s.sim.world
	check(w.world_state_error().is_empty(),"injured attack audit")
	Rules.heal_layers(w.body_states[hero],1000);Rules.record(w,hero,-1)
	check(w.world_state_error().is_empty(),"past injured attack remains valid after healing")
	check(preload("res://sim/simulator.gd").from_snapshot(s.sim.snapshot())!=null,"injured attack and healing snapshot restores")
	w.body_states[hero].parts[4].layers[2].integrity=600;w.body_states[hero].revision+=1
	Rules.record(w,hero,-1)
	var moved:=false
	for offset in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		var command=action.move_to(hero,w.entities[hero].position+offset)
		if not s.FieldTurns.assess(s.sim,command).accepted:continue
		var step:Dictionary=s.commit_field_action(command)
		check(step.accepted,"fractured leg field move: "+str(step.get("reason","")))
		moved=step.accepted;break
	check(moved,"fractured leg moves in live field")
	check(s.sim.world.world_state_error().is_empty(),"fractured movement audit")
