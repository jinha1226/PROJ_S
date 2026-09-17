extends "res://game/crawl/world.gd"
## Usage-weighted combat skill progression for Model B.
const Progression=preload("res://game/crawl/progression_data.gd")
const USAGE_SKILLS := {"sword":"검술","spear":"창술","mace":"둔기술","axe":"도끼술","bow":"궁술","fire":"화염술","ice":"냉기술","air":"기류술","hex":"변이·제어","summon":"소환술"}
var combat_usage:Dictionary={};var discovered_rewards:Dictionary={};var discovered_fusions:Dictionary={}
var weapon_chain:Dictionary={};var magic_momentum:Dictionary={"fire":0,"ice":0,"air":0,"hex":0,"summon":0}
func _init(p_seed:int=44,species:String="human") -> void:
	super(p_seed,species)
	for id in USAGE_SKILLS:
		if not skills.has(id):skills[id]=0
	focus=["melee"];refresh_unlocks(false)
func weapon_skill(t:String)->String:
	match t:
		"sword","dagger":return "sword"
		"spear":return "spear"
		"mace","staff":return "mace"
		"axe":return "axe"
		"bow":return "bow"
		_:return "sword"
func aptitude_for(skill:String)->int:
	var apt:Dictionary=DATA.species[hero().species].apt
	if apt.has(skill):return int(apt[skill])
	if skill in ["sword","spear","mace","axe"]:return int(apt.get("melee",100))
	if skill=="bow":return int(apt.get("ranged",100))
	return int(apt.get(skill,100))
func add_skill_xp(skill:String,base_amount:int)->void:
	if not USAGE_SKILLS.has(skill) or base_amount<=0:return
	var before=skill_rank(skill);var amount=maxi(1,base_amount*aptitude_for(skill)/100)
	if god=="bind" and bound_weapon>=0 and skill in ["sword","spear","mace","axe","bow"]:amount=amount*13/10
	skills[skill]=int(skills.get(skill,0))+amount
	if skill_rank(skill)>before:message("%s 숙련 %d"%[USAGE_SKILLS[skill],skill_rank(skill)]);refresh_unlocks(true)
	emit("growth.skill",0,-1,amount)
func refresh_unlocks(announce:bool=true)->void:
	for skill in USAGE_SKILLS:
		for reward in Progression.rewards_for(skill,skill_rank(skill)):
			var key:String="%s:%d"%[skill,int(reward.level)]
			if discovered_rewards.has(key):continue
			discovered_rewards[key]=true
			if announce:message("해금 · %s Lv%d · %s"%[USAGE_SKILLS[skill],int(reward.level),str(reward.name)])
	for fusion in Progression.unlocked_fusions(skills):
		var key:String="%s:%d"%[str(fusion.id),int(fusion.tier)]
		if discovered_fusions.has(key):continue
		discovered_fusions[key]=true
		if announce:message("융합 발견 · %s"%str(fusion.display_name))
func unlocked_rewards(skill:String)->Array:return Progression.rewards_for(skill,skill_rank(skill))
func unlocked_fusions()->Array:return Progression.unlocked_fusions(skills)
func fusion_tier(id:String)->int:
	for row in unlocked_fusions():
		if str(row.id)==id:return int(row.tier)
	return 0
func record_usage(enemy_id:int,skill:String)->void:
	if enemy_id<=0 or not USAGE_SKILLS.has(skill):return
	if not combat_usage.has(enemy_id):combat_usage[enemy_id]={}
	var u:Dictionary=combat_usage[enemy_id];u[skill]=int(u.get(skill,0))+1;combat_usage[enemy_id]=u
func award_usage_xp(enemy_id:int,kill_xp:int)->void:
	var u:Dictionary=combat_usage.get(enemy_id,{});combat_usage.erase(enemy_id)
	if kill_xp<=0 or u.is_empty():return
	var total:=0
	for skill in u:total+=int(u[skill])
	var remaining:=kill_xp;var keys:Array=u.keys()
	for i in range(keys.size()):
		var skill:String=str(keys[i]);var share:=remaining if i==keys.size()-1 else mini(remaining,maxi(0,int(round(float(kill_xp)*float(int(u[skill]))/float(total)))))
		remaining-=share;add_skill_xp(skill,share)
func stats(a:Dictionary)->Dictionary:
	var s=super(a)
	if int(a.get("id",-1))!=0:return s
	if int(a.gear.weapon)>=0:
		var it:Dictionary=inventory[int(a.gear.weapon)];var w:Dictionary=DATA.weapons[it.type];var skill:=weapon_skill(str(it.type));var rank:=skill_rank(skill)
		var legacy:String="ranged" if str(w.trait)=="ranged" else "melee";var old:=skill_rank(legacy)
		s.damage+=rank-old;s.delay=clampi(int(s.delay)+(old-rank)*4,60,220)
		if skill=="sword":s.damage+=rank/2
		elif skill=="spear":s.damage+=rank/3
		elif skill=="mace":s.damage+=rank/2
		elif skill=="axe":s.damage+=rank/2
		elif skill=="bow":s.damage+=rank/3
		if rank>=9:s.delay=maxi(60,int(s.delay)-8)
	return s
func apply_weapon_fusions(skill:String,target:Dictionary)->void:
	var rank:=skill_rank(skill)
	if rank>=3:damage(hero(),target,1+rank/3)
	var chain:=int(weapon_chain.get(skill+":"+str(target.id),0))+1;weapon_chain[skill+":"+str(target.id)]=chain
	if rank>=7 and chain>=2:damage(hero(),target,2)
	var pairs:Dictionary={
		"sword":[["sword_fire","fire"],["sword_ice","ice"],["sword_hex","hex"]],
		"spear":[["spear_ice","ice"],["spear_air","air"]],
		"mace":[["mace_fire","fire"],["mace_air","air"]],
		"axe":[["axe_fire","fire"],["axe_summon","summon"]],
		"bow":[["bow_fire","fire"],["bow_ice","ice"],["bow_hex","hex"]]}
	for pair in pairs.get(skill,[]):
		var tier:=fusion_tier(str(pair[0]));var element:String=str(pair[1])
		if tier<=0:continue
		match element:
			"fire":damage(hero(),target,3+skill_rank("fire"),"fire");if tier>=2:add_hazard(int(target.cell),"fire",300)
			"ice":damage(hero(),target,2+skill_rank("ice"),"ice");target.statuses.slow=time+(300 if tier>=2 else 180)
			"air":damage(hero(),target,2+skill_rank("air"),"air");if tier>=2:chain_element(target,"air",3+skill_rank("air")/2)
			"hex":target.statuses.confuse=time+(300 if tier>=2 else 180)
			"summon":
				if tier>=2 and int(target.hp)<=maxi(8,int(target.max_hp)/3):spawn_fusion_minion("처형의 잔영",int(target.cell),skill_rank("summon"))
func chain_element(origin:Dictionary,element:String,power:int)->void:
	for other in actors:
		if other.id!=origin.id and other.floor==floor_id and other.team=="enemy" and other.hp>0 and position(other.cell).distance_squared_to(position(origin.cell))<=4:damage(hero(),other,power,element);return
func spawn_fusion_minion(name:String,near_cell:int,power:int)->void:
	var c=free_near(near_cell)
	if c<0:return
	var a=spawn({"id":"fusion","name":name,"sprite":"human","hp":12+power*2,"power":4+power,"speed":100,"ac":1,"ev":4,"will":100,"ai":"guardian","res":{"poison":100}},floor_id,c,"ally",400);occupancy[c]=int(a.id)
func attack(source:Dictionary,target:Dictionary)->void:
	var player:=int(source.get("id",-1))==0;var enemy_id:=int(target.get("id",-1));var skill:=""
	if player and enemy_id>0 and int(hero().gear.weapon)>=0:skill=weapon_skill(str(inventory[int(hero().gear.weapon)].type));record_usage(enemy_id,skill)
	var hp_before:=int(target.hp);super(source,target)
	if player and not skill.is_empty() and hp_before>int(target.hp) and int(target.hp)>0:apply_weapon_fusions(skill,target)
	if player and enemy_id>0 and hp_before>0 and int(target.hp)<=0:award_usage_xp(enemy_id,18+depth()*8)
func apply_magic_progression(skill:String,target:Dictionary)->void:
	var rank:=skill_rank(skill);magic_momentum[skill]=mini(3,int(magic_momentum.get(skill,0))+1)
	if target.is_empty() or int(target.hp)<=0:return
	var bonus:=0
	if rank>=2:bonus+=1
	if rank>=4:bonus+=1
	if rank>=6:bonus+=1
	if rank>=8:bonus+=int(magic_momentum[skill])
	if rank>=9:bonus+=2
	if bonus>0 and skill in ["fire","ice","air"]:damage(hero(),target,bonus,skill)
	if skill=="ice" and rank>=5:target.statuses.slow=time+300
	if skill=="hex" and rank>=5:target.statuses.confuse=time+300
func apply_reverse_fusions(skill:String,target:Dictionary)->void:
	if target.is_empty() or int(target.hp)<=0:return
	var weapon_ids:Array=["sword","spear","mace","axe","bow"]
	for weapon in weapon_ids:
		var id:=skill+"_"+weapon;var tier:=fusion_tier(id)
		if tier<=0:continue
		damage(hero(),target,2+skill_rank(weapon))
		if tier>=2:chain_element(target,"fire" if skill=="fire" else "ice" if skill=="ice" else "air",3+skill_rank(weapon)/2)
	# Symmetric magic combinations: their identity comes from the pair, not main/sub order.
	var magic_pairs:Dictionary={"fire_air":["fire","air","fire"],"fire_summon":["fire","summon","fire"],"ice_air":["ice","air","ice"],"ice_summon":["ice","summon","ice"],"air_summon":["air","summon","air"],"hex_summon":["hex","summon","air"]}
	for id in magic_pairs:
		var row:Array=magic_pairs[id]
		if skill not in [row[0],row[1]]:continue
		var tier:=fusion_tier(id)
		if tier<=0:continue
		if row[1]=="summon":
			spawn_fusion_minion("융합 정령",int(target.cell),skill_rank("summon")+tier)
		else:
			damage(hero(),target,3+skill_rank(str(row[0]))+skill_rank(str(row[1]))/2,str(row[2]))
			if tier>=2:chain_element(target,str(row[2]),4+skill_rank(str(row[1])))
func cast(id:String,target:int)->bool:
	var skill:String=str(DATA.spells[id].school) if DATA.spells.has(id) else "";var victim:Dictionary={}
	if target>=0 and target<occupancy.size() and occupancy[target]>0:victim=actors[occupancy[target]]
	var accepted=super(id,target)
	if not accepted or skill.is_empty():return accepted
	var actor_id:=int(victim.get("id",-1))
	if actor_id>0:record_usage(actor_id,skill)
	else:
		for enemy in visible_enemies():record_usage(int(enemy.id),skill)
	apply_magic_progression(skill,victim);apply_reverse_fusions(skill,victim);return true
func gain_xp(amount:int)->void:
	xp+=amount
	while level<12 and xp>=level*level*65:level+=1;hero().max_hp+=4;hero().hp+=4;hero().max_mp+=1;hero().mp+=1;message("레벨 %d"%level)
	emit("growth.xp",0,-1,amount)
