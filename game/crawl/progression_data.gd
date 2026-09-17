extends RefCounted
## Data-only progression catalogue. Effects can be wired incrementally without changing unlock rules.

const LEVEL_REWARDS := {
	"sword": ["검술 기초","예리한 날","깊은 베기","상처 추적","반격","혈흔 감지","연속참","동맥 절단","검의 흐름","검성"],
	"spear": ["창술 기초","긴 간격","관통 찌르기","거리 유지","꿰뚫기","빈틈 포착","연속 찌르기","심부 관통","창의 흐름","창성"],
	"mace": ["둔기 기초","충격 강화","강타","균형 붕괴","분쇄","골절 압박","진동타","갑주 파쇄","충격 축적","분쇄자"],
	"axe": ["도끼술 기초","중절단","내려찍기","절단 가속","휩쓸기","상처 확대","처형도끼","사지 절단","광폭 절단","도끼달인"],
	"bow": ["궁술 기초","조준","관통사격","거리 감각","속사","약점 조준","다중사격","심장 관통","사수의 호흡","명궁"],
	"fire": ["화염학파 기초","열 축적","화염탄","연소 지속","화염 폭발","고열","화염 장벽","연소 전파","백열","화염 지배"],
	"ice": ["냉기학파 기초","한기 축적","서리창","둔화 강화","빙결","취성","빙벽","냉기 전파","절대영도","냉기 지배"],
	"air": ["기류학파 기초","전하 축적","번개","전도 강화","돌풍","연쇄 방전","폭풍장","과전압","폭풍의 눈","기류 지배"],
	"hex": ["변이학파 기초","약화 침투","속박","상태 연장","왜곡","취약화","변이 파동","상태 전염","지배","변이 지배"],
	"summon": ["소환학파 기초","결속","하급 소환","지속 강화","희생 명령","군집","상급 소환","공명","군단","소환 지배"]
}

# Direction matters for weapon/magic pairs: main 5 + sub 3 unlocks tier I,
# main 8 + sub 6 unlocks tier II. Magic/magic entries are symmetric.
const FUSIONS := [
	{"id":"sword_fire","main":"sword","sub":"fire","name":"화염검","tier2":"작열참","kind":"modifier"},
	{"id":"fire_sword","main":"fire","sub":"sword","name":"화염검무","tier2":"불꽃검진","kind":"active"},
	{"id":"sword_ice","main":"sword","sub":"ice","name":"빙결검","tier2":"동결참","kind":"modifier"},
	{"id":"ice_sword","main":"ice","sub":"sword","name":"서리검진","tier2":"빙검폭","kind":"active"},
	{"id":"sword_hex","main":"sword","sub":"hex","name":"저주검","tier2":"파멸각인","kind":"reaction"},
	{"id":"hex_sword","main":"hex","sub":"sword","name":"검인주박","tier2":"검진속박","kind":"active"},
	{"id":"spear_ice","main":"spear","sub":"ice","name":"빙결창","tier2":"빙하관통","kind":"modifier"},
	{"id":"ice_spear","main":"ice","sub":"spear","name":"서리창진","tier2":"빙주난무","kind":"active"},
	{"id":"spear_air","main":"spear","sub":"air","name":"뇌전창","tier2":"천뢰관통","kind":"reaction"},
	{"id":"air_spear","main":"air","sub":"spear","name":"번개창진","tier2":"낙뢰창역","kind":"active"},
	{"id":"mace_fire","main":"mace","sub":"fire","name":"용암분쇄","tier2":"화산충격","kind":"reaction"},
	{"id":"fire_mace","main":"fire","sub":"mace","name":"유성철퇴","tier2":"용암낙하","kind":"active"},
	{"id":"mace_air","main":"mace","sub":"air","name":"뇌격분쇄","tier2":"천둥파쇄","kind":"reaction"},
	{"id":"air_mace","main":"air","sub":"mace","name":"낙뢰강타","tier2":"폭뢰진","kind":"active"},
	{"id":"axe_fire","main":"axe","sub":"fire","name":"작열도끼","tier2":"화염처형","kind":"modifier"},
	{"id":"fire_axe","main":"fire","sub":"axe","name":"화염단두","tier2":"불기둥참","kind":"active"},
	{"id":"axe_summon","main":"axe","sub":"summon","name":"혈육사역","tier2":"시체군단","kind":"reaction"},
	{"id":"summon_axe","main":"summon","sub":"axe","name":"도끼사역마","tier2":"처형군세","kind":"modifier"},
	{"id":"bow_fire","main":"bow","sub":"fire","name":"폭발화살","tier2":"유성사격","kind":"modifier"},
	{"id":"fire_bow","main":"fire","sub":"bow","name":"화염유도탄","tier2":"불비","kind":"active"},
	{"id":"bow_ice","main":"bow","sub":"ice","name":"빙결화살","tier2":"빙우","kind":"modifier"},
	{"id":"ice_bow","main":"ice","sub":"bow","name":"서리유도탄","tier2":"빙설사격","kind":"active"},
	{"id":"bow_hex","main":"bow","sub":"hex","name":"속박사격","tier2":"주박연사","kind":"reaction"},
	{"id":"hex_bow","main":"hex","sub":"bow","name":"저주화살비","tier2":"속박영역","kind":"active"},
	{"id":"fire_air","main":"fire","sub":"air","name":"화염폭풍","tier2":"초열폭풍","kind":"active","symmetric":true},
	{"id":"fire_summon","main":"fire","sub":"summon","name":"화염정령","tier2":"화염군주","kind":"modifier","symmetric":true},
	{"id":"ice_air","main":"ice","sub":"air","name":"눈보라","tier2":"백색폭풍","kind":"active","symmetric":true},
	{"id":"ice_summon","main":"ice","sub":"summon","name":"서리정령","tier2":"빙하정령","kind":"modifier","symmetric":true},
	{"id":"air_summon","main":"air","sub":"summon","name":"폭풍정령","tier2":"폭풍군주","kind":"modifier","symmetric":true},
	{"id":"hex_summon","main":"hex","sub":"summon","name":"변이소환","tier2":"이형군단","kind":"modifier","symmetric":true}
]

static func rewards_for(skill:String,level:int)->Array:
	var result:Array=[]
	var rows:Array=LEVEL_REWARDS.get(skill,[])
	for i in range(mini(level,rows.size())):
		result.append({"level":i+1,"name":rows[i],"type":"active" if i in [2,4,6] else ("mastery" if i==9 else "passive")})
	return result

static func unlocked_fusions(skills:Dictionary)->Array:
	var result:Array=[]
	for fusion in FUSIONS:
		var main_rank:=rank_for(skills,str(fusion.main))
		var sub_rank:=rank_for(skills,str(fusion.sub))
		var tier:=0
		if bool(fusion.get("symmetric",false)):
			var hi=maxi(main_rank,sub_rank);var lo=mini(main_rank,sub_rank)
			if hi>=8 and lo>=6:tier=2
			elif hi>=5 and lo>=3:tier=1
		else:
			if main_rank>=8 and sub_rank>=6:tier=2
			elif main_rank>=5 and sub_rank>=3:tier=1
		if tier>0:
			var row:Dictionary=fusion.duplicate()
			row["tier"]=tier
			row["display_name"]=fusion.tier2 if tier==2 else fusion.name
			result.append(row)
	return result

static func rank_for(skills:Dictionary,id:String)->int:
	return mini(10,int(sqrt(float(skills.get(id,0))/25.0)))
