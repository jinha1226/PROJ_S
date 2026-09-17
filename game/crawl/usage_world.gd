extends "res://game/crawl/world.gd"
## Usage-based skill progression for Model B.
## Skills improve from the action that actually uses them; kill XP only drives character level.

const USAGE_SKILLS := {
	"sword": "검술",
	"spear": "창술",
	"mace": "둔기술",
	"axe": "도끼술",
	"bow": "궁술",
	"fire": "화염술",
	"ice": "냉기술",
	"air": "기류술",
	"hex": "변이·제어",
	"summon": "소환술",
	"armour": "갑옷술",
	"dodge": "회피술",
	"stealth": "은신술",
	"tools": "도구술"
}
const PRACTICE_ATTACK := 12
const PRACTICE_SPELL := 16
const PRACTICE_DEFENSE := 8
const PRACTICE_MOVE := 2
const PRACTICE_TOOL := 10

func _init(p_seed:int=44,species:String="human") -> void:
	super(p_seed,species)
	for id in USAGE_SKILLS:
		if not skills.has(id):skills[id]=0
	# Legacy focus remains serialized only for backwards save compatibility.
	focus=["melee"]

func weapon_skill(weapon_type:String)->String:
	match weapon_type:
		"sword","dagger":return "sword"
		"spear":return "spear"
		"mace":return "mace"
		"axe":return "axe"
		"bow":return "bow"
		# Staff is a general magical implement; physical staff blows train blunt technique.
		"staff":return "mace"
		_:return "sword"

func aptitude_for(skill:String)->int:
	var apt:Dictionary=DATA.species[hero().species].apt
	if apt.has(skill):return int(apt[skill])
	if skill in ["sword","spear","mace","axe"]:return int(apt.get("melee",100))
	if skill=="bow":return int(apt.get("ranged",100))
	if skill=="armour":return int(apt.get("defense",100))
	if skill in ["dodge","stealth"]:return int(apt.get("survival",100))
	return int(apt.get(skill,100))

func practice(skill:String,base_amount:int)->void:
	if not USAGE_SKILLS.has(skill) or base_amount<=0:return
	var before=skill_rank(skill)
	var amount=maxi(1,base_amount*aptitude_for(skill)/100)
	if god=="bind" and bound_weapon>=0 and skill in ["sword","spear","mace","axe","bow"]:amount=amount*13/10
	skills[skill]=int(skills.get(skill,0))+amount
	var after=skill_rank(skill)
	if after>before:message("%s 숙련 %d"%[USAGE_SKILLS[skill],after])
	emit("growth.skill",0,-1,amount)

func stats(a:Dictionary)->Dictionary:
	var s={"damage":int(a.power),"delay":100,"ac":int(a.ac),"ev":int(a.ev),"sh":0,"enc":0,"range":1,"brand":"","trait":"","res":a.res.duplicate(),"power":0}
	if int(a.id)==0:
		var spec:Dictionary=DATA.species[a.species]
		var gear:Dictionary=a.gear
		if int(gear.weapon)>=0:
			var it:Dictionary=inventory[int(gear.weapon)];var w:Dictionary=DATA.weapons[it.type]
			var mastery=skill_rank(weapon_skill(str(it.type)))
			s.damage=int(w.damage)+int(it.enchant)+mastery+int(spec.str)/6
			s.delay=maxi(60,int(w.delay)-mastery*4);s.range=int(w.range);s.trait=w.trait;s.brand=it.brand
			if w.trait=="focus":s.power+=4
		if int(gear.armour)>=0:
			var armour:Dictionary=inventory[int(gear.armour)];var ar:Dictionary=DATA.armours[armour.type]
			var armour_rank=skill_rank("armour")
			s.ac+=int(ar.ac)+int(armour.enchant)+armour_rank/3
			s.enc=maxi(0,int(ar.enc)-int(spec.str)/5-armour_rank/2)
			s.ev-=int(ar.ev_penalty)
		s.ev+=int(spec.dex)/3+skill_rank("dodge")/2
		if int(gear.shield)>=0 and s.trait not in ["ranged","focus"]:s.sh=mini(35,15+skill_rank("armour")*2);s.enc+=2
		if int(gear.ring)>=0:
			var ring:Dictionary=DATA.rings[inventory[int(gear.ring)].type]
			if ring.stat in ["ev","power"]:s[ring.stat]+=int(ring.value)
			else:s.res[ring.stat]=int(ring.value)
		if god=="war" and piety>=20:s.damage+=3
		if bound_weapon>=0 and god=="bind":s.power+=3
	if a.statuses.has("ward"):s.ac+=6
	if a.statuses.has("rage"):s.damage+=8
	if a.statuses.has("corrode"):s.ac=maxi(0,int(s.ac)-4)
	return s

func submit(kind:String,target:int=-1,value:String="")->bool:
	var start_cell=int(hero().cell)
	var accepted=super(kind,target,value)
	if not accepted:return false
	if kind=="MOVE" and int(hero().cell)!=start_cell:
		practice("dodge",PRACTICE_MOVE)
		if visible_enemies().is_empty():practice("stealth",PRACTICE_MOVE)
	elif kind=="USE" and value=="wand":practice("tools",PRACTICE_TOOL)
	return true

func attack(source:Dictionary,target:Dictionary)->void:
	if int(source.get("id",-1))==0 and int(hero().gear.weapon)>=0:
		var it:Dictionary=inventory[int(hero().gear.weapon)]
		practice(weapon_skill(str(it.type)),PRACTICE_ATTACK)
	var hp_before=int(target.hp)
	super(source,target)
	if int(target.get("id",-1))==0:
		# Being attacked while wearing armour trains armour handling; avoiding all HP loss trains evasion.
		if int(hero().gear.armour)>=0:practice("armour",PRACTICE_DEFENSE)
		if int(target.hp)==hp_before:practice("dodge",PRACTICE_DEFENSE)

func cast(id:String,target:int)->bool:
	var accepted=super(id,target)
	if accepted and DATA.spells.has(id):practice(str(DATA.spells[id].school),PRACTICE_SPELL)
	return accepted

func gain_xp(amount:int)->void:
	# Kill XP raises only the adventurer level. Skill XP comes from practice().
	xp+=amount
	while level<12 and xp>=level*level*65:
		level+=1;hero().max_hp+=4;hero().hp+=4;hero().max_mp+=1;hero().mp+=1
		message("레벨 %d · 숙련은 사용한 행동으로 성장합니다."%level)
	emit("growth.xp",0,-1,amount)
