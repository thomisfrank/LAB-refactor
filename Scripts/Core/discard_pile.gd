# [discard_pile.gd] (Corrected)
extends Node2D

# --- EXPORTS (Configurable in Inspector) ---
@export_group("Pile Randomization")
@export_range(-15, 15, 0.1) var rotation_range_degrees: float = 15.0
@export_range(1.0, 5.0, 0.1) var rotation_bias_exponent: float = 2.0
@export var position_offset_range_pixels: Vector2 = Vector2(10, 10)

@export_group("Arrival Animation")
@export_category("Pop Animation")
@export_range(0.1, 2.0) var pop_start_scale: float = 0.5
@export_range(1.0, 2.0) var pop_overshoot_scale: float = 1.2
@export_range(0.05, 0.5) var pop_scale_up_duration: float = 0.2
@export_range(0.05, 0.5) var pop_scale_settle_duration: float = 0.15
@export var pop_scale_ease: Tween.EaseType = Tween.EASE_OUT
@export var pop_scale_trans: Tween.TransitionType = Tween.TRANS_BACK

@export_category("Flash Animation")
@export_range(1.0, 5.0) var flash_brightness: float = 3.0
@export_range(1.0, 4.0) var flash_mid_brightness: float = 2.5
@export_range(0.01, 0.3) var flash_initial_duration: float = 0.08
@export_range(0.1, 0.5) var flash_fade_duration: float = 0.25
@export var flash_ease: Tween.EaseType = Tween.EASE_IN_OUT

# --- PUBLIC API ---

## Called by DropZone or EffectsManager to add the ACTUAL card node to the pile.
func add_card(card: Node2D) -> void:
	if not is_instance_valid(card): 
		return

	# 1. Reparent the card to this discard pile.
	var old_global_pos: Vector2 = card.global_position
	if is_instance_valid(card.get_parent()):
		card.get_parent().remove_child(card)
	add_child(card)

	# Preserve visual world position immediately after reparent.
	card.global_position = old_global_pos

	# 2. Disable interactions.
	card.set_process(false)
	var display_container: Control = card.get_node_or_null("Visuals/CardViewport")
	if is_instance_valid(display_container):
		display_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 3. Ensure card is face up and visuals reset.
	if card.has_method("apply_start_face_up"):
		card.start_face_up = true
		card.apply_start_face_up()
	
	var visuals: Node2D = card.get_node_or_null("Visuals")
	if is_instance_valid(visuals):
		visuals.rotation = 0.0

	# 4. Apply Randomization: animate the card's local position into the pile
	var target_local := Vector2(
		randf_range(-position_offset_range_pixels.x, position_offset_range_pixels.x),
		randf_range(-position_offset_range_pixels.y, position_offset_range_pixels.y)
	)
	var r: float = randf_range(-1.0, 1.0)
	var biased: float = sign(r) * pow(abs(r), rotation_bias_exponent)
	card.rotation = deg_to_rad(biased * clampf(rotation_range_degrees, -15.0, 15.0))
	var arrival_duration: float = 0.25

	# 5. Play Arrival Animation (Flash & Pop) & Hide Shadow.
	if is_instance_valid(visuals):
		# Ensure material is cleared (e.g., from disintegration)
		if is_instance_valid(display_container): 
			display_container.material = null
		
		visuals.scale = Vector2.ONE * pop_start_scale
		
		# --- THIS IS THE FIX ---
		# Start the card as visible (Color.WHITE)
		visuals.modulate = Color.WHITE
		# The line that set alpha to 0.0 has been REMOVED.
		
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		
		# Move card local position into the pile smoothly
		tween.tween_property(card, "position", target_local, arrival_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		# Pop scale
		tween.tween_property(visuals, "scale", Vector2.ONE * pop_overshoot_scale, pop_scale_up_duration).set_ease(pop_scale_ease).set_trans(pop_scale_trans)
		
		# Flash and fade in (This now animates from WHITE -> BRIGHT -> WHITE)
		tween.tween_property(visuals, "modulate", Color(flash_mid_brightness, flash_mid_brightness, flash_mid_brightness, 1.0), flash_initial_duration).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(visuals, "modulate", Color.WHITE, flash_fade_duration).set_ease(flash_ease)
		
		# Settle scale
		tween.parallel().tween_property(visuals, "scale", Vector2.ONE, pop_scale_settle_duration).set_ease(Tween.EASE_IN_OUT)

		# After animation, hide the shadow node.
		tween.finished.connect(_on_tween_finished.bind(visuals))


# --- PRIVATE FUNCTIONS ---
func _on_tween_finished(visuals: Node2D) -> void:
	if not is_instance_valid(visuals): 
		return
	var shadow: CanvasItem = visuals.get_node_or_null("Shadow")
	if is_instance_valid(shadow):
		shadow.hide()