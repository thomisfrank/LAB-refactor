extends Node

# --- Signals ---
signal tray_animation_finished

# --- Properties ---
@export_group("Animation")
@export var slide_duration: float = 0.8
@export var slide_from_x: int = -499  # Start off-screen to the right
@export var slide_to_x: int = 479    # End position (visible on right side)
@export var typing_speed: float = 0.05
@export var new_state_beat_duration: float = 0.8 # Time between typing round and turn

# --- Node References ---
var game_state_tray: Control
var end_round_tray: Control
var end_game_tray: Control
var new_state_tray: Control
var new_state_label: Label

# --- Private State ---
var tween: Tween
var GameManager_GameState: Script # To access the enum

# --- Godot Lifecycle ---

func _ready() -> void:
	# 1. Get nodes
	var main_node = get_node_or_null("/root/main")
	if main_node:
		var front_layer = main_node.get_node_or_null("FrontLayerUI")
		if front_layer:
			game_state_tray = front_layer.get_node_or_null("GameStateTray")

	if not game_state_tray:
		push_error("UIManager: Could not find GameStateTray!")
		return
		
	# Get child trays
	end_round_tray = game_state_tray.get_node_or_null("EndRoundTray")
	end_game_tray = game_state_tray.get_node_or_null("EndGameTray")
	new_state_tray = game_state_tray.get_node_or_null("NewStateTray")
	if new_state_tray:
		new_state_label = new_state_tray.get_node_or_null("StateDisplay/RoundLabel")

	# 2. Register with GameManager and connect signals
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.register_manager("UIManager", self)
		if not gm.is_connected("game_state_changed", Callable(self, "_on_game_state_changed")):
			gm.connect("game_state_changed", Callable(self, "_on_game_state_changed"))
		GameManager_GameState = gm.get_script()

	# 3. Set initial state
	game_state_tray.position.x = slide_from_x
	game_state_tray.visible = false
	if end_round_tray: end_round_tray.visible = false
	if end_game_tray: end_game_tray.visible = false
	if new_state_tray: new_state_tray.visible = false


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
				var round_num = rm.current_round_number
				var turn_text = "Player Turn" # Assuming player starts
				_display_new_state("Round %d" % round_num, turn_text)


# --- Public API ---

func show_tray() -> void:
	if not is_instance_valid(game_state_tray):
		return

	# Ensure it's visible before tweening
	game_state_tray.visible = true

	# Stop any existing animation on this node
	if tween and tween.is_running():
		tween.kill()

	# Create and configure the new tween
	tween = create_tween()
	tween.set_parallel(false) # Run animations sequentially
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.set_ease(Tween.EASE_OUT)

	# Animate the slide-in
	tween.tween_property(game_state_tray, "position:x", slide_to_x, slide_duration)

	# Emit a signal when the animation is complete
	tween.tween_callback(func(): emit_signal("tray_animation_finished", "show"))


## Slides the GameStateTray out of view.
func hide_tray() -> void:
	if not is_instance_valid(game_state_tray):
		return

	# Stop any existing animation
	if tween and tween.is_running():
		tween.kill()

	# Create and configure the new tween
	tween = create_tween()
	tween.set_parallel(false)
	tween.set_trans(Tween.TRANS_SINE) # Use a smoother exit
	tween.set_ease(Tween.EASE_IN)

	# Animate the slide-out
	tween.tween_property(game_state_tray, "position:x", slide_from_x, slide_duration / 2)

	# Hide the node after it has slid out and emit the signal
	tween.tween_callback(func(): 
		game_state_tray.visible = false
		emit_signal("tray_animation_finished", "hide")
	)


# --- Private Helpers ---

func _show_tray_content(tray_node: Control) -> void:
	if not is_instance_valid(tray_node): return
	
	# Hide all other trays
	for tray in [end_round_tray, end_game_tray, new_state_tray]:
		if is_instance_valid(tray) and tray != tray_node:
			tray.visible = false
			
	tray_node.visible = true
	show_tray()

func _display_new_state(round_text: String, turn_text: String) -> void:
	if not is_instance_valid(new_state_label): return

	# Make sure the right tray is visible and slide it in
	_show_tray_content(new_state_tray)
	
	# Start the typing animation sequence
	var seq_tween = create_tween().set_parallel(false)
	seq_tween.tween_callback(func(): _animate_text_type(new_state_label, round_text))
	seq_tween.tween_interval(new_state_beat_duration)
	seq_tween.tween_callback(func(): _animate_text_backspace(new_state_label))
	seq_tween.tween_interval(typing_speed * new_state_label.text.length()) # Wait for backspace to finish
	seq_tween.tween_callback(func(): _animate_text_type(new_state_label, turn_text))
	seq_tween.tween_interval(new_state_beat_duration * 2) # Hold the turn text
	seq_tween.tween_callback(hide_tray)

func _animate_text_type(label: Label, text_to_type: String) -> void:
	var type_tween = create_tween()
	label.text = ""
	type_tween.tween_method(func(s: String): label.text = s, "", text_to_type, typing_speed * text_to_type.length())

func _animate_text_backspace(label: Label) -> void:
	var current_text = label.text
	var bs_tween = create_tween()
	bs_tween.tween_method(func(s: String): label.text = s, current_text, "", typing_speed * current_text.length())
