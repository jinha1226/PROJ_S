extends RefCounted
## Consumable catalogue. Legacy recovery scrolls remain loadable, but no longer drop.
const SPECS={
	"POTION_MYSTERY_HEAL":{"name":"활력 물약","effect":"HEAL","power":40,"text":"HP +40","negative":false},
	"POTION_MYSTERY_MANA":{"name":"마력 물약","effect":"ENERGY","power":6,"text":"MP +6","negative":false},
	"POTION_MYSTERY_HASTE":{"name":"가속 물약","effect":"HASTE","power":1,"text":"행동 속도 +50% · 6턴","negative":false},
	"POTION_MYSTERY_ARMOR":{"name":"경화 물약","effect":"ARMOR","power":1,"text":"방어 +5 · 6턴","negative":false},
	"POTION_MYSTERY_REGEN":{"name":"재생 물약","effect":"REGEN","power":1,"text":"매 턴 HP +6 · 5턴","negative":false},
	"POTION_MYSTERY_CLEANSE":{"name":"정화 물약","effect":"CLEANSE","power":1,"text":"독·둔화·쇠약·혼란 해제","negative":false},
	"POTION_MYSTERY_POISON":{"name":"독 물약","effect":"POISON","power":1,"text":"매 턴 피해 4 · 4턴","negative":true},
	"POTION_MYSTERY_SLOW":{"name":"둔화 물약","effect":"SLOW","power":1,"text":"행동 속도 -35% · 5턴","negative":true},
	"POTION_MYSTERY_WEAK":{"name":"쇠약 물약","effect":"WEAK","power":1,"text":"명중 -20%p · 방어 -3 · 5턴","negative":true},
	"SCROLL_MYSTERY_BLINK":{"name":"점멸의 두루마리","effect":"BLINK","power":1,"text":"시야 내 5칸의 빈칸으로 이동","negative":false},
	"SCROLL_MYSTERY_PUSH":{"name":"충격파의 두루마리","effect":"PUSH","power":1,"text":"주변 2칸의 적을 2칸 밀침","negative":false},
	"SCROLL_MYSTERY_FEAR":{"name":"공포의 두루마리","effect":"FEAR","power":1,"text":"주변 4칸의 적이 도망감 · 4턴","negative":false},
	"SCROLL_MYSTERY_SEAL":{"name":"봉인의 두루마리","effect":"SEAL","power":1,"text":"적 스킬·출혈 부가효과 봉인 · 5턴","negative":false},
	"SCROLL_MYSTERY_MAP":{"name":"지도의 두루마리","effect":"MAP","power":1,"text":"주변 10칸 지형을 기억으로 공개","negative":false},
	"SCROLL_MYSTERY_IDENTIFY":{"name":"감정의 두루마리","effect":"IDENTIFY","power":1,"text":"선택한 미감정 종류 감정","negative":false},
	"SCROLL_MYSTERY_NOISE":{"name":"소란의 두루마리","effect":"NOISE","power":1,"text":"주변 10칸 적을 현재 위치로 유인","negative":true},
	"SCROLL_MYSTERY_CONFUSION":{"name":"혼란의 두루마리","effect":"CONFUSION","power":1,"text":"명중 -25%p · 스킬 사용 불가 · 4턴","negative":true},
	"SCROLL_MYSTERY_TELEPORT":{"name":"불안정 전이의 두루마리","effect":"TELEPORT","power":1,"text":"5칸 내 안전한 빈칸으로 무작위 이동","negative":true},
	"SCROLL_MYSTERY_HEAL":{"name":"치유의 두루마리","effect":"HEAL","power":50,"text":"HP +50","negative":false},
	"SCROLL_MYSTERY_MANA":{"name":"마력 회복의 두루마리","effect":"ENERGY","power":10,"text":"MP +10","negative":false}
}
const DROP_IDS=["POTION_MYSTERY_HEAL","POTION_MYSTERY_MANA","POTION_MYSTERY_HASTE","POTION_MYSTERY_ARMOR","POTION_MYSTERY_REGEN","POTION_MYSTERY_CLEANSE","POTION_MYSTERY_POISON","POTION_MYSTERY_SLOW","POTION_MYSTERY_WEAK","SCROLL_MYSTERY_BLINK","SCROLL_MYSTERY_PUSH","SCROLL_MYSTERY_FEAR","SCROLL_MYSTERY_SEAL","SCROLL_MYSTERY_MAP","SCROLL_MYSTERY_IDENTIFY","SCROLL_MYSTERY_NOISE","SCROLL_MYSTERY_CONFUSION","SCROLL_MYSTERY_TELEPORT"]
static func definition(id:String)->Dictionary:return SPECS.get(id,{}).duplicate()
