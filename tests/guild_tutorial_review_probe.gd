extends SceneTree
## Read-only rule-level review probes; no live world mutation or game fixes.
const Rules=preload("res://sim/guild_tutorial_rules.gd")
const Event=preload("res://sim/sim_event.gd")
var failures:Array[String]=[]
func e(id:int,type:String,data:Dictionary={}):
	return Event.new(id,0,id,type,7,-1,Vector2i(1,1),1,-1,7,data)
func acceptance(quest:String):
	return e(1,Rules.EVENT_ACCEPTED,{"campaign_id":Rules.CAMPAIGN_ID,"quest_id":quest})
func check(value:bool,label:String):
	if not value:failures.append(label);print("FAIL ",label)
	else:print("PASS ",label)
func _init():
	var rows:Array=[acceptance("GUILD_TUTORIAL_RETURN"),
		e(2,"town.expedition_departed",{"expedition_index":1,"floor_index":1}),
		e(3,"base.resource_gathered",{"floor_index":1}),
		e(4,"dungeon.floor_entered",{"expedition_index":1,"floor_index":2}),
		e(5,"dungeon.expedition_returned",{"expedition_index":1})]
	check(Rules.state(rows,7,[]).quests[4].completed,"floor-one loot then deeper-floor return completes")
	rows=[acceptance("GUILD_TUTORIAL_LOOT"),
		e(2,"town.expedition_departed",{"expedition_index":1,"floor_index":1}),
		e(3,"item.dropped",{"instance_id":"START_POTION_001"}),
		e(4,"item.picked_up",{"instance_id":"START_POTION_001"})]
	check(not Rules.state(rows,7,[]).quests[3].completed,"re-picking starting gear does not count as new loot")
	rows=[acceptance("GUILD_TUTORIAL_MOVE"),e(2,"action.move",{"from_position":[1,1],"to_position":[2,2]}),
		e(3,"action.move",{"from_position":[2,2],"to_position":[3,2]}),
		e(4,"action.move",{"from_position":[3,2],"to_position":[4,2]})]
	check(not Rules.state(rows,7,[]).quests[0].completed,"movement without any expedition is excluded")
	print("GUILD REVIEW: ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
