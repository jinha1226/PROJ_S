extends RefCounted

const Map=preload("res://playtest/deterministic_dungeon_map.gd")
const Kernel=preload("res://sim/combat_kernel.gd")
const Heap=preload("res://game/rebuilt/min_heap.gd")
const Navigation=preload("res://game/rebuilt/navigation.gd")
const Personality=preload("res://sim/dungeon_population/hexaco_profile.gd")
const SCHEMA:=1
const WIDTH:=64
const HEIGHT:=64
var seed:int=44
var floor_number:int=1
var time:int=0
var terrain:=PackedStringArray()
var occupancy:=PackedInt32Array()
var memory:=PackedByteArray()
var visible:=PackedByteArray()
var visible_cells:=PackedInt32Array()
var actors:Array[Dictionary]=[]
var lights:=PackedInt32Array()
var light_strength:=PackedFloat32Array()
var loot:Dictionary={}
var exit_cell:int=-1
var gold:int=0
var potions:int=3
var torch_fuel:int=20000
var torch_lit:bool=true
var weapon:String="검"
var armor:int=2
var log:Array[String]=[]
var effects:Array[Dictionary]=[]
var scheduler=Heap.new()
var navigation=Navigation.new()
var sight_origin:int=-1
var fov_builds:int=0
var last_action_usec:int=0
var last_path_usec:int=0
var route_steps:=PackedInt32Array()
var auto_explore:bool=false

func _init(p_seed:int=44)->void:
	seed=p_seed;generate_floor()

func index(p:Vector2i)->int:return p.y*WIDTH+p.x
func position(cell:int)->Vector2i:return Vector2i(cell%WIDTH,cell/WIDTH)
func in_bounds(p:Vector2i)->bool:return p.x>=0 and p.y>=0 and p.x<WIDTH and p.y<HEIGHT
func blocked(cell:int)->bool:return cell<0 or cell>=terrain.size() or terrain[cell]=="wall"
func solid(p:Vector2i)->bool:return not in_bounds(p) or blocked(index(p))
func open_edge(a:int,b:int)->bool:return Kernel.open_edge(position(a),position(b),solid)
func move_cost(cell:int)->int:return 130 if terrain[cell]=="shallow_water" else 140 if terrain[cell]=="rubble" else 100
func hero()->Dictionary:return actors[0]
func terminal()->bool:return int(hero().hp)<=0

func make_actor(id:int,cell:int,team:String)->Dictionary:
	var profile=Personality.generated(seed+floor_number,id+1)
	return {"id":id,"cell":cell,"team":team,"hp":80 if team=="hero" else 18+floor_number*3,
		"max_hp":80 if team=="hero" else 18+floor_number*3,"ready":time,
		"power":10 if team=="hero" else 3+floor_number,"move_time":100 if team=="hero" else 120,
		"attack_time":110 if team=="hero" else 140,"stress":0,"skin":2,"bone":100,
		"blood":100,"profile":profile.to_dict(),"personality":profile.style_summary().label,
		"last_seen":-1,"facing":[0,1]}

func generate_floor()->void:
	var previous:Dictionary=actors[0].duplicate(true) if not actors.is_empty() else {}
	var layout:Dictionary=Map.generate(WIDTH,HEIGHT,seed+floor_number*7919)
	terrain=PackedStringArray(layout.terrain)
	occupancy.resize(terrain.size());occupancy.fill(-1)
	memory.resize(terrain.size());memory.fill(0)
	visible.resize(terrain.size());visible.fill(0);visible_cells.clear()
	actors.clear();scheduler.clear();loot.clear();lights.clear()
	navigation.fields.clear()
	var entry:int=index(layout.hero_position)
	exit_cell=index(layout.exit_position)
	var player:=make_actor(0,entry,"hero")
	if not previous.is_empty():
		player=previous;player.cell=entry;player.ready=time
	actors.append(player);occupancy[entry]=0
	for point in layout.enemy_positions:
		var cell:=index(point)
		if occupancy[cell]>=0 or blocked(cell):continue
		var actor:=make_actor(actors.size(),cell,"enemy")
		actors.append(actor);occupancy[cell]=actor.id
		# Never act before the first player input; same-time hero wins ties.
		scheduler.push([time,actor.id,actor.id])
	for cell in range(terrain.size()):
		if blocked(cell) or cell==entry or cell==exit_cell:continue
		if cell%97==0:lights.append(cell)
		if cell%173==0:loot[str(cell)]="potion"
		elif cell%127==0:loot[str(cell)]="gold"
	rebuild_lights()
	sight_origin=-1;route_steps.clear();auto_explore=false;update_sight()
	message("%d층에 도착했습니다."%floor_number)

func rebuild_lights()->void:
	light_strength.resize(terrain.size());light_strength.fill(0.0)
	for source in lights:
		var p:=position(source)
		for y in range(maxi(0,p.y-4),mini(HEIGHT,p.y+5)):
			for x in range(maxi(0,p.x-4),mini(WIDTH,p.x+5)):
				var target:=Vector2i(x,y)
				if Kernel.sees(p,target,solid,4):
					var cell:=index(target)
					light_strength[cell]=maxf(light_strength[cell],1.0-Vector2(p-target).length()*0.05)

func message(text:String)->void:
	log.append(text)
	if log.size()>40:log.pop_front()

func update_sight()->void:
	var origin:int=hero().cell
	if sight_origin==origin:return
	for cell in visible_cells:visible[cell]=0
	visible_cells.clear()
	var p:=position(origin)
	for y in range(maxi(0,p.y-6),mini(HEIGHT,p.y+7)):
		for x in range(maxi(0,p.x-6),mini(WIDTH,p.x+7)):
			var target:=Vector2i(x,y)
			if Kernel.sees(p,target,solid):
				var cell:=index(target)
				visible[cell]=1;memory[cell]=1;visible_cells.append(cell)
	sight_origin=origin;fov_builds+=1

func visible_enemies()->Array[int]:
	var ids:Array[int]=[]
	for cell in visible_cells:
		var id:=occupancy[cell]
		if id>0:ids.append(id)
	return ids

func submit(kind:String,target:int=-1)->bool:
	var started:=Time.get_ticks_usec()
	effects.clear()
	if terminal():return false
	var player:=hero()
	var cost:=100
	match kind:
		"MOVE":
			if blocked(target) or not open_edge(player.cell,target):return false
			var occupant:=occupancy[target]
			if occupant>0:
				cost=int(player.attack_time);attack(player,actors[occupant])
			elif occupant==-1:
				cost=move_cost(target);move_actor(player,target);pickup()
			else:return false
		"WAIT":pass
		"POTION":
			if potions<=0 or player.hp>=player.max_hp:return false
			potions-=1;player.hp=mini(player.max_hp,player.hp+30);player.blood=mini(100,player.blood+20)
			message("회복약을 사용했습니다.")
		"TORCH":torch_lit=not torch_lit and torch_fuel>0
		"DESCEND":
			if player.cell!=exit_cell:return false
			floor_number+=1;time+=100;generate_floor();return true
		_:return false
	player.ready=time+cost
	var limit:=0
	while not scheduler.empty() and not terminal():
		var row:Array=scheduler.pop()
		var actor:Dictionary=actors[int(row[2])]
		if actor.hp<=0 or int(actor.ready)!=int(row[0]):continue
		if int(row[0])>=int(player.ready):scheduler.push(row);break
		time=int(row[0]);enemy_turn(actor)
		scheduler.push([actor.ready,actor.id,actor.id])
		limit+=1
		assert(limit<10000,"Action clock failed to advance")
	time=int(player.ready)
	if torch_lit:torch_fuel=maxi(0,torch_fuel-cost)
	if torch_fuel==0:torch_lit=false
	update_sight()
	if visible_enemies().is_empty():player.stress=maxi(0,player.stress-1)
	else:player.stress=mini(100,player.stress+1)
	if terminal():message("쓰러졌습니다. 새 게임으로 다시 시작할 수 있습니다.")
	last_action_usec=Time.get_ticks_usec()-started
	return true

func move_actor(actor:Dictionary,target:int)->void:
	var old:int=actor.cell
	var direction:=position(target)-position(old)
	actor.facing=[signi(direction.x),signi(direction.y)]
	occupancy[old]=-1;occupancy[target]=actor.id;actor.cell=target
	effects.append({"kind":"move","actor":actor.id,"from":old,"to":target})

func attack(source:Dictionary,target:Dictionary)->void:
	var defense:int=armor+int(target.skin) if target.team=="hero" else int(target.skin)
	var damage:=maxi(1,int(source.power)-defense)
	target.hp=maxi(0,int(target.hp)-damage)
	target.blood=maxi(0,100*int(target.hp)/int(target.max_hp))
	target.stress=mini(100,int(target.stress)+5)
	if visible[int(target.cell)]==1 or target.id==0:
		message("%s → %s: %d 피해"%["나" if source.id==0 else "적","나" if target.id==0 else "적",damage])
		effects.append({"kind":"hit","cell":target.cell,"amount":damage})
	if target.hp==0:
		occupancy[int(target.cell)]=-1
		if target.id>0:loot[str(target.cell)]="gold"
		message("적을 쓰러뜨렸습니다." if target.id>0 else "전투 불능")

func enemy_turn(actor:Dictionary)->void:
	var start:int=actor.cell
	var goal:int=hero().cell
	var sees:bool=Kernel.sees(position(start),position(goal),solid)
	if sees:actor.last_seen=goal
	elif actor.last_seen==start:actor.last_seen=-1
	var destination:int=actor.last_seen
	if destination<0:actor.ready=time+100;return
	var delta:=position(goal)-position(start)
	if sees and maxi(absi(delta.x),absi(delta.y))==1 and open_edge(start,goal):
		attack(actor,hero());actor.ready=time+int(actor.attack_time);return
	# Personality influences low-health retreat, without extra world simulation.
	if sees and actor.hp*3<actor.max_hp and int(actor.profile.E)>600:
		var best:=start
		var distance:=position(start).distance_squared_to(position(goal))
		for direction in Kernel.DIRECTIONS:
			var point:Vector2i=position(start)+direction
			if not in_bounds(point):continue
			var cell:=index(point)
			if blocked(cell) or occupancy[cell]>=0 or not open_edge(start,cell):continue
			if point.distance_squared_to(position(goal))>distance:
				best=cell;distance=point.distance_squared_to(position(goal))
		if best!=start:move_actor(actor,best)
	else:
		var next:=navigation.next_step(self,start,destination)
		if next>=0:move_actor(actor,next)
	actor.ready=time+maxi(int(actor.move_time),move_cost(actor.cell))

func pickup()->void:
	var key:=str(hero().cell)
	if not loot.has(key):return
	if loot[key]=="potion":potions+=1;message("회복약을 주웠습니다.")
	else:gold+=5;message("금화 5개를 주웠습니다.")
	loot.erase(key)

func plan_route(goal:int)->bool:
	var started:=Time.get_ticks_usec()
	route_steps=navigation.route(self,int(hero().cell),goal)
	last_path_usec=Time.get_ticks_usec()-started
	return not route_steps.is_empty()

func stop_auto()->void:auto_explore=false;route_steps.clear()

func auto_step()->bool:
	if terminal() or auto_explore and not visible_enemies().is_empty():stop_auto();return false
	if route_steps.is_empty() and auto_explore:
		# One BFS finds the nearest reachable frontier; no search per candidate.
		var queue:=PackedInt32Array([int(hero().cell)])
		var parent:=PackedInt32Array();parent.resize(terrain.size());parent.fill(-2)
		parent[queue[0]]=-1
		var head:=0
		var goal:=-1
		while head<queue.size():
			var cell:=queue[head];head+=1
			for direction in Kernel.DIRECTIONS:
				var point:Vector2i=position(cell)+direction
				if not in_bounds(point):continue
				var next:=index(point)
				if memory[next]==0 and open_edge(cell,next):goal=cell;break
				if parent[next]!=-2 or blocked(next) or occupancy[next]>=0 or not open_edge(cell,next):continue
				parent[next]=cell;queue.append(next)
			if goal>=0:break
		if goal>=0:
			while parent[goal]>=0:route_steps.append(goal);goal=parent[goal]
			route_steps.reverse()
	if route_steps.is_empty():stop_auto();return false
	var next:=route_steps[0];route_steps.remove_at(0)
	var health_before:int=hero().hp
	if not submit("MOVE",next):stop_auto();return false
	if hero().hp<health_before:stop_auto()
	return true

func save_data()->Dictionary:
	return {"schema":SCHEMA,"seed":seed,"floor":floor_number,"time":time,
		"terrain":Array(terrain),"memory":Array(memory),"actors":actors.duplicate(true),
		"loot":loot.duplicate(),"lights":Array(lights),"exit":exit_cell,"gold":gold,
		"potions":potions,"torch_fuel":torch_fuel,"torch_lit":torch_lit,"armor":armor,"weapon":weapon}

func restore(data:Dictionary)->bool:
	if int(data.get("schema",-1))!=SCHEMA:return false
	for key in ["seed","floor","time","terrain","memory","actors","loot","lights","exit","gold","potions","torch_fuel","torch_lit","armor","weapon"]:
		if not data.has(key):return false
	if not data.loot is Dictionary or not data.lights is Array:return false
	if int(data.time)<0 or int(data.floor)<1 or int(data.exit)<0 or int(data.exit)>=WIDTH*HEIGHT:return false
	for light in data.lights:
		if int(light)<0 or int(light)>=WIDTH*HEIGHT:return false
	if not data.get("terrain") is Array or data.terrain.size()!=WIDTH*HEIGHT:return false
	if not data.get("memory") is Array or data.memory.size()!=WIDTH*HEIGHT:return false
	if not data.get("actors") is Array or data.actors.is_empty() or data.actors.size()>512:return false
	var taken:Dictionary={}
	for i in range(data.actors.size()):
		var a:Variant=data.actors[i]
		if not a is Dictionary:return false
		for field in make_actor(0,0,"hero"):
			if not a.has(field):return false
		var cell:=int(a.cell)
		if int(a.id)!=i or cell<0 or cell>=WIDTH*HEIGHT or int(a.hp)<0 or int(a.hp)>int(a.max_hp):return false
		if int(a.ready)<0 or int(a.move_time)<1 or int(a.attack_time)<1:return false
		if int(a.hp)>0:
			if taken.has(cell) or data.terrain[cell]=="wall":return false
			taken[cell]=true
	seed=int(data.seed);floor_number=int(data.floor);time=int(data.time)
	terrain=PackedStringArray(data.terrain);memory=PackedByteArray(data.memory)
	actors.assign(data.actors.duplicate(true))
	for actor in actors:
		for key in ["id","cell","hp","max_hp","ready","power","move_time","attack_time","stress","skin","bone","blood","last_seen"]:
			actor[key]=int(actor[key])
		actor.profile=Personality.from_dict(actor.profile).to_dict()
		actor.facing=[int(actor.facing[0]),int(actor.facing[1])]
	loot=data.loot.duplicate();lights=PackedInt32Array(data.lights);exit_cell=int(data.exit)
	gold=int(data.gold);potions=int(data.potions);torch_fuel=int(data.torch_fuel)
	torch_lit=bool(data.torch_lit);armor=int(data.armor);weapon=str(data.weapon)
	occupancy.fill(-1);scheduler.clear()
	for actor in actors:
		if actor.hp<=0:continue
		occupancy[int(actor.cell)]=actor.id
		if actor.id>0:scheduler.push([actor.ready,actor.id,actor.id])
	navigation.fields.clear();rebuild_lights();sight_origin=-1;stop_auto();update_sight();return true
