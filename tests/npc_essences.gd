extends SceneTree
## §3.9: strangers pick essences by personality, keep a set going, earn their
## own essences from their own kills and bring them along when recruited.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const NpcEssences = preload("res://expedition/actors/npc_essences.gd")
const Hexaco = preload("res://sim/dungeon_population/hexaco_profile.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func stranger(s, index: int, facets: Dictionary, essences: Dictionary, level: int) -> Dictionary:
	var npc: Dictionary = s.roster[index]
	npc.profile = Hexaco.new(facets)
	npc.level = level; npc.essences = essences.duplicate(); npc.essence_spells = {}; npc.essence_seen = {}
	npc.equipped_abilities = []
	Essences.sync_slots(npc)
	return npc

func run() -> void:
	var s = Session.new_run(731)
	var caster: String = str(Essences.CASTER_BY_SCHOOL.fire)
	var pool := {"ORC_CLEAVER":1,"HOB_TAUNT":1,"RAT_GNAW":1,caster:1}
	var blunt: Dictionary = stranger(s,0,{"A":100,"C":500,"O":500},pool,1)
	NpcEssences.choose(s,blunt)
	check(blunt.equipped_abilities == ["ORC_CLEAVER"],"low agreeableness wears the berserker")
	var careful: Dictionary = stranger(s,1,{"A":900,"C":950,"O":100},pool,1)
	NpcEssences.choose(s,careful)
	check(careful.equipped_abilities == ["HOB_TAUNT"],"high conscientiousness wears the guard")
	var curious: Dictionary = stranger(s,2,{"A":900,"C":100,"O":950},pool,1)
	NpcEssences.choose(s,curious)
	check(curious.equipped_abilities == [caster],"high openness wears the caster")
	check(not str(curious.essence_spells.get(caster,"")).is_empty(),"and picks a spell for it")
	var pack: Dictionary = stranger(s,3,{"A":100,"C":500,"O":500},{"ORC_CLEAVER":1,"GNOLL_SPEAR":1,"GOBLIN_SHIV":1},2)
	NpcEssences.choose(s,pack)
	check(pack.equipped_abilities == ["GNOLL_SPEAR","ORC_CLEAVER"],"a second berserker keeps the set going over an equal ambusher")
	check(NpcEssences.continuing(["GNOLL_SPEAR"],"ORC_CLEAVER") == 1 and NpcEssences.continuing(["GNOLL_SPEAR"],"GOBLIN_SHIV") == 0,"continuation counts shared tags")
	# Its own hunt.
	var hunter: Dictionary = stranger(s,4,{"A":500,"C":500,"O":500},{},1)
	var foe: Dictionary = s.enemies.filter(func(e): return Essences.has(str(e.get("part_id",""))))[0]
	var bag: Dictionary = s.parts_bag.duplicate(true)
	NpcEssences.on_hunt(s,foe,[hunter])
	check(Essences.absorbed(hunter,str(foe.part_id)),"the first kill of a species gives the npc its essence")
	check(hunter.equipped_abilities[0] == str(foe.part_id),"and it wears it at once")
	check(hunter.essence_seen.has(str(foe.species_id)),"the species is remembered")
	check(s.parts_bag == bag,"the party bag is untouched")
	var variant: Dictionary = foe.duplicate(true)
	variant.variant_element = "fire"; variant.part_id = str(foe.part_id)+"@fire"
	NpcEssences.on_hunt(s,variant,[hunter])
	check(Essences.absorbed(hunter,str(variant.part_id)) and hunter.essence_seen.has(str(foe.species_id)+"@fire"),"the variant has its own first kill")
	var hero_before: Dictionary = s.party[0].get("essences",{}).duplicate()
	NpcEssences.on_hunt(s,foe,[s.party[0]])
	check(s.party[0].get("essences",{}) == hero_before,"party members take nothing through this path")
	# The session's kill path calls it.
	var other: Dictionary = stranger(s,5,{"A":500,"C":500,"O":500},{},1)
	var second: Dictionary = s.enemies.filter(func(e): return e.hp > 0 and e.id != foe.id and Essences.has(str(e.get("part_id",""))))[0]
	other.hp = other.max_hp; other.state = "MET"; other.pos = second.pos+Vector2i(1,0)
	s.npcs.append(other)
	s.damage(second,9999,int(other.id),"SLASH")
	check(second.hp <= 0 and Essences.absorbed(other,str(second.part_id)),"an npc's own kill in play gives it the essence")
	check(s.parts_bag == bag,"still nothing for the party")
	# Recruited, it keeps them.
	var kept: Dictionary = other.essences.duplicate(); var worn: Array = other.equipped_abilities.duplicate()
	s.Recruit.join(s,other)
	check(s.party[-1].essences == kept and s.party[-1].equipped_abilities == worn,"recruiting keeps the essences and the loadout")
	print("NPC essences: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
