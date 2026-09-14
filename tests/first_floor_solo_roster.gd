extends SceneTree
const Generator=preload("res://sim/nine_room_generator.gd")
const Stages=preload("res://sim/first_floor_stages.gd")
func _init():
	var failures:Array=[]
	for seed in [44,20260828,99]:
		var floor:Dictionary=Generator.generate(seed,1)
		for room in floor.rooms:
			var count:int=floor.enemy_roster.filter(func(e):return e.group_id=="ROOM_%d"%room.room_id).size()
			if count!=(1 if room.role=="COMBAT" else 0):failures.append("room roster %d"%room.room_id)
			var spec:Dictionary=Stages.room(room.room_id)
			for y in range(8):
				for x in range(8):
					if spec.rows[y][x]=="#" and floor.terrain[(room.bounds[1]+y)*24+room.bounds[0]+x]!="wall":failures.append("pillar removed")
		if floor.enemy_roster.size()!=4:failures.append("first floor must have four initial enemies")
		var second:Dictionary=Generator.generate(seed,2)
		for room in second.rooms:
			if room.role=="COMBAT" and second.enemy_roster.filter(func(e):return e.group_id=="ROOM_%d"%room.room_id).size()!=int(Generator.CONFIG.enemies_per_combat_room):failures.append("second floor changed")
	print("FIRST_FLOOR_SOLO_ROSTER ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
