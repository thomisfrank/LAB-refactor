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

# Main entry point for resolving any card effect
func resolve_effect(card_node: Node) -> void:
	print("[EffectsManager] resolve_effect() called")

	# --- Start Debugging ---
	if not is_instance_valid(card_node):
		push_error("EffectManager: The passed 'card_node' (InteractiveCard) is itself invalid.")
		return
	print("[EffectsManager] Passed card_node is a valid instance.")

	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	
	if not is_instance_valid(actual_card):
		push_error("EffectManager: Failed to find 'actual_card' at path 'VisualsContainer/Visuals/CardViewport/SubViewport/Card'.")
		return
	print("[EffectsManager] Found 'actual_card' node.")
	
	if not "card_data" in actual_card:
		push_error("EffectManager: 'actual_card' node does NOT have the 'card_data' property.")
		# Let's print all properties to see what it does have
		print_rich("[b]Properties on actual_card:[/b]")
		for prop in actual_card.get_property_list():
			print("  - %s" % prop.name)
		return
	print("[EffectsManager] 'actual_card' has the 'card_data' property.")
	# --- End Debugging ---

	if not is_instance_valid(actual_card) or not "card_data" in actual_card:
		push_error("EffectManager: Invalid card node passed.") # Original error
		return

	var effect_type = actual_card.card_data.get("effect_type", "")
	
	# Fallback: infer effect from suit if effect_type is missing
	if effect_type == "":
		var suit = actual_card.card_data.get("suit", "")
		effect_type = suit.to_lower()
	
	print("[EffectsManager] Card effect_type: %s" % effect_type)

	match effect_type:
		"draw":
			print("[EffectsManager] Matched 'draw', calling _execute_draw()")
			_execute_draw(card_node)
		"peekdeck":
			print("[EffectsManager] Matched 'peekdeck' - not implemented yet")
		"peekhand":
			print("[EffectsManager] Matched 'peekhand' - not implemented yet")
		"swap":
			print("[EffectsManager] Matched 'swap', calling _execute_swap()")
			_execute_swap(card_node)
		_:
			print("No effect found for card: %s" % actual_card.card_data.get("name", "Unknown"))

func _execute_draw(card_node: Node) -> void:
	print("[EffectsManager] === DRAW EFFECT START ===")
	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if not actual_card:
		push_error("EffectManager: Could not find actual card node in _execute_draw.")
		return

	print("[EffectsManager] Played card: %s" % actual_card.card_data.get("name", "Unknown"))
	print("[EffectsManager] Card node path: %s" % card_node.get_path())

	# Ensure we have CardManager reference
	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager:
		push_error("EffectManager: CardManager not found")
		return
	
	print("[EffectsManager] CardManager found: %s" % card_manager.get_path())

	# Step 1: Card is already dropped into drop zone (handled by drop_zone.gd)
	# Wait a beat before proceeding
	print("[EffectsManager] Step 1: Waiting 0.3s...")
	await get_tree().create_timer(0.3).timeout
	print("[EffectsManager] Step 1: Wait complete")
	
	# Step 2: Auto-draw the top card of the deck
	print("[EffectsManager] Step 2: Drawing new card from deck...")
	var new_card = await card_manager.draw_single_card_to_hand(true)
	
	if is_instance_valid(new_card):
		var new_actual_card = new_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
		if new_actual_card and "card_data" in new_actual_card:
			print("[EffectsManager] Step 2: Card drawn successfully: %s" % new_actual_card.card_data.get("name", "Unknown"))
		# Lock the new card so it can't be played this turn
		if new_card.has_method("set_locked"):
			new_card.set_locked(true)
			print("[EffectsManager] Step 2: New card locked")
		else:
			print("[EffectsManager] Step 2: WARNING - card has no set_locked method")
	else:
		print("[EffectsManager] Step 2: WARNING - new_card is null or invalid")
	
	# Wait another beat
	print("[EffectsManager] Step 3: Waiting 0.3s...")
	await get_tree().create_timer(0.3).timeout
	print("[EffectsManager] Step 3: Wait complete")
	
	# Step 3: Discard the played card
	print("[EffectsManager] Step 4: Discarding played card...")
	var main_node = get_node_or_null("/root/main")
	if main_node:
		print("[EffectsManager] Step 4: main node found")
		if main_node.has_method("add_to_discard_pile"):
			print("[EffectsManager] Step 4: add_to_discard_pile method exists")
			if is_instance_valid(card_node):
				print("[EffectsManager] Step 4: card_node is valid, calling add_to_discard_pile")
				main_node.add_to_discard_pile(card_node)
				print("[EffectsManager] Step 4: add_to_discard_pile called")
			else:
				print("[EffectsManager] Step 4: ERROR - card_node is invalid")
		else:
			print("[EffectsManager] Step 4: ERROR - main has no add_to_discard_pile method")
	else:
		print("[EffectsManager] Step 4: ERROR - main node not found")
	
	# Note: Action consumption is handled by drop_zone.gd when the card is dropped
	# We don't call record_action_played here to avoid double-counting
	
	print("[EffectsManager] === DRAW EFFECT COMPLETE ===")


func _execute_swap(card_node: Node) -> void:
	print("[EffectsManager] === SWAP EFFECT START ===")
	var actual_card = card_node.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card")
	if not actual_card:
		push_error("EffectManager: Could not find actual card node in _execute_swap.")
		return

	print("[EffectsManager] Played card: %s" % actual_card.card_data.get("name", "Unknown"))
	print("[EffectsManager] Card node path: %s" % card_node.get_path())

	# Ensure we have CardManager reference
	if not card_manager:
		card_manager = game_manager.get_manager("CardManager")
	
	if not card_manager:
		push_error("EffectManager: CardManager not found")
		return

	# Step 1: Card is already dropped into drop zone (handled by drop_zone.gd)
	# Wait a beat before proceeding
	print("[EffectsManager] Step 1: Waiting 0.3s...")
	await get_tree().create_timer(0.3).timeout
	print("[EffectsManager] Step 1: Wait complete")
	
	# Step 2: Enter selection state and perform swap
	print("[EffectsManager] Step 2: Entering opponent card selection state...")
	await _enter_swap_selection_state(card_node)
	
	# Note: Action consumption is already handled by drop_zone.gd when the card is dropped
	# We don't need to consume it again here
	
	print("[EffectsManager] === SWAP EFFECT COMPLETE ===")


func _enter_swap_selection_state(swap_card_node: Node) -> void:
	print("[EffectsManager] Entering swap selection state...")
	
	# Show selection mode label with disintegration effect
	var selection_label = get_node_or_null("/root/main/FrontLayerUI/SelectionModeLabel")
	if selection_label:
		# Start hidden with shader at full progress
		selection_label.modulate = Color(1, 1, 1, 0)  # Fully transparent
		selection_label.show()
		
		# Fade in using modulate instead of shader
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		print("[EffectsManager] Selection mode label shown with fade effect")
	
	# Get opponent hand cards
	var opponent_hand = get_tree().get_nodes_in_group("opponent_hand")
	if opponent_hand.is_empty():
		print("[EffectsManager] ERROR: No opponent cards found!")
		print("[EffectsManager] Available groups: %s" % get_tree().get_nodes_in_group("").size())
		
		# Debug: print all groups
		for group_name in ["player_hand", "opponent_hand", "drop_zone"]:
			var nodes = get_tree().get_nodes_in_group(group_name)
			print("[EffectsManager]   Group '%s': %d nodes" % [group_name, nodes.size()])
		
		# Hide label if no opponent cards
		if selection_label:
			selection_label.hide()
		
		# Can't swap if no opponent cards - consume action but do nothing
		if turn_manager and turn_manager.has_method("consume_action"):
			turn_manager.consume_action()
		return
	
	print("[EffectsManager] Found %d opponent cards" % opponent_hand.size())
	
	# Enable selection on opponent cards (add hover overlay and click handling)
	for card in opponent_hand:
		if card.has_method("enable_swap_selection"):
			card.enable_swap_selection()
	
	# Wait for player to select a card
	print("[EffectsManager] Waiting for player to select an opponent card...")
	var selection_data = [null, false]  # [selected_card, signal_received]
	
	# Connect to all opponent cards' selection signals
	for card in opponent_hand:
		if card.has_signal("card_selected_for_swap"):
			card.card_selected_for_swap.connect(func(card_node):
				if not selection_data[1]:  # Only respond to first selection
					selection_data[1] = true  # signal_received
					selection_data[0] = card_node  # selected_card
			)
	
	# Wait until a card is selected
	while selection_data[0] == null:
		await get_tree().process_frame
	
	var selected_card = selection_data[0]
	print("[EffectsManager] Card selected! Starting swap animation...")
	
	# Hide selection mode label with fade effect
	if selection_label:
		var tween = create_tween()
		tween.tween_property(selection_label, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await tween.finished
		selection_label.hide()
		print("[EffectsManager] Selection mode label hidden with fade effect")
	
	# Disable selection state on all opponent cards
	for card in opponent_hand:
		if card.has_method("disable_swap_selection"):
			card.disable_swap_selection()
	
	# Perform the swap animation
	await _perform_swap_animation(swap_card_node, selected_card)


func _perform_swap_animation(swap_card: Node, opponent_card: Node) -> void:
	print("[EffectsManager] Performing swap animation...")
	
	# Get drop zone position for the middle animation
	var drop_zone = get_node_or_null("/root/main/Parallax/DropZone")
	var drop_zone_pos = Vector2.ZERO
	if drop_zone:
		print("[EffectsManager] Found drop zone at: %s" % drop_zone.get_path())
		# Use the DropZone's own position - this is where cards actually drop
		drop_zone_pos = drop_zone.global_position
		print("[EffectsManager] Using drop_zone center position: %s" % drop_zone_pos)
	else:
		# Fallback to screen center if drop zone not found
		print("[EffectsManager] Drop zone not found, using screen center")
		var viewport_rect = get_viewport().get_visible_rect()
		drop_zone_pos = viewport_rect.size / 2.0
	
	# Store original positions
	var swap_card_original_pos = swap_card.global_position
	var opponent_card_original_pos = opponent_card.global_position
	
	# Animation duration
	var move_duration = 0.5
	var flip_duration = 0.2
	var pause_duration = 0.3
	
	# Bring opponent card to front so it's visible during animation
	var original_z_index = opponent_card.z_index
	opponent_card.z_index = 1000
	
	# Step 1: Move opponent card to drop zone (like AI playing a card)
	print("[EffectsManager] Step 1: Moving opponent card to drop zone...")
	print("[EffectsManager]   Opponent card start pos: %s" % opponent_card.global_position)
	print("[EffectsManager]   Drop zone target pos: %s" % drop_zone_pos)
	var tween1 = create_tween()
	tween1.tween_property(opponent_card, "global_position", drop_zone_pos, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween1.finished
	print("[EffectsManager]   Opponent card arrived at: %s" % opponent_card.global_position)
	
	# Step 2: Small pause at drop zone
	print("[EffectsManager] Step 2: Pausing at drop zone...")
	await get_tree().create_timer(pause_duration).timeout
	
	# Step 3: Flip opponent card
	print("[EffectsManager] Step 3: Flipping opponent card...")
	if opponent_card.has_method("flip_card"):
		opponent_card.flip_card()
		print("[EffectsManager]   Card flipped!")
	else:
		print("[EffectsManager]   WARNING: opponent_card has no flip_card method")
	await get_tree().create_timer(flip_duration).timeout
	
	# Step 4: Move opponent card to player hand and swap card to opponent hand simultaneously
	print("[EffectsManager] Step 4: Swapping to final positions...")
	var tween2 = create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(opponent_card, "global_position", swap_card_original_pos, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween2.tween_property(swap_card, "global_position", opponent_card_original_pos, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween2.finished
	
	# Step 4: Transfer cards between hands and relayout
	print("[EffectsManager] Step 4: Transferring cards and relayouting...")
	
	# Update is_player_card flags
	print("[EffectsManager] Step 4a: Updating is_player_card flags...")
	opponent_card.is_player_card = true
	swap_card.is_player_card = false
	print("[EffectsManager] Step 4a: Flags updated")
	
	# Flip the cards to their correct orientations
	# Opponent card is already flipped face-up, keep it that way
	# Swap card needs to flip to back (face-down for opponent)
	print("[EffectsManager] Step 4b: Flipping swap card...")
	if swap_card.has_method("flip_card"):
		# Check if it's currently face-up, if so flip it
		var card_face = swap_card.get_node_or_null("VisualsContainer/Visuals/CardViewport/SubViewport/Card/CardFace")
		if card_face and card_face.visible:
			swap_card.flip_card()
			print("[EffectsManager] Flipped swap card to back (face-down)")
	print("[EffectsManager] Step 4b: Flip complete")
	
	# Update hand groups (this will remove from old group and add to new group)
	print("[EffectsManager] Step 4c: Updating hand groups...")
	if opponent_card.has_method("update_hand_group"):
		opponent_card.update_hand_group()
	if swap_card.has_method("update_hand_group"):
		swap_card.update_hand_group()
	print("[EffectsManager] Step 4c: Groups updated")
	print("[EffectsManager] Step 4c: Groups updated")
	
	# Ensure the newly acquired card is LOCKED (can't play it this turn - same as Draw effect)
	print("[EffectsManager] Step 4d: Setting card states...")
	if opponent_card.has_method("set_locked"):
		opponent_card.set_locked(true)
		print("[EffectsManager] Locked newly acquired card")
	if "is_dragging" in opponent_card:
		opponent_card.is_dragging = false
	if "is_in_play_area" in opponent_card:
		opponent_card.is_in_play_area = false
	
	# Rotate opponent card to 0 degrees for player hand (right-side up)
	opponent_card.rotation = 0
	if opponent_card.has_node("VisualsContainer/Visuals"):
		opponent_card.get_node("VisualsContainer/Visuals").rotation = 0
	
	# Make sure the swap card going to opponent is UNLOCKED (it's their card now)
	if swap_card.has_method("set_locked"):
		swap_card.set_locked(false)
	if "is_dragging" in swap_card:
		swap_card.is_dragging = false
	if "is_in_play_area" in swap_card:
		swap_card.is_in_play_area = false
	
	# Rotate swap card 180 degrees for opponent hand (upside down)
	swap_card.rotation = deg_to_rad(180)
	if swap_card.has_node("VisualsContainer/Visuals"):
		swap_card.get_node("VisualsContainer/Visuals").rotation = deg_to_rad(180)
	
	print("[EffectsManager] Step 4d: Card states set")
	
	# Reparent cards to CardManager if they aren't already
	print("[EffectsManager] Step 4e: Reparenting cards...")
	if opponent_card.get_parent() != card_manager:
		var old_parent = opponent_card.get_parent()
		if old_parent:
			old_parent.remove_child(opponent_card)
		card_manager.add_child(opponent_card)
		print("[EffectsManager] Reparented opponent_card to CardManager")
	
	if swap_card.get_parent() != card_manager:
		var old_parent = swap_card.get_parent()
		if old_parent:
			old_parent.remove_child(swap_card)
		card_manager.add_child(swap_card)
		print("[EffectsManager] Reparented swap_card to CardManager")
	
	# Ensure mouse interaction is enabled on both cards
	if opponent_card.has_node("VisualsContainer/Visuals/CardViewport"):
		var viewport = opponent_card.get_node("VisualsContainer/Visuals/CardViewport")
		viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	if swap_card.has_node("VisualsContainer/Visuals/CardViewport"):
		var viewport = swap_card.get_node("VisualsContainer/Visuals/CardViewport")
		viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	
	print("[EffectsManager] Step 4e: Reparenting complete")
	
	# Relayout both hands (this will parent them to proper slots)
	print("[EffectsManager] Step 4f: Relayouting hands...")
	if card_manager:
		card_manager.relayout_hand(true)  # Player hand
		print("[EffectsManager] Player hand relayout called")
		card_manager.relayout_hand(false)  # Opponent hand
		print("[EffectsManager] Opponent hand relayout called")
		print("[EffectsManager] Both hands relayouted")
	print("[EffectsManager] Step 4f: Relayout complete")
	
	# Restore z_index
	opponent_card.z_index = original_z_index
	
	print("[EffectsManager] Swap animation complete!")
