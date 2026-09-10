class_name GuildTutorialRules
extends RefCounted

## Event-derived, campaign-scoped guild tutorial progression.
const RULESET_ID := "guild-tutorial-v2"
const CAMPAIGN_ID := "GUILD_TUTORIAL_CAMPAIGN_V1"
const EVENT_ACCEPTED := "town.guild_tutorial_accepted"
const EVENT_SUPPORT_GRANTED := "town.guild_tutorial_support_granted"
const EVENT_REWARD_CLAIMED := "town.guild_tutorial_reward_claimed"

const QUEST_IDS := [
	"GUILD_TUTORIAL_MOVE", "GUILD_TUTORIAL_GUARD", "GUILD_TUTORIAL_HEAL",
	"GUILD_TUTORIAL_LOOT", "GUILD_TUTORIAL_RETURN", "GUILD_TUTORIAL_BIND",
	"GUILD_TUTORIAL_SKILL", "GUILD_TUTORIAL_UPGRADE", "GUILD_TUTORIAL_INJURY", "GUILD_TUTORIAL_TREAT"]

static func definitions() -> Array[Dictionary]:
	var result:Array[Dictionary]=[
		{"quest_id":"GUILD_TUTORIAL_MOVE","title":"첫 발걸음",
			"description":"1층에서 세 번 이동하고, 그중 한 번은 대각선으로 이동하세요.",
			"hint":"터치 이동은 실제 행동을 성공했을 때만 기록됩니다.",
			"reward_kind":"ITEM","reward_text":"식량 1개",
			"reward_rows":[{"definition_id":"FOOD_RATION","quantity":1}]},
		{"quest_id":"GUILD_TUTORIAL_GUARD","title":"서두르지 않는 싸움",
			"description":"1층에서 대기 방어를 한 번 사용하고 적에게 유효 공격을 하세요.",
			"hint":"주민을 공격해도 의뢰 진행으로 인정되지 않습니다.",
			"reward_kind":"GOLD","reward_text":"금화 20개","gold":20},
		{"quest_id":"GUILD_TUTORIAL_HEAL","title":"살아서 돌아올 준비",
			"description":"다친 뒤 자신의 회복 물약으로 실제 체력을 회복하세요.",
			"hint":"물약이 없으면 훈련용 지원을 한 번 받을 수 있습니다.",
			"reward_kind":"ITEM","reward_text":"회복 물약 1개 보충",
			"reward_rows":[{"definition_id":"POTION_HEALING","quantity":1}]},
		{"quest_id":"GUILD_TUTORIAL_LOOT","title":"첫 전리품",
			"description":"1층에서 바닥 전리품이나 거점 물자를 하나 획득하세요.",
			"hint":"실제로 가방이나 원정 보관 기록에 들어간 물자만 인정됩니다.",
			"reward_kind":"GOLD","reward_text":"금화 20개","gold":20},
		{"quest_id":"GUILD_TUTORIAL_RETURN","title":"원정의 마무리",
			"description":"1층 전리품을 확보한 원정에서 마을로 귀환하세요.",
			"hint":"모든 의뢰를 완료하지 않아도 던전에 출발할 수 있습니다.",
			"reward_kind":"ITEM","reward_text":"기본 보급 묶음",
			"reward_rows":[{"definition_id":"FOOD_RATION","quantity":1},
				{"definition_id":"POTION_HEALING","quantity":1}]},
		{"quest_id":"GUILD_TUTORIAL_BIND","title":"내 것이 된 이능",
			"description":"이능 획득물을 보관한 뒤 효과와 슬롯을 확인하고 자신에게 결속하세요.",
			"hint":"획득물이 없으면 길드에서 화염탄 훈련 지원을 한 번 받을 수 있습니다. 상태창 이능 탭에서 결속하세요. 레벨당 한 칸, 최대 여섯 칸이며 현재 해제할 수 없습니다.",
			"reward_kind":"GOLD","reward_text":"금화 20개","gold":20},
		{"quest_id":"GUILD_TUTORIAL_SKILL","title":"힘을 쓰는 법",
			"description":"던전에서 자신의 액티브 스킬을 한 번 성공적으로 실행하세요.",
			"hint":"스킬 버튼을 눌러 대상이나 지점을 선택하세요. 기존 스킬도 인정하며 취소·자원 부족은 인정하지 않습니다.",
			"reward_kind":"ITEM","reward_text":"회복 물약 1개",
			"reward_rows":[{"definition_id":"POTION_HEALING","quantity":1}]},
		{"quest_id":"GUILD_TUTORIAL_UPGRADE","title":"한 단계 나은 무기",
			"description":"마을에서 재료를 사용해 자신의 무기를 한 번 재제작하세요.",
			"hint":"재제작 미리보기 후 확정하세요. 장착 교체나 무기 구입만으로는 완료되지 않습니다.",
			"reward_kind":"GOLD","reward_text":"금화 20개","gold":20},
		{"quest_id":"GUILD_TUTORIAL_INJURY","title":"상처를 읽는 법",
			"description":"전투 중 팔이나 다리에 부상이 생기면 부위 상태와 기능 영향을 확인하세요.",
			"hint":"일부러 다칠 필요 없습니다. 팔 기능 저하는 무기 사용에, 다리 기능 저하는 이동에 영향을 줍니다. 초상화를 길게 눌러 상태를 확인하세요.",
			"reward_kind":"ITEM","reward_text":"회복 물약 1개",
			"reward_rows":[{"definition_id":"POTION_HEALING","quantity":1}]},
		{"quest_id":"GUILD_TUTORIAL_TREAT","title":"팔다리 돌보기",
			"description":"의뢰 수락 후 전투에서 다친 팔다리를 마을 치유소에서 치료하세요.",
			"hint":"HP 물약과 부위 치료는 다릅니다. 치유소는 상처와 기능 손상을 치료하지만 절단된 팔다리를 재생하지는 않습니다.",
			"reward_kind":"GOLD","reward_text":"금화 20개","gold":20},
	]
	return result

static func definition(quest_id: String) -> Dictionary:
	for row in definitions():
		if str(row.quest_id) == quest_id: return row
	return {}

static func state(events: Array, protagonist_id: int = -1, enemy_ids: Array = []) -> Dictionary:
	return preload("res://sim/guild_tutorial_index.gd").new().observe(events,protagonist_id,enemy_ids,definitions())

static func legacy_state(events: Array, protagonist_id: int = -1, enemy_ids: Array = []) -> Dictionary:
	var accepted: Dictionary = {}
	var claimed: Dictionary = {}
	var support: Dictionary = {}
	for event in events:
		if str(event.type) == EVENT_ACCEPTED \
				and str(event.data.get("campaign_id", "")) == CAMPAIGN_ID \
				and (protagonist_id <= 0 or int(event.actor_id) == protagonist_id):
			var quest_id := str(event.data.get("quest_id", ""))
			if quest_id in QUEST_IDS and not accepted.has(quest_id): accepted[quest_id] = event
		elif str(event.type) == EVENT_SUPPORT_GRANTED \
				and str(event.data.get("campaign_id", "")) == CAMPAIGN_ID:
			support[str(event.data.get("quest_id", ""))] = true
		elif str(event.type) == EVENT_REWARD_CLAIMED \
				and str(event.data.get("campaign_id", "")) == CAMPAIGN_ID:
			claimed[str(event.data.get("quest_id", ""))] = true
	var rows: Array[Dictionary] = []
	for definition_value in definitions():
		var definition: Dictionary = definition_value
		var quest_id := str(definition.quest_id)
		var accepted_event = accepted.get(quest_id)
		var progress := _progress(events, accepted_event, quest_id, protagonist_id, enemy_ids)
		var completed := accepted_event != null and bool(progress.complete)
		var status := "AVAILABLE"
		if accepted_event != null: status = "COMPLETED" if completed else "ACTIVE"
		if claimed.has(quest_id): status = "CLAIMED"
		rows.append({"quest_id":quest_id,"title":str(definition.title),
			"description":str(definition.description),"hint":str(definition.hint),
			"reward_text":str(definition.reward_text),"reward_kind":str(definition.reward_kind),
			"status":status,"accepted":accepted_event != null,
			"completed":completed,"claimed":claimed.has(quest_id),
			"support_granted":support.has(quest_id),
			"progress":progress.duplicate(true),
			"can_accept":accepted_event == null,"can_claim":completed and not claimed.has(quest_id)})
	return {"schema_version":1,"ruleset_id":RULESET_ID,"campaign_id":CAMPAIGN_ID,
		"quests":rows}.duplicate(true)

static func _progress(events: Array, accepted_event, quest_id: String,
		protagonist_id: int, enemy_ids: Array) -> Dictionary:
	var result := {"count":0,"target":1,"diagonal":false,"complete":false,
		"hold_done":false,"attack_done":false,
		"floor_index":1,"expedition_index":0,"event_ids":[]}
	if quest_id == "GUILD_TUTORIAL_MOVE":result.target=3
	elif quest_id == "GUILD_TUTORIAL_GUARD":result.target=2
	if accepted_event == null: return result
	var floor_index := 1
	var expedition_index := 0
	var loot_expeditions: Dictionary = {}
	for event in events:
		if int(event.id) <= int(accepted_event.id): continue
		if str(event.type) == "town.expedition_departed":
			expedition_index = int(event.data.get("expedition_index", expedition_index))
			floor_index = int(event.data.get("floor_index", 1))
		elif str(event.type) == "dungeon.floor_entered":
			floor_index = int(event.data.get("floor_index", floor_index))
			expedition_index = int(event.data.get("expedition_index", expedition_index))
		result.floor_index = floor_index;result.expedition_index = expedition_index
		# Return tutorial progress is expedition-scoped. Record loot before the
		# quest-specific branch so an accepted return quest can observe loot that
		# happened earlier in the same expedition.
		if floor_index == 1 and int(event.actor_id) == protagonist_id \
				and (str(event.type) == "item.picked_up" or str(event.type) == "base.resource_gathered"):
			loot_expeditions[expedition_index] = true
		if int(event.actor_id) != protagonist_id or protagonist_id <= 0: continue
		if floor_index != 1: continue
		if quest_id == "GUILD_TUTORIAL_MOVE" and str(event.type) == "action.move":
			var from_value: Variant = event.data.get("from_position", [])
			var to_value: Variant = event.data.get("to_position", [])
			if from_value is Array and to_value is Array and from_value.size() == 2 \
					and to_value.size() == 2:
				result.count = mini(3, int(result.count) + 1)
				if absi(int(to_value[0]) - int(from_value[0])) == 1 \
						and absi(int(to_value[1]) - int(from_value[1])) == 1:
					result.diagonal = true
				result.event_ids.append(int(event.id))
		elif quest_id == "GUILD_TUTORIAL_GUARD":
			if str(event.type) == "action.hold":
				result.hold_done = true;result.event_ids.append(int(event.id))
			elif str(event.type) == "action.melee_attack" \
					and int(event.target_id) in enemy_ids \
					and str(event.data.get("outcome", "")) in ["HIT", "FINISHER"]:
				result.attack_done = true;result.event_ids.append(int(event.id))
		elif quest_id == "GUILD_TUTORIAL_HEAL" \
				and str(event.type) == "health.restored" \
				and int(event.target_id) == protagonist_id \
				and int(event.magnitude) > 0 \
				and str(event.data.get("kind", "")) == "POTION":
			result.count = 1;result.event_ids.append(int(event.id))
		elif quest_id == "GUILD_TUTORIAL_LOOT":
			if str(event.type) == "item.picked_up" or str(event.type) == "base.resource_gathered":
				result.count = 1;result.event_ids.append(int(event.id))
		elif quest_id == "GUILD_TUTORIAL_RETURN" \
				and str(event.type) == "dungeon.expedition_returned":
				if loot_expeditions.has(int(event.data.get("expedition_index", -1))):
					result.count = 1;result.event_ids.append(int(event.id))
		result.floor_index = floor_index;result.expedition_index = expedition_index
	if quest_id == "GUILD_TUTORIAL_MOVE": result.complete = int(result.count) >= 3 and bool(result.diagonal)
	elif quest_id == "GUILD_TUTORIAL_GUARD":
		result.count = int(result.hold_done) + int(result.attack_done)
		result.complete = bool(result.hold_done) and bool(result.attack_done)
	else: result.complete = int(result.count) >= 1
	return result
