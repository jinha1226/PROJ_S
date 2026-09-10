extends RefCounted
const LIMBS:=["LEFT_ARM","RIGHT_ARM","LEFT_LEG","RIGHT_LEG"]
static var _world_ref:WeakRef
static var _count:=0
static var _tail
static var _enabled:=false
static func enabled(world)->bool:
	if world.party_encounter==null:return false
	if _world_ref==null or _world_ref.get_ref()!=world or _count>world.events.size() \
			or (_count>0 and _tail!=world.events[_count-1]):
		_world_ref=weakref(world);_count=0;_tail=null;_enabled=false
	for i in range(_count,world.events.size()):
		var event=world.events[i]
		if event.type=="town.guild_tutorial_accepted" and event.actor_id==world.party_encounter.protagonist_id \
				and event.data.get("quest_id","") in ["GUILD_TUTORIAL_INJURY","GUILD_TUTORIAL_TREAT"]:
			_enabled=true
	_count=world.events.size();_tail=world.events[-1] if _count>0 else null
	return _enabled
static func record_injury(world,injury:Dictionary,source)->bool:
	if not injury.get("mutated",false) or injury.get("part_id","") not in LIMBS:return true
	if world.party_encounter==null or source.target_id!=world.party_encounter.protagonist_id \
			or source.instigator_id not in world.party_encounter.enemy_ids or not enabled(world):return true
	return world.emit_event("guild.tutorial_limb_injured",source.target_id,source.target_id,source.position,1,source.id,
		{"part_id":str(injury.part_id),"condition":str(injury.condition)})!=null
static func injured_parts(body)->Array[String]:
	var result:Array[String]=[]
	if body==null:return result
	for part in body.parts:
		if part.part_id not in LIMBS:continue
		var damaged:bool=part.condition=="DISABLED"
		for layer in part.layers:
			if part.condition!="SEVERED" and int(layer.integrity)<1000:damaged=true
		for wound in body.wounds:
			if wound.part_id==part.part_id and (int(wound.severity)>0 or int(wound.bleeding)>0):damaged=true
		if damaged:result.append(str(part.part_id))
	return result
