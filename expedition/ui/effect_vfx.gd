extends RefCounted
## Semantic, deterministic visuals. No combat RNG, timers, actors or textures
## are changed here. Events are emitted only after the gameplay effect succeeds.
const DURATION := 0.46
const STATUS := {
	"burn":"fire", "freeze":"ice", "slow":"slow", "poison":"poison", "bleed":"bleed",
	"bind":"bind", "stun":"stun", "confuse":"confuse", "dominate":"dominate",
	"fracture":"fracture", "exposed":"mark", "marked":"mark", "vulnerable":"mark",
	"weak":"hex", "brittle":"fracture", "distort":"confuse", "taunted":"mark", "taunt":"mark",
	"ward":"shield", "immune":"shield", "shield_stance":"shield", "cracked":"fracture",
	"haste":"haste", "wet":"water", "furnace":"fire", "summon_power":"buff",
	"fire_mastery":"fire", "ice_freeze":"ice", "air_chain":"lightning", "stormeye":"lightning",
	"hex_mastery":"hex", "next_chain":"lightning", "next_fire":"fire", "next_pierce":"pierce",
	"next_ice_slow":"ice", "summon_hp":"buff", "summon_time":"summon", "summon_renew":"heal"
}
const REACTION := {"steam":"steam", "ice":"ice", "discharge":"lightning", "electrocute":"lightning",
	"poison_pool":"poison", "poison_blast":"poison_blast", "shatter":"shatter", "boiling":"fire", "betrayal":"dominate"}
const PALETTE := {
	"slash":"fff0cd", "pierce":"ffe399", "impact":"e3ba83", "fire":"ff843e", "ice":"a1e4ff",
	"lightning":"80ecff", "poison":"a8de62", "poison_blast":"a8de62", "bleed":"ed5c64",
	"heal":"83e5aa", "lifesteal":"dc657e", "mana":"80acff", "shield":"e8d28e", "reflect":"a4f0e8",
	"counter":"ffd075", "cleanse":"c8ffef", "revive":"ffeaba", "summon":"c3a1ed", "death":"b99bd3",
	"hex":"c999eb", "confuse":"d5a6ed", "dominate":"df83db", "bind":"ebe1ca", "stun":"ffe088",
	"fracture":"d8c6ae", "mark":"ffaf86", "slow":"98c4dc", "haste":"8cead8", "rage":"ff715c",
	"buff":"ffe19b", "dodge":"c7e2f3", "crit":"ffbd72", "push":"dac3a0", "water":"89cddc", "sleep":"b8c5ed",
	"steam":"e0e6e1", "shatter":"a1e4ff"
}
const STACK := {"aim":"mark", "guard":"shield", "quick":"haste", "rage_hits":"rage", "dodge_crit":"crit", "block_attack":"counter", "ally_kill":"buff"}

static func status_style(status: String) -> String:
	return str(STATUS.get(status,"buff"))

static func damage_style(element: String, form: String = "", dot: bool = false) -> String:
	match element.to_upper():
		"FIRE": return "fire"
		"ICE": return "ice"
		"AIR", "ELECTRIC": return "lightning"
		"POISON": return "poison"
		"WILL": return "hex"
		"BLEED": return "bleed"
		"RETALIATE": return "reflect"
		"COUNTER": return "counter"
	if dot and form == "SLASH": return "bleed"
	match form if form != "" else element:
		"SLASH": return "slash"
		"PIERCE": return "pierce"
	return "impact"

static func emit(s, style: String, cell: Vector2i, from: Vector2i, details: Dictionary = {}) -> void:
	if not PALETTE.has(style): return
	# Refreshes and spread loops can touch a cell repeatedly in one action.
	for previous in s.effects:
		if previous.get("kind","") == "VFX" and previous.get("vfx","") == style and previous.get("cell") == cell and previous.get("from") == from and int(previous.get("action",-1)) == int(s.action_serial): return
	var event := details.duplicate()
	event.merge({"kind":"VFX","vfx":style,"from":from,"cell":cell,"action":int(s.action_serial)},true)
	s.effects.append(event)
	trim(s)

static func trim(s) -> void:
	if s.presentation != null: return
	# Keep the original 32 gameplay notices/hits. Cosmetic events may never
	# evict damage entries that the encounter simulator has yet to harvest.
	var substantive: Array = s.effects.filter(func(e): return e.get("kind","") != "VFX")
	while substantive.size() > 32:
		var first: Dictionary = substantive.pop_front()
		for i in range(s.effects.size()):
			if is_same(s.effects[i],first): s.effects.remove_at(i); break
	while s.effects.size() > 64:
		var index := -1
		for i in range(s.effects.size()):
			if s.effects[i].get("kind","") == "VFX": index = i; break
		if index < 0: break
		s.effects.remove_at(index)

static func status(s, actor: Dictionary, id: String, source: Dictionary = {}) -> void:
	if actor.has("pos"): emit(s,status_style(id),actor.pos,source.get("pos",actor.pos),{"status":id})

## Every stroke is bounded by tile size; direction is supplied by visible
## endpoints only. Thus an unseen attacker cannot reveal its location.
static func draw(canvas, style: String, center: Vector2, start: Vector2, radius: float, elapsed: float) -> void:
	if elapsed < 0 or elapsed >= DURATION or not PALETTE.has(style): return
	var t := elapsed/DURATION
	var fade := 1.0-t
	var r := maxf(3,radius)
	var width := clampf(r*0.09,1.0,2.6)
	var color := Color(str(PALETTE[style]),fade)
	var white := Color(1,0.98,0.89,fade)
	var direction := (center-start).normalized()
	if direction == Vector2.ZERO: direction = Vector2.RIGHT
	match style:
		"slash", "counter", "crit":
			var heading := direction.angle()
			canvas.draw_arc(center,r*(0.7+t*0.35),heading-1.5+t,heading+1.0+t,16,color,width*2,true)
			if style == "crit": cross(canvas,center,r*0.45,white,width)
			if style == "counter": arrow(canvas,center-direction*r,center+direction*r,color,width)
		"pierce":
			arrow(canvas,center-direction*r*(1.3-t),center+direction*r*(0.3+t),white,width*1.7)
			canvas.draw_arc(center,r*(0.25+t*0.4),0,TAU,16,color,width,true)
		"impact", "push", "fracture":
			canvas.draw_arc(center,r*(0.2+t),0,TAU,20,color,width*1.6,true)
			for i in range(6):
				var ray := Vector2.RIGHT.rotated(i*TAU/6+0.3)
				canvas.draw_line(center+ray*r*(0.3+t),center+ray*r*(0.55+t),color,width,true)
			if style == "fracture": bolt(canvas,center-Vector2(r*0.25,r*0.5),center+Vector2(r*0.3,r*0.5),color,width)
		"fire", "rage":
			for i in range(5):
				var x := (i-2)*r*0.3
				var p := center+Vector2(x,-r*t*0.8)
				var height := r*(0.6+0.2*sin(i*2.1+t*5))
				canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(-r*0.17,r*0.2),p+Vector2(r*0.08,-height),p+Vector2(r*0.18,r*0.2)]),color)
				canvas.draw_line(p,p+Vector2(0,-height*0.4),white,width,true)
		"ice", "shatter":
			for i in range(6):
				var ray := Vector2.RIGHT.rotated(i*TAU/6)
				var at := center+ray*r*t*(1.0 if style == "shatter" else 0.2)
				canvas.draw_line(at,at+ray*r*0.85,color,width*1.4,true)
				var tip := at+ray*r*0.6
				canvas.draw_line(tip,tip-ray.rotated(0.65)*r*0.28,color,width,true)
				canvas.draw_line(tip,tip-ray.rotated(-0.65)*r*0.28,color,width,true)
		"lightning", "reflect":
			if start.distance_to(center) > r*0.4: bolt(canvas,start,center,color,width*1.6)
			for i in range(3):
				var ray := Vector2.RIGHT.rotated(i*TAU/3+t*2)
				bolt(canvas,center+ray*r*0.1,center+ray*r*(0.7+t*0.3),white,width)
			if style == "reflect" and start != center: shield(canvas,start,r*0.55,color,width)
		"poison", "poison_blast", "bleed":
			for i in range(5):
				var angle := i*2.4
				var p := center+Vector2(cos(angle),sin(angle))*r*(0.25+t*(1.2 if style == "poison_blast" else 0.6))
				p.y += r*t*t if style == "bleed" else -r*t*0.55
				canvas.draw_circle(p,r*(0.1+0.02*(i%3))*fade+0.5,color)
				if style == "bleed": canvas.draw_line(p-Vector2(0,r*0.2),p,color,width,true)
			if style == "poison_blast": canvas.draw_arc(center,r*(0.4+t*1.0),0,TAU,24,color,width*2,true)
		"heal", "mana", "cleanse", "revive":
			canvas.draw_arc(center+Vector2(0,r*0.5),r*(0.4+t*0.5),0,TAU,24,color,width,true)
			for i in range(3):
				var p := center+Vector2((i-1)*r*0.5,-r*(t*1.2+i*0.12))
				cross(canvas,p,r*0.12,color,width)
			if style in ["cleanse","revive"]:
				canvas.draw_line(center+Vector2(0,r*0.5),center-Vector2(0,r*(0.5+t)),white,width*2,true)
		"lifesteal":
			if start != center:
				var point := start.lerp(center,minf(1,t*1.6))
				canvas.draw_line(start.lerp(center,maxf(0,t*1.6-0.25)),point,color,width*2,true)
				canvas.draw_circle(point,r*0.16,white)
			cross(canvas,center-Vector2(0,r*t),r*0.2,color,width*1.5)
		"shield": shield(canvas,center,r*(0.8+t*0.1),color,width*1.5)
		"bind":
			canvas.draw_arc(center,r*0.8,0,TAU,24,color,width,true)
			for i in range(4):
				var ray := Vector2.RIGHT.rotated(i*PI/2)
				canvas.draw_line(center+ray*r*0.8,center-ray*r*0.5,color,width,true)
		"stun", "confuse", "dominate", "sleep":
			for i in range(3):
				var angle := i*TAU/3+t*3
				var p := center+Vector2(cos(angle)*r*0.65,sin(angle)*r*0.22-r*0.65)
				cross(canvas,p,r*0.12,color,width)
			if style == "dominate": canvas.draw_arc(center,r*0.85,0,TAU,24,color,width*2,true)
		"hex":
			var points := PackedVector2Array([center+Vector2(0,-r),center+Vector2(r*0.6,0),center+Vector2(0,r),center-Vector2(r*0.6,0),center+Vector2(0,-r)])
			canvas.draw_polyline(points,color,width,true)
			canvas.draw_line(center-Vector2(r*0.35,0),center+Vector2(r*0.35,0),white,width,true)
		"mark":
			canvas.draw_arc(center,r*(0.8-t*0.25),0,TAU,24,color,width,true)
			for ray in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
				canvas.draw_line(center+ray*r,center+ray*r*0.55,color,width,true)
		"summon", "death":
			var p := center+Vector2(0,r*0.5)
			canvas.draw_arc(p,r*(0.6+t*0.3),0,TAU,24,color,width*1.7,true)
			canvas.draw_arc(p,r*(0.35+t*0.3),0,TAU,24,color,width,true)
			for i in range(4):
				var ray := Vector2.RIGHT.rotated(i*PI/2+t)
				canvas.draw_line(p+ray*r*0.3,p+ray*r*0.7,color,width,true)
			canvas.draw_line(p,p+Vector2(0,r*(0.7+t)*(1 if style == "death" else -1)),white,width*1.5,true)
		"dodge":
			for i in range(3):
				var p := center+Vector2(-r*(t+i*0.2),0)
				canvas.draw_arc(p,r*0.6,-PI*0.4,PI*0.4,12,Color(color,fade*(1.0-i*0.25)),width,true)
		"slow", "haste", "buff":
			for i in range(3):
				var p := center+Vector2((i-1)*r*0.42,r*(0.3-t))
				var dy := r*0.28*(1 if style == "slow" else -1)
				canvas.draw_polyline(PackedVector2Array([p+Vector2(-r*0.14,-dy),p,p+Vector2(r*0.14,-dy)]),color,width,true)
		"steam", "water":
			for i in range(4):
				var p := center+Vector2((i-1.5)*r*0.35,-r*t*0.8)
				canvas.draw_arc(p,r*(0.2+t*0.3),0,PI if style == "water" else TAU,16,Color(color,fade*0.65),width*2,true)

static func cross(canvas, p: Vector2, r: float, color: Color, width: float) -> void:
	canvas.draw_line(p-Vector2(r,0),p+Vector2(r,0),color,width,true)
	canvas.draw_line(p-Vector2(0,r),p+Vector2(0,r),color,width,true)

static func projectile(canvas, style: String, start: Vector2, end: Vector2, radius: float, elapsed: float) -> void:
	if elapsed < 0 or elapsed >= 0.18 or not PALETTE.has(style): return
	var t := elapsed/0.18
	var tip := start.lerp(end,t)
	var tail := start.lerp(end,maxf(0,t-0.15))
	var color := Color(str(PALETTE[style]),1.0-t*0.4)
	var width := clampf(radius*0.08,1,2.4)
	if style == "pierce": arrow(canvas,tail,tip,color,width)
	else:
		canvas.draw_line(tail,tip,color,width*2,true)
		canvas.draw_circle(tip,maxf(2,radius*0.15),color)

static func arrow(canvas, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	canvas.draw_line(a,b,color,width,true)
	var back := (a-b).normalized()*minf(8,a.distance_to(b)*0.35)
	canvas.draw_line(b,b+back.rotated(0.6),color,width,true)
	canvas.draw_line(b,b+back.rotated(-0.6),color,width,true)

static func bolt(canvas, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var side := (b-a).normalized().orthogonal()*minf(7,a.distance_to(b)*0.16)
	canvas.draw_polyline(PackedVector2Array([a,a.lerp(b,0.3)+side,a.lerp(b,0.55)-side,b]),color,width,true)

static func shield(canvas, p: Vector2, r: float, color: Color, width: float) -> void:
	canvas.draw_polyline(PackedVector2Array([p+Vector2(-r*0.6,-r*0.6),p+Vector2(r*0.6,-r*0.6),p+Vector2(r*0.45,r*0.2),p+Vector2(0,r*0.7),p+Vector2(-r*0.45,r*0.2),p+Vector2(-r*0.6,-r*0.6)]),color,width,true)
