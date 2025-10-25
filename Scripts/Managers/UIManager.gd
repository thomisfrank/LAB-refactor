extends Node

# --- Signals ---
signal tray_animation_finished
signal turn_message_finished

# --- Properties ---
@export_group("Slide Animation")
@export var slide_duration: float = 0.8
@export var slide_from_x: int = -499
@export var slide_to_x: int = 479
@export_enum("Linear:0", "Sine:1", "Quint:2", "Quart:3", "Quad:4", "Expo:5", "Elastic:6", "Cubic:7", "Circ:8", "Bounce:9", "Back:10", "Spring:11") var slide_in_trans: int = 9
@export_enum("In:0", "Out:1", "InOut:2", "OutIn:3") var slide_in_ease: int = 1
@export var slide_out_duration: float = 0.4
@export_enum("Linear:0", "Sine:1", "Quint:2", "Quart:3", "Quad:4", "Expo:5", "Elastic:6", "Cubic:7", "Circ:8", "Bounce:9", "Back:10", "Spring:11") var slide_out_trans: int = 1
@export_enum("In:0", "Out:1", "InOut:2", "OutIn:3") var slide_out_ease: int = 0

@export_group("Overlay")
@export var overlay_fade_in_duration: float = 0.3
@export var overlay_fade_out_duration: float = 0.3
@export var overlay_max_alpha: float = 0.7411765

@export_group("Text Animation")
@export var typing_speed: float = 0.05
@export var new_state_beat_duration: float = 0.8
@export var round_display_duration: float = 0.8
@export var turn_display_duration: float = 0.9

# --- Node References ---
var game_state_tray: Control
var end_round_tray: Control
var end_game_tray: Control
var new_state_tray: Control
var new_state_label: Label
var overlay: ColorRect
var player_actions_panel: Node
var opponent_actions_panel: Node
var player_actions_left_label: Node
var opponent_actions_left_label: Node
var player_score_box: Node
var opponent_score_box: Node
var okay_button: TextureButton
var play_again_button: TextureButton
var player_pass_button: TextureButton

# --- Private State ---
var tween: Tween
var GameManager_GameState: Script
var _can_hide_automatically: bool = true

# --- Godot Lifecycle ---
func _ready() -> void:
	var main_node = get_node_or_null("/root/main")
	if main_node:
		var front_layer = main_node.get_node_or_null("FrontLayerUI")
		if front_layer:
			game_state_tray = front_layer.get_node_or_null("GameStateTray")
			overlay = front_layer.get_node_or_null("Overlay")
			
			var ui_panel = front_layer.get_node_or_null("UIPanel")
			if ui_panel:
				player_actions_panel = ui_panel.get_node_or_null("TurnEconomy/PlayerUI")
				opponent_actions_panel = ui_panel.get_node_or_null("TurnEconomy/OpponentUI")
				player_actions_left_label = ui_panel.get_node_or_null("TurnEconomy/PlayerUI/ActionDisplay/ActionsLeftLabel")
				opponent_actions_left_label = ui_panel.get_node_or_null("TurnEconomy/OpponentUI/ActionDisplay/ActionsLeftLabel")
				player_score_box = ui_panel.get_node_or_null("TurnEconomy/PlayerUI/Scorebox")
				opponent_score_box = ui_panel.get_node_or_null("TurnEconomy/OpponentUI/Scorebox")
				
				# Connect the player's pass button
				player_pass_button = ui_panel.get_node_or_null("PanelBG/VBoxContainer/TurnEconomy/PlayerUI/PassButton")
				if player_pass_button and not player_pass_button.is_connected("pressed", Callable(self, "_on_player_pass_pressed")):
					player_pass_button.connect("pressed", Callable(self, "_on_player_pass_pressed"))

	if not game_state_tray:
		push_error("UIManager: Could not find GameStateTray!")
		return
		
	end_round_tray = game_state_tray.get_node_or_null("EndRoundTray")
	end_game_tray = game_state_tray.get_node_or_null("EndGameTray")
	new_state_tray = game_state_tray.get_node_or_null("NewStateTray")
	if new_state_tray:
		new_state_label = new_state_tray.get_node_or_null("StateDisplay/RoundLabel")
		if new_state_label:
			new_state_label.text = ""

	if end_round_tray:
		okay_button = end_round_tray.get_node_or_null("NavButtons/OkayButton")
		if okay_button and not okay_button.is_connected("pressed", Callable(self, "_on_okay_button_pressed")):
			okay_button.connect("pressed", Callable(self, "_on_okay_button_pressed"))
	
	if end_game_tray:
		play_again_button = end_game_tray.get_node_or_null("NavButtons/PlayAgainButton")
		if play_again_button and not play_again_button.is_connected("pressed", Callable(self, "_on_play_again_pressed")):
			play_again_button.connect("pressed", Callable(self, "_on_play_again_pressed"))

	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.register_manager("UIManager", self)
		if not gm.is_connected("game_state_changed", Callable(self, "_on_game_state_changed")):
			gm.connect("game_state_changed", Callable(self, "_on_game_state_changed"))
		GameManager_GameState = gm.get_script()

	game_state_tray.position.x = slide_from_x
	game_state_tray.visible = false
	if end_round_tray: end_round_tray.visible = false
	if end_game_tray: end_game_tray.visible = false
	if new_state_tray: new_state_tray.visible = false
	if overlay: overlay.visible = false


# --- Signal Handlers ---
func _on_game_state_changed(new_state: int) -> void:
	if not GameManager_GameState: return

	var state_name = ""
	match new_state:
		GameManager_GameState.GameState.ROUND_END:
			state_name = "ROUND_END (endround)"
			print("[UIManager] %s - GameStateTray fired for: %s" % [Time.get_ticks_msec(), state_name])
			_show_tray_content(end_round_tray)
		GameManager_GameState.GameState.GAME_OVER:
			state_name = "GAME_OVER (endgame)"
			print("[UIManager] %s - GameStateTray fired for: %s" % [Time.get_ticks_msec(), state_name])
			_show_tray_content(end_game_tray)
		GameManager_GameState.GameState.ROUND_START:
			state_name = "ROUND_START (newstate)"
			print("[UIManager] %s - GameStateTray fired for: %s" % [Time.get_ticks_msec(), state_name])
			var gm = get_node_or_null("/root/GameManager")
			var rm = get_node_or_null("/root/main/Managers/RoundManager")
			if gm and rm:
				var round_num = rm.current_round_number + 1
				var next_starter_is_player: bool = rm.last_starter != GameManager_GameState.Player.PLAYER_ONE
				var turn_text := "Your Turn" if next_starter_is_player else "Opponent's Turn"
				_display_new_state("Round %d" % round_num, turn_text)


# --- Public API ---
func show_tray() -> void:
	if not is_instance_valid(game_state_tray): return

	print("[UIManager] %s - show_tray called, making game_state_tray visible" % Time.get_ticks_msec())

	if overlay:
		overlay.visible = true
		var overlay_color = overlay.color
		overlay.color = Color(overlay_color.r, overlay_color.g, overlay_color.b, 0.0)
		var overlay_tween = create_tween()
		overlay_tween.tween_property(overlay, "color:a", overlay_max_alpha, overlay_fade_in_duration)

	game_state_tray.visible = true

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.set_parallel(false)
	tween.set_trans(slide_in_trans)
	tween.set_ease(slide_in_ease)
	tween.tween_property(game_state_tray, "position:x", slide_to_x, slide_duration)
	tween.tween_callback(func(): emit_signal("tray_animation_finished", "show"))


func hide_tray(force: bool = false) -> void:
	if not _can_hide_automatically and not force:
		print("[UIManager] %s - hide_tray called but blocked (_can_hide_automatically=false, force=%s)" % [Time.get_ticks_msec(), force])
		return
		
	if not is_instance_valid(game_state_tray):
		return

	print("[UIManager] %s - GameStateTray hiding (going back)" % Time.get_ticks_msec())

	if overlay:
		var overlay_tween = create_tween()
		overlay_tween.tween_property(overlay, "color:a", 0.0, overlay_fade_out_duration)
		overlay_tween.tween_callback(func(): overlay.visible = false)

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.set_parallel(false)
	tween.set_trans(slide_out_trans)
	tween.set_ease(slide_out_ease)
	tween.tween_property(game_state_tray, "position:x", slide_from_x, slide_out_duration)
	tween.tween_callback(func():
		game_state_tray.visible = false
		emit_signal("tray_animation_finished", "hide")
	)


# --- Private Helpers ---
func _show_tray_content(tray_node: Control) -> void:
	if not is_instance_valid(tray_node): return
	
	var tray_type = "unknown"
	if tray_node == new_state_tray:
		tray_type = "newstate"
	elif tray_node == end_round_tray:
		tray_type = "endround"
	elif tray_node == end_game_tray:
		tray_type = "endgame"
	
	print("[UIManager] %s - Showing tray content: %s" % [Time.get_ticks_msec(), tray_type])
	
	for tray in [end_round_tray, end_game_tray, new_state_tray]:
		if is_instance_valid(tray) and tray != tray_node:
			tray.visible = false
			
	tray_node.visible = true
	show_tray()

	# Control when it hides
	if tray_node == new_state_tray:
		_can_hide_automatically = true
	else:
		_can_hide_automatically = false


func _display_new_state(round_text: String, turn_text: String) -> void:
	if not is_instance_valid(new_state_label): return

	new_state_label.text = ""
	new_state_label.visible_characters = 0

	_show_tray_content(new_state_tray)

	if tween:
		tween.tween_callback(func(): _start_typing_sequence(round_text, turn_text))
	else:
		_start_typing_sequence(round_text, turn_text)


func _start_typing_sequence(round_text: String, turn_text: String) -> void:
	if not is_instance_valid(new_state_label): return

	var seq_tween = create_tween().set_parallel(false)

	# Type Round X
	seq_tween.tween_callback(func():
		new_state_label.text = round_text
		new_state_label.visible_characters = 0
	)
	seq_tween.tween_property(new_state_label, "visible_characters", round_text.length(), typing_speed * round_text.length()).set_trans(Tween.TRANS_LINEAR)
	seq_tween.tween_interval(round_display_duration)

	# Backspace
	seq_tween.tween_property(new_state_label, "visible_characters", 0, typing_speed * round_text.length()).set_trans(Tween.TRANS_LINEAR)

	# Type Turn Text
	seq_tween.tween_callback(func():
		new_state_label.text = turn_text
		new_state_label.visible_characters = 0
	)
	seq_tween.tween_property(new_state_label, "visible_characters", turn_text.length(), typing_speed * turn_text.length()).set_trans(Tween.TRANS_LINEAR)
	seq_tween.tween_interval(turn_display_duration)

	# Auto hide tray
	seq_tween.tween_callback(hide_tray)


# --- Score & Button Functions ---
func update_scores(scores: Dictionary) -> void:
	var p1_score = scores.get(0, 0)
	var p2_score = scores.get(1, 0)
	var p1_digits = _format_digits(p1_score, 3)
	var p2_digits = _format_digits(p2_score, 3)

	if player_score_box:
		var d1 = player_score_box.get_node_or_null("#__")
		var d2 = player_score_box.get_node_or_null("_#_")
		var d3 = player_score_box.get_node_or_null("__#")
		if d1: d1.text = str(p1_digits[0])
		if d2: d2.text = str(p1_digits[1])
		if d3: d3.text = str(p1_digits[2])

	if opponent_score_box:
		var od1 = opponent_score_box.get_node_or_null("#__")
		var od2 = opponent_score_box.get_node_or_null("_#_")
		var od3 = opponent_score_box.get_node_or_null("__#")
		if od1: od1.text = str(p2_digits[0])
		if od2: od2.text = str(p2_digits[1])
		if od3: od3.text = str(p2_digits[2])


func _format_digits(value: int, length: int) -> Array:
	var s = str(value)
	while s.length() < length:
		s = "0" + s
	var out: Array = []
	for i in range(length):
		out.append(s[i])
	return out


func _on_okay_button_pressed() -> void:
	hide_tray(true)
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("continue_to_next_round"):
		gm.continue_to_next_round()


func _on_play_again_pressed() -> void:
	hide_tray(true)
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("restart_game"):
		gm.restart_game()


func _on_player_pass_pressed() -> void:
	print("[UIManager] Player pass button pressed")
	var gm = get_node_or_null("/root/GameManager")
	var tm = null
	if gm and gm.has_method("get_manager"):
		tm = gm.get_manager("TurnManager")
	if not tm:
		tm = get_node_or_null("/root/main/Managers/TurnManager")
	
	if tm and tm.has_method("pass_current_player"):
		tm.pass_current_player()
	else:
		push_error("UIManager: TurnManager not found or missing pass_current_player method")


func set_pass_button_enabled(enabled: bool) -> void:
	if player_pass_button:
		player_pass_button.disabled = not enabled
		print("[UIManager] Pass button %s" % ("enabled" if enabled else "disabled"))


func show_turn_message(is_player_turn: bool) -> void:
	if not is_instance_valid(new_state_label): return
	
	var turn_text := "Your Turn" if is_player_turn else "Opponent's Turn"
	print("[UIManager] %s - Showing turn message: %s" % [Time.get_ticks_msec(), turn_text])
	
	new_state_label.text = turn_text
	new_state_label.visible_characters = 0
	
	_show_tray_content(new_state_tray)
	
	# Wait for the slide-in animation to finish, then start typing
	if tween:
		tween.tween_callback(func():
			var seq_tween = create_tween().set_parallel(false)
			seq_tween.tween_property(new_state_label, "visible_characters", turn_text.length(), typing_speed * turn_text.length()).set_trans(Tween.TRANS_LINEAR)
			seq_tween.tween_interval(turn_display_duration)
			seq_tween.tween_callback(func():
				hide_tray()
				emit_signal("turn_message_finished")
			)
		)


func show_end_round_screen(winner: int, player_total: int, opponent_total: int, player_cards_info: Array = [], opponent_cards_info: Array = []) -> void:
	print("[UIManager] %s - show_end_round_screen called (winner=%s)" % [Time.get_ticks_msec(), winner])
	# The EndRoundTray is shown by _on_game_state_changed when ROUND_END fires
	# This method is called by GameManager to populate the tray with data
	# For now, just ensure the tray stays visible
	# TODO: Populate EndRoundTray with card info and totals


func await_end_round_close() -> void:
	print("[UIManager] %s - await_end_round_close: waiting for user to close end round tray" % Time.get_ticks_msec())
	# Wait for the okay button to be pressed
	# The okay button calls hide_tray(true) which will close the tray
	# We need to wait for that to happen
	if not end_round_tray or not end_round_tray.visible:
		return
	
	# Wait for the tray to be hidden
	while end_round_tray.visible:
		await get_tree().process_frame
	
	print("[UIManager] %s - End round tray closed by user" % Time.get_ticks_msec())


func show_game_over_screen(winner: int, winner_score: int) -> void:
	print("[UIManager] %s - show_game_over_screen called (winner=%s, score=%s)" % [Time.get_ticks_msec(), winner, winner_score])
	# The EndGameTray is shown by _on_game_state_changed when GAME_OVER fires
	# This method is called by GameManager to populate the tray with data
	# TODO: Populate EndGameTray with winner info and final score
