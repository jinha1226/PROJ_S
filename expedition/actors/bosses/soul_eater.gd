extends RefCounted
## 9층 영혼 포식자 (spec §7.3): 영혼석. Four zone-3 monsters wait in chains by
## the altar and wake with the fight. Whatever dies within seven cells feeds
## it: its health back, and the dead one's technique (three at most). Every
## fourth turn it announces a seal on one member's strongest essence, which then
## drops out of that member's stats, techniques and sets for three turns.
const Common = preload("res://expedition/actors/bosses/boss_common.gd")
const Abilities = preload("res://expedition/items/abilities.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const ZONE3 := ["dcss_river_rat","giant_leech","swamp_toad","temple_serpent","water_spirit","dcss_gnoll","frost_imp","gnoll_summoner"]
const BOUND := 4
const ABSORB_REACH := 7
const MAX_STOLEN := 3
const SEAL_EVERY := 4
const SEAL_TURNS := 3
const ASLEEP := 1 << 40

static func spawn(s, boss: Dictionary, room: Dictionary, depth: int) -> void:
	boss.stolen = []; boss.seal = {}; boss.woke = false
	var cells: Array = []
	for cell in s.floor_state.features:
		if str(s.floor_state.features[cell].get("kind","")) == "binding" and room.rect.has_point(cell): cells.append(cell)
	cells.sort_custom(func(a,b): return a.y < b.y or a.y == b.y and a.x < b.x)
	var pool: Array = ZONE3.duplicate()
	for i in range(mini(BOUND,cells.size())):
		var species_id: String = str(pool.pop_at(s.Hexaco.sample(s.seed_value,int(depth)*100+i,"bound_species",pool.size())))
		var row: Dictionary = s.Encounters.species(species_id)
		var roles: Array = row.get("roles",["MELEE"])
		var member := {"display_name":str(row.get("display_name",species_id)),"max_health":int(row.get("max_health",40)),
			"species_id":species_id,"role":str(roles[0]) if not roles.is_empty() else "MELEE","pos":cells[i]}
		var chained: Dictionary = s.Floor.mint_enemy(s,member,"BOSS_BOUND","boss",true)
		chained.bound_to = int(boss.id); chained.sleep_until = ASLEEP; chained.alert = false

static func wake(s, boss: Dictionary) -> void:
	if bool(boss.get("woke",false)): return
	boss.woke = true
	for enemy in s.enemies:
		if int(enemy.get("bound_to",-1)) != int(boss.id) or int(enemy.hp) <= 0: continue
		enemy.sleep_until = 0; enemy.alert = true; enemy.ready_at = int(s.time)+100
	s.message("구속의 사슬이 풀립니다")

static func turn(s, boss: Dictionary) -> void:
	for id in boss.cooldowns: boss.cooldowns[id] = maxi(0,int(boss.cooldowns[id])-1)
	expire_seals(s,boss)
	if not (boss.seal as Dictionary).is_empty():
		lay_seal(s,boss); return
	if int(boss.turns) % SEAL_EVERY == 0 and announce_seal(s,boss): return
	var foe: Dictionary = Common.target(s,boss)
	if foe.is_empty(): return
	for i in range(boss.stolen.size()-1,-1,-1):
		var id: String = str(boss.stolen[i])
		if Abilities.legal(s,boss,id,foe.pos):
			Abilities.execute(s,boss,id,foe.pos); return
	if s.melee_reach(boss.pos,foe.pos):
		Common.swing(s,boss,foe); return
	if not s.status_blocks(boss,"MOVE"): Common.step_toward(s,boss,foe)

static func absorb(s, boss: Dictionary, dead: Dictionary) -> void:
	if Common.reach(dead.pos,boss.pos) > ABSORB_REACH: return
	boss.hp = mini(int(boss.max_hp),int(boss.hp)+int(dead.get("max_hp",0)))
	var part: String = str(dead.get("part_id",""))
	if Abilities.has(part):
		boss.stolen.erase(part); boss.stolen.append(part)
		while boss.stolen.size() > MAX_STOLEN: boss.stolen.pop_front()
		boss.cooldowns[part] = 0
	s.message("%s · %s의 영혼을 흡수했습니다" % [boss.name,dead.name])

static func strongest(member: Dictionary) -> String:
	var best := ""
	var tier := 0
	for id in Essences.equipped(member):
		var at: int = Essences.tier(member,str(id))
		if at > tier: best = str(id); tier = at
	return best

## Marks the member wearing the most essences (lowest id on a tie) and that
## member's highest-tier essence (first slot on a tie).
static func announce_seal(s, boss: Dictionary) -> bool:
	var candidates: Array = s.alive().filter(func(a): return not Essences.equipped(a).is_empty())
	if candidates.is_empty(): return false
	candidates.sort_custom(func(a,b):
		var ca: int = Essences.equipped(a).size()
		var cb: int = Essences.equipped(b).size()
		return ca > cb if ca != cb else int(a.id) < int(b.id))
	var member: Dictionary = candidates[0]
	var essence: String = strongest(member)
	boss.seal = {"actor":int(member.id),"essence":essence}
	Common.announce(boss,[member.pos],0,"SEAL",1)
	s.message("%s · 영혼 봉인 예고 → %s의 %s" % [boss.name,member.name,Essences.title(essence)])
	return true

static func lay_seal(s, boss: Dictionary) -> void:
	var seal: Dictionary = boss.seal
	boss.seal = {}
	Common.clear(boss)
	var member: Dictionary = s.actor_by_id(int(seal.actor))
	var essence: String = str(seal.essence)
	if member.is_empty() or int(member.hp) <= 0 or essence not in Essences.equipped(member): return
	member.get_or_add("sealed",{})[essence] = int(boss.turns)+SEAL_TURNS
	refresh(s,member)
	s.message("%s의 %s이(가) 봉인되었습니다" % [member.name,Essences.title(essence)])

static func refresh(s, member: Dictionary) -> void:
	Essences.sync_spells(member)
	s.StatSheet.refresh_pools(s,member)

static func expire_seals(s, boss: Dictionary) -> void:
	for member in s.party:
		var sealed: Dictionary = member.get("sealed",{})
		var changed := false
		for id in sealed.keys():
			if int(sealed[id]) <= int(boss.turns): sealed.erase(id); changed = true
		if changed: refresh(s,member)

static func release(s, _boss: Dictionary) -> void:
	for member in s.party:
		if member.get("sealed",{}).is_empty(): continue
		member.sealed = {}
		refresh(s,member)
