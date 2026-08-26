extends Node

var game_session: GameSession


func _ready() -> void:
	if game_session == null:
		create_new_game()


func create_new_game() -> GameSession:
	game_session = GameSession.new()
	game_session.new_game()
	return game_session


func load_snapshot(snapshot: Dictionary) -> CommandResult:
	if game_session == null:
		game_session = GameSession.new()
	return game_session.load_game(snapshot)
