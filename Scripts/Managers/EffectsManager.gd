extends Node

# Manager references
var game_manager: Node
var card_manager: Node
var turn_manager: Node

func _ready() -> void:
	game_manager = get_node("/root/GameManager")
	game_manager.register_manager("EffectManager", self)
	card_manager = game_manager.get_manager("CardManager")
	turn_manager = game_manager.get_manager("TurnManager")

func resolve_effect(card_node: Node) -> void:
	if not is_instance_valid(card_node):
		push_error("EffectManager: The passed 'card_node' (InteractiveCard) is itself invalid.")
		return

	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	
	if not is_instance_valid(actual_card) or not "card_data" in actual_card:
		push_error("EffectManager: Invalid card node passed.")
		return

	var effect_type = actual_card.card_data.get("effect_type", "")
	
	if effect_type == "":
		var suit = actual_card.card_data.get("suit", "")
		effect_type = suit.to_lower()

	match effect_type:
		"draw":
			await _execute_draw(card_node)
		"peekdeck":
			await _execute_peek_deck(card_node)
		"peekhand":
			await _execute_peek_hand(card_node)
		"swap":
			await _execute_swap(card_node)
		_:
			print("[EffectsManager] No effect found for card: %s" % actual_card.card_data.get("name", "Unknown"))
			_consume_action(card_node)

func _consume_action(card_node: Node) -> void:
	"""Helper to consume an action after a card effect resolves"""
	print("[EffectsManager] _consume_action called")
	if not turn_manager:
		turn_manager = game_manager.get_manager("TurnManager")
	
	if turn_manager and turn_manager.has_method("record_action_played"):
		var is_player_card = true
		if "is_player_card" in card_node:
			is_player_card = card_node.is_player_card
		print("[EffectsManager] Calling record_action_played, is_player_card=%s" % is_player_card)
		turn_manager.record_action_played(is_player_card)
		print("[EffectsManager] record_action_played completed")
	else:
		print("[EffectsManager] ERROR: turn_manager not found or doesn't have record_action_played")

func _consume_action_for_player(is_player: bool) -> void:
	"""Helper to consume an action for a specific player"""
	print("[EffectsManager] _consume_action_for_player called, is_player=%s" % is_player)
	if not turn_manager:
		turn_manager = game_manager.get_manager("TurnManager")
	
	if turn_manager and turn_manager.has_method("record_action_played"):
		print("[EffectsManager] Calling record_action_played, is_player=%s" % is_player)
		turn_manager.record_action_played(is_player)
		print("[EffectsManager] record_action_played completed")
	else:
		print("[EffectsManager] ERROR: turn_manager not found or doesn't have record_action_played")

func _relock_dropzone_cards() -> void:
	"""Re-lock rotation on any cards currently in the drop zone by restoring their stored rotation"""
	var drop_zone = get_node_or_null("/root/main/Parallax/DropZone")
	if not drop_zone:
		return
	
	# Check the drop zone's PlayAreaCardSlot for any cards
	var play_area_slot = drop_zone.get_node_or_null("PlayAreaCardSlot")
	if play_area_slot:
		for child in play_area_slot.get_children():
			if "is_in_play_area" in child and child.is_in_play_area and "locked_drop_zone_rotation" in child:
				# Use the stored rotation from when the card was dropped
				var stored_rotation = child.locked_drop_zone_rotation
				
				# Forcibly set rotation, overriding other tweens
				child.rotation = stored_rotation
				if child.has_node("VisualsContainer/Visuals"):
					child.get_node("VisualsContainer/Visuals").rotation = stored_rotation
				
				# Re-lock the rotation
				if "lock_rotation" in child:
					child.lock_rotation = true
	
	# Also check all cards in the scene tree
	for child in get_tree().get_nodes_in_group("cards"):
		if "is_in_play_area" in child and child.is_in_play_area and "locked_drop_zone_rotation" in child:
			# Use the stored rotation from when the card was dropped
			var stored_rotation = child.locked_drop_zone_rotation
			
			# Forcibly set rotation, overriding other tweens
			child.rotation = stored_rotation
			if child.has_node("VisualsContainer/Visuals"):
				child.get_node("VisualsContainer/Visuals").rotation = stored_rotation
			
			# Re-lock the rotation
			if "lock_rotation" in child:
				child.lock_rotation = true

func _execute_draw(card_node: Node) -> void:
	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if not actual_card:
		push_error("EffectManager: Could not find actual card node in _execute_draw.")
		return

	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager:
		push_error("EffectManager: CardManager not found")
		return
	
	await get_tree().create_timer(0.3).timeout
	
	var new_card = await card_manager.draw_single_card_to_hand(true)
	
	if is_instance_valid(new_card) and new_card.has_method("set_locked"):
		new_card.set_locked(true)
	
	await get_tree().create_timer(0.3).timeout
	
	var main_node = get_node_or_null("/root/main")
	if main_node and main_node.has_method("add_to_discard_pile") and is_instance_valid(card_node):
		main_node.add_to_discard_pile(card_node)
	
	await get_tree().create_timer(0.1).timeout
	_consume_action(card_node)
	
	# Re-lock the rotation on cards in play area after relayout is done
	await get_tree().create_timer(0.2).timeout
	_relock_dropzone_cards()


func _execute_swap(card_node: Node) -> void:
	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if not actual_card:
		push_error("EffectManager: Could not find actual card node in _execute_swap.")
		return

	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager:
		push_error("EffectManager: CardManager not found")
		return

	# Store who played the card BEFORE it gets swapped
	var played_by_player = true
	if "is_player_card" in card_node:
		played_by_player = card_node.is_player_card

	await get_tree().create_timer(0.3).timeout
	
	# Check if this is an AI card - use AI logic instead
	if not played_by_player:
		await _execute_swap_ai(card_node)
		return
	
	await _enter_swap_selection_state(card_node)
	
	print("[EffectsManager] Swap effect complete, about to consume action")
	await get_tree().create_timer(0.1).timeout
	print("[EffectsManager] Calling _consume_action for swap, played_by_player=%s" % played_by_player)
	_consume_action_for_player(played_by_player)
	print("[EffectsManager] _consume_action called")
	
	# Re-lock the rotation on cards in play area after relayout is done
	await get_tree().create_timer(0.2).timeout
	_relock_dropzone_cards()


func _enter_swap_selection_state(swap_card_node: Node) -> void:
	var selection_label = get_node_or_null("/root/main/FrontLayerUI/SelectionModeLabel")
	if selection_label:
		selection_label.modulate = Color(1, 1, 1, 0)
		selection_label.show()
		
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var opponent_hand = get_tree().get_nodes_in_group("opponent_hand")
	if opponent_hand.is_empty():
		if selection_label:
			selection_label.hide()
		
		if turn_manager and turn_manager.has_method("consume_action"):
			turn_manager.consume_action()
		return
	
	for card in opponent_hand:
		if card.has_method("enable_swap_selection"):
			card.enable_swap_selection()
	
	var selection_data = [null, false]
	
	for card in opponent_hand:
		if card.has_signal("card_selected_for_swap"):
			card.card_selected_for_swap.connect(func(card_node):
				if not selection_data[1]:
					selection_data[1] = true
					selection_data[0] = card_node
			)
	
	while selection_data[0] == null:
		await get_tree().process_frame
	
	var selected_card = selection_data[0]
	
	if selection_label:
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await tween.finished
		selection_label.hide()
	
	for card in opponent_hand:
		if card.has_method("disable_swap_selection"):
			card.disable_swap_selection()
	
	await _perform_swap_animation(swap_card_node, selected_card)


func _perform_swap_animation(swap_card: Node, opponent_card: Node) -> void:
	# Play swap sound
	var audio_manager = get_node_or_null("/root/main/Managers/AudioManager")
	if audio_manager and audio_manager.has_method("play_swap"):
		audio_manager.play_swap()
	
	var drop_zone = get_node_or_null("/root/main/Parallax/DropZone")
	var drop_zone_pos = Vector2.ZERO
	if drop_zone:
		drop_zone_pos = drop_zone.global_position
	else:
		var viewport_rect = get_viewport().get_visible_rect()
		drop_zone_pos = viewport_rect.size / 2.0
	
	var swap_card_original_pos = swap_card.global_position
	var opponent_card_original_pos = opponent_card.global_position
	
	var move_duration = 0.5
	var flip_duration = 0.2
	var pause_duration = 0.3
	
	var original_z_index = opponent_card.z_index
	opponent_card.z_index = 1000
	
	var tween1 = create_tween()
	tween1.tween_property(opponent_card, "global_position", drop_zone_pos, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween1.finished
	
	await get_tree().create_timer(pause_duration).timeout
	
	if opponent_card.has_method("flip_card"):
		opponent_card.flip_card()
	await get_tree().create_timer(flip_duration).timeout
	
	var tween2 = create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(opponent_card, "global_position", swap_card_original_pos, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween2.tween_property(swap_card, "global_position", opponent_card_original_pos, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween2.finished
	
	opponent_card.is_player_card = true
	swap_card.is_player_card = false
	
	if swap_card.has_method("flip_card"):
		var card_face = swap_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card/CardFace")
		if card_face and card_face.visible:
			swap_card.flip_card()
	
	if opponent_card.has_method("update_hand_group"):
		opponent_card.update_hand_group()
	if swap_card.has_method("update_hand_group"):
		swap_card.update_hand_group()
	
	if opponent_card.has_method("set_locked"):
		opponent_card.set_locked(true)
	if "is_dragging" in opponent_card:
		opponent_card.is_dragging = false
	if "is_in_play_area" in opponent_card:
		opponent_card.is_in_play_area = false
	
	opponent_card.rotation = 0
	if opponent_card.has_node("VisualsContainer/Visuals"):
		opponent_card.get_node("VisualsContainer/Visuals").rotation = 0
	
	if swap_card.has_method("set_locked"):
		swap_card.set_locked(false)
	if "is_dragging" in swap_card:
		swap_card.is_dragging = false
	if "is_in_play_area" in swap_card:
		swap_card.is_in_play_area = false
	
	swap_card.rotation = deg_to_rad(180)
	if swap_card.has_node("VisualsContainer/Visuals"):
		swap_card.get_node("VisualsContainer/Visuals").rotation = deg_to_rad(180)
	
	if opponent_card.get_parent() != card_manager:
		var old_parent = opponent_card.get_parent()
		if old_parent:
			old_parent.remove_child(opponent_card)
		card_manager.add_child(opponent_card)
	
	if swap_card.get_parent() != card_manager:
		var old_parent = swap_card.get_parent()
		if old_parent:
			old_parent.remove_child(swap_card)
		card_manager.add_child(swap_card)
	
	if opponent_card.has_node("VisualsContainer/Visuals/CardViewport"):
		var viewport = opponent_card.get_node("VisualsContainer/Visuals/CardViewport")
		viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	if swap_card.has_node("VisualsContainer/Visuals/CardViewport"):
		var viewport = swap_card.get_node("VisualsContainer/Visuals/CardViewport")
		viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	
	opponent_card.z_index = original_z_index
	
	if card_manager:
		await get_tree().process_frame
		card_manager.relayout_hand(true)
		await get_tree().process_frame
		card_manager.relayout_hand(false)
		await get_tree().process_frame


func _execute_peek_hand(card_node: Node) -> void:
	"""
	PeekHand: Enter selection mode, show the selected opponent card in ShowCase,
	allow player to swap or keep their card.
	"""
	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if not actual_card:
		push_error("EffectManager: Could not find actual card node in _execute_peek_hand.")
		return

	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager:
		push_error("EffectManager: CardManager not found")
		return

	# Store who played the card BEFORE any swaps
	var played_by_player = true
	if "is_player_card" in card_node:
		played_by_player = card_node.is_player_card

	await get_tree().create_timer(0.3).timeout
	
	# Check if this is an AI card - use AI logic instead
	if not played_by_player:
		await _execute_peek_hand_ai(card_node)
		return
	
	# Enter selection mode to pick an opponent card
	var selected_opponent_card = await _enter_peek_hand_selection(card_node)
	
	if not is_instance_valid(selected_opponent_card):
		# User cancelled or no valid selection, return peek card to hand
		await _return_peek_card_to_hand(card_node)
		_consume_action_for_player(played_by_player)
		return
	
	# Show the showcase with the selected card
	var choice = await _show_peek_hand_showcase(selected_opponent_card)
	
	if choice == "swap":
		# Perform the swap animation
		await _perform_swap_animation(card_node, selected_opponent_card)
		
		await get_tree().create_timer(0.1).timeout
		_consume_action_for_player(played_by_player)
		
		# Re-lock the rotation on cards in play area after relayout is done
		await get_tree().create_timer(0.2).timeout
		_relock_dropzone_cards()
	else:
		# Keep the peek card, return it to hand
		await _return_peek_card_to_hand(card_node)
		_consume_action_for_player(played_by_player)


func _execute_peek_deck(card_node: Node) -> void:
	"""
	PeekDeck: Show the top card of the deck in ShowCase,
	allow player to draw it or keep their peek card.
	"""
	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if not actual_card:
		push_error("EffectManager: Could not find actual card node in _execute_peek_deck.")
		return

	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager:
		push_error("EffectManager: CardManager not found")
		return

	# Store who played the card
	var played_by_player = true
	if "is_player_card" in card_node:
		played_by_player = card_node.is_player_card

	# Check if there's a card in the deck to peek at
	if card_manager.is_deck_depleted():
		print("[EffectsManager] Deck is empty, cannot peek")
		await _return_peek_card_to_hand(card_node)
		_consume_action(card_node)
		return

	await get_tree().create_timer(0.3).timeout
	
	# Check if this is an AI card - use AI logic instead
	if not played_by_player:
		await _execute_peek_deck_ai(card_node)
		return
	
	# Get the top card data without drawing it
	var top_card_name = card_manager.deck[card_manager.draw_index]
	
	# Show the showcase with the top deck card
	var choice = await _show_peek_deck_showcase(top_card_name)
	
	if choice == "draw":
		# First draw the new card
		var new_card = await card_manager.draw_single_card_to_hand(true)
		
		if is_instance_valid(new_card) and new_card.has_method("set_locked"):
			new_card.set_locked(true)
		
		await get_tree().create_timer(0.3).timeout
		
		# Apply disintegration to the peek card before discarding
		if is_instance_valid(card_node) and card_node.has_method("apply_disintegration"):
			var drop_zone = get_node_or_null("/root/main/Parallax/DropZone")
			if drop_zone and "disintegration_shader" in drop_zone and drop_zone.disintegration_shader:
				card_node.apply_disintegration(
					drop_zone.disintegration_shader,
					0.0,
					1.0,
					1.5,
					Tween.EASE_IN,
					Tween.TRANS_SINE
				)
				# Wait for disintegration to complete
				await get_tree().create_timer(1.5).timeout
		
		# THEN discard the peek card to the discard pile
		var main_node = get_node_or_null("/root/main")
		if main_node and main_node.has_method("add_to_discard_pile") and is_instance_valid(card_node):
			main_node.add_to_discard_pile(card_node)
		
		await get_tree().create_timer(0.1).timeout
		_consume_action(card_node)
		
		# Re-lock the rotation on cards in play area after relayout is done
		await get_tree().create_timer(0.2).timeout
		_relock_dropzone_cards()
	else:
		# Keep the peek card, return it to hand
		await _return_peek_card_to_hand(card_node)
		_consume_action(card_node)

func _enter_peek_hand_selection(_peek_card_node: Node) -> Node:
	"""
	Enter selection mode for PeekHand - similar to swap selection.
	Returns the selected opponent card or null if cancelled.
	"""
	var selection_label = get_node_or_null("/root/main/FrontLayerUI/SelectionModeLabel")
	if selection_label:
		selection_label.text = "Select an opponent card to peek at"
		selection_label.modulate = Color(1, 1, 1, 0)
		selection_label.show()
		
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var opponent_hand = get_tree().get_nodes_in_group("opponent_hand")
	if opponent_hand.is_empty():
		if selection_label:
			selection_label.hide()
		return null
	
	for card in opponent_hand:
		if card.has_method("enable_swap_selection"):
			card.enable_swap_selection()
	
	var selection_data = [null, false]
	
	for card in opponent_hand:
		if card.has_signal("card_selected_for_swap"):
			card.card_selected_for_swap.connect(func(card_node):
				if not selection_data[1]:
					selection_data[1] = true
					selection_data[0] = card_node
			)
	
	while selection_data[0] == null:
		await get_tree().process_frame
	
	var selected_card = selection_data[0]
	
	if selection_label:
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await tween.finished
		selection_label.hide()
	
	for card in opponent_hand:
		if card.has_method("disable_swap_selection"):
			card.disable_swap_selection()
	
	return selected_card


func _show_peek_hand_showcase(opponent_card: Node) -> String:
	"""
	Show the opponent's card in the ShowCase UI and wait for player choice.
	Returns "swap" or "keep".
	"""
	var showcase = _setup_showcase()
	if not showcase:
		return "keep"
	
	# Get the card name from the opponent's card
	var actual_card = opponent_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if not actual_card or not "card_data" in actual_card:
		return "keep"
	
	var card_name = actual_card.card_data.get("name", "")
	if card_name == "":
		return "keep"
	
	# Get the card data
	var card_data_loader = get_node_or_null("/root/CardDataLoader")
	if not card_data_loader:
		return "keep"
	
	var card_data = card_data_loader.get_card_data(card_name)
	if card_data.is_empty():
		return "keep"
	
	# Create a temporary card to display
	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager or not card_manager.card_scene:
		return "keep"
	
	var temp_card = card_manager.card_scene.instantiate()
	
	var showcase_slot = showcase.get_node_or_null("ShowCaseSlot")
	if not showcase_slot:
		temp_card.queue_free()
		return "keep"
	
	# Add the temp card to the showcase
	showcase_slot.add_child(temp_card)
	temp_card.position = Vector2(250, 350)  # Center in the 500x700 slot
	temp_card.rotation = 0
	temp_card.scale = Vector2(1, 1)
	
	# Disable card dragging but keep hover effects
	if "is_locked" in temp_card:
		temp_card.is_locked = true
	if "idle_wobble_enabled" in temp_card:
		temp_card.idle_wobble_enabled = false
	
	# Enable hover behavior for info screen
	if "can_hover" in temp_card:
		temp_card.can_hover = true
	
	# Wait a frame for the card to be ready
	await get_tree().process_frame
	
	# Set the card data
	var temp_actual_card = temp_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if temp_actual_card and temp_actual_card.has_method("set_card_data"):
		temp_actual_card.set_card_data(card_name)
	
	# Make sure card is face up
	if temp_card.has_method("flip_card"):
		var card_back = temp_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card/CardBack")
		if card_back and card_back.visible:
			temp_card.flip_card()
			await get_tree().create_timer(0.3).timeout
	
	# Update button label
	var swap_label = showcase.get_node_or_null("ShowCaseButtons/SwapDrawButton/Label")
	if swap_label:
		swap_label.text = "Swap"
	
	# Show the overlay
	var overlay = get_node_or_null("/root/main/FrontLayerUI/Overlay")
	if overlay:
		overlay.modulate = Color(1, 1, 1, 0)
		overlay.show()
		var overlay_tween = create_tween()
		overlay_tween.tween_property(overlay, "modulate:a", 0.7, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Show the showcase
	showcase.modulate = Color(1, 1, 1, 0)
	showcase.show()
	var tween = create_tween()
	tween.tween_property(showcase, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	# Wait for button press
	var choice = await _wait_for_showcase_choice(showcase)
	
	# Fade out showcase and overlay
	var fade_tween = create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(showcase, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if overlay:
		fade_tween.tween_property(overlay, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await fade_tween.finished
	showcase.hide()
	if overlay:
		overlay.hide()
	
	# Clean up the temporary card
	temp_card.queue_free()
	
	return choice


func _show_peek_deck_showcase(card_name: String) -> String:
	"""
	Show the top deck card in the ShowCase UI and wait for player choice.
	Returns "draw" or "keep".
	"""
	var showcase = _setup_showcase()
	if not showcase:
		return "keep"
	
	# Get the card data
	var card_data_loader = get_node_or_null("/root/CardDataLoader")
	if not card_data_loader:
		return "keep"
	
	var card_data = card_data_loader.get_card_data(card_name)
	if card_data.is_empty():
		return "keep"
	
	# Create a temporary card to display
	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager or not card_manager.card_scene:
		return "keep"
	
	var temp_card = card_manager.card_scene.instantiate()
	
	var showcase_slot = showcase.get_node_or_null("ShowCaseSlot")
	if not showcase_slot:
		temp_card.queue_free()
		return "keep"
	
	# Add the temp card to the showcase
	showcase_slot.add_child(temp_card)
	temp_card.position = Vector2(250, 350)  # Center in the 500x700 slot
	temp_card.rotation = 0
	temp_card.scale = Vector2(1, 1)
	
	# Disable card dragging but keep hover effects
	if "is_locked" in temp_card:
		temp_card.is_locked = true
	if "idle_wobble_enabled" in temp_card:
		temp_card.idle_wobble_enabled = false
	
	# Enable hover behavior for info screen
	if "can_hover" in temp_card:
		temp_card.can_hover = true
	
	# Wait a frame for the card to be ready
	await get_tree().process_frame
	
	# Set the card data
	var actual_card = temp_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if actual_card and actual_card.has_method("set_card_data"):
		actual_card.set_card_data(card_name)
	
	# Make sure card is face up
	if temp_card.has_method("flip_card"):
		var card_back = temp_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card/CardBack")
		if card_back and card_back.visible:
			temp_card.flip_card()
	
	# Update button label
	var draw_label = showcase.get_node_or_null("ShowCaseButtons/SwapDrawButton/Label")
	if draw_label:
		draw_label.text = "Draw"
	
	# Show the overlay
	var overlay = get_node_or_null("/root/main/FrontLayerUI/Overlay")
	if overlay:
		overlay.modulate = Color(1, 1, 1, 0)
		overlay.show()
		var overlay_tween = create_tween()
		overlay_tween.tween_property(overlay, "modulate:a", 0.7, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Show the showcase
	showcase.modulate = Color(1, 1, 1, 0)
	showcase.show()
	var tween = create_tween()
	tween.tween_property(showcase, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.finished
	
	# Wait for button press
	var choice = await _wait_for_showcase_choice(showcase)
	
	# Fade out showcase and overlay
	var fade_tween = create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(showcase, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if overlay:
		fade_tween.tween_property(overlay, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await fade_tween.finished
	showcase.hide()
	if overlay:
		overlay.hide()
	
	# Clean up the temporary card
	temp_card.queue_free()
	
	return choice


func _setup_showcase() -> Node:
	"""
	Set up the ShowCase UI. Returns the showcase node or null if not found.
	"""
	# First check if showcase already exists in the scene
	var showcase = get_node_or_null("/root/main/FrontLayerUI/ShowCase")
	
	if not showcase:
		# Try to instance it if it doesn't exist
		var showcase_scene = load("res://Scenes/UI/show_case.tscn")
		if showcase_scene:
			showcase = showcase_scene.instantiate()
			var front_layer = get_node_or_null("/root/main/FrontLayerUI")
			if front_layer:
				front_layer.add_child(showcase)
				showcase.hide()
			else:
				push_error("EffectsManager: FrontLayerUI not found")
				return null
		else:
			push_error("EffectsManager: Could not load show_case.tscn")
			return null
	
	return showcase


func _wait_for_showcase_choice(showcase: Node) -> String:
	"""
	Wait for the player to press either the Swap/Draw button or Keep button.
	Returns "swap"/"draw" or "keep".
	"""
	var choice_data = [""]
	
	var swap_draw_button = showcase.get_node_or_null("ShowCaseButtons/SwapDrawButton")
	var keep_button = showcase.get_node_or_null("ShowCaseButtons/KeepButton")
	
	if not swap_draw_button or not keep_button:
		push_error("EffectsManager: ShowCase buttons not found")
		return "keep"
	
	# Get the button label to determine what action to return
	var button_label = showcase.get_node_or_null("ShowCaseButtons/SwapDrawButton/Label")
	var button_action = "swap"  # Default
	if button_label and button_label.text == "Draw":
		button_action = "draw"
	
	var audio_manager = get_node_or_null("/root/main/Managers/AudioManager")
	
	var action_pressed = func():
		if audio_manager and audio_manager.has_method("play_button_press"):
			audio_manager.play_button_press()
		choice_data[0] = button_action
	var keep_pressed = func():
		if audio_manager and audio_manager.has_method("play_button_press"):
			audio_manager.play_button_press()
		choice_data[0] = "keep"
	
	swap_draw_button.connect("pressed", action_pressed)
	keep_button.connect("pressed", keep_pressed)
	
	while choice_data[0] == "":
		await get_tree().process_frame
	
	swap_draw_button.disconnect("pressed", action_pressed)
	keep_button.disconnect("pressed", keep_pressed)
	
	return choice_data[0]


func _return_peek_card_to_hand(peek_card_node: Node) -> void:
	"""
	Return the peek card from the play area back to the player's hand.
	"""
	if not is_instance_valid(peek_card_node):
		return
	
	# Get the play area slot
	var drop_zone = get_node_or_null("/root/main/Parallax/DropZone")
	if not drop_zone:
		return
	
	var play_area_slot = drop_zone.get_node_or_null("PlayAreaCardSlot")
	if not play_area_slot:
		return
	
	# Remove from play area
	if peek_card_node.get_parent() == play_area_slot:
		play_area_slot.remove_child(peek_card_node)
	
	# Reset card state
	if "is_in_play_area" in peek_card_node:
		peek_card_node.is_in_play_area = false
	if "is_dragging" in peek_card_node:
		peek_card_node.is_dragging = false
	if peek_card_node.has_method("set_locked"):
		peek_card_node.set_locked(true)
	
	# Reset rotation
	peek_card_node.rotation = 0
	if peek_card_node.has_node("VisualsContainer/Visuals"):
		peek_card_node.get_node("VisualsContainer/Visuals").rotation = 0
	
	# Re-parent to CardManager
	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if card_manager and peek_card_node.get_parent() != card_manager:
		card_manager.add_child(peek_card_node)
	
	# Relayout the hand
	if card_manager:
		await get_tree().process_frame
		card_manager.relayout_hand(true)
		await get_tree().process_frame


func _execute_peek_hand_ai(card_node: Node) -> void:
	"""AI version of PeekHand - highlights player cards and makes a random choice."""
	var selection_label = get_node_or_null("/root/main/FrontLayerUI/SelectionModeLabel")
	if selection_label:
		selection_label.text = "Opponent is peeking..."
		selection_label.modulate = Color(1, 1, 1, 0)
		selection_label.show()
		
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Get all player cards
	var player_hand = get_tree().get_nodes_in_group("player_hand")
	if player_hand.is_empty():
		if selection_label:
			selection_label.hide()
		await _return_peek_card_to_hand(card_node)
		_consume_action_for_player(false)
		return
	
	# Enable selection highlighting on all player cards
	for card in player_hand:
		if card.has_method("enable_swap_selection"):
			card.enable_swap_selection()
	
	# Thinking time - randomly highlight cards
	var thinking_time = randf_range(1.5, 3.0)
	var elapsed = 0.0
	var highlight_interval = 0.3
	var time_since_highlight = 0.0
	
	while elapsed < thinking_time:
		await get_tree().process_frame
		var delta = get_tree().root.get_process_delta_time()
		elapsed += delta
		time_since_highlight += delta
		
		# Every interval, toggle highlight on a random card
		if time_since_highlight >= highlight_interval:
			time_since_highlight = 0.0
			var random_card = player_hand[randi() % player_hand.size()]
			# Just re-enable to refresh the highlight effect
			if random_card.has_method("enable_swap_selection"):
				random_card.enable_swap_selection()
	
	# Pick a random card to "peek" at
	var selected_card = player_hand[randi() % player_hand.size()]
	
	# Hide label
	if selection_label:
		var label_tween = create_tween()
		label_tween.tween_property(selection_label, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await label_tween.finished
		selection_label.hide()
	
	# Disable selection highlighting
	for card in player_hand:
		if card.has_method("disable_swap_selection"):
			card.disable_swap_selection()
	
	# AI makes a random choice: 50% swap, 50% keep
	var should_swap = randf() < 0.5
	
	if should_swap:
		# Perform the swap animation
		await _perform_swap_animation(card_node, selected_card)
		await get_tree().create_timer(0.1).timeout
		_consume_action_for_player(false)
		await get_tree().create_timer(0.2).timeout
		_relock_dropzone_cards()
	else:
		# Keep the peek card, return it to hand
		await _return_peek_card_to_hand(card_node)
		_consume_action_for_player(false)

func _execute_swap_ai(card_node):
	print("EffectsManager: AI executing Swap card")
	
	# Show "Opponent is swapping..." label
	var selection_label = get_node_or_null("/root/main/FrontLayerUI/SelectionModeLabel")
	if selection_label:
		selection_label.text = "Opponent is swapping..."
		selection_label.modulate = Color(1, 1, 1, 0)
		selection_label.show()
		
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Get all player cards
	var player_cards = get_tree().get_nodes_in_group("player_hand")
	if player_cards.is_empty():
		print("EffectsManager: No player cards found for AI swap")
		_consume_action_for_player(false)
		return
	
	# Enable swap selection visuals on all player cards
	for player_card in player_cards:
		if player_card.has_method("enable_swap_selection"):
			player_card.enable_swap_selection()
	
	# Thinking time with random highlighting
	var thinking_time = randf_range(1.0, 2.0)
	var highlight_interval = 0.3
	var elapsed = 0.0
	
	while elapsed < thinking_time:
		# Randomly highlight a player card
		var random_card = player_cards[randi() % player_cards.size()]
		if random_card.has_method("highlight_for_swap"):
			random_card.highlight_for_swap()
		
		await get_tree().create_timer(highlight_interval).timeout
		elapsed += highlight_interval
	
	# Pick a random player card to swap with
	var target_card = player_cards[randi() % player_cards.size()]
	print("EffectsManager: AI chose to swap with player card: ", target_card.name)
	
	# Disable swap selection on all cards
	for player_card in player_cards:
		if player_card.has_method("disable_swap_selection"):
			player_card.disable_swap_selection()
	
	# Hide selection label
	if selection_label:
		var hide_tween = create_tween()
		hide_tween.tween_property(selection_label, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await hide_tween.finished
		selection_label.hide()
	
	# Perform the swap animation
	await _perform_swap_animation(card_node, target_card)
	
	# Consume action and relock cards
	_consume_action_for_player(false)
	
	await get_tree().create_timer(0.2).timeout
	_relock_dropzone_cards()


func _execute_peek_deck_ai(card_node: Node) -> void:
	"""AI version of PeekDeck - shows thinking message and makes a random choice."""
	var selection_label = get_node_or_null("/root/main/FrontLayerUI/SelectionModeLabel")
	if selection_label:
		selection_label.text = "Opponent is peeking..."
		selection_label.modulate = Color(1, 1, 1, 0)
		selection_label.show()
		
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# AI thinking time
	var thinking_time = randf_range(1.5, 3.0)
	await get_tree().create_timer(thinking_time).timeout
	
	# Hide label
	if selection_label:
		var label_tween = create_tween()
		label_tween.tween_property(selection_label, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await label_tween.finished
		selection_label.hide()
	
	# AI makes a random choice: 50% draw, 50% keep
	var should_draw = randf() < 0.5
	
	if should_draw:
		# First draw the new card
		var new_card = await card_manager.draw_single_card_to_hand(false)  # false = opponent card
		
		if is_instance_valid(new_card) and new_card.has_method("set_locked"):
			new_card.set_locked(true)
		
		await get_tree().create_timer(0.3).timeout
		
		# Apply disintegration to the peek card before discarding
		if is_instance_valid(card_node) and card_node.has_method("apply_disintegration"):
			var drop_zone = get_node_or_null("/root/main/Parallax/DropZone")
			if drop_zone and "disintegration_shader" in drop_zone and drop_zone.disintegration_shader:
				card_node.apply_disintegration(
					drop_zone.disintegration_shader,
					0.0,
					1.0,
					1.5,
					Tween.EASE_IN,
					Tween.TRANS_SINE
				)
				# Wait for disintegration to complete
				await get_tree().create_timer(1.5).timeout
		
		# THEN discard the peek card to the discard pile
		var main_node = get_node_or_null("/root/main")
		if main_node and main_node.has_method("add_to_discard_pile") and is_instance_valid(card_node):
			main_node.add_to_discard_pile(card_node)
		
		await get_tree().create_timer(0.1).timeout
		_consume_action_for_player(false)
		
		await get_tree().create_timer(0.2).timeout
		_relock_dropzone_cards()
	else:
		# Keep the peek card, return it to hand
		await _return_peek_card_to_hand(card_node)
		_consume_action_for_player(false)
