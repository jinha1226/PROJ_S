extends RefCounted
## Parts catalog. One definition is both a monster's signature attack and the
## item the player equips: `passive` applies while equipped (or always, for the
## owning species), the active is executed by `resolve` for either side.
const Essences = preload("res://expedition/progression/essences.gd")
const Hunt = preload("res://expedition/progression/hunt.gd")
const Forms = preload("res://expedition/combat/forms.gd")
const DROP_PERCENT := 50
const NO_PASSIVE := {}
const IMMEDIATE := {"prep":0,"target":"NEAREST"}
const DEFINITIONS = {
	"PUSH":{"name":"밀치기","item":"밀치기 요령","description":"인접한 적을 한 칸 밀어냅니다. 밀 곳이 없으면 피해 8. 적의 예고 공격을 취소합니다.","target":"ENEMY","range":1,"radius":0,"damage":8,"cooldown":0,"effect":"PUSH","axis":"MELEE","rule_when":"CHARGING","short":"밀치기","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"GUARD":{"name":"엄호","item":"엄호 요령","description":"인접 아군이 받을 피해를 대신 받고 절반만 입습니다.","target":"ALLY","range":1,"radius":0,"damage":0,"cooldown":0,"effect":"GUARD","axis":"","rule_when":"ALLY_LETHAL","short":"엄호","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"SHOCKWAVE":{"name":"수렁 충격파","item":"수렁의 핵","description":"범위 2 · 피해 16 · 아군 피해 · 재사용 3턴","target":"SELF","range":0,"radius":2,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"충격파","shape":"CIRCLE","self_hit":false,"icon":4,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":true,"tile_wet":0},
	"BOMB":{"name":"폭탄 투척","item":"암살자의 화약낭","description":"사거리 4 · 범위 1 · 피해 16 · 아군 피해 · 재사용 3턴","target":"ENEMY","range":4,"radius":1,"damage":16,"cooldown":3,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"폭탄","shape":"SQUARE","self_hit":true,"icon":3,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":true,"tile_wet":0},
	"IRON_HIDE":{"name":"철갑 방어","item":"거인의 철갑핵","description":"받는 피해 -75% · 1턴 · 재사용 3턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":3,"effect":"SHIELD","axis":"","rule_when":"DANGER","short":"철갑","shape":"SQUARE","self_hit":false,"icon":5,"species":"","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"RAT_GNAW":{"name":"물어뜯기","item":"쥐 이빨","description":"물어뜯기: 인접 대상 피해 9 · 재사용 2턴","target":"ENEMY","range":1,"radius":0,"damage":9,"cooldown":2,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"물기","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_rat","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"LIZARD_TAIL":{"name":"꼬리치기","item":"도마뱀 꼬리","description":"꼬리치기: 대상 주위 3×3 피해 6 · 재사용 3턴","target":"ENEMY","range":1,"radius":1,"damage":6,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"꼬리","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_frilled_lizard","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"KOBOLD_SLING":{"name":"투석","item":"코볼트 투석끈","description":"투석: 사거리 4 피해 7 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":7,"cooldown":2,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"투석","shape":"SQUARE","self_hit":false,"icon":5,"species":"kobold","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"GOBLIN_SHIV":{"name":"기습","item":"고블린 단검","description":"기습: 사거리 3 이동 후 피해 10 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":10,"cooldown":3,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS","short":"기습","shape":"SQUARE","self_hit":false,"icon":5,"species":"goblin","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"HOB_TAUNT":{"name":"도발","item":"홉고블린 뿔피리","description":"도발: 반경 3의 적이 2라운드 동안 나만 노림(보스는 1라운드) · 재사용 4턴","target":"SELF","range":0,"radius":3,"damage":0,"cooldown":4,"effect":"TAUNT","status_ticks":200,"axis":"","rule_when":"DANGER","short":"도발","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_hobgoblin","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0,"player_only":true},
	"GOBLIN_AIM":{"name":"조준 사격","item":"고블린 궁수의 깃","description":"조준 사격: 사거리 6 피해 16 · 조준에 시간이 더 걸림 · 재사용 4턴","target":"ENEMY","range":6,"radius":0,"damage":16,"cooldown":4,"delay":150,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"조준","shape":"SQUARE","self_hit":false,"icon":3,"species":"goblin_archer","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"SHIELD_STANCE":{"name":"방패 자세","item":"고블린 방패병의 방패","description":"방패 자세: 2라운드 동안 막기 +40 · 이동 불가 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":4,"effect":"STANCE","status":"shield_stance","status_ticks":200,"axis":"","rule_when":"DANGER","short":"방패","shape":"SQUARE","self_hit":false,"icon":5,"species":"goblin_shield","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"ORC_THROW":{"name":"도끼 투척","item":"오크 투척 도끼","description":"도끼 투척: 사거리 3 피해 12 · 대상 한 칸 밀림 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":12,"cooldown":3,"push":1,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"투척","shape":"SQUARE","self_hit":false,"icon":3,"species":"orc_thrower","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"SPIDER_WEB":{"name":"거미줄","item":"동굴 거미 실샘","description":"거미줄: 사거리 3 · 속박 2라운드 · 재사용 4턴","target":"ENEMY","range":3,"radius":0,"damage":0,"cooldown":4,"status":"bind","status_ticks":200,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"거미줄","shape":"SQUARE","self_hit":false,"icon":3,"species":"cave_spider","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"BEETLE_CURL":{"name":"몸 말기","item":"바위 딱정벌레 등껍질","description":"몸 말기: 1라운드 동안 받는 피해 −75% · 재사용 3턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":3,"effect":"SHIELD","axis":"","rule_when":"DANGER","short":"몸말기","shape":"SQUARE","self_hit":false,"icon":5,"species":"rock_beetle","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"ORE_SLAM":{"name":"내려찍기","item":"광석 골렘 핵","description":"내려찍기: 인접 대상 피해 14 · 1라운드 둔화 · 재사용 3턴","target":"ENEMY","range":1,"radius":0,"damage":14,"cooldown":3,"status":"slow","status_ticks":100,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"찍기","shape":"SQUARE","self_hit":false,"icon":5,"species":"ore_golem","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"LEECH_LATCH":{"name":"달라붙기","item":"거대 거머리 빨판","description":"달라붙기: 인접 대상 피해 8 · 준 피해만큼 회복 · 재사용 2턴","target":"ENEMY","range":1,"radius":0,"damage":8,"cooldown":2,"drain":100,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"흡착","shape":"SQUARE","self_hit":false,"icon":5,"species":"giant_leech","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"TOAD_SPIT":{"name":"독침","item":"늪 두꺼비 독샘","description":"독침: 사거리 4 피해 6 · 중독 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":6,"cooldown":2,"status":"poison","status_ticks":300,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"독침","shape":"SQUARE","self_hit":false,"icon":3,"species":"swamp_toad","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"SERPENT_SHED":{"name":"허물 벗기","item":"신전 뱀 허물","description":"허물 벗기: 상태이상을 모두 풀고 1라운드 면역 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":4,"effect":"CLEANSE","status_ticks":100,"axis":"","rule_when":"HP","short":"허물","shape":"SQUARE","self_hit":false,"icon":5,"species":"temple_serpent","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"WATER_WAVE":{"name":"해일","item":"물의 정령 물방울","description":"해일: 사거리 3 · 3×3 피해 6 · 칸을 적심 · 한 칸 밀림 · 아군도 휩쓸림 · 재사용 3턴","target":"ENEMY","range":3,"radius":1,"damage":6,"cooldown":3,"push":1,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"해일","shape":"SQUARE","self_hit":false,"icon":4,"species":"water_spirit","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":true,"tile_wet":100},
	"SKELETON_WALL":{"name":"방패벽","item":"해골 병사 방패","description":"방패벽: 자신과 인접 아군 방어 +3 · 2라운드 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":4,"effect":"WARD_ALLIES","status":"shield_wall","status_ticks":200,"axis":"","rule_when":"DANGER","short":"방패벽","shape":"SQUARE","self_hit":false,"icon":5,"species":"skeleton_soldier","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"SKELETON_VOLLEY":{"name":"뼈화살 연사","item":"해골 궁수 화살통","description":"뼈화살 연사: 사거리 5 · 피해 6 두 번 · 재사용 3턴","target":"ENEMY","range":5,"radius":0,"damage":6,"cooldown":3,"hits":2,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"연사","shape":"SQUARE","self_hit":false,"icon":3,"species":"skeleton_archer","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"GHOUL_CLAW":{"name":"할퀴기","item":"구울 발톱","description":"할퀴기: 인접 대상 피해 10 · 출혈 · 재사용 2턴","target":"ENEMY","range":1,"radius":0,"damage":10,"cooldown":2,"status":"bleed","status_ticks":300,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"할퀴기","shape":"SQUARE","self_hit":false,"icon":5,"species":"ghoul","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"VAMPIRE_BITE":{"name":"흡혈 물기","item":"흡혈 박쥐 송곳니","description":"흡혈 물기: 2칸 돌진 후 피해 8 · 준 피해의 절반 회복 · 재사용 3턴","target":"ENEMY","range":2,"radius":0,"damage":8,"cooldown":3,"drain":50,"effect":"LUNGE","axis":"MELEE","rule_when":"ALWAYS","short":"흡혈","shape":"SQUARE","self_hit":false,"icon":5,"species":"vampire_bat","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"THORN_ARMOUR":{"name":"가시 갑옷","item":"망령 기사 갑주","description":"가시 갑옷: 3라운드 동안 근접 공격자에게 받은 피해의 30% 반사 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":4,"effect":"THORNS","status":"thorns","status_ticks":300,"axis":"","rule_when":"DANGER","short":"가시","shape":"SQUARE","self_hit":false,"icon":5,"species":"wraith_knight","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"WRAITH":{"name":"원혼의 저주","item":"원혼의 속삭임","description":"원혼의 저주: 사거리 4 피해 5 · 약화 · 재사용 3턴","target":"ENEMY","range":4,"radius":0,"damage":5,"cooldown":3,"status":"weak","status_ticks":300,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"저주","shape":"SQUARE","self_hit":false,"icon":4,"species":"wraith","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"will","monster_only":true},
	"GRAVEKEEPER":{"name":"묘지의 부름","item":"묘지기의 등불","description":"묘지의 부름: 사거리 3 피해 8 · 둔화 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":8,"cooldown":3,"status":"slow","status_ticks":200,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"부름","shape":"SQUARE","self_hit":false,"icon":4,"species":"gravekeeper","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"will","monster_only":true},
	"ORC_CLEAVER":{"name":"휘두르기","item":"오크 도끼","description":"휘두르기: 대상 주위 3×3 피해 11 · 재사용 3턴","target":"ENEMY","range":1,"radius":1,"damage":11,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"도끼","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_orc","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"GNOLL_SPEAR":{"name":"창 찌르기","item":"놀 창","description":"창 찌르기: 사거리 2 피해 12 · 재사용 3턴","target":"ENEMY","range":2,"radius":0,"damage":12,"cooldown":3,"effect":"DAMAGE","axis":"MELEE","rule_when":"ALWAYS","short":"창","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_gnoll","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0},
	"RIVER_RAT_SPLASH":{"name":"물세례","item":"강쥐 가죽","description":"물세례: 사거리 3 · 3×3 피해 5 · 칸을 적심 · 재사용 3턴","target":"ENEMY","range":3,"radius":1,"damage":5,"cooldown":3,"effect":"DAMAGE","axis":"RANGED","rule_when":"ALWAYS","short":"물","shape":"SQUARE","self_hit":false,"icon":5,"species":"dcss_river_rat","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":70},
	"FIRE_CALLER":{"name":"화염 화살","item":"화염술사의 불씨","description":"화염 화살: 사거리 4 피해 9 · 맞은 칸에 불 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":9,"cooldown":2,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"화염","shape":"SQUARE","self_hit":false,"icon":4,"species":"kobold_firecaller","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"fire","monster_only":true},
	"FROST_IMP":{"name":"서리 숨결","item":"서리 도깨비의 뿔","description":"서리 숨결: 사거리 3 · 3×3 피해 6 · 둔화 · 재사용 3턴","target":"ENEMY","range":3,"radius":1,"damage":6,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"서리","shape":"SQUARE","self_hit":false,"icon":4,"species":"frost_imp","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"ice","monster_only":true},
	"STORM_BAT":{"name":"번개 화살","item":"폭풍 박쥐의 날개막","description":"번개 화살: 사거리 4 피해 8 · 젖은 대상 피해 +4 · 재사용 2턴","target":"ENEMY","range":4,"radius":0,"damage":8,"cooldown":2,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"번개","shape":"SQUARE","self_hit":false,"icon":4,"species":"storm_bat","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"air","monster_only":true},
	"GOBLIN_HEXER":{"name":"혼란의 저주","item":"고블린 주술 부적","description":"혼란의 저주: 사거리 4 피해 4 · 혼란 · 재사용 3턴","target":"ENEMY","range":4,"radius":0,"damage":4,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"저주","shape":"SQUARE","self_hit":false,"icon":4,"species":"goblin_hexer","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"will","monster_only":true},
	"GNOLL_SUMMONER":{"name":"영혼 채찍","item":"놀 소환사의 사슬","description":"영혼 채찍: 사거리 3 피해 10 · 혼란 · 재사용 3턴","target":"ENEMY","range":3,"radius":0,"damage":10,"cooldown":3,"effect":"DAMAGE","axis":"MAGIC","rule_when":"ALWAYS","short":"채찍","shape":"SQUARE","self_hit":false,"icon":4,"species":"gnoll_summoner","passive":NO_PASSIVE,"enemy":{"prep":1,"target":"NEAREST"},"allies_hit":false,"tile_wet":0,"element":"will","monster_only":true},
	"GOBLIN_CHIEF":{"name":"지휘","item":"족장의 뿔나팔","description":"사거리 4 · 표시한 적이 3라운드 동안 받는 피해 +20% · 재사용 4턴","target":"ENEMY","range":4,"radius":0,"damage":0,"cooldown":4,"effect":"MARK","axis":"","rule_when":"ALWAYS","short":"지휘","shape":"SQUARE","self_hit":false,"icon":5,"species":"goblin_chief","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"FURNACE_HEART":{"name":"과열 장갑","item":"용광로 심장","description":"2라운드 동안 받는 피해 -40% · 끝날 때 주변 1칸 화염 피해 12 · 재사용 4턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":4,"effect":"FURNACE","axis":"","rule_when":"DANGER","short":"과열","shape":"SQUARE","self_hit":false,"icon":5,"species":"furnace_golem","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0},
	"SOUL_EATER":{"name":"영혼 먹기","item":"포식자의 핵","description":"다음에 처치한 몬스터의 기술을 한 번 쓸 수 있음 · 재사용 5턴","target":"SELF","range":0,"radius":0,"damage":0,"cooldown":5,"effect":"DEVOUR","axis":"","rule_when":"ALWAYS","short":"먹기","shape":"SQUARE","self_hit":false,"icon":5,"species":"soul_eater","passive":NO_PASSIVE,"enemy":IMMEDIATE,"allies_hit":false,"tile_wet":0}}
## Actions that are not catalog parts.
const BASIC_BADGES := {"ATTACK":"공격","MOVE":"이동","WAIT":"대기"}
const BASIC := ["PUSH","GUARD"]

## Element variants (spec §3.7). "<BASE_ID>@<element>" is the base part with an
## element: same numbers, its element's damage and mark. Every reader of the
## catalog goes through `has` and `definition`, so a variant id works anywhere
## a base id does.
const ELEMENT_NAMES := {"fire":"화염","ice":"냉기","air":"전기","poison":"독","will":"의지","bleed":"출혈"}
const ELEMENT_FORMS := {"fire":"FIRE","ice":"ICE","air":"AIR","poison":"POISON","will":"WILL"}
const ELEMENT_NOTES := {"fire":"화염: 맞은 칸에 불이 붙음","ice":"냉기: 둔화","air":"전기: 젖은 대상에게 피해 +4","poison":"독: 중독","will":"의지: 혼란","bleed":"출혈: 출혈"}
## Damage cuts that do not stack: the largest applies (zones spec §4).
const IRON_GUARD_CUT := 75
const GUARD_CUT := 50
const THORN_PERCENT := 30
const OPPOSITE := {"fire":"ice","ice":"fire"}
static var variant_cache: Dictionary = {}

static func base_id(id: String) -> String:
	return id.get_slice("@",0).get_slice("/",0)

## Actions retain elemental variants but never a stone's /part suffix.
static func active_id(id: String) -> String:
	if id.contains("/") and not Essences.has(id): return ""
	var element := element_of(id)
	return base_id(id)+("@"+element if not element.is_empty() else "")

## Slotted stones share a species cooldown. Monsters' intrinsic variants keep
## their active ids: their turn driver and stolen techniques already use them.
static func cooldown_id(id: String, actor: Dictionary = {}) -> String:
	return active_id(id) if bool(actor.get("enemy",false)) else base_id(id)

static func cooldown(actor: Dictionary, id: String) -> int:
	var key := cooldown_id(id,actor)
	var result := 0
	for old in actor.get("cooldowns",{}):
		if cooldown_id(str(old),actor) == key: result = maxi(result,int(actor.cooldowns[old]))
	return result

static func element_of(id: String) -> String:
	var at := id.find("@")
	return "" if at < 0 else id.substr(at+1)

static func has(id: String) -> bool:
	if id.count("@") > 1 or id.count("/") > 1 or (id.contains("/") and not Essences.has(id)): return false
	var element := element_of(id)
	return DEFINITIONS.has(base_id(id)) and (ELEMENT_NAMES.has(element) if id.contains("@") else true)

## The catalog row for `id`; a variant is a copy of its base with the element.
static func definition(id: String) -> Dictionary:
	if not has(id): return {}
	id = active_id(id)
	var element := element_of(id)
	if element.is_empty(): return DEFINITIONS[id]
	if not variant_cache.has(id):
		var def: Dictionary = DEFINITIONS[base_id(id)].duplicate(true)
		def["element"] = element
		def.name = "%s %s" % [ELEMENT_NAMES[element],def.name]
		def.item = "%s %s" % [ELEMENT_NAMES[element],def.item]
		def.description = "%s · %s" % [def.description,ELEMENT_NOTES[element]]
		variant_cache[id] = def
	return variant_cache[id]

## Whether `actor` may use `id` as an action: a caster species' own attack is
## the monster's, never a party member's; a player-only part (도발) is never a
## monster's.
static func usable_by(actor: Dictionary, id: String) -> bool:
	if not has(id): return false
	if str(actor.get("borrowed","")) == id: return true
	var def: Dictionary = definition(id)
	if bool(actor.get("enemy",false)): return not bool(def.get("player_only",false))
	return not bool(def.get("monster_only",false))

## The kill key of a monster: its species, and its element for a variant.
static func kind_key(enemy: Dictionary) -> String:
	var element: String = str(enemy.get("variant_element",""))
	return str(enemy.get("species_id","")) if element.is_empty() else "%s@%s" % [enemy.get("species_id",""),element]


## Part ids that a species drops, in DEFINITIONS insertion order.
static func droppable() -> Array:
	var result: Array = []
	for id in DEFINITIONS:
		if not str(definition(id).species).is_empty(): result.append(id)
	return result

## The signature part of `species_id`, or "" when the species has none.
static func species_part(species_id: String) -> String:
	for id in DEFINITIONS:
		if str(definition(id).species) == species_id: return id
	return ""

## Short badge text for any action kind, catalog part or basic action.
static func badge(kind: String) -> String:
	return str(definition(kind).short) if has(kind) else str(BASIC_BADGES.get(kind,kind))

static func default_rule(id: String) -> Dictionary:
	id = active_id(id)
	var def: Dictionary = definition(id)
	var target: String = {"SELF":"SELF","ALLY":"ALLY"}.get(def.target,"NEAREST")
	return preload("res://expedition/ai/tactic_rules.gd").make_rule(id,target,def.rule_when)

## Nearest free cell adjacent to the target that the actor can reach within the part's range.
static func lunge_cell(s, actor: Dictionary, id: String, target: Vector2i) -> Vector2i:
	var def: Dictionary = definition(id)
	var best := Vector2i(-1,-1)
	var best_len := 1 << 30
	for d in s.DIRECTIONS:
		var cell: Vector2i = target+d
		if not s.inside(cell) or not s.is_free(cell) or not s.melee_reach(cell,target): continue
		var route: Dictionary = s.TurnCore.path(s.BOARD_SIDE,s.BOARD_SIDE,actor.pos,[cell],func(a,b): return s.can_step(a,b),func(_p): return 100)
		if not route.found: continue
		var steps: int = route.path.size()-1
		if steps > int(def.range): continue
		if steps < best_len or (steps == best_len and str(cell) < str(best)): best = cell; best_len = steps
	return best

static func cells(s, actor: Dictionary, id: String, target: Vector2i) -> Array:
	var result: Array = []
	if not has(id): return result
	var def: Dictionary = definition(id)
	var center: Vector2i = actor.pos if def.target == "SELF" else target
	for y in range(maxi(0,center.y-def.radius),mini(s.BOARD_SIDE,center.y+def.radius+1)):
		for x in range(maxi(0,center.x-def.radius),mini(s.BOARD_SIDE,center.x+def.radius+1)):
			var cell := Vector2i(x,y)
			var in_range: bool = s.distance(center,cell) <= def.radius if def.shape == "CIRCLE" else maxi(absi(center.x-x),absi(center.y-y)) <= def.radius
			if in_range and s.tile(cell).terrain != "wall" and s.TurnCore.Geometry.sees(center,cell,func(p): return s.tile(p).terrain == "wall"): result.append(cell)
	return result

## A monster hits for the listed damage. A member adds half of the reading
## attribute over ten.
static func power(s, actor: Dictionary, def: Dictionary, _id: String = "") -> int:
	if int(def.damage) <= 0: return 0
	if actor.enemy: return scaled(actor,int(def.damage))
	var key: String = {"RANGED":"dex","MAGIC":"int"}.get(str(def.axis),"str")
	return int(def.damage)+maxi(0,s.StatSheet.value(s,actor,key)-10)/2

## Whether `actor` holds the part: a slot for party members, the species signature for monsters.
static func holds(actor: Dictionary, id: String) -> bool:
	if not has(id): return false
	id = active_id(id)
	if actor.enemy: return active_id(str(actor.get("part_id",""))) == id or id in actor.get("stolen",[])
	if str(actor.get("borrowed","")) == id: return true
	if id in BASIC: return true
	return id in held(actor) and usable_by(actor,id)

static func held(actor: Dictionary) -> Array:
	var result: Array = []; var species: Array = []
	var stones: Array = Essences.equipped(actor)
	# Legacy action fixtures (PUSH, GUARD, IRON_HIDE, BOMB) do not own stones.
	for raw in actor.get("equipped_abilities",[]):
		if has(str(raw)) and str(definition(str(raw)).get("species","")).is_empty() and not actor.get("sealed",{}).has(str(raw)): stones.append(str(raw))
	for stone in stones:
		if not has(str(stone)): continue
		var id := active_id(str(stone)); var base := base_id(id)
		if base in species: continue
		species.append(base); result.append(id)
	var borrowed: String = str(actor.get("borrowed",""))
	if not borrowed.is_empty() and borrowed not in result: result.append(borrowed)
	return result

static func legal(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not has(id) or not usable_by(actor,id) or not holds(actor,id) or cooldown(actor,id) > 0: return false
	if s.phase != "BATTLE" or actor.hp <= 0 or not s.inside(target): return false
	if not actor.enemy and actor.ap <= 0: return false
	var def: Dictionary = definition(id)
	if def.target == "SELF":
		if def.effect == "HEAL" and actor.hp >= actor.max_hp: return false
		return target == actor.pos
	var victim: Dictionary = s.at(target)
	if victim.is_empty() or victim.hp <= 0: return false
	if actor.enemy and victim == s.party[0] and not s.floor_state.visible.has(actor.pos): return false
	if def.target == "ALLY":
		return victim.enemy == actor.enemy and victim.id != actor.id and s.melee_reach(actor.pos,target)
	if victim.enemy == actor.enemy: return false
	# distance() is Manhattan, so a range-1 skill would miss the diagonals a
	# basic attack reaches; "adjacent" means melee_reach everywhere else.
	var in_range: bool = s.melee_reach(actor.pos,target) if int(def.range) == 1 else s.distance(actor.pos,target) <= int(def.range)
	if not in_range or (int(def.range) > 1 and not s.TurnCore.Geometry.sees(actor.pos,target,func(p): return s.tile(p).terrain == "wall")): return false
	if def.effect == "LUNGE": return lunge_cell(s,actor,id,target) != Vector2i(-1,-1)
	return true

static func execute(s, actor: Dictionary, id: String, target: Vector2i) -> bool:
	if not legal(s,actor,id,target): return false
	id = active_id(id)
	# Ranged and magical parts train only when they affect a hostile target.
	# Record before resolving damage so a killing blow receives its XP share.
	if not actor.enemy:
		var affected: Array = cells(s,actor,id,target)
		for foe in s.enemies:
			if foe.hp > 0 and foe.pos in affected: Hunt.record(actor,int(foe.id))
	resolve(s,actor,id,target)
	return true

## Resolves the part on `target` without a legality check: a telegraphed
## monster part lands on the announced cell whoever stands there now.
static func resolve(s, actor: Dictionary, id: String, target: Vector2i) -> void:
	id = active_id(id)
	if Forms.attack_action(s,id): actor["physical_blow"] = true
	var def: Dictionary = definition(id)
	var victim: Dictionary = s.at(target)
	# The use is logged first so that a miss is the last line the log shows.
	if def.effect not in ["GUARD","PUSH"]: s.message(actor.name+" · "+def.name)
	match def.effect:
		"MARK":
			if victim.is_empty(): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else: victim.statuses["marked"] = int(s.time)+300
		"FURNACE": actor.statuses["furnace"] = int(s.time)+200
		"DEVOUR": actor.devour_ready = true
		"SHIELD": actor.iron_guard = true
		"STANCE", "THORNS":
			actor.statuses[str(def.status)] = s.time+int(def.status_ticks)
		"CLEANSE":
			for status in actor.statuses.keys():
				if status in s.Statuses.HARMFUL:
					actor.statuses.erase(status); actor.get("status_power",{}).erase(status)
			actor.statuses["immune"] = s.time+int(def.status_ticks)
		"WARD_ALLIES":
			for other in s.party+s.npcs+s.enemies:
				if other.hp > 0 and s.side_of(other) == s.side_of(actor) and (other.id == actor.id or s.melee_reach(actor.pos,other.pos)):
					other.statuses[str(def.status)] = s.time+int(def.status_ticks)
		"TAUNT":
			var taunted := 0
			for other in s.party+s.npcs+s.enemies:
				if other.hp <= 0 or s.side_of(other) == s.side_of(actor) or s.distance(actor.pos,other.pos) > int(def.radius): continue
				if other.get("statuses",{}).has("immune"): continue
				var ticks: int = int(def.status_ticks)/(2 if other.get("boss",false) else 1)
				other.statuses["taunted"] = s.time+ticks
				other.get_or_add("status_power",{})["taunted"] = int(actor.id)
				taunted += 1
			if taunted == 0: s.message(actor.name+"의 도발에 아무도 응하지 않았습니다.")
		"HEAL":
			var before: int = int(actor.hp)
			s.StoneEffects.heal(s,actor,int(def.heal),actor)
			var row: Dictionary = s.member_stats(actor.id)
			if not row.is_empty(): row.healed += int(actor.hp)-before
		"GUARD":
			if victim.is_empty(): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else:
				actor["guarded"] = true
				victim["protected_by"] = actor.id
				var row: Dictionary = s.member_stats(actor.id)
				if not row.is_empty(): row.guards += 1
				s.message("%s · 엄호 → %s" % [actor.name,victim.name])
		"PUSH":
			if victim.is_empty(): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			elif victim.get("boss",false):
				s.damage(victim,power(s,actor,def,id),actor.id,"IMPACT")
				s.message("%s · 밀리지 않습니다" % victim.name)
			else:
				var destination: Vector2i = target+(target-actor.pos)
				if s.can_step(target,destination): victim.pos = destination
				else: s.damage(victim,power(s,actor,def,id),actor.id,"IMPACT")
				s.intents = s.intents.filter(func(intent): return intent.id != victim.id)
				s.Floor.MonsterAI.interrupt(s,victim)
				s.message("밀쳐내기 · 적의 예고 공격을 취소했습니다.")
		"LUNGE":
			var cell := lunge_cell(s,actor,id,target)
			if cell != Vector2i(-1,-1): actor.pos = cell
			# A telegraphed lunge lands on the announced cell, but never on the
			# caster's own side: a fellow monster who stepped in is a miss.
			var spared: bool = not victim.is_empty() and not def.allies_hit and victim.enemy == actor.enemy
			if victim.is_empty() or spared or cell == Vector2i(-1,-1): s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
			else:
				s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":[target],"area":false,"amount":0,"form":"SLASH","caption":str(def.get("short",def.name))})
				strike_victim(s,actor,victim,power(s,actor,def,id),"SLASH",def)
		"DAMAGE":
			var affected := cells(s,actor,id,target)
			var amount: int = power(s,actor,def,id)
			s.effects.append({"kind":"ENEMY_ATTACK","from":actor.pos,"cell":target,"cells":affected,"area":affected.size() > 1,"amount":0,"form":"IMPACT","caption":str(def.get("short",def.name))})
			var hit := 0
			for other in s.party+s.npcs+s.enemies:
				if other.hp <= 0 or other.id == actor.id or other.pos not in affected: continue
				if not def.allies_hit and other.enemy == actor.enemy: continue
				for i in range(maxi(1,int(def.get("hits",1)))):
					if other.hp > 0: strike_victim(s,actor,other,amount,"IMPACT",def)
				hit += 1
			# Bombs can also hit the caster; self-centered shockwaves cannot.
			if def.self_hit and actor.pos in affected: s.damage(actor,amount,actor.id,"IMPACT"); hit += 1
			for cell in affected:
				if int(def.tile_wet) > 0: s.tile(cell).wet = maxi(int(s.tile(cell).wet),int(def.tile_wet))
			if hit == 0 and def.target != "SELF": s.message(actor.name+"의 "+def.name+"가 빗나갔습니다.")
	if int(def.cooldown) > 0: actor.cooldowns[cooldown_id(id,actor)] = int(def.cooldown)+1
	# Who pressed what, for the battle report: the monsters' parts in one pot,
	# each member's in their own row.
	if actor.enemy: s.battle_stats.enemy_parts[id] = int(s.battle_stats.enemy_parts.get(id,0))+1
	else:
		var row: Dictionary = s.member_stats(actor.id)
		if not row.is_empty(): row.parts[id] = int(row.parts.get(id,0))+1
	if str(actor.get("borrowed","")) == id: actor.borrowed = ""

static func scaled(actor: Dictionary, amount: int) -> int:
	return amount*int(actor.get("attack_percent",100))/100

const SHOCK_BONUS := 4
const FIRE_TILE_ADD := 35
const ELEMENT_TICKS := 200

## One victim of a part: the damage (in the part's element when it has one),
## the element's mark, then what the part leaves behind. Returns the HP lost.
static func strike_victim(s, actor: Dictionary, victim: Dictionary, amount: int, form: String, def: Dictionary) -> int:
	if actor.enemy and victim == s.party[0] and not s.floor_state.visible.has(actor.pos): return 0
	var element: String = str(def.get("element",""))
	var damage_form: String = form if element in ["","bleed"] else str(ELEMENT_FORMS[element])
	if element == "air" and int(s.tile(victim.pos).wet) > 0: amount += SHOCK_BONUS
	var part_form: String = Forms.of_part(def)
	if element in ["","bleed"]: amount = Forms.scale(amount,part_form,s.protection_recipient(victim))
	var was: String = Forms.begin(s,part_form)
	var lost: int = int(s.damage(victim,amount,actor.id,damage_form))
	Forms.end(s,was)
	if not element.is_empty(): element_mark(s,victim,element)
	after_strike(s,actor,victim,lost,def)
	return lost

## What a part leaves after its hit: blood drunk, a status, a shove.
static func after_strike(s, actor: Dictionary, victim: Dictionary, lost: int, def: Dictionary) -> void:
	if int(def.get("drain",0)) > 0 and lost > 0 and int(actor.hp) > 0:
		s.StoneEffects.heal(s,actor,lost*int(def.drain)/100,actor)
	if int(victim.hp) <= 0: return
	var status: String = str(def.get("status",""))
	if not status.is_empty(): s.Statuses.apply(s,victim,status,int(def.get("status_ticks",200)))
	if int(def.get("push",0)) > 0:
		var step: Vector2i = (victim.pos-actor.pos).sign()
		var destination: Vector2i = victim.pos+step
		if step != Vector2i.ZERO and s.inside(destination) and s.can_step(victim.pos,destination) and s.at(destination).is_empty(): victim.pos = destination

## What an element leaves behind on whoever it hit.
static func element_mark(s, victim: Dictionary, element: String) -> void:
	match element:
		"fire":
			var tile: Dictionary = s.tile(victim.pos)
			if int(tile.wet) <= 0 and str(tile.terrain) != "water": tile.fire = mini(100,int(tile.fire)+FIRE_TILE_ADD)
		"ice":
			if victim.hp > 0: s.Statuses.apply(s,victim,"slow",ELEMENT_TICKS)
		"poison":
			if victim.hp > 0 and int(victim.get("res",{}).get("poison",0)) < 100: victim.statuses["poison"] = s.time+ELEMENT_TICKS+100
		"will":
			if victim.hp > 0: s.Statuses.apply(s,victim,"confuse",ELEMENT_TICKS)
		"bleed":
			if victim.hp > 0: s.Statuses.apply(s,victim,"bleed",ELEMENT_TICKS+100)

## The one damage cut that applies to `actor`: the largest of 몸 말기 (75),
## 엄호 (50) and any `damage_cut` percent a status or boss set. Cuts never add up.
static func reduction(actor: Dictionary) -> int:
	var best: int = int(actor.get("damage_cut",0))
	if bool(actor.get("iron_guard",false)): best = maxi(best,IRON_GUARD_CUT)
	if bool(actor.get("guarded",false)): best = maxi(best,GUARD_CUT)
	return clampi(maxi(best,40 if actor.get("statuses",{}).has("furnace") else 0),0,100)
