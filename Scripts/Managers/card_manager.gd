extends Node2D

signal draw_started

# --- EXPORT VARIABLES (Set these in the Inspector) ---
@export var card_scene: PackedScene
@export var deck_node: Node2D # Drag your Deck node here

# --- RUNTIME VARIABLES (Set by RoundManager before drawing) ---
var card_size: Vector2 = Vector2(500, 700)
var card_spacing: float = 150.0
var fan_angle_degrees: float = 15.0

var deck: Array = []
var draw_index: int = 0
var last_deck_remaining: int = -1
var deck_counter_tween: Tween

# --- Draw animation tuning ---
@export_group("Draw Animation")
@export var draw_base_duration: float = 0.5
@export var draw_stagger: float = 0.075
@export var relayout_duration: float = 0.28
@export var relayout_stagger: float = 0.02

# --- Flip tuning ---
@export_group("Flip / Reveal")
@export var flip_on_player_draw: bool = true
@export var flip_during_fraction: float = 0.6
@export var flip_pre_pop_scale: float = 1.08
@export var flip_pre_pop_duration: float = 0.06
@export var flip_time_jitter: float = 0.03

var hand_tween: Tween

@export_group("Deck Counter - Flicker")
@export var flicker_steps: int = 8
@export var flicker_step_time: float = 0.04
@export var flicker_stagger: float = 0.06
@export var flicker_blank_chance: float = 0.2
@export var flicker_final_pause: float = 0.04

func _ready() -> void:
	_initialize_deck()

func _initialize_deck() -> void:
	# Use the global CardDataLoader singleton
	if is_instance_valid(CardDataLoader):
		deck = CardDataLoader.get_deck_composition()
		if deck.is_empty():
			push_warning("[CardManager] Deck composition is empty after loading from CardDataLoader!")
		else:
			deck.shuffle()
	else:
		push_error("[CardManager] CardDataLoader global not found - deck will be empty")

	draw_index = 0
	_update_deck_counter()

func _ensure_card_scene() -> bool:
	if not card_scene:
		push_error("CardManager: card_scene is not set!")
		return false
	return true

func draw_cards(number: int, start_pos: Vector2, _hand_center_pos: Vector2, face_up: bool = true, is_player: bool = true) -> void:
	emit_signal("draw_started")
	
	# Use global InfoScreenManager
	if is_instance_valid(InfoScreenManager) and InfoScreenManager.has_method("clear"):
		InfoScreenManager.clear()

	if number <= 0 or not _ensure_card_scene():
		return

	var hand_slots_path: String = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root: Node = get_node_or_null(hand_slots_path)
	
	face_up = false if is_player else false

	var slot_positions: Array[Node] = []
	if not is_instance_valid(hand_slots_root):
		push_error("[CardManager] ERROR: HandSlots not found at path '%s'" % hand_slots_path)
		return
	
	for slot in hand_slots_root.get_children():
		if is_instance_valid(slot):
			slot_positions.append(slot)
	
	if slot_positions.is_empty():
		push_error("[CardManager] ERROR: No valid hand slots found for %s!" % ("player" if is_player else "opponent"))
		return
	
	if hand_tween and hand_tween.is_running():
		hand_tween.kill()
	hand_tween = null

	for i in range(number):
		var card_instance: Node2D = card_scene.instantiate()
		add_child(card_instance)
		
		if draw_index < deck.size() and card_instance.has_method("set_card_data"):
			var card_name: StringName = deck[draw_index]
			card_instance.set_card_data(card_name)
			draw_index += 1
			_update_deck_counter()
		else:
			push_warning("[CardManager] WARNING: No card data available or method missing!")
		
		var target_slot: Node2D = slot_positions[i] if i < slot_positions.size() else slot_positions[slot_positions.size() - 1]
		
		if is_instance_valid(deck_node) and card_instance is CanvasItem:
			card_instance.z_index = (deck_node as CanvasItem).z_index + 10
		elif card_instance is CanvasItem:
			card_instance.z_index = 100

		if "start_face_up" in card_instance:
			card_instance.start_face_up = face_up
			if card_instance.has_method("apply_start_face_up"):
				card_instance.apply_start_face_up()
		if "is_player_card" in card_instance:
			card_instance.is_player_card = is_player
		if "card_index" in card_instance:
			card_instance.card_index = i

		var base_card_size := Vector2(500, 700)
		card_instance.scale = (card_size / base_card_size) * 0.9

		var spawn_pos: Vector2 = start_pos
		if is_instance_valid(deck_node):
			var top_card: Node2D = deck_node.get_node_or_null("TopCard")
			if is_instance_valid(top_card):
				spawn_pos = top_card.global_position + Vector2(0, -12)
			else:
				spawn_pos = (deck_node as Node2D).global_position + Vector2(0, -20)
		card_instance.global_position = spawn_pos
		card_instance.rotation = 0.0

		var slot_global_pos: Vector2 = target_slot.global_position
		var slot_global_rot: float = target_slot.global_rotation
		var duration: float = draw_base_duration

		var arc_height: float = clamp((spawn_pos.y - slot_global_pos.y) * 0.3, -120, -30)
		var mid_pos := Vector2(lerp(spawn_pos.x, slot_global_pos.x, 0.5), lerp(spawn_pos.y, slot_global_pos.y, 0.5) + arc_height)
		var t1: float = duration * 0.55
		var t2: float = max(0.01, duration - t1)
		var t: Tween = create_tween()
		
		t.tween_property(card_instance, "global_position", mid_pos, t1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(card_instance, "rotation", lerp(0.0, slot_global_rot * 0.3, 0.7), t1)
		t.parallel().tween_property(card_instance, "scale", card_size / base_card_size, t1 * 0.6)
		
		t.tween_property(card_instance, "global_position", slot_global_pos, t2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.parallel().tween_property(card_instance, "rotation", slot_global_rot, t2)
		t.parallel().tween_property(card_instance, "scale", card_size / base_card_size, t2)

		if card_instance.has_node("Visuals/Shadow"):
			var shadow_node: Node2D = card_instance.get_node("Visuals/Shadow")
			t.parallel().tween_property(shadow_node, "scale", Vector2(0.9, 0.9), t1)
			t.parallel().tween_property(shadow_node, "scale", Vector2(1.1, 1.1), t2)

		await t.finished

		var pop_t: Tween = create_tween()
		pop_t.tween_property(card_instance, "scale", (card_size / base_card_size) * 1.05, 0.08).set_ease(Tween.EASE_OUT)
		pop_t.tween_property(card_instance, "scale", card_size / base_card_size, 0.12).set_delay(0.08).set_ease(Tween.EASE_IN)

		if is_instance_valid(card_instance) and card_instance.has_method("set_home_position"):
			card_instance.set_home_position(slot_global_pos, slot_global_rot)

		if not face_up and flip_on_player_draw and is_player and card_instance.has_method("flip_card"):
			card_instance.flip_card()

		if draw_stagger > 0:
			await get_tree().create_timer(draw_stagger).timeout


func _set_home_after_delay(card_instance: Node2D, final_pos: Vector2, final_rot: float, delay: float) -> void:
	if not is_instance_valid(card_instance):
		return
	var t: Tween = create_tween()
	t.tween_interval(delay)
	t.tween_callback(func():
		if is_instance_valid(card_instance) and card_instance.is_inside_tree():
			if card_instance.has_method("set_home_position"):
				card_instance.set_home_position(final_pos, final_rot)
			else:
				card_instance.global_position = final_pos
				card_instance.rotation = final_rot
	)


func _get_hand_slot_positions(is_player: bool = true) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var hand_slots_path: String = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root: Node = get_node_or_null(hand_slots_path)
	if not is_instance_valid(hand_slots_root):
		return slots
	for slot in hand_slots_root.get_children():
		if is_instance_valid(slot) and slot is Node2D:
			slots.append({"global_pos": (slot as Node2D).global_position, "rot": (slot as Node2D).rotation})
	return slots


func _update_deck_counter() -> void:
	# Use the exported deck_node variable
	if not is_instance_valid(deck_node):
		return
	var counter: Control = deck_node.get_node_or_null("DeckCounter")
	if not is_instance_valid(counter):
		return
		
	var remaining: int = max(0, deck.size() - draw_index)
	
	var tens: int = int(remaining / 10.0) % 10
	var ones: int = int(remaining % 10)

	var no_label: Label = counter.get_node_or_null("HBoxContainer/NoValueLabel")
	var d1_label: Label = counter.get_node_or_null("HBoxContainer/DeckDigit1Label")
	var d2_label: Label = counter.get_node_or_null("HBoxContainer/DeckDigit2Label")

	if is_instance_valid(no_label):
		no_label.text = "0"
	if is_instance_valid(d1_label):
		d1_label.text = str(tens)
	if is_instance_valid(d2_label):
		d2_label.text = str(ones)

	if last_deck_remaining != remaining:
		last_deck_remaining = remaining
		if is_instance_valid(d1_label):
			_flicker_gauge_label(d1_label, tens, 0.0)
		if is_instance_valid(d2_label):
			_flicker_gauge_label(d2_label, ones, flicker_stagger)


func _flicker_gauge_label(lbl: Label, final_digit: int, delay: float = 0.0) -> void:
	if not is_instance_valid(lbl) or not lbl.is_inside_tree():
		return

	var t: Tween = create_tween()
	if delay > 0.0:
		t.tween_interval(delay)

	for i in range(flicker_steps):
		var dt: float = flicker_step_time
		var show_blank: bool = randf() < flicker_blank_chance
		var rnd_digit: String = str(randi() % 10)
		if show_blank:
			t.tween_callback(func():
				if is_instance_valid(lbl):
					lbl.text = " "
			)
		else:
			t.tween_callback(func():
				if is_instance_valid(lbl):
					lbl.text = rnd_digit
			)
		t.tween_interval(dt)

	t.tween_interval(flicker_final_pause)
	t.tween_callback(func():
		if is_instance_valid(lbl):
			lbl.text = str(final_digit)
	)


func get_hand_cards(is_player: bool = true) -> Array[Node2D]:
	var cards: Array[Node2D] = []
	for child in get_children():
		if child and "is_player_card" in child and child.is_player_card == is_player:
			cards.append(child as Node2D)
	return cards


func draw_single_card_to_hand(is_player: bool) -> Node2D:
	if is_deck_depleted():
		return null

	var hand_slots_path: String = "../HandSlots" if is_player else "../OpponentHandSlots"
	var hand_slots_root: Node = get_node_or_null(hand_slots_path)
	if not is_instance_valid(hand_slots_root):
		push_error("CardManager: Cannot find hand slots at %s" % hand_slots_path)
		return null

	var existing_cards_count: int = get_hand_cards(is_player).size()
	var all_slots: Array[Node] = hand_slots_root.get_children()

	if existing_cards_count >= all_slots.size():
		return null

	var target_slot: Node2D = all_slots[existing_cards_count]

	var card_instance: Node2D = card_scene.instantiate()
	card_instance.scale = Vector2(0.4, 0.4)
	add_child(card_instance)

	if draw_index < deck.size():
		var card_name: StringName = deck[draw_index]
		card_instance.set_card_data(card_name)
		draw_index += 1
		_update_deck_counter()

	card_instance.is_player_card = is_player
	card_instance.card_index = existing_cards_count

	# Use exported deck_node
	card_instance.global_position = (deck_node as Node2D).global_position if is_instance_valid(deck_node) else self.global_position

	var tween: Tween = create_tween()
	tween.tween_property(card_instance, "global_position", target_slot.global_position, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(card_instance, "rotation", target_slot.rotation, 0.6)

	await tween.finished

	if card_instance.has_method("set_home_position"):
		card_instance.set_home_position(target_slot.global_position, target_slot.rotation)

	if has_method("relayout_hand"):
		relayout_hand(is_player)

	return card_instance


func instantiate_top_card_for_peek() -> Node2D:
	if is_deck_depleted():
		return null

	var card_instance: Node2D = card_scene.instantiate()
	var card_name: StringName = deck[draw_index]
	if card_instance.has_method("set_card_data"):
		card_instance.set_card_data(card_name)

	card_instance.set_meta("is_temp_peek", true)
	return card_instance


func is_deck_depleted() -> bool:
	return draw_index >= deck.size()


func discard_all_hands() -> void:
	var all_cards: Array[Node2D] = get_hand_cards(true) + get_hand_cards(false)

	if all_cards.is_empty():
		return

	# Get discard pile from GameManager
	var discard_pile: Node = GameManager.get_manager("DiscardPile")
	var target_global_pos: Vector2
	
	if is_instance_valid(discard_pile) and discard_pile is Node2D:
		target_global_pos = (discard_pile as Node2D).global_position
	else:
		push_warning("CardManager: DiscardPile not found or invalid. Discarding to screen center.")
		var vp: Rect2 = get_viewport().get_visible_rect()
		target_global_pos = vp.position + vp.size * 0.5

	var move_duration: float = 0.36
	var dz_shader: Shader = null
	for zone in get_tree().get_nodes_in_group("drop_zones"):
		if is_instance_valid(zone) and zone.has_method("on_card_dropped") and "disintegration_shader" in zone:
			dz_shader = zone.disintegration_shader
			break

	var anim_tweens: Array[Dictionary] = []
	var disintegrating_cards: Array[Node] = []
	var scene_root: Node = get_tree().get_current_scene()

	for card in all_cards:
		if not is_instance_valid(card):
			continue

		if is_instance_valid(scene_root) and card.get_parent() != scene_root:
			card.get_parent().remove_child(card)
			scene_root.add_child(card)

		if card.has_method("apply_disintegration"):
			card.apply_disintegration(dz_shader, 0.0, 1.0, 0.9, Tween.EASE_IN, Tween.TRANS_SINE)
			disintegrating_cards.append(card)
		else:
			var spawn_pos: Vector2 = card.global_position
			var mid_pos := Vector2(lerp(spawn_pos.x, target_global_pos.x, 0.5), lerp(spawn_pos.y, target_global_pos.y, 0.5) - 120)
			var t: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			t.tween_method(func(progress: float):
				var p1: Vector2 = spawn_pos.lerp(mid_pos, progress)
				var p2: Vector2 = mid_pos.lerp(target_global_pos, progress)
				if is_instance_valid(card):
					card.global_position = p1.lerp(p2, progress)
			, 0.0, 1.0, move_duration)
			if card is CanvasItem:
				t.parallel().tween_property(card, "scale", card.scale * 0.92, move_duration * 0.6)
				t.parallel().tween_property(card, "rotation", card.rotation + deg_to_rad(6.0), move_duration)
			anim_tweens.append({"tween": t, "card": card})

	# Wait for all non-disintegration tweens to finish
	for entry in anim_tweens:
		await (entry["tween"] as Tween).finished
		var c: Node2D = entry["card"]
		# Standardize on using DiscardPile manager
		if is_instance_valid(discard_pile) and discard_pile.has_method("add_card") and is_instance_valid(c):
			discard_pile.add_card(c)
		elif is_instance_valid(c):
			c.queue_free() # Fallback

	# Now wait for disintegrating cards
	var waited_total: float = 0.0
	var poll_dt: float = 0.05
	var timeout_total: float = 6.0
	
	if disintegrating_cards.size() > 0:
		while waited_total < timeout_total:
			var all_done: bool = true
			for dcard in disintegrating_cards:
				if not is_instance_valid(dcard):
					continue
				if is_instance_valid(discard_pile):
					if dcard.get_parent() != discard_pile:
						all_done = false
						break
				else:
					all_done = false
					break
			if all_done:
				break
			await get_tree().create_timer(poll_dt).timeout
			waited_total += poll_dt
		if not is_instance_valid(discard_pile):
			await get_tree().create_timer(0.9).timeout

	relayout_hand(true)
	relayout_hand(false)


func relayout_hand(is_player: bool = true) -> void:
	var cards: Array[Node2D] = []
	for child in get_children():
		if is_instance_valid(child) and child.has_method("set_home_position"):
			if "is_player_card" in child:
				if is_player and not child.is_player_card:
					continue
				if not is_player and child.is_player_card:
					continue
			cards.append(child as Node2D)

	cards.sort_custom(_sort_hand_cards)

	var slots: Array[Dictionary] = _get_hand_slot_positions(is_player)
	if slots.is_empty():
		return

	for i in range(cards.size()):
		var card: Node2D = cards[i]
		if not is_instance_valid(card):
			continue
		
		if "card_index" in card:
			card.card_index = i
		
		var slot: Dictionary = slots[i] if i < slots.size() else slots[slots.size() - 1]
		var slot_pos: Vector2 = slot["global_pos"]
		var slot_rot: float = slot["rot"]
		
		card.set_home_position(slot_pos, slot_rot)
		
		var t: Tween = create_tween()
		t.tween_property(card, "global_position", slot_pos, relayout_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.parallel().tween_property(card, "rotation", slot_rot, relayout_duration)
		
		_set_home_after_delay(card, slot_pos, slot_rot, relayout_duration)
		
		if card.has_method("set_locked") and "is_locked" in card:
			card.z_index = 200 + i if not card.is_locked else 100 + i
		else:
			card.z_index = 200 + i
		
		if relayout_stagger > 0:
			await get_tree().create_timer(relayout_stagger).timeout

# Custom sort: unlocked cards first, then locked, each by card_index
func _sort_hand_cards(a: Node2D, b: Node2D) -> bool:
	var a_locked: bool = ("is_locked" in a and a.is_locked)
	var b_locked: bool = ("is_locked" in b and b.is_locked)
	if a_locked == b_locked:
		var ai: int = a.card_index if "card_index" in a else 0
		var bi: int = b.card_index if "card_index" in b else 0
		return ai < bi
	return not a_locked # (unlocked < locked)

func _sort_by_card_index(a: Node2D, b: Node2D) -> bool:
	var ai: int = a.card_index if "card_index" in a else 0
	var bi: int = b.card_index if "card_index" in b else 0
	return ai < bi
