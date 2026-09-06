extends Node

const RC_LOG = "LocalMods-RomanceCharm"
const MOD_DIR = "LocalMods-RomanceCharm/"
const COIN_ID = "item_revival_coin"
const BOSS_CHARM_CHANCE := 0.10
const BOSS_REVIVE_HP_RATIO := 0.25
const BOSS_WAVE_HEAL_RATIO := 0.20
const ALLY_GRACE_PERIOD := 1.5
const ALLY_KNOCKBACK_BASE := 8.0
# A strong charm swarm attracts bosses. Pressure scales with swarm dominance:
# chance, concurrent cap and per-wave cap all grow with the power ratio, so a
# full-screen 100%-charm army gets a real boss brawl instead of a free pass
const BOSS_MAGNET_INTERVAL := 4.0
const BOSS_MAGNET_MIN_RATIO := 0.10
const BOSS_MAGNET_RATIO_FACTOR := 0.8
const BOSS_MAGNET_CHANCE_CAP := 0.70
const BOSS_MAGNET_RATIO_CLAMP := 3.0
# alive cap = base + floor(ratio) (max 5); wave cap = base + floor(ratio*1.5) (max 7)
const BOSS_MAGNET_BASE_ALIVE := 2
const BOSS_MAGNET_BASE_PER_WAVE := 3
# absolute gates so tiny armies can't attract bosses no matter the ratio:
# magnet stays off below 3 charmed, and the "full conversion = max pressure"
# rule only kicks in for a real swarm (5+)
const BOSS_MAGNET_MIN_CHARMED := 3
const BOSS_MAGNET_FULL_SWARM_MIN := 5
const CHARM_BEHAVIOR_SCENE := "res://dlcs/dlc_1/effect_behaviors/enemy/charm_enemy_effect_behavior.tscn"

var _last_main = null
var _spawned_for_main = null
var _last_wave := -1
var _was_in_progress := false
var _scan_accum := 0.0
var _regen_accum := 0.0
var _boss_magnet_accum := 0.0
# alive magnet-spawned boss instance ids (pruned in _scan)
var _magnet_bosses := {}
var _magnet_spawned_this_wave := 0

# boss instance_id -> {scene_path, health, damage, hp_ratio}
var _boss_records := {}
# alive coin-ally instance ids (cleaned up at wave begin / on death)
var _coin_allies := {}
# coin item_instance_id -> {"slots": [{"scene_path": String}]}
var _coin_bindings := {}
# species scene_path -> count of currently alive charmed instances (combat only)
var _charmed_alive_species := {}


func _init() -> void:
	# Warm the script cache so mod content compiles against cached vanilla classes
	load("res://items/global/effect.gd")
	load("res://items/global/item_data.gd")
	ModLoaderLog.info("romance charm init", RC_LOG)


func _ready() -> void:
	var _e = RunData.connect("enemy_charmed", self, "_on_enemy_charmed")
	_add_translations()
	# ContentLoader registers content at ItemService._ready, which happens after
	# all mod _ready calls, so registering here is on time.
	# The icon must be built at runtime: exported Godot can't load a raw png as a
	# Texture ext_resource without .import/.stex metadata (that was the v1.0.4
	# crash), so we load the tres without an icon and assign an ImageTexture
	var cl = get_node_or_null("/root/ModLoader/Darkly77-ContentLoader/ContentLoader")
	if cl != null and cl.has_method("load_data_by_dictionary"):
		var item = load("res://mods-unpacked/" + MOD_DIR + "content/items/revival_coin/revival_coin_data.tres")
		if item != null:
			item.icon = _load_texture_from_disk(ModLoaderMod.get_unpacked_dir() + MOD_DIR + "content/items/revival_coin/revival_coin_icon.png")
			cl.load_data_by_dictionary({"items": [item]}, "LocalMods-RomanceCharm")
			# ContentLoader's unlock pass pushes the string my_id, but the shop
			# pool checks my_id_hash (int) — custom items would never roll.
			# Unlock it properly ourselves; this runs before _install_data builds
			# the tier pools, so the coin lands in the shop pool on time
			var coin_hash = Keys.generate_hash(COIN_ID)
			if not ProgressData.items_unlocked.has(coin_hash):
				ProgressData.items_unlocked.push_back(coin_hash)
			ModLoaderLog.info("revival coin registered", RC_LOG)
		else:
			ModLoaderLog.error("revival coin tres failed to load", RC_LOG)
	else:
		ModLoaderLog.error("ContentLoader node not found, revival coin unavailable", RC_LOG)
	set_process(true)


func _load_texture_from_disk(abs_path: String):
	var img = Image.new()
	if img.load(abs_path) != OK:
		ModLoaderLog.error("failed to load image: %s" % abs_path, RC_LOG)
		return null
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex


func _add_translations() -> void:
	for locale in ["zh_Hans_CN", "zh_CN", "zh"]:
		var zh = Translation.new()
		zh.locale = locale
		zh.add_message("ITEM_REVIVAL_COIN", "复活币")
		zh.add_message("EFFECT_REVIVAL_COIN", "每波结束时，从场上仍存活的被魅惑小怪中随机绑定一只；之后每波开始时它以魅惑状态满血参战（数值随波次增长），战死后下一波重新归来。被诅咒时绑定两只")
		TranslationServer.add_translation(zh)
	var en = Translation.new()
	en.locale = "en"
	en.add_message("ITEM_REVIVAL_COIN", "Revival Coin")
	en.add_message("EFFECT_REVIVAL_COIN", "At the end of each wave, binds a random charmed enemy still alive on the field. It joins every following wave charmed at full HP (stats scale with waves); if it dies, it returns next wave. Binds two when cursed")
	TranslationServer.add_translation(en)


# ---------------- perma charm + ally targeting ----------------

func _on_enemy_charmed(enemy) -> void:
	if not is_instance_valid(enemy):
		return
	call_deferred("_setup_charmed_ally", enemy)


# Deferred so it runs after charm() finishes (charm() disables the hurtbox
# and starts the 8s timer; we undo both)
func _setup_charmed_ally(enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var cb = _get_charm_behavior(enemy)
	if cb == null or not cb.charmed:
		return
	var timer = cb.get_node_or_null("CharmTimer")
	if timer != null:
		timer.stop()
	# Charm triggers below 25% HP; refill normal enemies to full so the ally
	# isn't one hit from death. Bosses are excluded: revive-charm sets their HP
	# ratio deliberately (25% + 20%/wave)
	if enemy.get("is_elite") == null and enemy.current_stats.health < enemy.max_stats.health:
		enemy.current_stats.health = enemy.max_stats.health
		enemy.emit_signal("health_updated", enemy, enemy.current_stats.health, enemy.max_stats.health)
	# Vanilla bug: the hit that triggers charm applies burning AFTER charm()
	# already cleared it (on_hurt runs before apply_burning in
	# hurt_area_entered_deferred), and burn ticks are timer-based so they keep
	# hurting the ally. Clear it again here (deferred = after the hit resolved)
	if enemy.has_method("stop_burning"):
		enemy.stop_burning()
	# Hittable by enemy contact/projectiles only, never by the player's weapons.
	# The hurtbox stays disabled for a grace period: charm triggers below 25% HP,
	# usually inside a crowd, and enabling it right away gets the ally bursted
	# down by every enemy hitbox already overlapping it (charm's +100 speed
	# bonus lets it walk out during the grace window)
	var hurtbox = enemy.get("_hurtbox")
	if hurtbox != null:
		# remember the original collision setup so _on_charmed_ally_died can
		# restore it — the entity spawner pools and respawns dead enemy nodes,
		# and a recycled node with our mask would be untargetable by the player
		if not enemy.has_meta("rc_hb_layer"):
			enemy.set_meta("rc_hb_layer", hurtbox.collision_layer)
			enemy.set_meta("rc_hb_mask", hurtbox.collision_mask)
		hurtbox.collision_layer = Utils.PETS_BIT
		hurtbox.collision_mask = Utils.ENEMIES_BIT | Utils.ENEMY_PROJECTILES_BIT
	# enemies target charmed allies the same way they target players/pets
	var main = Utils.get_scene_node()
	if main == null or not ("_entity_spawner" in main):
		return
	var spawner = main.get("_entity_spawner")
	if spawner == null:
		return
	if not spawner.targetable_pets.has(enemy):
		spawner.targetable_pets.push_back(enemy)
	# absolute guarantee: the ally's contact hitbox can never hurt the player,
	# even if some layer edge case lets them overlap (hitbox.ignored_objects is
	# checked by the victim's hurtbox before any damage). Original list is
	# stored and restored on death for the spawner pool
	var hitbox = enemy.get("_hitbox")
	if hitbox != null:
		if not enemy.has_meta("rc_ignored"):
			enemy.set_meta("rc_ignored", hitbox.ignored_objects.duplicate())
		var players = main.get("_players")
		if players is Array and not players.empty() and is_instance_valid(players[0]):
			hitbox.ignored_objects = enemy.get_meta("rc_ignored").duplicate()
			hitbox.ignored_objects.push_back(players[0])
	if not enemy.is_connected("died", self, "_on_charmed_ally_died"):
		var _e = enemy.connect("died", self, "_on_charmed_ally_died")
	if hurtbox != null:
		var _t = get_tree().create_timer(ALLY_GRACE_PERIOD).connect("timeout", self, "_enable_ally_hurtbox", [enemy])


# Contact damage only triggers when a hitbox ENTERS a hurtbox, so an ally and
# an enemy that end up overlapping would never damage each other again (the
# "quantum entanglement" wiggle). Giving the ally knockback breaks the
# deadlock: hit -> enemy pushed away -> charges back in -> hit again.
# Amount = small base + the player's knockback stat. Never negative: the
# negative-knockback path in take_damage indexes players_ref[123] for
# enemy-sourced hits and would crash
func _apply_ally_knockback(enemy) -> void:
	var hb = enemy.get("_hitbox")
	if hb == null:
		return
	if not enemy.has_meta("rc_kb"):
		enemy.set_meta("rc_kb", [hb.knockback_amount, hb.knockback_piercing])
	hb.knockback_amount = max(0.0, ALLY_KNOCKBACK_BASE + RunData.get_player_effect(Keys.knockback_hash, 0))
	if is_instance_valid(enemy.current_target):
		hb.knockback_direction = enemy.global_position.direction_to(enemy.current_target.global_position)


func _enable_ally_hurtbox(enemy) -> void:
	if not is_instance_valid(enemy) or enemy.dead:
		return
	var cb = _get_charm_behavior(enemy)
	if cb == null or not cb.charmed:
		return
	var hurtbox = enemy.get("_hurtbox")
	if hurtbox != null:
		hurtbox.enable()


func _on_charmed_ally_died(entity, _args) -> void:
	# restore the hurtbox collision setup so a pooled respawn of this node
	# comes back as a normal, player-hittable enemy
	if entity.has_meta("rc_hb_layer"):
		var hb = entity.get("_hurtbox")
		if hb != null:
			hb.collision_layer = entity.get_meta("rc_hb_layer")
			hb.collision_mask = entity.get_meta("rc_hb_mask")
		entity.remove_meta("rc_hb_layer")
		entity.remove_meta("rc_hb_mask")
	if entity.has_meta("rc_kb"):
		var kb = entity.get("_hitbox")
		if kb != null:
			kb.knockback_amount = entity.get_meta("rc_kb")[0]
			kb.knockback_piercing = entity.get_meta("rc_kb")[1]
		entity.remove_meta("rc_kb")
	if entity.has_meta("rc_ignored"):
		var hb2 = entity.get("_hitbox")
		if hb2 != null:
			hb2.ignored_objects = entity.get_meta("rc_ignored")
		entity.remove_meta("rc_ignored")
	var main = Utils.get_scene_node()
	if main == null or not ("_entity_spawner" in main):
		return
	var spawner = main.get("_entity_spawner")
	if spawner != null:
		spawner.targetable_pets.erase(entity)


# ---------------- main loop ----------------

func _process(delta: float) -> void:
	_scan_accum += delta
	_regen_accum += delta

	# wave end: bind coins to random still-living charmed species
	if _was_in_progress and not RunData.wave_in_progress:
		_on_wave_end()
	_was_in_progress = RunData.wave_in_progress

	var main = Utils.get_scene_node()
	if main == null or not ("_entity_spawner" in main):
		return
	var spawner = main.get("_entity_spawner")
	if spawner == null or not spawner.has_method("get_all_enemies"):
		return

	if main != _last_main:
		if RunData.current_wave < _last_wave:
			_reset_run_state()
		_last_wave = RunData.current_wave
		_last_main = main

	if main != _spawned_for_main and RunData.wave_in_progress \
	and spawner.get("_current_wave_data") != null:
		_spawned_for_main = main
		_on_wave_begin(spawner, main)

	if _scan_accum >= 0.5:
		_scan_accum = 0.0
		if RunData.wave_in_progress:
			_scan(spawner, main)

	if _regen_accum >= 1.0:
		_regen_accum = 0.0
		if RunData.wave_in_progress:
			_regen_charmed(spawner)

	_boss_magnet_accum += delta
	if _boss_magnet_accum >= BOSS_MAGNET_INTERVAL:
		_boss_magnet_accum = 0.0
		if RunData.wave_in_progress:
			_boss_magnet_roll(spawner, main)


# A strong charm swarm attracts an extra boss. Strength is measured by combat
# power (max HP x max damage) of NORMAL enemies only (bosses excluded from
# both sides, see below), charmed share vs hostile share. One boss per roll,
# capped alive and per wave
func _boss_magnet_roll(spawner, main) -> void:
	if spawner.get("_cleaning_up"):
		return
	var charmed_power := 0
	var hostile_power := 0
	var charmed_count := 0
	for enemy in spawner.get_all_enemies(true):
		if enemy == null or not is_instance_valid(enemy) or enemy.dead:
			continue
		var power = enemy.max_stats.health * max(1, enemy.max_stats.damage)
		var cb = _get_charm_behavior(enemy)
		# elites/bosses are excluded from BOTH sides: on the charmed side they
		# would snowball the ratio forever; on the hostile side one spawned
		# boss's huge stats would dilute the ratio below threshold and stall
		# all further spawns (v12 was too conservative because of this)
		if enemy.get("is_elite") != null:
			continue
		if cb != null and cb.charmed:
			charmed_power += power
			charmed_count += 1
		else:
			hostile_power += power
	# absolute gate: a handful of charmed enemies never attracts bosses, no
	# matter how dominant the ratio is (v19 bug: 1 coin ally + empty field =
	# clamped ratio = boss rain at wave 4)
	if charmed_count < BOSS_MAGNET_MIN_CHARMED:
		return
	# full conversion (nothing hostile left) = maximum pressure, but only for
	# a real swarm
	var ratio = 0.0
	if hostile_power <= 0:
		if charmed_count < BOSS_MAGNET_FULL_SWARM_MIN:
			return
		ratio = BOSS_MAGNET_RATIO_CLAMP
	else:
		ratio = float(charmed_power) / float(hostile_power)
	if ratio < BOSS_MAGNET_MIN_RATIO:
		return
	# the stronger the swarm, the more bosses it has to earn; in endless the
	# vanilla waves spawn dozens of bosses on their own, so the caps keep
	# growing with the wave number to stay relevant
	var endless_bonus = max(0, (RunData.current_wave - 20) / 4)
	var alive_cap = BOSS_MAGNET_BASE_ALIVE + int(min(ratio, BOSS_MAGNET_RATIO_CLAMP)) + endless_bonus
	var wave_cap = BOSS_MAGNET_BASE_PER_WAVE + int(min(ratio, BOSS_MAGNET_RATIO_CLAMP) * 1.5) + endless_bonus * 2
	if _magnet_spawned_this_wave >= wave_cap:
		return
	if _magnet_bosses.size() >= alive_cap:
		return
	var chance = min(BOSS_MAGNET_CHANCE_CAP, ratio * BOSS_MAGNET_RATIO_FACTOR)
	if not Utils.get_chance_success(chance):
		return
	var pool = ItemService.get_elites_from_zone(RunData.current_zone) + ItemService.get_bosses_from_zone(RunData.current_zone)
	if pool.empty():
		return
	var count = 2 if ratio >= 1.5 else 1
	var spawned := 0
	for i in count:
		var data = Utils.get_rand_element(pool)
		if data == null or data.scene == null:
			continue
		var pos = spawner.get_spawn_pos_in_area(_get_player_pos(main), -1, 100)
		var args = EntitySpawner.SpawnEntityArgs.new(pos, EntityType.BOSS)
		var boss = spawner.spawn_entity(data.scene, args, null, null, -1)
		if boss == null:
			continue
		# runtime-instanced bosses have no filename; remember the scene path so
		# the revive-charm and wave carry-over can rebuild them
		boss.set_meta("rc_scene_path", data.scene.resource_path)
		_magnet_bosses[boss.get_instance_id()] = true
		spawned += 1
	_magnet_spawned_this_wave += spawned
	if spawned > 0:
		ModLoaderLog.info("charm swarm attracted %s boss(es) (power ratio %.2f, wave spawns %s/%s)" % [spawned, ratio, _magnet_spawned_this_wave, wave_cap], RC_LOG)


func _reset_run_state() -> void:
	_boss_records.clear()
	_coin_allies.clear()
	_coin_bindings.clear()
	_charmed_alive_species.clear()


func _on_wave_begin(spawner, main) -> void:
	_magnet_spawned_this_wave = 0
	# carry over bosses that were alive at the end of last wave
	var carried = []
	for id in _boss_records:
		carried.append(_boss_records[id])
	_boss_records.clear()
	for record in carried:
		record.hp_ratio = min(1.0, record.hp_ratio + BOSS_WAVE_HEAL_RATIO)
		_revive_boss(record, main)

	# respawn bound coin allies, fresh and wave-scaled
	_coin_allies.clear()
	_reconcile_coins()
	var filled := 0
	var total := 0
	for item_id in _coin_bindings:
		for slot in _coin_bindings[item_id].slots:
			total += 1
			if not slot.scene_path.empty():
				filled += 1
	if total > 0:
		ModLoaderLog.info("coin respawn check: %s/%s slots filled" % [filled, total], RC_LOG)
	for item_id in _coin_bindings:
		for slot in _coin_bindings[item_id].slots:
			if slot.scene_path.empty():
				continue
			var ally = _spawn_charmed_enemy(slot.scene_path, main, 0)
			if ally != null:
				_coin_allies[ally.get_instance_id()] = true


func _on_wave_end() -> void:
	# forensic log for the wave-end-with-charmed-boss crash hunt
	if not _boss_records.empty():
		ModLoaderLog.info("wave end: carrying %s charmed boss(es)" % _boss_records.size(), RC_LOG)
	# bind unbound coin slots to a random charmed species still alive
	if _charmed_alive_species.empty():
		return
	var candidates = _charmed_alive_species.keys()
	for item_id in _coin_bindings:
		for slot in _coin_bindings[item_id].slots:
			if not slot.scene_path.empty():
				continue
			slot.scene_path = candidates[randi() % candidates.size()]
			ModLoaderLog.info("revival coin bound to %s" % slot.scene_path, RC_LOG)


# ---------------- scan ----------------

func _scan(spawner, main) -> void:
	var enemies = spawner.get_all_enemies(true)

	# hook boss deaths + snapshot charmed enemies
	_charmed_alive_species.clear()
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.dead:
			continue
		if enemy.get("is_elite") != null and not enemy.has_meta("rc_hooked"):
			enemy.set_meta("rc_hooked", true)
			enemy.connect("died", self, "_on_boss_died")
		var cb = _get_charm_behavior(enemy)
		if cb == null or not cb.charmed:
			continue
		_apply_ally_knockback(enemy)
		if enemy.get("is_elite") == null:
			# only normal enemies are coin-bindable species
			if not enemy.filename.empty():
				_charmed_alive_species[enemy.filename] = int(_charmed_alive_species.get(enemy.filename, 0)) + 1
			continue
		var id = enemy.get_instance_id()
		var scene_path = enemy.filename
		if scene_path.empty() and enemy.has_meta("rc_scene_path"):
			scene_path = enemy.get_meta("rc_scene_path")
		if not _boss_records.has(id):
			_boss_records[id] = {
				"scene_path": scene_path,
				"health": enemy.max_stats.health,
				"damage": enemy.max_stats.damage,
				"hp_ratio": 1.0,
			}
		var record = _boss_records[id]
		record.hp_ratio = float(enemy.current_stats.health) / float(max(1, enemy.max_stats.health))
		if not scene_path.empty():
			record.scene_path = scene_path

	# NOTE: no culling of _boss_records here — a charmed boss killed by the
	# wave-end cleanup is dead but must keep its record for the carry-over.
	# Real deaths erase their record in _on_boss_died; run resets clear the rest.
	_reconcile_coins()

	# bind empty coin slots as soon as a charmed ally exists, and spawn the
	# new ally immediately — wave-end binding stays as a fallback, but a coin
	# bought in the shop should not take two full waves to do anything
	if not _charmed_alive_species.empty():
		var candidates = _charmed_alive_species.keys()
		for item_id in _coin_bindings:
			for slot in _coin_bindings[item_id].slots:
				if not slot.scene_path.empty():
					continue
				slot.scene_path = candidates[randi() % candidates.size()]
				ModLoaderLog.info("revival coin bound to %s" % slot.scene_path, RC_LOG)
				var ally = _spawn_charmed_enemy(slot.scene_path, main, 0)
				if ally != null:
					_coin_allies[ally.get_instance_id()] = true

	# prune dead coin ally ids; the binding itself persists and respawns next wave
	for ally_id in _coin_allies.keys():
		var e = instance_from_id(ally_id)
		if e == null or not is_instance_valid(e) or e.dead:
			_coin_allies.erase(ally_id)

	# prune dead magnet bosses
	for id in _magnet_bosses.keys():
		var e2 = instance_from_id(id)
		if e2 == null or not is_instance_valid(e2) or e2.dead:
			_magnet_bosses.erase(id)


func _reconcile_coins() -> void:
	var coins = []
	for item in RunData.get_player_items_ref(0):
		if item != null and item.my_id == COIN_ID:
			coins.append(item)
	for key in _coin_bindings.keys():
		var found = false
		for item in coins:
			if item.get_instance_id() == key:
				found = true
		if not found:
			ModLoaderLog.info("coin binding erased (coin gone)", RC_LOG)
			_coin_bindings.erase(key)
	for item in coins:
		var id = item.get_instance_id()
		if not _coin_bindings.has(id):
			ModLoaderLog.info("coin binding created", RC_LOG)
			var n = 2 if item.is_cursed else 1
			var slots = []
			for i in n:
				slots.append({"scene_path": ""})
			_coin_bindings[id] = {"slots": slots}


# ---------------- boss revive ----------------

func _on_boss_died(enemy, _args) -> void:
	if not is_instance_valid(enemy):
		return
	var id = enemy.get_instance_id()
	if _boss_records.has(id):
		# wave-end cleanup also calls die() on bosses; that is not a real death,
		# keep the record so the carry-over rebuilds it next wave
		if _args != null and _args.cleaning_up:
			return
		# our own charmed boss died for good
		_boss_records.erase(id)
		return
	# cleanup deaths never roll revive-charm: the 0.6s revive timer would fire
	# after the wave already ended and spawn a boss into a scene that is being
	# torn down (hard engine crash, no script error in the log)
	if _args != null and _args.cleaning_up:
		return
	var cb = _get_charm_behavior(enemy)
	if cb != null and cb.charmed:
		return
	if not _player_has_charm_source():
		return
	if not Utils.get_chance_success(BOSS_CHARM_CHANCE):
		return
	var scene_path = enemy.filename
	if scene_path.empty() and enemy.has_meta("rc_scene_path"):
		scene_path = enemy.get_meta("rc_scene_path")
	var record = {
		"scene_path": scene_path,
		"health": enemy.max_stats.health,
		"damage": enemy.max_stats.damage,
		"hp_ratio": BOSS_REVIVE_HP_RATIO,
		"pos": enemy.global_position,
	}
	if record.scene_path.empty():
		return
	ModLoaderLog.info("boss revive-charm rolled: %s" % record.scene_path, RC_LOG)
	var _t = get_tree().create_timer(0.6).connect("timeout", self, "_revive_boss", [record, null])


func _revive_boss(record, main) -> void:
	ModLoaderLog.info("revive-boss begin: %s" % record.get("scene_path", "?"), RC_LOG)
	if main == null:
		main = Utils.get_scene_node()
	if main == null or not ("_entity_spawner" in main):
		return
	var spawner = main.get("_entity_spawner")
	if spawner == null or not RunData.wave_in_progress:
		return
	if spawner.get("_cleaning_up"):
		return
	var scene = load(record.scene_path)
	if scene == null:
		return
	var pos = record.get("pos")
	if pos == null:
		# carried bosses have no death position; spawn at a random spot in the
		# zone instead of right on the player's face (a boss materializing on
		# top of you and instantly charging looks and feels like an attack)
		pos = spawner.get_spawn_pos_in_area(_get_player_pos(main), -1, 100)
	var args = EntitySpawner.SpawnEntityArgs.new(pos, EntityType.BOSS)
	var boss = spawner.spawn_entity(scene, args, null, null, -1)
	if boss == null:
		return
	# freeze stats at the values from the wave it was charmed
	boss.max_stats.health = record.health
	boss.max_stats.damage = record.damage
	boss.current_stats.health = int(record.health * record.hp_ratio)
	boss.current_stats.damage = record.damage
	var hb = boss.get("_hitbox")
	if hb != null:
		hb.damage = record.damage
	_charm_enemy(boss, 0)
	# verify the charm actually took — a revived boss that stays hostile keeps
	# its frozen stats and WILL kill the player at wave start
	var cb = _get_charm_behavior(boss)
	var is_charmed = cb != null and cb.charmed
	if not is_charmed:
		ModLoaderLog.error("boss revive charm FAILED, despawning to be safe: %s" % record.scene_path, RC_LOG)
		boss.die(Utils.default_die_args)
		return
	ModLoaderLog.info("boss revived charmed: %s hp=%s/%s" % [boss.name, boss.current_stats.health, boss.max_stats.health], RC_LOG)


# ---------------- spawning helpers ----------------

func _spawn_charmed_enemy(scene_path: String, main, player_index: int):
	var spawner = main.get("_entity_spawner")
	if spawner == null:
		return null
	var scene = load(scene_path)
	if scene == null:
		ModLoaderLog.error("coin ally scene failed to load: %s" % scene_path, RC_LOG)
		return null
	var pos = _get_player_pos(main) + Vector2(rand_range(-90, 90), rand_range(-90, 90))
	var args = EntitySpawner.SpawnEntityArgs.new(pos, EntityType.ENEMY)
	var enemy = spawner.spawn_entity(scene, args, null, null, player_index)
	if enemy == null:
		ModLoaderLog.error("coin ally spawn_entity failed: %s" % scene_path, RC_LOG)
		return null
	ModLoaderLog.info("coin ally spawned: %s" % scene_path, RC_LOG)
	# spawn_entity only applies charmed_by when the charm behavior exists
	_charm_enemy(enemy, player_index)
	return enemy


func _charm_enemy(enemy, player_index: int) -> void:
	var cb = _get_charm_behavior(enemy)
	if cb == null:
		cb = _attach_charm_behavior(enemy)
	if cb == null:
		return
	if not cb.charmed:
		enemy.set_charmed(player_index)
	# charm() starts the 8s timer; the enemy_charmed signal handler stops it


func _get_charm_behavior(enemy):
	var eb = enemy.get("effect_behaviors")
	if eb == null:
		return null
	for child in eb.get_children():
		if "charmed" in child:
			return child
	return null


func _attach_charm_behavior(enemy):
	var scene = load(CHARM_BEHAVIOR_SCENE)
	if scene == null:
		return null
	var eb = enemy.get("effect_behaviors")
	if eb == null:
		return null
	var b = scene.instance()
	eb.add_child(b)
	if b.has_method("init"):
		b.init(enemy)
	return b


func _get_player_pos(main) -> Vector2:
	var players = main.get("_players")
	if players is Array and not players.empty() and is_instance_valid(players[0]):
		return players[0].global_position
	return Vector2.ZERO


func _player_has_charm_source() -> bool:
	if RunData.get_player_effect(Keys.charm_on_hit_hash, 0).size() > 0:
		return true
	return RunData.existing_weapon_has_effect(Keys.charm_on_hit_hash)


# ---------------- regen link ----------------

func _regen_charmed(spawner) -> void:
	var regen = Utils.get_stat(Keys.stat_hp_regeneration_hash, 0)
	if regen <= 0:
		return
	for enemy in spawner.get_all_enemies(true):
		if enemy == null or not is_instance_valid(enemy) or enemy.dead:
			continue
		var cb = _get_charm_behavior(enemy)
		if cb == null or not cb.charmed:
			continue
		if enemy.current_stats.health < enemy.max_stats.health:
			enemy.current_stats.health = min(enemy.max_stats.health, enemy.current_stats.health + regen)
