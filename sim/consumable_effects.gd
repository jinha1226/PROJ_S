extends RefCounted
const Catalog=preload("res://sim/consumable_catalog.gd")
const DURATIONS={"HASTE":600,"ARMOR":600,"REGEN":500,"POISON":400,"SLOW":500,"WEAK":500,"FEAR":400,"SEAL":500,"CONFUSION":400,"NOISE":500}
const BAD=["POISON","SLOW","WEAK","CONFUSION"]
static func projection(w)->Dictionary:
	var p:Dictionary=w.get_meta("consumable_effect_cache",{})
	if p.is_empty() or p.cursor>w.events.size() or (p.cursor>0 and p.tail!=w.events[p.cursor-1]):
		p={"cursor":0,"tail":null,"statuses":{},"clears":{}}
	for i in range(p.cursor,w.events.size()):
		var e=w.events[i]
		if e.type=="consumable.status":p.statuses["%d:%s"%[e.target_id,e.data.effect]]=e
		if e.type=="consumable.cleansed":p.clears[e.target_id]=e.id
	p.cursor=w.events.size();p.tail=w.events.back() if not w.events.is_empty() else null
	w.set_meta("consumable_effect_cache",p);return p
static func status(w,id:int,key:String,before:int=-1):
	var e=null;var clear:=-1;var now:int=w.world_time
	if before<0:
		var p:=projection(w);e=p.statuses.get("%d:%s"%[id,key]);clear=int(p.clears.get(id,-1))
	else:
		var boundary=w.event_by_id(before)
		if boundary!=null:now=boundary.world_time
		for row in w.events:
			if row.id>=before:break
			if row.target_id!=id:continue
			if row.type=="consumable.status" and row.data.effect==key:e=row
			if row.type=="consumable.cleansed":clear=row.id
	return e if e!=null and int(e.data.until)>now and (key not in BAD or clear<e.id) else null
static func rate(w,id:int,before:int=-1)->int:
	return (50 if status(w,id,"HASTE",before)!=null else 0)-(35 if status(w,id,"SLOW",before)!=null else 0)
static func accuracy(w,id:int,before:int=-1)->int:
	return (-200 if status(w,id,"WEAK",before)!=null else 0)+(-250 if status(w,id,"CONFUSION",before)!=null else 0)
static func armor(w,id:int)->int:
	return (5 if status(w,id,"ARMOR")!=null else 0)-(3 if status(w,id,"WEAK")!=null else 0)
static func skill_blocked(w,id:int)->bool:return status(w,id,"SEAL")!=null or status(w,id,"CONFUSION")!=null
static func summary(w,id:int)->String:
	var parts:Array[String]=[]
	var labels={"HASTE":"가속","ARMOR":"경화","REGEN":"재생","POISON":"독","SLOW":"둔화","WEAK":"쇠약","FEAR":"공포","SEAL":"봉인","CONFUSION":"혼란"}
	for key in labels:
		var e=status(w,id,key)
		if e!=null:parts.append("%s %d"%[labels[key],ceili(float(int(e.data.until)-w.world_time)/100.0)])
	return " · ".join(parts)
static func add(w,actor:int,target:int,effect:String,cause:int)->bool:
	return w.emit_event("consumable.status",actor,target,w.entities[target].position,1,cause,{"schema_version":1,"effect":effect,"until":str(w.world_time+int(DURATIONS[effect]))})!=null
static func tick(sim,start:int,end:int)->bool:
	var w=sim.world;var runtime=load("res://sim/abilities/monster_ability_runtime.gd")
	var p:=projection(w)
	for s in p.statuses.values().duplicate():
		var key:String=s.data.effect
		if key not in ["POISON","REGEN"] or not runtime.alive(w,s.target_id):continue
		if key=="POISON" and int(p.clears.get(s.target_id,-1))>s.id:continue
		var stop:int=mini(end,int(s.data.until))
		var ticks:int=maxi(0,(stop-s.world_time)/100-maxi(0,(start-s.world_time)/100))
		for n in range(mini(5,ticks)):
			var entity=w.entities[s.target_id]
			var amount:int=mini(4,maxi(0,entity.health-1)) if key=="POISON" else mini(6,entity.max_health-entity.health)
			if amount<=0:continue
			var pulse=w.emit_event("consumable.pulse",s.actor_id,s.target_id,entity.position,amount,s.id,{"schema_version":1,"effect":key})
			if pulse==null or runtime.impact(sim,s.actor_id,s.target_id,"VENOM_FANG" if key=="POISON" else "REGENERATIVE_TISSUE",amount,"physical" if key=="POISON" else "HEAL",pulse.id)<0:return false
	return true
static func event_error(w,e)->String:
	if not str(e.type).begins_with("consumable."):return ""
	var source=w.event_by_id(e.cause_id)
	if source==null or source.id>=e.id or e.data.get("schema_version")!=1 or not w.entities.has(e.actor_id) or not w.entities.has(e.target_id):return "consumable_event_source"
	if e.type=="consumable.activated":
		if source.type!="item.used" or source.actor_id!=e.actor_id or e.world_time!=source.world_time or e.step_index!=source.step_index:return "consumable_activation_source"
		if not Catalog.SPECS.has(str(source.data.get("definition_id",""))) or e.data.get("definition_id")!=source.data.definition_id or e.data.size()!=3 or not e.data.get("selection") is Dictionary:return "consumable_activation_data"
		return ""
	if e.type=="consumable.pulse":
		if source.type!="consumable.status" or source.data.effect!=e.data.get("effect") or e.actor_id!=source.actor_id or e.target_id!=source.target_id or e.magnitude<1 or e.magnitude>(4 if e.data.effect=="POISON" else 6):return "consumable_pulse_invalid"
		return ""
	if source.type!="consumable.activated" or source.actor_id!=e.actor_id or source.world_time!=e.world_time or source.step_index!=e.step_index:return "consumable_effect_source"
	var effect:String=Catalog.definition(str(source.data.definition_id)).get("effect","")
	match str(e.type):
		"consumable.status":
			if e.data.get("effect")!=effect or not DURATIONS.has(effect) or e.data.get("until")!=str(e.world_time+int(DURATIONS[effect])) or e.magnitude!=1:return "consumable_status_invalid"
		"consumable.cleansed":
			if effect!="CLEANSE" or e.target_id!=source.target_id:return "consumable_cleanse_invalid"
		"consumable.map":
			if effect!="MAP" or e.magnitude!=10:return "consumable_map_invalid"
		_:return "unknown_consumable_event"
	return ""
static func move_error(w,e)->String:
	var source=w.event_by_id(e.cause_id)
	if source==null or source.type!="consumable.activated" or not event_error(w,source).is_empty():return "consumable_move_source"
	var effect:String=Catalog.definition(source.data.definition_id).effect
	if effect not in ["BLINK","TELEPORT","PUSH"] or e.world_time!=source.world_time or e.step_index!=source.step_index or e.data.get("move_time_cost")!=1:return "consumable_move_invalid"
	var from:Vector2i=Vector2i(e.data.from_position[0],e.data.from_position[1])
	if maxi(absi(from.x-e.position.x),absi(from.y-e.position.y))>(2 if effect=="PUSH" else 5):return "consumable_move_range"
	return ""
