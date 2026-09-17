extends SceneTree
const World=preload("res://game/crawl/world.gd")
var failures:Array[String]=[]
var checks=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);printerr("FAIL ",label)
func arena(seed:int=1):
	var w=World.new(seed)
	for a in w.actors:
		if a.id>0:a.hp=0
	w.terrain.fill("floor")
	for i in range(w.WIDTH):w.terrain[i]="wall";w.terrain[(w.HEIGHT-1)*w.WIDTH+i]="wall"
	for i in range(w.HEIGHT):w.terrain[i*w.WIDTH]="wall";w.terrain[i*w.WIDTH+w.WIDTH-1]="wall"
	w.current().terrain=Array(w.terrain);w.current().loot={};w.current().hazards={};w.current().features={}
	w.hero().cell=w.index(Vector2i(15,15));w.rebuild_occupancy();w.update_sight();return w
func _initialize()->void:
	call_deferred("run")
func run()->void:
	check(World.DATA.monsters.size()==24,"24 enemy roles")
	check(World.DATA.spells.size()==12,"12 spells")
	var terrains={}
	for seed in range(1,17):
		var w=World.new(seed)
		for floor_id in World.DATA.floors:
			w.enter_floor(floor_id,"")
			var visited={int(w.hero().cell):true};var queue=[int(w.hero().cell)];var head=0
			while head<queue.size():
				var c=int(queue[head]);head+=1
				for d in w.Kernel.DIRECTIONS:
					var p=w.position(c)+d;var n=w.index(p)
					if w.in_bounds(p) and not visited.has(n) and w.open_edge(c,n):visited[n]=true;queue.append(n)
			for c in w.current().features:check(visited.has(int(c)),"reachable %d %s %s"%[seed,floor_id,c])
			check(w.validation_error(w.save_data()).is_empty(),"valid generated %d %s: %s"%[seed,floor_id,w.validation_error(w.save_data())])
		terrains[JSON.stringify(w.floors.D1.terrain).sha256_text()]=true
	check(terrains.size()==16,"distinct seeds")
	var w=arena()
	var start=w.time;var hp=w.hero().hp
	check(not w.submit("MOVE",-1) and w.time==start and w.hero().hp==hp,"invalid input no time/damage")
	check(w.submit("WAIT") and w.time==100 and w.boundary==200,"environment clock")
	var enemy=w.spawn(World.DATA.monsters[0],w.floor_id,w.hero().cell+1);w.rebuild_occupancy();w.update_sight()
	w.auto_explore=true;check(not w.auto_step() and not w.auto_explore,"explore stops at enemy")
	check(not w.start_rest(),"rest blocked by enemy")
	w.skills.melee=3600
	for i in range(10):
		if enemy.hp<=0:break
		w.submit("ATTACK",enemy.cell)
	check(enemy.hp==0 and w.xp>0 and w.skills.survival>0,"kill and goal XP")
	# Valid save restores exact RNG continuation, not a fresh combat roll.
	var wire=JSON.parse_string(JSON.stringify(w.save_data()));var loaded=World.new(987)
	check(loaded.restore(wire),"restore: "+loaded.last_error)
	for i in range(4):w.submit("WAIT");loaded.submit("WAIT")
	check(w.save_data()==loaded.save_data(),"deterministic continuation")
	var old=loaded.save_data();var corrupt=wire.duplicate(true);corrupt.actors[0].cell=-3
	check(not loaded.restore(corrupt) and loaded.save_data()==old,"bad save leaves live run intact")
	for spell_id in World.DATA.spells:
		var sw=arena(91);sw.spells=World.DATA.spells.keys();sw.prepared=[spell_id]
		for key in sw.skills:sw.skills[key]=10000
		sw.hero().mp=100;sw.hero().max_mp=100;sw.hero().hp-=20
		var cell=sw.hero().cell+2;var target=sw.spawn(World.DATA.monsters[5],sw.floor_id,cell);target.hp=100;target.max_hp=100
		sw.rebuild_occupancy();sw.update_sight()
		if spell_id in ["hound","turret"]:cell=sw.hero().cell+sw.WIDTH
		if spell_id=="passwall":sw.terrain[sw.hero().cell+1]="wall";target.hp=0;sw.rebuild_occupancy();sw.update_sight()
		if spell_id=="ignite":target.statuses.poison=sw.time+500
		var before=sw.hero().mp
		check(sw.submit("CAST",cell,spell_id),"cast "+spell_id+": "+sw.last_error)
		check(sw.hero().mp<before,"spell consumes MP "+spell_id)
		check(sw.time>=100,"spell consumes time "+spell_id)
		check(sw.validation_error(sw.save_data()).is_empty(),"spell state "+spell_id+": "+sw.validation_error(sw.save_data()))
	var rw=arena();var r=rw.spawn(World.DATA.monsters[11],rw.floor_id,rw.hero().cell+2);rw.rebuild_occupancy();var before=int(r.hp)
	rw.damage(rw.hero(),r,20,"fire");check(before-r.hp==5,"75% fire resistance")
	rw.add_hazard(rw.hero().cell,"fire",300);before=rw.hero().hp;rw.submit("WAIT");check(rw.hero().hp<before,"environment hurts player")
	var fw=arena();var shooter=fw.spawn(World.DATA.monsters[2],fw.floor_id,fw.hero().cell+4);fw.rebuild_occupancy();fw.update_sight()
	fw.add_hazard(fw.hero().cell+1,"fog",400);fw.update_sight();check(not fw.can_see(shooter,fw.hero().cell),"fog blocks enemy sight too")
	for deity in World.DATA.gods:
		var gw=arena();gw.current().features[str(gw.hero().cell)]={"kind":"altar","god":deity}
		check(gw.submit("WORSHIP",-1,deity) and gw.god==deity,"worship "+deity)
		gw.piety=100
		if deity=="war":
			check(not gw.submit("CAST",gw.hero().cell,"blink"),"martial ban")
			check(gw.submit("GOD") and gw.hero().statuses.has("rage"),"martial active")
		elif deity=="bind":
			gw.inventory.append(gw.item("weapon","axe"));check(not gw.submit("EQUIP",gw.inventory.size()-1),"gear binding")
			check(gw.submit("BREAK_BIND") and gw.inventory[0].destroyed,"binding destruction")
		else:check(gw.actors[-1].ai=="guardian" and gw.hero().max_hp<72,"kin sacrifice and guardian")
		check(gw.submit("ABANDON") and gw.penance>0,"abandonment "+deity)
	# All branch stairs are exercised with submit, suppressing combat for topology test.
	var run_world=World.new(420)
	for id in World.DATA.floors:
		if not run_world.floors.has(id):run_world.generate(id)
		run_world.floors[id].return_spawned=true
	for a in run_world.actors:
		if a.id>0:a.hp=0
	run_world.rebuild_occupancy()
	for dest in ["D2","D3","M1","M2","M1","D3","F1","F2","F1","D3","Z","D3","D2","D1","OUT"]:
		if run_world.floor_id in ["M2","F2","Z"]:
			for c in run_world.current().features.keys():
				if run_world.current().features[c].kind in ["rune","orb"]:
					walk(run_world,int(c));check(run_world.submit("INTERACT"),"objective pickup")
		var destination=-1
		for c in run_world.current().features:
			var f:Dictionary=run_world.current().features[c]
			if f.kind=="stairs" and f.to==dest:destination=int(c);break
		check(destination>=0,"stair exists "+dest)
		if destination<0:break
		walk(run_world,destination);check(run_world.submit("INTERACT"),"transition "+dest)
		check(run_world.validation_error(run_world.save_data()).is_empty(),"run state "+dest)
	check(run_world.won and run_world.runes.size()==2 and run_world.orb,"two runes orb return victory")
	var chase=arena();chase.orb=true;chase.enter_floor("D2","D1")
	check(chase.current().get("return_spawned",false),"orb reinforcements")
	var chase_count=chase.actors.size();chase.enter_floor("D1","D2");chase.enter_floor("D2","D1")
	check(chase.actors.size()<=chase_count+2,"reinforcements not farmed")
	var explore_world=World.new(1337)
	for a in explore_world.actors:
		if a.id>0:a.hp=0
	explore_world.current().hazards.clear();explore_world.rebuild_occupancy()
	for i in range(900):
		explore_world.auto_explore=true
		if not explore_world.auto_step():break
	var unknown_open=0
	for c in range(explore_world.terrain.size()):
		if not explore_world.blocked(c) and explore_world.memory[c]==0:unknown_open+=1
	check(unknown_open==0,"auto-explore finishes reachable map, no corner stall")
	var dead=arena();dead.hero().hp=0;var t=dead.time
	check(not dead.submit("WAIT") and dead.time==t,"permadeath terminal")
	var dying=arena();dying.hero().hp=1;dying.add_hazard(dying.hero().cell,"fire",300)
	dying.submit("WAIT")
	check(dying.terminal() and dying.validation_error(dying.save_data()).is_empty(),"death can be saved")
	print("MODEL_B_ACCEPTANCE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
func walk(w,goal:int)->void:
	# Movement and the complete action clock still run; no teleporting objectives.
	w.current().hazards.clear()
	var path=w.navigation.route(w,int(w.hero().cell),goal,false)
	for c in path:check(w.submit("MOVE",c),"walk objective")
	check(w.hero().cell==goal,"arrived objective")
