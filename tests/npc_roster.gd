extends SceneTree
## Run roster: ten NPCs, two duos, three to five placed per floor with a situation.
const Session = preload("res://expedition/session.gd")
const Roster = preload("res://expedition/npc_roster.gd")
var failures := 0
var checks := 0
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)
func _initialize() -> void: call_deferred("run")

func run() -> void:
	roster(); placement(); reappearance()
	print("NPC roster: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func roster() -> void:
	var s = Session.new(41,false,false,true,1)
	var rows: Array = Roster.generate(s)
	check(rows.size() == 10 and s.roster == rows,"ten NPCs on the run roster")
	var names: Array = rows.map(func(n): return n.name)
	check(names.size() == names.reduce(func(acc,n): return acc if n in acc else acc+[n],[]).size(),"names are unique")
	check(rows.all(func(n): return n.npc and not n.enemy and n.id >= 100 and n.hp == 55 and n.max_hp == 55 and n.state == "UNMET" and not n.awake),"npc fields")
	check(rows.all(func(n): return n.stress >= 0 and n.stress <= 40),"stress 0-40")
	check(rows.all(func(n): return n.stance in ["CHARGER","SKIRMISHER","GUARDIAN"] and n.stance == s.Stances.default_stance(n.profile)),"stance is the personality's default")
	var with_part: int = rows.filter(func(n): return n.equipped_abilities[0] != "").size()
	check(with_part >= 1 and with_part <= 8 and rows.all(func(n): return n.equipped_abilities[1] == "" and (n.equipped_abilities[0] == "" or n.rules.size() == 1)),"some carry one part with its rule")
	var paired: Array = rows.filter(func(n): return n.partner >= 0)
	check(paired.size() == 4 and paired.all(func(n): return rows.filter(func(m): return m.id == n.partner)[0].partner == n.id),"two mutual duos")
	check(paired.all(func(n): return n.bond in ["close","strained"] and rows.filter(func(m): return m.id == n.partner)[0].bond == n.bond),"bond shared by the pair")
	check(rows.filter(func(n): return n.partner < 0).all(func(n): return n.bond == ""),"singles have no bond")
	var again: Array = Roster.generate(Session.new(41,false,false,true,1))
	check(again.map(func(n): return [n.name,n.partner,n.bond,n.stance]) == rows.map(func(n): return [n.name,n.partner,n.bond,n.stance]),"deterministic per seed")

func placement() -> void:
	var s = Session.new(42,false,false,true,1); s.depart()
	check(s.roster.size() == 10,"depart generates the roster")
	check(s.npcs.size() == 3,"floor 1 places three")
	check(s.npcs.all(func(n): return n.state == "MET" and n.floor_seen == Roster.depth(s) and n.hp > 0),"placed NPCs are met on this floor")
	for n in s.npcs:
		check(s.inside(n.pos) and s.tile(n.pos).terrain != "wall" and s.at(n.pos) == n,"npc stands on a floor cell and at() finds it")
		check(Roster.situation(n) in ["FIGHTING","WOUNDED","RESTING"],"situation set")
		if Roster.situation(n) == "WOUNDED": check(n.hp*100/n.max_hp >= 30 and n.hp*100/n.max_hp <= 50 and n.stress >= 30,"wounded hp 30-50%% (%s)" % n.name)
		if Roster.situation(n) == "FIGHTING":
			check(n.hp*100/n.max_hp >= 60 and n.hp*100/n.max_hp <= 80,"fighting hp 60-80%%")
			check(s.enemies.any(func(e): return e.hp > 0 and e.get("npc_pack",-1) == n.id and s.distance(e.pos,n.pos) <= 2),"a pack placed beside the fighting npc")
		if Roster.situation(n) == "RESTING": check(n.hp == n.max_hp,"resting at full")
	var rooms: Array = Roster.npc_rooms(s.floor_state.layout)
	check(rooms.size() >= 3 and rooms.size() <= 5,"three to five npc rooms")
	check(s.npcs.all(func(n): return rooms.any(func(r): return s.floor_state.layout.rooms[r].rect.has_point(n.pos))),"npcs stand in npc rooms")
	# Duos placed together when both are free.
	var duo_seen := false
	for seed in range(20):
		var t = Session.new(seed,false,false,true,1); t.depart()
		for n in t.npcs:
			if n.partner >= 0 and t.npcs.any(func(m): return m.id == n.partner):
				duo_seen = true
				var m: Dictionary = t.npcs.filter(func(x): return x.id == n.partner)[0]
				check(t.distance(n.pos,m.pos) <= 2,"duo placed together (seed %d)" % seed)
	check(duo_seen,"some seed places a duo")
	# Hungry flag: half of the wounded/fighting.
	var hungry := 0; var eligible := 0
	for seed in range(20):
		var t = Session.new(100+seed,false,false,true,1); t.depart()
		for n in t.npcs:
			if Roster.situation(n) != "RESTING": eligible += 1; hungry += 1 if n.hungry else 0
	check(hungry > 0 and hungry < eligible,"some, not all, are hungry (%d/%d)" % [hungry,eligible])

func reappearance() -> void:
	var s = Session.new(43,false,false,true,1); s.depart()
	var first: Array = s.npcs.map(func(n): return n.id)
	var met: Dictionary = s.npcs[0]; met.hp = 50
	Roster.place(s) # second floor placement on the same layout for the test
	check(s.npcs.size() >= 4 and s.npcs.size() <= 5,"later floors place four or five")
	var unmet_first: bool = s.npcs.filter(func(n): return n.id not in first).size() >= s.npcs.size()-first.size()
	check(unmet_first,"unmet NPCs are preferred")
	if s.npcs.any(func(n): return n.id == met.id):
		var back: Dictionary = s.npcs.filter(func(n): return n.id == met.id)[0]
		check(back.hp >= 35 and back.hp <= 45,"a met NPC returns 10-30%% worse off")
	met.state = "DEAD"; Roster.place(s)
	check(not s.npcs.any(func(n): return n.id == met.id),"the dead never return")
	s.roster[3].state = "PARTY"; Roster.place(s)
	check(not s.npcs.any(func(n): return n.id == s.roster[3].id),"party members are not placed")
