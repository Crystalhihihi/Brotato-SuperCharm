extends Node

# TEMPORARY diagnostic (charmed-boss instant-death hunt, v49): duck-typed
# member of the enemy's effect_behaviors container — unit.gd calls these
# methods on every child without a class check. on_taken_damage fires for
# EVERY take_damage regardless of path (hurtbox hits AND direct calls like
# the riposte dodge reflection), so the log names the exact killer.
# unit.die() queue_frees this node together with the enemy.

var _parent = null


func init(parent):
	_parent = parent
	return self


func on_hurt(hitbox) -> void:
	_log_hit("on_hurt", hitbox, null)


func on_taken_damage(args) -> int:
	_log_hit("on_taken_damage", args.get("hitbox") if args != null else null, args)
	return 0


func _log_hit(tag, hitbox, args) -> void:
	var hb_desc := "no-hitbox"
	if hitbox != null and is_instance_valid(hitbox):
		var from = hitbox.get("from")
		var from_desc := "null"
		if from != null and is_instance_valid(from):
			from_desc = "%s pi=%s" % [from.get_class(), from.get("player_index")]
		hb_desc = "hitbox=%s layer=%s dmg=%s from=%s" % [hitbox.name, hitbox.collision_layer, hitbox.get("damage"), from_desc]
	var fpi = "?"
	if args != null:
		fpi = str(args.get("from_player_index"))
	var hp = -1
	if _parent != null and is_instance_valid(_parent):
		hp = _parent.current_stats.health
	ModLoaderLog.info("BOSS PROBE %s: %s hp_left=%s from_player_index=%s wave=%s" % [tag, hb_desc, hp, fpi, RunData.current_wave], "Crystalhihihi-SuperCharm")


func get_bonus_damage(_hitbox, _from_player_index) -> int:
	return 0


func on_death(_args) -> void:
	pass


func on_burned(_burning_data, _from_player_index) -> void:
	pass


func on_moved(_delta_position) -> void:
	pass


func update_target() -> void:
	pass
