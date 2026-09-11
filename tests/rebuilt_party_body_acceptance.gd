extends SceneTree
const World=preload("res://game/rebuilt/world.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func arena(w)->void:
	w.terrain.fill("floor");w.occupancy.fill(-1);w.memory.fill(1)
	w.actors.clear();w.scheduler.clear();w.navigation.fields.clear()
	w.actors.append(w.make_actor(0,w.index(Vector2i(10,10)),"hero"))
	w.occupancy[w.hero().cell]=0;w.time=0;w.sight_origin=-1;w.update_sight()
func append_actor(w,point:Vector2i,team:String)->Dictionary:
	var actor:Dictionary=w.make_actor(w.actors.size(),w.index(point),team)
	w.actors.append(actor);w.occupancy[actor.cell]=actor.id
	return actor
func _init()->void:
	var w=World.new()
	check(w.companions().size()==1,"new game has companion")
	arena(w)
	var ally:=append_actor(w,Vector2i(11,10),"companion")
	var hp:int=ally.hp
	var old:int=w.hero().cell
	check(w.submit("MOVE",ally.cell),"friendly swap accepted")
	check(ally.hp==hp and ally.cell==old and w.occupancy[old]==ally.id and w.occupancy[w.hero().cell]==0,"swap no friendly fire and valid occupancy")
	check(w.visible_enemies().is_empty(),"companion is not visible enemy")
	w.move_actor(ally,w.index(Vector2i(15,10)))
	var distance:int=w.position(ally.cell).distance_squared_to(w.position(w.hero().cell))
	w.companion_turn(ally)
	check(w.position(ally.cell).distance_squared_to(w.position(w.hero().cell))<distance,"companion follows")
	ally.order="HOLD";old=ally.cell;w.companion_turn(ally)
	check(ally.cell==old,"hold order prevents follow")
	var enemy:=append_actor(w,w.position(ally.cell)+Vector2i.DOWN,"enemy")
	enemy.hp=1;w.companion_turn(ally)
	check(enemy.hp==0 and w.occupancy[enemy.cell]==-1,"companion immediate lethal attack")
	enemy=append_actor(w,w.position(ally.cell)+Vector2i.DOWN,"enemy")
	hp=ally.hp;w.enemy_turn(enemy)
	check(ally.hp<hp,"enemy can target companion")
	check(ally.body.wounds.size()>0 and ally.body.revision>0,"combat applies existing body injury")
	check(ally.blood==100*ally.body.current_blood/int(ally.body.body_scalars.blood_capacity),"blood comes from body ledger")
	check(ally.body.validation_error().is_empty(),"injured body remains valid")
	check(not World.Body.description(ally).contains("%d"),"body status formats all scalar values")
	# Injury function rules are the existing project's authoritative limb rules.
	w.injury_serial+=1
	check(ally.body.transition_part_condition("LEFT_LEG","DISABLED",w.injury_serial)=="","disable leg")
	check(ally.body.transition_part_condition("LEFT_ARM","SEVERED",w.injury_serial)=="","sever arm")
	World.Body.sync(ally)
	check(w.movement_time(ally,ally.cell)==160 and ally.attack_factor==75,"limb conditions affect movement and attack")
	var saved:Dictionary=w.save_data()
	var loaded=World.new(123)
	check(loaded.restore(JSON.parse_string(JSON.stringify(saved))),"party and injury load")
	check(loaded.save_data()==saved,"exact party injury roundtrip")
	w.submit("WAIT");loaded.submit("WAIT")
	check(loaded.save_data()==w.save_data(),"deterministic continuation with body")
	var malformed:Dictionary=saved.duplicate(true);malformed.actors[1].body.current_blood=-1
	var before:Dictionary=loaded.save_data()
	check(not loaded.restore(malformed) and loaded.save_data()==before,"malformed body rejected without mutation")
	# The pre-body v1 save contains no recoverable limb history: initialise bodies.
	var legacy:Dictionary=saved.duplicate(true);legacy.schema=1;legacy.erase("injury_serial")
	for actor in legacy.actors:
		for key in ["body","order","move_factor","attack_factor"]:actor.erase(key)
	check(loaded.restore(legacy) and loaded.hero().body!=null,"v1 rebuilt saves migrate")
	var ally_body:Dictionary=ally.body.to_dict()
	var ally_hp:int=ally.hp
	w.floor_number+=1;w.generate_floor()
	check(w.companions().size()==1 and w.companions()[0].hp==ally_hp,"party survives floor change")
	check(w.companions()[0].body.parts==ally.body.parts and w.companions()[0].body.wounds==ally.body.wounds,"injuries survive floor change")
	check(w.companions()[0].body.current_blood==int(ally_body.current_blood),"blood persists across floor")
	arena(w);ally=append_actor(w,Vector2i(11,10),"companion");ally.hp=20
	ally.body.current_blood-=100;ally.body.revision+=1;World.Body.sync(ally)
	var blood:int=ally.body.current_blood
	check(w.submit("POTION",ally.id) and ally.hp==50 and ally.body.current_blood>blood,"targeted companion potion")
	var attacker:=append_actor(w,Vector2i(12,10),"enemy");ally.hp=1
	# Accuracy now permits misses; death must occur on the first landed lethal hit.
	for i in range(20):
		if ally.hp==0:break
		w.attack(attacker,ally)
	check(ally.hp==0 and w.occupancy[ally.cell]==-1 and not w.loot.has(str(ally.cell)),"companion death no enemy loot")
	check(not w.submit("POTION",ally.id),"potion cannot revive dead companion")
	print("REBUILT PARTY BODY: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
