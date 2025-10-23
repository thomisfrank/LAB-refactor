extends Node

@export var move_offset: Vector2 = Vector2(150, 0)
@export var lift_height: float = 80.0
@export var lift_duration: float = 0.3
@export var rotate_duration: float = 0.3
@export var move_duration: float = 0.6

var game_manager: Node = null
var card_manager: Node = null


func _ready() -> void:
	# GameManager is a global autoload.
	game_manager = GameManager
	if game_manager and game_manager.has_method("register_manager"):
		game_manager.register_manager("AIManager", self)
	else:
		push_error("AIManager: Could not register with global GameManager.")

func _resolve_card_manager() -> void:
	if is_instance_valid(card_manager):
		return
		
	if is_instance_valid(game_manager) and game_manager.has_method("get_manager"):
		card_manager = game_manager.get_manager("CardManager")
	
	if not is_instance_valid(card_manager):
		push_error("AIManager: CardManager not found via GameManager.")

func on_ai_turn() -> void:
	_resolve_card_manager()
	if not is_instance_valid(card_manager):
		push_error("AIManager: CardManager not found; cannot move card.")
		return

	var card_node: Node2D = null
	for c in card_manager.get_children():
		if is_instance_valid(c) and "is_player_card" in c and not c.is_player_card:
			card_node = c
			break
	
	if not is_instance_valid(card_node):
		return

	var main_node: Node = get_node_or_null("/root/main")
	if is_instance_valid(main_node) and card_node.get_parent() != main_node:
		card_node.reparent(main_node)

	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	var target_position: Vector2 = vp_rect.position + vp_rect.size * 0.5 + move_offset

	# PHASE 1: Lift and Rotate
	var start_position: Vector2 = card_node.global_position
	var lifted_position: Vector2 = start_position + Vector2(0, -lift_height)
	var target_rotation: float = 0.0

	var t: Tween = create_tween()

	# Lift
	t.tween_property(card_node, "global_position", lifted_position, lift_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

	# Rotate
	t.parallel().tween_property(card_node, "rotation", target_rotation, rotate_duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	# PHASE 2: Arc Move
	t.tween_callback(_move_card_in_arc.bind(card_node, lifted_position, target_position))


func _move_card_in_arc(card_node: Node2D, start_pos: Vector2, target_pos: Vector2) -> void:
	var control_point: Vector2 = (start_pos + target_pos) / 2 + Vector2(0, -150)
	var t: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	var flip_delay: float = move_duration * 0.33
	t.tween_callback(func():
		if is_instance_valid(card_node) and card_node.has_method("flip_card"):
			card_node.flip_card()
	).set_delay(flip_delay)

	t.parallel().tween_method(func(progress: float):
		if not is_instance_valid(card_node): return
		var p1: Vector2 = start_pos.lerp(control_point, progress)
		var p2: Vector2 = control_point.lerp(target_pos, progress)
		card_node.global_position = p1.lerp(p2, progress)
	, 0.0, 1.0, move_duration)
	
	t.tween_callback(_trigger_drop_zone.bind(card_node))


func _trigger_drop_zone(card_node: Node2D) -> void:
	if not is_instance_valid(card_node):
		return

	for zone in get_tree().get_nodes_in_group("drop_zones"):
		if is_instance_valid(zone) and zone.has_method("on_card_dropped"):
			zone.on_card_dropped(card_node)
			
			var tm: Node = null
			if is_instance_valid(game_manager) and game_manager.has_method("get_manager"):
				tm = game_manager.get_manager("TurnManager")
			
			if is_instance_valid(tm) and tm.has_method("pass_current_player"):
				var should_pass_now: bool = true
				if "opponent_actions_remaining" in tm and int(tm.opponent_actions_remaining) <= 0:
					should_pass_now = false
				
				if should_pass_now:
					var main_node: Node = get_node_or_null("/root/main")
					var discard_node: Node = null
					if is_instance_valid(main_node) and "discard_pile_node" in main_node:
						discard_node = main_node.discard_pile_node
					
					if is_instance_valid(discard_node):
						var waited: float = 0.0
						var timeout: float = 5.0
						while is_instance_valid(card_node) and card_node.get_parent() != discard_node and waited < timeout:
							await get_tree().create_timer(0.05).timeout
							waited += 0.05
						
						await get_tree().create_timer(1.0).timeout
						if is_instance_valid(tm) and tm.has_method("pass_current_player"):
							tm.pass_current_player()
					else:
						# No discard node found - fallback to a simple 1s delay
						await get_tree().create_timer(1.0).timeout
						if is_instance_valid(tm) and tm.has_method("pass_current_player"):
							tm.pass_current_player()
			return
	
	push_warning("AIManager: No drop zone found to trigger card drop")