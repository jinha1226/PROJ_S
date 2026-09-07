extends SceneTree
const Model=preload("res://playtest/active_combat_lab_model.gd")
const Selector=preload("res://sim/abilities/tactical_action_selector.gd")
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	if not value:failures.append(message)
func arena():
	var model=Model.new(44);model.actors=[];model.blocked={}
	return model
func _init()->void:
	var model=arena()
	var source:Dictionary=model._actor(3,"PARTY","human",Vector2i(5,5),100,20,["MEND","BARRIER"])
	var hero:Dictionary=model._actor(1,"PARTY","human",Vector2i(6,5),100,20,[])
	var ally:Dictionary=model._actor(2,"PARTY","human",Vector2i(5,6),100,20,[])
	ally.hp=12;ally.recoverable=30
	var enemy:Dictionary=model._actor(5,"ENEMY","goblin",Vector2i(5,7),100,20,[])
	model.actors=[hero,ally,source,enemy];model.timeline.reset(model.actors)
	var selected:Dictionary=model.choose_action(source)
	check(selected.target==2 and selected.kind in ["MEND","BARRIER"],"protect endangered companion over healthy player")
	for row in model.actors:row.team="ENEMY" if row.team=="PARTY" else "PARTY"
	var mirrored:Dictionary=model.choose_action(source)
	check(mirrored.target==selected.target and mirrored.kind==selected.kind,"same protection rules for enemy faction")
	for row in model.actors:row.team="ENEMY" if row.team=="PARTY" else "PARTY"
	hero.id=2;ally.id=1;model.timeline.ready={1:100,2:0,3:100,5:100}
	selected=model.choose_action(source)
	check(selected.target==1 and selected.kind in ["MEND","BARRIER"],"same protection after player identity swap")
	source.skills=["BARRIER"];ally.barrier=28
	selected=model.choose_action(source)
	check(not(selected.kind=="BARRIER" and selected.target==1),"do not replace sufficient barrier")
	enemy.skills=["FIREBOLT"];enemy.position=Vector2i(5,10)
	check(Selector.threat(model,enemy,ally)==32,"ranged caster counted beyond melee distance")
	model.blocked[Vector2i(5,8)]=true
	check(Selector.threat(model,enemy,ally)==0,"wall blocks threat")
	model.blocked.clear();model.timeline.ready[5]=1000
	check(Selector.threat(model,enemy,ally)==0,"late enemy is not immediate threat")
	model=arena()
	var left:Dictionary=model._actor(1,"PARTY","human",Vector2i(4,5),100,20,[])
	var right:Dictionary=model._actor(2,"PARTY","human",Vector2i(6,5),100,20,[])
	enemy=model._actor(5,"ENEMY","goblin",Vector2i(5,5),100,20,[])
	model.actors=[left,right,enemy];model.timeline.reset(model.actors)
	var counts:Dictionary={1:0,2:0}
	for sample in range(1,65):
		model.seed=sample
		var first:Dictionary=model.choose_action(enemy)
		counts[first.target]+=1
		var position:Vector2i=model.actor(first.target).position
		left.id=2;right.id=1;model.actors.reverse()
		var second:Dictionary=model.choose_action(enemy)
		check(model.actor(second.target).position==position,"ID/order independent equal target choice")
		left.id=1;right.id=2;model.actors.reverse()
	check(counts[1]>10 and counts[2]>10,"symmetric targets both selected across seeds")
	print("symmetric choices: ",counts)
	for failure in failures:printerr(failure)
	print("Tactical selector: %d failures"%failures.size());quit(0 if failures.is_empty() else 1)
