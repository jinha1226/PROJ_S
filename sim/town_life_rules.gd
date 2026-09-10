extends RefCounted
## Event-derived campaign progression. Legacy saves have no START event.
const START_EVENT := "town.life_started"
const HOUSE_COST := 240
const REQUIRED_RETURNS := 2
# Hero plus two companions in the field.
const FIELD_LIMIT := 3
const BOUNTY := 80

static func field_count(world)->int:
	var count:=0
	for id in world.party_encounter.active_party_member_ids:
		var body=world.combatant_states.get(id)
		if body==null or body.life_state!="DEAD":count+=1
	return count

static func living_company_count(world)->int:
	var count:=0
	for id in state(world.events).members:
		if world.combatant_states[id].life_state!="DEAD" and world.party_encounter.member(id).presence!="EXILED":count+=1
	return count

static func state(events:Array)->Dictionary:
	var result:={"enabled":false,"house_owned":false,"members":[],"talks":{},
		"claimed":[],"visits":0,"start_expedition":0}
	for event in events:
		var data:Dictionary=event.data
		match str(event.type):
			START_EVENT:
				result.enabled=true;result.start_expedition=int(data.expedition_index)
				result.members=[int(data.founder_id)]
			"town.conversation","population.greeted","population.assisted":
				var key:=str(data.entity_id)
				if not result.talks.has(key):result.talks[key]=[]
				result.talks[key].append(int(data.expedition_index))
				if event.type=="population.assisted":result.talks[key].append(int(data.expedition_index))
			"town.company_joined":
				var id:=int(data.entity_id)
				if id not in result.members:result.members.append(id)
			"town.house_acquired":result.house_owned=true
			"town.expedition_reward":result.claimed.append(int(data.expedition_index))
			"town.guild_candidates_arrived":
				if result.enabled:result.visits+=1
	return result

static func enabled(events:Array)->bool:
	for event in events:
		if str(event.type)==START_EVENT:return true
	return false

static func house_available(events:Array)->bool:
	var value:=state(events)
	return not value.enabled or value.house_owned

static func successful_returns(events:Array)->Array[int]:
	# Only actual, banked salvage counts. Walking out and straight back cannot
	# generate renown or money. Works for manual and timed extraction alike.
	var gathered:Dictionary={};var returned:Dictionary={}
	for event in events:
		if str(event.type)=="base.resource_gathered":
			gathered[int(event.data.expedition_index)]=true
		elif str(event.type)=="dungeon.expedition_returned":
			returned[int(event.data.expedition_index)]=true
	var result:Array[int]=[]
	for index in returned:
		if gathered.has(index):result.append(index)
	result.sort();return result

static func operation_error(value:Variant)->String:
	if not value is Dictionary or not value.get("action") is String:return "invalid_town_life_operation"
	var keys:Array=value.keys();keys.sort()
	if value.action in ["START","CLAIM","ACQUIRE"]:
		return "" if keys==["action"] else "invalid_town_life_operation"
	if value.action not in ["TALK","JOIN","ASSIGN","RESERVE","REST"] or keys!=["action","entity_id"]:
		return "invalid_town_life_operation"
	var id:Variant=value.entity_id
	if not id is String or not id.is_valid_int() or str(int(id))!=id or int(id)<=0:
		return "invalid_town_life_entity"
	return ""
