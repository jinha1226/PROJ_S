extends "res://game/crawl/world.gd"
## Usage-weighted combat skill progression for Model B.
const Progression=preload("res://game/crawl/progression_data.gd")
const USAGE_SKILLS := {"sword":"검술","spear":"창술","mace":"둔기술","axe":"도끼술","bow":"궁술","fire":"화염술","ice":"냉기술","air":"기류술","hex":"변이·제어","summon":"소환술"}
var combat_usage:Dictionary={}
var discovered_rewards:Dictionary={}
var discovered_fusions:Dictionary={}
var sword_chain:=0
var last_sword_target:=-1
var fire_momentum:=0

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
	var after=skill_rank(skill)
	if after>before:message("%s 숙련 %d"%[USAGE_SKILLS[skill],after]);refresh_unlocks(true)
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
	var usage:Dictionary=combat_usage[enemy_id];usage[skill]=int(usage.get(skill,0))+1;combat_usage[enemy_id]=usage
func award_usage_xp(enemy_id:int,kill_xp:int)->void:
	if kill_xp<=0:return
	var usage:Dictionary=combat_usage.get(enemy_id,{});combat_usage.erase(enemy_id)
	if usage.is_empty():return
	var total:=0
	for skill in usage:total+=int(usage[skill])
	var remaining:=kill_xp;var keys:Array=usage.keys()
	for i in range(keys.size()):
		var skill:String=str(keys[i]);var share:=remaining if i==keys.size()-1 else mini(remaining,maxi(0,int(round(float(kill_xp)*float(int(usage[skill]))/float(total)))))
		remaining-=share;add_skill_xp(skill,share)

func stats(a:Dictionary)->Dictionary:
	var s=super(a)
	if int(a.get("id",-1))!=0:return s
	if int(a.gear.weapon)>=0:
		var it:Dictionary=inventory[int(a.gear.weapon)];var w:Dictionary=DATA.weapons[it.type]
		var mastery:=skill_rank(weapon_skill(str(it.type)));var legacy:String="ranged" if str(w.trait)=="ranged" else "melee";var old:=skill_rank(legacy)
		s.damage+=mastery-old;s.delay=clampi(int(s.delay)+(old-mastery)*4,60,220)
		if weapon_skill(str(it.type))=="sword":
			# Sword passives: precision/damage cadence. Lv10 mastery is intentionally modest.
			s.damage+=skill_rank("sword")/2
			if skill_rank("sword")>=9:s.delay=maxi(60,int(s.delay)-8)
	return s

func attack(source:Dictionary,target:Dictionary)->void:
	var player:=int(source.get("id",-1))==0;var enemy_id:=int(target.get("id",-1));var sword:=false
	if player and enemy_id>0 and int(hero().gear.weapon)>=0:
		var it:Dictionary=inventory[int(hero().gear.weapon)];var skill:=weapon_skill(str(it.type));record_usage(enemy_id,skill);sword=skill=="sword"
	var hp_before:=int(target.hp);super(source,target)
	if player and sword and hp_before>int(target.hp) and int(target.hp)>0:
		var rank:=skill_rank("sword")
		# Sword Lv3/5/7/8: deeper cuts, counter-pressure represented as escalating follow-up damage.
		if rank>=3:damage(hero(),target,1+rank/3)
		if rank>=7 and last_sword_target==enemy_id:sword_chain=mini(3,sword_chain+1)
		else:sword_chain=1
		last_sword_target=enemy_id
		if rank>=7 and sword_chain>=2:damage(hero(),target,2)
		# Sword-main + fire-sub: weapon hit carries fire. Tier II leaves a burning tile.
		var sf:=fusion_tier("sword_fire")
		if sf>0:
			damage(hero(),target,3+skill_rank("fire"),"fire")
			if sf>=2:add_hazard(int(target.cell),"fire",300)
	if player and enemy_id>0 and hp_before>0 and int(target.hp)<=0:award_usage_xp(enemy_id,18+depth()*8)

func cast(id:String,target:int)->bool:
	var skill:String=str(DATA.spells[id].school) if DATA.spells.has(id) else "";var fire_target:Dictionary={}
	if skill=="fire" and target>=0 and target<occupancy.size() and occupancy[target]>0:fire_target=actors[occupancy[target]]
	var accepted=super(id,target)
	if not accepted or skill.is_empty():return accepted
	var actor_id:=-1
	if target>=0:
		var a=actor_at(target)
		if a!=null and int(a.get("id",-1))>0:actor_id=int(a.id)
	if actor_id>0:record_usage(actor_id,skill)
	else:
		for enemy in visible_enemies():record_usage(int(enemy.id),skill)
	if skill=="fire":
		var rank:=skill_rank("fire");fire_momentum=mini(3,fire_momentum+1)
		# Fire Lv2/4/6/8/9: heat momentum improves subsequent successful fire casts.
		if not fire_target.is_empty() and int(fire_target.hp)>0:
			var bonus:=0
			if rank>=2:bonus+=1
			if rank>=4:bonus+=1
			if rank>=6:bonus+=1
			if rank>=8:bonus+=fire_momentum
			if rank>=9:bonus+=2
			if bonus>0:damage(hero(),fire_target,bonus,"fire")
		# Fire-main + sword-sub: spells form a blade echo around the victim. This is deliberately
		# spell-triggered, so the reverse ordering plays differently from 화염검.
		var fs:=fusion_tier("fire_sword")
		if fs>0 and not fire_target.is_empty() and int(fire_target.hp)>0:
			damage(hero(),fire_target,2+skill_rank("sword"))
			if fs>=2:
				for other in actors:
					if other.id!=fire_target.id and other.floor==floor_id and other.team=="enemy" and other.hp>0 and position(other.cell).distance_squared_to(position(fire_target.cell))<=2:damage(hero(),other,3+skill_rank("sword")/2,"fire")
	return true
func gain_xp(amount:int)->void:
	xp+=amount
	while level<12 and xp>=level*level*65:level+=1;hero().max_hp+=4;hero().hp+=4;hero().max_mp+=1;hero().mp+=1;message("레벨 %d"%level)
	emit("growth.xp",0,-1,amount)
