extends Node2D
const Art = preload("res://expedition/mobile_art.gd")
const OUTLINE = preload("res://expedition/actor_outline.gdshader")
var actor: Dictionary = {}
var rect := Rect2()
var tint := Color.WHITE
var boss := false

func _init() -> void:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = OUTLINE
	material = shader_material

func _draw() -> void:
	if actor.is_empty(): return
	if actor.enemy:
		draw_texture_rect(Art.BOSS if boss else Art.ENEMY,rect,false,tint)
	else:
		Art.paint_actor(self,int(actor.id) % Art.ACTORS.size() if actor.get("npc",false) else int(actor.id),rect,tint)
