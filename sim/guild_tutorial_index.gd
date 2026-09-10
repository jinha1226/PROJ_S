extends RefCounted
## Disposable presentation/progression index. Only appended events are consumed.
var count:=0
var tail
var hero:=-1
var floor_index:=0
var expedition:=0
var in_dungeon:=false
var quests:Dictionary={}
var origins:Dictionary={}
var seen_items:Dictionary={}

func observe(events:Array,hero_id:int,enemies:Array,definitions:Array)->Dictionary:
	if hero!=hero_id or count>events.size() or (count>0 and tail!=events[count-1]):
		count=0;tail=null;hero=hero_id;floor_index=0;expedition=0;in_dungeon=false
		quests.clear();origins.clear();seen_items.clear()
	for d in definitions:
		if not quests.has(d.quest_id):quests[d.quest_id]={"accepted":false,"claimed":false,"support":false,
			"count":0,"diagonal":false,"hold":false,"attack":false,"loot":{},"limbs":{},"complete":false}
	for i in range(count,events.size()):_consume(events[i],enemies)
	count=events.size();tail=events[-1] if count>0 else null
	var rows:Array=[]
	for d in definitions:
		var q:Dictionary=quests[d.quest_id];var row:Dictionary=d.duplicate(true)
		var target:=3 if d.quest_id.ends_with("MOVE") else 2 if d.quest_id.ends_with("GUARD") else 1
		row.merge({"status":"CLAIMED" if q.claimed else "COMPLETED" if q.complete else "ACTIVE" if q.accepted else "AVAILABLE",
			"accepted":q.accepted,"claimed":q.claimed,"completed":q.complete,"support_granted":q.support,
			"can_accept":not q.accepted,"can_claim":q.complete and not q.claimed,
			"progress":{"count":q.count,"target":target,"diagonal":q.diagonal,"hold_done":q.hold,
				"attack_done":q.attack,"complete":q.complete,"floor_index":floor_index,"expedition_index":expedition}})
		row.progress["injured_parts"]=q.limbs.keys()
		rows.append(row)
	return {"schema_version":1,"ruleset_id":"guild-tutorial-v2","campaign_id":"GUILD_TUTORIAL_CAMPAIGN_V1","quests":rows}

func _consume(event,enemies:Array)->void:
	var type:String=event.type;var data:Dictionary=event.data
	if event.actor_id==hero and type=="town.expedition_departed":
		in_dungeon=true;floor_index=int(data.get("floor_index",1));expedition=int(data.get("expedition_index",0))
	elif event.actor_id==hero and type=="dungeon.floor_entered" and in_dungeon:
		floor_index=int(data.get("floor_index",floor_index))
	# Only newly generated dungeon drops have a reward origin. Starting gear,
	# purchased items and player-discarded gear are not authored floor rewards.
	if type=="corpse.loot_materialized" and in_dungeon:
		for key in ["generated_items","generated_reward_items"]:
			for item in data.get(key,[]):origins[str(item.instance_id)]={"floor":floor_index,"expedition":expedition}
	if event.actor_id!=hero:return
	if type.begins_with("town.guild_tutorial_") and data.get("campaign_id","")=="GUILD_TUTORIAL_CAMPAIGN_V1":
		var id:String=data.get("quest_id","")
		if quests.has(id):
			if type=="town.guild_tutorial_accepted":quests[id].accepted=true
			elif type=="town.guild_tutorial_support_granted":quests[id].support=true
			elif type=="town.guild_tutorial_reward_claimed":quests[id].claimed=true
		return
	var new_loot:=false
	if in_dungeon and floor_index==1:
		if type=="base.resource_gathered" and event.magnitude>0:new_loot=true
		elif type=="item.picked_up":
			var id:String=data.get("instance_id","");var origin:Dictionary=origins.get(id,{})
			new_loot=not seen_items.has(id) and origin.get("floor",0)==1 and origin.get("expedition",0)==expedition
	if type=="item.picked_up":seen_items[str(data.get("instance_id",""))]=true
	for id in quests:
		var q:Dictionary=quests[id]
		if not q.accepted or q.claimed or q.complete:continue
		if type=="guild.tutorial_limb_injured" and event.target_id==hero:
			q.limbs[str(data.part_id)]=true
			if id.ends_with("INJURY"):q.count=1;q.complete=true
		if id.ends_with("TREAT") and type=="guild.tutorial_limb_treated" and event.target_id==hero:
			for part in data.get("part_ids",[]):
				if q.limbs.has(str(part)):q.count=1;q.complete=true
		if id.ends_with("BIND") and type=="party.ability_bound" and event.target_id==hero:
			q.count=1;q.complete=true
		elif id.ends_with("SKILL") and in_dungeon and type=="action.skill":
			q.count=1;q.complete=true
		elif id.ends_with("UPGRADE") and not in_dungeon and type=="weapon.recrafted" and event.target_id==hero:
			q.count=1;q.complete=true
		if new_loot:q.loot[expedition]=true
		if id.ends_with("RETURN") and type=="dungeon.expedition_returned":
			if in_dungeon and q.loot.has(int(data.get("expedition_index",-1))):q.count=1;q.complete=true
			continue
		if not in_dungeon or floor_index!=1:continue
		if id.ends_with("MOVE") and type=="action.move":
			var a:Variant=data.get("from_position",[]);var b:Variant=data.get("to_position",[])
			if a is Array and b is Array and a.size()==2 and b.size()==2:
				var dx:=absi(int(a[0])-int(b[0]));var dy:=absi(int(a[1])-int(b[1]))
				if maxi(dx,dy)==1:
					q.count=mini(3,int(q.count)+1);q.diagonal=q.diagonal or (dx==1 and dy==1)
					q.complete=q.count==3 and q.diagonal
		elif id.ends_with("GUARD"):
			if type=="action.hold":q.hold=true
			if type=="action.melee_attack" and event.target_id in enemies and data.get("outcome","") in ["HIT","FINISHER"]:q.attack=true
			q.count=int(q.hold)+int(q.attack);q.complete=q.count==2
		elif id.ends_with("HEAL") and type=="health.restored" and event.target_id==hero and event.magnitude>0 and data.get("kind","")=="POTION":q.count=1;q.complete=true
		elif id.ends_with("LOOT") and new_loot:q.count=1;q.complete=true
	if type in ["dungeon.expedition_returned","party.expedition_auto_returned"]:in_dungeon=false;floor_index=0
