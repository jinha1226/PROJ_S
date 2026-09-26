extends RefCounted
## Effect stacks use the session clock and explicit expiry boundaries.
static func count(actor: Dictionary, key: String, now: int = 0) -> int:
	var row: Dictionary = actor.get("stacks",{}).get(key,{})
	if row.is_empty(): return 0
	if int(row.get("expires",-1)) >= 0 and int(row.expires) <= now:
		clear(actor,key); return 0
	return int(row.get("n",0))

static func add(actor: Dictionary, key: String, amount: int, cap: int, until: Variant, now: int) -> int:
	var n := clampi(count(actor,key,now)+amount,0,cap)
	actor.stack_serial = int(actor.get("stack_serial",0))+1
	actor.get_or_add("stacks",{})[key] = {"n":n,"until":until,"generation":int(actor.stack_serial),"expires":now+int(until) if until is float or until is int else -1}
	return n

static func clear(actor: Dictionary, key: String) -> void:
	actor.get("stacks",{}).erase(key)

static func expire(actor: Dictionary, boundary: String, now: int) -> void:
	for key in actor.get("stacks",{}).keys():
		count(actor,str(key),now)
		if str(actor.get("stacks",{}).get(key,{}).get("until","")) == boundary: clear(actor,str(key))

static func reset(actor: Dictionary) -> void:
	actor.stacks = {}
