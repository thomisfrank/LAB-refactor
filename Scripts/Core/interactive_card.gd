# [interactive_card.gd] (Corrected)
extends Node2D

signal card_was_clicked(card_node: Node2D)
signal disintegration_finished
signal moved_to_discard

# --- Node References & Exports ---
@onready var visuals: Node2D = $Visuals
@onready var shadow: Sprite2D = $Visuals/Shadow
@onready var display_container: SubViewportContainer = $Visuals/CardViewport
@onready var card_viewport: Node = $Visuals/CardViewport/SubViewport/Card
@onready var card_back: Node2D = $Visuals/CardViewport/SubViewport/Card/CardBack
@onready var card_face: Node2D = $Visuals/CardViewport/SubViewport/Card/CardFace
@onready var lock_icon: CanvasItem = $Visuals/LockedState
@onready var SelectOutline: ColorRect = $Visuals/SelectOutline

# --- Card Appearance ---
@export var start_face_up: bool = true
var card_name: StringName = ""

# --- Card Ownership ---
@export var is_player_card: bool = true
@export var is_draggable: bool = true

# --- Interactions ---
@export_category("Interactions")
@export var max_tilt_angle: float = 20.0
@export var hover_scale: float = 1.1

@export_group("Hover Flourish")
@export var hover_lift_y: float = -60.0
@export var hover_z_index: int = 1000
@export var hover_rotation_straighten: float = 0.65
@export var hover_flourish_duration: float = 0.35
@export var hover_flourish_ease: Tween.EaseType = Tween.EASE_OUT
@export var hover_flourish_trans: Tween.TransitionType = Tween.TRANS_CUBIC

# ... (all other exports are unchanged) ...
@export_group("Drag Feel")
@export var drag_smoothing: float = 1.0
@export var drag_lerp_speed: float = 20.0

@export_group("Shadow Control")
@export var shadow_follow_speed: float = 8.0
@export var max_shadow_offset: float = 50.0
@export var shadow_y_offset: float = 15.0
@export var shadow_instant_follow: bool = false

@export_group("Display")
@export var display_center_fallback: Vector2 = Vector2(250, 350)

@export_group("Idle / Wobble")
@export var wobble_speed: float = 15.0
@export var wobble_angle: float = 3.0
@export var wobble_smoothing: float = 5.0
@export var idle_wobble_enabled: bool = true
@export var idle_wobble_speed: float = 2.0
@export var idle_wobble_angle: float = 1.5
@export var idle_wobble_vertical: float = 5.0
@export var wave_phase_offset: float = 0.8

@export_group("Flip Animation")
@export var flip_duration: float = 0.25
@export var flip_ease: Tween.EaseType = Tween.EASE_IN_OUT
@export var flip_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var flip_pop_scale: float = 1.05
@export var flip_pop_duration: float = 0.3

# --- State Variables ---
var is_mouse_over: bool = false
var is_dragging: bool = false
var is_locked: bool = false
var hover_tween: Tween
var prev_global_position: Vector2 = Vector2.ZERO
var drag_offset: Vector2 = Vector2.ZERO
var wobble_time: float = 0.0
var card_index: int = 0
var card_data: Dictionary = {}

var original_z_index: int = 0
var hover_y_offset: float = 0.0

# --- Snap back variables ---
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


# --- Godot Functions ---

func _ready() -> void:
	# This logic for adding a CollisionArea is preserved
	if not has_node("CollisionArea"):
		var area := Area2D.new()
		area.name = "CollisionArea"
		area.collision_layer = 1
		area.collision_mask = 1

		var rect_shape := RectangleShape2D.new()
		var shape_size: Vector2 = Vector2(200, 280)
		if is_instance_valid(display_container) and display_container.custom_minimum_size != Vector2.ZERO:
			shape_size = display_container.custom_minimum_size
		rect_shape.size = shape_size

		var cs := CollisionShape2D.new()
		cs.shape = rect_shape
		area.position = _get_display_center_offset()

		area.add_child(cs)
		add_child(area)
		area.add_to_group("cards")

	add_to_group("cards")

	if is_instance_valid(lock_icon):
		lock_icon.visible = false
	if is_instance_valid(SelectOutline):
		SelectOutline.hide()

	prev_global_position = global_position
	original_z_index = z_index
	
	if is_instance_valid(display_container) and display_container.material:
		display_container.material = display_container.material.duplicate()
	
	apply_start_face_up()

## Handles clicks on the main node.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		emit_signal("card_was_clicked", self)
		
		# We still check for drag start here, but drag_logic() will enforce turn/lock state
		if is_draggable and is_player_card:
			is_dragging = true

func _process(delta: float) -> void:
	drag_logic()
	handle_shadow()
	handle_tilt(delta)
	handle_wobble(delta)
	handle_hover_offset()

## Public helper to re-apply start_face_up after instantiation if needed
func apply_start_face_up() -> void:
	if start_face_up:
		if is_instance_valid(card_face): card_face.show()
		if is_instance_valid(card_back): card_back.hide()
	else:
		if is_instance_valid(card_face): card_face.hide()
		if is_instance_valid(card_back): card_back.show()

## Sets card data from CardDataLoader and applies it to the visual sub-scene.
func set_card_data(data_name: StringName) -> void:
	card_name = data_name
	
	if not is_node_ready():
		await ready
	
	if is_instance_valid(card_viewport) and card_viewport.has_method("set_card_data"):
		card_viewport.set_card_data(data_name)

	# Use global CardDataLoader (which is confirmed)
	if is_instance_valid(CardDataLoader):
		card_data = CardDataLoader.get_card_data(data_name)
	else:
		card_data = {}
		push_error("InteractiveCard: CardDataLoader global not found.")
	
	if not is_instance_valid(display_container):
		return

	# Connect signals for hover/click
	var enter_callable := Callable(self, "_on_display_mouse_entered")
	if not display_container.is_connected("mouse_entered", enter_callable):
		display_container.mouse_entered.connect(enter_callable)
		
	var exit_callable := Callable(self, "_on_display_mouse_exited")
	if not display_container.is_connected("mouse_exited", exit_callable):
		display_container.mouse_exited.connect(exit_callable)

	var gui_callable := Callable(self, "_on_display_gui_input")
	if not display_container.is_connected("gui_input", gui_callable):
		display_container.gui_input.connect(gui_callable)


## Flips the card from front-to-back or back-to-front.
func flip_card() -> Tween:
	var tween: Tween = create_tween().set_ease(flip_ease).set_trans(flip_trans)
	
	var visible_side: Node2D = card_back if card_back.is_visible() else card_face
	var hidden_side: Node2D = card_face if card_back.is_visible() else card_back

	# Part 1: First Half of Flip (Card AND Shadow)
	tween.tween_property(visible_side, "scale:x", 0.0, flip_duration)
	if is_instance_valid(shadow):
		tween.parallel().tween_property(shadow, "scale:x", 0.0, flip_duration)
	
	# Part 2: The Swap
	tween.tween_callback(func():
		visible_side.hide()
		hidden_side.show()
		hidden_side.scale.x = 0.0
	)
	
	# Part 3: Second Half of Flip (Card AND Shadow)
	tween.tween_property(hidden_side, "scale:x", 1.0, flip_duration)
	if is_instance_valid(shadow):
		tween.parallel().tween_property(shadow, "scale:x", 1.0, flip_duration)
	
	# Part 4: Pop effect
	if is_instance_valid(display_container):
		tween.tween_property(display_container, "scale", Vector2.ONE * flip_pop_scale, flip_pop_duration * 0.5).set_ease(Tween.EASE_OUT)
		tween.tween_property(display_container, "scale", Vector2.ONE, flip_pop_duration * 0.5).set_ease(Tween.EASE_IN)

	return tween

# --- Signal Handlers ---

func _on_display_mouse_entered() -> void:
	is_mouse_over = true
	
	# Use global InfoScreenManager (which is confirmed)
	if card_face.visible and card_name != "" and is_instance_valid(InfoScreenManager):
		InfoScreenManager.show_card_info(card_name)
	
	if not is_dragging:
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		
		z_index = hover_z_index
		var target_rotation: float = lerp(rotation, home_rotation, hover_rotation_straighten)
		
		hover_tween = create_tween().set_ease(hover_flourish_ease).set_trans(hover_flourish_trans)
		hover_tween.set_parallel(true)
		if is_instance_valid(display_container):
			hover_tween.tween_property(display_container, "scale", Vector2.ONE * hover_scale, hover_flourish_duration)
		hover_tween.tween_property(self, "hover_y_offset", hover_lift_y, hover_flourish_duration)
		hover_tween.tween_property(self, "rotation", target_rotation, hover_flourish_duration)

func _on_display_mouse_exited() -> void:
	is_mouse_over = false
	
	# Use global InfoScreenManager (which is confirmed)
	if is_instance_valid(InfoScreenManager):
		InfoScreenManager.clear()
	
	if not is_dragging:
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		
		z_index = original_z_index
		
		hover_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		hover_tween.set_parallel(true)
		if is_instance_valid(display_container):
			hover_tween.tween_property(display_container, "scale", Vector2.ONE, hover_flourish_duration * 0.8)
		hover_tween.tween_property(self, "hover_y_offset", 0.0, hover_flourish_duration * 0.8)
		hover_tween.tween_property(self, "rotation", home_rotation, hover_flourish_duration * 0.8)

## Handles clicks that happen inside the SubViewport's area.
func _on_display_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("card_was_clicked", self)

## Called when the card_was_clicked signal is emitted.
func _on_card_clicked() -> void:
	# Use global GameManager (which is confirmed)
	if not is_instance_valid(GameManager):
		return

	if GameManager.has_method("is_in_selection_mode") and GameManager.is_in_selection_mode:
		if GameManager.has_method("resolve_selection"):
			GameManager.resolve_selection(self)
			is_dragging = false # Prevent starting drag on selection clicks

# --- Helper Functions ---

func drag_logic() -> void:
	# Use global GameManager
	if not is_instance_valid(GameManager):
		return
		
	# --- THIS IS THE FIX ---
	# Find TurnManager in the scene tree, as it's not global
	var turn_manager: Node = get_node_or_null("/root/main/Managers/TurnManager")
	
	if (GameManager.has_method("is_in_selection_mode") and GameManager.is_in_selection_mode) or \
	   (not is_instance_valid(turn_manager) or not turn_manager.get_is_player_turn()):
		is_dragging = false # Ensure dragging stops if turn ends
		return
	# --- END OF FIX ---

	if is_mouse_over and Input.is_action_just_pressed("click") and is_player_card and _can_drag():
		is_dragging = true
		GameManager.emit_signal("drag_started")
		
		hover_y_offset = 0.0
		z_index = hover_z_index
		
		var visual_center: Vector2 = _get_visual_center()
		drag_offset = get_global_mouse_position() - visual_center
		
		if hover_tween and hover_tween.is_running():
			hover_tween.kill()
		hover_tween = create_tween().set_ease(Tween.EASE_OUT)
		if is_instance_valid(display_container):
			hover_tween.tween_property(display_container, "scale", Vector2.ONE, 0.2)

	if is_dragging and Input.is_action_just_released("click"):
		is_dragging = false
		z_index = original_z_index
		_check_drop_zones()
		GameManager.emit_signal("drag_ended")

	if is_locked and is_dragging:
		is_dragging = false
		snap_back_to_original_position()
		GameManager.emit_signal("drag_ended")

	if is_dragging:
		var visual_center_target: Vector2 = get_global_mouse_position() - drag_offset
		var target_position: Vector2 = visual_center_target - _get_display_center_offset()
		if drag_smoothing >= 1.0:
			global_position = target_position
		else:
			var lerp_weight: float = clamp(drag_lerp_speed * drag_smoothing * 0.01, 0.0, 0.99)
			global_position = global_position.lerp(target_position, lerp_weight)

func _check_drop_zones() -> void:
	for zone in get_tree().get_nodes_in_group("drop_zones"):
		if zone.has_method("contains_global_position"):
			if zone.contains_global_position(global_position):
				if zone.has_method("on_card_dropped"):
					zone.on_card_dropped(self)
				return
	
	snap_back_to_original_position()

func _get_display_center_offset() -> Vector2:
	if is_instance_valid(display_container):
		var rect: Rect2 = display_container.get_rect()
		return visuals.position + rect.size * 0.5
	return visuals.position + display_center_fallback

func _get_visual_center() -> Vector2:
	return global_position + _get_display_center_offset()

## Sets the card's designated home position in the hand.
func set_home_position(pos: Vector2, rot: float) -> void:
	home_position = pos
	home_rotation = rot

## Locks or unlocks the card, toggling its visual and draggability.
func set_locked(locked_state: bool) -> void:
	is_locked = locked_state
	if is_instance_valid(lock_icon):
		lock_icon.visible = is_locked
		if is_locked:
			lock_icon.z_index = 4096
			lock_icon.modulate = Color.WHITE
		
## Enables/disables the hover-to-select outline.
func set_peek_hover_enabled(is_enabled: bool) -> void:
	if not is_instance_valid(SelectOutline) or not is_instance_valid(display_container):
		return

	var enter_callable := Callable(SelectOutline, "show")
	var exit_callable := Callable(SelectOutline, "hide")

	if is_enabled:
		if not display_container.is_connected("mouse_entered", enter_callable):
			display_container.mouse_entered.connect(enter_callable)
		if not display_container.is_connected("mouse_exited", exit_callable):
			display_container.mouse_exited.connect(exit_callable)
	else:
		if display_container.is_connected("mouse_entered", enter_callable):
			display_container.mouse_entered.disconnect(enter_callable)
		if display_container.is_connected("mouse_exited", exit_callable):
			display_container.mouse_exited.disconnect(exit_callable)
		SelectOutline.hide()

	if is_locked:
		is_dragging = false
		display_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		display_container.mouse_filter = Control.MOUSE_FILTER_PASS

func _can_drag() -> bool:
	if is_locked or not is_player_card:
		return false
	return true

## Snaps the card back to its home position with a bounce.
func snap_back_to_original_position() -> void:
	if snap_back_tween and snap_back_tween.is_running():
		snap_back_tween.kill()
	
	snap_back_tween = create_tween()
	snap_back_tween.set_parallel(true)
	snap_back_tween.tween_property(self, "global_position", home_position, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	snap_back_tween.tween_property(self, "rotation", home_rotation, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	if is_instance_valid(display_container):
		snap_back_tween.tween_property(display_container, "scale", Vector2(1.1, 1.1), 0.25).set_ease(Tween.EASE_OUT)
		snap_back_tween.tween_property(display_container, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_IN).set_delay(0.25)

func handle_shadow() -> void:
	if not is_instance_valid(shadow): return
	var center_x: float = get_viewport_rect().size.x / 2.0
	var distance_from_center: float = global_position.x - center_x
	var distance_percent: float = distance_from_center / center_x
	var target_x: float = -distance_percent * max_shadow_offset
	
	if shadow_instant_follow:
		shadow.position.x = target_x
	else:
		shadow.position.x = lerpf(shadow.position.x, target_x, shadow_follow_speed * get_process_delta_time())
	
	shadow.position.y = shadow_y_offset

func handle_tilt(delta: float) -> void:
	if not is_instance_valid(display_container): return
	var mat: ShaderMaterial = display_container.material as ShaderMaterial
	if not mat:
		return
		
	if is_mouse_over and not is_dragging:
		var card_size: Vector2 = display_container.size
		var mouse_pos: Vector2 = display_container.get_local_mouse_position()
		var percent_x: float = (mouse_pos.x / card_size.x) - 0.5
		var percent_y: float = (mouse_pos.y / card_size.y) - 0.5
		
		var rot_y: float = percent_x * max_tilt_angle * -2.0
		var rot_x: float = percent_y * max_tilt_angle * 2.0
		
		mat.set_shader_parameter("y_rot", rot_y)
		mat.set_shader_parameter("x_rot", rot_x)
	else:
		var param_y = mat.get_shader_parameter("y_rot")
		var current_rot_y: float = param_y if param_y != null else 0.0

		var param_x = mat.get_shader_parameter("x_rot")
		var current_rot_x: float = param_x if param_x != null else 0.0

		mat.set_shader_parameter("y_rot", lerpf(current_rot_y, 0.0, delta * 5.0))
		mat.set_shader_parameter("x_rot", lerpf(current_rot_x, 0.0, delta * 5.0))

func handle_wobble(delta: float) -> void:
	if not is_instance_valid(visuals): return
	var velocity: Vector2 = (global_position - prev_global_position) / delta
	var speed: float = velocity.length()
	
	var resting_rotation_rad: float = 0.0
	if not is_player_card:
		resting_rotation_rad = PI
	
	var target_rotation_rad: float = resting_rotation_rad
	
	if speed > 1.0 and is_dragging:
		wobble_time += delta * wobble_speed
		var max_angle_rad: float = deg_to_rad(wobble_angle)
		var wobble_offset: float = sin(wobble_time) * max_angle_rad
		target_rotation_rad = resting_rotation_rad + wobble_offset
	
	elif idle_wobble_enabled and not is_dragging:
		wobble_time += delta * idle_wobble_speed
		var phase: float = wobble_time + (card_index * wave_phase_offset)
		var idle_max_angle_rad: float = deg_to_rad(idle_wobble_angle)
		target_rotation_rad = resting_rotation_rad + sin(phase) * idle_max_angle_rad

	visuals.rotation = lerp_angle(visuals.rotation, target_rotation_rad, delta * wobble_smoothing)
	prev_global_position = global_position

func handle_hover_offset() -> void:
	if not is_instance_valid(visuals): return
	if not is_dragging:
		visuals.position.y = hover_y_offset

## Triggers the disintegration effect on this card.
func apply_disintegration(shader: Shader, _start_progress: float = 0.0, target_progress: float = 1.0, duration: float = 1.5, ease_type: int = Tween.EASE_IN, trans_type: int = Tween.TRANS_SINE, shader_pixel_amount: int = 50, shader_edge_width: float = 0.04, shader_edge_color: Color = Color(1.5,1.5,1.5,1.0)) -> void:
	if not is_instance_valid(display_container) or not is_instance_valid(shader):
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("progress", _start_progress)
	display_container.material = mat

	if use_disintegration_override:
		mat.set_shader_parameter("pixel_amount", override_pixel_amount)
		mat.set_shader_parameter("edge_width", override_edge_width)
		mat.set_shader_parameter("edge_color", override_edge_color)
	else:
		mat.set_shader_parameter("pixel_amount", shader_pixel_amount)
		mat.set_shader_parameter("edge_width", shader_edge_width)
		mat.set_shader_parameter("edge_color", shader_edge_color)

	var tween: Tween = create_tween()
	tween.tween_property(mat, "shader_parameter/progress", target_progress, duration).set_ease(ease_type).set_trans(trans_type)
	tween.tween_callback(func():
		var ap: AnimationPlayer = get_node_or_null("AnimationPlayer")
		if is_instance_valid(ap) and ap.has_animation("digital_decay"):
			var cb := Callable(self, "_on_animation_player_animation_finished")
			if not ap.is_connected("animation_finished", cb):
				ap.animation_finished.connect(cb)
			ap.play("digital_decay")
			return
		_destroy_after_disintegration()
	)

func _destroy_after_disintegration() -> void:
	if is_instance_valid(self) and is_inside_tree():
		emit_signal("moved_to_discard")
		emit_signal("disintegration_finished")
		queue_free()

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "digital_decay":
		_destroy_after_disintegration()
