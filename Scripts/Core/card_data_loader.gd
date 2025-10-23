# [card_data_loader.gd]
extends Node

# Constant for the directory path to avoid hardcoding it multiple times
const CARD_DATA_PATH := "res://Scripts/CardData/"

# Private variables to encapsulate the data.
var _card_data_dict: Dictionary = {}
var _deck_composition: Array = []

# --- Initialization ---

func _ready() -> void:
	_load_all_card_data()
	_load_deck_composition()
	print("CardDataLoader: Loaded %d card definitions and %d deck entries." % [_card_data_dict.size(), _deck_composition.size()])

# --- Public Accessors (Encapsulation) ---

## Returns the data dictionary for a specific card name.
func get_card_data(card_name: StringName) -> Dictionary:
	return _card_data_dict.get(card_name, {})

## Returns the list of cards that make up the default deck.
func get_deck_composition() -> Array:
	return _deck_composition.duplicate() # Return a copy to prevent modification

# --- Private Helpers ---

## Helper function to handle file opening, reading, JSON parsing, and closing.
func _load_json_file(file_path: String): # Returns Dictionary or Array
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not is_instance_valid(file):
		push_error("Failed to open JSON file: %s" % file_path)
		return {}

	var json_string: String = file.get_as_text()
	file.close() # Always close the file handle

	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)

	if parse_result != OK:
		push_error("JSON Parse Error in %s: %s" % [file_path, json.get_error_message()])
		return {}

	return json.data

# --- Loading Functions (Updated to use helper) ---

## Loads all individual card JSON files from the data directory.
func _load_all_card_data() -> void:
	var dir: DirAccess = DirAccess.open(CARD_DATA_PATH)
	if not is_instance_valid(dir):
		push_error("Failed to open card data directory: %s" % CARD_DATA_PATH)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# Filter for valid card data files
		if file_name.ends_with(".json") and file_name != "Back.json" and file_name != "deck.json":
			var file_path: String = CARD_DATA_PATH.path_join(file_name)
			var data = _load_json_file(file_path) # Use the helper

			if data is Dictionary and data.has("name"):
				var card_name_str: StringName = data[&"name"]
				_card_data_dict[card_name_str] = data
			elif not data.is_empty():
				push_warning("Skipping file %s: Missing 'name' field or invalid format." % file_name)

		file_name = dir.get_next()
	dir.list_dir_end()


## Loads the deck composition array from deck.json.
func _load_deck_composition() -> void:
	var file_path: String = CARD_DATA_PATH.path_join("deck.json")
	var data = _load_json_file(file_path) # Use the helper

	if data is Array:
		_deck_composition = data
	else:
		push_error("Deck composition file '%s' did not contain a valid JSON Array." % file_path)