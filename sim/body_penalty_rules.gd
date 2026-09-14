extends RefCounted
const TAG:="body_penalties_v1"
const EVENT:="body.penalties_changed"
const RECOVERY_RATES:={"SKIN":25,"SOFT_TISSUE":15,"BONE":8}
static func enabled(world)->bool:
	return world!=null and world.party_encounter!=null and world.entities.has(world.party_encounter.protagonist_id) and TAG in world.entities[world.party_encounter.protagonist_id].tags
static func grade(value:int,kind:String)->String:
	var low:=25 if kind in ["SKIN","MUSCLE"] else 70
	var high:=40 if kind in ["SKIN","MUSCLE"] else 100
	return "하" if value<low else "중" if value<high else "상"
static func part_stage(part:Dictionary)->int:
	if str(part.condition) in ["DISABLED","SEVERED"]:return 3
	var soft:=1000;var bone:=1000
	for layer in part.layers:
		if layer.layer_id=="SOFT_TISSUE":soft=int(layer.integrity)
		elif layer.layer_id=="BONE":bone=int(layer.integrity)
	return 2 if bone<=600 else 1 if soft<=700 else 0
static func stage_label(stage:int)->String:
	return ["정상","깊은 상처","골절","기능 상실"][clampi(stage,0,3)]
static func summary(body)->Dictionary:
	var attack:=1000;var move:=1000;var worst:=0
	if body!=null:
		for part in body.parts:
			var stage:=part_stage(part);worst=maxi(worst,stage)
			if part.part_id in ["LEFT_ARM","RIGHT_ARM"]:attack-=[0,100,250,250][stage]
			if part.part_id in ["LEFT_LEG","RIGHT_LEG"]:move+=[0,250,500,1000][stage]
	return {"attack_milli":maxi(500,attack),"move_milli":mini(3000,move),"recovery_milli":[1000,800,600,400][worst]}
static func current(world,id:int)->Dictionary:
	return summary(world.body_states.get(id)) if enabled(world) else summary(null)
static func scale_damage(world,id:int,amount:int,before:int=-1)->int:
	var values:=current(world,id) if before<0 else historical(world,id,before)
	return maxi(1,amount*int(values.attack_milli)/1000) if amount>0 else 0
static func move_cost(world,id:int,amount:int)->int:
	return maxi(1,(amount*int(current(world,id).move_milli)+999)/1000)
static func needs_recovery(body)->bool:
	if body==null:return false
	for part in body.parts:
		if part.condition=="SEVERED":continue
		for layer in part.layers:
			if int(layer.integrity)<1000:return true
	return false
static func heal_layers(body,pulses:int)->Array:
	var changes:Array=[]
	if body==null or pulses<=0:return changes
	for part in body.parts:
		if part.condition=="SEVERED":continue
		for layer in part.layers:
			var rate:int=RECOVERY_RATES[layer.layer_id]
			var amount:=mini(1000-int(layer.integrity),rate*pulses)
			if amount<=0:continue
			layer.integrity+=amount
			changes.append({"part_id":part.part_id,"layer_id":layer.layer_id,"amount":amount,"after":layer.integrity})
		if part.condition=="DISABLED" and int(part.layers[1].integrity)>700 and int(part.layers[2].integrity)>600:
			part.condition="FUNCTIONAL";part.condition_source_event_id=-1
	if not changes.is_empty():body.revision+=1
	return changes
static func record(world,id:int,cause:int)->bool:
	if not enabled(world):return true
	var values:=current(world,id)
	if values==historical(world,id,world.events.size()+1):return true
	return world.emit_event(EVENT,id,id,world.entities[id].position,0,cause,values)!=null
static func historical(world,id:int,before:int)->Dictionary:
	if not enabled(world):return summary(null)
	# Incremental event index; no full history scan per attack or frame.
	var cache:Dictionary=world.get_meta("body_penalty_history_v1",{})
	if cache.is_empty() or int(cache.cursor)>world.events.size() or (int(cache.cursor)>0 and cache.tail!=world.events[int(cache.cursor)-1]):
		cache={"cursor":0,"tail":null,"rows":{}}
	for i in range(int(cache.cursor),world.events.size()):
		var event=world.events[i]
		if event.type!=EVENT and event.type!="town.clinic_service":continue
		var actor:int=event.target_id
		if not cache.rows.has(actor):cache.rows[actor]=[]
		cache.rows[actor].append({"id":event.id,"values":event.data if event.type==EVENT else summary(null)})
	cache.cursor=world.events.size();cache.tail=world.events[-1] if not world.events.is_empty() else null
	world.set_meta("body_penalty_history_v1",cache)
	var rows:Array=cache.rows.get(id,[]);var low:=0;var high:=rows.size()
	while low<high:
		var mid:int=(low+high)/2
		if int(rows[mid].id)<before:low=mid+1
		else:high=mid
	return rows[low-1].values if low>0 else summary(null)
