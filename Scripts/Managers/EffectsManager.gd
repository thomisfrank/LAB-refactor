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
			print("[EffectsManager] Matched 'swap' - not implemented yet")
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
