class_name DarknessStressRules
extends RefCounted

## Event-sourced darkness exposure. Exposure is reconstructed from the event
## tail, while stress is applied through the existing party morale system.
const RULESET_ID := "darkness-stress-v1"
const EVENT_EXPOSURE_CHANGED := "darkness.exposure_changed"
const DEEP_DARK_THRESHOLD := 180
const GRACE_TIME := 300
const MAX_EXPOSURE := 2000
const STRESS_PER_100_TIME := 12

const VisionRulesScript = preload("res://sim/vision_rules.gd")
const Index = preload("res://sim/darkness_event_index.gd")
const V2 := "darkness-stress-v2"

static func state(world, entity_id: int) -> Dictionary:
	var result := {"entity_id": entity_id, "exposure": 0, "deep_dark": false,
		"illumination": 0, "grace_remaining": GRACE_TIME,
		"last_event_id": -1, "sampled_world_time": -1}
	if world == null or not world.entities.has(entity_id): return result
	var latest = _latest_event(world, entity_id)
	if latest != null:
		result.last_event_id = int(latest.id)
		result.exposure = clampi(int(latest.data.get("exposure_after", 0)), 0, MAX_EXPOSURE)
		result.sampled_world_time = int(latest.world_time)
	var lighting := VisionRulesScript.lighting_for_world(world)
	result.illumination = VisionRulesScript.illumination(
		world, world.entities[entity_id].position, lighting)
	result.deep_dark = int(result.illumination) < DEEP_DARK_THRESHOLD
	result.grace_remaining = maxi(0, GRACE_TIME - int(result.exposure))
	return result


static func _legacy_commit_boundary(world, start_time: int, end_time: int) -> bool:
	if world == null or world.party_encounter == null or end_time <= start_time:
		return true
	var elapsed := end_time - start_time
	var ids: Array[int] = []
	for raw_id in world.party_encounter.active_party_member_ids:
		var entity_id := int(raw_id)
		var member = world.party_encounter.member(entity_id)
		var combatant = world.combatant_states.get(entity_id)
		if member == null or combatant == null or not world.entities.has(entity_id): continue
		if member.presence not in ["DEPLOYED", "GROUPED"] or combatant.life_state == "DEAD": continue
		ids.append(entity_id)
	ids.sort()
	for entity_id in ids:
		var previous := state(world, entity_id)
		var before := int(previous.exposure)
		var illumination := int(previous.illumination)
		var deep_dark := illumination < DEEP_DARK_THRESHOLD
		var after := mini(MAX_EXPOSURE, before + elapsed) if deep_dark else maxi(0, before - elapsed)
		if after == before: continue
		var member = world.party_encounter.member(entity_id)
		var profile := VisionRulesScript.profile_for_entity(world.entities[entity_id])
		var resistance := clampi(int(profile.get("darkness_stress_resistance_milli", 500)), 0, 1000)
		var before_progress := maxi(0, before - GRACE_TIME)
		var after_progress := maxi(0, after - GRACE_TIME)
		var susceptibility := 1000 - resistance
		var before_stress := int(before_progress * STRESS_PER_100_TIME * susceptibility / 100000.0)
		var after_stress := int(after_progress * STRESS_PER_100_TIME * susceptibility / 100000.0)
		var stress_delta := maxi(0, after_stress - before_stress)
		var event: Variant = world.emit_event(EVENT_EXPOSURE_CHANGED, entity_id, -1,
			world.entities[entity_id].position, stress_delta, -1, {
				"schema_version": 1, "ruleset_id": RULESET_ID,
				"exposure_before": before, "exposure_after": after,
				"elapsed": elapsed, "illumination": illumination,
				"deep_dark": deep_dark, "stress_delta": stress_delta,
				"resistance_milli": resistance})
		if event == null: return false
	return true


static func _latest_event(world, entity_id: int):
	return Index.latest(world,entity_id)

static func enabled(world)->bool:
	return Index.enabled(world)

static func begin_sample(world)->Dictionary:
	if not enabled(world):return {}
	return {"time":int(world.world_time),"current":_capture(world),"segments":{}}

static func _capture(world)->Dictionary:
	var rows:Dictionary={}
	if world.party_encounter==null:return rows
	var lighting:Dictionary=VisionRulesScript.lighting_for_world(world)
	for id in world.party_encounter.active_party_member_ids:
		var member=world.party_encounter.member(int(id))
		if member==null or member.presence not in ["DEPLOYED","GROUPED"] \
				or not world.entities.has(id) or not world.combatant_states.has(id) \
				or world.combatant_states[id].life_state=="DEAD":continue
		var pos:Vector2i=world.entities[id].position
		var lights:Array=[]
		var base:int=VisionRulesScript.illumination(world,pos,{"ambient_level":lighting.ambient_level,"sources":[]})
		for source in lighting.sources:
			var level:int=VisionRulesScript.illumination(world,pos,{"ambient_level":0,"sources":[source]})
			var until:=-1
			if source.has("instance_id"):
				until=int(world.world_time)+int(preload("res://sim/torch_rules.gd").state(world,str(source.instance_id)).fuel_remaining)
			if level>base:lights.append({"level":level,"until":until})
		rows[int(id)]={"base":base,"lights":lights}
	return rows

# Called after each instantaneous action/environment mutation. Charge the
# previous sample up to this timestamp, then sample the new configuration.
# No canonical events are emitted until the owning turn's final boundary.
static func checkpoint(world,sample:Dictionary)->void:
	if sample.is_empty():return
	var start:int=sample.time;var end:int=world.world_time
	if end>start:
		for id in sample.current:
			var row:Dictionary=sample.current[id]
			var cuts:Array[int]=[start,end]
			for light in row.lights:
				var expiry:int=light.until
				if expiry>start and expiry<end and expiry not in cuts:cuts.append(expiry)
			cuts.sort()
			if not sample.segments.has(id):sample.segments[id]=[]
			for i in range(cuts.size()-1):
				var level:int=row.base
				for light in row.lights:
					if int(light.until)<0 or int(light.until)>cuts[i]:level=maxi(level,int(light.level))
				var segments:Array=sample.segments[id]
				var elapsed:int=cuts[i+1]-cuts[i]
				if not segments.is_empty() and int(segments[-1].illumination)==level:
					segments[-1].elapsed+=elapsed
				else:segments.append({"elapsed":elapsed,"illumination":level})
	sample.time=end;sample.current=_capture(world)

static func project(before:int,remainder:int,resistance:int,segments:Array)->Dictionary:
	var exposure:=before;var numerator:=remainder;var stress:=0
	for segment in segments:
		var elapsed:int=segment.elapsed
		if int(segment.illumination)<DEEP_DARK_THRESHOLD:
			var charged:=maxi(0,elapsed-maxi(0,GRACE_TIME-exposure))
			exposure=mini(MAX_EXPOSURE,exposure+elapsed)
			numerator+=charged*STRESS_PER_100_TIME*(1000-resistance)
			stress+=numerator/100000
			numerator%=100000
		else:exposure=maxi(0,exposure-elapsed)
	return {"exposure":exposure,"remainder":numerator,"stress":stress}

static func commit_boundary(world,start_time:int,end_time:int,sample:Dictionary={})->bool:
	if not enabled(world):return _legacy_commit_boundary(world,start_time,end_time)
	if sample.is_empty():return end_time<=start_time
	checkpoint(world,sample)
	var ids:Array=sample.segments.keys();ids.sort()
	for id in ids:
		var member=world.party_encounter.member(id)
		if id not in world.party_encounter.active_party_member_ids or member==null \
				or member.presence not in ["DEPLOYED","GROUPED"] \
				or not world.combatant_states.has(id) or world.combatant_states[id].life_state=="DEAD":continue
		var segments:Array=sample.segments[id]
		if segments.is_empty():continue
		var sampled_elapsed:=0
		for segment in segments:sampled_elapsed+=int(segment.elapsed)
		var latest=Index.latest(world,id)
		var before:int=int(latest.data.exposure_after) if latest!=null else 0
		var remainder:int=int(latest.data.get("remainder_after",0)) if latest!=null else 0
		var resistance:int=clampi(int(VisionRulesScript.profile_for_entity(world.entities[id]).get("darkness_stress_resistance_milli",500)),0,1000)
		var projected:=project(before,remainder,resistance,segments)
		if projected.exposure==before and projected.remainder==remainder and projected.stress==0:continue
		var event=world.emit_event(EVENT_EXPOSURE_CHANGED,id,-1,world.entities[id].position,int(projected.stress),-1,{
			"schema_version":2,"ruleset_id":V2,"exposure_before":before,"exposure_after":int(projected.exposure),
			"remainder_before":remainder,"remainder_after":int(projected.remainder),"segments":segments.duplicate(true),
			"elapsed":sampled_elapsed,"resistance_milli":resistance,"stress_delta":int(projected.stress)})
		if event==null:return false
	return true

static func morale_sources(world,event_start:int,boundary_start:int)->Array:
	if not enabled(world):return world.events_since(event_start)
	var result:Array=[]
	for event in world.events_since(boundary_start):
		if event.type==EVENT_EXPOSURE_CHANGED and int(event.magnitude)>0:result.append(event)
	return result

static func event_error(data:Dictionary,previous:Dictionary,magnitude:int)->String:
	var keys:Array=data.keys();keys.sort()
	if keys!=["elapsed","exposure_after","exposure_before","remainder_after","remainder_before","resistance_milli","ruleset_id","schema_version","segments","stress_delta"] \
			or data.get("schema_version")!=2 or data.get("ruleset_id")!=V2 or not data.get("segments") is Array:
		return "darkness_v2_shape"
	for key in ["elapsed","exposure_after","exposure_before","remainder_after","remainder_before","resistance_milli","schema_version","stress_delta"]:
		if not data[key] is int:return "darkness_v2_scalar"
	if data.elapsed<=0 or data.elapsed>10000 or data.exposure_before<0 or data.exposure_before>MAX_EXPOSURE \
			or data.remainder_before<0 or data.remainder_before>=100000 or data.resistance_milli<0 or data.resistance_milli>1000:
		return "darkness_v2_range"
	if int(data.exposure_before)!=int(previous.get("exposure_after",0)) \
			or int(data.remainder_before)!=int(previous.get("remainder_after",0)):return "darkness_chain_invalid"
	var total:=0
	for segment in data.segments:
		if not segment is Dictionary or segment.size()!=2 or not segment.get("elapsed") is int \
				or not segment.get("illumination") is int:return "darkness_segment_invalid"
		if segment.elapsed<=0 or segment.illumination<0 or segment.illumination>1000:return "darkness_segment_invalid"
		total+=int(segment.elapsed)
	if total!=int(data.elapsed):return "darkness_duration_invalid"
	var expected:=project(data.exposure_before,data.remainder_before,data.resistance_milli,data.segments)
	if expected.exposure!=data.exposure_after or expected.remainder!=data.remainder_after \
			or expected.stress!=data.stress_delta or magnitude!=expected.stress:return "darkness_projection_invalid"
	return ""
