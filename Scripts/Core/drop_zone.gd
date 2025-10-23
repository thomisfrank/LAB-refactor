# [drop_zone.gd] (Corrected for Marker2D)
extends Area2D

@export var disintegration_shader: Shader

# ... (all @export variables are the same) ...
@export_category("Fade Animation")
@export_range(0.0, 1.0) var fade_in_alpha: float = 0.4
@export_range(0.0, 1.0) var fade_out_alpha: float = 0.0
@export_range(0.1, 2.0) var fade_in_duration: float = 0.3
@export_range(0.1, 2.0) var fade_out_duration: float = 0.3
@export var fade_in_ease: Tween.EaseType = Tween.EASE_OUT
@export var fade_in_trans: Tween.TransitionType = Tween.TRANS_SINE
@export var fade_out_ease: Tween.EaseType = Tween.EASE_IN
@export var fade_out_trans: Tween.TransitionType = Tween.TRANS_SINE

@export_category("Shader Params")
@export_range(2, 200) var shader_pixel_amount: int = 50
@export_range(0.0, 0.5) var shader_edge_width: float = 0.04
@export var shader_edge_color: Color = Color(1.5, 1.5, 1.5, 1.0)
@export_range(0.0, 1.0) var shader_start_progress: float = 0.0
@export_range(0.0, 1.0) var shader_target_progress: float = 1.0
@export_range(0.05, 5.0) var shader_tween_duration: float = 1.5
@export var shader_tween_ease: Tween.EaseType = Tween.EASE_IN
@export var shader_tween_trans: Tween.TransitionType = Tween.TRANS_SINE


@onready var visual: ColorRect = $Drop
# --- THIS IS THE CHANGE ---
# We now type-hint this as Marker2D
@onready var play_slot: Marker2D = $PlayAreaCardSlot
# --- END OF CHANGE ---
var _waiting_drop_cards: Dictionary = {}

# --- GODOT FUNCTIONS ---
func _ready() -> void:
	if is_instance_valid(visual): 
		visual.modulate.a = fade_out_alpha
	add_to_group("drop_zones")
	
	if GameManager.has_signal("drag_started"):
		GameManager.drag_started.connect(_fade_in)
	if GameManager.has_signal("drag_ended"):
		GameManager.drag_ended.connect(_fade_out)

# --- FADE LOGIC ---
func _fade_in() -> void:
	if is_instance_valid(visual): 
		create_tween().tween_property(visual, "modulate:a", fade_in_alpha, fade_in_duration).set_trans(fade_in_trans).set_ease(fade_in_ease)

func _fade_out() -> void:
	if is_instance_valid(visual): 
		create_tween().tween_property(visual, "modulate:a", fade_out_alpha, fade_out_duration).set_trans(fade_out_trans).set_ease(fade_out_ease)

# --- DROP LOGIC ---
## Called by InteractiveCard when it's released over this zone.
func on_card_dropped(card_node: Node) -> void:
	if not is_instance_valid(card_node) or not "card_data" in card_node:
		push_error("DropZone: Invalid card node dropped.")
		return

	var card_data: Dictionary = card_node.card_data
	var effect_type: String = card_data.get("effect_type", "")
	var should_discard: bool = true

	# --- THIS IS THE FIX ---
	# Now we check for Marker2D
	if not is_instance_valid(play_slot):
	# --- END OF FIX ---
		push_error("DropZone: PlayAreaCardSlot Marker2D missing; cannot accept dropped card.")
		return

	var scene_root: Node = get_tree().get_current_scene()
	if not is_instance_valid(scene_root):
		push_error("DropZone: No current scene found; cannot reparent dropped card.")
		return

	# Preserve world position then reparent to the scene root (neutral scale)
	var handoff_parent: Node = scene_root
	var old_global: Vector2 = (card_node as Node2D).global_position
	if is_instance_valid(card_node.get_parent()):
		card_node.get_parent().remove_child(card_node)
	scene_root.add_child(card_node)

	if is_instance_valid(card_node):
		(card_node as Node2D).global_position = old_global
		_prepare_card_for_zone(card_node as Node2D)
	
	var target_pos: Vector2 = play_slot.global_position
	var target_rot: float = 0.0
	
	var tw: Tween = create_tween().set_parallel()
	tw.tween_property(card_node, "global_position", target_pos, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(card_node, "rotation", target_rot, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	var visuals_node: Node2D = card_node.get_node_or_null("Visuals")
	if is_instance_valid(visuals_node):
		tw.tween_property(visuals_node, "rotation", target_rot, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Notify Turn Manager immediately that an action was played.
	var turn_manager: Node = GameManager.get_manager("TurnManager")
	if is_instance_valid(turn_manager):
		var is_player_action: bool = card_node.is_player_card if is_instance_valid(card_node) and "is_player_card" in card_node else true
		turn_manager.record_action_played(is_player_action)

	# 1. Resolve Effect (if any)
	var effects_manager: Node = GameManager.get_manager("EffectManager")
	if is_instance_valid(effects_manager):
		effects_manager.resolve_effect(card_node)
		if effect_type in ["peek_deck", "peek_hand", "swap"]:
			should_discard = false

	# Wait briefly for effects to run... (This is the 5-second lag on Draw cards)
	if is_instance_valid(card_node):
		var waited: float = 0.0
		var timeout: float = 5.0 # We will fix this 5s lag later

		_waiting_drop_cards[card_node] = false

		if card_node.has_signal("disintegration_finished"):
			card_node.disintegration_finished.connect(_on_signal_mark_finished.bind(card_node), CONNECT_ONE_SHOT)
		if card_node.has_signal("moved_to_discard"):
			card_node.moved_to_discard.connect(_on_signal_mark_finished.bind(card_node), CONNECT_ONE_SHOT)

		# --- THIS IS THE FIX ---
		# The card's parent is now the handoff_parent (scene_root)
		while waited < timeout and not _waiting_drop_cards.get(card_node, false) and is_instance_valid(card_node):
			if handoff_parent and card_node.get_parent() != handoff_parent:
		# --- END OF FIX ---
				_release_card_from_zone(card_node as Node2D)
				_waiting_drop_cards[card_node] = true
				break
			await get_tree().create_timer(0.08).timeout
			waited += 0.08

		_waiting_drop_cards.erase(card_node)

	var card_manager: Node = GameManager.get_manager("CardManager")
	if not is_instance_valid(card_node) or (is_instance_valid(card_manager) and card_node.get_parent() == card_manager):
		should_discard = false

	# 2. Handle Discarding
	if should_discard:
		var discard_pile: Node = GameManager.get_manager("DiscardPile")
		if not is_instance_valid(discard_pile):
			push_error("DropZone: DiscardPile manager not found!")
			if is_instance_valid(card_node): card_node.queue_free()
			return

		if card_node.has_method("apply_disintegration") and is_instance_valid(disintegration_shader):
			var root_scene: Node = get_tree().get_current_scene()
			if is_instance_valid(card_node.get_parent()): card_node.get_parent().remove_child(card_node)
			if is_instance_valid(root_scene): root_scene.add_child(card_node)

			card_node.apply_disintegration(
				disintegration_shader,
				shader_start_progress,
				shader_target_progress,
				shader_tween_duration,
				shader_tween_ease,
				shader_tween_trans,
				shader_pixel_amount,
				shader_edge_width,
				shader_edge_color
			)
			await card_node.disintegration_finished

			if is_instance_valid(card_node) and not card_node.is_queued_for_deletion():
				discard_pile.add_card(card_node)
		else:
			push_warning("DropZone: Card cannot disintegrate or shader missing. Adding directly.")
			discard_pile.add_card(card_node)

# ... (rest of the functions are unchanged) ...
func contains_global_position(global_pos: Vector2) -> bool:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if not is_instance_valid(cs) or not is_instance_valid(cs.shape):
		push_error("DropZone: Missing CollisionShape2D. Add a CollisionShape2D to enable drop detection.")
		return false
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = global_pos
	params.collide_with_areas = true
	var results: Array[Dictionary] = space.intersect_point(params)
	for r in results:
		if r.collider == self:
			return true
	return false
func _on_signal_mark_finished(card: Node) -> void:
	if card in _waiting_drop_cards:
		_waiting_drop_cards[card] = true
func _prepare_card_for_zone(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	card.set_process(false)

	var clamped_base_rot: float = clamp(card.rotation, deg_to_rad(-2.0), deg_to_rad(2.0))

	card.rotation = clamped_base_rot
	var visuals_node: Node2D = card.get_node_or_null("Visuals")
	if is_instance_valid(visuals_node):
		visuals_node.rotation = clamped_base_rot

	if "is_dragging" in card: card.is_dragging = false
	if "prev_global_position" in card: card.prev_global_position = card.global_position
	if "wobble_time" in card: card.wobble_time = 0.0
	if "hover_y_offset" in card: card.hover_y_offset = 0.0
	if "home_rotation" in card: card.home_rotation = clamped_base_rot
	if "is_locked" in card: card.is_locked = true
	if "idle_wobble_enabled" in card: card.idle_wobble_enabled = false

	var visuals: Node = card.get_node_or_null("Visuals")
	if is_instance_valid(visuals):
		var lock_icon: CanvasItem = visuals.get_node_or_null("LockedState")
		if is_instance_valid(lock_icon):
			lock_icon.hide()
		var shadow: CanvasItem = visuals.get_node_or_null("Shadow")
		if is_instance_valid(shadow):
			shadow.hide()
	var display_container: Control = card.get_node_or_null("Visuals/CardViewport")
	if is_instance_valid(display_container):
		display_container.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _release_card_from_zone(card: Node2D) -> void:
	if not is_instance_valid(card):
		return

	card.set_process(true)

	if "is_locked" in card: card.is_locked = false
	if "idle_wobble_enabled" in card: card.idle_wobble_enabled = true

	var visuals: Node = card.get_node_or_null("Visuals")
	if is_instance_valid(visuals):
		var shadow: CanvasItem = visuals.get_node_or_null("Shadow")
		if is_instance_valid(shadow):
			shadow.show()

	var display_container: Control = card.get_node_or_null("Visuals/CardViewport")
	if is_instance_valid(display_container):
		display_container.mouse_filter = Control.MOUSE_FILTER_PASS
