extends SceneTree
## §4 알림: a level gained and an essence found each get a big centre banner,
## one at a time, tapped away.
const Session = preload("res://expedition/run/session.gd")
const Essences = preload("res://expedition/progression/essences.gd")
const Banners = preload("res://expedition/ui/screens/banners.gd")
const EssenceTab = preload("res://expedition/ui/screens/essence_tab.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func frames(n: int) -> void:
	for _i in range(n): await process_frame

func labels(node: Node) -> Array:
	return node.find_children("*","Label",true,false).map(func(l): return l.text)

func run() -> void:
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	var s = Session.new_run(731)
	scene.session = s; root.size = Vector2i(390,844); root.add_child(scene); scene.set_process(false)
	await frames(4)
	s.events.clear()
	var hero: Dictionary = s.party[0]
	check(s.gain_level_xp(hero,65) == 1,"one level gained")
	s.events.append({"kind":"ESSENCE","id":"GOBLIN_SHIV@fire","new":true})
	s.parts_bag["RAT_GNAW"] = 1
	s.phase = "CAMP"
	check(s.absorb_essence(0,"RAT_GNAW").is_empty(),"the hero already has the rat essence")
	s.events.append({"kind":"ESSENCE","id":"RAT_GNAW","new":false})
	scene.refresh(); await frames(3)
	var level: Node = scene.get_node_or_null("LevelUpBanner")
	check(level != null,"refresh shows the level-up banner first")
	check(level != null and labels(level).has("레벨 2"),"the banner names the new level")
	check(level != null and level.find_child("BannerSlotLine",true,false).text == "이능 슬롯 +1","and the slot it opened")
	var rect: Rect2 = level.get_global_rect()
	var centre: Vector2 = scene.get_global_rect().get_center()
	check(rect.get_center().distance_to(centre) <= 2,"the banner sits in the centre")
	check(scene.get_node_or_null("EssenceBanner") == null,"one banner at a time")
	level.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	var found: Node = scene.get_node_or_null("EssenceBanner")
	check(found != null and scene.get_node_or_null("LevelUpBanner") == null,"tapping it brings the next one")
	check(found != null and labels(found).has("새 이능"),"a new essence says so")
	check(found != null and labels(found).has(EssenceTab.tag_line("GOBLIN_SHIV@fire")),"both tags are shown")
	var skin: StyleBoxFlat = found.get_theme_stylebox("panel")
	check(skin.border_color == EssenceTab.ELEMENT_COLORS.fire,"a fire variant has a fire border")
	found.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	var again: Node = scene.get_node_or_null("EssenceBanner")
	check(again != null and again.find_child("BannerUpgrade",true,false) != null,"an essence someone holds offers a tier up")
	check(again != null and again.find_child("BannerUpgrade",true,false).text.contains(str(hero.name)),"naming who can take it")
	again.find_child("BannerOk",true,false).pressed.emit(); await frames(3)
	check(not Banners.showing(scene) and not s.events.any(func(e): return str(e.kind) in ["LEVEL_UP","ESSENCE"]),"the queue is drained")
	s.events.append({"kind":"LEVEL_UP","actor":999,"level":3})
	check(not Banners.show_next(scene) and s.events.is_empty(),"a level-up of someone outside the party is dropped silently")
	scene.queue_free(); await process_frame
	print("Banners: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
