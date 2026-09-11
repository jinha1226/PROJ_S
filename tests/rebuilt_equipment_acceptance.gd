extends SceneTree
const World=preload("res://game/rebuilt/world.gd")
const Gear=preload("res://game/rebuilt/equipment.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func arena(w)->void:
	w.terrain.fill("floor");w.occupancy.fill(-1);w.memory.fill(1)
	w.actors.clear();w.scheduler.clear();w.navigation.fields.clear()
	w.actors.append(w.make_actor(0,w.index(Vector2i(10,10)),"hero"))
	w.occupancy[w.hero().cell]=0;w.time=0;w.sight_origin=-1;w.update_sight()
func enemy(w)->Dictionary:
	var actor:Dictionary=w.make_actor(w.actors.size(),w.index(Vector2i(11,10)),"enemy")
	w.actors.append(actor);w.occupancy[actor.cell]=actor.id
	return actor
func _init()->void:
	var w=World.new();arena(w)
	var hero:Dictionary=w.hero()
	check(Gear.valid(hero),"valid initial gear and training")
	var sword:Dictionary=Gear.stats(hero).duplicate()
	check(w.submit("EQUIP",w.inventory.find("HAND_AXE")),"equip owned weapon")
	var axe:Dictionary=Gear.stats(hero)
	check(axe.damage>sword.damage and axe.delay>sword.delay and axe.accuracy<sword.accuracy,"weapon tradeoffs affect stats")
	check(w.time==100,"equipment consumes a turn")
	var saved:Dictionary=w.save_data()
	check(not w.submit("EQUIP",999) and w.save_data()==saved,"invalid equip atomic")
	w.inventory.append("MAIL")
	check(w.submit("EQUIP",w.inventory.find("MAIL")),"equip armor")
	var mail:Dictionary=Gear.stats(hero).duplicate()
	check(mail.protection>sword.protection and mail.burden>sword.burden,"armor protection burden")
	check(not w.submit("TRAIN",0),"obsolete focused training removed")
	var target:=enemy(w);target.hp=1
	for i in range(20):
		if target.hp==0:break
		w.attack(hero,target)
	check(target.hp==0 and hero.growth.xp==25,"kill grants character XP once")
	w.attack(hero,target)
	check(hero.growth.xp==25,"dead actor cannot farm XP")
	World.Growth.gain(hero,75)
	check(w.invest(0,"MELEE") and Gear.stats(hero).damage>mail.damage,"point investment raises damage")
	check(Gear.stats(hero).delay==mail.delay and Gear.stats(hero).accuracy==mail.accuracy,"no double speed or accuracy scaling")
	for i in range(5):w.submit("WAIT")
	check(hero.growth.xp==100,"waiting grants no XP")
	w.inventory.append("BUCKLER")
	check(w.submit("EQUIP",w.inventory.find("BUCKLER")) and Gear.stats(hero).block>0,"shield equipped and active")
	w.injury_serial+=1
	hero.body.transition_part_condition("LEFT_ARM","SEVERED",w.injury_serial);World.Body.sync(hero)
	check(Gear.stats(hero).block==0,"arm loss disables shield")
	check(w.submit("EQUIP",w.inventory.find("NO_SHIELD")),"remove unusable shield")
	hero.body.transition_part_condition("RIGHT_ARM","SEVERED",w.injury_serial);World.Body.sync(hero)
	check(Gear.stats(hero).weapon=="UNARMED","arm loss forces unarmed")
	check(not w.submit("EQUIP",w.inventory.find("SHORT_SWORD")),"reject unusable weapon")
	check(not Gear.description(hero).contains("%d"),"equipment status formatting")
	saved=w.save_data()
	var loaded=World.new()
	check(loaded.restore(JSON.parse_string(JSON.stringify(saved))) and loaded.save_data()==saved,"equipment and skills exact JSON roundtrip")
	var corrupt:Dictionary=saved.duplicate(true);corrupt.actors[0].gear.weapon="UNKNOWN"
	check(not loaded.restore(corrupt) and loaded.save_data()==saved,"invalid gear rejects atomically")
	corrupt=saved.duplicate(true);corrupt.actors[0].growth.xp=-1
	check(not loaded.restore(corrupt),"invalid XP rejected")
	arena(w);hero=w.hero();target=enemy(w)
	target.hp=100000;target.max_hp=100000;hero.power=1
	var misses:=0;var hits:=0
	for i in range(100):
		var hp:int=target.hp
		w.attack(hero,target)
		if hp==target.hp:misses+=1
		else:hits+=1
	check(misses>0 and hits>0,"accuracy produces hits and misses")
	saved=w.save_data();check(loaded.restore(saved),"combat snapshot")
	for i in range(10):
		w.attack(hero,target);loaded.attack(loaded.hero(),loaded.actors[1])
	check(w.save_data()==loaded.save_data(),"no save reload reroll")
	arena(w)
	var loot_cell:int=w.index(Vector2i(11,10))
	w.loot[str(loot_cell)]="BUCKLER"
	w.inventory.erase("BUCKLER")
	check(w.submit("MOVE",loot_cell) and "BUCKLER" in w.inventory,"equipment pickup")
	saved=w.save_data();saved.schema=2;saved.erase("inventory")
	for actor in saved.actors:
		for key in ["gear","skill_xp","training"]:actor.erase(key)
	check(not loaded.restore(saved),"old schema is not silently converted")
	print("REBUILT EQUIPMENT: ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
