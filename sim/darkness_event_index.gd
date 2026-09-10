extends RefCounted
const ACTIVATION := "darkness.rules_activated"
const EXPOSURE := "darkness.exposure_changed"

static func sync(world)->Dictionary:
	var cache:Dictionary=world.darkness_event_cache
	var count:int=world.events.size()
	if cache.is_empty() or int(cache.get("count",0))>count \
			or (int(cache.get("count",0))>0 and cache.get("tail")!=world.events[int(cache.count)-1]):
		cache={"count":0,"tail":null,"enabled":false,"latest":{}}
	for i in range(int(cache.count),count):
		var event=world.events[i]
		if event.type==ACTIVATION:cache.enabled=true
		elif event.type==EXPOSURE:cache.latest[int(event.actor_id)]=event
	cache.count=count;cache.tail=world.events[-1] if count>0 else null
	world.darkness_event_cache=cache
	return cache

static func enabled(world)->bool:
	return world!=null and bool(sync(world).enabled)

static func latest(world,id:int):
	return sync(world).latest.get(id)
