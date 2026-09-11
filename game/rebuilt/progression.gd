extends RefCounted

const Loader=preload("res://sim/json_content_loader.gd")
static var DATA:Dictionary=Loader.load_document("res://data/content/rebuilt_progression.json")
const IDS=["MELEE","RANGED","MAGIC","DEFENSE"]

static func config_error()->String:
	for key in ["max_level","max_rank","xp_factor","points_per_level","attack_per_rank_milli","defense_per_rank_milli","defense_cap_milli","max_mp","starting_arrows","arrow_pickup","kill_xp_base","kill_xp_per_floor"]:
		if not integer(DATA.get(key)) or DATA[key]<0:return "invalid "+key
	if DATA.max_level<2 or DATA.max_level>100 or DATA.max_rank<1 or DATA.max_rank>100 or DATA.xp_factor<1 or DATA.points_per_level<1 or DATA.defense_cap_milli>=1000:return "invalid progression bounds"
	if not DATA.get("axes") is Array or DATA.axes.size()!=4:return "invalid axes"
	for i in range(4):
		if DATA.axes[i].id!=IDS[i]:return "axis mismatch"
	for id in ["SHOOT","FIREBOLT"]:
		var action:Variant=DATA.get("actions",{}).get(id)
		if not action is Dictionary or not integer(action.get("range")) or action.range<1 or action.range>6:return "invalid action"
	return ""

static func initialise(actor:Dictionary)->void:
	actor.growth={"xp":0,"level":1,"points":0,"ranks":{"MELEE":0,"RANGED":0,"MAGIC":0,"DEFENSE":0}}

static func threshold(level:int)->int:
	return int(DATA.xp_factor)*(level-1)*(level-1)

static func gain(actor:Dictionary,amount:int)->int:
	if amount<=0 or actor.hp<=0:return 0
	var g:Dictionary=actor.growth
	g.xp=mini(threshold(int(DATA.max_level)),int(g.xp)+amount)
	var before:int=g.level
	while int(g.level)<int(DATA.max_level) and int(g.xp)>=threshold(int(g.level)+1):
		g.level=int(g.level)+1;g.points=int(g.points)+int(DATA.points_per_level)
	return int(g.level)-before

static func invest(actor:Dictionary,axis:String)->bool:
	if axis not in IDS or actor.hp<=0:return false
	var g:Dictionary=actor.growth
	if int(g.points)<1 or int(g.ranks[axis])>=int(DATA.max_rank):return false
	g.points=int(g.points)-1;g.ranks[axis]=int(g.ranks[axis])+1
	return true

static func multiplier(actor:Dictionary,axis:String)->int:
	assert(axis in IDS and axis!="DEFENSE","Unmapped offensive effect")
	return 1000+int(actor.growth.ranks[axis])*int(DATA.attack_per_rank_milli)

static func scale(actor:Dictionary,axis:String,base:int)->int:
	return maxi(0,(base*multiplier(actor,axis)+500)/1000)

static func reduction(actor:Dictionary)->int:
	return mini(int(DATA.defense_cap_milli),int(actor.growth.ranks.DEFENSE)*int(DATA.defense_per_rank_milli))

static func defend(actor:Dictionary,damage:int)->int:
	if damage<=0:return 0
	return maxi(1,(damage*(1000-reduction(actor))+500)/1000)

static func preview(actor:Dictionary,axis:String)->String:
	var rank:int=actor.growth.ranks[axis]
	if axis=="DEFENSE":
		var current:=reduction(actor)
		var next:=mini(int(DATA.defense_cap_milli),(rank+1)*int(DATA.defense_per_rank_milli))
		return "피해 감소 %d%% → %d%%"%[current/10,next/10]
	var current:=multiplier(actor,axis)
	return "효과량 ×%.2f → ×%.2f"%[current/1000.0,(current+int(DATA.attack_per_rank_milli))/1000.0]

static func valid(value:Variant)->bool:
	if not value is Dictionary or value.size()!=4:return false
	for key in ["xp","level","points"]:
		if not integer(value.get(key)):return false
	if value.level<1 or value.level>DATA.max_level or value.xp<0 or value.xp>threshold(int(DATA.max_level)) or value.points<0:return false
	if value.xp<threshold(int(value.level)):return false
	if value.level<DATA.max_level and value.xp>=threshold(int(value.level)+1):return false
	if not value.get("ranks") is Dictionary or value.ranks.size()!=4:return false
	var spent:=0
	for axis in IDS:
		var rank:Variant=value.ranks.get(axis)
		if not integer(rank) or rank<0 or rank>DATA.max_rank:return false
		spent+=int(rank)
	return spent+int(value.points)==(int(value.level)-1)*int(DATA.points_per_level)

static func integer(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and value==floor(value)

static func normalized(value:Dictionary)->Dictionary:
	var result:Dictionary=value.duplicate(true)
	for key in ["xp","level","points"]:result[key]=int(result[key])
	for axis in IDS:result.ranks[axis]=int(result.ranks[axis])
	return result
