extends Node2D

@export_group("Scene References")
# Path to the Parallax node (set in the Inspector if you move it)
@export var parallax_path: NodePath = NodePath("Parallax")

@export_group("Discard Pile")
# Drag and drop your DiscardPile node here in the Inspector
@export var discard_pile_node: Node2D

@onready var parallax_node: Control = get_node_or_null(parallax_path)
@onready var card_manager: Node = null
@onready var deck_node: Node = null

func _ready() -> void:
	# Re-resolve nodes at runtime in case scene tree changed while editing
	if not is_instance_valid(parallax_node):
		parallax_node = get_node_or_null(parallax_path)
	
	if is_instance_valid(parallax_node):
		card_manager = parallax_node.get_node_or_null("CardManager")
		deck_node = parallax_node.get_node_or_null("Deck")

## Call this function when a card is played.
func add_to_discard_pile(card: Node2D) -> void:
	if not is_instance_valid(discard_pile_node):
		push_error("Main: DiscardPile node is not set.")
		return
	
	# Delegate to the discard pile's add_card method
	if discard_pile_node.has_method("add_card"):
		discard_pile_node.add_card(card)
	else:
		push_error("Main: DiscardPile node has no add_card method.")
