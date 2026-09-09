extends RefCounted
## Opt-in wall-clock probe for hot paths. Disabled by default: `begin()` returns
## 0 and `end()` returns immediately, so instrumented code pays one static
## bool read. Tests and probes enable it, run a workload, and print `report()`.
static var enabled:=false
static var totals:Dictionary={}
static var counts:Dictionary={}

static func begin()->int:
	return Time.get_ticks_usec() if enabled else 0

static func end(label:String,started:int)->void:
	if not enabled:return
	var elapsed:int=Time.get_ticks_usec()-started
	totals[label]=int(totals.get(label,0))+elapsed
	counts[label]=int(counts.get(label,0))+1

static func reset()->void:
	totals.clear();counts.clear()

static func report(title:String="")->String:
	var labels:Array=totals.keys()
	labels.sort_custom(func(a,b):return int(totals[a])>int(totals[b]))
	var lines:Array[String]=[]
	if not title.is_empty():lines.append("== %s"%title)
	for label in labels:
		var count:int=maxi(1,int(counts.get(label,1)))
		lines.append("   %-34s total %8d us  avg %6d us  n=%d"%[label,int(totals[label]),int(totals[label])/count,count])
	return "\n".join(lines)
