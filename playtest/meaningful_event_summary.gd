extends RefCounted

## Presentation only: preserve recorded wording, select one recent action and its
## important consequence/reaction. Never mix an old fight into a newer loot turn.
static func summarize(history:Dictionary,message_for:Callable,is_filler:Callable,notice:String="")->String:
	var groups:Variant=history.get("groups",[])
	if not groups is Array:return notice
	var newest:Array=[]
	var newest_step:=-1
	for group in groups:
		if not group is Dictionary or not group.get("rows",[]) is Array:continue
		var candidates:Array=[]
		var seen:Dictionary={}
		for row in group.rows:
			if not row is Dictionary:continue
			var message:String=str(message_for.call(row)).replace("\n"," ").strip_edges()
			if message.is_empty() or is_filler.call(message) or seen.has(message):continue
			seen[message]=true
			var kind:String=str(row.get("type",""))
			var category:=0
			var priority:=0
			if kind in ["entity.died","entity.downed","entity.recovered","party.rescue_completed"]:
				category=1;priority=100
			elif kind.begins_with("body.") or kind.begins_with("status.") or kind.begins_with("environment."):
				category=1;priority=50
			elif kind.begins_with("enemy.") or kind.begins_with("party.assist") or kind=="party.rescue_dialogue":
				category=2;priority=40
			elif kind.begins_with("combat."):priority=60
			elif kind.begins_with("action."):priority=30
			else:priority=20
			if kind in ["action.move","action.hold","action.wait","environment.fuel_consumed"]:continue
			candidates.append({"message":message,"category":category,"priority":priority,"order":candidates.size()})
		if candidates.is_empty():continue
		var step:int=int(group.get("step_index",0))
		if newest.is_empty() or step>=newest_step:newest=candidates;newest_step=step
	if newest.is_empty():return notice
	var selected:Array=[]
	for category in range(3):
		var best:Dictionary={}
		for row in newest:
			if row.category==category and (best.is_empty() or row.priority>best.priority):best=row
		if not best.is_empty():selected.append(best)
	# Fill missing roles with useful facts from the same turn, not old events.
	for row in newest:
		if selected.size()>=3:break
		if not selected.has(row):selected.append(row)
	selected.sort_custom(func(a,b):return a.category<b.category if a.category!=b.category else a.order<b.order)
	var lines:Array[String]=[]
	for row in selected:lines.append(row.message)
	if not notice.is_empty():lines.push_front(notice)
	return "\n".join(lines.slice(0,3))
