extends "res://game/crawl/game.gd"
const UsageWorld=preload("res://game/crawl/usage_world.gd")

func _init()->void:
	world=UsageWorld.new()

func growth()->void:
	panel("숙련 · 전투에서 자연 성장")
	label(content,"숙련은 10종입니다. 적을 처치하면 그 적의 XP가 전투 중 사용한 무기·마법의 사용 횟수 비율대로 나뉩니다.\n현재 XP %d · 공격 지연 %d · 주문 부담 %d"%[world.xp,world.stats(world.hero()).delay,world.stats(world.hero()).enc])
	for axis in UsageWorld.USAGE_SKILLS:
		label(content,"%s  %d  · 숙련 XP %d"%[UsageWorld.USAGE_SKILLS[axis],world.skill_rank(axis),int(world.skills.get(axis,0))])
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
