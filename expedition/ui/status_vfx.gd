extends RefCounted
## Small repeating marks attached to the actor, not the floor. Rendering is
## read-only; the wall clock animates them without advancing combat time.
const Vfx = preload("res://expedition/ui/effect_vfx.gd")
const ORDER := ["freeze","slow","burn","poison","bleed","charge","wet","bind","stun","confuse","dominate","weak","death_mark","brittle","distort","fracture","exposed","marked","vulnerable","taunted","taunt","blessing","ward","immune","shield_stance","haste"]

static func styles(actor: Dictionary, time: int) -> Array:
	var result: Array = []
	if int(actor.get("hp",0)) <= 0: return result
	var statuses: Dictionary = actor.get("statuses",{})
	for id in ORDER:
		if not statuses.has(id) or int(statuses[id]) < time: continue
		if id == "slow" and statuses.has("freeze") and int(statuses.freeze) >= time: continue
		var style := Vfx.status_style(str(id))
		if style not in result: result.append(style)
	return result

static func draw(canvas, actor: Dictionary, time: int, foot: Vector2, size: float, clock: float) -> void:
	var phase := clock+posmod(int(actor.get("id",0)),13)*0.137
	for style in styles(actor,time): draw_style(canvas,str(style),foot,size,phase)

static func drop(canvas, p: Vector2, size: float, color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([p+Vector2(0,-size*1.8),p+Vector2(size*0.85,0),p+Vector2(0,size*0.65),p-Vector2(size*0.85,0)]),color)

static func draw_style(canvas, style: String, foot: Vector2, size: float, clock: float) -> void:
	var r := maxf(3,size)
	var width := clampf(r*0.095,1.2,2.8)
	var color := Color(str(Vfx.PALETTE.get(style,"ffe19b")))
	var torso := foot-Vector2(0,r*1.25)
	var head := foot-Vector2(0,r*2.6)
	var pulse := 0.78+0.18*sin(clock*TAU)
	match style:
		"fire":
			# Fire climbs the sides, leaving the face and body silhouette clear.
			for i in range(4):
				var t := fposmod(clock*1.15+i*0.25,1.0)
				var p := torso+Vector2((-1 if i%2 == 0 else 1)*r*0.65,-r*(t*0.7-0.2))
				var h := r*(0.45+0.15*sin(clock*9+i))
				var points := PackedVector2Array([p+Vector2(-r*0.17,0),p+Vector2(-r*0.09,-h*0.5),p+Vector2(r*0.03,-h),p+Vector2(r*0.19,-h*0.3),p+Vector2(r*0.16,0)])
				canvas.draw_colored_polygon(points,Color(color,0.9))
				canvas.draw_line(p-Vector2(0,r*0.04),p-Vector2(0,h*0.45),Color("ffe4a1"),width,true)
				canvas.draw_circle(p-Vector2(r*0.05,h+r*t*0.5),maxf(0.8,r*0.045),Color("ffba65",1.0-t*0.7))
		"ice":
			# Fixed crystals remain visible between pulses: frozen is never just a flash.
			for i in range(4):
				var p := foot+Vector2((i-1.5)*r*0.4,-r*0.18)
				var h := r*(2.2 if i%2 == 0 else 2.7)
				var points := PackedVector2Array([p-Vector2(r*0.18,0),p+Vector2(-r*0.16,-h*0.65),p+Vector2(r*0.05,-h),p+Vector2(r*0.2,-h*0.55),p+Vector2(r*0.16,0)])
				canvas.draw_colored_polygon(points,Color(color,0.24))
				points.append(points[0]); canvas.draw_polyline(points,Color(color,pulse),width,true)
			canvas.draw_arc(torso,r*0.72,PI*0.15,PI*0.85,12,Color("def6ff",pulse),width,true)
		"slow":
			for i in range(3):
				var p := foot+Vector2((i-1)*r*0.48,-r*0.2)
				canvas.draw_line(p-Vector2(r*0.12,r*0.25),p+Vector2(r*0.12,r*0.25),Color(color,pulse),width,true)
			canvas.draw_arc(foot,r*0.65,0,PI,12,Color(color,0.8),width,true)
		"poison":
			for i in range(3):
				var t := fposmod(clock*0.85+i/3.0,1.0)
				var p := foot+Vector2(r*(0.65+0.14*sin(clock*3+i)),-r*(0.35+t*1.35))
				drop(canvas,p,maxf(1.6,r*0.115),Color(color,0.92))
				canvas.draw_arc(p+Vector2(r*0.1,-r*0.2),r*(0.14+t*0.12),-PI,0,9,Color(color,0.45*(1.0-t)),width,true)
		"bleed":
			for i in range(3):
				var t := fposmod(clock*1.2+i/3.0,1.0)
				var p := foot+Vector2(-r*(0.4+i*0.13),-r*0.8+r*t*0.95)
				drop(canvas,p,maxf(1.6,r*0.12),Color(color,0.95))
				canvas.draw_line(p-Vector2(0,r*0.23),p-Vector2(0,r*0.08),Color(color,0.65),width,true)
		"lightning":
			for i in range(2):
				var p := torso+Vector2((-1 if i == 0 else 1)*r*0.9,-r*0.4)
				var t := fposmod(clock*2+i*0.43,1.0)
				Vfx.bolt(canvas,p,p+Vector2(r*0.16,r*0.85),Color(color,0.35+0.6*(1.0-t)),width)
		"water":
			for i in range(2):
				var t := fposmod(clock*0.6+i*0.5,1.0)
				drop(canvas,torso+Vector2(r*(i-0.5),r*t),r*0.09,Color(color,0.7))
		"hex":
			var p := head+Vector2(-r*0.55,r*0.25)
			var points := PackedVector2Array([p-Vector2(0,r*0.25),p+Vector2(r*0.18,0),p+Vector2(0,r*0.25),p-Vector2(r*0.18,0),p-Vector2(0,r*0.25)])
			canvas.draw_polyline(points,Color(color,pulse),width,true)
		"buff":
			canvas.draw_arc(head+Vector2(0,r*0.12),r*0.45,PI*1.1,PI*1.9,16,Color(color,pulse),width,true)
			Vfx.cross(canvas,head+Vector2(r*0.5,r*0.1),r*0.13,color,width)
		"stun", "confuse", "dominate":
			for i in range(3):
				var angle := clock*(1.4 if style == "stun" else -1.8)+i*TAU/3
				var p := head+Vector2(cos(angle)*r*0.5,sin(angle)*r*0.16)
				if style == "stun": Vfx.cross(canvas,p,r*0.13,color,width)
				else: canvas.draw_arc(p,r*0.11,0,PI*1.6,8,color,width,true)
		"bind":
			canvas.draw_arc(foot-Vector2(0,r*0.15),r*0.68,0,TAU,20,Color(color,pulse),width,true)
			for i in [-1,1]:
				canvas.draw_polyline(PackedVector2Array([foot+Vector2(i*r*0.6,0),foot+Vector2(i*r*0.3,-r*0.65),foot+Vector2(-i*r*0.3,-r*0.25)]),color,width,true)
		"fracture":
			Vfx.bolt(canvas,torso+Vector2(-r*0.3,-r*0.35),torso+Vector2(r*0.2,r*0.35),Color(color,pulse),width)
		"mark":
			var p := head+Vector2(r*0.6,r*0.2)
			canvas.draw_polyline(PackedVector2Array([p+Vector2(-r*0.16,-r*0.12),p,p+Vector2(r*0.16,-r*0.12)]),Color(color,pulse),width*1.2,true)
		"shield":
			Vfx.shield(canvas,torso+Vector2(-r*0.65,0),r*0.35,Color(color,pulse),width)
		"haste":
			for i in range(2):
				var t := fposmod(clock+i*0.5,1.0)
				var p := foot+Vector2(-r*0.7,-r*t)
				canvas.draw_polyline(PackedVector2Array([p+Vector2(-r*0.14,r*0.14),p,p+Vector2(r*0.14,r*0.14)]),Color(color,0.9-t*0.5),width,true)
