extends "res://game/crawl/game.gd"
const UsageWorld=preload("res://game/crawl/usage_world.gd")

func _init()->void:
	world=UsageWorld.new()

func growth()->void:
	panel("숙련 · 스킬 · 융합")
	label(content,"처치 XP가 사용 횟수 비율대로 숙련에 분배됩니다. 숙련 Lv1~10마다 보상이 자동 해금되고, 주계열 Lv5 + 보조계열 Lv3부터 방향성 융합이 열립니다.\n현재 XP %d · 공격 지연 %d · 주문 부담 %d"%[world.xp,world.stats(world.hero()).delay,world.stats(world.hero()).enc])
	for axis in UsageWorld.USAGE_SKILLS:
		var rank:int=world.skill_rank(axis)
		var names:Array=[]
		for reward in world.unlocked_rewards(axis):names.append("Lv%d %s"%[int(reward.level),str(reward.name)])
		label(content,"%s  Lv%d · XP %d\n%s"%[UsageWorld.USAGE_SKILLS[axis],rank,int(world.skills.get(axis,0))," · ".join(names) if not names.is_empty() else "아직 해금 없음"])
	var fusions:Array=world.unlocked_fusions()
	label(content,"융합 스킬")
	if fusions.is_empty():label(content,"아직 없음 · 주계열 Lv5 + 보조계열 Lv3 필요")
	else:
		for fusion in fusions:
			var direction:String="%s → %s"%[UsageWorld.USAGE_SKILLS.get(fusion.main,fusion.main),UsageWorld.USAGE_SKILLS.get(fusion.sub,fusion.sub)]
			label(content,"%s · Tier %d · %s · %s"%[fusion.display_name,int(fusion.tier),direction,str(fusion.kind)])
	label(content,"배운 주문 · 준비 최대 6개 · 안전한 곳에서 변경")
	for key in world.spells:
		var id:String=key;var sp:Dictionary=World.DATA.spells[id]
		label(content,"%s · %s · Lv%d · %dMP · 실패%d%%\n%s"%[sp.name,UsageWorld.USAGE_SKILLS.get(sp.school,World.DATA.skills.get(sp.school,sp.school)),sp.level,sp.mp,world.failure(id),sp.note])
		button(content,"준비 해제" if id in world.prepared else "준비",func():world.submit("PREPARE",-1,id);growth();refresh(false);save_timer.start())

func new_game_menu()->void:
	panel("새 탐험 · 종족 선택")
	for key in World.DATA.species:
		var id:String=key;var s:Dictionary=World.DATA.species[id]
		label(content,"%s · HP%d MP%d\n%s"%[s.name,s.hp,s.mp,s.note])
		button(content,s.name+" 시작",func():world=UsageWorld.new(int(Time.get_unix_time_from_system()),id);save_allowed=true;dialog.hide();refresh(false);save())
