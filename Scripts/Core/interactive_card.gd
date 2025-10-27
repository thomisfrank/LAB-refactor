extends Node2D

signal discard_animation_complete

@onready var visuals = $VisualsContainer/Visuals
@onready var shadow = $VisualsContainer/Visuals/Shadow
@onready var display_container: SubViewportContainer = $VisualsContainer/Visuals/CardViewport
@onready var card_viewport = $VisualsContainer/Visuals/CardViewport/SubViewport/Card
@onready var card_back = $VisualsContainer/Visuals/CardViewport/SubViewport/Card/CardBack
@onready var card_face = $VisualsContainer/Visuals/CardViewport/SubViewport/Card/CardFace
@onready var lock_icon = $VisualsContainer/LockIcon
@onready var description = $VisualsContainer/description

@export var start_face_up: bool = true
var card_name: String = ""

@export var is_player_card: bool = true
@export_category("Interactions")
@export var max_tilt_angle: float = 20.0
@export var hover_scale: float = 1.1

@export_group("Hover Flourish")
@export var hover_lift_y: float = -60.0  # How much to lift the card up on hover (negative = up)
@export var hover_z_index: int = 1000  # Z-index when hovering (brings card to front)
@export var hover_rotation_straighten: float = 0.65  # How much to straighten rotation (0-1, 1 = fully straight)
@export var hover_flourish_duration: float = 0.35  # Duration of hover animation
@export var hover_flourish_ease: Tween.EaseType = Tween.EASE_OUT
@export var hover_flourish_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var description_hover_delay: float = 1.0  # Seconds before description appears

@export_group("Drag Feel")
@export var drag_smoothing: float = 1.0  # 1.0 = instant, lower = smoother/floatier
@export var drag_lerp_speed: float = 20.0  # Only used if drag_smoothing < 1.0

@export_group("Shadow Control")
@export var shadow_follow_speed: float = 8.0
@export var max_shadow_offset: float = 50.0
@export var shadow_y_offset: float = 15.0
@export var shadow_instant_follow: bool = false  # If true, shadow follows instantly without lerp

@export_group("Display")
@export var display_center_fallback: Vector2 = Vector2(250, 350)  # Used when display_container info is unavailable

@export_group("Idle / Wobble")
@export var wobble_speed: float = 15.0  # How fast the card wobbles back and forth.
@export var wobble_angle: float = 3.0  # The maximum angle in degrees the card will wobble.
@export var wobble_smoothing: float = 5.0  # How quickly the wobble fades in and out. Higher is snappier.
@export var idle_wobble_enabled: bool = true  # Enable gentle wobble when card is idle
@export var idle_wobble_speed: float = 2.0  # Speed of idle wobble oscillation
@export var idle_wobble_angle: float = 1.5  # Maximum angle for idle wobble in degrees
@export var idle_wobble_vertical: float = 5.0  # Vertical movement amount for idle wobble (pixels)
@export var wave_phase_offset: float = 0.8  # Time offset between cards in the wave (higher = more spread out)

@export_group("Flip Animation")
@export var flip_duration: float = 0.25  # Duration of each half of the flip
@export var flip_ease: Tween.EaseType = Tween.EASE_IN_OUT
@export var flip_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var flip_pop_scale: float = 1.05
@export var flip_pop_duration: float = 0.3

var is_mouse_over: bool = false
var is_dragging: bool = false
var is_in_play_area: bool = false
var is_locked: bool = false
var lock_rotation: bool = false
var locked_drop_zone_rotation: float = 0.0  # Stores the rotation set when dropped, for restoration after relayout
var hover_tween: Tween
var prev_global_position: Vector2 = Vector2.ZERO
var drag_offset: Vector2 = Vector2.ZERO
var wobble_time: float = 0.0
var card_index: int = 0

var original_z_index: int = 0
var hover_y_offset: float = 0.0
var description_timer: float = 0.0

var home_position: Vector2 = Vector2.ZERO
var home_rotation: float = 0.0
var snap_back_tween: Tween

@export_category("Per-card Disintegration Override")
@export var use_disintegration_override: bool = false
@export_range(2, 200) var override_pixel_amount: int = 50
@export_range(0.0, 0.5) var override_edge_width: float = 0.04
@export var override_edge_color: Color = Color(1.5, 1.5, 1.5, 1.0)
@export var override_shader_tween_duration: float = 1.5
@export var override_shader_start_progress: float = 0.0
@export var override_shader_target_progress: float = 1.0
@export var override_shader_tween_ease: Tween.EaseType = Tween.EASE_IN
@export var override_shader_tween_trans: Tween.TransitionType = Tween.TRANS_SINE

func _ready() -> void:
	pass
	# Create or ensure a CollisionArea exists in the main scene tree so physics Area overlap works
	# (cards' visuals live in a SubViewport, so put the Area2D on this InteractiveCard node instead)
	if not has_node("CollisionArea"):
		var area = Area2D.new()
		area.name = "CollisionArea"
		# Put area on a default layer that DropZone will also use (adjust if you use layers differently)
		area.collision_layer = 1
		area.collision_mask = 1

		var rect_shape = RectangleShape2D.new()
		# Try to size the shape to the display container size; fallback to a reasonable default
		var shape_size = Vector2(200, 280)
		if display_container and display_container.custom_minimum_size:
			shape_size = display_container.custom_minimum_size
		rect_shape.size = shape_size

		var cs = CollisionShape2D.new()
		cs.shape = rect_shape

		# Position the area to coincide with the visible card center used during dragging.
		# Use computed display center instead of hardcoded magic numbers
		area.position = _get_display_center_offset()

		area.add_child(cs)
		add_child(area)
		# Mark the Area2D itself as a card so DropZone's area.is_in_group("cards") check succeeds.
		area.add_to_group("cards")

	# Also add the InteractiveCard itself to the group in case other code expects it
	add_to_group("cards")
	
	# Note: Don't add to player_hand/opponent_hand groups here - that happens
	# after is_player_card is set by CardManager (see update_hand_group() method)

	prev_global_position = global_position
	# Store original z_index for hover restoration
	original_z_index = z_index
	# Create a unique material instance for this card so shader changes don't affect other cards
	if display_container.material:
		display_container.material = display_container.material.duplicate()
	
	# Set initial card visibility based on export
	if start_face_up:
		card_face.show()
		card_back.hide()
	else:
		card_face.hide()
		card_back.show()

func apply_start_face_up() -> void:
	# Public helper to re-apply start_face_up after instantiation if needed
	if start_face_up:
		if card_face:
			card_face.show()
		if card_back:
			card_back.hide()
	else:
		if card_face:
			card_face.hide()
		if card_back:
			card_back.show()

func update_hand_group() -> void:
	# Update the hand group based on current is_player_card flag
	# Remove from both groups first
	remove_from_group("player_hand")
	remove_from_group("opponent_hand")
	
	# Add to appropriate group
	if is_player_card:
		add_to_group("player_hand")
	else:
		add_to_group("opponent_hand")

func set_card_data(data_name: String) -> void:
	card_name = data_name
	
	if not is_node_ready():
		await ready
	
	if card_viewport and card_viewport.has_method("set_card_data"):
		card_viewport.set_card_data(data_name)
		
		# Update description text if available
		if description and description.has_node("Label"):
			var desc_label = description.get_node("Label")
			# Wait a frame for card_viewport to load the data
			await get_tree().process_frame
			if card_viewport and "card_data" in card_viewport:
				var data = card_viewport.card_data
				if data.has("description"):
					desc_label.text = data["description"]
	else:
		# card_viewport missing set_card_data method; ignore silently
		pass
	
	# Check if signals are connected
	if display_container:
		var mf = display_container.mouse_filter
		var _mf_name = "UNKNOWN"
		if mf == Control.MOUSE_FILTER_STOP:
			_mf_name = "STOP"
		elif mf == Control.MOUSE_FILTER_PASS:
			_mf_name = "PASS"
		elif mf == Control.MOUSE_FILTER_IGNORE:
			_mf_name = "IGNORE"
		if display_container.has_method("get_rect"):
			var _r = display_container.get_rect()

func _process(delta: float) -> void:
	# Run all our per-frame logic
	drag_logic()
	handle_shadow()
	handle_tilt(delta)
	handle_wobble(delta)
	handle_hover_offset()
	handle_description_hover(delta)

func flip_card():
	# Play card flip sound
	var audio_manager = get_node_or_null("/root/main/Managers/AudioManager")
	if audio_manager and audio_manager.has_method("play_card_tap"):
		audio_manager.play_card_tap()
	
	var tween = create_tween().set_ease(flip_ease).set_trans(flip_trans)
	
	var visible_side = card_back if card_back.is_visible() else card_face
	var hidden_side = card_face if card_back.is_visible() else card_back

	tween.tween_property(visible_side, "scale:x", 0.0, flip_duration)
	tween.parallel().tween_property(shadow, "scale:x", 0.0, flip_duration)
	
	tween.tween_callback(func():
		visible_side.hide()
		hidden_side.show()
		hidden_side.scale.x = 0.0
	)
	
	tween.tween_property(hidden_side, "scale:x", 1.0, flip_duration)
	tween.parallel().tween_property(shadow, "scale:x", 1.0, flip_duration)
	
	tween.tween_property(display_container, "scale", Vector2(flip_pop_scale, flip_pop_scale), flip_pop_duration * 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_property(display_container, "scale", Vector2.ONE, flip_pop_duration * 0.5).set_ease(Tween.EASE_IN)

	return tween

func _on_display_mouse_entered() -> void:
	is_mouse_over = true
	description_timer = 0.0  # Reset timer when hover starts
	
	# Play card touch sound on hover
	var audio_manager = get_node_or_null("/root/main/Managers/AudioManager")
	if audio_manager and audio_manager.has_method("play_card_touch") and is_player_card:
		audio_manager.play_card_touch()
	
	# Handle swap selection hover
	if is_selectable_for_swap:
		_on_swap_hover_enter()
		return  # Don't do normal hover effects during swap selection
	
	# Show card info if face up
	if card_face.visible and card_name != "":
		var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
		if info_manager:
			info_manager.show_card_info(card_name)
	
	if not is_dragging:
		# Kill any existing hover tween
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		
		# Bring card to front
		z_index = hover_z_index
		
		# Calculate target rotation (straighten toward 0, but not completely)
		# For opponent cards (which have visuals.rotation = PI), we want to straighten
		# the card's base rotation toward the home rotation, not 0
		var target_rotation = lerp(rotation, home_rotation, hover_rotation_straighten)
		
		# Create smooth hover flourish
		hover_tween = create_tween().set_ease(hover_flourish_ease).set_trans(hover_flourish_trans)
		hover_tween.set_parallel(true)
		
		# Scale up
		hover_tween.tween_property(display_container, "scale", Vector2(hover_scale, hover_scale), hover_flourish_duration)
		
		# Lift up and straighten rotation
		hover_tween.tween_property(self, "hover_y_offset", hover_lift_y, hover_flourish_duration)
		# Only tween rotation if rotation is not locked
		if not lock_rotation:
			hover_tween.tween_property(self, "rotation", target_rotation, hover_flourish_duration)

func _on_display_mouse_exited() -> void:
	is_mouse_over = false
	description_timer = 0.0  # Reset timer when hover ends
	
	# Handle swap selection hover exit
	if is_selectable_for_swap:
		_on_swap_hover_exit()
		return  # Don't do normal hover exit effects during swap selection
	
	# Hide description
	if description:
		description.visible = false
	
	# Clear info screen
	var info_manager = get_node_or_null("/root/main/Managers/InfoScreenManager")
	if info_manager:
		info_manager.clear()
	
	if not is_dragging:
		# Kill any existing hover tween
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		
		# Restore original z_index
		z_index = original_z_index
		
		# Create smooth return animation
		hover_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		hover_tween.set_parallel(true)
		
		# Scale back to normal
		hover_tween.tween_property(display_container, "scale", Vector2.ONE, hover_flourish_duration * 0.8)
		
		# Return to original position and rotation
		hover_tween.tween_property(self, "hover_y_offset", 0.0, hover_flourish_duration * 0.8)
		# Only tween rotation back if rotation is not locked
		if not lock_rotation:
			hover_tween.tween_property(self, "rotation", home_rotation, hover_flourish_duration * 0.8)

# --- Helper Functions ---

func drag_logic() -> void:
	var turn_manager = get_node_or_null("/root/main/Managers/TurnManager")
	if not turn_manager or not turn_manager.get_is_player_turn():
		return
	
	# Handle swap selection click
	if is_mouse_over and Input.is_action_just_pressed("click") and is_selectable_for_swap:
		_on_swap_click()
		return  # Don't start dragging during swap selection
	
	# Only allow dragging for player cards that are not locked
	if is_mouse_over and Input.is_action_just_pressed("click") and is_player_card and not is_locked:
		is_dragging = true
		# Don't update home position here - it's set by CardManager
		
		# Reset hover effects when starting drag
		hover_y_offset = 0.0
		z_index = hover_z_index  # Keep high z-index while dragging
		
		# Calculate offset accounting for where the visuals actually are
		# Use the exact display center (global) instead of hardcoded offsets
		var visual_center = _get_visual_center()
		drag_offset = get_global_mouse_position() - visual_center
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		hover_tween = create_tween().set_ease(Tween.EASE_OUT)
		hover_tween.tween_property(display_container, "scale", Vector2.ONE, 0.2)

	if is_dragging and Input.is_action_just_released("click"):
		is_dragging = false
		# Restore original z_index after drag
		z_index = original_z_index
		# Check if we released over a drop zone
		_check_drop_zones()

	if is_dragging:
		# Target is mouse position minus offset, adjusted back for visual center
		var visual_center_target = get_global_mouse_position() - drag_offset
		var target_position = visual_center_target - _get_display_center_offset()
		if drag_smoothing >= 1.0:
			# Instant/snappy drag
			global_position = target_position
		else:
			# Smooth/floaty drag - lerp_speed and smoothing control responsiveness
			var lerp_weight = clamp(drag_lerp_speed * drag_smoothing * 0.01, 0.0, 0.99)
			global_position = global_position.lerp(target_position, lerp_weight)

func _check_drop_zones() -> void:
	# Check if any drop zones contain our current position
	for zone in get_tree().get_nodes_in_group("drop_zones"):
		if zone.has_method("contains_global_position"):
			if zone.contains_global_position(global_position):
				# Trigger the drop
				if zone.has_method("on_card_dropped"):
					# Snap to the marker position
					zone.on_card_dropped(self, true, true)
				return
	
	# No valid drop zone found - snap back to original position with bounce
	snap_back_to_original_position()


### Utility: compute display/visual center offsets ###
func _get_display_center_offset() -> Vector2:
	# Returns the offset from this node to the center of the display_container
	if display_container and display_container.get_rect:
		var rect = display_container.get_rect()
		# display_container is usually positioned so its top-left is (0,0) inside the card node
		return visuals.position + rect.size * 0.5
	# Fallback to previous magic numbers (keeps old behavior if container missing)
	return visuals.position + Vector2(250, 350)

func _get_visual_center() -> Vector2:
	# Returns the global position of the visible center of the card
	return global_position + _get_display_center_offset()

func set_home_position(pos: Vector2, rot: float) -> void:
	"""Call this to set the card's designated home position in the hand"""
	home_position = pos
	home_rotation = rot

func set_locked(locked: bool) -> void:
	"""Lock or unlock the card. Locked cards cannot be dragged and show a lock icon."""
	is_locked = locked
	if lock_icon:
		lock_icon.visible = locked
	
	# If card is being locked while dragging, cancel the drag
	if is_locked and is_dragging:
		is_dragging = false
		z_index = original_z_index
		snap_back_to_original_position()

func snap_back_to_original_position() -> void:
	if snap_back_tween and snap_back_tween.is_running():
		snap_back_tween.kill()
	
	# Create bouncy snap-back animation
	snap_back_tween = create_tween()
	snap_back_tween.set_parallel(true)
	
	# Bounce back to home position with overshoot
	snap_back_tween.tween_property(self, "global_position", home_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Only tween rotation back if rotation is not locked
	if not lock_rotation:
		snap_back_tween.tween_property(self, "rotation", home_rotation, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Add a little scale bounce for extra juice
	snap_back_tween.tween_property(display_container, "scale", Vector2(1.1, 1.1), 0.25).set_ease(Tween.EASE_OUT)
	snap_back_tween.tween_property(display_container, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_IN).set_delay(0.25)

func handle_shadow() -> void:
	var center_x: float = get_viewport_rect().size.x / 2.0
	var distance_from_center: float = global_position.x - center_x
	var distance_percent: float = distance_from_center / center_x
	
	var target_x = -distance_percent * max_shadow_offset
	
	# Use the shadow_instant_follow export to control behavior
	if shadow_instant_follow:
		# Instant shadow follow (no lerp)
		shadow.position.x = target_x
	else:
		# Smooth shadow follow using shadow_follow_speed
		# Ensure numeric values for lerp
		var from_x = float(shadow.position.x)
		var to_x = float(target_x)
		var w = float(shadow_follow_speed) * get_process_delta_time()
		shadow.position.x = lerp(from_x, to_x, w)
	
	shadow.position.y = shadow_y_offset

func handle_description_hover(delta: float) -> void:
	"""Shows description after hovering for the specified delay duration."""
	if not description:
		return
	
	if is_mouse_over and not is_dragging:
		description_timer += delta
		if description_timer >= description_hover_delay and card_face.visible:
			description.visible = true
	else:
		description_timer = 0.0
		description.visible = false

func handle_tilt(delta: float) -> void:
	var mat = display_container.material as ShaderMaterial
	if not mat:
		return
	if is_mouse_over and not is_dragging:
		var card_size: Vector2 = display_container.size
		var mouse_pos: Vector2 = display_container.get_local_mouse_position()
		var percent_x = (mouse_pos.x / card_size.x) - 0.5
		var percent_y = (mouse_pos.y / card_size.y) - 0.5
		
		var rot_y = percent_x * max_tilt_angle * -2.0
		var rot_x = percent_y * max_tilt_angle * 2.0
		
		mat.set_shader_parameter("y_rot", rot_y)
		mat.set_shader_parameter("x_rot", rot_x)
	else:
		var current_rot_y = mat.get_shader_parameter("y_rot")
		var current_rot_x = mat.get_shader_parameter("x_rot")
		# Coerce shader params to floats or default to 0.0
		if typeof(current_rot_y) == TYPE_INT or typeof(current_rot_y) == TYPE_FLOAT:
			current_rot_y = float(current_rot_y)
		else:
			current_rot_y = 0.0
		if typeof(current_rot_x) == TYPE_INT or typeof(current_rot_x) == TYPE_FLOAT:
			current_rot_x = float(current_rot_x)
		else:
			current_rot_x = 0.0
		mat.set_shader_parameter("y_rot", lerp(current_rot_y, 0.0, delta * 5.0))
		mat.set_shader_parameter("x_rot", lerp(current_rot_x, 0.0, delta * 5.0))

func handle_wobble(delta: float) -> void:
	var velocity = (global_position - prev_global_position) / delta
	var speed = velocity.length()
	
	var resting_rotation_rad = 0.0
	if not is_player_card:
		resting_rotation_rad = PI
	
	if is_in_play_area or lock_rotation:
		# EXPLICITLY reset the visuals rotation (the wobble/idle offset) to the resting rotation.
		# The parent InteractiveCard node holds the randomized tilt for cards in play area.
		if visuals.rotation != resting_rotation_rad:
			visuals.rotation = resting_rotation_rad
		return
	
	var target_rotation_rad = resting_rotation_rad
	
	if speed > 1.0 and is_dragging:
		wobble_time += delta * wobble_speed
		var max_angle_rad = deg_to_rad(wobble_angle)
		var wobble_offset = sin(wobble_time) * max_angle_rad
		target_rotation_rad = resting_rotation_rad + wobble_offset
	
	# Add idle wave effect when card is not being dragged (if enabled)
	elif idle_wobble_enabled and not is_dragging:
		wobble_time += delta * idle_wobble_speed
		var phase = wobble_time + (card_index * wave_phase_offset)
		var idle_max_angle_rad = deg_to_rad(idle_wobble_angle)
		target_rotation_rad = resting_rotation_rad + sin(phase) * idle_max_angle_rad # Wobble *around* the resting rotation

	# Smoothly move the visuals rotation towards the target rotation
	visuals.rotation = lerp_angle(visuals.rotation, target_rotation_rad, delta * wobble_smoothing)
	
	# Update the position for the next frame
	prev_global_position = global_position

func handle_hover_offset() -> void:
	# Apply hover Y offset to lift the card up when hovering (without disrupting home position)
	# This offset is applied to the visuals node rather than global_position to avoid conflicts
	if not is_dragging:
		visuals.position.y = hover_y_offset
		# Also apply to lock icon so it follows the card when hovering
		if lock_icon:
			lock_icon.position.y = hover_y_offset


func _on_flip_pressed() -> void:
	flip_card()


# Called by DropZone to trigger the disintegration effect on this card.
func apply_disintegration(disintegration_shader: Shader, _start_progress: float = 0.0, target_progress: float = 1.0, duration: float = 1.5, ease_type: int = Tween.EASE_IN, trans_type: int = Tween.TRANS_SINE, shader_pixel_amount: int = 50, shader_edge_width: float = 0.04, shader_edge_color: Color = Color(1.5,1.5,1.5,1.0)) -> void:
	# Ensure we have a material we can modify on the display container (SubViewportContainer).
	if not display_container:
		pass
		# print("No display_container on card; cannot apply disintegration.")
		return

	if not disintegration_shader:
		pass
		# print("No disintegration shader provided")
		return

	# Create a new ShaderMaterial with the disintegration shader
	var mat = ShaderMaterial.new()
	mat.shader = disintegration_shader
	
	# Set initial progress from parameter
	mat.set_shader_parameter("progress", _start_progress)
	
	# Apply the material to the display container
	display_container.material = mat

	# Apply shader uniforms (prefer per-card overrides)
	if use_disintegration_override:
		mat.set_shader_parameter("pixel_amount", override_pixel_amount)
		mat.set_shader_parameter("edge_width", override_edge_width)
		mat.set_shader_parameter("edge_color", override_edge_color)
	else:
		mat.set_shader_parameter("pixel_amount", shader_pixel_amount)
		mat.set_shader_parameter("edge_width", shader_edge_width)
		mat.set_shader_parameter("edge_color", shader_edge_color)

	# Animate the shader parameter 'progress' (uses parameters passed from DropZone)
	var tween = create_tween()
	tween.tween_property(mat, "shader_parameter/progress", target_progress, duration).set_ease(ease_type).set_trans(trans_type)
	tween.tween_callback(func():
		# After shader tween completes, either play a 'digital_decay' AnimationPlayer animation
		# and wait for its completion, or immediately add this card to the discard pile.
		if has_node("AnimationPlayer"):
			var ap = $AnimationPlayer
			if ap and ap.has_animation("digital_decay"):
				var cb = Callable(self, "_on_animation_player_animation_finished")
				if not ap.is_connected("animation_finished", cb):
					ap.animation_finished.connect(cb)
				ap.play("digital_decay")
				return
		# Fallback: directly move to discard pile if main provides the API
		_move_to_discard_pile()
	)


func _move_to_discard_pile() -> void:
	"""Helper to move this card to the discard pile via the main scene."""
	var scene_root = get_tree().get_current_scene()
	if scene_root and scene_root.has_method("add_to_discard_pile"):
		# Important: card must still be in the tree when add_to_discard_pile is called
		if is_instance_valid(self) and is_inside_tree():
			scene_root.add_to_discard_pile(self)
			# Emit signal after successfully moving to discard
			emit_signal("discard_animation_complete")
		else:
			pass
			# interactive card invalid or not in tree; freeing
			queue_free()
	else:
		pass
		# main handler not found for discard; freeing card
		queue_free()


func _on_animation_player_animation_finished(anim_name: String) -> void:
	if anim_name == "digital_decay":
		_move_to_discard_pile()

signal card_selected_for_swap(card_node: Node)

var is_selectable_for_swap: bool = false
var swap_overlay: ColorRect = null

func enable_swap_selection() -> void:
	"""Enable this card to be selected for swapping (opponent cards only)"""
	if is_player_card:
		return
	
	is_selectable_for_swap = true
	
	if not swap_overlay:
		swap_overlay = ColorRect.new()
		swap_overlay.name = "SwapOverlay"
		swap_overlay.color = Color(0.906, 0.298, 0.235, 0.0)
		swap_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if visuals:
			visuals.add_child(swap_overlay)
			if display_container:
				swap_overlay.size = display_container.size
				swap_overlay.position = display_container.position


func disable_swap_selection() -> void:
	"""Disable swap selection and remove overlay"""
	is_selectable_for_swap = false
	
	if swap_overlay:
		swap_overlay.queue_free()
		swap_overlay = null
	
	print("[InteractiveCard] Swap selection disabled for card: %s" % card_name)


func _on_swap_hover_enter() -> void:
	"""Show red overlay when hovering during swap selection"""
	if not is_selectable_for_swap or not swap_overlay:
		return
	
	# Fade in red overlay to 40% opacity
	var tween = create_tween()
	tween.tween_property(swap_overlay, "color:a", 0.4, 0.2)


func _on_swap_hover_exit() -> void:
	"""Hide red overlay when not hovering"""
	if not swap_overlay:
		return
	
	# Fade out red overlay
	var tween = create_tween()
	tween.tween_property(swap_overlay, "color:a", 0.0, 0.2)


func _on_swap_click() -> void:
	"""Handle click during swap selection"""
	if not is_selectable_for_swap:
		return
	
	print("[InteractiveCard] Card selected for swap: %s" % card_name)
	emit_signal("card_selected_for_swap", self)
