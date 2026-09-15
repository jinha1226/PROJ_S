extends RefCounted

## Rates are percentages: 100 is normal, 200 is twice as fast. Movement,
## attacks and spellcasting remain independent; waiting has no speed bonus.
static func duration(world,actor_id:int,kind:String,base:int,before:int=-1)->int:
	if not preload("res://sim/field_turn_rules.gd").enabled(world):return base
	if kind=="MOVE":base+=preload("res://sim/abilities/monster_ability_runtime.gd").move_delay(world,actor_id)
	var member=world.party_encounter.member(actor_id)
	if member==null or kind=="HOLD":return base
	var channel:="MOVE" if kind=="MOVE" else "ATTACK" if kind in ["MELEE","STRIKE","SHOVE"] else "CAST"
	var rate:int=maxi(25,int(member.action_speeds[channel])+preload("res://sim/consumable_effects.gd").rate(world,actor_id,before))
	return maxi(1,int((base*100+rate-1)/rate))
