extends RefCounted

## Same rules for every faction and actor; no player ID or terminal knowledge.
static func incoming(model,target:Dictionary)->float:
	var total:float=0.0
	for foe in model.actors:
		if foe.team==target.team or int(foe.hp)<=0:continue
		total+=threat(model,foe,target)
	return total

static func threat(model,foe:Dictionary,target:Dictionary)->float:
	var horizon:int=model.timeline.now+model.timeline.duration(target,"WAIT")
	if int(model.timeline.ready.get(int(foe.id),horizon+1))>horizon:return 0.0
	var amount:float=0.0
	var distance:int=model.distance(foe.position,target.position)
	if model.Effects.clear_line(foe.position,target.position,model.blocked):
		if distance<=1:amount=float(model.basic_power(foe))
		elif distance==2:amount=float(model.basic_power(foe))*0.35
	for kind in foe.skills:
		if not model.body_bridge.use_error(foe,str(kind)).is_empty():continue
		var check:Dictionary=model.Effects.assess(str(kind),foe,target,model.actors,model.blocked,model.BOUNDS)
		if check.accepted:amount=maxf(amount,float(check.damage))
	return amount

static func choose(model,source:Dictionary)->Dictionary:
	var options:Array=[]
	var risks:Dictionary={}
	for ally in model.actors:
		if ally.team==source.team and int(ally.hp)>0:risks[int(ally.id)]=incoming(model,ally)
	var support:float=0.85+float(source.profile.A)/2000.0
	var reserve:float=1.0+float(source.profile.C)/500.0
	for target in model.actors:
		if int(target.hp)<=0:continue
		for kind in ["ATTACK"]+source.skills:
			var effect:Dictionary={}
			if kind=="ATTACK":
				if target.team==source.team or model.distance(source.position,target.position)>1 or not model.Effects.clear_line(source.position,target.position,model.blocked):continue
				effect={"damage":model.basic_power(source),"healing":0,"barrier":0,"cost":0}
			else:
				effect=model.preview(int(source.id),str(kind),int(target.id))
				if not effect.accepted:continue
			var score:float=0.0
			var reason:String="공격"
			if int(effect.damage)>0:
				var effective:float=maxf(0.0,float(effect.damage)-float(target.barrier))
				score=minf(effective,float(target.hp))+minf(float(effect.damage),float(target.barrier))*0.5
				# Finishing a threat protects whoever it can hurt, not just a leader.
				if effective>=float(target.hp):
					score+=12.0
					for ally in model.actors:
						if ally.team!=source.team or int(ally.hp)<=0:continue
						var danger:float=threat(model,target,ally)
						score+=danger*0.35*(2.0 if danger>=int(ally.hp)+int(ally.barrier) else 1.0)
					reason="위협 처치"
				if kind=="SHOVE":
					var displaced:Dictionary=target.duplicate(true);displaced.position=effect.destination
					for ally in model.actors:
						if ally.team!=source.team or int(ally.hp)<=0:continue
						score+=maxf(0.0,threat(model,target,ally)-threat(model,displaced,ally))*support
					reason="밀어내기"
			else:
				var danger:float=float(risks.get(int(target.id),0.0))
				var hp:float=float(target.hp)
				var exposed:float=maxf(0.0,danger-float(target.barrier))
				var urgency:float=1.0+minf(2.0,exposed/maxf(1.0,hp))
				if int(effect.healing)>0:
					score=float(effect.healing)*support*urgency
					reason="위험 아군 치유" if exposed>0 else "부상 회복"
				if int(effect.barrier)>0:
					# Only credit the replacement's additional, threatened absorption.
					score=minf(maxf(0.0,float(effect.barrier)-float(target.barrier)),exposed)*support*urgency
					reason="위험 아군 보호"
			score=(score-float(effect.cost)*reserve)*100.0/model.timeline.duration(source,str(kind))
			options.append({"kind":str(kind),"target":int(target.id),"position":Vector2i(-1,-1),"score":score,"reason":reason,"tie_cell":target.position})
	# Pick approach targets by distance, then a seeded spatial tie-break, never ID.
	var foes:Array=[]
	for target in model.actors:
		if target.team!=source.team and int(target.hp)>0:
			foes.append({"target":target,"distance":model.distance(source.position,target.position),"tie":tie(model,source,"APPROACH",target.position)})
	foes.sort_custom(func(a,b):return a.distance<b.distance if a.distance!=b.distance else a.tie<b.tie)
	for entry in foes:
		var next:Vector2i=model._next_step(source.position,entry.target.position)
		if next==source.position:continue
		options.append({"kind":"MOVE","target":-1,"position":next,"score":8.0*100/model.timeline.duration(source,"MOVE"),"reason":"접근","tie_cell":next});break
	options.append({"kind":"WAIT","target":-1,"position":Vector2i(-1,-1),"score":0.0,"reason":"대기","tie_cell":source.position})
	for option in options:option.tie=tie(model,source,str(option.kind),option.tie_cell)
	options.sort_custom(func(a,b):
		if a.score!=b.score:return a.score>b.score
		if a.tie!=b.tie:return a.tie<b.tie
		if a.kind!=b.kind:return a.kind<b.kind
		return a.tie_cell.y<b.tie_cell.y if a.tie_cell.y!=b.tie_cell.y else a.tie_cell.x<b.tie_cell.x)
	return options[0]

static func tie(model,source:Dictionary,kind:String,cell:Vector2i)->int:
	# Small integer hash, stable under actor renumbering and array reordering.
	var value:int=int(model.seed)*73856093+int(model.timeline.now)*19349663
	value^=int(source.position.x)*83492791+int(source.position.y)*2971215073
	value^=cell.x*961748941+cell.y*982451653+int(kind.hash())
	value=(value^(value>>16))*73244475
	return (value^(value>>16))&0x7fffffff
