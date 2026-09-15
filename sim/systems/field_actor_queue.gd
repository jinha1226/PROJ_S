extends RefCounted

const Heap=preload("res://game/rebuilt/min_heap.gd")
var heap=Heap.new()
var seeded:=false
var builds:=0
var member_count:=0
var enemy_count:=0

func rebuild(sim)->void:
	heap.clear();seeded=true;builds+=1
	var world=sim.world;var party=world.party_encounter
	member_count=party.active_party_member_ids.size();enemy_count=party.enemy_busy_rows.size()
	for id in party.active_party_member_ids:push_actor(sim,id)
	for id in sim.party_coordinator._stream_enemy_ids():push_actor(sim,id)

func ready_at(sim,id:int)->int:
	var world=sim.world;var party=world.party_encounter
	if id==world.party_control_actor_id() or party.safe_phase=="PARTY_DEFEATED" or not world.can_act(id,world.world_time):return -1
	var member=party.member(id)
	if member!=null:return maxi(world.world_time,member.busy_until) if member.presence=="DEPLOYED" else -1
	if not party.enemy_busy_rows.has(id):return -1
	return maxi(world.world_time,int(party.enemy_busy_rows[id]))

func push_actor(sim,id:int)->void:
	var at:=ready_at(sim,id)
	if at>=0:heap.push([at,id])

func next(sim,end:int)->Dictionary:
	if not seeded:rebuild(sim)
	var world=sim.world
	var scheduled:Dictionary={}
	if not world.scheduled_entries.is_empty() and int(world.scheduled_entries[0].due_time)<=end:
		scheduled={"at":int(world.scheduled_entries[0].due_time),"id":0}
	while not heap.empty():
		var row:Array=heap.rows[0]
		var at:=ready_at(sim,int(row[1]))
		if at<0:heap.pop();continue
		if at!=int(row[0]):heap.pop();heap.push([at,row[1]]);continue
		if at>=end:return scheduled
		if not scheduled.is_empty() and int(scheduled.at)<=at:return scheduled
		heap.pop();return {"at":at,"id":int(row[1])}
	return scheduled

func completed(sim,id:int)->void:
	# Environment cadence can spawn actors, revive or change multiple clocks.
	# Rebuild after it; ordinary actor actions update just that actor's entry.
	var party=sim.world.party_encounter
	if id==0 or member_count!=party.active_party_member_ids.size() or enemy_count!=party.enemy_busy_rows.size():rebuild(sim)
	else:push_actor(sim,id)
