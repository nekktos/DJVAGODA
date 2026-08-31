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
##   - постройки: что стоит, где, чьё и достроено ли;
##   - батраки: сколько их у каждой стороны и кто из них кто;
##   - нанятый отряд игрока: сколько мечников и сколько лучников.
##
## Что НЕ сохраняется намеренно: позиции персонажей, снаряды, трупы и кучи
## груза. Это состояние боя, а не прогресса; восстанавливать его значит
## воскрешать середину чужой драки. Игроки возвращаются на базы своей стороны —
## как после смерти.
##
## ПОСТРОЙКИ раньше лежали в том же списке, и это была ошибка. Склад стоит сотни
## камня и поднимает стороне потолок хранения — а потолок мы сохраняли. Выходило
## худшее из двух: ресурсы списаны, потолок поднят, а склада на месте нет.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")

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
## Мир задан ключом --world=ИМЯ. Такой мир «новой игрой» не подменяют: набор
## проверок сам выбирает, в каком файле работать, и смена имени под ним увела
## бы проверку в пустоту.
var _world_from_cmdline := false

var _autosave_t := 0.0
## Профили, уже восстановленные в этой сессии: второй раз накатывать нельзя.
var _restored := {}


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_frozen = args.has("--freshworld")
	for arg in args:
		if arg.begins_with("--world="):
			world_id = arg.substr("--world=".length())
			_world_from_cmdline = true
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

	# Недостроенное сохраняем вместе с прогрессом: стройка идёт минутами, и
	# выход из игры посреди неё не должен стоить всей затраченной кучи.
	var built: Array = []
	for node in world.get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(node):
			continue
		built.append({
			"kind": int(node.kind),
			"point": node.position,
			"yaw": float(node.rotation.y),
			"owner": int(node.owner_id),
			"faction": int(node.faction),
			"progress": float(node.progress),
			"health": float(node.health),
		})
	cfg.set_value("world", "buildings", built)

	# Батраки — такое же вложение, как постройки: каждый нанят за золото, а
	# золото добывают они же. Позиции не сохраняем и здесь, только сторону,
	# ремесло и базу: батрак возвращается к своей базе, как игрок после смерти.
	var hands: Array = []
	for node in world.get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(node) or not ("sync_role" in node):
			continue
		hands.append({
			"faction": int(node.faction),
			"role": int(node.sync_role),
			"home": node.home,
		})
	cfg.set_value("world", "labourers", hands)

	for faction in FACTIONS.COUNT:
		var wallet: Node = world.treasury.of(faction)
		if wallet == null:
			continue
		var key := "treasury/%d" % faction
		cfg.set_value(key, "carried", wallet.carried.amounts)
		cfg.set_value(key, "carried_cap", wallet.carried.capacity)
		cfg.set_value(key, "stored", wallet.stored.amounts)
		cfg.set_value(key, "stored_cap", wallet.stored.capacity)
		# Лошади — такое же имущество стороны, как золото, и стоят дороже:
		# двадцать пять золота и двенадцать железа за голову, до дюжины в
		# конюшне. Не сохраняя их, мы сжигали всю конюшню при каждом выходе.
		cfg.set_value(key, "horses", int(wallet.horses))

	for child in world.get_node("Players").get_children():
		var profile := String(child.profile_id)
		if profile.is_empty():
			continue
		# Прогресс лежит на паре ПРОФИЛЬ + СТОРОНА, а не на одном профиле.
		#
		# Раньше слот был один, и сторона из него навязывалась поверх выбора в
		# меню: сыграв однажды за злодея, человек больше не мог сесть ни за кого
		# другого — меню показывало выбор, которого не было. Прогресс при этом
		# всё равно привязан к стороне (GDD раздел 6), просто теперь у каждой
		# стороны он свой.
		var key := _player_key(profile, int(child.faction))
		cfg.set_value("player/" + profile, "last_faction", int(child.faction))
		cfg.set_value(key, "faction", int(child.faction))
		cfg.set_value(key, "gear_tier", int(child.gear_tier))
		# Сколько лошадей запрягать — решение игрока, а не случайное число.
		# Сбрасывать его к двойке при каждом входе значит заставлять принимать
		# это решение заново каждый раз.
		cfg.set_value(key, "harness_size", int(child.harness_size))
		cfg.set_value(key, "is_leader", bool(child.is_leader))
		cfg.set_value(key, "orders_done", int(child.orders_done))
		cfg.set_value(key, "final_threshold", int(child.final_threshold))
		cfg.set_value(key, "alive", bool(child.health.alive))
		cfg.set_value(key, "severed_mask", int(child.body.severed_mask))
		cfg.set_value(key, "prosthetics", child.body.prosthetics)
		cfg.set_value(key, "eyes_lost", int(child.body.eyes_lost))
		# Вставленные глаза — отдельно от выбитых. Без этого вернувшийся игрок
		# оказывался слепым на глаз, за который уже заплатил.
		cfg.set_value(key, "eye_implants", int(child.body.eye_implants))
		# Трофеи ОБЯЗАНЫ переживать выход.
		#
		# Некротический протез стоит десять чужих конечностей одного вида, и
		# набрать столько за один заход почти нельзя. Не сохраняя счёт, мы делаем
		# самый дорогой протез в игре недостижимым для всех, кто хоть раз вышел —
		# то есть для всех.
		cfg.set_value(key, "trophies", child.trophies)
		# Отряд — нанятое за золото, а не «состояние боя». Сохраняем СОСТАВ:
		# кто мечник, кто лучник. Позиции не сохраняем и здесь — отряд стоит у
		# казармы, из которой его набирали.
		#
		# Отряд принадлежит ЧЕЛОВЕКУ, а не стороне, поэтому и лежит он в разделе
		# профиля, а не мира: сетевой id при следующем входе будет другой, и
		# восстанавливать бойцов надо в тот момент, когда новый id уже известен,
		# то есть при спавне персонажа.
		#
		# Призванных волков не сохраняем НАМЕРЕННО: у них свой короткий срок
		# жизни, они не переживают и одной сессии. Восстановленный волк был бы
		# не возвращённым имуществом, а выдумкой.
		var squad := PackedInt32Array()
		for unit in world.units_of(int(child.peer_id)):
			if not is_instance_valid(unit) or bool(unit.is_beast):
				continue
			squad.append(1 if bool(unit.is_archer) else 0)
		cfg.set_value(key, "squad", squad)
		cfg.set_value(key, "bandages", int(child.body.bandages))
		cfg.set_value(key, "in_wheelchair", bool(child.body.in_wheelchair))

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
	_restore_buildings(world, cfg)
	_restore_labourers(world, cfg)

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
		wallet.horses = int(cfg.get_value(key, "horses", wallet.horses))
		# А вот УВЕДЁННЫХ с обозом лошадей возвращаем в конюшню, а не
		# восстанавливаем счётчик: обозов после загрузки нет ни одного, и
		# «занятые» лошади остались бы занятыми навсегда — с караваном, которого
		# не существует.
		wallet.horses_out = 0

	_restored.clear()
	print("[сейв] мир загружен: %s" % path)
	loaded.emit(path)
	return true


## Поставить обратно всё, что было построено.
##
## Сносим ВСЁ, что стоит сейчас, и ставим заново по списку. Иначе загрузка
## посреди партии (через консоль) удваивала бы каждый дом, а казарма стражи,
## снесённая в прошлой партии, возвращалась бы из мировой генерации — и половина
## условия поражения стражи отменялась сама собой.
##
## `restored_buildings` нужен миру: увидев его, он НЕ ставит стартовую казарму
## сам. У старых сейвов раздела нет, флаг остаётся снятым, и мир ведёт себя
## по-прежнему.
var restored_buildings := false

func _restore_buildings(world: Node, cfg: ConfigFile) -> void:
	restored_buildings = cfg.has_section_key("world", "buildings")
	if not restored_buildings:
		return
	for node in world.get_tree().get_nodes_in_group("building"):
		if is_instance_valid(node):
			node.free()
	for entry in cfg.get_value("world", "buildings", []):
		var progress := float(entry.get("progress", 1.0))
		var node: Node = world.spawn_building(
			int(entry["kind"]), entry["point"], int(entry.get("owner", 0)),
			int(entry.get("faction", 0)), progress >= 1.0,
			float(entry.get("yaw", 0.0)))
		if node == null:
			continue
		node.progress = progress
		node.health = float(entry.get("health", node.health))


## Вернуть батраков — по стороне, ремеслу и базе.
##
## Стартовых двух батраков злодея мир ставит сам, если у стороны нет ни одного.
## Этот предохранитель мы НЕ отменяем, в отличие от стартовой казармы: сторона
## без батраков и без золота не может нанять батрака, чтобы добыть золото, и
## партия встаёт намертво. Пришедших из сейва он и так пропустит — они есть.
func _restore_labourers(world: Node, cfg: ConfigFile) -> void:
	if not cfg.has_section_key("world", "labourers"):
		return
	for node in world.get_tree().get_nodes_in_group("unit"):
		if is_instance_valid(node) and "sync_role" in node:
			node.free()
	var i := 0
	for entry in cfg.get_value("world", "labourers", []):
		var home: Vector3 = entry.get("home", Vector3.ZERO)
		# Раскладываем по кругу вокруг базы: вставшие в одну точку расталкивают
		# друг друга физикой и первые секунды после загрузки едут врассыпную.
		var angle: float = TAU * float(i) / 8.0
		i += 1
		var spot: Vector3 = home + Vector3(cos(angle) * 5.0, 0.5, sin(angle) * 5.0)
		world.spawn_labourer(int(entry.get("faction", 0)), spot, home,
			int(entry.get("role", 0)))


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
	return _faction_in(cfg, profile)


## Чем профиль играл в ЭТОМ файле. Отдельно от `saved_faction`, потому что меню
## перебирает чужие файлы, а не только текущий.
##
## ПОДСКАЗКА, а не приказ: навязывать эту сторону поверх выбора в меню нельзя —
## именно так выбор и перестал работать, игрок жал «эльфы», а садился злодеем.
static func _faction_in(cfg: ConfigFile, profile: String) -> int:
	var key := "player/" + profile
	if not cfg.has_section(key):
		return -1
	return int(cfg.get_value(key, "last_faction", cfg.get_value(key, "faction", -1)))


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
	var key := _player_key(profile, int(player.faction))
	if not cfg.has_section(key):
		# Запасной путь для старых сохранений: там слот был один на профиль, без
		# стороны в имени. Берём его, только если сторона совпадает, — иначе
		# эльфу достанется прогресс злодея.
		var legacy := "player/" + profile
		if cfg.has_section(legacy) \
				and int(cfg.get_value(legacy, "faction", -1)) == int(player.faction):
			key = legacy
		else:
			return false

	player.gear_tier = int(cfg.get_value(key, "gear_tier", 0))
	player.harness_size = int(cfg.get_value(key, "harness_size", player.harness_size))
	player.is_leader = bool(cfg.get_value(key, "is_leader", player.is_leader))
	player.orders_done = int(cfg.get_value(key, "orders_done", 0))
	player.final_threshold = int(cfg.get_value(key, "final_threshold", player.final_threshold))
	player.body.severed_mask = int(cfg.get_value(key, "severed_mask", 0))
	player.body.prosthetics = cfg.get_value(key, "prosthetics", player.body.prosthetics)
	player.body.eyes_lost = int(cfg.get_value(key, "eyes_lost", 0))
	player.body.eye_implants = int(cfg.get_value(key, "eye_implants", 0))
	player.trophies = cfg.get_value(key, "trophies", player.trophies)
	player.body.bandages = int(cfg.get_value(key, "bandages", player.body.bandages))
	player.body.in_wheelchair = bool(cfg.get_value(key, "in_wheelchair", false))

	_restore_squad(player, cfg.get_value(key, "squad", PackedInt32Array()))

	_restored[profile] = true
	print("[сейв] восстановлен профиль %s (сторона %s)" % [
		profile, FACTIONS.name_of(int(player.faction))
	])
	return true


## Вернуть нанятый отряд человеку, который только что вошёл.
##
## Здесь, а не в `load_world`: отряд привязан к сетевому id, а тот выдаётся
## заново при каждом подключении. В момент загрузки мира человека ещё нет и
## владельца бойцам назначить не из чего; в момент спавна — есть.
##
## Ставим у казармы, как при найме, и тем же разводом по спирали: спавн всех в
## одну точку вбивает капсулы друг в друга, и CharacterBody3D потом не может их
## расцепить. Казармы нет (снесли) — ставим у самого человека.
func _restore_squad(player: Node3D, kinds: PackedInt32Array) -> void:
	if kinds.is_empty():
		return
	var world: Node = get_parent()
	var peer := int(player.peer_id)
	# Второй раз не набираем: у вошедшего отряд уже может быть, если сюда
	# как-то дошли дважды, и удвоенное войско хуже потерянного.
	if not world.units_of(peer).is_empty():
		return
	var base: Vector3 = player.global_position
	var barracks: Node3D = world.barracks_of(int(player.faction), RES.Building.SWORD_BARRACKS)
	if barracks != null:
		base = barracks.global_position
	var count: int = mini(kinds.size(), RES.SQUAD_LIMIT)
	for i in count:
		var angle: float = float(i) * 0.9
		var radius: float = 3.0 + float(i) * 0.45
		var spot: Vector3 = base + Vector3(cos(angle) * radius, 1.0, 9.0 + sin(angle) * radius)
		world.spawn_unit(peer, i, spot, false, int(kinds[i]) == 1)
	print("[сейв] отряду возвращено бойцов: %d" % count)


## Ключ прогресса: профиль и сторона. Разные стороны — разные слоты, и это
## позволяет одному человеку вести злодея и эльфа в одном мире, не теряя ни
## того, ни другого.
func _player_key(profile: String, faction: int) -> String:
	return "player/%s/%d" % [profile, faction]


func has_save() -> bool:
	return FileAccess.file_exists(save_path())


## Коротко о том, что лежит в сейве, — для главного меню. Пустой словарь, если
## сохранения нет.
##
## Меню обязано показывать, ЧТО именно оно предлагает продолжить. «Продолжить»
## без единого слова о том, какая это партия и как давно она была, — это кнопка
## наугад: человек с двумя мирами и одним компьютером нажмёт её и потеряет
## понимание, куда попал.
func save_summary() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(save_path()) != OK:
		return {}
	return {
		"world": world_id,
		"at": String(cfg.get_value("meta", "saved_at", "")),
		"faction": saved_faction(Net.profile_id),
	}


## Все сохранённые миры, свежие первыми.
##
## Меню обязано показывать не только последнюю партию. Один файл на мир — это
## уже поддержка нескольких кампаний, и до сих пор она была видна только тому,
## кто знает про ключ `--world=ИМЯ`. Для всех остальных вторая партия означала
## потерю первой.
##
## Читаем каждый файл целиком: дата и сторона лежат внутри, а по имени файла о
## партии не сказать ничего — оно случайное.
func list_saves() -> Array:
	var found: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return found
	for file_name in dir.get_files():
		if not file_name.ends_with(".cfg"):
			continue
		var cfg := ConfigFile.new()
		if cfg.load("%s/%s" % [SAVE_DIR, file_name]) != OK:
			continue
		found.append({
			"world": file_name.get_basename(),
			"at": String(cfg.get_value("meta", "saved_at", "")),
			"faction": _faction_in(cfg, Net.profile_id),
		})
	# Свежие первыми. Дата лежит строкой вида «2026-08-29T14:34:21», и такие
	# строки сравниваются как даты — на то формат и выбран.
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["at"]) > String(b["at"]))
	return found


## Стереть сохранённую партию. Насовсем.
##
## Единственное необратимое действие во всём меню, и потому единственное, где
## файл действительно удаляется: «новая игра» и переход в другой мир ничего не
## трогают, они лишь меняют имя текущего. Здесь же после нажатия возврата нет.
##
## Мир, заданный ключом `--world=ИМЯ`, не стираем: под набором проверок это
## выдернуло бы файл, с которым он работает.
func delete_world(id: String) -> bool:
	if _frozen or _world_from_cmdline or id.is_empty():
		return false
	var path := "%s/%s.cfg" % [SAVE_DIR, id]
	if not FileAccess.file_exists(path):
		return false
	if DirAccess.remove_absolute(path) != OK:
		return false
	print("[сейв] партия %s стёрта" % id)
	# Стёрли ту, в которой были, — забываем и её имя: иначе следующий запуск
	# «продолжит» мир, которого нет, и молча начнёт пустой.
	if id == world_id:
		_restored.clear()
	return true


## Перейти в другой сохранённый мир: он становится текущим.
##
## Прежнее имя записываем рядом — тем же способом, что при новой игре. Ничего не
## стирается: миров на диске сколько было, столько и осталось.
func adopt_world(id: String) -> bool:
	if _frozen or _world_from_cmdline or id.is_empty() or id == world_id:
		return false
	var cfg := ConfigFile.new()
	cfg.load(WORLD_ID_PATH)
	cfg.set_value("world", "previous", world_id)
	cfg.set_value("world", "id", id)
	cfg.save(WORLD_ID_PATH)
	world_id = id
	_restored.clear()
	_autosave_t = 0.0
	print("[сейв] переходим в мир %s" % world_id)
	return true


## Начать НОВУЮ партию.
##
## Не стираем старую, а заводим новый идентификатор мира: файлы лежат по одному
## на мир, и «новая игра» — это новое имя, а не пустой файл. Старая партия
## остаётся на диске целой, и промах мимо кнопки не стоит человеку кампании;
## вернуться к ней можно ключом `--world=ИМЯ`, а прежнее имя мы для этого и
## записываем рядом.
##
## Возвращает имя нового мира.
func begin_new_world() -> String:
	if _frozen or _world_from_cmdline:
		return world_id
	var cfg := ConfigFile.new()
	cfg.load(WORLD_ID_PATH)
	cfg.set_value("world", "previous", world_id)
	world_id = _mint_world_id(cfg)
	_restored.clear()
	_autosave_t = 0.0
	print("[сейв] новая партия, мир %s (прежний %s остался на диске)"
		% [world_id, cfg.get_value("world", "previous", "—")])
	return world_id


# --- идентификатор мира ----------------------------------------------------

## Мир хозяина. Заводится один раз и живёт в user://, поэтому «мир первого
## хоста» остаётся тем же самым миром между запусками игры.
func _load_or_make_world_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(WORLD_ID_PATH) == OK:
		var saved_id := String(cfg.get_value("world", "id", ""))
		if not saved_id.is_empty():
			return saved_id
	return _mint_world_id(cfg)


## Завести имя нового мира и записать его как текущее.
func _mint_world_id(cfg: ConfigFile) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fresh := "w%08x" % rng.randi()
	cfg.set_value("world", "id", fresh)
	cfg.save(WORLD_ID_PATH)
	return fresh
