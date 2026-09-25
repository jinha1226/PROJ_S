extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const NpcAI = preload("res://expedition/actors/npc_ai.gd")
const Hostility = preload("res://expedition/actors/npc_hostility.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
const Summons = preload("res://expedition/spells/summons.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func field(offset: Vector2i) -> Dictionary:
	var s = Session.new(91,true,true,true,3)
	s.depart()
	var c := Fixture.arena(s,12)
	Fixture.equip_basics(s)
	var npc: Dictionary = s.npcs[0]
	s.npcs = [npc]
	npc.pos = c+offset
	npc.hp = npc.max_hp
	npc.stress = 0
	npc.awake = true
	npc.hostile = false
	npc.partner = -1
	npc.equipped_abilities = ["",""]
	npc.rules = []
	s.floor_state.observe(s)
	return {"s":s,"npc":npc,"c":c}

func traits(npc: Dictionary, h: int, a: int, x: int) -> void:
	npc.profile = Hexaco.new({"H":h,"A":a,"X":x,"E":500,"C":500,"O":500})

func run() -> void:
	personality_and_situation()
	first_strike_and_pursuit()
	player_assault()
	defense_and_death()
	summon_sides()
	print("NPC hostility: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func personality_and_situation() -> void:
	var f := field(Vector2i(2,0)); var s = f.s; var npc: Dictionary = f.npc
	traits(npc,0,0,1000)
	check(not Hostility.may_start(s,npc),"healthy party deters even aggressive NPC")
	s.party[0].hp = 2
	check(Hostility.may_start(s,npc),"low H/A NPC sees an injured hero as an opening")
	npc.hp = maxi(1,npc.max_hp/5)
	check(not Hostility.may_start(s,npc),"wounded NPC is less willing to start a fight")
	npc.hp = npc.max_hp
	traits(npc,1000,1000,500)
	check(not Hostility.may_start(s,npc),"warm, honest NPC does not prey on weakness")
	traits(npc,0,0,1000)
	s.serial += 1
	s.remember_plain(npc,"AID_RECEIVED",s.party[0].id+1,s.party[0].id+1,500)
	check(not Hostility.may_start(s,npc),"receiving aid strongly deters betrayal")

func first_strike_and_pursuit() -> void:
	var f := field(Vector2i(1,0)); var s = f.s; var npc: Dictionary = f.npc
	traits(npc,0,0,1000)
	s.party[0].hp = 2
	NpcAI.turn(s,npc)
	check(npc.hostile and npc.activity == "적대 중","NPC turns hostile on its own turn")
	check(npc.ap == 0,"hostile NPC spends its action attacking")
	check(npc in s.party_enemies() and npc not in s.friends(),"party sees hostile NPC as a threat, not a friend")
	check(not s.Recruit.dialogue(s,npc).can_propose and not s.Recruit.dialogue(s,npc).can_aid,"hostile NPC cannot be recruited or aided")
	var g := field(Vector2i(4,0)); var t = g.s; var pursuer: Dictionary = g.npc
	traits(pursuer,0,0,1000)
	t.party[0].hp = 2
	var before: int = t.distance(pursuer.pos,t.party[0].pos)
	NpcAI.turn(t,pursuer)
	check(pursuer.hostile and t.distance(pursuer.pos,t.party[0].pos) < before,"hostile NPC closes distance through normal movement")

func player_assault() -> void:
	var f := field(Vector2i(1,0)); var s = f.s; var npc: Dictionary = f.npc
	traits(npc,1000,1000,500)
	check(not s.attack_preview(npc.pos).is_empty(),"neutral NPC is a valid player attack target")
	check(s.act("ATTACK",npc.pos),"player may attack a neutral NPC")
	check(npc.hostile,"attacked NPC stays hostile even if the attack misses")
	check(npc.memory.salience_for_subject(s.party[0].id+1,["ATTACKED_BY_PLAYER"]) > 0,"NPC remembers the player's attack")
	check(not s.recruit(npc) and not s.aid(npc),"hostility blocks social actions")

func defense_and_death() -> void:
	var f := field(Vector2i(1,0)); var s = f.s; var npc: Dictionary = f.npc
	var monster: Dictionary = s.enemies[0]
	monster.hp = 30
	monster.pos = npc.pos+Vector2i(0,1)
	monster.part_id = ""
	monster.charging = false
	s.NpcHostility.provoke(s,npc,s.party[0])
	var before: int = monster.hp
	NpcAI.turn(s,npc)
	check(npc.ap == 0 and (monster.hp < before or s.effects.any(func(e): return e.get("cell",Vector2i(-1,-1)) == monster.pos)),"hostile NPC defends itself against an adjacent monster")
	monster.hp = 0
	npc.hp = 1
	var kills: int = int(s.run_stats.kills)
	var stress: int = int(s.party[0].stress)
	for i in range(12):
		if npc.hp <= 0: break
		s.party[0].ap = 1
		s.act_as(s.party[0],"ATTACK",npc.pos,false)
	check(npc.state == "DEAD","player can finish a weak NPC")
	check(int(s.run_stats.kills) == kills and s.party[0].stress == stress,"hostile NPC death grants no monster kill or grief")

func summon_sides() -> void:
	var f := field(Vector2i(2,0)); var s = f.s
	var ally: Dictionary = Summons.summon(s,s.party[0],f.c+Vector2i(0,1))
	var enemy_caster: Dictionary = s.enemies[0]
	enemy_caster.hp = 20
	enemy_caster.pos = f.c+Vector2i(4,4)
	var enemy_pet: Dictionary = Summons.summon(s,enemy_caster,f.c+Vector2i(4,3))
	s.floor_state.observe(s)
	check(s.side_of(ally) == 0 and s.side_of(enemy_pet) == 1,"summons retain their caster's side")
	check(ally in s.friends() and enemy_pet not in s.friends(),"enemy summon is not a party friend")
	check(s.attack_preview(ally.pos).is_empty(),"player cannot assault an allied summon")
