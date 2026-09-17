extends RefCounted
## Model B simulation. UI never advances time except through submit().
## Future body/personality/absorption adapters consume these semantic events.
signal integration_event(event:Dictionary)
static var DATA = preload("res://sim/json_content_loader.gd").load_document("res://data/content/crawl.json")
const Map = preload("res://playtest/deterministic_dungeon_map.gd")
const Kernel = preload("res://sim/combat_kernel.gd")
const Turns = preload("res://sim/turn_engine.gd")
const Navigation = preload("res://game/rebuilt/navigation.gd")
const WIDTH = 40
const HEIGHT = 40
const SCHEMA = 1
var floor_number:int:
	get:return DATA.floors.keys().find(floor_id)+1
var seed:int
var rng = RandomNumberGenerator.new()
var time = 0
var boundary = 100
var serial = 0
var floor_id = "D1"
var floors:Dictionary = {}
var actors:Array[Dictionary] = []
var inventory:Array[Dictionary] = []
var kin_sacrifice=0
var supplies = {"heal":3,"blink":2,"haste":1,"fog":1,"wand":4}
var spells:Array = ["bolt","blink"]
var prepared:Array = ["bolt","blink"]
var skills:Dictionary = {}
var focus:Array = ["melee","survival"]
var xp = 0
var level = 1
var god = ""
var piety = 0
var penance = 0
var bound_weapon = -1
var runes:Array = []
var orb = false
var won = false
var log:Array[String] = []
var effects:Array[Dictionary] = []
var terrain = PackedStringArray()
var memory = PackedByteArray()
var visible = PackedByteArray()
var visible_cells = PackedInt32Array()
var occupancy = PackedInt32Array()
var route_steps = PackedInt32Array()
var auto_explore = false
var resting = false
var navigation = Navigation.new()
var discovery = false
var last_error = ""

func _init(p_seed:int=44,species:String="human") -> void:
	seed=p_seed;rng.seed=seed
	for key in DATA.skills:skills[key]=0
	var spec:Dictionary=DATA.species.get(species,DATA.species.human)
	actors.append({"id":0,"name":spec.name,"species":species,"sprite":species,"team":"hero","floor":"D1","cell":0,"hp":int(spec.hp),"max_hp":int(spec.hp),"mp":int(spec.mp),"max_mp":int(spec.mp),"ready":0,"power":8,"speed":100,"ac":0,"ev":4,"will":30,"ai":"hero","res":{},"statuses":{},"last_seen":-1,"expires":0,"summoned":false,"gear":{"weapon":0,"armour":1,"ring":-1,"shield":-1}})
	inventory=[item("weapon","sword"),item("armour","leather"),item("shield","buckler")]
	if species=="elf":inventory[0]=item("weapon","staff");inventory[1]=item("armour","robe");focus=["fire","air"]
	enter_floor("D1","")
	message("두 분기의 룬을 모아 오브를 가져오세요. 행동할 때만 시간이 흐릅니다.")

func index(p:Vector2i)->int:return p.y*WIDTH+p.x
func position(cell:int)->Vector2i:return Vector2i(cell%WIDTH,cell/WIDTH)
func in_bounds(p:Vector2i)->bool:return p.x>=0 and p.y>=0 and p.x<WIDTH and p.y<HEIGHT
func blocked(cell:int)->bool:return cell<0 or cell>=terrain.size() or terrain[cell]=="wall"
func solid(p:Vector2i)->bool:return not in_bounds(p) or blocked(index(p))
func open_edge(a:int,b:int)->bool:return not blocked(b) and Kernel.open_edge(position(a),position(b),solid)
func move_cost(cell:int)->int:return 140 if terrain[cell]=="shallow_water" else 120 if terrain[cell]=="rubble" else 100
func hero()->Dictionary:return actors[0]
func terminal()->bool:return hero().hp<=0 or won
func friendly(a:Dictionary)->bool:return a.team!="enemy"
func current()->Dictionary:return floors[floor_id]
func floor_name()->String:return DATA.floors[floor_id].name
func depth()->int:return int(DATA.floors[floor_id].depth)
func message(value:String)->void:
	log.append(value)
	if log.size()>60:log.pop_front()
func reject(value:String)->bool:
	last_error=value;message(value);return false
func emit(kind:String,source:int=-1,target:int=-1,amount:int=0)->void:
	serial+=1;integration_event.emit({"id":serial,"time":time,"type":kind,"actor":source,"target":target,"amount":amount,"floor":floor_id})
func item(category:String,id:String,brand:String="",enchant:int=0)->Dictionary:
	return {"category":category,"type":id,"brand":brand,"enchant":enchant,"artefact":false,"destroyed":false}
func item_name(it:Dictionary)->String:
	var table:Dictionary=DATA.get({"weapon":"weapons","armour":"armours","ring":"rings"}.get(it.category,""),{})
	var name:String=table.get(it.type,{}).get("name","방패")
	return "%s%s%s%s"%["유물 " if it.artefact else "",name," +%d"%int(it.enchant) if int(it.enchant)>0 else "",(" · "+str(it.brand)) if not str(it.brand).is_empty() else ""]
func skill_rank(id:String)->int:return mini(12,int(sqrt(float(skills.get(id,0))/25.0)))
func stats(a:Dictionary)->Dictionary:
	var s={"damage":int(a.power),"delay":100,"ac":int(a.ac),"ev":int(a.ev),"sh":0,"enc":0,"range":1,"brand":"","trait":"","res":a.res.duplicate(),"power":0}
	if int(a.id)==0:
		var spec:Dictionary=DATA.species[a.species]
		var gear:Dictionary=a.gear
		if int(gear.weapon)>=0:
			var it:Dictionary=inventory[int(gear.weapon)];var w:Dictionary=DATA.weapons[it.type]
			s.damage=int(w.damage)+int(it.enchant)+skill_rank(w.axis)+int(spec.str)/6
			s.delay=maxi(60,int(w.delay)-skill_rank(w.axis)*4);s.range=int(w.range);s.trait=w.trait;s.brand=it.brand
			if w.trait=="focus":s.power+=4
		if int(gear.armour)>=0:
			var it:Dictionary=inventory[int(gear.armour)];var ar:Dictionary=DATA.armours[it.type]
			s.ac+=int(ar.ac)+int(it.enchant)+skill_rank("defense")/3;s.enc=maxi(0,int(ar.enc)-int(spec.str)/5-skill_rank("defense")/2)
			s.ev-=int(ar.ev_penalty)
		s.ev+=int(spec.dex)/3+skill_rank("survival")/2
		if int(gear.shield)>=0 and s.trait not in ["ranged","focus"]:s.sh=mini(35,15+skill_rank("defense")*2);s.enc+=2
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
func failure(id:String)->int:
	var sp:Dictionary=DATA.spells[id]
	return clampi(8+int(sp.level)*9+int(stats(hero()).enc)*5-skill_rank(sp.school)*5-int(DATA.species[hero().species].int),0,85)
func movement_time(a:Dictionary,cell:int)->int:
	var value=maxi(int(a.speed),move_cost(cell))
	if a.ai=="skirmish":value=int(a.speed)
	if a.statuses.has("slow"):value=value*3/2
	if a.statuses.has("haste"):value=value*2/3
	return maxi(40,value)
func visible_enemies()->Array[int]:
	var result:Array[int]=[]
	for c in visible_cells:
		var id=occupancy[c]
		if id>0 and actors[id].team=="enemy":result.append(id)
	return result
func update_sight()->void:
	visible.fill(0);visible_cells.clear()
	var p=position(hero().cell)
	for y in range(maxi(0,p.y-6),mini(HEIGHT,p.y+7)):
		for x in range(maxi(0,p.x-6),mini(WIDTH,p.x+7)):
			var cell=index(Vector2i(x,y))
			if not Kernel.sees(p,Vector2i(x,y),solid):continue
			# Fog blocks vision beyond its first cell along an integer ray.
			var obscured=false
			var dist=maxi(absi(x-p.x),absi(y-p.y))
			for step in range(1,dist):
				var mid=Vector2i(Vector2(p).lerp(Vector2(x,y),float(step)/dist).round())
				if current().hazards.get(str(index(mid)),{}).get("kind","")=="fog":obscured=true;break
			if obscured:continue
			visible[cell]=1;visible_cells.append(cell)
			if memory[cell]==0 and (current().features.has(str(cell)) or current().loot.has(str(cell))):discovery=true
			memory[cell]=1
	current().memory=Array(memory)
func rebuild_occupancy()->void:
	occupancy.resize(WIDTH*HEIGHT);occupancy.fill(-1)
	for a in actors:
		if a.floor==floor_id and a.hp>0:occupancy[int(a.cell)]=int(a.id)
func free_near(origin:int)->int:
	for d in Kernel.DIRECTIONS:
		var p=position(origin)+d
		if in_bounds(p) and open_edge(origin,index(p)) and occupancy[index(p)]<0:return index(p)
	return -1
func move_actor(a:Dictionary,to:int)->void:
	var old=int(a.cell);occupancy[old]=-1;occupancy[to]=int(a.id);a.cell=to
	effects.append({"kind":"move","actor":a.id,"from":old,"to":to})
	emit("actor.moved",int(a.id),-1,to)

func generate(id:String)->void:
	var definition:Dictionary=DATA.floors[id]
	var local_rng=RandomNumberGenerator.new();local_rng.seed=seed+DATA.floors.keys().find(id)*7919
	var layout:Dictionary=Map.generate(WIDTH,HEIGHT,local_rng.seed)
	var tiles:Array=layout.terrain.duplicate()
	# Reuse sector rooms, then add cross connections so retreat is not a snake.
	for n in range(3):
		var a:Vector2i=layout.rooms[local_rng.randi_range(0,layout.rooms.size()-1)].get_center()
		var b:Vector2i=layout.rooms[local_rng.randi_range(0,layout.rooms.size()-1)].get_center()
		while a!=b:
			tiles[index(a)]="floor"
			if a.x!=b.x:a.x+=signi(b.x-a.x)
			else:a.y+=signi(b.y-a.y)
	var floor={"terrain":tiles,"memory":[],"features":{},"loot":{},"hazards":{},"entry":index(layout.hero_position),"generated":true}
	var blanks=PackedByteArray();blanks.resize(WIDTH*HEIGHT);blanks.fill(0);floor.memory=Array(blanks)
	var candidates:Array[int]=[]
	for c in range(tiles.size()):
		if tiles[c]=="wall":continue
		# Only branch-relevant materials have mechanics; no hidden food/light tax.
		if tiles[c] in ["fog","grass","metal","wood_floor","ice"]:tiles[c]="floor"
		if definition.theme=="water" and c%5<2:tiles[c]="shallow_water"
		if definition.theme=="fire" and c%7<2:tiles[c]="rubble"
		if position(c).distance_squared_to(layout.hero_position)>49:candidates.append(c)
	# Seeded Fisher-Yates, isolated from combat RNG.
	for i in range(candidates.size()-1,0,-1):
		var j=local_rng.randi_range(0,i);var temp=candidates[i];candidates[i]=candidates[j];candidates[j]=temp
	var exit=index(layout.exit_position)
	floor.features[str(floor.entry)]={"kind":"stairs","to":"OUT" if id=="D1" else definition.links[0]}
	var destinations:Array=definition.links.duplicate()
	if id!="D1":destinations.pop_front()
	for target in destinations:
		var cell=exit if floor.features.size()==1 else candidates.pop_back()
		floor.features[str(cell)]={"kind":"stairs","to":target}
	if id=="D2":
		for deity in DATA.gods:floor.features[str(candidates.pop_back())]={"kind":"altar","god":deity}
	if definition.has("rune"):floor.features[str(exit)]={"kind":"rune","id":definition.rune}
	if id=="Z":floor.features[str(exit)]={"kind":"orb"}
	# Small guarded cache / optional vault; risk and reward share the same room.
	var vault_cell=candidates.pop_back()
	if int(definition.depth)>1:
		var vault_room:Rect2i=layout.rooms[4]
		var center=index(vault_room.get_center())
		if not floor.features.has(str(center)):vault_cell=center;candidates.erase(center)
		floor.vault_id="pillar_court" if local_rng.randi_range(0,1)==0 else "flooded_cache"
		for y in range(vault_room.position.y+1,vault_room.end.y-1):
			for x in range(vault_room.position.x+1,vault_room.end.x-1):
				var c=index(Vector2i(x,y))
				if c==vault_cell or floor.features.has(str(c)):continue
				if floor.vault_id=="flooded_cache":tiles[c]="shallow_water"
				elif x%3==0 and y%3==0:tiles[c]="wall";candidates.erase(c)
	floor.features[str(vault_cell)]={"kind":"cache"}
	var pool:Array=[];var total=0
	for m in DATA.monsters:
		if int(m.weight)<=0 or int(m.depth)>int(definition.depth):continue
		if not str(m.branch).is_empty() and m.branch!=definition.theme:continue
		var candidate:Dictionary=m.duplicate(true)
		candidate.weight=maxi(1,int(m.weight)/(1+maxi(0,int(definition.depth)-int(m.depth)-1)*2))
		pool.append(candidate);total+=int(candidate.weight)
	floors[id]=floor
	if int(definition.depth)>1:
		for d in Kernel.DIRECTIONS:
			var p=position(vault_cell)+d
			if in_bounds(p) and tiles[index(p)]!="wall" and not floor.features.has(str(index(p))):
				spawn(pool[-1],id,index(p));candidates.erase(index(p));break
	var count=6+int(definition.depth)*2
	for n in range(count):
		var roll=local_rng.randi_range(1,total);var picked:Dictionary=pool[0]
		for m in pool:
			roll-=int(m.weight)
			if roll<=0:picked=m;break
		var cell=candidates.pop_back()
		while floor.features.has(str(cell)) or actor_at(id,cell)>=0:cell=candidates.pop_back()
		spawn(picked,id,cell)
		# Pack roles create local pairs, with actual cell collision checks.
		if picked.ai=="pack" and n%2==0:
			for d in Kernel.DIRECTIONS:
				var p=position(cell)+d;var occupied=false
				for a in actors:
					if a.floor==id and a.cell==index(p):occupied=true
				if in_bounds(p) and tiles[index(p)]!="wall" and not occupied:spawn(picked,id,index(p));break
	if definition.has("rune") or id=="Z":
		var boss:Dictionary=DATA.monsters[22 if definition.theme=="water" else 23]
		for d in Kernel.DIRECTIONS:
			var p=position(exit)+d
			if in_bounds(p) and tiles[index(p)]!="wall":
				for a in actors:
					if a.floor==id and a.cell==index(p):a.hp=0
				spawn(boss,id,index(p));break
	for n in range(10):
		var c=candidates.pop_back()
		if floor.features.has(str(c)):continue
		if n<5:floor.loot[str(c)]={"kind":"supply","id":["heal","blink","haste","fog","wand"][n]}
		elif n<8:
			var category=["weapon","armour","ring"][n-5]
			var table:Dictionary=DATA[{"weapon":"weapons","armour":"armours","ring":"rings"}[category]]
			var it=item(category,table.keys()[local_rng.randi_range(0,table.size()-1)],"",local_rng.randi_range(0,2))
			if category=="weapon":it.brand=["","fire","ice","venom","drain"][local_rng.randi_range(0,4)]
			floor.loot[str(c)]={"kind":"item","item":it}
		else:floor.loot[str(c)]={"kind":"book","id":DATA.spells.keys()[local_rng.randi_range(0,DATA.spells.size()-1)]}
	# Branch threats are legible hazards, never unavoidable damage on stairs.
	for n in range(4 if int(definition.depth)>1 else 0):
		var c=candidates.pop_back()
		if not floor.features.has(str(c)) and not floor.loot.has(str(c)):
			floor.hazards[str(c)]={"kind":"fire" if definition.theme=="fire" else "trap","until":-1,"source":-1}

func actor_at(where:String,cell:int)->int:
	for a in actors:
		if a.floor==where and a.hp>0 and a.cell==cell:return int(a.id)
	return -1

func spawn(definition:Dictionary,where:String,cell:int,team:String="enemy",duration:int=0)->Dictionary:
	var a=definition.duplicate(true)
	a.id=actors.size();a.species=definition.id;a.team=team;a.floor=where;a.cell=cell
	a.max_hp=int(a.hp);a.hp=int(a.hp);a.mp=20;a.max_mp=20;a.ready=time+100
	a.statuses={};a.last_seen=-1;a.expires=time+duration if duration>0 else 0;a.summoned=duration>0;a.gear={}
	actors.append(a)
	return a

func enter_floor(id:String,from:String)->void:
	if floors.has(floor_id):current().memory=Array(memory) if memory.size()>0 else current().memory
	if not floors.has(id):generate(id)
	floor_id=id;terrain=PackedStringArray(current().terrain);memory=PackedByteArray(current().memory)
	visible.resize(terrain.size());visible.fill(0)
	var entry=int(current().entry)
	for key in current().features:
		var feature:Dictionary=current().features[key]
		if feature.kind=="stairs" and feature.to==from:entry=int(key);break
	# Enemies cannot block arrival; displace any occupant before the party enters.
	for a in actors:
		if a.floor==id and a.id!=0 and a.hp>0 and a.cell==entry:
			for d in Kernel.DIRECTIONS:
				var p=position(entry)+d;var taken=false
				for other in actors:
					if other.floor==id and other.hp>0 and other.cell==index(p):taken=true
				if in_bounds(p) and not blocked(index(p)) and not taken:a.cell=index(p);break
	hero().cell=entry;hero().floor=id
	for a in actors:
		if a.id>0 and a.team!="enemy" and a.hp>0:
			a.floor=id;a.cell=entry;a.ready=time+100
		if a.floor==id:a.ready=maxi(time+100,int(a.ready))
	rebuild_occupancy();occupancy[entry]=0
	for a in actors:
		if a.id>0 and friendly(a) and a.hp>0:
			var c=free_near(entry)
			if c>=0:a.cell=c;occupancy[c]=int(a.id)
	if orb and id!="Z" and not current().get("return_spawned",false):
		current().return_spawned=true
		var count=0
		for c in range(terrain.size()):
			var distance=position(c).distance_squared_to(position(hero().cell))
			if not blocked(c) and occupancy[c]<0 and distance>49 and distance<100 and not current().features.has(str(c)):
				var pursuer=spawn(DATA.monsters[17 if count==0 else 4],id,c)
				pursuer.summoned=true;pursuer.last_seen=int(hero().cell);occupancy[c]=int(pursuer.id);count+=1
				if count==2:break
		message("오브를 감지한 추격자가 이 층에 진입했습니다.")
	stop_auto();navigation.fields.clear();discovery=false;update_sight();message(floor_name()+" 진입")
	emit("floor.entered",0)

func submit(kind:String,target:int=-1,value:String="")->bool:
	last_error="";effects.clear();discovery=false
	if terminal():return reject("이 탐험은 종료되었습니다.")
	var cost=100;var h=hero()
	match kind:
		"MOVE":
			if h.statuses.has("confuse") and rng.randi_range(0,2)==0:
				var confused=position(h.cell)+Kernel.DIRECTIONS[rng.randi_range(0,7)]
				if in_bounds(confused):target=index(confused)
			if not open_edge(h.cell,target):return reject("한 칸씩 이동하거나 알려진 경로를 선택하세요.")
			var occupant=occupancy[target]
			if occupant>0:
				if not friendly(actors[occupant]):cost=int(stats(h).delay);attack(h,actors[occupant])
				else:
					var old=int(h.cell);actors[occupant].cell=old;occupancy[old]=occupant;h.cell=target;occupancy[target]=0
			else:cost=movement_time(h,target);move_actor(h,target);pickup();trigger_trap(h)
		"ATTACK":
			if target<0 or target>=occupancy.size() or occupancy[target]<=0:return reject("적을 선택하세요.")
			var victim=actors[occupancy[target]];var s=stats(h)
			if friendly(victim) or not can_see(h,target,int(s.range)):return reject("무기 사거리 밖입니다.")
			cost=int(s.delay);attack(h,victim)
		"WAIT":pass
		"CAST":
			if not cast(value,target):return false
			cost=200 if value=="passwall" else 100
		"USE":
			if not use_supply(value,target):return false
		"INTERACT":
			var feature:Dictionary=current().features.get(str(h.cell),{})
			if feature.is_empty():return reject("계단·제단·보물 위에서 사용하세요.")
			match str(feature.kind):
				"stairs":
					if feature.to=="OUT":
						if not orb:return reject("두 룬과 오브를 가져와야 탈출합니다.")
						won=true;stop_auto();message("오브와 함께 탈출했습니다. 승리!");emit("run.won",0);return true
					if feature.to=="Z" and runes.size()<2:return reject("습지와 화로의 룬 2개가 필요합니다.")
					var from=floor_id;advance(100)
					if not terminal():enter_floor(feature.to,from)
					return true
				"rune":
					if feature.id not in runes:runes.append(feature.id);message("룬 획득: "+feature.id)
					current().features.erase(str(h.cell));emit("rune.acquired",0)
				"orb":
					orb=true;current().features.erase(str(h.cell));message("오브 획득! D1 출구로 귀환하세요. 적들이 위치를 감지합니다.");emit("orb.acquired",0)
				"cache":
					var it=item("weapon",DATA.weapons.keys()[rng.randi_range(0,DATA.weapons.size()-1)],["fire","ice","venom","drain"][rng.randi_range(0,3)],2);it.artefact=true;inventory.append(it)
					current().features.erase(str(h.cell));message(item_name(it)+" 획득")
				"altar":return reject("신앙 창에서 이 제단의 계약을 선택하세요.")
		"WORSHIP":
			var feature:Dictionary=current().features.get(str(h.cell),{})
			if feature.get("kind")!="altar" or feature.get("god")!=value or not DATA.gods.has(value):return reject("해당 신의 제단 위에서 계약하세요.")
			if god==value:return reject("이미 이 계약을 따르고 있습니다.")
			if not god.is_empty():leave_god()
			god=value;piety=15
			if god=="bind":bound_weapon=int(h.gear.weapon)
			if god=="kin":
				var lost=maxi(1,int(h.max_hp)/5);kin_sacrifice=lost;h.max_hp-=lost;h.hp=mini(h.hp,h.max_hp);summon_guardian()
			message(DATA.gods[god].name+" 계약");emit("god.joined",0)
		"ABANDON":
			if god.is_empty():return reject("계약이 없습니다.")
			leave_god()
		"GOD":
			if god.is_empty():return reject("먼저 제단에서 계약하세요.")
			var price=10 if god=="war" else 8 if god=="bind" else 12
			if piety<price:return reject("신앙이 부족합니다.")
			if god=="war":h.statuses.rage=time+400
			elif god=="bind":
				for c in range(terrain.size()):
					if position(c).distance_squared_to(position(h.cell))<=100:memory[c]=1
			elif not summon_guardian():return reject("수호령이 이미 있거나 공간이 없습니다.")
			piety-=price
		"EQUIP":
			if target<0 or target>=inventory.size() or inventory[target].destroyed:return reject("장비가 없습니다.")
			var it=inventory[target];var slot=it.category
			if h.gear[slot]==target:return reject("이미 장착 중입니다.")
			if slot=="weapon" and bound_weapon>=0:return reject("결속 무기를 교체하려면 먼저 파괴해야 합니다.")
			if it.type=="plate" and h.species=="elf":return reject("엘프는 판금을 장착할 수 없습니다.")
			h.gear[slot]=target
			if slot=="weapon" and god=="bind":bound_weapon=target
			cost=200 if slot=="armour" else 100;message(item_name(it)+" 장착")
		"BREAK_BIND":
			if bound_weapon<0:return reject("결속 장비가 없습니다.")
			inventory[bound_weapon].destroyed=true;h.gear.weapon=-1;bound_weapon=-1;message("결속 무기를 파괴했습니다.")
		"FOCUS":
			if not DATA.skills.has(value):return false
			if not safe():return reject("안전한 곳에서 훈련 목표를 바꾸세요.")
			if value in focus:
				if focus.size()==1:return reject("한 가지 목표는 남겨야 합니다.")
				focus.erase(value)
			else:
				if focus.size()>=2:focus.pop_front()
				focus.append(value)
			message("훈련 목표 변경 · 경험치를 자동 배분합니다.");return true
		"PREPARE":
			if value not in spells or not safe():return reject("안전한 곳에서 배운 주문을 준비하세요.")
			if value in prepared:prepared.erase(value)
			elif prepared.size()<6:prepared.append(value)
			else:return reject("준비 주문은 최대 6개입니다.")
			return true
		_:return false
	if kind!="MOVE":
		if h.statuses.has("slow"):cost=cost*3/2
		if h.statuses.has("haste"):cost=cost*2/3
	advance(cost);return true

func advance(cost:int)->void:
	var end=time+cost
	hero().ready=end
	# Environment wins ties; hero wins actor ties at the end of its own action.
	Kernel.advance(end,func(limit:int)->Dictionary:
		var best:Dictionary={}
		if terminal():return best
		if boundary<=limit:best={"at":boundary,"id":-1}
		for a in actors:
			if a.id==0 or a.floor!=floor_id or a.hp<=0 or int(a.ready)>=limit:continue
			best=Kernel.earlier(best,maxi(time,int(a.ready)),int(a.id),limit)
		return best,
		func(event:Dictionary)->bool:
			time=int(event.at)
			if int(event.id)==-1:environment_tick();boundary+=100
			elif not terminal():actor_turn(actors[int(event.id)])
			return true)
	time=end
	if boundary<=time:boundary=(time/100+1)*100
	update_sight()
	if terminal():stop_auto();message("탐험 종료 · 죽음은 되돌릴 수 없습니다." if not won else "승리")
	if discovery or not visible_enemies().is_empty():stop_auto()
	emit("turn.completed",0,-1,cost)

func can_see(a:Dictionary,cell:int,radius:int=6)->bool:
	if blocked(cell):return false
	if int(a.id)==0 and visible[cell]==0:return false
	return sight_clear(a,cell,radius)
func sight_clear(a:Dictionary,cell:int,radius:int=6)->bool:
	if not Kernel.sees(position(a.cell),position(cell),solid,radius):return false
	var p=position(a.cell);var target=position(cell);var dist=maxi(absi(target.x-p.x),absi(target.y-p.y))
	for step in range(1,dist):
		var mid=Vector2i(Vector2(p).lerp(Vector2(target),float(step)/dist).round())
		if current().hazards.get(str(index(mid)),{}).get("kind","")=="fog":return false
	return true
func damage(source:Dictionary,target:Dictionary,raw:int,element:String="physical")->void:
	if target.hp<=0 or raw<=0:return
	var s=stats(target);var amount=raw
	if element!="physical":amount=maxi(0,raw*(100-int(s.res.get(element,0)))/100)
	target.hp=maxi(0,int(target.hp)-amount)
	if element=="fire":target.statuses.erase("ward")
	emit("combat.damage",int(source.get("id",-1)),int(target.id),amount)
	if target.id==0 or visible[int(target.cell)]==1:
		message("%s → %s %d (%s)"%[source.get("name","환경"),target.name,amount,element])
	if target.id==0:stop_auto()
	if target.hp==0:
		occupancy[int(target.cell)]=-1;emit("actor.died",int(source.get("id",-1)),int(target.id))
		if target.team=="enemy" and not target.summoned and friendly(source):
			gain_xp(18+depth()*8)
			if not god.is_empty():piety=mini(100,piety+2)
			if rng.randi_range(0,4)==0 and not current().loot.has(str(target.cell)):current().loot[str(target.cell)]={"kind":"supply","id":"heal"}
func attack(source:Dictionary,target:Dictionary)->void:
	if target.hp<=0:return
	var offense=stats(source);var defense=stats(target)
	if rng.randi_range(0,99)<clampi(int(defense.ev)*2,5,45):message(target.name+" 회피");return
	if rng.randi_range(0,99)<int(defense.sh):message(target.name+" 방패 방어");return
	var raw=int(offense.damage)
	if offense.trait=="stab" and (target.statuses.has("confuse") or target.last_seen<0):raw*=2
	var ac=int(defense.ac)/2 if offense.trait=="pierce" else int(defense.ac)
	var physical=Turns.physical(raw,950,0,rng.randi_range(0,ac))
	damage(source,target,int(physical.damage))
	if source.hp<=0 or target.hp<=0:return
	match str(offense.brand):
		"fire","ice":damage(source,target,4,str(offense.brand))
		"venom":
			if int(defense.res.get("poison",0))<100:target.statuses.poison=time+300
		"drain":source.hp=mini(int(source.max_hp),int(source.hp)+3)
	if offense.trait=="cleave":
		for a in actors:
			if a.id!=target.id and a.floor==floor_id and a.hp>0 and friendly(source)!=friendly(a) and open_edge(source.cell,a.cell):damage(source,a,maxi(1,raw/2-int(stats(a).ac)))
	match str(source.ai):
		"poison":
			if int(defense.res.get("poison",0))<100:target.statuses.poison=time+300
		"acid":target.statuses.corrode=time+500
		"drain":source.hp=mini(source.max_hp,source.hp+4)

func gain_xp(amount:int)->void:
	xp+=amount
	for axis in focus:
		var aptitude=int(DATA.species[hero().species].apt.get(axis,100))
		var trained=amount*aptitude/focus.size()/100
		if god=="bind" and bound_weapon>=0:trained=trained*13/10
		skills[axis]+=trained
	while level<12 and xp>=level*level*65:
		level+=1;hero().max_hp+=4;hero().hp+=4;hero().max_mp+=1;hero().mp+=1
		message("레벨 %d · 자동 훈련: %s"%[level,", ".join(focus)])
	emit("growth.xp",0,-1,amount)

func leave_god()->void:
	if god=="kin":
		hero().max_hp+=kin_sacrifice;kin_sacrifice=0
		for a in actors:
			if a.ai=="guardian":a.hp=0
	if god=="bind":bound_weapon=-1
	god="";piety=0;penance=12;rebuild_occupancy();message("계약 파기 · 다음 12턴 동안 징벌")
func summon_guardian()->bool:
	for a in actors:
		if a.ai=="guardian" and a.hp>0:return false
	var c=free_near(hero().cell)
	if c<0:return false
	var a=spawn({"id":"guardian","name":"수호령","sprite":"human","hp":32+level*2,"power":8+level,"speed":100,"ac":3,"ev":5,"will":80,"ai":"guardian","res":{"poison":100}},floor_id,c,"ally")
	occupancy[c]=int(a.id);return true

func actor_turn(a:Dictionary)->void:
	a.ready=time+movement_time(a,a.cell)
	if a.expires>0 and time>=a.expires:a.hp=0;occupancy[int(a.cell)]=-1;return
	if a.statuses.has("confuse"):
		var p=position(a.cell)+Kernel.DIRECTIONS[rng.randi_range(0,7)]
		if in_bounds(p) and open_edge(a.cell,index(p)) and occupancy[index(p)]<0:move_actor(a,index(p))
		return
	var target:Dictionary={};var distance=99999
	for other in actors:
		if other.floor!=floor_id or other.hp<=0 or friendly(other)==friendly(a):continue
		var d=position(a.cell).distance_squared_to(position(other.cell))
		if d<distance and can_see(a,other.cell):target=other;distance=d
	if target.is_empty():
		if friendly(a) and a.ai!="turret":
			var step=navigation.next_step(self,a.cell,hero().cell)
			if step>=0 and position(a.cell).distance_squared_to(position(hero().cell))>2:move_actor(a,step)
		elif orb or a.last_seen>=0:
			var goal=int(hero().cell) if orb else int(a.last_seen)
			var step=navigation.next_step(self,a.cell,goal)
			if step>=0:move_actor(a,step)
			else:a.last_seen=-1
		return
	a.last_seen=target.cell
	# A seen pack member alerts nearby packmates, without wall omniscience.
	if a.ai=="pack":
		for other in actors:
			if other.floor==floor_id and other.ai=="pack" and position(a.cell).distance_squared_to(position(other.cell))<=16:other.last_seen=target.cell
	if a.ai=="support":
		for other in actors:
			if other.floor==floor_id and other.team==a.team and other.hp>0 and other.hp<other.max_hp/2 and can_see(a,other.cell,4):other.hp=mini(other.max_hp,other.hp+8);a.ready=time+150;return
	if a.ai=="summoner" and int(a.mp)>=4:
		var c=free_near(a.cell)
		if c>=0:
			var summoned=spawn(DATA.monsters[0],floor_id,c,a.team,500);occupancy[c]=int(summoned.id);a.mp-=4;a.ready=time+150;return
	if a.ai in ["ranged","caster","electric","slow","water","hex","turret"] and distance<=25:
		if a.ai=="hex":target.statuses.confuse=time+200
		elif a.ai=="slow":target.statuses.slow=time+300;damage(a,target,int(a.power),"ice")
		elif a.ai=="water":terrain[int(target.cell)]="shallow_water";current().terrain=Array(terrain);damage(a,target,int(a.power))
		else:
			var element="fire" if a.ai=="caster" else "air" if a.ai=="electric" else "physical"
			var raw=int(a.power)+(5 if element=="air" and terrain[int(target.cell)]=="shallow_water" else 0)
			damage(a,target,raw,element)
			a.ready=time+130
		return
	if open_edge(a.cell,target.cell) or a.ai=="reach" and distance<=4:
		attack(a,target);a.ready=time+maxi(70,int(a.speed));return
	if a.ai=="turret":return
	if a.ai=="blink" and distance>8 and rng.randi_range(0,2)==0:
		var c=free_near(target.cell)
		if c>=0:move_actor(a,c);return
	var step=navigation.next_step(self,a.cell,target.cell)
	if step>=0:
		move_actor(a,step);trigger_trap(a)
		if a.ai=="charge":a.statuses.rage=time+110

func add_hazard(cell:int,kind:String,duration:int,source:int=0)->void:
	if blocked(cell):return
	current().hazards[str(cell)]={"kind":kind,"until":time+duration,"source":source}
func environment_tick()->void:
	for a in actors:
		if a.floor!=floor_id or a.hp<=0:continue
		for key in a.statuses.keys():
			if int(a.statuses[key])<=time:a.statuses.erase(key)
		if a.statuses.has("poison"):damage({"id":-1,"name":"독","team":"enemy"},a,2,"poison")
		var hazard:Dictionary=current().hazards.get(str(a.cell),{})
		if not hazard.is_empty():
			var source:Dictionary=actors[int(hazard.source)] if int(hazard.source)>=0 else {"id":-1,"name":"환경","team":"enemy"}
			if hazard.kind=="fire":damage(source,a,5,"fire")
			elif hazard.kind=="poison" and int(stats(a).res.get("poison",0))<100:a.statuses.poison=time+300
			elif hazard.kind=="ice":a.statuses.slow=time+150
		if a.ai=="regen":a.hp=mini(a.max_hp,a.hp+2)
		if a.expires>0 and time>=a.expires:a.hp=0;occupancy[int(a.cell)]=-1
	for key in current().hazards.keys():
		var hz:Dictionary=current().hazards[key]
		if int(hz.until)>0 and int(hz.until)<=time:current().hazards.erase(key)
	if penance>0:
		penance-=1
		if penance%3==0:damage({"id":-1,"name":"징벌","team":"enemy"},hero(),3,"air")
	if safe():
		hero().hp=mini(hero().max_hp,hero().hp+1+skill_rank("survival")/4)
		hero().mp=mini(hero().max_mp,hero().mp+1)
func trigger_trap(a:Dictionary)->void:
	var key=str(a.cell)
	if current().hazards.get(key,{}).get("kind")=="trap":
		current().hazards.erase(key);damage({"name":"가시 함정","team":"enemy","id":-1},a,7);a.statuses.slow=time+200;stop_auto()

func spell_cells(id:String,target:int)->Array[int]:
	var result:Array[int]=[]
	var effect:String=DATA.spells[id].effect
	if effect in ["blast","cloud"]:
		for c in range(terrain.size()):
			if not blocked(c) and position(c).distance_squared_to(position(target))<=2 and Kernel.sees(position(target),position(c),solid,2):result.append(c)
	elif effect=="cone":
		var direction=Vector2(position(target)-position(hero().cell)).normalized()
		for c in visible_cells:
			var delta=Vector2(position(c)-position(hero().cell))
			if delta.length()>0 and delta.length()<=4 and delta.normalized().dot(direction)>=0.7:result.append(c)
	elif effect=="ignite":
		for c in visible_cells:
			if current().hazards.get(str(c),{}).get("kind")=="poison" or occupancy[c]>=0 and actors[occupancy[c]].statuses.has("poison"):result.append(c)
	else:result.append(target)
	return result
func cast(id:String,target:int)->bool:
	if id not in prepared:return reject("준비하지 않은 주문입니다.")
	if god=="war":return reject("전투의 맹세는 주문을 금지합니다.")
	var sp:Dictionary=DATA.spells[id];var effect:String=sp.effect
	if int(hero().mp)<int(sp.mp):return reject("MP가 부족합니다.")
	if effect in ["ward","mend","blink","ignite"]:target=int(hero().cell)
	elif effect=="passwall":
		if target<0 or target>=terrain.size() or blocked(target) or occupancy[target]>=0 or memory[target]==0:return reject("알려진 빈칸을 선택하세요.")
		var delta=position(target)-position(hero().cell)
		if delta.length_squared()>9 or delta==Vector2i.ZERO:return reject("벽 너머 3칸 이내를 선택하세요.")
		var mid=position(hero().cell)+Vector2i(signi(delta.x),signi(delta.y))
		if not solid(mid):return reject("인접한 벽을 관통해야 합니다.")
	elif not can_see(hero(),target,int(sp.range)):return reject("시야·사거리 밖입니다.")
	if effect in ["bolt","confuse"] and (occupancy[target]<0 or friendly(actors[occupancy[target]])):return reject("적을 선택하세요.")
	if effect in ["hound","turret"] and occupancy[target]>=0:return reject("빈칸에 소환하세요.")
	if effect=="mend" and hero().hp>=hero().max_hp:return reject("HP가 이미 가득 찼습니다.")
	hero().mp-=int(sp.mp)
	if rng.randi_range(0,99)<failure(id):message(sp.name+" 실패 · MP와 행동 소모");return true
	var power=int(sp.power)+skill_rank(sp.school)*2+int(stats(hero()).power)
	match effect:
		"blink":blink(hero())
		"passwall":move_actor(hero(),target);pickup()
		"ward":hero().statuses.ward=time+400
		"mend":hero().hp=mini(hero().max_hp,hero().hp+power);hero().statuses.slow=time+300
		"hound","turret":
			var a=spawn({"id":effect,"name":"추적령" if effect=="hound" else "포탑","sprite":"wolf" if effect=="hound" else "beetle","hp":18+power,"power":power,"speed":100,"ac":2,"ev":3,"will":100,"ai":effect,"res":{"poison":100}},floor_id,target,"ally",600)
			occupancy[target]=int(a.id)
		"confuse":
			var victim=actors[occupancy[target]]
			if rng.randi_range(0,99)+power>=int(victim.will):victim.statuses.confuse=time+300
			else:message(victim.name+" 혼란 저항")
		_:
			for c in spell_cells(id,target):
				if effect=="cloud":add_hazard(c,"poison",400);continue
				if effect in ["blast","ignite"]:add_hazard(c,"fire",300)
				if effect=="cone" and terrain[c]=="shallow_water":terrain[c]="ice";current().terrain=Array(terrain);add_hazard(c,"ice",400)
				var occupant=occupancy[c]
				if occupant>=0:
					if effect=="ignite":actors[occupant].statuses.erase("poison")
					if effect=="cone":actors[occupant].statuses.slow=time+200
					damage(hero(),actors[occupant],power,"ice" if effect=="cone" else "fire")
	emit("spell.cast",0,-1,int(sp.mp));return true
func blink(a:Dictionary)->bool:
	var cells:Array[int]=[]
	for c in visible_cells:
		if not blocked(c) and occupancy[c]<0 and position(c).distance_squared_to(position(a.cell))<=16 and not current().hazards.has(str(c)):cells.append(c)
	if cells.is_empty():message("순간이동할 공간이 없습니다.");return false
	move_actor(a,cells[rng.randi_range(0,cells.size()-1)]);return true
func use_supply(id:String,target:int)->bool:
	if not supplies.has(id) or int(supplies[id])<=0:return reject("남은 소모품이 없습니다.")
	match id:
		"heal":
			if hero().hp>=hero().max_hp and not hero().statuses.has("poison"):return reject("회복할 필요가 없습니다.")
			hero().hp=mini(hero().max_hp,hero().hp+30);hero().statuses.erase("poison")
		"blink":
			if not blink(hero()):return false
		"haste":hero().statuses.haste=time+500
		"fog":
			for d in Kernel.DIRECTIONS:add_hazard(index(position(hero().cell)+d),"fog",400)
		"wand":
			if not can_see(hero(),target,6) or occupancy[target]<=0 or friendly(actors[occupancy[target]]):return reject("시야 내 적을 선택하세요.")
			damage(hero(),actors[occupancy[target]],18+skill_rank("tools")*2,"air")
		_:return false
	supplies[id]-=1;emit("item.used",0);return true
func pickup()->void:
	var key=str(hero().cell)
	if not current().loot.has(key):return
	var entry:Dictionary=current().loot[key]
	if entry.kind=="supply":supplies[entry.id]+=2 if entry.id=="wand" else 1;message("소모품 획득: "+entry.id)
	elif entry.kind=="book":
		if entry.id not in spells:spells.append(entry.id);message("주문 발견: "+DATA.spells[entry.id].name)
		else:supplies.wand+=1;message("중복 주문서 → 마도구 충전")
	else:inventory.append(entry.item);message(item_name(entry.item)+" 획득")
	current().loot.erase(key);discovery=true;emit("item.acquired",0)

func safe()->bool:
	if terminal() or penance>0 or not hero().statuses.is_empty() or current().hazards.has(str(hero().cell)):return false
	for a in actors:
		if a.floor==floor_id and a.team=="enemy" and a.hp>0 and sight_clear(a,int(hero().cell),8):return false
	return true
func stop_auto()->void:auto_explore=false;resting=false;route_steps.clear()
func plan_route(goal:int)->bool:
	if not visible_enemies().is_empty():return reject("적이 보일 때는 한 칸씩 이동하세요.")
	route_steps=navigation.route(self,int(hero().cell),goal)
	for c in route_steps:
		if current().hazards.has(str(c)):route_steps.clear();return reject("위험 타일이 있는 경로입니다.")
	return not route_steps.is_empty()
func start_rest()->bool:
	stop_auto()
	if not safe():return reject("적·상태 이상·위험이 있을 때 자동 휴식하지 않습니다.")
	resting=true;return true
func auto_step()->bool:
	if terminal() or not visible_enemies().is_empty():stop_auto();return false
	if resting:
		if not safe() or hero().hp>=hero().max_hp and hero().mp>=hero().max_mp:stop_auto();return false
		return submit("WAIT")
	if route_steps.is_empty() and auto_explore:
		var queue=PackedInt32Array([int(hero().cell)]);var parents={int(hero().cell):-1};var head=0;var goal=-1
		while head<queue.size():
			var c=queue[head];head+=1
			for d in Kernel.DIRECTIONS:
				var p=position(c)+d
				if not in_bounds(p):continue
				var next=index(p)
				if memory[next]==0 and Kernel.open_edge(position(c),p,solid):goal=c;break
				if parents.has(next) or memory[next]==0 or not open_edge(c,next) or occupancy[next]>=0 or current().hazards.has(str(next)):continue
				parents[next]=c;queue.append(next)
			if goal>=0:break
		while goal>=0 and int(parents[goal])>=0:route_steps.append(goal);goal=int(parents[goal])
		route_steps.reverse()
	if route_steps.is_empty():stop_auto();return false
	var next=route_steps[0];route_steps.remove_at(0)
	if occupancy[next]>=0 or current().hazards.has(str(next)):stop_auto();return false
	return submit("MOVE",next)

func save_data()->Dictionary:
	current().terrain=Array(terrain);current().memory=Array(memory)
	return {"schema":SCHEMA,"kin_sacrifice":kin_sacrifice,"seed":str(seed),"rng":str(rng.state),"time":time,"boundary":boundary,"serial":serial,"floor":floor_id,"floors":floors.duplicate(true),"actors":actors.duplicate(true),"inventory":inventory.duplicate(true),"supplies":supplies.duplicate(),"spells":spells.duplicate(),"prepared":prepared.duplicate(),"skills":skills.duplicate(),"focus":focus.duplicate(),"xp":xp,"level":level,"god":god,"piety":piety,"penance":penance,"bound_weapon":bound_weapon,"runes":runes.duplicate(),"orb":orb,"won":won,"log":log.duplicate()}
static func integer(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value))
static func in_range(value:Variant,lo:int,hi:int)->bool:return integer(value) and value>=lo and value<=hi
static func valid_item(it:Variant)->bool:
	if not it is Dictionary:return false
	for k in ["category","type","brand","enchant","artefact","destroyed"]:
		if not it.has(k):return false
	if not it.artefact is bool or not it.destroyed is bool or not in_range(it.enchant,0,9):return false
	if it.brand not in ["","fire","ice","venom","drain"]:return false
	if it.category=="shield":return it.type=="buckler"
	var table:Dictionary=DATA.get({"weapon":"weapons","armour":"armours","ring":"rings"}.get(it.category,""),{})
	return it.type is String and table.has(it.type)
static func validation_error(data:Dictionary)->String:
	for k in ["schema","kin_sacrifice","seed","rng","time","boundary","serial","floor","floors","actors","inventory","supplies","spells","prepared","skills","focus","xp","level","god","piety","penance","bound_weapon","runes","orb","won","log"]:
		if not data.has(k):return "missing "+k
	if not in_range(data.kin_sacrifice,0,1000):return "sacrifice"
	if data.schema!=SCHEMA or not data.seed is String or not data.seed.is_valid_int() or not data.rng is String or not data.rng.is_valid_int():return "version/random"
	if not in_range(data.time,0,100000000) or not in_range(data.boundary,int(data.time)+1,int(data.time)+100) or not in_range(data.serial,0,100000000):return "clock"
	if not DATA.floors.has(data.floor) or not data.floors is Dictionary or not data.floors.has(data.floor) or data.floors.size()>8:return "floor"
	if not data.actors is Array or data.actors.is_empty() or data.actors.size()>4096:return "actors"
	if not data.inventory is Array or data.inventory.size()>512:return "inventory"
	for it in data.inventory:
		if not valid_item(it):return "item"
	for id in data.floors:
		if not DATA.floors.has(id):return "floor id"
		var f=data.floors[id]
		if not f is Dictionary:return "floor record"
		for k in ["terrain","memory","features","loot","hazards","entry"]:
			if not f.has(k):return "floor missing "+k
		if not f.terrain is Array or f.terrain.size()!=WIDTH*HEIGHT or not f.memory is Array or f.memory.size()!=WIDTH*HEIGHT:return "grid"
		for i in range(WIDTH*HEIGHT):
			if not f.terrain[i] is String or f.terrain[i] not in ["wall","floor","shallow_water","rubble","ice","door","open_door","closed_door","stone_floor"] or not in_range(f.memory[i],0,1):return "tile"
		if not in_range(f.entry,0,WIDTH*HEIGHT-1) or f.terrain[int(f.entry)]=="wall":return "entry"
		for group in ["features","loot","hazards"]:
			if not f[group] is Dictionary:return "cell data"
			for key in f[group]:
				if not key is String or not key.is_valid_int() or int(key)<0 or int(key)>=WIDTH*HEIGHT or not f[group][key] is Dictionary:return "cell key"
				var row:Dictionary=f[group][key]
				if not row.get("kind") is String:return "cell kind"
				if group=="features":
					if row.kind not in ["stairs","altar","rune","orb","cache"]:return "feature"
					if row.kind=="stairs" and row.get("to") not in DATA.floors.keys()+["OUT"]:return "stairs"
					if row.kind=="altar" and not DATA.gods.has(row.get("god")):return "altar"
					if row.kind=="rune" and row.get("id") not in ["marsh","forge"]:return "rune"
				elif group=="hazards":
					if row.kind not in ["fire","poison","ice","fog","trap"] or not in_range(row.get("until"),-1,100001000) or not in_range(row.get("source"),-1,data.actors.size()-1):return "hazard"
				else:
					if row.kind=="item":
						if not valid_item(row.get("item")):return "loot item"
					elif row.kind=="book":
						if not DATA.spells.has(row.get("id")):return "book"
					elif row.kind=="supply":
						if row.get("id") not in ["heal","blink","haste","fog","wand"]:return "supply"
					else:return "loot kind"
	var occupied={}
	for i in range(data.actors.size()):
		var a=data.actors[i]
		if not a is Dictionary:return "actor type"
		for key in ["id","name","species","sprite","team","floor","cell","hp","max_hp","mp","max_mp","ready","power","speed","ac","ev","will","ai","res","statuses","last_seen","expires","summoned","gear"]:
			if not a.has(key):return "actor missing "+key
		if a.id!=i or not data.floors.has(a.floor) or not in_range(a.cell,0,WIDTH*HEIGHT-1) or not in_range(a.max_hp,1,10000) or not in_range(a.hp,0,int(a.max_hp)):return "actor identity"
		if a.team not in ["hero","enemy","ally"] or (i==0)!=(a.team=="hero"):return "team"
		for key in ["name","species","sprite","ai"]:
			if not a[key] is String:return "actor string"
		for key in ["ready","power","ac","ev","will","mp","max_mp","expires"]:
			if not in_range(a[key],0,100001000):return "actor number"
		if not in_range(a.speed,30,1000) or not in_range(a.last_seen,-1,WIDTH*HEIGHT-1):return "actor movement"
		if not a.res is Dictionary or not a.statuses is Dictionary or not a.gear is Dictionary or not a.summoned is bool:return "actor state"
		for key in a.statuses:
			if key not in ["poison","ward","rage","corrode","confuse","haste","slow"] or not in_range(a.statuses[key],0,100001000):return "status"
		for key in a.res:
			if key not in ["fire","ice","air","poison"] or not in_range(a.res[key],0,100):return "resistance"
		if a.hp>0:
			var cell_key=str(a.floor)+":"+str(int(a.cell))
			if occupied.has(cell_key) or data.floors[a.floor].terrain[int(a.cell)]=="wall":return "occupancy"
			occupied[cell_key]=true
	var h=data.actors[0]
	if not DATA.species.has(h.species) or h.floor!=data.floor or h.mp>h.max_mp:return "hero"
	for slot in ["weapon","armour","ring","shield"]:
		if not in_range(h.gear.get(slot),-1,data.inventory.size()-1):return "gear index"
		var idx=int(h.gear[slot])
		if idx>=0 and (data.inventory[idx].category!=slot or data.inventory[idx].destroyed):return "gear slot"
	if not data.supplies is Dictionary or not data.skills is Dictionary:return "progress"
	for id in ["heal","blink","haste","fog","wand"]:
		if not in_range(data.supplies.get(id),0,10000):return "supplies"
	for id in DATA.skills:
		if not in_range(data.skills.get(id),0,10000000):return "skills"
	for key in ["spells","prepared","focus","runes","log"]:
		if not data[key] is Array:return "lists"
		for value in data[key]:
			if not value is String:return "string list"
	if data.prepared.size()>6 or data.focus.is_empty() or data.focus.size()>2 or data.runes.size()>2 or data.log.size()>60:return "list size"
	for id in data.spells:
		if not DATA.spells.has(id):return "spell"
	for id in data.prepared:
		if id not in data.spells:return "prepared"
	for id in data.focus:
		if not DATA.skills.has(id):return "focus"
	for id in data.runes:
		if id not in ["marsh","forge"]:return "rune id"
	if not in_range(data.level,1,12) or not in_range(data.xp,0,10000000) or not in_range(data.piety,0,100) or not in_range(data.penance,0,12):return "growth"
	if data.god not in DATA.gods.keys()+[""] or not in_range(data.bound_weapon,-1,data.inventory.size()-1):return "god"
	if int(data.bound_weapon)>=0 and (data.god!="bind" or data.bound_weapon!=h.gear.weapon):return "binding"
	if not data.orb is bool or not data.won is bool or data.won and (not data.orb or h.hp<=0):return "end state"
	return ""
func restore(data:Dictionary)->bool:
	data=preload("res://sim/json_content_loader.gd")._normalize_json_numbers(data)
	last_error=validation_error(data)
	if not last_error.is_empty():return false
	kin_sacrifice=int(data.kin_sacrifice);seed=int(data.seed);rng.seed=seed;rng.state=int(data.rng)
	time=int(data.time);boundary=int(data.boundary);serial=int(data.serial);floor_id=data.floor
	floors=data.floors.duplicate(true);actors.assign(data.actors.duplicate(true));inventory.assign(data.inventory.duplicate(true))
	supplies=data.supplies.duplicate();spells=data.spells.duplicate();prepared=data.prepared.duplicate();skills=data.skills.duplicate();focus=data.focus.duplicate()
	xp=int(data.xp);level=int(data.level);god=data.god;piety=int(data.piety);penance=int(data.penance);bound_weapon=int(data.bound_weapon)
	runes=data.runes.duplicate();orb=data.orb;won=data.won;log.assign(data.log)
	terrain=PackedStringArray(current().terrain);memory=PackedByteArray(current().memory);visible.resize(terrain.size())
	rebuild_occupancy();stop_auto();navigation.fields.clear();effects.clear();update_sight();return true
