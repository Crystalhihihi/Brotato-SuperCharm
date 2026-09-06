extends "res://effects/items/charm_effect.gd"


static func get_id() -> String:
	return "rc_charm_coin"


# The base get_args looks up an icon for the scaling stat, and structure_range
# has no stat icon resource — the lookup crashes get_text and the panel shows
# "Null". Our text needs no placeholders, so bypass the whole pipeline
func get_text(_player_index: int, _colored: bool = true) -> String:
	return tr("EFFECT_CHARM_COIN")
