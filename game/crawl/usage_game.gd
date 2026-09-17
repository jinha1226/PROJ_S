extends "res://game/crawl/game.gd"
const UsageWorld=preload("res://game/crawl/usage_world.gd")

func _init()->void:
	world=UsageWorld.new()

func growth()->void:
	panel("숙련 · 사용하면 성장")
	label(content,"전투 XP는 레벨만 올립니다. 무기·마법·방어·회피·은신·도구 숙련은 실제 사용으로 오릅니다.\n현재 XP %d · 공격 지연 %d · 주문 부담 %d"%[world.xp,world.stats(world.hero()).delay,world.stats(world.hero()).enc])
	for axis in UsageWorld.USAGE_SKILLS:
		label(content,"%s  %d  · 숙련도 %d"%[UsageWorld.USAGE_SKILLS[axis],world.skill_rank(axis),int(world.skills.get(axis,0))])
	label(content,"배운 주문 · 준비 최대 6개 · 안전한 곳에서 변경")
	for key in world.spells:
		var id:String=key;var sp:Dictionary=World.DATA.spells[id]
		label(content,"%s · %s · Lv%d · %dMP · 실패%d%%\n%s"%[sp.name,UsageWorld.USAGE_SKILLS.get(sp.school,World.DATA.skills.get(sp.school,sp.school)),sp.level,sp.mp,world.failure(id),sp.note])
		button(content,"준비 해제" if id in world.prepared else "준비",func():world.submit("PREPARE",-1,id);growth();refresh(false);save_timer.start())
