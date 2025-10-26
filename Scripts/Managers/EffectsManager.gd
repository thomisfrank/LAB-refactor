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
			_execute_draw(card_node)
		"peekdeck":
			print("[EffectsManager] PeekDeck not implemented yet")
		"peekhand":
			print("[EffectsManager] PeekHand not implemented yet")
		"swap":
			_execute_swap(card_node)
		_:
			print("[EffectsManager] No effect found for card: %s" % actual_card.card_data.get("name", "Unknown"))

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

	await get_tree().create_timer(0.3).timeout
	
	await _enter_swap_selection_state(card_node)


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
	
	if card_manager:
		card_manager.relayout_hand(true)
		card_manager.relayout_hand(false)
	
	opponent_card.z_index = original_z_index
