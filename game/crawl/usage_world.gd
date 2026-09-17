extends "res://game/crawl/world.gd"
## Usage-weighted combat skill progression for Model B.
const Progression=preload("res://game/crawl/progression_data.gd")

const USAGE_SKILLS := {
	"sword":"검술","spear":"창술","mace":"둔기술","axe":"도끼술","bow":"궁술",
	"fire":"화염술","ice":"냉기술","air":"기류술","hex":"변이·제어","summon":"소환술"
}
var combat_usage:Dictionary={}
var discovered_rewards:Dictionary={}
var discovered_fusions:Dictionary={}

func _init(p_seed:int=44,species:String="human") -> void:
	super(p_seed,species)
	for id in USAGE_SKILLS:
		if not skills.has(id):skills[id]=0
	focus=["melee"]
	refresh_unlocks(false)

func weapon_skill(weapon_type:String)->String:
	match weapon_type:
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
	var before=skill_rank(skill)
	var amount=maxi(1,base_amount*aptitude_for(skill)/100)
	if god=="bind" and bound_weapon>=0 and skill in ["sword","spear","mace","axe","bow"]:amount=amount*13/10
	skills[skill]=int(skills.get(skill,0))+amount
	var after=skill_rank(skill)
	if after>before:
		message("%s 숙련 %d"%[USAGE_SKILLS[skill],after])
		refresh_unlocks(true)
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

func unlocked_rewards(skill:String)->Array:
	return Progression.rewards_for(skill,skill_rank(skill))

func unlocked_fusions()->Array:
	return Progression.unlocked_fusions(skills)

func record_usage(enemy_id:int,skill:String)->void:
	if enemy_id<=0 or not USAGE_SKILLS.has(skill):return
	if not combat_usage.has(enemy_id):combat_usage[enemy_id]={}
	var usage:Dictionary=combat_usage[enemy_id]
	usage[skill]=int(usage.get(skill,0))+1
	combat_usage[enemy_id]=usage

func award_usage_xp(enemy_id:int,kill_xp:int)->void:
	if kill_xp<=0:return
	var usage:Dictionary=combat_usage.get(enemy_id,{})
	combat_usage.erase(enemy_id)
	if usage.is_empty():return
	var total_uses:=0
	for skill in usage:total_uses+=int(usage[skill])
	if total_uses<=0:return
	var remaining:=kill_xp
	var keys:Array=usage.keys()
	for i in range(keys.size()):
		var skill:String=str(keys[i]);var share:int
		if i==keys.size()-1:share=remaining
		else:
			share=maxi(0,int(round(float(kill_xp)*float(int(usage[skill]))/float(total_uses))))
			share=mini(share,remaining)
		remaining-=share
		add_skill_xp(skill,share)

func stats(a:Dictionary)->Dictionary:
	var s=super(a)
	if int(a.get("id",-1))!=0:return s
	var gear:Dictionary=a.gear
	if int(gear.weapon)>=0:
		var it:Dictionary=inventory[int(gear.weapon)];var w:Dictionary=DATA.weapons[it.type]
		var mastery:=skill_rank(weapon_skill(str(it.type)))
		var legacy_skill:String="ranged" if str(w.trait)=="ranged" else "melee"
		var legacy_mastery:=skill_rank(legacy_skill)
		s.damage+=mastery-legacy_mastery
		s.delay=clampi(int(s.delay)+(legacy_mastery-mastery)*4,60,220)
	return s

func attack(source:Dictionary,target:Dictionary)->void:
	var player_attack:=int(source.get("id",-1))==0
	var enemy_id:=int(target.get("id",-1))
	if player_attack and enemy_id>0 and int(hero().gear.weapon)>=0:
		var it:Dictionary=inventory[int(hero().gear.weapon)]
		record_usage(enemy_id,weapon_skill(str(it.type)))
	var hp_before:=int(target.hp)
	super(source,target)
	if player_attack and enemy_id>0 and hp_before>0 and int(target.hp)<=0:
		award_usage_xp(enemy_id,int(target.get("xp",0)))

func cast(id:String,target:int)->bool:
	var accepted=super(id,target)
	if not accepted or not DATA.spells.has(id):return accepted
	var skill:String=str(DATA.spells[id].school);var actor_id:=-1
	if target>=0:
		var a=actor_at(target)
		if a!=null and int(a.get("id",-1))>0:actor_id=int(a.id)
	if actor_id>0:record_usage(actor_id,skill)
	else:
		for enemy in visible_enemies():record_usage(int(enemy.id),skill)
	return true

func gain_xp(amount:int)->void:
	xp+=amount
	while level<12 and xp>=level*level*65:
		level+=1;hero().max_hp+=4;hero().hp+=4;hero().max_mp+=1;hero().mp+=1
		message("레벨 %d"%level)
	emit("growth.xp",0,-1,amount)
