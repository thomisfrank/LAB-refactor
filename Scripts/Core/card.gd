extends Button

# --- Node References with Type Hints ---
# $CardFace is a direct child.
@onready var card_face: Node2D = $CardFace
# The rest are children of CardFace.
@onready var card_icon: Sprite2D = $CardFace/Icon
@onready var value_label: Label = $CardFace/ValueLabel
@onready var value_label2: Label = $CardFace/ValueLabel2
@onready var suit_label: Label = $CardFace/SuitLabel
@onready var suit_label2: Label = $CardFace/SuitLabel2
@onready var background: Sprite2D = $CardFace/Background


# --- Public Methods ---

## Resets the card's visual transform.
func set_rotation_and_scale_to_neutral() -> void:
	rotation = 0.0
	scale = Vector2.ONE

## Loads and applies card data using the global CardDataLoader.
func set_card_data(data_name: StringName) -> void:
	# Access CardDataLoader directly as it is an Autoload (global)
	var data: Dictionary = CardDataLoader.get_card_data(data_name)
	
	if data.is_empty():
		push_error("[Card] ERROR: No data found for: %s" % data_name)
		return
	
	# Store the card name on the instance
	self.name = data_name 
	
	# --- Applying Card Data ---
	if data.has(&"icon_path"):
		var texture: Texture2D = load("res://Assets/CardFramework/" + data[&"icon_path"])
		if texture and is_instance_valid(card_icon):
			card_icon.texture = texture
	
	if data.has(&"value"):
		var value_text: String = str(data[&"value"])
		if is_instance_valid(value_label):
			value_label.text = value_text
		if is_instance_valid(value_label2):
			value_label2.text = value_text
	
	if data.has(&"suit"):
		var suit_text: String = data[&"suit"]
		if is_instance_valid(suit_label):
			suit_label.text = suit_text
		if is_instance_valid(suit_label2):
			suit_label2.text = suit_text
	
	# --- Set Shader Colors ---
	if is_instance_valid(background) and background.material and data.has(&"color_a") and data.has(&"color_b") and data.has(&"color_c"):
		# CRITICAL: Duplicate the material instance so each card has unique colors
		background.material = background.material.duplicate()
		
		var color_a: Color = _array_to_color(data[&"color_a"])
		var color_b: Color = _array_to_color(data[&"color_b"])
		var color_c: Color = _array_to_color(data[&"color_c"])
		
		background.material.set_shader_parameter("color_a", color_a)
		background.material.set_shader_parameter("color_light", color_b)
		background.material.set_shader_parameter("color_mid", color_a)
		background.material.set_shader_parameter("color_dark", color_c)


## Helper: convert an array [r,g,b,(a)] to a Color safely
func _array_to_color(arr: Array) -> Color:
	if not arr or arr.size() < 3:
		push_warning("card: invalid color array, defaulting to white")
		return Color.WHITE
	
	var a: float = 1.0
	if arr.size() > 3:
		a = float(arr[3])
	return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
