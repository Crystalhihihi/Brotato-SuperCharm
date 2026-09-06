extends "res://items/global/effect.gd"


static func get_id() -> String:
	return "romance_revival_coin_marker"


func apply(_player_index: int) -> void:
	pass


func unapply(_player_index: int) -> void:
	pass


# key is empty, and the base get_args runs tr("") which yields "Null" on the
# item panel — bypass the pipeline, our text needs no placeholders
func get_text(_player_index: int, _colored: bool = true) -> String:
	return tr("EFFECT_REVIVAL_COIN")
