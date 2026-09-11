extends SceneTree
const World=preload("res://game/rebuilt/world.gd")
const Growth=preload("res://game/rebuilt/progression.gd")
const GrowthPanel=preload("res://game/rebuilt/growth_panel.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func arena(w)->void:
	w.terrain.fill("floor");w.occupancy.fill(-1);w.memory.fill(1);w.actors.clear();w.scheduler.clear();w.navigation.fields.clear()
	w.actors.append(w.make_actor(0,w.index(Vector2i(10,10)),"hero"));w.occupancy[w.hero().cell]=0
	w.sight_origin=-1;w.update_sight();w.time=0
func enemy(w,point:Vector2i=Vector2i(14,10))->Dictionary:
	var actor:Dictionary=w.make_actor(w.actors.size(),w.index(point),"enemy")
	w.actors.append(actor);w.occupancy[actor.cell]=actor.id;return actor
func _init()->void:run.call_deferred()
func run()->void:
	var w=World.new();arena(w);var hero:Dictionary=w.hero()
	check(Growth.valid(hero.growth) and hero.growth.points==0,"level 1 canonical state")
	check(Growth.gain(hero,99)==0 and hero.growth.points==0,"no early point")
	check(Growth.gain(hero,1)==1 and hero.growth.points==1,"levelup awards one point")
	check(w.invest(0,"MELEE") and hero.growth.points==0,"spend point once")
	check(not w.invest(0,"MELEE"),"overspend rejected")
	check(Growth.scale(hero,"MELEE",100)==108 and Growth.scale(hero,"MAGIC",100)==100,"single mapped multiplier")
	check(Growth.gain(hero,300)==1 and hero.growth.level==3,"cumulative XP level")
	var snapshot:Dictionary=w.save_data()
	var loaded=World.new();check(loaded.restore(JSON.parse_string(JSON.stringify(snapshot))) and loaded.save_data()==snapshot,"point budget roundtrip")
	var invalid:Dictionary=snapshot.duplicate(true);invalid.actors[0].growth.points+=1
	check(not loaded.restore(invalid) and loaded.save_data()==snapshot,"forged point rejected atomically")
	invalid=snapshot.duplicate(true);invalid.actors[0].growth.ranks.MELEE=1.5
	check(not loaded.restore(invalid),"fractional ranks rejected")
	var panel=GrowthPanel.new();root.add_child(panel);panel.open(w)
	check(panel.cards.size()==4 and panel.invest_buttons.size()==4,"four visible investment cards")
	var before:int=hero.growth.points
	panel.preview_invest(2);panel.confirm.canceled.emit()
	check(hero.growth.points==before,"cancel spends nothing")
	panel.preview_invest(2);panel.commit_pending();panel.commit_pending()
	check(hero.growth.points==before-1 and hero.growth.ranks.MAGIC==1,"duplicate confirmation no double spend")
	panel.hide();panel.queue_free()
	Growth.gain(hero,1000000)
	check(hero.growth.level==Growth.DATA.max_level and Growth.valid(hero.growth),"level cap preserves budget")
	for i in range(20):Growth.invest(hero,"DEFENSE")
	check(hero.growth.ranks.DEFENSE==10 and Growth.defend(hero,100)==80 and Growth.defend(hero,1)==1,"defense cap and minimum")
	arena(w);hero=w.hero();var target:=enemy(w)
	var before_state:Dictionary=w.save_data()
	check(not w.submit("FIREBOLT",target.cell) and w.save_data()==before_state,"unbound spell rejected atomically")
	hero.gear.weapon="BOW";w.arrows=2
	var initial:int=target.hp
	check(w.submit("SHOOT",target.cell) and w.arrows==1 and w.time>0,"ranged action consumes ammo and time")
	check(target.hp<initial,"ranged damage")
	w.terrain[w.index(Vector2i(12,10))]="wall"
	before_state=w.save_data()
	check(not w.submit("SHOOT",target.cell) and w.save_data()==before_state,"wall blocks shot before cost")
	w.terrain[w.index(Vector2i(12,10))]="floor";w.arrows=0
	check(not w.submit("SHOOT",target.cell),"empty ammo rejected")
	check(w.attack_stats(hero).skill=="MELEE","bow bump uses melee fallback")
	Growth.gain(hero,100);w.sight_origin=-1;w.update_sight()
	check(not w.invest(0,"RANGED"),"combat investment blocked")
	arena(w);hero=w.hero();target=enemy(w)
	target.bound_abilities=["FIREBOLT"];target.hp=1
	w.apply_damage(hero,target,1)
	check(w.loot[str(target.cell)]=="fire_essence","actual fire user drops essence")
	w.move_actor(hero,target.cell);w.pickup()
	check(w.fire_essences==1,"essence pickup separate from binding")
	check(w.submit("BIND_FIRE") and "FIREBOLT" in hero.bound_abilities and w.fire_essences==0,"binding transaction")
	w.fire_essences=1;before_state=w.save_data()
	check(not w.submit("BIND_FIRE") and w.save_data()==before_state,"duplicate binding preserves essence")
	var caster_cell:Vector2i=w.position(hero.cell)
	target=enemy(w,caster_cell+Vector2i(3,0));target.hp=100;target.max_hp=100;target.fire_resistance=50
	Growth.gain(hero,100);Growth.invest(hero,"MAGIC")
	var expected:=Growth.defend(target,Growth.scale(hero,"MAGIC",12)*50/100)
	initial=target.hp
	check(w.submit("FIREBOLT",target.cell) and initial-target.hp==expected,"magic one multiplier then resistance")
	check(hero.mp==16 and target.body.wounds.size()>0,"MP and elemental injury")
	hero.mp=0;before_state=w.save_data()
	check(not w.submit("FIREBOLT",target.cell) and w.save_data()==before_state,"no MP atomic rejection")
	target.fire_resistance=100;initial=target.hp;w.cast_fire(hero,target)
	check(target.hp==initial,"full fire resistance")
	check(loaded.restore(JSON.parse_string(JSON.stringify(w.save_data()))),"ability resources restore")
	# Floor traversal retains invested points and bound abilities without new grants.
	var growth_before:Dictionary=hero.growth.duplicate(true)
	w.floor_number+=1;w.generate_floor()
	check(w.hero().growth==growth_before and "FIREBOLT" in w.hero().bound_abilities,"floor retains growth and binding")
	print("REBUILT GROWTH: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
