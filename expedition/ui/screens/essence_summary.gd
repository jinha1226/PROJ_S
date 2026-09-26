extends RefCounted
## Display-only summaries of real passive effects. Exact conditions stay in details.
const Essences = preload("res://expedition/progression/essences.gd")
const Effects = preload("res://expedition/progression/stone_effects.gd")
const StatSheet = preload("res://expedition/progression/stat_sheet.gd")
const TEXT := {
	"RAT_GNAW":"인접 아군당 공격 +10%",
	"LIZARD_TAIL":"근접 피격 시 25% 반격",
	"KOBOLD_SLING":"원거리 피해 +25%",
	"GOBLIN_SHIV":"체력 가득한 적에게 첫 피해 ×2",
	"GOBLIN_AIM":"원거리 사거리 +2",
	"SHIELD_STANCE":"막기 확률 +20",
	"HOB_TAUNT":"최대 HP +20%",
	"GOBLIN_HEXER":"거는 상태이상 지속 +50%",
	"ORC_CLEAVER":"공격 +20% · 받는 피해 +10%",
	"ORC_THROW":"원거리 공격 20% 추가 사격",
	"SPIDER_WEB":"공격 시 25% 속박",
	"BEETLE_CURL":"받는 피해 −15%",
	"ORE_SLAM":"공격 시 20% 기절",
	"FIRE_CALLER":"화염 피해 +30% · 공격 시 15% 화상",
	"STORM_BAT":"행동 속도 +20%",
	"RIVER_RAT_SPLASH":"젖은 칸에서 피해 +25%",
	"LEECH_LATCH":"같은 적 연속 공격 시 피해 누적 증가",
	"TOAD_SPIT":"공격 시 30% 중독",
	"SERPENT_SHED":"상태이상 50% 차단",
	"WATER_WAVE":"매 라운드 자신·인접 아군 HP 3% 회복",
	"GNOLL_SPEAR":"HP 절반 이하에서 공격 +35%",
	"FROST_IMP":"냉기 피해 +30% · 공격 시 10% 빙결",
	"GNOLL_SUMMONER":"소환수 +1 · 소환수 피해 +50%",
	"SKELETON_WALL":"인접 아군 받는 피해 −10%",
	"SKELETON_VOLLEY":"치명타 확률 +15% · 피해 +50%",
	"GHOUL_CLAW":"처치 시 HP 15% 회복",
	"VAMPIRE_BITE":"준 피해 15% 흡혈",
	"THORN_ARMOUR":"받은 근접 피해 30% 반사",
	"WRAITH":"공격 시 약화 · 처치 시 주변 혼란",
	"GRAVEKEEPER":"전투당 한 번 HP 30%로 부활",
	"RAT_INCISOR":"베기·찌르기 출혈 확률 +10%p",
	"RAT_HEART":"동료 처치 후 다음 공격 +20%",
	"LIZARD_FRILL":"피격으로 분노 축적 · 공격 시 소모",
	"LIZARD_EYE":"회피 후 다음 공격 치명타 +30",
	"KOBOLD_HIDE":"인접 적 없을 때 회피 +10",
	"KOBOLD_HEART":"제자리 조준으로 원거리 피해 증가",
	"GOBLIN_EAR":"전투 첫 공격 확정 치명타",
	"GOBLIN_TOOTH":"상태이상 부여 시 적 방어 감소",
	"ARCHER_KNUCKLE":"원거리 명중 시 20% 뒤의 적 관통",
	"ARCHER_EYE":"4칸 이상 거리에서 피해 +20%",
	"SHIELD_HIDE":"막기 시 반격",
	"SHIELD_HEART":"막기 시 공격자 골절 판정",
	"HOB_HIDE":"공격마다 HP 2% 소모 · 공격 +30%",
	"HOB_JAW":"타격 골절 확률 +10%p",
	"HEXER_HAND":"적 상태이상당 피해 +8%",
	"HEXER_SKULL":"저주 주문 의지 판정 −20",
	"ORC_HIDE":"출혈 재적용 시 틱 3회 즉시 피해",
	"ORC_HEART":"HP 30% 이하에서 받는 피해 −25%",
	"THROWER_SHOULDER":"타격 명중 시 15% 밀침 · 충돌 피해",
	"THROWER_EYE":"원거리 명중 시 20% 표식",
	"SPIDER_LEG":"치명타 후 다음 행동 지연 −30%",
	"SPIDER_SHELL":"상태이상 3개 이상인 적에게 피해 +30%",
	"BEETLE_WING":"라운드 시작 인접 적당 방어 +2",
	"BEETLE_CORE":"피격 시 방어 축적 · 최대 +8",
	"GOLEM_VEIN":"타격으로 적 방어 무시",
	"GOLEM_CORE":"기절·빙결·골절된 적에게 피해 +30%",
	"FIRECALLER_HAND":"화상 적에게 피해 +20%",
	"FIRECALLER_BONE":"원소 반응 시 MP +2",
	"BAT_BONE":"전기 피해 +30% · 젖은 적 감전 시 기절",
	"BAT_EAR":"이동한 라운드 회피 +15",
	"RIVER_RAT_TOOTH":"출혈 부여 시 적 방어 −2",
	"RIVER_RAT_HEART":"피격 없는 라운드 MP +1",
	"LEECH_SEGMENT":"출혈 틱 피해 +2",
	"LEECH_SUCKER":"출혈 적에게 준 피해 10% 흡혈",
	"TOAD_TONGUE":"중독 재적용 시 틱 피해 증가",
	"TOAD_BONE":"중독 적에게 받는 피해 −15%",
	"SERPENT_SCALE":"독 저항 +50 · 중독 면역",
	"SERPENT_FANG":"중독 적에게 피해 +15%",
	"SPIRIT_CURRENT":"젖은 칸에서 받는 피해 −15%",
	"SPIRIT_DROP":"회복한 대상 방어 +3",
	"GNOLL_HIDE":"잃은 HP에 비례해 행동 속도 증가",
	"GNOLL_BONE":"외부 회복 불가 · 매 라운드 HP 4% 재생",
	"FROST_CLAW":"빙결 적 처치 시 주변 빙결",
	"FROST_HORN":"거는 화상·빙결 지속 +50%",
	"SUMMONER_HIDE":"소환수 둘이 같은 적 공격 시 피해 +15%",
	"SUMMONER_BONE":"소환수 HP +50%",
	"SKELETON_ARM":"출혈 지속 +50%",
	"SKELETON_SKULL":"처치 시 20% 해골 소환",
	"BOWMAN_FINGER":"골절 적에게 피해 +20%",
	"BOWMAN_SOCKET":"원거리 공격 시 10% 골절",
	"GHOUL_JAW":"처치한 적이 다음 라운드 폭발",
	"GHOUL_HEART":"상태이상 적 처치 시 HP 5% 회복",
	"VAMPIRE_WING":"이동 후 첫 공격 피해 +20%",
	"VAMPIRE_HEART":"초과 흡혈이 보호로 전환",
	"WRAITH_KNIGHT_CLOAK":"근접 피격 시 20% 공격자 약화",
	"WRAITH_KNIGHT_CORE":"골절 부여 시 20% 기절",
	"WRAITH_SHROUD":"상태이상 적 처치 시 주변에 전염",
	"WRAITH_BONE":"상태이상 부여 시 HP 2 회복",
	"GRAVEKEEPER_HAND":"소환수 처치 시 내 HP 5% 회복",
	"GRAVEKEEPER_BONE":"소환수 사망 시 주변 폭발"
}

## Sum fixed bonuses, not conditional damage or healing, which are not additive.
static func stats(actor: Dictionary) -> String:
	var totals := {}
	for id in Essences.equipped(actor):
		for key in Essences.stats(str(id)):
			totals[key] = int(totals.get(key,0))+int(Essences.stats(str(id))[key])
	var lines: Array = []
	for key in StatSheet.KEYS:
		if int(totals.get(key,0)) != 0:
			lines.append("%s %+d%s" % [StatSheet.NAMES[key],int(totals[key]),"%" if key in ["speed","dodge"] or str(key).begins_with("res_") else ""])
	return " · ".join(lines)

## One short fragment per distinct active passive; variants do not stack a passive.
static func passives(actor: Dictionary) -> String:
	var seen: Array = []; var lines: Array = []
	for id in Essences.equipped(actor):
		var effect: String = Effects.effect_of(str(id))
		if effect.is_empty() or effect in seen: continue
		seen.append(effect)
		lines.append(str(TEXT.get(effect,Effects.EFFECTS.get(effect,{}).get("text",""))))
	return "\n".join(lines)
