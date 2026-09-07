extends RefCounted

## Isolated, deterministic balance arena. Never mutates campaign saves.
const Effects=preload("res://sim/abilities/active_effect_model.gd")
const Skills=preload("res://sim/abilities/active_skill_registry.gd")
const Hexaco=preload("res://sim/dungeon_population/hexaco_profile.gd")
const BOUNDS:=Rect2i(0,0,18,18)
var actors:Array=[]
var blocked:Dictionary={}
var history:Array[String]=[]
var decisions:Array=[]
var turn:=0
var terminal:=""
var seed:=44

func _init(p_seed:int=44)->void:reset(p_seed)

func reset(p_seed:int=44)->void:
	seed=p_seed;actors.clear();blocked.clear();history.clear();decisions.clear();turn=0;terminal=""
	for x in range(18):blocked[Vector2i(x,0)]=true;blocked[Vector2i(x,17)]=true
	for y in range(18):blocked[Vector2i(0,y)]=true;blocked[Vector2i(17,y)]=true
	for position in [Vector2i(4,6),Vector2i(4,7),Vector2i(12,10),Vector2i(13,10)]:blocked[position]=true
	var species:=["human","dwarf","elf","orc"]
	var kits:=[["FIREBOLT","BARRIER"],["STRIKE","SHOVE"],["MEND","BARRIER"],["FIREBOLT","STRIKE"]]
	for index in range(4):
		actors.append(_actor(index+1,"PARTY",species[index],Vector2i(7+index%2,9+index/2),100,20,kits[index]))
	for index in range(5):
		var monster:=_actor(index+5,"ENEMY","goblin" if index%2==0 else "kobold",Vector2i(6+index,5+index%2),60,12,[])
		if index==4:monster.resistances={"FIRE":50};monster.name="내화 코볼트"
		actors.append(monster)
	history.append("4인 파티 · 기술 2개 · 기력 12. 주인공이 행동하면 동료와 적이 행동합니다.")

func _actor(id:int,team:String,species:String,position:Vector2i,hp:int,power:int,skills:Array)->Dictionary:
	var profile=Hexaco.generated(seed,id)
	return {"id":id,"team":team,"species_id":species,"name":"주인공" if id==1 else ("동료 %d"%id if team=="PARTY" else "적 %d"%(id-4)),
		"position":position,"hp":hp,"max_hp":hp,"power":power,"energy":12,"skills":skills.duplicate(),
		"armor":0,"resistances":{},"barrier":0,"barrier_actions":0,"recoverable":0,"recovery_credit":0,
		"profile":profile.to_dict(),"personality":str(profile.style_summary().label)}

func actor(id:int)->Dictionary:
	for row in actors:
		if row.id==id:return row
	return {}

func actor_at(cell:Vector2i)->Dictionary:
	for row in actors:
		if int(row.hp)>0 and row.position==cell:return row
	return {}

func preview(caster_id:int,skill:String,target_id:int)->Dictionary:
	return Effects.assess(skill,actor(caster_id),actor(target_id),actors,blocked,BOUNDS)

func act(kind:String,target_id:int=-1,destination:Vector2i=Vector2i(-1,-1))->Dictionary:
	if not terminal.is_empty():return {"accepted":false,"reason":"전투가 끝났습니다."}
	var hero:=actor(1)
	var result:=_execute(hero,kind,target_id,destination)
	if not result.accepted:return result
	turn+=1
	_update_terminal()
	if terminal.is_empty():
		for id in range(2,5):
			if int(actor(id).hp)>0:_automatic(actor(id))
			_update_terminal()
			if not terminal.is_empty():break
	if terminal.is_empty():
		for id in range(5,10):
			if int(actor(id).hp)>0:_automatic(actor(id))
			_update_terminal()
			if not terminal.is_empty():break
	if history.size()>100:history=history.slice(history.size()-100)
	if decisions.size()>100:decisions=decisions.slice(decisions.size()-100)
	return {"accepted":true,"reason":"ok","turn":turn,"terminal":terminal}

func _execute(source:Dictionary,kind:String,target_id:int,destination:Vector2i)->Dictionary:
	var target:=actor(target_id)
	if kind in Skills.SKILLS:
		var assessment:=preview(source.id,kind,target_id)
		if not assessment.accepted:return assessment
		source.energy-=assessment.cost
		if int(assessment.damage)>0:_damage(target,int(assessment.damage))
		if int(assessment.barrier)>0:
			target.barrier=assessment.barrier;target.barrier_actions=2
		if int(assessment.healing)>0:
			target.hp+=assessment.healing;target.recoverable-=assessment.healing
		if kind=="SHOVE" and int(target.hp)>0:target.position=assessment.destination
		history.append("%s → %s: %s (-%d 기력)"%[source.name,target.name,Skills.SKILLS[kind].name,assessment.cost])
	elif kind=="ATTACK":
		if target.is_empty() or target.team==source.team or int(target.hp)<=0 \
				or distance(source.position,target.position)>1 \
				or not Effects.clear_line(source.position,target.position,blocked):return {"accepted":false,"reason":"인접한 적을 선택하세요."}
		_damage(target,int(source.power));history.append("%s → %s: 공격"%[source.name,target.name])
	elif kind=="MOVE":
		if distance(source.position,destination)!=1 or not BOUNDS.has_point(destination) \
				or blocked.has(destination) or not actor_at(destination).is_empty() \
				or not Effects.clear_line(source.position,destination,blocked):return {"accepted":false,"reason":"이동 가능한 인접 칸을 선택하세요."}
		source.position=destination
	elif kind=="WAIT":pass
	else:return {"accepted":false,"reason":"알 수 없는 행동입니다."}
	# Barrier lasts through the recipient's next action, then expires on the next.
	if int(source.barrier_actions)>0 and not (kind=="BARRIER" and target_id==int(source.id)):
		source.barrier_actions-=1
		if int(source.barrier_actions)==0:source.barrier=0
	return {"accepted":true,"reason":"ok"}

func _damage(target:Dictionary,amount:int)->void:
	var absorbed:=mini(int(target.barrier),amount);target.barrier-=absorbed
	var damage:=mini(int(target.hp),amount-absorbed)
	target.hp-=damage
	# Integer remainder prevents tiny hits from manufacturing recovery credit.
	var numerator:=int(target.recovery_credit)+damage
	target.recoverable=mini(int(target.max_hp)-int(target.hp),int(target.recoverable)+numerator/2)
	target.recovery_credit=numerator%2
	if int(target.hp)<=0:target.barrier=0;history.append("%s 쓰러짐"%target.name)

func _automatic(source:Dictionary)->void:
	var candidates:Array=[]
	for skill in source.skills:
		for target in actors:
			var assessment:=preview(source.id,str(skill),target.id)
			if not assessment.accepted:continue
			var score:float=float(assessment.damage)
			var support:float=0.75+float(source.profile.A)/2000.0
			if int(assessment.healing)>0:score=float(assessment.healing)*support*(1.8 if int(target.hp)<35 else 1.0)
			if int(assessment.barrier)>0:
				var threats:=0
				for foe in actors:
					if foe.team!=target.team and int(foe.hp)>0 and distance(foe.position,target.position)<=2:threats+=1
				score=float(assessment.barrier)*support*minf(1.5,float(threats)*0.7)
			# Conscientious actors value keeping energy, but never bypass legality.
			score-=float(assessment.cost)*(1.0+float(source.profile.C)/500.0)
			candidates.append({"kind":skill,"target":target.id,"position":Vector2i(-1,-1),"score":score})
	var nearest:Dictionary={};var nearest_distance:=999
	for target in actors:
		if target.team==source.team or int(target.hp)<=0:continue
		var separation:=distance(source.position,target.position)
		if separation<nearest_distance:nearest=target;nearest_distance=separation
		if separation<=1 and Effects.clear_line(source.position,target.position,blocked):
			candidates.append({"kind":"ATTACK","target":target.id,"position":Vector2i(-1,-1),"score":float(source.power)})
	if not nearest.is_empty():
		var next:=_next_step(source.position,nearest.position)
		if next!=source.position:candidates.append({"kind":"MOVE","target":-1,"position":next,"score":8.0})
	candidates.append({"kind":"WAIT","target":-1,"position":Vector2i(-1,-1),"score":0.0})
	candidates.sort_custom(func(a,b):return float(a.score)>float(b.score) if a.score!=b.score else (str(a.kind)<str(b.kind) if a.kind!=b.kind else int(a.target)<int(b.target)))
	var selected:Dictionary=candidates[0]
	decisions.append({"actor_id":source.id,"kind":selected.kind,"target":selected.target,"score":selected.score})
	_execute(source,str(selected.kind),int(selected.target),selected.position)

func _next_step(origin:Vector2i,target:Vector2i)->Vector2i:
	var frontier:Array[Vector2i]=[origin];var visited:Dictionary={origin:origin};var cursor:=0
	while cursor<frontier.size():
		var current:Vector2i=frontier[cursor];cursor+=1
		if distance(current,target)<=1 and Effects.clear_line(current,target,blocked):
			var step:=current
			while visited[step]!=origin and step!=origin:step=visited[step]
			return step
		for y in range(-1,2):
			for x in range(-1,2):
				var next:=current+Vector2i(x,y)
				if visited.has(next) or not BOUNDS.has_point(next) or blocked.has(next) \
						or not actor_at(next).is_empty() or not Effects.clear_line(current,next,blocked):continue
				visited[next]=current;frontier.append(next)
	return origin

func _update_terminal()->void:
	if int(actor(1).hp)<=0:terminal="패배"
	var living:=false
	for row in actors:
		if row.team=="ENEMY" and int(row.hp)>0:living=true
	if not living:terminal="승리"

static func distance(a:Vector2i,b:Vector2i)->int:
	return maxi(absi(a.x-b.x),absi(a.y-b.y))
