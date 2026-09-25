extends SceneTree
## Level and boss banners; soul-stone drops stay in the log.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Banners = preload("res://expedition/ui/screens/banners.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func frames(n: int) -> void:
	for _i in range(n): await process_frame

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await frames(4)
	s.events.clear()
	var hero: Dictionary = s.party[0]
	check(s.gain_level_xp(hero,65) == 1,"one level gained")
	s.grant_part("GOBLIN_SHIV")
	check(s.log_lines[-1] == Essences.title("GOBLIN_SHIV")+" 획득","soul stone acquisition stays in the log")
	check(not s.events.any(func(e): return str(e.kind) == "ESSENCE"),"a soul stone queues no acquisition banner")
	s.events.append({"kind":"BOSS","name":"고블린 족장","hint":"지휘 부하"})
	scene.refresh(); await frames(3)
	var level: Node = scene.get_node_or_null("LevelUpBanner")
	check(level != null,"level-up banner appears first")
	check(level != null and level.find_children("*","Label",true,false).any(func(l): return l.text == "레벨 2"),"level is shown")
	check(level != null and level.find_child("BannerSlotLine",true,false).text == "영혼석 슬롯 +1","new slot is shown")
	check(scene.get_node_or_null("EssenceBanner") == null,"no acquisition banner appears")
	var rect: Rect2 = level.get_global_rect()
	check(rect.get_center().distance_to(scene.get_global_rect().get_center()) <= 2,"banner is centred")
	level.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	var boss: Node = scene.get_node_or_null("BossBanner")
	check(boss != null and boss.find_children("*","Label",true,false).any(func(l): return l.text == "고블린 족장"),"boss name follows the level")
	check(boss != null and boss.find_children("*","Label",true,false).any(func(l): return l.text == "지휘 부하"),"boss hint stays brief")
	boss.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	check(not Banners.showing(scene) and not s.events.any(func(e): return str(e.kind) in ["LEVEL_UP","BOSS"]),"banner queue drains")
	s.events.append({"kind":"LEVEL_UP","actor":999,"level":3})
	check(not Banners.show_next(scene) and s.events.is_empty(),"invalid level event is discarded")
	scene.queue_free(); await process_frame
	print("Banners: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
