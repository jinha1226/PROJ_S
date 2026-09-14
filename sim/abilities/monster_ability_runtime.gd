extends RefCounted

const Defs=preload("res://sim/abilities/monster_ability_definitions.gd")
const Terrain=preload("res://sim/terrain_registry.gd")
const Affinities=preload("res://sim/species_hazard_affinity_registry.gd")
const KEY:="monster_effect_projection_v1"

static func distance(a:Vector2i,b:Vector2i)->int:return maxi(absi(a.x-b.x),absi(a.y-b.y))
static func alive(world,id:int)->bool:return world.entities.has(id) and world.combatant_states.has(id) and world.combatant_states[id].life_state=="ACTIVE"
static func passive(world,id:int,ability:String)->bool:
	var member=world.party_encounter.member(id) if world.party_encounter!=null else null
	return member!=null and ability in member.bound_ability_ids

static func projection(world)->Dictionary:
	var p:Dictionary=world.get_meta(KEY,{})
	if p.is_empty() or int(p.cursor)>world.events.size() or (int(p.cursor)>0 and p.tail!=world.events[int(p.cursor)-1]):
		p={"cursor":0,"tail":null,"statuses":{},"moves":{},"charges":{},"used_moves":{}}
	for i in range(int(p.cursor),world.events.size()):
		var e=world.events[i]
		if e.type=="ability.status":
			p.statuses["%d:%s"%[e.target_id,e.data.status]]=e
		elif e.type=="ability.charge":p.charges[e.target_id]=e.magnitude
		elif e.type=="action.move":p.moves[e.actor_id]=e
		elif e.type=="ability.leap_used":p.used_moves[e.actor_id]=e.data.move_id
	p.cursor=world.events.size();p.tail=world.events[-1] if not world.events.is_empty() else null
	world.set_meta(KEY,p);return p

static func status(world,id:int,key:String):
	var e=projection(world).statuses.get("%d:%s"%[id,key])
	if key in ["POISON","SLOW"] and e!=null and int(preload("res://sim/consumable_effects.gd").projection(world).clears.get(id,-1))>e.id:return null
	return e if e!=null and int(e.data.until)>world.world_time and e.magnitude>0 else null

static func add_status(world,actor:int,target:int,id:String,key:String,power:int,duration:int,cause:int)->bool:
	return world.emit_event("ability.status",actor,target,world.entities[target].position,maxi(0,power),cause,
		{"schema_version":1,"ability_id":id,"status":key,"until":str(world.world_time+duration)})!=null

static func scale(world,id:int,ability:String,value:int)->int:
	var growth=preload("res://sim/party_growth_rules.gd").for_actor(world,id)
	if growth!=null:
		return growth.mastery_scale(str(Defs.definition(ability).get("axis","MAGIC")),value)
	return value

static func assess(world,actor:int,id:String,target:int)->Dictionary:
	var d:=Defs.definition(id)
	var no:={"accepted":false,"reason":"monster_ability_invalid","message":"사용할 수 없는 대상입니다."}
	if preload("res://sim/consumable_effects.gd").skill_blocked(world,actor):no.message="봉인·혼란 중에는 스킬을 사용할 수 없습니다.";return no
	if d.is_empty() or not alive(world,actor) or not alive(world,target):return no
	var member=world.party_encounter.member(actor)
	if member==null or id not in member.active_skill_ids():return no
	var allied:bool=target in world.party_encounter.active_party_member_ids
	if (d.target=="SELF" and target!=actor) or (d.target=="ENEMY" and (allied or not world.is_autonomous_target(target))):return no
	var origin:Vector2i=world.entities[actor].position;var position:Vector2i=world.entities[target].position
	if distance(origin,position)>int(d.range):no.message="사거리 밖입니다.";return no
	if target!=actor and (not preload("res://sim/enemy_perception_registry.gd").has_line_of_sight(world,origin,position) or preload("res://sim/party_perception_registry.gd").visible_party_members(world,world.party_encounter,position).is_empty()):
		no.message="보이는 대상을 선택하세요.";return no
	if member.energy<int(d.cost):no.message="MP가 부족합니다.";return no
	if d.effect=="ACID" and world.entities[actor].health<=5:no.message="HP가 6 이상 필요합니다.";return no
	if d.effect=="REGENERATE":
		if world.party_encounter.ration_milli<10000:no.message="식량이 10 필요합니다.";return no
		if world.entities[actor].health>=world.entities[actor].max_health:no.message="체력이 가득 찼습니다.";return no
	var landing:=position
	if d.effect=="LEAP":
		landing=Vector2i(-1,-1)
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
			var cell:Vector2i=position+delta
			if not world.in_bounds(cell) or not Terrain.definition(str(world.tile_at(cell).terrain)).get("passable",false):continue
			if cell!=origin and not world.occupying_entities_at(cell).is_empty():continue
			if not preload("res://sim/combat_kernel.gd").sees(origin,cell,world.combat_sight_blocked):continue
			if landing==Vector2i(-1,-1) or distance(origin,cell)<distance(origin,landing):landing=cell
		if landing==Vector2i(-1,-1):no.message="도약할 빈칸이 없습니다.";return no
	return {"accepted":true,"reason":"ok","message":str(d.name),"actor_id":actor,"target_id":target,"skill_id":id,
		"cost":int(d.cost),"action_time":preload("res://sim/field_action_timing.gd").duration(world,actor,id,100),"damage":0,"healing":0,"destination":landing}

static func impact(sim,actor:int,target:int,id:String,amount:int,kind:String,cause:int)->int:
	var w=sim.world
	if not alive(w,target) or amount<=0:return 0
	var entity=w.entities[target]
	if kind=="HEAL":amount=mini(amount,entity.max_health-entity.health)
	if amount<=0:return 0
	var trigger=w.event_by_id(cause)
	if trigger!=null and trigger.instigator_id!=actor:
		var reaction=w.emit_event("ability.reaction",actor,target,entity.position,0,-1,{"schema_version":1,"ability_id":id,"trigger_id":cause})
		if reaction==null:return -1
		cause=reaction.id
	if kind=="electric":amount=maxi(1,amount) # Canonical equipment/environment resistance below.
	var source=w.emit_event("ability.impact",actor,target,entity.position,amount,cause,
		{"schema_version":1,"ability_id":id,"kind":kind})
	if source==null:return -1
	if kind=="HEAL":
		entity.health+=amount
		return amount if w.emit_event("health.restored",target,target,entity.position,amount,source.id,
			{"schema_version":1,"ruleset_id":"monster-abilities-v1","kind":"MONSTER_ABILITY","health_after":entity.health})!=null else -1
	var resolved:int=sim.damage._element_armor_context(entity,kind,amount,source.id,entity.position).get("final_damage",amount)
	var terminal:bool=resolved>=entity.health and (w.lifecycle_succumbs(target) or target==w.party_encounter.protagonist_id)
	var result:Dictionary=sim.damage.apply_canonical_active_damage(entity,amount,kind,source.id,entity.position,w._active_step_index,entity.health,terminal,false)
	return int(result.get("applied_health_damage",0)) if result.get("accepted",false) else -1

static func poison(world,actor:int,target:int,stacks:int,cause:int)->bool:
	var old=status(world,target,"POISON")
	return add_status(world,actor,target,"VENOM_FANG","POISON",mini(3,stacks+(old.magnitude if old!=null else 0)),300,cause)

static func charge(world,actor:int,amount:int,cause:int)->bool:
	return world.emit_event("ability.charge",actor,actor,world.entities[actor].position,clampi(amount,0,3),cause,{"schema_version":1,"ability_id":"CHARGE_ORGAN"})!=null

static func area(sim,actor:int,id:String,power:int,cause:int)->bool:
	var w=sim.world;var origin:Vector2i=w.entities[actor].position
	for target in w.party_encounter.enemy_ids:
		if w.is_autonomous_target(target) and distance(origin,w.entities[target].position)<=2 and preload("res://sim/enemy_perception_registry.gd").has_line_of_sight(w,origin,w.entities[target].position):
			if impact(sim,actor,target,id,scale(w,actor,id,power),"electric",cause)<0:return false
	return true

static func commit(sim,actor:int,id:String,target:int,a:Dictionary):
	var w=sim.world;var d:=Defs.definition(id)
	var e=w.emit_event("ability.cast",actor,target,w.entities[target].position,0,-1,
		{"schema_version":1,"skill_id":id,"cost":int(a.cost),"action_time":int(a.action_time)})
	if e==null:return null
	var power:=scale(w,actor,id,int(d.power));var ok:=true
	match str(d.effect):
		"DAMAGE","EXECUTE","LEAP","ACID","SIPHON":
			if d.effect=="LEAP" and a.destination!=w.entities[actor].position:
				ok=sim.movement.commit_preflighted_move(actor,a.destination,str(w.tile_at(a.destination).terrain),1,e.id)!=null
			if d.effect=="ACID":ok=ok and impact(sim,actor,actor,id,5,"physical",e.id)>=0
			if d.effect=="EXECUTE" and w.entities[target].health<w.entities[target].max_health:power+=scale(w,actor,id,12)
			var dealt:=impact(sim,actor,target,id,power,"physical",e.id) if ok else -1
			ok=dealt>=0
			if d.effect=="SIPHON" and dealt>0:ok=ok and impact(sim,actor,actor,id,dealt,"HEAL",e.id)>=0
		"HIDE","SHELL","STONE":ok=add_status(w,actor,actor,id,str(d.effect),power,200 if d.effect=="SHELL" else 300,e.id)
		"VEIL":ok=add_status(w,actor,actor,id,"VEIL",1,300,e.id)
		"ECHO","DEEP":
			ok=add_status(w,actor,actor,id,str(d.effect),6,300,e.id)
		"FROST":
			ok=add_status(w,actor,target,id,"FROST_ZONE",1,300,e.id)
			for enemy in w.party_encounter.enemy_ids:
				if w.is_autonomous_target(enemy) and distance(w.entities[target].position,w.entities[enemy].position)<=1 and preload("res://sim/combat_kernel.gd").sees(w.entities[target].position,w.entities[enemy].position,w.combat_sight_blocked):ok=ok and add_status(w,actor,enemy,id,"SLOW",100,300,e.id)
		"POISON":ok=poison(w,actor,target,3,e.id)
		"DISCHARGE":
			var stored:int=projection(w).charges.get(actor,0)
			ok=area(sim,actor,id,int(d.power)+stored*6,e.id) and charge(w,actor,0,e.id)
		"REGENERATE":
			w.party_encounter.ration_milli-=10000
			ok=w.emit_event("ability.ration_spent",actor,actor,w.entities[actor].position,10000,e.id,{"schema_version":1,"ability_id":id})!=null
			ok=ok and impact(sim,actor,actor,id,power,"HEAL",e.id)>=0
	if not ok:return null
	var member=w.party_encounter.member(actor);member.energy-=int(a.cost);member.busy_until=w.world_time+int(a.action_time)
	w.party_encounter.revision+=1
	return e

static func anchored(world,id:int)->bool:return status(world,id,"SHELL")!=null or status(world,id,"STONE")!=null
static func move_delay(world,id:int)->int:
	var slow=status(world,id,"SLOW")
	var delay:int=slow.magnitude if slow!=null else 0
	if world.entities.has(id):
		for e in projection(world).statuses.values():
			if e.data.status=="FROST_ZONE" and int(e.data.until)>world.world_time and id in world.party_encounter.enemy_ids and distance(e.position,world.entities[id].position)<=1:delay=maxi(delay,100)
	return delay

static func stealth(world,id:int)->bool:
	if status(world,id,"VEIL")!=null:return true
	if not passive(world,id,"SHADOW_VEIL"):return false
	var vision=preload("res://sim/vision_rules.gd")
	var lighting:Dictionary=vision.lighting_for_world(world)
	lighting.ambient_level=0 # Ambient readability must not erase shadow gameplay on floors 1–2.
	return vision.illumination(world,world.entities[id].position,lighting)<300

static func armor(world,id:int,form:String="")->int:
	var value:int=preload("res://sim/consumable_effects.gd").armor(world,id)+(4 if passive(world,id,"HIDE_PLATING") else 0)
	if passive(world,id,"CARAPACE"):value+=3+(5 if form=="PIERCE" else 0)
	if passive(world,id,"STONE_SKELETON") and form=="IMPACT":value+=6
	for key in ["HIDE","SHELL","STONE"]:
		var buff=status(world,id,key)
		if buff!=null:value+=buff.magnitude
	return value

static func reactions(sim,start:int)->bool:
	var w=sim.world;var stop:int=w.events.size()
	for i in range(start,stop):
		var hit=w.events[i]
		if hit.type=="action.move":
			if hit.actor_id in w.party_encounter.enemy_ids:
				var delay:=move_delay(w,hit.actor_id)
				if delay>0:w.party_encounter.enemy_busy_rows[hit.actor_id]=int(w.party_encounter.enemy_busy_rows.get(hit.actor_id,w.world_time))+delay
			if status(w,hit.actor_id,"SLOW")!=null and not add_status(w,hit.actor_id,hit.actor_id,"FROST_SILK","SLOW",0,0,hit.id):return false
			continue
		var veil=status(w,hit.actor_id,"VEIL") if hit.actor_id>0 else null
		if hit.type in ["action.melee_attack","ability.cast","action.skill"] and veil!=null and veil.id<hit.id:
			if not add_status(w,hit.actor_id,hit.actor_id,"SHADOW_VEIL","VEIL",0,0,hit.id):return false
		if hit.type!="combat.physical_damage" or hit.magnitude<=0:continue
		var attack=w.event_by_id(hit.cause_id)
		if attack==null or attack.type!="action.melee_attack":continue
		var actor:int=attack.actor_id;var target:int=hit.target_id
		var melee:bool=distance(w.entities[actor].position,hit.position)<=1
		# Apply on-hit effects only to the original attack, never their damage children.
		if alive(w,target):
			for id in ["PREDATOR_NERVE","THROWING_INSTINCT","HUNTER_LEAP"]:
				if not passive(w,actor,id):continue
				var amount:=0
				if id=="PREDATOR_NERVE" and melee and int(hit.data.get("health_before",w.entities[target].health+hit.magnitude))<w.entities[target].max_health:amount=6
				if id=="THROWING_INSTINCT" and not melee:amount=4
				if id=="HUNTER_LEAP" and melee:
					var p:=projection(w);var move=p.moves.get(actor)
					if move!=null and move.world_time+150>=w.world_time and p.used_moves.get(actor,-1)!=move.id:
						amount=8
						if w.emit_event("ability.leap_used",actor,actor,w.entities[actor].position,0,hit.id,{"schema_version":1,"ability_id":id,"move_id":move.id})==null:return false
				if amount>0 and impact(sim,actor,target,id,scale(w,actor,id,amount),"physical",hit.id)<0:return false
			if passive(w,actor,"FROST_SILK") and not add_status(w,actor,target,"FROST_SILK","SLOW",100,300,hit.id):return false
			if passive(w,actor,"VENOM_FANG") and melee and not poison(w,actor,target,1,hit.id):return false
		if passive(w,actor,"BLOOD_SIPHON") and melee and impact(sim,actor,actor,"BLOOD_SIPHON",clampi(hit.magnitude/4,1,5),"HEAL",hit.id)<0:return false
		if alive(w,target) and passive(w,target,"CAUSTIC_BLOOD") and melee and impact(sim,target,actor,"CAUSTIC_BLOOD",scale(w,target,"CAUSTIC_BLOOD",5),"physical",hit.id)<0:return false
		if alive(w,target) and passive(w,target,"CHARGE_ORGAN"):
			var count:int=projection(w).charges.get(target,0)+1
			if not charge(w,target,0 if count>=3 else count,hit.id):return false
			if count>=3 and not area(sim,target,"CHARGE_ORGAN",18,hit.id):return false
	return true

static func hidden_from(world,origin:Vector2i,target:Vector2i)->bool:
	if world.party_encounter==null or distance(origin,target)<=2:return false
	var enemy_observer:=false
	for e in world.occupying_entities_at(origin):
		if e.id in world.party_encounter.enemy_ids:enemy_observer=true;break
	if not enemy_observer:return false
	for e in world.occupying_entities_at(target):
		if e.id in world.party_encounter.active_party_member_ids and stealth(world,e.id):return true
	return false

static func delay_before(world,event)->int:
	var delay:=0;var latest=null
	for e in world.events:
		if e.id>=event.id:break
		if e.type=="ability.status" and e.target_id==event.actor_id and e.data.status=="SLOW":latest=e
	if latest!=null and int(latest.data.until)>event.world_time:delay=latest.magnitude
	return delay

static func accuracy_bonus(world,actor:int,weapon_id:String,before:int=-1)->int:
	var penalty:int=preload("res://sim/consumable_effects.gd").accuracy(world,actor,before)
	var weapon=preload("res://sim/weapon_registry.gd").definition(weapon_id)
	if weapon==null or weapon.proficiency_id!="RANGED":return penalty
	var enabled:=passive(world,actor,"THROWING_INSTINCT")
	if before>0:
		enabled=false
		for e in world.events:
			if e.id>=before:break
			if e.type=="party.ability_bound" and e.actor_id==actor and e.data.ability_id=="THROWING_INSTINCT":enabled=true
	return penalty+(150 if enabled else 0)

static func tick(sim,start:int,end:int)->bool:
	var w=sim.world
	# Snapshot the projection; emitted effects cannot recursively tick themselves.
	var statuses:Array=projection(w).statuses.values().duplicate()
	for s in statuses:
		if s.data.status!="POISON" or not alive(w,s.target_id):continue
		if int(preload("res://sim/consumable_effects.gd").projection(w).clears.get(s.target_id,-1))>s.id:continue
		var until:int=mini(end,int(s.data.until))
		var ticks:int=maxi(0,(until-s.world_time)/100-maxi(0,(start-s.world_time)/100))
		for n in range(mini(3,ticks)):
			if not alive(w,s.target_id):break
			if impact(sim,s.actor_id,s.target_id,"VENOM_FANG",s.magnitude*2,"physical",s.id)<0:return false
	if end/100==start/100:return true
	for actor in w.party_encounter.active_party_member_ids:
		if not alive(w,actor) or not passive(w,actor,"REGENERATIVE_TISSUE"):continue
		var safe:=true
		for enemy in w.party_encounter.enemy_ids:
			if alive(w,enemy) and distance(w.entities[actor].position,w.entities[enemy].position)<=6:safe=false;break
		if safe and w.entities[actor].health<w.entities[actor].max_health:
			var pulse=w.emit_event("ability.pulse",actor,actor,w.entities[actor].position,0,-1,{"schema_version":1,"ability_id":"REGENERATIVE_TISSUE"})
			if pulse==null or impact(sim,actor,actor,"REGENERATIVE_TISSUE",2*mini(10,end/100-start/100),"HEAL",pulse.id)<0:return false
	return true

static func markers(world)->Array:
	var result:Array=[]
	if world.party_encounter==null:return result
	var actor:int=world.party_control_actor_id()
	if not alive(world,actor):return result
	var origin:Vector2i=world.entities[actor].position
	var radius:=3 if passive(world,actor,"ECHO_SENSE") or passive(world,actor,"DEEP_EYE") else 0
	var echo=status(world,actor,"ECHO");var deep=status(world,actor,"DEEP")
	if echo!=null or deep!=null:radius=6
	for e in projection(world).statuses.values():
		if int(e.data.until)<=world.world_time or e.magnitude<=0:continue
		var key:String=str(e.data.status)
		if key in ["FROST_ZONE","POISON","HIDE","SHELL","STONE","VEIL"] and world.entities.has(e.target_id):
			var p:Vector2i=e.position if key=="FROST_ZONE" else world.entities[e.target_id].position
			result.append({"position":[p.x,p.y],"kind":key})
	if radius==0:return result
	var direction:Vector2i=world.party_encounter.facing
	for id in world.entities:
		var entity=world.entities[id]
		if id==actor or not alive(world,id) or distance(origin,entity.position)>radius:continue
		if deep!=null and echo==null and Vector2(entity.position-origin).dot(Vector2(direction))<0:continue
		result.append({"position":[entity.position.x,entity.position.y],"kind":"LIFE"})
	if passive(world,actor,"DEEP_EYE") or deep!=null:
		for y in range(maxi(0,origin.y-radius),mini(world.height,origin.y+radius+1)):
			for x in range(maxi(0,origin.x-radius),mini(world.width,origin.x+radius+1)):
				var p:=Vector2i(x,y);var tile=world.tile_at(p)
				if deep!=null and Vector2(p-origin).dot(Vector2(direction))<0:continue
				if int(tile.temperature)>400 or int(tile.smoke_amount)>0 or str(tile.terrain) in ["deep_water","lava"]:result.append({"position":[x,y],"kind":"DANGER"})
	return result

static func event_error(world,e)->String:
	if not str(e.type).begins_with("ability."):return ""
	if e.type=="ability.passive_triggered":return "" # Original fire gland validator.
	var id:String=str(e.data.get("skill_id",e.data.get("ability_id","")))
	if not Defs.SKILLS.has(id) or e.data.get("schema_version")!=1 or not world.entities.has(e.actor_id) or not world.entities.has(e.target_id):return "monster_ability_event_invalid"
	var keys:Array=e.data.keys();keys.sort()
	match str(e.type):
		"ability.cast":
			var d:=Defs.definition(id)
			if keys!=["action_time","cost","schema_version","skill_id"] or e.cause_id!=-1 or e.magnitude!=0 or e.data.cost!=d.cost or not e.data.action_time is int or e.data.action_time<1:return "monster_cast_invalid"
		"ability.status":
			if keys!=["ability_id","schema_version","status","until"] or e.data.status not in ["POISON","SLOW","FROST_ZONE","HIDE","SHELL","STONE","VEIL","ECHO","DEEP","DEEP_TARGET"] \
					or not preload("res://sim/int64_codec.gd").is_canonical(e.data.until) or int(e.data.until)<e.world_time or int(e.data.until)>e.world_time+300:return "monster_status_invalid"
			var allowed:Dictionary={"VENOM_FANG":["POISON"],"FROST_SILK":["SLOW","FROST_ZONE"],"HIDE_PLATING":["HIDE"],"CARAPACE":["SHELL"],"STONE_SKELETON":["STONE"],"SHADOW_VEIL":["VEIL"],"ECHO_SENSE":["ECHO"],"DEEP_EYE":["DEEP","DEEP_TARGET"]}
			if str(e.data.status) not in allowed.get(id,[]):return "monster_status_ability_mismatch"
			if e.data.status=="POISON" and e.magnitude not in [1,2,3]:return "monster_poison_stacks_invalid"
		"ability.impact":
			if keys!=["ability_id","kind","schema_version"] or e.data.kind not in ["physical","electric","HEAL"] or e.magnitude<=0 or e.magnitude>1000:return "monster_impact_invalid"
		"ability.charge":
			if keys!=["ability_id","schema_version"] or id!="CHARGE_ORGAN" or e.magnitude>3:return "monster_charge_invalid"
		"ability.ration_spent":
			if keys!=["ability_id","schema_version"] or id!="REGENERATIVE_TISSUE" or e.magnitude!=10000:return "monster_ration_invalid"
		"ability.leap_used":
			if keys!=["ability_id","move_id","schema_version"] or id!="HUNTER_LEAP" or not e.data.move_id is int:return "monster_leap_invalid"
		"ability.pulse":
			if keys!=["ability_id","schema_version"] or id!="REGENERATIVE_TISSUE" or e.cause_id!=-1:return "monster_pulse_invalid"
		"ability.reaction":
			if keys!=["ability_id","schema_version","trigger_id"] or not e.data.trigger_id is int or e.cause_id!=-1:return "monster_reaction_invalid"
			var trigger=world.event_by_id(e.data.trigger_id)
			if trigger==null or trigger.id>=e.id or trigger.type!="combat.physical_damage" or trigger.target_id!=e.actor_id \
					or id not in ["CAUSTIC_BLOOD","CHARGE_ORGAN"] or trigger.step_index!=e.step_index or trigger.world_time!=e.world_time:return "monster_reaction_invalid"
		_:return "unknown_monster_event"
	if e.type not in ["ability.cast","ability.pulse","ability.reaction"]:
		var source=world.event_by_id(e.cause_id)
		if source!=null and source.type=="consumable.pulse" and e.type=="ability.impact":
			var expected:String="VENOM_FANG" if source.data.effect=="POISON" else "REGENERATIVE_TISSUE"
			var kind:String="physical" if source.data.effect=="POISON" else "HEAL"
			return "" if id==expected and e.data.kind==kind and e.actor_id==source.actor_id and e.target_id==source.target_id and e.magnitude==source.magnitude and e.world_time==source.world_time and e.step_index==source.step_index and preload("res://sim/consumable_effects.gd").event_error(world,source).is_empty() else "consumable_impact_invalid"
		if source==null or source.type not in ["ability.cast","ability.status","ability.pulse","ability.reaction","combat.physical_damage","action.move","action.melee_attack","action.skill"]:return "monster_effect_source_invalid"
	return ""

static func heal_error(world,e)->String:
	var source=world.event_by_id(e.cause_id)
	if source==null or source.type!="ability.impact" or source.data.get("kind")!="HEAL" or not event_error(world,source).is_empty() \
			or e.target_id!=source.target_id or e.actor_id!=e.target_id or e.magnitude!=source.magnitude or e.position!=source.position \
			or e.world_time!=source.world_time or e.step_index!=source.step_index:return "monster_heal_invalid"
	return ""
