extends RefCounted
## Presentation-only replay of relation events; never changes the simulation.
const TYPES := ["relationship.aid_recorded", "relationship.gratitude_recorded", "relationship.harm_recorded"]
var states:Dictionary={}
var suffixes:Dictionary={}

static func score(relation:Dictionary)->int:
	return clampi(50+int(int(relation.get("trust",0))/2)
		-int(int(relation.get("fear",0))/3)-int(int(relation.get("hostility",0))/2)
		+int(int(relation.get("gratitude",0))/2)-int(int(relation.get("grievance",0))/2),0,100)

static func _effective(base:Dictionary,personal:Dictionary)->Dictionary:
	return {"trust":clampi(int(base.get("base_trust",0))+int(personal.trust),-100,100),
		"fear":clampi(int(base.get("base_fear",0))+int(personal.fear),0,100),
		"hostility":clampi(int(base.get("base_hostility",0))+int(int(personal.grievance)/5)-int(int(personal.gratitude)/10),0,100),
		"gratitude":personal.gratitude,"grievance":personal.grievance}

func append(world,event)->void:
	if event.type not in TYPES:return
	if not world.entities.has(event.actor_id) or not world.entities.has(event.target_id):return
	var key:=Vector2i(event.actor_id,event.target_id)
	var personal:Dictionary=states.get(key,{"trust":0,"fear":0,"gratitude":0,"grievance":0}).duplicate()
	var base:Dictionary=world.species_relations.get_relation(world.entities[event.actor_id].species_id,world.entities[event.target_id].species_id)
	var before:=score(_effective(base,personal))
	personal.trust=int(event.data.get("personal_trust_delta",personal.trust))
	if event.type=="relationship.aid_recorded":
		personal.gratitude=int(event.data.gratitude)
		personal.fear=clampi(int(personal.fear)-int(int(event.magnitude)/20),-30,30)
	elif event.type=="relationship.harm_recorded":
		personal.grievance=int(event.data.grievance)
		personal.fear=clampi(int(personal.fear)+int((int(event.magnitude)+3)/4),-30,30)
	else:
		personal.gratitude=int(event.data.gratitude)
		personal.fear=int(event.data.get("personal_fear_delta",personal.fear))
	states[key]=personal
	var after:=score(_effective(base,personal))
	suffixes[event.id]=" · %s → %s 호감도 %+d (%d/100)"%[
		world.entities[event.actor_id].display_name,world.entities[event.target_id].display_name,after-before,after]
