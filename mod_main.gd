extends Node

const RC_LOG = "Crystalhihihi-SuperCharm"
const MOD_DIR = "Crystalhihihi-SuperCharm/"
const COIN_ID = "item_revival_coin"
const CHARM_COIN_ID = "item_charm_coin"
const BOSS_CHARM_CHANCE := 0.10
# romantic players already hit 100% charm late game, so their charm coin bonus
# is a better boss-taming rate instead of more small-fry charm
const BOSS_CHARM_ROMANTIC_BONUS := 0.05
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
# alive cap by wave: 10->1, 15->2, 20->3 (+endless bonus); counts hostile
# bosses/elites (vanilla wave spawns included), charmed allies excluded
const BOSS_MAGNET_BASE_PER_WAVE := 3
# absolute gates so tiny armies can't attract bosses no matter the ratio:
# magnet stays off below 3 charmed, and the "full conversion = max pressure"
# rule only kicks in for a real swarm (5+)
const BOSS_MAGNET_MIN_CHARMED := 3
const BOSS_MAGNET_FULL_SWARM_MIN := 5
# gate matches the cap table now (both start at wave 10); vanilla elites start
# appearing around wave 10 anyway, earlier bosses punish an early charm army
# that can barely form (wave-4 boss rain incident)
const BOSS_MAGNET_MIN_WAVE := 10
const CHARM_BEHAVIOR_SCENE := "res://dlcs/dlc_1/effect_behaviors/enemy/charm_enemy_effect_behavior.tscn"

var _last_main = null
var _spawned_for_main = null
var _last_wave := -1
var _was_in_progress := false
var _scan_accum := 0.0
var _regen_accum := 0.0
var _police_accum := 0.0
var _boss_magnet_accum := 0.0
var _magnet_spawned_this_wave := 0

# boss instance_id -> {scene_path, health, damage, hp_ratio}
var _boss_records := {}
# alive coin-ally instance ids (cleaned up at wave begin / on death)
var _coin_allies := {}
# one slot per coin (two per cursed coin). NOT keyed by item instance id:
# vanilla pushes the shared ItemService pool instance for non-cursed shop buys
# (only cursing duplicates), so two coins share one instance id and id-keying
# collapses them into one binding (v32 bug: 2 coins owned, 1 ally spawned)
var _coin_slots := []
# species scene_path -> count of currently alive charmed instances (combat only)
var _charmed_alive_species := {}
# species a new coin slot may bind to: same set MINUS coin allies, so a fresh
# coin can't clone an existing ally at wave start — it binds to a "real" charm.
# value = best max HP seen for that species (weighted binding prefers tanks)
var _bindable_species := {}
# base max_enemies of the wave before we refund the swarm's share
var _max_enemies_base := -1
var _max_enemies_base_for := 0
# reference point for the farthest-first swarm cull sort
var _cull_player_pos := Vector2.ZERO
# The swarm cap doubles as the max_enemies refund cap: without it an endless
# charm swarm pushes the alive cap without bound, the physics server drowns in
# "flushing queries" errors and the engine eventually hard-crashes mid-wave
# (v33 endless crash). Above the cap, vanilla would randomly execute the
# overflow at every spawn timing (entity_spawner.on_group_spawn_timing_reached
# kills enemies.size() - max_enemies picked at random from the whole enemies
# list, allies included, no loot — the "charmed units silently vanished"
# report), so we cull deterministically instead: weakest max-HP first, ties
# broken by farthest from the player, coin allies exempt. Both knobs are
# player-configurable (ModOptions / config file, default 100, unlimited opt-in)
# v42 config store = a NAMED config ("config_created_by_mod_options", QMtato
# pattern). The auto-created "default" config is schema-owned: the game
# REGENERATES it from manifest defaults at every launch (verified: hand-edited
# default.json reverts to schema on next start) and update_config refuses to
# save it. ModOptions' display cache is refreshed directly in _init_config.
const CONFIG_NAME := "config_created_by_mod_options"
# the config keys double as the UI labels: dami-ModOptions renders the raw key
# (to_upper) as the slider/checkbox text, so the keys ARE the Chinese names.
# v36/37 used RC_SWARM_CAP / RC_SWARM_UNLIMITED — _apply_config_data migrates
const CONF_CAP := "魅惑大军上限"
const CONF_UNLIMITED := "无上限模式"
var _swarm_cap := 100
var _swarm_unlimited := false
var _config = null


func _init() -> void:
	# Warm the script cache so mod content compiles against cached vanilla classes
	load("res://items/global/effect.gd")
	load("res://items/global/item_data.gd")
	load("res://effects/items/double_value_effect.gd")
	load("res://effects/items/charm_effect.gd")
	ModLoaderLog.info("romance charm init", RC_LOG)


func _ready() -> void:
	var _e = RunData.connect("enemy_charmed", self, "_on_enemy_charmed")
	# v31: registering translations during the ModLoader init frame CORRUPTS the
	# stored messages (long BBCode ones come back as garbage like "2"/"Null" from
	# TranslationServer — reproduced with -s probes; registering the exact same
	# strings 0.5s later is clean). Defer past the whole init phase.
	var _tt = get_tree().create_timer(0.5).connect("timeout", self, "_add_translations")
	# Register custom effect classes into ItemService.effects (same thing QMtato
	# does in its _ready). ItemParentData.deserialize_and_merge rebuilds saved
	# effects by looking up get_id() in that array — unregistered custom effects
	# are silently DROPPED on run resume. Since v30 the item tres files use
	# vanilla effect classes; these two remain registered ONLY so saves written
	# by v25~v29 (custom effect ids in the save) still restore their effects.
	# This must happen before the save-file load, which runs after all mod
	# _ready calls, so here is on time.
	var registered_effect_ids = []
	for eff in ItemService.effects:
		registered_effect_ids.push_back(eff.get_id())
	for eff_path in ["effects/charm_coin_effect.gd", "effects/revival_marker_effect.gd"]:
		var eff_script = load("res://mods-unpacked/" + MOD_DIR + eff_path)
		if eff_script != null and not eff_script.get_id() in registered_effect_ids:
			ItemService.effects.push_back(eff_script)
			registered_effect_ids.push_back(eff_script.get_id())
	# ContentLoader registers content at ItemService._ready, which happens after
	# all mod _ready calls, so registering here is on time.
	# The icon must be built at runtime: exported Godot can't load a raw png as a
	# Texture ext_resource without .import/.stex metadata (that was the v1.0.4
	# crash), so we load the tres without an icon and assign an ImageTexture
	var cl = get_node_or_null("/root/ModLoader/Darkly77-ContentLoader/ContentLoader")
	if cl != null and cl.has_method("load_data_by_dictionary"):
		var coin = load("res://mods-unpacked/" + MOD_DIR + "content/items/revival_coin/revival_coin_data.tres")
		var charm_coin = load("res://mods-unpacked/" + MOD_DIR + "content/items/charm_coin/charm_coin_data.tres")
		if coin != null and charm_coin != null:
			var unpacked = ModLoaderMod.get_unpacked_dir() + MOD_DIR
			coin.icon = _load_texture_from_disk(unpacked + "content/items/revival_coin/revival_coin_icon.png")
			charm_coin.icon = _load_texture_from_disk(unpacked + "content/items/charm_coin/charm_coin_icon.png")
			cl.load_data_by_dictionary({"items": [coin, charm_coin]}, "Crystalhihihi-SuperCharm")
			# ContentLoader's unlock pass pushes the string my_id, but the shop
			# pool checks my_id_hash (int) — custom items would never roll.
			# Unlock them properly ourselves; this runs before _install_data
			# builds the tier pools, so both coins land in the shop pool on time
			for id in [COIN_ID, CHARM_COIN_ID]:
				var h = Keys.generate_hash(id)
				if not ProgressData.items_unlocked.has(h):
					ProgressData.items_unlocked.push_back(h)
			ModLoaderLog.info("revival coin + charm coin registered", RC_LOG)
		else:
			ModLoaderLog.error("coin tres failed to load (revival=%s, charm=%s)" % [coin != null, charm_coin != null], RC_LOG)
	else:
		ModLoaderLog.error("ContentLoader node not found, coins unavailable", RC_LOG)
	_init_config()
	set_process(true)


# Loads the swarm config from the named config (file:
# user://configs/Crystalhihihi-SuperCharm/config_created_by_mod_options.json).
# Works without dami-ModOptions (file is created here and stays hand-editable);
# with ModOptions installed the setting_changed signal applies live, mid-run
# included, and the display cache refresh below keeps the menu honest.
func _init_config() -> void:
	var configs = ModLoaderConfig.get_configs(RC_LOG)
	if configs.has(CONFIG_NAME):
		_config = ModLoaderConfig.get_config(RC_LOG, CONFIG_NAME)
	else:
		_config = ModLoaderConfig.create_config(RC_LOG, CONFIG_NAME, {
			CONF_CAP: float(_swarm_cap), CONF_UNLIMITED: _swarm_unlimited})
	if _config != null:
		_apply_config_data(_config.data)
		# values MUST be floats: ModOptions renders a slider only when the
		# flattened value `is float` (mod_options_tab.gd:61) — an int silently
		# drops the whole row. JSON round-trips as float, but a GDScript int
		# written here poisons the in-memory cache for this session
		_config.data[CONF_CAP] = float(_swarm_cap)
		_config.data[CONF_UNLIMITED] = _swarm_unlimited
		var _e = ModLoaderConfig.update_config(_config)
		# ModOptions loads before us (optional dependency) and built its display
		# cache in its own _ready from the schema-owned default config — refresh
		# the cache so the real values show in the menu on this same launch
		var mci = get_node_or_null("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
		if mci != null:
			if mci.mod_configs.has(RC_LOG):
				mci.mod_configs[RC_LOG][CONF_CAP] = float(_swarm_cap)
				mci.mod_configs[RC_LOG][CONF_UNLIMITED] = _swarm_unlimited
			var _c = mci.connect("setting_changed", self, "_on_mod_setting_changed")
	ModLoaderLog.info("swarm config: cap=%s unlimited=%s" % [_swarm_cap, _swarm_unlimited], RC_LOG)


func _apply_config_data(data) -> void:
	if data == null:
		return
	# v36/37 legacy keys (RC_SWARM_CAP / RC_SWARM_UNLIMITED) still honored so an
	# old config file migrates instead of resetting
	if data.has(CONF_CAP):
		_swarm_cap = clamp(int(data[CONF_CAP]), 0, 1000)
	elif data.has("RC_SWARM_CAP"):
		_swarm_cap = clamp(int(data["RC_SWARM_CAP"]), 0, 1000)
	if data.has(CONF_UNLIMITED):
		_swarm_unlimited = bool(data[CONF_UNLIMITED])
	elif data.has("RC_SWARM_UNLIMITED"):
		_swarm_unlimited = bool(data["RC_SWARM_UNLIMITED"])


func _on_mod_setting_changed(setting_name, value, mod_name) -> void:
	if mod_name != RC_LOG:
		return
	if setting_name == CONF_CAP:
		_swarm_cap = clamp(int(value), 0, 1000)
	elif setting_name == CONF_UNLIMITED:
		_swarm_unlimited = bool(value)
	else:
		return
	# ModOptions keeps changes in memory only (its on_setting_changed never
	# touches disk) — persisting is the mod's job. The named config is writable
	# via update_config ("default" is schema-owned and refused, see _init_config)
	if _config != null:
		_config.data[CONF_CAP] = float(_swarm_cap)
		_config.data[CONF_UNLIMITED] = _swarm_unlimited
		var _e = ModLoaderConfig.update_config(_config)
	ModLoaderLog.info("swarm config changed: %s=%s (cap=%s unlimited=%s)" % [setting_name, value, _swarm_cap, _swarm_unlimited], RC_LOG)


func _load_texture_from_disk(abs_path: String):
	var img = Image.new()
	if img.load(abs_path) != OK:
		ModLoaderLog.error("failed to load image: %s" % abs_path, RC_LOG)
		return null
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex


func _add_translations() -> void:
	# vanilla-style rich text: BBCode colors straight from the user's settings
	# (same source the vanilla effect renderer uses)
	var pos = "[color=#" + ProgressData.settings.color_positive + "]"
	var cur = "[color=#" + Utils.CURSE_COLOR.to_html() + "]"
	var e = "[/color]"
	for locale in ["zh_Hans_CN", "zh_CN", "zh"]:
		var zh = Translation.new()
		zh.locale = locale
		zh.add_message("ITEM_REVIVAL_COIN", "复活币")
		zh.add_message("EFFECT_REVIVAL_COIN", "战斗中从仍存活的被魅惑小怪中随机绑定" + pos + "一只" + e + "；之后每波它以魅惑状态" + pos + "满血" + e + "参战（数值随波次增长），战死后下一波重新归来。被" + cur + "诅咒" + e + "时绑定" + cur + "两只" + e)
		zh.add_message("ITEM_CHARM_COIN", "魅惑币")
		zh.add_message("EFFECT_CHARM_COIN", "攻击命中生命值低于 " + pos + "30%" + e + " 的敌人时，有 " + pos + "1%" + e + " 概率将其魅惑（最多持有 " + pos + "5" + e + " 个）。被" + cur + "诅咒" + e + "时：概率提升至 " + cur + "2%" + e + "，且生命值低于 " + cur + "60%" + e + " 的敌人追加 " + cur + "1%" + e + " 概率")
		zh.add_message("RC_CONFIG_CAP_TOOLTIP", "同屏魅惑小怪的最大数量（默认 100）。超过上限时最大生命最低的会被静默裁掉。调太高会导致无尽后期卡顿甚至闪退")
		zh.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "移除魅惑大军数量上限。警告：实体过多会压垮物理引擎导致闪退，后果自负")
		# identity mappings are REQUIRED: when the best-matching (zh) translation
		# lacks a msgid, Godot keeps searching other same-language translations
		# and zh_TW would win — Simplified players saw Traditional labels
		zh.add_message("魅惑大军上限", "魅惑大军上限")
		zh.add_message("无上限模式", "无上限模式")
		TranslationServer.add_translation(zh)
	var en = Translation.new()
	en.locale = "en"
	en.add_message("ITEM_REVIVAL_COIN", "Revival Coin")
	en.add_message("EFFECT_REVIVAL_COIN", "Binds " + pos + "one" + e + " random charmed enemy still alive on the field. It joins every wave charmed at " + pos + "full HP" + e + " (stats scale with waves); if it dies, it returns next wave. Binds " + cur + "two" + e + " when " + cur + "cursed" + e)
	en.add_message("ITEM_CHARM_COIN", "Charm Coin")
	en.add_message("EFFECT_CHARM_COIN", "Hits on enemies below " + pos + "30%" + e + " HP have a " + pos + "1%" + e + " chance to charm them (max " + pos + "5" + e + "). When " + cur + "cursed" + e + ": " + cur + "2%" + e + " chance, plus an extra " + cur + "1%" + e + " window on enemies below " + cur + "60%" + e + " HP")
	en.add_message("RC_CONFIG_CAP_TOOLTIP", "Max charmed small enemies alive at once (default 100). Overflow is silently culled, lowest max-HP first. Too high may lag or crash in endless")
	en.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "Removes the swarm cap entirely. WARNING: too many entities can crash the physics engine. Use at your own risk")
	# the config keys ARE Chinese labels in the ModOptions menu (rendered as
	# config_key.to_upper()); registering translations under the key text itself
	# localizes the menu for other languages without renaming the keys (no save
	# migration). The zh blocks above map the keys to themselves (identity) —
	# without that, Godot's same-language fallback lets zh_TW's Traditional
	# mapping win in a Simplified Chinese game
	en.add_message("魅惑大军上限", "Charmed swarm cap")
	en.add_message("无上限模式", "Unlimited mode")
	TranslationServer.add_translation(en)
	for locale in ["zh_Hant_TW", "zh_TW"]:
		var tw = Translation.new()
		tw.locale = locale
		tw.add_message("ITEM_REVIVAL_COIN", "復活幣")
		tw.add_message("EFFECT_REVIVAL_COIN", "戰鬥中從仍存活的被魅惑小怪中隨機綁定" + pos + "一隻" + e + "；之後每波它以魅惑狀態" + pos + "滿血" + e + "參戰（數值隨波次成長），戰死後下一波重新歸來。被" + cur + "詛咒" + e + "時綁定" + cur + "兩隻" + e)
		tw.add_message("ITEM_CHARM_COIN", "魅惑幣")
		tw.add_message("EFFECT_CHARM_COIN", "攻擊命中生命值低於 " + pos + "30%" + e + " 的敵人時，有 " + pos + "1%" + e + " 機率將其魅惑（最多持有 " + pos + "5" + e + " 個）。被" + cur + "詛咒" + e + "時：機率提升至 " + cur + "2%" + e + "，且生命值低於 " + cur + "60%" + e + " 的敵人追加 " + cur + "1%" + e + " 機率")
		tw.add_message("RC_CONFIG_CAP_TOOLTIP", "同屏魅惑小怪的最大數量（預設 100）。超過上限時最大生命最低的會被靜默裁掉。調太高會導致無盡後期卡頓甚至閃退")
		tw.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "移除魅惑大軍數量上限。警告：實體過多會壓垮物理引擎導致閃退，後果自負")
		tw.add_message("魅惑大军上限", "魅惑大軍上限")
		tw.add_message("无上限模式", "無上限模式")
		TranslationServer.add_translation(tw)
	var ru = Translation.new()
	ru.locale = "ru"
	ru.add_message("ITEM_REVIVAL_COIN", "Монета воскрешения")
	ru.add_message("EFFECT_REVIVAL_COIN", "В бою привязывает " + pos + "одного" + e + " случайного очарованного врага, ещё живого на поле; затем каждую волну он сражается очарованным с " + pos + "полным ОЗ" + e + " (характеристики растут с волнами), а после гибели возвращается на следующей. При " + cur + "проклятии" + e + " привязывает " + cur + "двух" + e)
	ru.add_message("ITEM_CHARM_COIN", "Монета очарования")
	ru.add_message("EFFECT_CHARM_COIN", "Попадания по врагам с ОЗ ниже " + pos + "30%" + e + " имеют " + pos + "1%" + e + " шанс очаровать их (макс. " + pos + "5" + e + "). При " + cur + "проклятии" + e + ": шанс " + cur + "2%" + e + ", плюс дополнительный " + cur + "1%" + e + " по врагам с ОЗ ниже " + cur + "60%" + e)
	ru.add_message("RC_CONFIG_CAP_TOOLTIP", "Максимум очарованных мелких врагов на экране (по умолчанию 100). Превышение тихо удаляется, начиная с самых слабых по макс. ОЗ. Слишком высокое значение может тормозить или крашить игру в бесконечном режиме")
	ru.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "Снимает лимит армии очарованных. ВНИМАНИЕ: слишком много сущностей может обрушить физический движок и крашнуть игру. На свой страх и риск")
	ru.add_message("魅惑大军上限", "Лимит армии очарованных")
	ru.add_message("无上限模式", "Без лимита")
	TranslationServer.add_translation(ru)
	var es = Translation.new()
	es.locale = "es"
	es.add_message("ITEM_REVIVAL_COIN", "Moneda de resurrección")
	es.add_message("EFFECT_REVIVAL_COIN", "En combate vincula a " + pos + "un" + e + " enemigo encantado que siga vivo; cada oleada lucha encantado con " + pos + "PS completos" + e + " (las estadísticas escalan con las oleadas) y, si muere, vuelve en la siguiente. Al estar " + cur + "maldita" + e + " vincula a " + cur + "dos" + e)
	es.add_message("ITEM_CHARM_COIN", "Moneda de encantamiento")
	es.add_message("EFFECT_CHARM_COIN", "Los golpes a enemigos con menos del " + pos + "30%" + e + " de PS tienen un " + pos + "1%" + e + " de probabilidad de encantarlos (máx. " + pos + "5" + e + "). Al estar " + cur + "maldita" + e + ": " + cur + "2%" + e + " de probabilidad, más un " + cur + "1%" + e + " extra sobre enemigos con menos del " + cur + "60%" + e + " de PS")
	es.add_message("RC_CONFIG_CAP_TOOLTIP", "Máximo de enemigos pequeños encantados a la vez (100 por defecto). El exceso se elimina en silencio, primero los de menos PS máx. Un valor muy alto puede causar lag o cierres en infinito")
	es.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "Elimina el límite del ejército. AVISO: demasiadas entidades pueden romper el motor físico y cerrar el juego. Bajo tu responsabilidad")
	es.add_message("魅惑大军上限", "Límite del ejército encantado")
	es.add_message("无上限模式", "Modo sin límite")
	TranslationServer.add_translation(es)
	for locale in ["pt_BR", "pt"]:
		var pt = Translation.new()
		pt.locale = locale
		pt.add_message("ITEM_REVIVAL_COIN", "Moeda de Ressurreição")
		pt.add_message("EFFECT_REVIVAL_COIN", "Em combate, vincula " + pos + "um" + e + " inimigo encantado ainda vivo no campo; ele luta em toda onda encantado com " + pos + "PV completos" + e + " (atributos escalam com as ondas) e, se morrer, retorna na próxima. Quando " + cur + "amaldiçoada" + e + ", vincula " + cur + "dois" + e)
		pt.add_message("ITEM_CHARM_COIN", "Moeda de Encantamento")
		pt.add_message("EFFECT_CHARM_COIN", "Golpes em inimigos com menos de " + pos + "30%" + e + " de PV têm " + pos + "1%" + e + " de chance de encantá-los (máx. " + pos + "5" + e + "). Quando " + cur + "amaldiçoada" + e + ": " + cur + "2%" + e + " de chance, mais " + cur + "1%" + e + " extra em inimigos com menos de " + cur + "60%" + e + " de PV")
		pt.add_message("RC_CONFIG_CAP_TOOLTIP", "Máximo de inimigos pequenos encantados ao mesmo tempo (padrão 100). O excesso é removido silenciosamente, dos mais fracos em PV máx. primeiro. Valores altos demais podem causar lag ou crashes no infinito")
		pt.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "Remove o limite do exército. AVISO: entidades demais podem quebrar o motor de física e fechar o jogo. Por sua conta e risco")
		pt.add_message("魅惑大军上限", "Limite do exército encantado")
		pt.add_message("无上限模式", "Modo sem limite")
		TranslationServer.add_translation(pt)
	var de = Translation.new()
	de.locale = "de"
	de.add_message("ITEM_REVIVAL_COIN", "Wiederbelebungsmünze")
	de.add_message("EFFECT_REVIVAL_COIN", "Bindet im Kampf " + pos + "einen" + e + " zufälligen verzauberten Gegner, der noch lebt; er kämpft jede Welle verzaubert mit " + pos + "vollen LP" + e + " (Werte skalieren mit den Wellen) und kehrt nach dem Tod in der nächsten Welle zurück. Wenn " + cur + "verflucht" + e + ", bindet sie " + cur + "zwei" + e)
	de.add_message("ITEM_CHARM_COIN", "Zaubermünze")
	de.add_message("EFFECT_CHARM_COIN", "Treffer auf Gegner unter " + pos + "30 %" + e + " LP haben eine " + pos + "1 %" + e + "-Chance, sie zu verzaubern (max. " + pos + "5" + e + "). Wenn " + cur + "verflucht" + e + ": " + cur + "2 %" + e + " Chance, plus zusätzliche " + cur + "1 %" + e + " bei Gegnern unter " + cur + "60 %" + e + " LP")
	de.add_message("RC_CONFIG_CAP_TOOLTIP", "Maximale Zahl gleichzeitig verzauberter kleiner Gegner (Standard 100). Überschuss wird still entfernt, niedrigste max. LP zuerst. Zu hohe Werte können im Endlosmodus laggen oder crashen")
	de.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "Entfernt das Armeelimit komplett. WARNUNG: Zu viele Entitäten können die Physik-Engine zum Absturz bringen. Auf eigene Gefahr")
	de.add_message("魅惑大军上限", "Limit der verzauberten Armee")
	de.add_message("无上限模式", "Unbegrenzt-Modus")
	TranslationServer.add_translation(de)
	var fr = Translation.new()
	fr.locale = "fr"
	fr.add_message("ITEM_REVIVAL_COIN", "Pièce de réanimation")
	fr.add_message("EFFECT_REVIVAL_COIN", "En combat, lie " + pos + "un" + e + " ennemi charmé encore vivant ; il combat chaque vague charmé avec " + pos + "ses PV complets" + e + " (stats adaptées aux vagues) et, s'il meurt, revient à la vague suivante. Quand elle est " + cur + "maudite" + e + ", elle en lie " + cur + "deux" + e)
	fr.add_message("ITEM_CHARM_COIN", "Pièce de charme")
	fr.add_message("EFFECT_CHARM_COIN", "Les coups sur les ennemis sous " + pos + "30 %" + e + " de PV ont " + pos + "1 %" + e + " de chance de les charmer (max " + pos + "5" + e + "). Quand elle est " + cur + "maudite" + e + " : " + cur + "2 %" + e + " de chance, plus " + cur + "1 %" + e + " supplémentaire sur les ennemis sous " + cur + "60 %" + e + " de PV")
	fr.add_message("RC_CONFIG_CAP_TOOLTIP", "Nombre max d'ennemis communs charmés simultanément (100 par défaut). Le surplus est supprimé silencieusement, PV max les plus faibles d'abord. Trop haut peut laguer ou crasher en infini")
	fr.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "Supprime la limite de l'armée. ATTENTION : trop d'entités peuvent faire crasher le moteur physique. À vos risques et périls")
	fr.add_message("魅惑大军上限", "Limite de l'armée charmée")
	fr.add_message("无上限模式", "Mode illimité")
	TranslationServer.add_translation(fr)
	var ja = Translation.new()
	ja.locale = "ja"
	ja.add_message("ITEM_REVIVAL_COIN", "復活コイン")
	ja.add_message("EFFECT_REVIVAL_COIN", "戦闘中、生存している魅了済みの敵からランダムに" + pos + "1体" + e + "をバインド。以降毎WAVE、魅了状態・" + pos + "HP全開" + e + "で参戦（数値はWAVEに応じて成長）。死亡しても次のWAVEで復帰。" + cur + "呪い" + e + "時は" + cur + "2体" + e + "バインド")
	ja.add_message("ITEM_CHARM_COIN", "魅惑コイン")
	ja.add_message("EFFECT_CHARM_COIN", "HP" + pos + "30%" + e + "未満の敵への攻撃命中時、" + pos + "1%" + e + "の確率で魅了する（最大" + pos + "5" + e + "個まで所持可）。" + cur + "呪い" + e + "時：確率が" + cur + "2%" + e + "に上昇し、HP" + cur + "60%" + e + "未満の敵には追加で" + cur + "1%" + e + "の確率")
	ja.add_message("RC_CONFIG_CAP_TOOLTIP", "同時に存在できる魅了した雑魚の最大数（デフォルト100）。超過分は最大HPが低い順に静かに除去される。高すぎるとエンドレス後半で重くなりクラッシュすることもある")
	ja.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "魅了大軍の上限を解除する。警告：エンティティが多すぎると物理エンジンが破綻しクラッシュする可能性あり。自己責任で")
	ja.add_message("魅惑大军上限", "魅了大軍の上限")
	ja.add_message("无上限模式", "無制限モード")
	TranslationServer.add_translation(ja)
	var ko = Translation.new()
	ko.locale = "ko"
	ko.add_message("ITEM_REVIVAL_COIN", "부활 코인")
	ko.add_message("EFFECT_REVIVAL_COIN", "전투 중 살아있는 매혹된 적 중 무작위 " + pos + "1마리" + e + "를 바인드. 이후 매 웨이브 매혹 상태로 " + pos + "체력 최대" + e + "로 참전(수치는 웨이브에 따라 증가). 사망해도 다음 웨이브에 복귀. " + cur + "저주" + e + " 시 " + cur + "2마리" + e + " 바인드")
	ko.add_message("ITEM_CHARM_COIN", "매혹 코인")
	ko.add_message("EFFECT_CHARM_COIN", "HP " + pos + "30%" + e + " 미만의 적 명중 시 " + pos + "1%" + e + " 확률로 매혹(최대 " + pos + "5" + e + "개 보유). " + cur + "저주" + e + " 시: 확률 " + cur + "2%" + e + "로 증가, HP " + cur + "60%" + e + " 미만의 적에게 추가 " + cur + "1%" + e + " 확률")
	ko.add_message("RC_CONFIG_CAP_TOOLTIP", "동시에 존재하는 매혹된 잡몹의 최대 수(기본 100). 초과분은 최대 HP가 낮은 순으로 조용히 정리됨. 너무 높으면 엔드리스 후반에 렉이나 충돌이 발생할 수 있음")
	ko.add_message("RC_CONFIG_UNLIMITED_TOOLTIP", "매혹 군단 상한을 해제함. 경고: 엔티티가 너무 많으면 물리 엔진이 버티지 못하고 게임이 종료될 수 있음. 본인 책임 하에 사용")
	ko.add_message("魅惑大军上限", "매혹 군단 상한")
	ko.add_message("无上限模式", "무제한 모드")
	TranslationServer.add_translation(ko)


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
	# Drop ally-ally body collision (charm() set the body mask to PETS_BIT +
	# OBSTACLES_BIT): in a dense swarm the move_and_slide pair resolution
	# between allies is pure physics tax — removing it buys real headroom for
	# a bigger swarm cap. Walls stay; combat is unaffected since hit detection
	# runs through hitboxes/hurtboxes, not bodies. Restored on death by the
	# charm behavior's uncharm(), which saved the original mask at charm time
	enemy.collision_mask = Utils.OBSTACLES_BIT
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
	# Pin the vanilla retarget timer forever: enemy.gd re-picks targets every
	# 0.25s, and the charm behavior's update_target scans the ENTIRE enemy list
	# per ally per pick (allies x enemies x 4/s of pure GDScript distance
	# checks — the quadratic swarm tax in endless). The 0.1s police in
	# _police_charmed_targets owns ally targeting now, so vanilla never
	# re-picks at all — this also closes the 0.25s window where the whole
	# swarm fell back to targeting the player (the "mass defection" look).
	# Restored to 0 in _on_charmed_ally_died: the spawner pools dead nodes and
	# a pooled hostile with a pinned timer would never retarget again
	enemy.update_target_timer = -99999.0


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
	# unpin the vanilla retarget timer (see _setup_charmed_ally) so a pooled
	# respawn of this node comes back with working targeting
	entity.update_target_timer = 0.0
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

	_police_accum += delta
	if _police_accum >= 0.1:
		_police_accum = 0.0
		if RunData.wave_in_progress:
			_police_charmed_targets(spawner, main)

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
	if RunData.current_wave < BOSS_MAGNET_MIN_WAVE:
		return
	var charmed_power := 0
	var hostile_power := 0
	var charmed_count := 0
	# hostile bosses/elites alive on the field (vanilla wave spawns included);
	# charmed boss allies don't eat the cap — it limits threats, not your army
	var bosses_alive := 0
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
			if cb == null or not cb.charmed:
				bosses_alive += 1
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
	# alive cap by wave: 10->1, 15->2, 20->3, then endless bonus. v33 tuning:
	# was 8/12/16/20 -> 1/2/3/4 counting only magnet-spawned bosses; now the cap
	# counts all hostile bosses/elites on the field, so wave-start bosses eat
	# the budget
	var alive_cap = clamp(1 + (RunData.current_wave - 10) / 5, 1, 3) + endless_bonus
	var wave_cap = BOSS_MAGNET_BASE_PER_WAVE + int(min(ratio, BOSS_MAGNET_RATIO_CLAMP) * 1.5) + endless_bonus * 2
	wave_cap = max(wave_cap, alive_cap)
	if _magnet_spawned_this_wave >= wave_cap:
		return
	if bosses_alive >= alive_cap:
		return
	var chance = min(BOSS_MAGNET_CHANCE_CAP, ratio * BOSS_MAGNET_RATIO_FACTOR)
	if not Utils.get_chance_success(chance):
		return
	var pool = ItemService.get_elites_from_zone(RunData.current_zone) + ItemService.get_bosses_from_zone(RunData.current_zone)
	if pool.empty():
		return
	var count = 2 if ratio >= 1.5 else 1
	# never exceed the remaining room of either cap (v23 bug: the 2-at-once
	# roll ignored the alive cap, so every stage spawned one extra boss)
	count = min(count, alive_cap - bosses_alive)
	count = min(count, wave_cap - _magnet_spawned_this_wave)
	if count <= 0:
		return
	var spawned := 0
	for i in count:
		var data = Utils.get_rand_element(pool)
		if data == null or data.scene == null:
			continue
		var pos = spawner.get_spawn_pos_in_area(_get_player_pos(main), -1, 100, true)
		var args = EntitySpawner.SpawnEntityArgs.new(pos, EntityType.BOSS)
		var boss = spawner.spawn_entity(data.scene, args, null, null, -1)
		if boss == null:
			continue
		# runtime-instanced bosses have no filename; remember the scene path so
		# the revive-charm and wave carry-over can rebuild them
		boss.set_meta("rc_scene_path", data.scene.resource_path)
		spawned += 1
	_magnet_spawned_this_wave += spawned
	if spawned > 0:
		ModLoaderLog.info("charm swarm attracted %s boss(es) (power ratio %.2f, wave spawns %s/%s)" % [spawned, ratio, _magnet_spawned_this_wave, wave_cap], RC_LOG)


func _reset_run_state() -> void:
	_boss_records.clear()
	_coin_allies.clear()
	_coin_slots.clear()
	_charmed_alive_species.clear()
	_bindable_species.clear()


# Each cursed charm coin injects an extra charm window (+1% under 60% HP) into
# the player's charm effects at runtime; the base 2%@30% boost comes from the
# vanilla curse pass doubling the effect value. The stat hash is
# structure_range — a stat that stays 0 in practice, keeping the chance flat
# instead of scaling off max HP into guaranteed charm in the ultra late game.
# Existing windows are counted live so a resumed save can't desync the count
func _reconcile_charm_coins() -> void:
	var cursed := 0
	for item in RunData.get_player_items_ref(0):
		if item != null and item.my_id == CHARM_COIN_ID and item.is_cursed:
			cursed += 1
	var arr = RunData.get_player_effects(0)[Keys.charm_on_hit_hash]
	var existing := 0
	for e in arr:
		if e is Array and e == [Keys.structure_range_hash, 1, 60]:
			existing += 1
	while existing < cursed:
		arr.push_back([Keys.structure_range_hash, 1, 60])
		existing += 1
	while existing > cursed:
		var idx = arr.find([Keys.structure_range_hash, 1, 60])
		if idx == -1:
			break
		arr.remove(idx)
		existing -= 1


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
	for slot in _coin_slots:
		if not slot.scene_path.empty():
			filled += 1
	if not _coin_slots.empty():
		ModLoaderLog.info("coin respawn check: %s/%s slots filled" % [filled, _coin_slots.size()], RC_LOG)
	for slot in _coin_slots:
		if slot.scene_path.empty():
			continue
		var ally = _spawn_charmed_enemy(slot.scene_path, main, 0)
		if ally != null:
			_coin_allies[ally.get_instance_id()] = true


func _on_wave_end() -> void:
	# forensic log for the wave-end-with-charmed-boss crash hunt
	if not _boss_records.empty():
		ModLoaderLog.info("wave end: carrying %s charmed boss(es)" % _boss_records.size(), RC_LOG)
	# bind unbound coin slots to a still-living charmed species, weighted by
	# max HP so slots land on tanky species instead of random fodder
	if _bindable_species.empty():
		return
	for slot in _coin_slots:
		if not slot.scene_path.empty():
			continue
		slot.scene_path = _pick_weighted_species(_bindable_species)
		ModLoaderLog.info("revival coin bound to %s" % slot.scene_path, RC_LOG)


# ---------------- scan ----------------

func _scan(spawner, main) -> void:
	var enemies = spawner.get_all_enemies(true)

	# hook boss deaths + snapshot charmed enemies
	_charmed_alive_species.clear()
	_bindable_species.clear()
	var charmed_smalls := []
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
			charmed_smalls.push_back(enemy)
			# only normal enemies are coin-bindable species; coin allies
			# themselves don't seed new bindings (no wave-start clones)
			if not enemy.filename.empty():
				_charmed_alive_species[enemy.filename] = int(_charmed_alive_species.get(enemy.filename, 0)) + 1
				if not _coin_allies.has(enemy.get_instance_id()):
					# value = best max HP seen for the species, used as the
					# weight for coin binding (tanky species bind preferentially)
					var seen_hp = int(_bindable_species.get(enemy.filename, 0))
					if enemy.max_stats.health > seen_hp:
						_bindable_species[enemy.filename] = enemy.max_stats.health
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

	# deterministic swarm cull: keeps the field at base + cap, so vanilla's
	# random execution pass barely ever triggers from our contribution. Coin
	# allies are exempt — they're the resurrection-bound few, not swarm.
	# Skipped entirely in unlimited mode (crash risk is the player's choice)
	var excess = charmed_smalls.size() - _swarm_cap
	if excess > 0 and not _swarm_unlimited and not spawner.get("_cleaning_up"):
		_cull_player_pos = _get_player_pos(main)
		charmed_smalls.sort_custom(self, "_sort_cull_order")
		var culled := 0
		for ally in charmed_smalls:
			if culled >= excess:
				break
			if _coin_allies.has(ally.get_instance_id()):
				continue
			ally.can_drop_loot = false
			ally.die()
			culled += 1
		if culled > 0:
			ModLoaderLog.info("swarm over %s cap: culled %s weakest charmed small(s)" % [_swarm_cap, culled], RC_LOG)

	# NOTE: no culling of _boss_records here — a charmed boss killed by the
	# wave-end cleanup is dead but must keep its record for the carry-over.
	# Real deaths erase their record in _on_boss_died; run resets clear the rest.
	_reconcile_coins()
	_reconcile_charm_coins()

	# bind empty coin slots as soon as a charmed ally exists, and spawn the
	# new ally immediately — wave-end binding stays as a fallback, but a coin
	# bought in the shop should not take two full waves to do anything
	if not _bindable_species.empty():
		for slot in _coin_slots:
			if not slot.scene_path.empty():
				continue
			slot.scene_path = _pick_weighted_species(_bindable_species)
			ModLoaderLog.info("revival coin bound to %s" % slot.scene_path, RC_LOG)
			var ally = _spawn_charmed_enemy(slot.scene_path, main, 0)
			if ally != null:
				_coin_allies[ally.get_instance_id()] = true

	# prune dead coin ally ids; the binding itself persists and respawns next wave
	for ally_id in _coin_allies.keys():
		var e = instance_from_id(ally_id)
		if e == null or not is_instance_valid(e) or e.dead:
			_coin_allies.erase(ally_id)

	# charmed allies stay in the spawner's enemies list, so a big swarm eats the
	# vanilla max_enemies budget and the game starts executing "excess" small
	# enemies (that's why smalls dry up mid game, not the bosses — bosses have
	# their own list). Refund the budget by the number of living charmed smalls
	var wd = spawner.get("_current_wave_data")
	if wd != null:
		if wd.get_instance_id() != _max_enemies_base_for:
			_max_enemies_base_for = wd.get_instance_id()
			_max_enemies_base = wd.max_enemies
		var charmed_total := 0
		for key in _charmed_alive_species:
			charmed_total += _charmed_alive_species[key]
		# unlimited mode refunds the full swarm (that's the v33 crash setup —
		# player's explicit choice); capped mode keeps the field at base + cap
		var refund = charmed_total if _swarm_unlimited else min(charmed_total, _swarm_cap)
		wd.max_enemies = _max_enemies_base + refund


# sort_custom comparator for the swarm cull: weakest max HP first (the swarm
# keeps its elite stock), ties broken by farthest from the player
func _sort_cull_order(a, b) -> bool:
	var ha = a.max_stats.health
	var hb = b.max_stats.health
	if ha != hb:
		return ha < hb
	return a.global_position.distance_squared_to(_cull_player_pos) > b.global_position.distance_squared_to(_cull_player_pos)


# Weighted random species pick, weights = best max HP seen (from
# _bindable_species). Tanky species get the coin slots, but fodder keeps a
# non-zero chance so bindings still vary run to run
func _pick_weighted_species(species_hp: Dictionary) -> String:
	var total := 0.0
	for key in species_hp:
		total += max(1, int(species_hp[key]))
	var roll = randf() * total
	for key in species_hp:
		roll -= max(1, int(species_hp[key]))
		if roll <= 0.0:
			return key
	return species_hp.keys()[0]


# Slots are counted, never keyed by item instance: non-cursed shop buys push the
# shared ItemService pool instance (only cursing duplicates it), so two coins can
# be the same object twice in the items array. Counting entries matches vanilla
# stacking semantics no matter how the array was built (shop, save load, debug)
func _reconcile_coins() -> void:
	var wanted := 0
	for item in RunData.get_player_items_ref(0):
		if item != null and item.my_id == COIN_ID:
			wanted += 2 if item.is_cursed else 1
	while _coin_slots.size() > wanted:
		# coin sold/lost: drop an unbound slot first, a bound one only if all are bound
		var drop := -1
		for i in range(_coin_slots.size() - 1, -1, -1):
			if _coin_slots[i].scene_path.empty():
				drop = i
				break
		if drop == -1:
			drop = _coin_slots.size() - 1
		_coin_slots.remove(drop)
		ModLoaderLog.info("coin slot removed (%s left)" % _coin_slots.size(), RC_LOG)
	while _coin_slots.size() < wanted:
		_coin_slots.append({"scene_path": ""})
		ModLoaderLog.info("coin slot created (%s total)" % _coin_slots.size(), RC_LOG)


# Vanilla targeting (enemy.gd update_target) re-picks the nearest pet/player
# every 0.25s; the charm behavior only overrides that with an enemy target
# while at least one ENEMIES_BIT unit is alive, and each re-pick scans the
# ENTIRE enemy list per ally (the quadratic swarm tax). Allies have their
# retarget timer pinned by _setup_charmed_ally (re-pinned here every tick),
# so this police pass IS their only targeting now: re-point allies whose
# target went stale — nearest hostile when one exists, otherwise the ally
# farthest from the player so the swarm drifts back into the field instead of
# crowding you. Runs at 0.1s cadence and stays cheap in endless: allies with
# a living hostile target (the common case) skip the inner scan entirely
func _police_charmed_targets(spawner, main) -> void:
	var players = main.get("_players")
	if not (players is Array) or players.empty() or not is_instance_valid(players[0]):
		return
	var player = players[0]
	var hostiles := []
	var allies := []
	for enemy in spawner.get_all_enemies(true):
		if enemy == null or not is_instance_valid(enemy) or enemy.dead or enemy.get_parent() == null:
			continue
		# charm() sets the body layer to PETS_BIT; nothing else in the enemies
		# list has it, so this is the fast charmed-or-not split
		if enemy.collision_layer == Utils.PETS_BIT:
			allies.push_back(enemy)
		elif enemy.collision_layer == Utils.ENEMIES_BIT:
			hostiles.push_back(enemy)
	if allies.empty():
		return
	for ally in allies:
		# backstop the pin from _setup_charmed_ally (respawn paths, late charm)
		ally.update_target_timer = -99999.0
		var target = ally.current_target
		if target != null and is_instance_valid(target) and not target.dead \
		and target.get("collision_layer") == Utils.ENEMIES_BIT:
			continue
		var new_target = null
		if not hostiles.empty():
			var best := INF
			for h in hostiles:
				var d: float = ally.global_position.distance_squared_to(h.global_position)
				if d < best:
					best = d
					new_target = h
		elif allies.size() > 1:
			var best := -1.0
			for other in allies:
				if other == ally:
					continue
				var d: float = player.global_position.distance_squared_to(other.global_position)
				if d > best:
					best = d
					new_target = other
		if new_target != null:
			ally.current_target = new_target


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
	if not Utils.get_chance_success(_boss_charm_chance()):
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
	# same teardown guard as _revive_boss: spawning into a scene that is being
	# torn down hard-crashes the engine with no script error (v16 lesson)
	if spawner.get("_cleaning_up"):
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


# romantic already hits 100% charm on small fry late game, so owning a charm
# coin on him instead improves the boss revive-charm rate
func _boss_charm_chance() -> float:
	var chance = BOSS_CHARM_CHANCE
	var character = RunData.get_player_character(0)
	if character != null and character.my_id == "character_romantic":
		for item in RunData.get_player_items_ref(0):
			if item != null and item.my_id == CHARM_COIN_ID:
				chance += BOSS_CHARM_ROMANTIC_BONUS
				break
	return chance


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
