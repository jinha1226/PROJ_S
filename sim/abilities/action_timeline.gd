extends RefCounted

## Integer simulation time. No wall-clock timers or UI-owned scheduling.
const COSTS:={"MOVE":100,"ATTACK":100,"WAIT":100,"STRIKE":140,"SHOVE":110,"FIREBOLT":120,"BARRIER":110,"MEND":130}
var now:int=0
var ready:Dictionary={}

func reset(actors:Array)->void:
	now=0;ready.clear()
	for actor in actors:
		# The isolated lab deliberately starts at the player's decision point.
		ready[int(actor.id)]=0 if int(actor.id)==1 else duration(actor,"WAIT")

func duration(actor:Dictionary,kind:String)->int:
	var speed:int=100
	if kind=="MOVE":speed=int(actor.get("move_speed",100))
	elif kind in ["ATTACK","STRIKE","SHOVE"]:speed=int(actor.get("attack_speed",100))
	elif kind!="WAIT":speed=int(actor.get("cast_speed",100))
	var base:int=int(actor.get("attack_time",100)) if kind=="ATTACK" else int(COSTS.get(kind,100))
	return maxi(1,ceili(float(base)*100.0/maxi(1,speed)))

func complete(actor:Dictionary,kind:String)->void:
	ready[int(actor.id)]=now+duration(actor,kind)

func next_actor(actors:Array,times:Dictionary=ready)->int:
	var selected:int=-1
	for actor in actors:
		var id:int=int(actor.id)
		if int(actor.hp)<=0 or not times.has(id):continue
		if selected<0 or int(times[id])<int(times[selected]) or (times[id]==times[selected] and id<selected):selected=id
	return selected

func forecast(actors:Array,hero_kind:String="",count:int=6)->Array:
	var times:Dictionary=ready.duplicate()
	if not hero_kind.is_empty():times[1]=now+duration(actors[0],hero_kind)
	var result:Array=[]
	var seen:Dictionary={}
	for index in range(count):
		var id:=next_actor(actors,times)
		if id<0:break
		result.append({"id":id,"time":times[id],"estimated":seen.has(id)})
		seen[id]=true
		# Unchosen future actions use WAIT only as a visibly estimated interval.
		for actor in actors:
			if int(actor.id)==id:times[id]+=duration(actor,"WAIT");break
	return result
