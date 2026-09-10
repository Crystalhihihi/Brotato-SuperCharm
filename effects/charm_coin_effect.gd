extends "res://effects/items/charm_effect.gd"


static func get_id() -> String:
	return "rc_charm_coin"


# Standard custom-text pattern (same as QMtato): the panel pipeline is
# Effect.get_text -> Text.text(tr(text_key), get_args()). Our text has no
# placeholders, so empty args render it as-is. Never let the base get_args run:
# CharmEffect.get_args looks up a small icon for the scaling stat, and
# structure_range has no icon resource — null.small_icon kills get_text
func get_args(_player_index: int) -> Array:
	return []
