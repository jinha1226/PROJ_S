extends SceneTree
const Auto=preload("res://playtest/party_auto_explore.gd")
const Reference=preload("res://tests/fixtures/reference_frontier_search.gd")
const Search=preload("res://playtest/fog_frontier_search.gd")
var failures:Array=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func run()->void:
	var planner=Auto.new(self);var reference=Reference.new(self)
	var rng:=RandomNumberGenerator.new();rng.seed=17171
	var old_us:=0;var new_us:=0
	for trial in range(120):
		var cells:Dictionary={};var visited:Dictionary={}
		for y in range(18):
			for x in range(18):
				if rng.randi_range(0,9)==0:continue
				var key:="%d:%d"%[x,y]
				cells[key]={"passable":rng.randi_range(0,5)!=0,"occupied":rng.randi_range(0,19)==0,
					"move_time_cost":rng.randi_range(1,5)*100,"diagonal_gateway":rng.randi_range(0,9)==0,
					"risk":10 if rng.randi_range(0,19)==0 else 0,"visibility_state":"MEMORY"}
				if rng.randi_range(0,3)==0:visited[key]=true
		cells["9:9"]={"passable":true,"move_time_cost":100}
		var snapshot:={"width":18,"height":18,"visited":visited}
		if trial%3!=0:snapshot["exit_position"]=[16,16];snapshot["exit_open"]=trial%3==2
		var begun:=Time.get_ticks_usec()
		var expected:Dictionary=reference._nearest_safe_frontier(snapshot,cells,Vector2i(9,9))
		old_us+=Time.get_ticks_usec()-begun;begun=Time.get_ticks_usec()
		var actual:Dictionary=planner._nearest_safe_frontier(snapshot,cells,Vector2i(9,9))
		new_us+=Time.get_ticks_usec()-begun
		check(actual==expected,"exact target/path/cost parity trial %d"%trial)
		var search=Search.new();search.search(snapshot,cells,Vector2i(9,9),{})
		for y in range(1,17):
			for x in range(1,17):
				var p:=Vector2i(x,y)
				for delta in Search.Directions:
					check(search.can_step(p,p+delta)==planner._known_step_is_safe(p,p+delta,cells),
						"diagonal/occupancy safety parity")
	# Unknown open exit must not force a complete known-component flood fill.
	var large:Dictionary={}
	for y in range(64):
		for x in range(64):
			if x==32 and y==33 or x==63 and y==63:continue
			large["%d:%d"%[x,y]]={"passable":true,"move_time_cost":100}
	var bounded:={"width":64,"height":64,"exit_open":true,"exit_position":[32,33]}
	var result:Dictionary=planner._nearest_safe_frontier(bounded,large,Vector2i(32,32))
	check(result.found and planner.last_search_expanded<large.size(),"unknown exit permits early stop")
	print("FRONTIER EQUIVALENCE old_us=",old_us," new_us=",new_us," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
