class_name ActiveEffectModel
extends RefCounted

## Pure assessment. The caller owns authoritative execution, rollback and events.
## Actor contract: id/team/position/hp/max_hp/energy/skills plus optional defenses.
const Registry=preload("res://sim/abilities/active_skill_registry.gd")

static func assess(skill_id:String,caster:Dictionary,target:Dictionary,
		actors:Array,blocked:Dictionary,bounds:Rect2i)->Dictionary:
	var skill:=Registry.definition(skill_id)
	if skill.is_empty():return _reject("알 수 없는 기술입니다.")
	if caster.is_empty() or target.is_empty():return _reject("대상이 없습니다.")
	if int(caster.get("hp",0))<=0:return _reject("시전자가 행동할 수 없습니다.")
	if int(target.get("hp",0))<=0:return _reject("대상이 이미 쓰러졌습니다.")
	if skill_id not in caster.get("skills",[]):return _reject("장착하지 않은 기술입니다.")
	if int(caster.get("energy",0))<int(skill.cost):return _reject("기력이 부족합니다.")
	var allied:bool=caster.team==target.team
	if allied!=(str(skill.target)=="ALLY"):return _reject("대상 진영이 맞지 않습니다.")
	var origin:Vector2i=caster.position;var destination:Vector2i=target.position
	if not bounds.has_point(origin) or not bounds.has_point(destination):return _reject("맵 밖입니다.")
	var delta:=destination-origin
	if maxi(absi(delta.x),absi(delta.y))>int(skill.range):return _reject("사거리 밖입니다.")
	if not clear_line(origin,destination,blocked):return _reject("벽에 가려져 있습니다.")
	var result:={"accepted":true,"reason":"ok","skill_id":skill_id,
		"caster_id":caster.id,"target_id":target.id,"cost":int(skill.cost),
		"damage":0,"healing":0,"barrier":0,"destination":destination}
	match str(skill.effect):
		"DAMAGE","SHOVE":
			var resistance:int=clampi(int(target.get("resistances",{}).get(skill.element,0)),-25,75)
			var raw:int=maxi(1,int(skill.power)-int(target.get("armor",0))) \
				if skill.element=="PHYSICAL" else int(skill.power)
			result.damage=maxi(1,roundi(raw*(1.0-resistance/100.0)))
			if skill.effect=="SHOVE":
				var landing:=destination+Vector2i(signi(delta.x),signi(delta.y))
				if not bounds.has_point(landing) or blocked.has(landing):return _reject("밀어낼 빈칸이 없습니다.")
				for actor in actors:
					if int(actor.get("hp",0))>0 and actor.position==landing:return _reject("밀어낼 칸에 다른 인물이 있습니다.")
				if not clear_line(destination,landing,blocked):return _reject("모서리를 통과해 밀 수 없습니다.")
				result.destination=landing
		"BARRIER":
			if int(target.get("barrier",0))>=int(skill.power):return _reject("이미 충분한 보호막이 있습니다.")
			result.barrier=int(skill.power)
		"HEAL":
			result.healing=mini(int(skill.power),mini(int(target.max_hp)-int(target.hp),int(target.get("recoverable",0))))
			if int(result.healing)<=0:return _reject("응급 치유 가능한 피해가 없습니다.")
	return result

static func clear_line(origin:Vector2i,target:Vector2i,blocked:Dictionary)->bool:
	var current:=origin
	var dx:=absi(target.x-origin.x);var dy:=-absi(target.y-origin.y)
	var sx:=signi(target.x-origin.x);var sy:=signi(target.y-origin.y)
	var error:=dx+dy
	while current!=target:
		var next:=current;var twice:=2*error
		if twice>=dy:error+=dy;next.x+=sx
		if twice<=dx:error+=dx;next.y+=sy
		if next.x!=current.x and next.y!=current.y:
			if blocked.has(Vector2i(next.x,current.y)) or blocked.has(Vector2i(current.x,next.y)):return false
		if blocked.has(next):return false
		current=next
	return true

static func _reject(message:String)->Dictionary:
	return {"accepted":false,"reason":message}
