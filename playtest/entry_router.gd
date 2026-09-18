extends Node

const GAME_SCENE:="res://playtest/party_encounter_sandbox.tscn"
const MODEL_B_SCENE:="res://game/crawl/game.tscn"
const LEGACY_SCENE:="res://playtest/party_encounter_sandbox.tscn"

func _ready() -> void:
	var model_b := "--model-b" in OS.get_cmdline_user_args() or OS.has_feature("model_b")
	var prototype := "--prototype-combat" in OS.get_cmdline_user_args()
	var room_tactics := "--room-tactics" in OS.get_cmdline_user_args()
	var legacy := "--legacy-demo" in OS.get_cmdline_user_args()
	var rebuilt := "--rebuilt-demo" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		model_b = model_b or bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('demo') === 'crawl'"))
		legacy = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('demo') === 'legacy'"))
		room_tactics = bool(JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('prototype') === 'room-tactics'"))
		prototype = bool(JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('prototype') === 'combat'"))
		rebuilt = bool(JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('demo') === 'rebuilt'"))
	var scene_path := "res://prototype/room_tactics_scene.tscn" if room_tactics \
		else "res://prototype/combat_scene.tscn" if prototype \
		else "res://game/rebuilt/game.tscn" if rebuilt \
		else LEGACY_SCENE if legacy \
		else MODEL_B_SCENE if model_b \
		else GAME_SCENE
	get_tree().change_scene_to_file.call_deferred(scene_path)
