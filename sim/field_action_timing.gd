extends RefCounted

## Rates are percentages: 100 is normal, 200 is twice as fast. Movement,
## attacks and spellcasting remain independent; waiting has no speed bonus.
static func duration(world,actor_id:int,kind:String,base:int)->int:
	if not preload("res://sim/field_turn_rules.gd").enabled(world):return base
	var member=world.party_encounter.member(actor_id)
	if member==null or kind=="HOLD":return base
	var channel:="MOVE" if kind=="MOVE" else "ATTACK" if kind in ["MELEE","STRIKE","SHOVE"] else "CAST"
	var rate:int=member.action_speeds[channel]
	return maxi(1,int((base*100+rate-1)/rate))
