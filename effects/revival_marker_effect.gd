extends "res://items/global/effect.gd"


static func get_id() -> String:
	return "romance_revival_coin_marker"


func apply(_player_index: int) -> void:
	pass


func unapply(_player_index: int) -> void:
	pass


# Standard custom-text pattern (same as QMtato): the panel pipeline is
# Effect.get_text -> Text.text(tr(text_key), get_args()). Our text has no
# placeholders, so empty args render it as-is. Never let the base get_args run:
# key is empty, and the base get_args runs tr("") which yields "Null"
func get_args(_player_index: int) -> Array:
	return []
