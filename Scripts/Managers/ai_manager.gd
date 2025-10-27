extends Node

@export var move_offset: Vector2 = Vector2(150, 0)
@export var lift_height: float = 80.0
@export var lift_duration: float = 0.3
@export var rotate_duration: float = 0.3
@export var move_duration: float = 0.6

var game_manager: Node = null
var card_manager: Node = null


func _ready() -> void:
	game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("register_manager"):
		game_manager.register_manager("AIManager", self)


func _resolve_card_manager() -> void:
	if game_manager and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Parallax/CardManager")
	if not card_manager:
		card_manager = get_node_or_null("/root/main/Managers/CardManager")


func on_ai_turn() -> void:
	# Add a thinking delay so the player can see what's happening
	await get_tree().create_timer(1.0).timeout
	
	# Get all opponent cards from the opponent_hand group
	var opponent_cards = get_tree().get_nodes_in_group("opponent_hand")
	
	print("[AI] Found ", opponent_cards.size(), " opponent cards")
	
	# If no cards in hand, just pass
	if opponent_cards.is_empty():
		print("[AI] No cards in hand, passing")
		_ai_pass()
		return
	
	# Randomly decide: play a card (70% chance) or pass (30% chance)
	var random_choice = randf()
	print("[AI] Random choice: ", random_choice)
	if random_choice < 0.7:
		# Play a random card from hand
		var card_node = opponent_cards[randi() % opponent_cards.size()]
		print("[AI] Playing card")
		_ai_play_card(card_node)
	else:
		# Pass turn
		print("[AI] Choosing to pass")
		_ai_pass()


func _ai_play_card(card_node: Node) -> void:
	"""AI plays the specified card with animation."""
	var main_node = get_node_or_null("/root/main")
	if main_node and card_node.get_parent() != main_node:
		card_node.reparent(main_node)

	# Find the drop zone to get the target position
	var drop_zone = null
	for zone in get_tree().get_nodes_in_group("drop_zones"):
		drop_zone = zone
		break
	
	if not drop_zone:
		push_error("AIManager: No drop zone found. Cannot play card.")
		return
	
	var play_area_marker = drop_zone.get_node_or_null("PlayAreaCardSlot/PlayAreaCardSlotMarker")
	if not play_area_marker:
		push_error("AIManager: PlayAreaCardSlotMarker not found. Cannot play card.")
		return
	
	# Override target position to exact coordinates
	var target_position = Vector2(1325, 650)
	print("[AI] Using hardcoded position: ", target_position)

	# PHASE 1: Lift and Rotate
	var start_position = card_node.global_position
	var lifted_position = start_position + Vector2(0, -lift_height)
	var target_rotation = deg_to_rad(180)  # Rotate 180 degrees to face right-side up

	var t = create_tween()

	# Lift
	t.tween_property(card_node, "global_position", lifted_position, lift_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

	# Rotate (at the same time as lift)
	t.parallel().tween_property(card_node, "rotation", target_rotation, rotate_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	# PHASE 2: Arc Move after the lift finishes
	t.tween_callback(func ():
		_move_card_in_arc(card_node, lifted_position, target_position)
	)


func _move_card_in_arc(card_node: Node2D, start: Vector2, target: Vector2) -> void:
	var control_point = (start + target) / 2 + Vector2(0, -150)  # curve upward
	var t = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# Flip the card about 1/3 of the way through the arc
	var flip_delay = move_duration * 0.33
	t.tween_callback(func():
		if card_node.has_method("flip_card"):
			card_node.flip_card()
	).set_delay(flip_delay)

	# Animate along an arc using a custom callback
	t.parallel().tween_method(func(progress):
		var p1 = start.lerp(control_point, progress)
		var p2 = control_point.lerp(target, progress)
		card_node.global_position = p1.lerp(p2, progress)
	, 0.0, 1.0, move_duration)
	
	# After the arc completes, trigger the drop zone
	t.tween_callback(func():
		_trigger_drop_zone(card_node)
	)


func _trigger_drop_zone(card_node: Node2D) -> void:
	"""Find the drop zone and trigger the card drop."""
	# Find all drop zones in the scene
	for zone in get_tree().get_nodes_in_group("drop_zones"):
		if zone.has_method("on_card_dropped"):
			# Call the drop zone's on_card_dropped method
			# snap=false to keep the card where it landed, disintegrate=true to trigger the effect
			zone.on_card_dropped(card_node, false, true)
			# After triggering the drop, ensure AI passes remaining actions so the second action is a pass
			# Try to find TurnManager via GameManager
			var tm = null
			if game_manager and game_manager.has_method("get_manager"):
				tm = game_manager.get_manager("TurnManager")
			if not tm:
				tm = get_node_or_null("/root/main/Managers/TurnManager")
			if not tm:
				tm = get_node_or_null("/root/main/TurnManager")
			# If TurnManager found and has pass_current_player, ask it to pass
			if tm and tm.has_method("pass_current_player"):
				# Wait until the card has been moved into the discard pile (disintegration finished)
				# Then wait 1 second (user-requested pause) and call pass_current_player.
				# Defensive: only do this if opponent still has actions remaining.
				var should_pass_now = true
				if "opponent_actions_remaining" in tm and int(tm.opponent_actions_remaining) <= 0:
					should_pass_now = false
				if should_pass_now:
					# Try to find the discard pile node via the main scene helper (if present)
					var main_node = get_node_or_null("/root/main")
					var discard_node = null
					if main_node and main_node.has_method("get") and "discard_pile_node" in main_node:
						discard_node = main_node.discard_pile_node
					# If we have a discard_node, poll until the card's parent is the discard node or timeout
					if discard_node:
						var waited = 0.0
						var timeout = 5.0
						while is_instance_valid(card_node) and card_node.get_parent() != discard_node and waited < timeout:
							await get_tree().create_timer(0.05).timeout
							waited += 0.05
						# Once card is in discard (or timed out), wait the user-requested 1s pause
						await get_tree().create_timer(1.0).timeout
						# Finally, request the TurnManager to pass the opponent
						if tm and tm.has_method("pass_current_player"):
							tm.pass_current_player()
					else:
						# No discard node found - fall back to a simple 1s delay then pass
						await get_tree().create_timer(1.0).timeout
						if tm and tm.has_method("pass_current_player"):
							tm.pass_current_player()
			return
	
	# If no drop zone found, log a warning
	push_warning("AIManager: No drop zone found to trigger card drop")


func _ai_pass() -> void:
	"""AI decides to pass their turn."""
	# Add a small delay so it doesn't feel instant
	await get_tree().create_timer(0.5).timeout
	
	var tm = null
	if game_manager and game_manager.has_method("get_manager"):
		tm = game_manager.get_manager("TurnManager")
	if not tm:
		tm = get_node_or_null("/root/main/Managers/TurnManager")
	
	if tm and tm.has_method("pass_current_player"):
		tm.pass_current_player()
	else:
		push_error("AIManager: Could not find TurnManager to pass turn")
