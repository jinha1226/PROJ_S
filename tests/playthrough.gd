extends SceneTree
const Session = preload("res://expedition/session.gd")
const Fixture = preload("res://tests/map_fixture.gd")

func _initialize() -> void:
	var s = Session.new()
	s.depart()
	for next in Fixture.path(s,8):
		if not s.travel(next): break
		if s.phase == "BATTLE": fight(s)
		elif s.rooms[s.room].kind == "camp": s.camp()
	var won: bool = s.phase == "EXPLORE" and s.room == 8 and s.rooms[8].cleared
	if won: s.retreat()
	print("Public-action map playthrough: won=%s, survivors=%d, bank=%d" % [won,s.alive().size(),s.bank])
	quit(0 if won and s.bank >= 100 else 1)

func fight(s) -> void:
	for turn in range(30):
		if s.phase != "BATTLE": break
		for index in range(s.party.size()):
			s.selected = index
			var actor: Dictionary = s.party[index]
			for action in range(2):
				if s.phase != "BATTLE" or actor.hp <= 0 or actor.ap <= 0: break
				var targets: Array = s.enemies.filter(func(e): return e.hp > 0)
				targets.sort_custom(func(a,b): return s.distance(actor.pos,a.pos) < s.distance(actor.pos,b.pos))
				var target: Dictionary = targets[0]
				if s.distance(actor.pos,target.pos) == 1:
					s.act("ATTACK",target.pos)
					continue
				var choices: Array = []
				for y in range(preload("res://expedition/dungeon_map.gd").ROOM_SIDE):
					for x in range(preload("res://expedition/dungeon_map.gd").ROOM_SIDE):
						var cell := Vector2i(x,y)
						if s.is_free(cell) and s.distance(actor.pos,cell) <= 2: choices.append(cell)
				choices.sort_custom(func(a,b): return s.distance(a,target.pos) < s.distance(b,target.pos))
				for cell in choices:
					if s.act("MOVE",cell): break
		if s.phase == "BATTLE": s.end_round()
