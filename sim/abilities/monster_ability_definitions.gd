extends RefCounted

## Runtime contracts, not acquisition metadata. Times use the field clock (100 ~= one move).
const SKILLS:={
	"PREDATOR_NERVE":{"name":"약점 일격","cost":3,"range":1,"target":"ENEMY","effect":"EXECUTE","power":24,"element":"PHYSICAL","axis":"MELEE","passive":"다친 적에게 근접 적중 시 추가 피해 6"},
	"THROWING_INSTINCT":{"name":"돌 파편","cost":2,"range":5,"target":"ENEMY","effect":"DAMAGE","power":18,"element":"PHYSICAL","axis":"RANGED","passive":"원거리 적중 시 추가 피해 4 · 원거리 명중 +15%p"},
	"HUNTER_LEAP":{"name":"도약 공격","cost":3,"range":3,"target":"ENEMY","effect":"LEAP","power":20,"element":"PHYSICAL","axis":"MELEE","passive":"이동 후 150시간 안에 첫 근접 적중 시 추가 피해 8"},
	"HIDE_PLATING":{"name":"피부 경화","cost":3,"range":1,"target":"SELF","effect":"HIDE","power":8,"element":"NONE","axis":"DEFENSE","passive":"방어 +4 · 신체 손상을 줄이는 장갑으로 적용"},
	"CARAPACE":{"name":"갑각 방어","cost":3,"range":1,"target":"SELF","effect":"SHELL","power":12,"element":"NONE","axis":"DEFENSE","passive":"방어 +3 · 관통 공격에 방어 +5 추가"},
	"CAUSTIC_BLOOD":{"name":"산성 투사체","cost":2,"range":4,"target":"ENEMY","effect":"ACID","power":24,"element":"PHYSICAL","axis":"MAGIC","passive":"인접 적에게 피격 시 산성 반격 피해 5"},
	"ECHO_SENSE":{"name":"반향 탐지","cost":2,"range":1,"target":"SELF","effect":"ECHO","power":6,"element":"NONE","axis":"MAGIC","passive":"3칸 이내 보이지 않는 생명체의 위치만 감지"},
	"FROST_SILK":{"name":"서리실 지대","cost":3,"range":4,"target":"ENEMY","effect":"FROST","power":300,"element":"ICE","axis":"MAGIC","passive":"적중한 적의 다음 이동 100시간 지연"},
	"CHARGE_ORGAN":{"name":"전하 방출","cost":3,"range":1,"target":"SELF","effect":"DISCHARGE","power":12,"element":"ELECTRIC","axis":"MAGIC","passive":"피격 시 전하 최대 3 축적 · 3회째 주변 자동 방전"},
	"VENOM_FANG":{"name":"맹독 주입","cost":3,"range":1,"target":"ENEMY","effect":"POISON","power":3,"element":"PHYSICAL","axis":"MELEE","passive":"근접 적중 시 독 +1중첩 · 최대 3중첩, 300시간"},
	"REGENERATIVE_TISSUE":{"name":"급속 재생","cost":3,"range":1,"target":"SELF","effect":"REGENERATE","power":24,"element":"NONE","axis":"MAGIC","passive":"주변 6칸에 적이 없을 때 100시간마다 HP 2 회복"},
	"STONE_SKELETON":{"name":"암석 자세","cost":3,"range":1,"target":"SELF","effect":"STONE","power":10,"element":"NONE","axis":"DEFENSE","passive":"충격 공격에 방어 +6 · 밀려남 저항"},
	"SHADOW_VEIL":{"name":"그림자 은폐","cost":3,"range":1,"target":"SELF","effect":"VEIL","power":300,"element":"NONE","axis":"DEFENSE","passive":"직접 광원 밖에서 적 시각 인지 범위 2칸으로 제한"},
	"BLOOD_SIPHON":{"name":"흡혈","cost":3,"range":1,"target":"ENEMY","effect":"SIPHON","power":18,"element":"PHYSICAL","axis":"MELEE","passive":"근접 적중 시 가한 피해의 25% 회복 · 최소 1, 최대 5"},
	"DEEP_EYE":{"name":"심층 집중","cost":2,"range":1,"target":"SELF","effect":"DEEP","power":6,"element":"NONE","axis":"MAGIC","passive":"3칸 이내 위험 타일과 숨은 생명체 위치 감지"},
}

static func has(id:String)->bool:return id=="FIREBOLT" or SKILLS.has(id)
static func definition(id:String)->Dictionary:return SKILLS.get(id,{}).duplicate(true)
