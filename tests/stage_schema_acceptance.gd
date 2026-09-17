extends SceneTree
const Catalog=preload("res://sim/stage_catalog.gd")
const Legacy=preload("res://sim/first_floor_stages.gd")
var failures:Array=[]
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():
	var doc:Dictionary=Catalog.floor(1)
	check(Catalog.error(doc).is_empty(),"f1 valid: "+Catalog.error(doc))
	check(doc.rooms.size()==9,"nine rooms")
	var ids:Dictionary={}
	for spec in doc.rooms:
		ids[spec.id]=true
		check(spec.design.keys().size()==5 and spec.design.difficulty is float or spec.design.difficulty is int,"design present "+spec.id)
		for e in spec.enemies:
			check(spec.rows[e.cell[1]][e.cell[0]]!="#","enemy on floor "+spec.id)
			check(e.role in Catalog.ENEMY_ROLES,"enemy role "+spec.id)
			check(not preload("res://sim/enemy_perception_registry.gd").profile(e.kind).is_empty(),"enemy kind exists "+spec.id+" "+str(e.kind))
		check(spec.objective.type in Catalog.OBJECTIVES,"objective "+spec.id)
		for edge in spec.reinforcements.spawn_edges:check(edge in Catalog.EDGES,"spawn edge "+spec.id)
	check(ids.size()==9,"unique ids")
	# Shim keeps the legacy surface used by the generator and older tests.
	check(Legacy.CONTENT.rooms.size()==9 and Legacy.CONTENT.edges.size()>0,"shim content")
	check(Legacy.room(0).has("enemy_cells"),"shim derives enemy_cells")
	check(Legacy.room(0).enemy_cells==Catalog.wave_enemies(Catalog.room(1,0),0).map(func(e):return e.cell),"enemy_cells equals wave 0")
	# Validator rejects broken documents.
	var broken:Dictionary=doc.duplicate(true);broken.rooms[0].enemies.append({"cell":[0,0],"kind":"goblin","role":"ASSAULT","wave":0})
	check(Catalog.error(broken)=="enemy_on_wall:f1_watchpost","wall spawn rejected: "+Catalog.error(broken))
	broken=doc.duplicate(true);broken.rooms[1].erase("design")
	check(Catalog.error(broken)=="design_missing:f1_descent","design required: "+Catalog.error(broken))
	broken=doc.duplicate(true);broken.rooms[0].objective.type="SURVIVE";broken.rooms[0].objective.rounds=0
	check(Catalog.error(broken)=="objective_rounds:f1_watchpost","survive needs rounds: "+Catalog.error(broken))
	broken=doc.duplicate(true);broken.rooms[0].enemies.append({"cell":[5,2],"kind":"goblin","role":"ASSAULT","wave":0})
	check(Catalog.error(broken)=="enemy_cell_duplicate:f1_watchpost","duplicate cell rejected: "+Catalog.error(broken))
	print("STAGE_SCHEMA ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
