extends RefCounted

const SITES={
	"TIMBER":{"label":"벌목","tile":[0,5],"supply":24,"steps":8},
	"STONE":{"label":"채석","tile":[15,11],"supply":18,"steps":10},
	"HERBS":{"label":"약초 채집","tile":[0,11],"supply":12,"steps":8},
}

static func remaining(world,resource:String)->int:
	var cache:Dictionary=world.get_meta("settlement_gathering_index",{})
	if cache.is_empty() or int(cache.cursor)>world.events.size() or (int(cache.cursor)>0 and cache.tail!=world.events[int(cache.cursor)-1]):
		cache={"cursor":0,"tail":null,"taken":{"TIMBER":0,"STONE":0,"HERBS":0},"banked":{"TIMBER":0,"STONE":0,"HERBS":0}}
	for n in range(int(cache.cursor),world.events.size()):
		var event=world.events[n]
		if event.type=="base.local_resource_harvested":cache.taken[str(event.data.resource_id)]+=int(event.data.amount)
		if event.type=="base.local_resource_deposited":cache.banked[str(event.data.resource_id)]+=int(event.data.amount)
	cache.cursor=world.events.size();cache.tail=world.events[-1] if not world.events.is_empty() else null
	world.set_meta("settlement_gathering_index",cache)
	return maxi(0,int(SITES[resource].supply)-int(cache.taken[resource]))

static func audit(world,value:Dictionary)->String:
	remaining(world,"TIMBER")
	var cache:Dictionary=world.get_meta("settlement_gathering_index")
	var cargo:Dictionary={"TIMBER":0,"STONE":0,"HERBS":0}
	for job in value.jobs.values():
		if str(job.action)!="GATHER":continue
		if job.resource_id not in SITES or int(job.cargo)<0 or int(job.cargo)>1:return "settlement_gather_cargo_invalid"
		if int(job.cargo)>0 and (not bool(job.materials_reserved) or str(job.material_location) not in ["CARRIED","RECOVERY"]):return "settlement_gather_location_invalid"
		cargo[str(job.resource_id)]+=int(job.cargo)
	for resource in SITES:
		if int(cache.taken[resource])>int(SITES[resource].supply) or int(cache.taken[resource])!=int(cache.banked[resource])+int(cargo[resource]):return "settlement_gather_conservation_failed"
	return ""
