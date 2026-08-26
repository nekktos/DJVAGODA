extends Node
##
## Сохранение мира (Этап 10, шаг 5, GDD раздел 6).
##
## Сохраняет и загружает ТОЛЬКО хост. Это прямо следует из решения «сохранение
## на главном клиенте»: у клиента нет ни авторитетного состояния, ни права его
## менять, и его файл сохранения был бы копией чужой правды.
##
## Прогресс игрока привязан к ПРОФИЛЮ и к МИРУ ХОЗЯИНА, а не к сетевому id.
## Peer id выдаётся заново при каждом подключении и как ключ сейва не годится —
## именно это было записано открытым вопросом с Этапа 0.
##
## Что сохраняется:
##   - мир: владелец дворца, павшие вожаки, объявленные победы;
##   - отношения фракций;
##   - казна каждой стороны, отдельно «при себе» и «в складе»;
##   - игроки по профилям: сторона, снаряжение, ранения, прогресс службы.
##
## Что НЕ сохраняется намеренно: позиции персонажей, снаряды, трупы, кучи груза
## и построенные здания. Это состояние боя, а не прогресса; восстанавливать его
## значит воскрешать середину чужой драки. Игроки возвращаются на базы своей
## стороны — как после смерти.
##

const FACTIONS := preload("res://scripts/factions.gd")

## Куда кладём. Один файл на мир: имя мира хранится у хозяина и переживает
## перезапуск, поэтому «мир первого хоста» остаётся тем же самым миром.
const SAVE_DIR := "user://saves"
const WORLD_ID_PATH := "user://world.cfg"

## Как часто хост сохраняется сам, секунды. Слоты и ручное сохранение по GDD
## тоже нужны, но автосейв важнее: без него любой вылет стирает партию.
const AUTOSAVE_INTERVAL := 60.0

signal saved(path: String)
signal loaded(path: String)

var world_id := ""

## Ключи командной строки:
##   --world=ИМЯ    работать с отдельным файлом мира
##   --freshworld   не загружать сохранение и не сохраняться самому
##
## Второй нужен автопроверкам: без него каждый прогон подхватывал бы мир,
## записанный предыдущим, и тесты перестали бы быть герметичными. Это не
## теория — ровно так они и посыпались все разом, когда автосейв появился.
var _frozen := false

var _autosave_t := 0.0
## Профили, уже восстановленные в этой сессии: второй раз накатывать нельзя.
var _restored := {}


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_frozen = args.has("--freshworld")
	for arg in args:
		if arg.begins_with("--world="):
			world_id = arg.substr("--world=".length())
	if world_id.is_empty():
		world_id = _load_or_make_world_id()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	_autosave_t += delta
	if _autosave_t < AUTOSAVE_INTERVAL:
		return
	_autosave_t = 0.0
	save_world()


func save_path() -> String:
	return "%s/%s.cfg" % [SAVE_DIR, world_id]


# --- сохранение ------------------------------------------------------------

## Записать состояние мира. Только на хосте. Возвращает путь или пустую строку.
func save_world() -> String:
	if not Net.hosting() or _frozen:
		return ""
	var world := get_parent()
	var cfg := ConfigFile.new()

	cfg.set_value("meta", "world_id", world_id)
	cfg.set_value("meta", "saved_at", Time.get_datetime_string_from_system())

	var objective: Node = world.objective
	cfg.set_value("world", "palace_owner", int(objective.palace_owner))
	cfg.set_value("world", "leader_down", objective.leader_down)
	cfg.set_value("world", "victors", objective.victors)

	cfg.set_value("diplomacy", "values", world.diplomacy.values)

	for faction in FACTIONS.COUNT:
		var wallet: Node = world.treasury.of(faction)
		if wallet == null:
			continue
		var key := "treasury/%d" % faction
		cfg.set_value(key, "carried", wallet.carried.amounts)
		cfg.set_value(key, "carried_cap", wallet.carried.capacity)
		cfg.set_value(key, "stored", wallet.stored.amounts)
		cfg.set_value(key, "stored_cap", wallet.stored.capacity)

	for child in world.get_node("Players").get_children():
		var profile := String(child.profile_id)
		if profile.is_empty():
			continue
		cfg.set_value("player/" + profile, "faction", int(child.faction))
		cfg.set_value("player/" + profile, "gear_tier", int(child.gear_tier))
		cfg.set_value("player/" + profile, "is_leader", bool(child.is_leader))
		cfg.set_value("player/" + profile, "orders_done", int(child.orders_done))
		cfg.set_value("player/" + profile, "final_threshold", int(child.final_threshold))
		cfg.set_value("player/" + profile, "alive", bool(child.health.alive))
		cfg.set_value("player/" + profile, "severed_mask", int(child.body.severed_mask))
		cfg.set_value("player/" + profile, "prosthetics", child.body.prosthetics)
		cfg.set_value("player/" + profile, "eyes_lost", int(child.body.eyes_lost))
		cfg.set_value("player/" + profile, "bandages", int(child.body.bandages))
		cfg.set_value("player/" + profile, "in_wheelchair", bool(child.body.in_wheelchair))

	var path := save_path()
	if cfg.save(path) != OK:
		push_warning("Не удалось сохранить мир в %s" % path)
		return ""
	print("[сейв] мир сохранён: %s" % path)
	saved.emit(path)
	return path


# --- загрузка --------------------------------------------------------------

## Восстановить мир из файла. Только на хосте, до появления игроков.
func load_world() -> bool:
	if not Net.hosting() or _frozen:
		return false
	var cfg := ConfigFile.new()
	var path := save_path()
	if cfg.load(path) != OK:
		return false

	var world := get_parent()
	var objective: Node = world.objective
	objective.palace_owner = int(cfg.get_value("world", "palace_owner", objective.palace_owner))
	objective.leader_down = cfg.get_value("world", "leader_down", objective.leader_down)
	objective.victors = cfg.get_value("world", "victors", objective.victors)

	world.diplomacy.values = cfg.get_value("diplomacy", "values", world.diplomacy.values)

	for faction in FACTIONS.COUNT:
		var wallet: Node = world.treasury.of(faction)
		if wallet == null:
			continue
		var key := "treasury/%d" % faction
		if not cfg.has_section(key):
			continue
		wallet.carried.amounts = cfg.get_value(key, "carried", wallet.carried.amounts)
		wallet.carried.capacity = int(cfg.get_value(key, "carried_cap", wallet.carried.capacity))
		wallet.stored.amounts = cfg.get_value(key, "stored", wallet.stored.amounts)
		wallet.stored.capacity = int(cfg.get_value(key, "stored_cap", wallet.stored.capacity))

	_restored.clear()
	print("[сейв] мир загружен: %s" % path)
	loaded.emit(path)
	return true


## Какую сторону этот профиль занимал в прошлый раз. -1 — профиль незнакомый.
##
## Нужно ДО спавна: прогресс привязан к фракции (GDD раздел 6), значит вернуться
## игрок должен за ту же сторону, за которую играл, а не за ту, что выбрал в меню.
func saved_faction(profile: String) -> int:
	if profile.is_empty() or _frozen:
		return -1
	var cfg := ConfigFile.new()
	if cfg.load(save_path()) != OK:
		return -1
	var key := "player/" + profile
	if not cfg.has_section(key):
		return -1
	return int(cfg.get_value(key, "faction", -1))


## Накатить сохранённое состояние на только что заспавненного персонажа.
## Только на хосте и только один раз за сессию на профиль.
func restore_player(player: Node3D) -> bool:
	if not Net.hosting() or player == null or _frozen:
		return false
	var profile := String(player.profile_id)
	if profile.is_empty() or _restored.has(profile):
		return false

	var cfg := ConfigFile.new()
	if cfg.load(save_path()) != OK:
		return false
	var key := "player/" + profile
	if not cfg.has_section(key):
		return false

	player.gear_tier = int(cfg.get_value(key, "gear_tier", 0))
	player.is_leader = bool(cfg.get_value(key, "is_leader", player.is_leader))
	player.orders_done = int(cfg.get_value(key, "orders_done", 0))
	player.final_threshold = int(cfg.get_value(key, "final_threshold", player.final_threshold))
	player.body.severed_mask = int(cfg.get_value(key, "severed_mask", 0))
	player.body.prosthetics = cfg.get_value(key, "prosthetics", player.body.prosthetics)
	player.body.eyes_lost = int(cfg.get_value(key, "eyes_lost", 0))
	player.body.bandages = int(cfg.get_value(key, "bandages", player.body.bandages))
	player.body.in_wheelchair = bool(cfg.get_value(key, "in_wheelchair", false))

	_restored[profile] = true
	print("[сейв] восстановлен профиль %s (сторона %s)" % [
		profile, FACTIONS.name_of(int(player.faction))
	])
	return true


func has_save() -> bool:
	return FileAccess.file_exists(save_path())


# --- идентификатор мира ----------------------------------------------------

## Мир хозяина. Заводится один раз и живёт в user://, поэтому «мир первого
## хоста» остаётся тем же самым миром между запусками игры.
func _load_or_make_world_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(WORLD_ID_PATH) == OK:
		var saved_id := String(cfg.get_value("world", "id", ""))
		if not saved_id.is_empty():
			return saved_id
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fresh := "w%08x" % rng.randi()
	cfg.set_value("world", "id", fresh)
	cfg.save(WORLD_ID_PATH)
	return fresh
