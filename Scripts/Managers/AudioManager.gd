extends Node

# --- User Configuration ---
# The time in seconds where the audible part of the music ends.
const LOOP_END_TIME: float = 51.0
# How long the crossfade between tracks should be.
const FADE_DURATION: float = 2.0

# --- Volume Controls ---
@export_group("Volume Settings")
@export_range(-80, 0, 0.1) var master_volume_db: float = 0.0:
	set(value):
		master_volume_db = value
		_update_music_volume()
		_update_sfx_volume()

@export_range(-80, 0, 0.1) var music_volume_db: float = 0.0:
	set(value):
		music_volume_db = value
		_update_music_volume()

@export_range(-80, 0, 0.1) var sfx_volume_db: float = 0.0:
	set(value):
		sfx_volume_db = value
		_update_sfx_volume()

# --- Node References ---
# In the editor, make sure AudioManager has three children:
# 1. AudioStreamPlayer named "MusicPlayerA"
# 2. AudioStreamPlayer named "MusicPlayerB"
# 3. Timer named "LoopTimer"
@onready var music_player_a: AudioStreamPlayer = $MusicPlayerA
@onready var music_player_b: AudioStreamPlayer = $MusicPlayerB
@onready var loop_timer: Timer = $LoopTimer

# --- SFX Pool ---
var sfx_players: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE: int = 10

# --- Private State ---
var _active_player: AudioStreamPlayer
var _music_track = preload("res://Assets/Sounds/music/intense_01.mp3")

# --- SFX Resources (loaded dynamically to avoid import errors) ---
var sfx_card_touch: Array = []
var sfx_single_draw: AudioStream
var sfx_new_round_draw: Array = []
var sfx_single_discard: Array = []
var sfx_all_hands_discard: Array = []
var sfx_swap: AudioStream
var sfx_button_press: AudioStream
var sfx_typing: Array = []
var sfx_card_tap: AudioStream
var sfx_ui_click: AudioStream

func _ready() -> void:
	# Initial setup
	music_player_a.stream = _music_track
	music_player_b.stream = _music_track
	_active_player = music_player_a
	
	# Configure the timer
	# We trigger the fade *before* the loop end time
	loop_timer.wait_time = LOOP_END_TIME - FADE_DURATION
	loop_timer.one_shot = true # We will restart it manually
	loop_timer.timeout.connect(_on_loop_timer_timeout)

	# Register with the global GameManager so it can find this node.
	# Note: This assumes "GameManager" is the name of the autoloaded singleton.
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		game_manager.register_manager("AudioManager", self)
	
	# Initialize SFX pool
	_init_sfx_pool()
	_load_sfx()

func _init_sfx_pool() -> void:
	"""Create a pool of AudioStreamPlayer nodes for playing multiple SFX simultaneously"""
	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		add_child(player)
		sfx_players.append(player)

func _load_sfx() -> void:
	"""Load all SFX resources dynamically"""
	# Load card touch sounds
	for i in range(5):
		var path = "res://Assets/Sounds/sfx/CardTouch0%d.wav" % i
		var sound = load(path)
		if sound:
			sfx_card_touch.append(sound)
	
	# Load other SFX
	sfx_single_draw = load("res://Assets/Sounds/sfx/SingleDraw00.wav")
	sfx_swap = load("res://Assets/Sounds/sfx/Swap00.wav")
	sfx_button_press = load("res://Assets/Sounds/sfx/ButtonPress00.wav")
	sfx_card_tap = load("res://Assets/Sounds/sfx/ESM_Card_Game_Card_Tap_05_Casino_Poker_Deal_Foley_Shuffle_Deck.wav")
	sfx_ui_click = load("res://Assets/Sounds/sfx/ESM_Card_Game_UI_General_Tiny_Metal_01_User_Interface_Tap_Click_Menu_Switch_Button.wav")
	
	# Load arrays
	sfx_new_round_draw.append(load("res://Assets/Sounds/sfx/NewRoundDraw00.wav"))
	sfx_new_round_draw.append(load("res://Assets/Sounds/sfx/NewRoundAutoDraw01.wav"))
	
	sfx_single_discard.append(load("res://Assets/Sounds/sfx/SingleDiscard00.wav"))
	sfx_single_discard.append(load("res://Assets/Sounds/sfx/SingleDiscard01.wav"))
	
	sfx_all_hands_discard.append(load("res://Assets/Sounds/sfx/AllHandsDiscard00.wav"))
	sfx_all_hands_discard.append(load("res://Assets/Sounds/sfx/AllHandsDiscard01.wav"))
	
	sfx_typing.append(load("res://Assets/Sounds/sfx/Typing00.wav"))
	sfx_typing.append(load("res://Assets/Sounds/sfx/Typing01.wav"))

func _get_available_sfx_player() -> AudioStreamPlayer:
	"""Get an available SFX player from the pool"""
	for player in sfx_players:
		if not player.playing:
			return player
	# If all busy, return the first one (it will interrupt)
	return sfx_players[0]

func play_sfx(sound: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	"""Play a sound effect with optional volume and pitch variation"""
	if not sound:
		return
	
	var player = _get_available_sfx_player()
	player.stream = sound
	# Combine the SFX-specific volume with master and category volumes
	player.volume_db = master_volume_db + sfx_volume_db + volume_db
	player.pitch_scale = pitch_scale
	player.play()
	player.play()

func play_random_from_array(sound_array: Array, volume_db: float = 0.0, pitch_variation: float = 0.0) -> void:
	"""Play a random sound from an array with optional pitch variation"""
	if sound_array.is_empty():
		return
	
	var sound = sound_array[randi() % sound_array.size()]
	var pitch = 1.0 + randf_range(-pitch_variation, pitch_variation)
	play_sfx(sound, volume_db, pitch)

# --- Specific SFX Functions ---

func play_card_touch() -> void:
	"""Play a random card touch sound with slight pitch variation"""
	play_random_from_array(sfx_card_touch, -5.0, 0.1)

func play_card_draw() -> void:
	"""Play card draw sound"""
	play_sfx(sfx_single_draw, -3.0, randf_range(0.95, 1.05))

func play_new_round_draw() -> void:
	"""Play new round draw sound"""
	play_random_from_array(sfx_new_round_draw, -2.0, 0.05)

func play_card_discard() -> void:
	"""Play single card discard sound"""
	play_random_from_array(sfx_single_discard, -3.0, 0.1)

func play_all_hands_discard() -> void:
	"""Play sound for discarding all hands"""
	play_random_from_array(sfx_all_hands_discard, -2.0, 0.05)

func play_swap() -> void:
	"""Play swap sound effect"""
	play_sfx(sfx_swap, -3.0)

func play_button_press() -> void:
	"""Play button press sound"""
	play_sfx(sfx_button_press, -5.0)

func play_typing() -> void:
	"""Play typing sound"""
	play_random_from_array(sfx_typing, -8.0, 0.15)

func play_card_tap() -> void:
	"""Play card tap/shuffle sound"""
	play_sfx(sfx_card_tap, -6.0, randf_range(0.9, 1.1))

func play_ui_click() -> void:
	"""Play UI click sound"""
	play_sfx(sfx_ui_click, -8.0)

# --- Volume Control Functions ---

func _update_music_volume() -> void:
	"""Update the volume of all music players"""
	var combined_volume = master_volume_db + music_volume_db
	if music_player_a:
		music_player_a.volume_db = combined_volume
	if music_player_b:
		music_player_b.volume_db = combined_volume

func _update_sfx_volume() -> void:
	"""Update the volume of all SFX players"""
	var combined_volume = master_volume_db + sfx_volume_db
	for player in sfx_players:
		if is_instance_valid(player):
			player.volume_db = combined_volume

func set_master_volume(volume_db: float) -> void:
	"""Set the master volume (affects both music and SFX)"""
	master_volume_db = clamp(volume_db, -80.0, 0.0)

func set_music_volume(volume_db: float) -> void:
	"""Set the music volume"""
	music_volume_db = clamp(volume_db, -80.0, 0.0)

func set_sfx_volume(volume_db: float) -> void:
	"""Set the SFX volume"""
	sfx_volume_db = clamp(volume_db, -80.0, 0.0)

# --- Music Control ---

func start_music() -> void:
	if _active_player and _active_player.playing:
		return # Music is already playing
	
	# Apply volume settings
	_update_music_volume()
	_active_player.play()
	loop_timer.start()

func _on_loop_timer_timeout() -> void:
	# Determine which player is active and which will fade in
	var fading_out_player: AudioStreamPlayer = _active_player
	var fading_in_player: AudioStreamPlayer = music_player_b if _active_player == music_player_a else music_player_a
	
	# Update the active player reference for the next loop
	_active_player = fading_in_player
	
	# Calculate target volume (respecting user volume settings)
	var target_volume = master_volume_db + music_volume_db
	
	# Start the next track silently, ready to be faded in
	fading_in_player.volume_db = -80.0 # Effectively silent
	fading_in_player.play(0) # Play from the beginning
	
	# Create a tween to handle the crossfade
	var tween = create_tween().set_parallel(true)
	
	# Fade the new track in to the target volume
	tween.tween_property(fading_in_player, "volume_db", target_volume, FADE_DURATION)
	# Fade the old track out
	tween.tween_property(fading_out_player, "volume_db", -80.0, FADE_DURATION)
	
	# After the fade is done, stop the old player completely
	await tween.finished
	fading_out_player.stop()
	
	# Restart the timer for the next loop
	loop_timer.start()
