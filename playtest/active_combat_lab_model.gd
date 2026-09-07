extends RefCounted

## Isolated, deterministic balance arena. Never mutates campaign saves.
const Effects=preload("res://sim/abilities/active_effect_model.gd")
const Skills=preload("res://sim/abilities/active_skill_registry.gd")
const Hexaco=preload("res://sim/dungeon_population/hexaco_profile.gd")
const Timeline=preload("res://sim/abilities/action_timeline.gd")
const TacticalSelector=preload("res://sim/abilities/tactical_action_selector.gd")
const BodyBridge=preload("res://sim/abilities/active_body_bridge.gd")
var body_bridge=BodyBridge.new()
var timeline=Timeline.new()
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
		var enemy_kits:=[["STRIKE","SHOVE"],["FIREBOLT"],["MEND","BARRIER"],["SHOVE"],["STRIKE"]]
		var roles:=["돌격병","화염술사","수호술사","척후병","내화 전사"]
		var monster:=_actor(index+5,"ENEMY","goblin" if index%2==0 else "kobold",Vector2i(6+index,5+index%2),90 if index in [0,4] else 60,16,enemy_kits[index])
		monster.name="적 %d %s"%[index+1,roles[index]]
		monster.energy=8 if index==2 else 6
		if index==4:monster.resistances={"FIRE":50}
		actors.append(monster)
	timeline.reset(actors)
	body_bridge.reset(actors,seed)
	history.append("4인 파티 · 행동 시간 기반. 주인공 차례에는 시간이 멈춥니다.")

func _actor(id:int,team:String,species:String,position:Vector2i,hp:int,power:int,skills:Array)->Dictionary:
	var profile=Hexaco.generated(seed,id)
	return {"id":id,"team":team,"species_id":species,"name":"주인공" if id==1 else ("동료 %d"%id if team=="PARTY" else "적 %d"%(id-4)),
		"position":position,"hp":hp,"max_hp":hp,"power":power,"energy":12,"skills":skills.duplicate(),
		"weapon_id":"SHORT_SWORD","move_speed":85 if species=="dwarf" else (110 if species=="elf" else 100),
		"attack_speed":110 if species=="orc" else 100,"cast_speed":110 if species=="elf" else 100,"attack_time":100,
		"armor":0,"resistances":{},"barrier":0,"barrier_actions":0,"recoverable":0,"recovery_credit":0,
		"last_action":"아직 행동 전","last_target":"","last_reason":"","profile":profile.to_dict(),"personality":str(profile.style_summary().label)}

func actor(id:int)->Dictionary:
	for row in actors:
		if row.id==id:return row
	return {}

func actor_at(cell:Vector2i)->Dictionary:
	for row in actors:
		if int(row.hp)>0 and row.position==cell:return row
	return {}

func preview(caster_id:int,skill:String,target_id:int)->Dictionary:
	var error:String=body_bridge.use_error(actor(caster_id),skill) if not actor(caster_id).is_empty() else ""
	if not error.is_empty():return {"accepted":false,"reason":error}
	return Effects.assess(skill,actor(caster_id),actor(target_id),actors,blocked,BOUNDS)

func basic_power(source:Dictionary)->int:return body_bridge.basic_power(source)

func act(kind:String,target_id:int=-1,destination:Vector2i=Vector2i(-1,-1))->Dictionary:
	if not terminal.is_empty():return {"accepted":false,"reason":"전투가 끝났습니다."}
	var hero:=actor(1)
	var result:=_execute(hero,kind,target_id,destination)
	if not result.accepted:return result
	turn+=1
	_update_terminal()
	while terminal.is_empty():
		var id:int=timeline.next_actor(actors)
		if id<0:break
		timeline.now=int(timeline.ready[id])
		if id==1:break
		_automatic(actor(id))
		_update_terminal()
	if history.size()>100:history=history.slice(history.size()-100)
	if decisions.size()>100:decisions=decisions.slice(decisions.size()-100)
	return {"accepted":true,"reason":"ok","turn":turn,"terminal":terminal}

func _execute(source:Dictionary,kind:String,target_id:int,destination:Vector2i)->Dictionary:
	var target:=actor(target_id)
	var description:=""
	var prior_hp:=int(target.get("hp",0))
	var prior_barrier:=int(target.get("barrier",0))
	if kind in Skills.SKILLS:
		var assessment:=preview(source.id,kind,target_id)
		if not assessment.accepted:return assessment
		var injury:Dictionary=body_bridge.plan(source,target,kind,mini(int(target.hp),maxi(0,int(assessment.damage)-int(target.barrier))),seed,timeline.now)
		if not injury.accepted:return injury
		body_bridge.commit(injury)
		source.energy-=assessment.cost
		if int(assessment.damage)>0:_damage(target,int(assessment.damage))
		if int(assessment.barrier)>0:
			target.barrier=assessment.barrier;target.barrier_actions=2
		if int(assessment.healing)>0:
			target.hp+=assessment.healing;target.recoverable-=assessment.healing
		if kind=="SHOVE" and int(target.hp)>0:target.position=assessment.destination
		description=str(Skills.SKILLS[kind].name)
		if int(assessment.damage)>0:description+=" · 피해 %d / 흡수 %d"%[prior_hp-int(target.hp),prior_barrier-int(target.barrier)]
		if int(assessment.healing)>0:description+=" · 회복 %d"%assessment.healing
		if int(assessment.barrier)>0:description+=" · 보호 %d"%assessment.barrier
		if kind=="SHOVE":description+=" · 밀치기"
		description+=" (-%d 기력)"%assessment.cost
	elif kind=="ATTACK":
		if target.is_empty() or target.team==source.team or int(target.hp)<=0 \
				or distance(source.position,target.position)>1 \
				or not Effects.clear_line(source.position,target.position,blocked):return {"accepted":false,"reason":"인접한 적을 선택하세요."}
		var power:int=basic_power(source)
		var injury:Dictionary=body_bridge.plan(source,target,kind,mini(int(target.hp),maxi(0,power-int(target.barrier))),seed,timeline.now)
		if not injury.accepted:return injury
		body_bridge.commit(injury)
		_damage(target,power);description="기본 공격 · 피해 %d / 흡수 %d"%[prior_hp-int(target.hp),prior_barrier-int(target.barrier)]
	elif kind=="MOVE":
		if distance(source.position,destination)!=1 or not BOUNDS.has_point(destination) \
				or blocked.has(destination) or not actor_at(destination).is_empty() \
				or not Effects.clear_line(source.position,destination,blocked):return {"accepted":false,"reason":"이동 가능한 인접 칸을 선택하세요."}
		source.position=destination;description="이동"
	elif kind=="WAIT":description="대기"
	else:return {"accepted":false,"reason":"알 수 없는 행동입니다."}
	source.last_action=description
	source.last_reason=""
	source.last_target=str(target.name) if not target.is_empty() else ""
	history.append("[T%d] %s%s: %s · 소요 %d"%[timeline.now,source.name," → "+source.last_target if not source.last_target.is_empty() else "",description,timeline.duration(source,kind)])
	timeline.complete(source,kind)
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
	var selected:Dictionary=choose_action(source)
	decisions.append({"actor_id":source.id,"kind":selected.kind,"target":selected.target,"score":selected.score,"reason":selected.get("reason","")})
	_execute(source,str(selected.kind),int(selected.target),selected.position)
	source.last_reason=str(selected.get("reason",""))
	if not source.last_reason.is_empty():history[-1]+=" · 판단: "+source.last_reason

## Pure decision query shared with offline balance experiments.
func choose_action(source:Dictionary)->Dictionary:
	return TacticalSelector.choose(self,source)

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
