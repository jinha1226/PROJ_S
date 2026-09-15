extends RefCounted
## Derived only; never serialized. Events are immutable after commit. A load,
## truncation or replacement tail rebuilds the index before any answer is used.
static func sync(world)->Dictionary:
	var cache:Dictionary=world.runtime_history_cache
	var count:int=world.events.size()
	if cache.is_empty() or not cache.has("assist_links") or int(cache.count)>count \
			or int(cache.count)>0 and cache.tail!=world.events[int(cache.count)-1]:
		cache={"count":0,"tail":null,"latest":{},"first":{},"rescues":{},"assist_links":{},"deaths":{},"morale":{},"commands":[],"first_contact":-1}
	for i in range(int(cache.count),count):
		var event=world.events[i]
		if str(event.type) in ["party.regroup_completed","party.disengage_completed",
				"dungeon.expedition_returned","party.expedition_auto_returned"]:
			cache.commands.clear()
		elif str(event.type) in ["party.command_issued","party.actor_command_issued"]:
			cache.commands.append(event)
		match str(event.type):
			"party.rescue_enabled","party.rescue_completed","campaign.living_expedition_initialized","town.life_started":
				if not cache.first.has(str(event.type)):cache.first[str(event.type)]=event
			"party.assist_started":cache.assist_links[int(event.actor_id)]={"target":int(event.target_id),"source":int(event.id),"moved":false}
			"party.assist_moved":
				if cache.assist_links.has(int(event.actor_id)):cache.assist_links[int(event.actor_id)].moved=true
			"party.assist_ended":cache.assist_links.erase(int(event.actor_id))
			"party.rescue_discovered":
				if not cache.rescues.has(int(event.target_id)):cache.rescues[int(event.target_id)]=event
			"party.field_formation_selected","party.field_control_selected","party.regroup_completed","party.contact_reported":
				cache.latest[str(event.type)]=event
			"entity.died":cache.deaths[int(event.target_id)]=event
			"party.morale_changed":cache.morale[int(event.actor_id)]=event
			"encounter.detected","encounter.party_ambush","encounter.enemy_ambush":
				if int(cache.first_contact)<0:cache.first_contact=int(event.id)
	cache.count=count;cache.tail=world.events[-1] if count>0 else null
	world.runtime_history_cache=cache
	return cache
