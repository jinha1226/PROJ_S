extends Node

const GAME_SCENE:="res://game/crawl/game.tscn"
const LEGACY_SCENE:="res://playtest/party_encounter_sandbox.tscn"

func _ready() -> void:
	var prototype := "--prototype-combat" in OS.get_cmdline_user_args()
	var legacy := "--legacy-demo" in OS.get_cmdline_user_args()
	var rebuilt := "--rebuilt-demo" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		legacy = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('demo') === 'legacy'"))
		prototype = bool(JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('prototype') === 'combat'"))
		rebuilt = bool(JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('demo') === 'rebuilt'"))
	var scene_path := "res://prototype/combat_scene.tscn" if prototype \
		else "res://game/rebuilt/game.tscn" if rebuilt \
		else LEGACY_SCENE if legacy \
		else GAME_SCENE
	get_tree().change_scene_to_file.call_deferred(scene_path)
