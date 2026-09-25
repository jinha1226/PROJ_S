extends Node2D
const Art = preload("res://expedition/art/mobile_art.gd")
var actor: Dictionary = {}
var rect := Rect2()
var tint := Color.WHITE
var boss := false

func _draw() -> void:
	if actor.is_empty(): return
	if actor.enemy:
		if boss: Art.paint_boss(self,rect,tint)
		else: Art.paint_monster(self,str(actor.get("species_id","kobold")),rect,tint)
	else:
		Art.paint_actor(self,int(actor.id) % Art.ACTOR_IDS.size() if actor.get("npc",false) else int(actor.id),rect,tint)
