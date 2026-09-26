extends SceneTree
const Session = preload("res://expedition/run/session.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
const Board = preload("res://expedition/ui/board.gd")
const Vfx = preload("res://expedition/ui/effect_vfx.gd")
const Presentation = preload("res://expedition/ui/battle_presentation.gd")
var checks := 0
var failures := 0

class Canvas extends RefCounted:
	var strokes: Array = []
	func draw_line(a, b, color, width, _aa): strokes.append(["line",a,b,color,width])
	func draw_arc(p, r, a, b, n, color, width, _aa): strokes.append(["arc",p,r,a,b,n,color,width])
	func draw_circle(p, r, color): strokes.append(["circle",p,r,color])
	func draw_polyline(points, color, width, _aa): strokes.append(["polyline",points,color,width])
	func draw_colored_polygon(points, color): strokes.append(["polygon",points,color])

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func setup():
	var s = Session.new(731,false,true,true,2); s.depart()
	var c: Vector2i = Fixture.arena(s,8)
	var foe: Dictionary = s.enemies[0]
	foe.hp = 400; foe.max_hp = 400; foe.pos = c+Vector2i.RIGHT
	foe.part_id = ""; foe.species_id = ""; foe.statuses = {}; foe.res = {}
	for actor in s.party:
		actor.equipped_abilities = []; actor.essences = {}; actor.statuses = {}
	s.floor_state.observe(s); s.effects.clear()
	return s

func rendered(style: String) -> Array:
	var canvas = Canvas.new()
	Vfx.draw(canvas,style,Vector2(100,100),Vector2(80,100),12,0.12)
	return canvas.strokes

func run() -> void:
	# All semantic styles render and expire, including a compact mobile tile.
	for style in Vfx.PALETTE:
		check(not rendered(style).is_empty(),style+" has geometry")
		for r in [1.0,8.0,24.0]:
			for t in [-0.1,0.0,0.13,0.45,0.46,1.0]:
				var canvas = Canvas.new()
				Vfx.draw(canvas,str(style),Vector2(100,100),Vector2(80,100),r,t)
				check(canvas.strokes.is_empty() == (t < 0 or t >= Vfx.DURATION),style+" obeys lifetime at every tile scale")
				for stroke in canvas.strokes:
					for value in stroke:
						if value is Vector2: check(value.is_finite(),"finite VFX geometry")
						if value is Color: check(value.a >= 0 and value.a <= 1,"bounded VFX opacity")
	check(rendered("fire") != rendered("ice") and rendered("ice") != rendered("lightning"),"elements differ in shape as well as color")
	check(rendered("slash") != rendered("pierce") and rendered("pierce") != rendered("impact"),"three physical forms differ")
	check(rendered("shield") != rendered("heal") and rendered("bind") != rendered("stun"),"defense, heal and control differ")
	for status in Session.Statuses.HARMFUL:
		check(Vfx.STATUS.has(status) and Vfx.PALETTE.has(Vfx.status_style(status)),status+" has an explicit visual")
	for reaction in Session.Reactions.NAMES: check(Vfx.REACTION.has(reaction),reaction+" has a visual")
	for pair in [["fire","fire"],["ICE","ice"],["air","lightning"],["ELECTRIC","lightning"],["poison","poison"],["will","hex"]]:
		check(Vfx.damage_style(pair[0],"SLASH") == pair[1],"element wins over physical drop form")
	check(Vfx.damage_style("physical","SLASH",true) == "bleed","bleed tick never uses a weapon slash")

	var s = setup()
	var hero: Dictionary = s.party[0]
	var foe: Dictionary = s.enemies[0]
	var roll_before: int = s.roll_serial
	var serial_before: int = s.serial
	var actors_before: Array = [hero.duplicate(true),foe.duplicate(true)]
	for i in range(100): Vfx.emit(s,"shield",hero.pos,hero.pos)
	check(s.effects.size() == 1,"one action deduplicates repeated visuals")
	check(s.roll_serial == roll_before and s.serial == serial_before and hero == actors_before[0] and foe == actors_before[1],"visual emission never changes combat or RNG")
	s.Reactions.begin_action(s); Vfx.emit(s,"shield",hero.pos,hero.pos)
	check(s.effects.size() == 2,"next action may show the same effect")
	s.effects.clear(); foe.statuses.immune = int(s.time)+100
	check(not s.Statuses.apply(s,foe,"poison",300,hero) and s.effects.is_empty(),"immune target has no false poison visual")
	foe.statuses.clear()
	check(s.Statuses.apply(s,foe,"poison",300,hero),"successful poison")
	check(s.effects.size() == 1 and s.effects[0].vfx == "poison","actual status has its own visual")
	s.Statuses.apply(s,foe,"poison",300,hero)
	check(s.effects.size() == 1,"refreshing an existing DOT does not spam VFX")
	s.effects.clear(); hero.hp = hero.max_hp
	s.StoneEffects.heal(s,hero,5,hero)
	check(s.effects.is_empty(),"full HP has no fake healing visual")
	hero.hp -= 5
	s.StoneEffects.heal(s,hero,3,hero,true,foe)
	check(s.effects[0].vfx == "lifesteal" and s.effects[0].from == foe.pos and s.effects[0].cell == hero.pos,"lifesteal travels from victim to healer")
	s.effects.clear()
	s.CombatRules.damage(s,hero,foe,3,"ice",0,s.Reactions.EXTRA_FORM)
	check(s.effects[0].vfx == "ice" and s.effects[0].element == "ice","secondary damage retains element instead of becoming a generic impact")
	s.effects.clear()
	s.StoneEffects.EffectEngine.Code.run(s,"reflect",hero,{}, {"attacker":foe,"lost":10})
	check(s.effects.any(func(e): return e.get("vfx","") == "reflect" and e.from == hero.pos and e.cell == foe.pos),"reflection follows the return direction")
	s.effects.clear()
	var places: Array = s.Spells.Summons.summon_cells(s,hero)
	var pet: Dictionary = s.Spells.Summons.summon(s,hero,places[0],"hound")
	check(s.effects.any(func(e): return e.get("vfx","") == "summon" and e.cell == pet.pos),"summon circle appears on the spawn cell")
	s.effects.clear()
	s.StoneEffects.modifier(s,"armour",hero)
	check(s.effects.is_empty(),"stat queries have no visual side effects")
	var recorder = Presentation.new(); recorder.begin(s)
	Vfx.emit(s,"heal",Vector2i.ZERO,Vector2i.ZERO)
	recorder.finish(s)
	check(recorder.frames.is_empty(),"unseen procs never create empty playback pauses")
	s.effects.clear()
	var damage := {"from":hero.pos,"cell":foe.pos,"amount":3,"form":"physical"}
	s.effects.append(damage)
	for i in range(100): Vfx.emit(s,"buff",Vector2i(i,0),Vector2i(i,0))
	check(s.effects.size() <= 64 and s.effects.any(func(e): return is_same(e,damage)),"cosmetic capacity preserves pending damage reports")
	s.effects.clear()
	hero.hp = hero.max_hp
	check(not s.Consumables.drink(s,"healing",hero) and s.effects.is_empty(),"failed healing potion has no visual")
	hero.hp -= 3
	check(s.Consumables.drink(s,"healing",hero) and s.effects[0].vfx == "heal","successful potion has healing VFX without changing its formula")
	s.effects.clear(); hero.mp = hero.max_mp
	check(not s.Consumables.read(s,"recharging",hero) and s.effects.is_empty(),"failed recharge has no visual")
	hero.mp -= 1
	check(s.Consumables.read(s,"recharging",hero) and s.effects[0].vfx == "mana","recharging scroll has MP VFX")

	var board = Board.new(); board.session = s; board.size = Vector2(320,320); board.geometry()
	var event := {"kind":"VFX","vfx":"reflect","from":hero.pos,"cell":foe.pos}
	var canvas = Canvas.new()
	board.effect_time = 0.13; board.effects = [event]
	board.draw_effect_visual(event,canvas)
	check(not canvas.strokes.is_empty(),"visible effect renders on the board")
	s.floor_state.visible.erase(foe.pos); canvas.strokes.clear()
	board.draw_effect_visual(event,canvas)
	check(canvas.strokes.is_empty(),"hidden target never leaks VFX")
	s.floor_state.visible[foe.pos] = true; s.floor_state.visible.erase(hero.pos)
	canvas.strokes.clear(); board.draw_effect_visual(event,canvas)
	check(not canvas.strokes.is_empty(),"visible target still shows a local impact from unseen source")
	check(not canvas.strokes.any(func(stroke): return stroke.has(board.cell_center(hero.pos)-Vector2(0,board.half_width*0.7))),"unseen source position never appears in a trail")
	# Presentation uses recorded visibility rather than advanced live state.
	var state := Presentation.snapshot(s)
	board.playback = [{"before":state,"after":state,"effects":[event]}]; board.visual_state = state
	s.floor_state.visible.erase(foe.pos)
	check(board.effect_visible(event),"playback culls with frame visibility")
	board.playback.clear(); board.visual_state = {}; board.effect_time = 0.3
	var first := {"from":hero.pos,"cell":foe.pos,"amount":1}
	var second := first.duplicate()
	board.effects = [first,event,{"kind":"PROC","from":hero.pos,"cell":hero.pos,"vfx":"heal"},second]
	check(is_equal_approx(board.clock_of(second),0.3-board.STAGGER),"auxiliary effects do not delay the next hit")
	board.effects = [event]
	check(board.hit_offset(hero.pos) == Vector2.ZERO,"VFX alone cannot lunge the caster")
	board.free()
	# Exercise native CanvasItem drawing, not just the geometry collector.
	var scene = load("res://expedition/ui/main.tscn").instantiate()
	scene.session = setup(); root.size = Vector2i(320,640); root.add_child(scene)
	await process_frame
	scene.board.effects.clear(); scene.board.effect_time = 0.13
	for style in Vfx.PALETTE:
		scene.board.effects.append({"kind":"VFX","vfx":style,"from":scene.session.party[0].pos,"cell":scene.session.enemies[0].pos})
	scene.board.queue_redraw(); await process_frame; await process_frame
	scene.queue_free(); await process_frame
	print("Effect VFX: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
