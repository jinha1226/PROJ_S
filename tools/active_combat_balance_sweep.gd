extends SceneTree
## Local-only paired experiment; deliberately not a CI job.
const Model=preload("res://playtest/active_combat_lab_model.gd")
const Skills=preload("res://sim/abilities/active_skill_registry.gd")
const POLICIES:=["utility","mage","support","frontline","weakest","nearest"]
const SCENARIOS:=["personality","skills","both","random_species","all_human","all_elf","all_orc"]
var body_enabled:bool=true
class Trial extends Model:
	var first_kill:int=-1
	var uses:Dictionary={}
	func _execute(source:Dictionary,kind:String,target_id:int,destination:Vector2i)->Dictionary:
		var result:Dictionary=super._execute(source,kind,target_id,destination)
		if result.accepted:
			var key:String=str(source.team)+":"+kind
			uses[key]=int(uses.get(key,0))+1
			if first_kill<0:
				for row in actors:
					if row.team=="ENEMY" and int(row.hp)<=0:first_kill=int(row.id);break
		return result

func _init()->void:call_deferred("run")

func configure(sample:int,scenario:String):
	var model=Trial.new(44 if scenario=="skills" else sample)
	var rng:=RandomNumberGenerator.new();rng.seed=100000+sample
	for id in range(1,5):
		var actor:Dictionary=model.actor(id)
		if scenario!="personality":
			var pool:Array=Skills.SKILLS.keys();pool.sort()
			actor.skills=[]
			for slot in range(2):
				var index:=rng.randi_range(0,pool.size()-1)
				actor.skills.append(pool[index]);pool.remove_at(index)
	var species_rng:=RandomNumberGenerator.new();species_rng.seed=200000+sample
	for id in range(1,5):
		var species:String=str(model.actor(id).species_id)
		if scenario=="random_species":species=["human","dwarf","elf","orc"][species_rng.randi_range(0,3)]
		elif scenario.begins_with("all_"):species=scenario.trim_prefix("all_")
		if scenario=="random_species" or scenario.begins_with("all_"):
			var row:Dictionary=model.actor(id)
			model.actors[id-1]=model._actor(id,"PARTY",species,row.position,100,20,row.skills)
	model.timeline.reset(model.actors)
	model.body_bridge.enabled=body_enabled
	model.body_bridge.reset(model.actors,model.seed)
	return model

func choose(model,policy:String)->Dictionary:
	var hero:Dictionary=model.actor(1)
	var fallback:Dictionary=model.choose_action(hero)
	if policy=="utility":return fallback
	# Change offensive target preference only. No omniscience, teleports,
	# party-wide commands, or different fallback controller between policies.
	var options:Array=[]
	for foe in model.actors:
		if foe.team!="ENEMY" or int(foe.hp)<=0:continue
		var best:Dictionary={};var best_score:float=-1.0
		for kind in ["ATTACK"]+hero.skills:
			var damage:int=0
			if kind=="ATTACK":
				if model.distance(hero.position,foe.position)>1 or not model.Effects.clear_line(hero.position,foe.position,model.blocked):continue
				damage=model.basic_power(hero)
			else:
				var preview:Dictionary=model.preview(1,str(kind),int(foe.id))
				if not preview.accepted or int(preview.damage)<=0:continue
				damage=int(preview.damage)
			var score:float=float(mini(damage,int(foe.hp)+int(foe.barrier)))/model.timeline.duration(hero,str(kind))
			if score>best_score:
				best_score=score;best={"kind":str(kind),"target":int(foe.id),"position":Vector2i(-1,-1)}
		if best.is_empty():continue
		var rank:int=0
		if policy in ["mage","support","frontline"]:rank=0 if int(foe.id)==int({"mage":6,"support":7,"frontline":5}[policy]) else 1
		elif policy=="weakest":rank=int(foe.hp)+int(foe.barrier)
		elif policy=="nearest":rank=model.distance(hero.position,foe.position)
		options.append({"action":best,"rank":rank,"distance":model.distance(hero.position,foe.position)})
	if options.is_empty():return fallback
	options.sort_custom(func(a,b):
		if a.rank!=b.rank:return a.rank<b.rank
		if a.distance!=b.distance:return a.distance<b.distance
		return int(a.action.target)<int(b.action.target))
	return options[0].action

func trial(sample:int,scenario:String,policy:String)->Dictionary:
	var model=configure(sample,scenario)
	var kits:Array=[];var species:Array=[]
	for id in range(1,5):kits.append(model.actor(id).skills.duplicate());species.append(model.actor(id).species_id)
	var invalid:int=0
	while model.terminal.is_empty() and model.turn<100 and model.timeline.now<15000:
		var action:=choose(model,policy)
		if not model.act(str(action.kind),int(action.target),action.position).accepted:invalid+=1;break
	var hp:int=0;var survivors:int=0;var enemy_hp:int=0
	for row in model.actors:
		if row.team=="PARTY":hp+=int(row.hp);survivors+=1 if int(row.hp)>0 else 0
		else:enemy_hp+=int(row.hp)
	return {"seed":sample,"scenario":scenario,"policy":policy,"win":model.terminal=="승리","outcome":model.terminal if not model.terminal.is_empty() else "censored","turns":model.turn,"time":model.timeline.now,"party_hp":hp,"survivors":survivors,"enemy_hp":enemy_hp,"first_kill":model.first_kill,"invalid":invalid,"skills":kits,"species":species,"uses":model.uses,"body":model.body_bridge.summary()}

func run()->void:
	var n:int=64
	var output:String="/tmp/active-combat-sweep.json"
	var scenarios:Array=SCENARIOS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg=="--no-body":body_enabled=false
		if arg.begins_with("--scenario="):scenarios=[arg.trim_prefix("--scenario=")]
		if arg.begins_with("--seeds="):n=int(arg.trim_prefix("--seeds="))
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var rows:Array=[]
	var start:int=Time.get_ticks_msec()
	for scenario in scenarios:
		for sample in range(1,n+1):
			for policy in POLICIES:rows.append(trial(sample,scenario,policy))
		print("completed %s: %d battles / %.1fs"%[scenario,rows.size(),(Time.get_ticks_msec()-start)/1000.0])
	# Replay verification includes loadouts, outcome, action frequencies and time.
	var replay_ok:bool=rows[0]==trial(1,scenarios[0],POLICIES[0])
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:printerr("Cannot write results");quit(1);return
	file.store_string(JSON.stringify({"seed_count":n,"body_enabled":body_enabled,"replay_ok":replay_ok,"rows":rows},"\t"));file.close()
	print("saved %s replay=%s"%[output,replay_ok]);quit(0 if replay_ok else 1)
