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
@export var ui_panel_fade_alpha: float = 0.3
@export var ui_panel_fade_duration: float = 0.3

@export_group("Text Animation")
@export var typing_speed: float = 0.05
@export var new_state_beat_duration: float = 0.8
@export var round_display_duration: float = 0.8
@export var turn_display_duration: float = 0.9

@export_group("Button Dust Effect")
@export var dust_particle_count: int = 8
@export var dust_particle_size: float = 4.0
@export var dust_lifetime: float = 0.5
@export var dust_color: Color = Color(0.9, 0.9, 0.8, 0.8)

# --- Node References ---
var game_state_tray: Control
var end_round_tray: Control
var end_game_tray: Control
var new_state_tray: Control
var new_state_label: Label
var overlay: ColorRect
var ui_panel: Control
var player_actions_panel: Node
var opponent_actions_panel: Node
var player_actions_left_label: Node
var opponent_actions_left_label: Node
var player_score_box: Node
var opponent_score_box: Node
var okay_button: TextureButton
var play_again_button: TextureButton
var player_pass_button: TextureButton

# --- Runtime flags ---
var tray_active: bool = false

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
			
			ui_panel = front_layer.get_node_or_null("UIPanel")
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
	
	# Ensure both player/opponent UI start at the same opacity (will be updated when tray shows)
	# This prevents one side from being fully visible at game start
	call_deferred("_sync_initial_ui_opacity")


func _sync_initial_ui_opacity() -> void:
	# If the game state tray will be shown at start, ensure both sides are faded equally
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_manager"):
		var tm = gm.get_manager("TurnManager")
		if tm and tm.has_method("_update_ui_opacity"):
			tm._update_ui_opacity()


# --- Signal Handlers ---
func _on_game_state_changed(new_state: int) -> void:
	if not GameManager_GameState: return

	match new_state:
		GameManager_GameState.GameState.ROUND_END:
			_show_tray_content(end_round_tray)
		GameManager_GameState.GameState.GAME_OVER:
			_show_tray_content(end_game_tray)
		GameManager_GameState.GameState.ROUND_START:
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

	if overlay:
		overlay.visible = true
		var overlay_color = overlay.color
		overlay.color = Color(overlay_color.r, overlay_color.g, overlay_color.b, 0.0)
		var overlay_tween = create_tween()
		overlay_tween.tween_property(overlay, "color:a", overlay_max_alpha, overlay_fade_in_duration)

	# Fade out the UI panel when tray is shown
	if ui_panel:
		var ui_tween = create_tween()
		ui_tween.tween_property(ui_panel, "modulate:a", ui_panel_fade_alpha, ui_panel_fade_duration)

	# Make the tray visible first so TurnManager sees the correct state
	# mark tray active (avoid timing issues reading visible)
	tray_active = true
	game_state_tray.visible = true

	# Update TurnManager to fade both sides equally when tray is visible
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("get_manager"):
		var tm = gm.get_manager("TurnManager")
		if tm and tm.has_method("_update_ui_opacity"):
			print("UIManager: show_tray -> calling TurnManager._update_ui_opacity()")
			tm._update_ui_opacity()

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
		return
		
	if not is_instance_valid(game_state_tray):
		return

	if overlay:
		var overlay_tween = create_tween()
		overlay_tween.tween_property(overlay, "color:a", 0.0, overlay_fade_out_duration)
		overlay_tween.tween_callback(func(): overlay.visible = false)

	# Fade in the UI panel when tray is hidden
	if ui_panel:
		var ui_tween = create_tween()
		ui_tween.tween_property(ui_panel, "modulate:a", 1.0, ui_panel_fade_duration)

	# Note: delay restoring TurnManager opacity until the tray is fully hidden (see tween callback)

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
		# mark tray inactive and then notify TurnManager to restore opacities and action UI
		tray_active = false
		var gm = get_node_or_null("/root/GameManager")
		if gm and gm.has_method("get_manager"):
			var tm = gm.get_manager("TurnManager")
			if tm:
				if tm.has_method("_update_ui_opacity"):
					print("UIManager: tween finished -> calling TurnManager._update_ui_opacity()")
					tm._update_ui_opacity()
				if tm.has_method("_update_action_ui"):
					print("UIManager: tween finished -> calling TurnManager._update_action_ui()")
					tm._update_action_ui()
	)


# --- Private Helpers ---
func _show_tray_content(tray_node: Control) -> void:
	if not is_instance_valid(tray_node): return
	
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


# Helper function to create dust effect on button press
func _create_button_dust_effect(button: Control) -> void:
	if not button:
		return
	
	# Get button center position and size
	var center_pos = Vector2.ZERO
	var button_size = Vector2.ZERO
	if button.has_method("get_global_rect"):
		var gr = button.get_global_rect()
		center_pos = gr.position + gr.size * 0.5
		button_size = gr.size
	elif "global_position" in button:
		center_pos = button.global_position
		if "size" in button:
			button_size = button.size
	
	# Calculate corners relative to center
	var half_width = button_size.x * 0.5
	var half_height = button_size.y * 0.5
	var corners = [
		Vector2(-half_width, -half_height),  # Top-left
		Vector2(half_width, -half_height),   # Top-right
		Vector2(-half_width, half_height),   # Bottom-left
		Vector2(half_width, half_height)     # Bottom-right
	]
	
	# Create dust particles at each corner
	for corner in corners:
		for i in range(2):  # 2 particles per corner
			var dust = ColorRect.new()
			
			# Try to add to FrontLayerUI if available, otherwise use current node
			var front_layer = get_node_or_null("/root/main/FrontLayerUI")
			if front_layer:
				front_layer.add_child(dust)
			else:
				add_child(dust)
			
			# Setup dust particle
			dust.size = Vector2(dust_particle_size, dust_particle_size)
			dust.color = dust_color
			dust.global_position = center_pos + corner
			dust.z_index = 10
			
			# Animate dust particle
			var dust_tween = create_tween()
			dust_tween.set_parallel(true)
			
			# Random direction outward from corner
			var angle = randf_range(-PI/4, PI/4) + atan2(corner.y, corner.x)
			var direction = Vector2(cos(angle), sin(angle))
			var distance = randf_range(30, 60)
			var target_pos = dust.global_position + direction * distance
			
			# Animate position and fade
			dust_tween.tween_property(dust, "global_position", target_pos, dust_lifetime)
			dust_tween.tween_property(dust, "modulate:a", 0.0, dust_lifetime)
			
			# Clean up particle when done
			dust_tween.finished.connect(func(): dust.queue_free())


func _on_okay_button_pressed() -> void:
	_create_button_dust_effect(okay_button)
	hide_tray(true)
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("continue_to_next_round"):
		gm.continue_to_next_round()


func _on_play_again_pressed() -> void:
	_create_button_dust_effect(play_again_button)
	hide_tray(true)
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("restart_game"):
		gm.restart_game()


func _on_player_pass_pressed() -> void:
	_create_button_dust_effect(player_pass_button)
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


func show_turn_message(is_player_turn: bool) -> void:
	if not is_instance_valid(new_state_label): return
	
	var turn_text := "Your Turn" if is_player_turn else "Opponent's Turn"
	
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


func show_end_round_screen(_winner: int, _player_total: int, _opponent_total: int, _player_cards_info: Array = [], _opponent_cards_info: Array = []) -> void:
	pass


func await_end_round_close() -> void:
	# Wait for the okay button to be pressed
	if not end_round_tray or not end_round_tray.visible:
		return
	
	# Wait for the tray to be hidden
	while end_round_tray.visible:
		await get_tree().process_frame


func show_game_over_screen(_winner: int, _winner_score: int) -> void:
	pass
