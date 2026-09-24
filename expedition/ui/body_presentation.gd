extends RefCounted
## Read-only presentation: never changes tissues, wounds, blood or simulation rules.
static func part_state(part: Dictionary) -> String:
	if part.condition == "SEVERED": return "절단"
	if part.condition == "DISABLED": return "사용 불가"
	for layer in part.layers:
		if int(layer.integrity) < 1000: return "상처"
	return "정상"

static func color(part: Dictionary) -> Color:
	match part_state(part):
		"정상": return Color("78917c")
		"상처": return Color("c6a34c")
		_: return Color("c36560")

static func summary(actor: Dictionary) -> String:
	if actor.hp <= 0: return "사망"
	if actor.blood < 30: return "위험 · 혈액 부족"
	if actor.body.parts.any(func(p): return p.condition != "FUNCTIONAL"): return "중상 · 부위 손상"
	if actor.body.parts.any(func(p): return part_state(p) != "정상") or actor.blood < 60: return "부상 · 회복 필요"
	return "건강 · 부위 이상 없음"

static func detail(part: Dictionary) -> String:
	match part_state(part):
		"절단": return "절단 · 물약 회복 불가"
		"사용 불가": return "기능 상실 · HP 회복과 별개"
		"상처": return "상처 · 기능 유지"
	return "정상"
