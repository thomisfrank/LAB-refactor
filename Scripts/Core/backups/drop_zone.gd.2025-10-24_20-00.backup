extends Area2D

@export var disintegration_shader: Shader

@export_category("Fade Animation")
@export_range(0.0, 1.0) var fade_in_alpha: float = 0.4  # Target alpha when card is dragging
# Hand repositioning removed - cards stay in their original positions
@export_range(0.0, 1.0) var fade_out_alpha: float = 0.0  # Target alpha when no drag
@export_range(0.1, 2.0) var fade_in_duration: float = 0.3  # How long fade-in takes
@export_range(0.1, 2.0) var fade_out_duration: float = 0.3  # How long fade-out takes
@export var fade_in_ease: Tween.EaseType = Tween.EASE_OUT
@export var fade_in_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var fade_out_ease: Tween.EaseType = Tween.EASE_IN
@export var fade_out_trans: Tween.TransitionType = Tween.TRANS_SINE

@onready var visual: ColorRect = $Drop  # Reference to the visual ColorRect child

var is_card_dragging: bool = false


@export_category("Shader Animation")
@export_range(0.0, 1.0) var shader_target_progress: float = 1.0
@export_range(0.0, 1.0) var shader_start_progress: float = 0.0
@export_range(0.05, 5.0) var shader_tween_duration: float = 1.5
@export var shader_tween_ease: Tween.EaseType = Tween.EASE_IN
@export var shader_tween_trans: Tween.TransitionType = Tween.TRANS_SINE

@export_category("Shader Params")
@export_range(2, 200) var shader_pixel_amount: int = 50
@export_range(0.0, 0.5) var shader_edge_width: float = 0.04
@export var shader_edge_color: Color = Color(1.5, 1.5, 1.5, 1.0)

@export_category("Card Snap Settings")
@export_range(0.0, 10.0) var rotation_correction_degrees: float = 3.0
@export_range(0.0, 5.0) var discard_delay_seconds: float = 1.0

@export_category("Dust Effect")
@export var dust_particle_count: int = 8
@export var dust_particle_size: float = 4.0
@export var dust_speed: float = 150.0
@export var dust_lifetime: float = 0.5
@export var dust_color: Color = Color(0.9, 0.9, 0.8, 0.8)

func _ready():
	# Don't use area_entered for drop detection anymore
	# We'll use a manual check when cards are released
	
	# Start with the drop zone invisible
	if visual:
		visual.modulate.a = fade_out_alpha
	
	# Add to drop_zones group so cards can find us
	add_to_group("drop_zones")

func _process(_delta: float) -> void:
	# Check if any card is currently being dragged
	var any_card_dragging = false
	for card in get_tree().get_nodes_in_group("cards"):
		# Check if the card or its parent has an is_dragging property
		var check_node = card
		if card.get_parent() and card.get_parent().has_method("get"):
			check_node = card.get_parent()
		
		if check_node.get("is_dragging") == true:
			any_card_dragging = true
			break
	
	# Fade in/out based on drag state
	if any_card_dragging and not is_card_dragging:
		is_card_dragging = true
		_fade_in()
	elif not any_card_dragging and is_card_dragging:
		is_card_dragging = false
		_fade_out()

func _fade_in() -> void:
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "modulate:a", fade_in_alpha, fade_in_duration).set_ease(fade_in_ease).set_trans(fade_in_trans)

func _fade_out() -> void:
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "modulate:a", fade_out_alpha, fade_out_duration).set_ease(fade_out_ease).set_trans(fade_out_trans)

# Called by cards when they're released to check if they're over this zone
func contains_global_position(pos: Vector2) -> bool:
	var cs = $CollisionShape2D
	if not cs or not cs.shape:
		return false
	
	var rect_shape = cs.shape as RectangleShape2D
	if rect_shape:
		var local_pos = to_local(pos)
		var size = rect_shape.size
		var rect = Rect2(-size * 0.5, size)
		return rect.has_point(local_pos + cs.position)
	return false

# Called by cards when dropped in this zone
func on_card_dropped(card_node: Node, snap: bool = true, _disintegrate: bool = true) -> void:
	var play_area_marker = $PlayAreaCardSlot/PlayAreaCardSlotMarker
	
	# Snap position to the play area card slot marker
	card_node.global_position = play_area_marker.global_position
	
	# Set rotation to random value between -rotation_correction_degrees and +rotation_correction_degrees
	var random_rotation_degrees = randf_range(-rotation_correction_degrees, rotation_correction_degrees)
	var target_rotation_rad = deg_to_rad(random_rotation_degrees)

	# Apply rotation to both the card node and its visuals to avoid other code (wobble/hover)
	card_node.rotation = target_rotation_rad
	if card_node.has_node("Visuals"):
		card_node.get_node("Visuals").rotation = target_rotation_rad

	# Defensive: clear dragging state and mark as in-play so wobble/drag logic won't override rotation
	# Set properties only if they exist on the card node
	if "is_dragging" in card_node:
		card_node.is_dragging = false
	if "is_in_play_area" in card_node:
		card_node.is_in_play_area = true
	# Lock rotation on the card so other code won't change it
	if "lock_rotation" in card_node:
		card_node.lock_rotation = true

	# Attempt to stop any active tweens that might change rotation/position on the card
	if "hover_tween" in card_node and card_node.hover_tween:
		if card_node.hover_tween.is_running():
			card_node.hover_tween.kill()
	if "snap_back_tween" in card_node and card_node.snap_back_tween:
		if card_node.snap_back_tween.is_running():
			card_node.snap_back_tween.kill()

	# Prevent a large wobble delta by syncing previous position
	if "prev_global_position" in card_node:
		card_node.prev_global_position = card_node.global_position

	# Remove shadow and reset z-index
	var shadow_node = card_node.get_node_or_null("Visuals/Shadow")
	if shadow_node:
		shadow_node.visible = false
	card_node.z_index = 0

	# Create dust cloud effect at card corners
	_create_dust_effect(card_node)

	# Disable interactivity by ignoring mouse events on the card's viewport
	var card_viewport = card_node.get_node_or_null("Visuals/CardViewport")
	if card_viewport:
		card_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Tell the card to stop its wobble logic
	if "is_in_play_area" in card_node:
		card_node.is_in_play_area = true

	# Wait before starting disintegration
	if _disintegrate and card_node.has_method("apply_disintegration"):
		await get_tree().create_timer(discard_delay_seconds).timeout
		card_node.apply_disintegration(disintegration_shader, shader_start_progress, shader_target_progress, shader_tween_duration, shader_tween_ease, shader_tween_trans)

	# Notify TurnManager that an action was played (for now, any card dropped counts)
	var gm = get_node_or_null("/root/GameManager")
	var tm: Node = null
	if gm and gm.has_method("get_manager"):
		tm = gm.get_manager("TurnManager")
	if not tm:
		tm = get_node_or_null("/root/main/Managers/TurnManager")
	if tm and tm.has_method("record_action_played"):
		# Determine ownership via card property if available
		var is_player_card = true
		if card_node.has_method("get") and "is_player_card" in card_node:
			is_player_card = card_node.is_player_card
		tm.record_action_played(is_player_card)

func _create_dust_effect(card_node: Node) -> void:
	# Get card bounds for corner positions
	var card_size = Vector2(100, 140)  # Standard card size
	
	# Corner positions relative to card center
	var corners = [
		Vector2(-50, -70),  # Top-left
		Vector2(50, -70),   # Top-right
		Vector2(-50, 70),   # Bottom-left
		Vector2(50, 70)     # Bottom-right
	]
	
	# Create dust particles at each corner
	for corner in corners:
		for i in range(2):  # 2 particles per corner
			var dust = ColorRect.new()
			get_parent().add_child(dust)  # Add to parent so it's visible
			
			# Setup dust particle
			dust.size = Vector2(dust_particle_size, dust_particle_size)
			dust.color = dust_color
			dust.global_position = card_node.global_position + corner
			dust.z_index = 10
			
			# Animate dust particle
			var tween = create_tween()
			tween.set_parallel(true)
			
			# Random direction outward from corner
			var angle = randf_range(-PI/4, PI/4) + atan2(corner.y, corner.x)
			var direction = Vector2(cos(angle), sin(angle))
			var distance = randf_range(30, 60)
			var target_pos = dust.global_position + direction * distance
			
			# Animate position and fade
			tween.tween_property(dust, "global_position", target_pos, dust_lifetime)
			tween.tween_property(dust, "modulate:a", 0.0, dust_lifetime)
			
			# Clean up particle when done
			tween.finished.connect(func(): dust.queue_free())
