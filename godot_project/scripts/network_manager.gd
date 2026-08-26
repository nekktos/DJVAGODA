extends Node
##
## Сетевой менеджер (автолоад "Net"). Этап 0 — сетевой фундамент.
##
## Два транспорта поверх одного и того же Godot High-Level Multiplayer API:
##   ENET  — прямой IP, работает локально и в локальной сети. Режим по умолчанию.
##   STEAM — P2P через Steam-релей (GodotSteam), проходит NAT без проброса порта.
##
## Отличие не только в классе пира: ENet адресуется по IP, Steam — по Steam ID
## хоста. Матчмейкинга и лобби нет, второй игрок вводит Steam ID вручную — это
## отдельная задача на будущее (GDD, раздел 9).
##
## Авторитетность (решение принято на Этапе 0):
##   - Движение персонажа — клиент-авторитет: каждый пир управляет только своим
##     CharacterBody3D и реплицирует его трансформ остальным.
##   - Всё остальное (урон, ресурсы, стройка, караван) на последующих этапах
##     будет считаться ХОСТОМ. Движение написано через apply_input(), чтобы
##     переезд на host-авторитет позже был локальной правкой, а не переписыванием.
##

enum Transport { ENET, STEAM }

const FACTIONS := preload("res://scripts/factions.gd")

const DEFAULT_PORT := 24545
## Вместимость сессии складывается из слотов сторон (FACTIONS.SLOTS): злодей
## один, у эльфов и стражи по пять. Клиентов, соответственно, на одного меньше.
## Свободные слоты позже займёт ИИ (задача следующих этапов).
static func max_clients() -> int:
	return FACTIONS.total_slots() - 1

## Тестовый AppID Valve (Spacewar). Свой понадобится только к релизу в Steam.
const DEV_APP_ID := 480

## Сколько ждать ответа хоста. Ни ENet, ни Steam при отказе (сессия заполнена,
## хост не запущен, неверный Steam ID) сигнала не присылают — без таймаута
## клиент висит вечно.
const CONNECT_TIMEOUT := 8.0

## Человекочитаемый статус для меню/лога.
signal status_changed(text: String)
## Сессия поднялась и готова: хост создал сервер, либо клиент подключился.
signal session_started
## Сессия завершена (выход, разрыв, ошибка подключения).
signal session_ended

var transport: Transport = Transport.ENET
var is_host := false
var active := false
## Сторона, выбранная в меню до подключения. Хост проверит, свободна ли она.
var chosen_faction := 0

## Устойчивый идентификатор ИГРОКА, а не подключения.
##
## ПОЧЕМУ СВОЙ ПРОФИЛЬ, А НЕ STEAM ID. Steam-транспорт в проекте необязателен —
## локальная игра по прямому IP остаётся основным режимом (GDD раздел 0). Если
## привязать сохранения к Steam ID, то у игры без Steam сохранений не будет
## вовсе, а с ним пришлось бы держать две разные схемы идентификации. Свой
## профиль работает одинаково в обоих транспортах, а Steam ID при желании
## всегда можно положить в него как значение.
##
## Файл лежит в user:// — это папка данных пользователя, она переживает
## переустановку игры и не попадает в репозиторий.
##
## ЧЕСТНО ПРО ЗАЩИТУ: клиент присылает свой профиль сам, значит может прислать
## чужой и забрать чужой прогресс. Для игры на своих это приемлемо; настоящая
## защита требует аккаунтов и сервера, а их в проекте нет и не планируется
## (GDD раздел 9 прошлой версии — матчмейкинг отдельная тема).
const PROFILE_PATH := "user://profile.cfg"

var profile_id := ""

var _connect_timeout_left := 0.0
var _steam_ready := false


func _ready() -> void:
	_load_profile()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if _steam_ready:
		_steam().call("run_callbacks")

	if _connect_timeout_left <= 0.0:
		return
	_connect_timeout_left -= delta
	if _connect_timeout_left <= 0.0:
		_fail("Хост не ответил за %d с. Он запущен? Сессия не заполнена?" % int(CONNECT_TIMEOUT))
		leave()


## Поднять хост. Возвращает true, если сокет удалось открыть.
func host_game(port: int = DEFAULT_PORT) -> bool:
	if active:
		leave()

	var peer: MultiplayerPeer
	if transport == Transport.STEAM:
		if not _ensure_steam():
			return false
		peer = ClassDB.instantiate("SteamMultiplayerPeer")
		var serr: int = peer.call("create_host", 0)
		if serr != OK:
			_fail("Steam не смог создать хост (код %d)." % serr)
			return false
	else:
		var enet := ENetMultiplayerPeer.new()
		var err := enet.create_server(port, max_clients())
		if err != OK:
			_fail("Не удалось открыть порт %d (код %d). Порт занят другим процессом?" % [port, err])
			return false
		peer = enet

	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	if transport == Transport.STEAM:
		status_changed.emit("Хост поднят через Steam. Твой Steam ID для друга: %d" % local_steam_id())
	else:
		status_changed.emit("Хост запущен на порту %d. Ждём игроков…" % port)
	session_started.emit()
	return true


## Подключиться к хосту. Для ENET address — это IP, для STEAM — Steam ID хоста.
## true — попытка начата (не факт успеха, ждём сигнала или таймаута).
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if active:
		leave()
	var addr := address.strip_edges()
	if addr.is_empty():
		_fail("Пустой адрес хоста.")
		return false

	var peer: MultiplayerPeer
	var human_target := ""
	if transport == Transport.STEAM:
		if not _ensure_steam():
			return false
		if not addr.is_valid_int():
			_fail("Steam ID должен быть числом, а получено «%s»." % addr)
			return false
		peer = ClassDB.instantiate("SteamMultiplayerPeer")
		var serr: int = peer.call("create_client", addr.to_int(), 0)
		if serr != OK:
			_fail("Steam не смог начать подключение к %s (код %d)." % [addr, serr])
			return false
		human_target = "Steam ID %s" % addr
	else:
		var enet := ENetMultiplayerPeer.new()
		var err := enet.create_client(addr, port)
		if err != OK:
			_fail("Не удалось начать подключение к %s:%d (код %d)." % [addr, port, err])
			return false
		peer = enet
		human_target = "%s:%d" % [addr, port]

	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	_connect_timeout_left = CONNECT_TIMEOUT
	status_changed.emit("Подключаемся к %s…" % human_target)
	return true


## Закрыть сессию и вернуться в оффлайн-состояние.
func leave() -> void:
	_connect_timeout_left = 0.0
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if active:
		active = false
		is_host = false
		session_ended.emit()
	else:
		is_host = false


## Список подключённых пиров, не считая себя.
func peer_count() -> int:
	if not active:
		return 0
	return multiplayer.get_peers().size()


func local_id() -> int:
	if not active or multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


## Доступен ли Steam-транспорт: аддон GodotSteam загружен и класс пира есть.
func steam_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


func local_steam_id() -> int:
	if not _steam_ready:
		return 0
	return int(_steam().call("getSteamID"))


## Синглтон Steam берём через Engine, а не по имени: если аддона в проекте нет,
## прямая ссылка на Steam стала бы ошибкой парсинга и уронила бы весь проект,
## включая локальную игру.
func _steam() -> Object:
	return Engine.get_singleton("Steam")


func _ensure_steam() -> bool:
	if _steam_ready:
		return true
	if not steam_available():
		_fail("Аддон GodotSteam не загружен — Steam-транспорт недоступен, играй по IP.")
		return false
	var res: Variant = _steam().call("steamInitEx", DEV_APP_ID, false)
	var status := int(res.get("status", -1)) if res is Dictionary else -1
	if status != 0:
		var verbal: String = str(res.get("verbal", "")) if res is Dictionary else ""
		_fail("Steam не инициализировался (код %d). %s Steam запущен?" % [status, verbal])
		return false
	_steam_ready = true
	return true


func _fail(text: String) -> void:
	push_warning(text)
	status_changed.emit(text)


func _on_peer_connected(id: int) -> void:
	# Steam-хост, в отличие от ENet, не умеет ограничивать число клиентов сам,
	# поэтому лимит держим здесь — для обоих транспортов одинаково.
	if multiplayer.is_server() and multiplayer.get_peers().size() > max_clients():
		status_changed.emit("Игрок %d отклонён: сессия заполнена." % id)
		if multiplayer.multiplayer_peer.has_method("disconnect_peer"):
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	status_changed.emit("Игрок %d подключился." % id)


func _on_peer_disconnected(id: int) -> void:
	status_changed.emit("Игрок %d отключился." % id)


func _on_connected_to_server() -> void:
	_connect_timeout_left = 0.0
	status_changed.emit("Подключение установлено. Ваш id — %d." % multiplayer.get_unique_id())
	session_started.emit()


func _on_connection_failed() -> void:
	_fail("Подключиться не удалось: хост не отвечает.")
	leave()


func _on_server_disconnected() -> void:
	# Штатное завершение, а не ошибка — в лог движка не пишем.
	status_changed.emit("Хост закрыл сессию.")
	leave()


## Прочитать профиль, а если его нет — завести. Делается один раз при запуске.
##
## Ключ --profile=ИМЯ подменяет профиль, не трогая файл. Он нужен не для читов,
## а по необходимости: два окна на одной машине делят папку user://, значит и
## файл профиля, значит без подмены оба игрока считались бы ОДНИМ человеком и
## тянули бы друг у друга сохранённый прогресс. Так же он нужен автопроверкам.
func _load_profile() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--profile="):
			profile_id = arg.substr("--profile=".length())
			if not profile_id.is_empty():
				print("[профиль] задан ключом: %s" % profile_id)
				return
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		profile_id = String(cfg.get_value("profile", "id", ""))
	if profile_id.is_empty():
		profile_id = _new_profile_id()
		cfg.set_value("profile", "id", profile_id)
		cfg.set_value("profile", "created", Time.get_datetime_string_from_system())
		cfg.save(PROFILE_PATH)
		print("[профиль] создан новый: %s" % profile_id)
	else:
		print("[профиль] %s" % profile_id)


## Случайный идентификатор. Не UUID по стандарту — достаточно того, что он
## уникален на практике и читается глазами в файле сохранения.
func _new_profile_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "p%08x%08x" % [rng.randi(), rng.randi()]


## Мы хост ПРЯМО СЕЙЧАС, с живым сетевым пиром.
##
## Отличается от multiplayer.is_server() тем, что не ругается в лог, когда пира
## нет вовсе. А нет его в двух совершенно обычных случаях: до подключения (сцена
## мира живёт с самого старта) и после разрыва сессии.
##
## Без этой проверки каждый кадр в лог падала строка «No multiplayer peer is
## assigned» — в одном прогоне автопроверки набралось 3794 штуки, и они
## маскировали настоящие ошибки.
func hosting() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


## Симметричная проверка для клиентских веток.
func joined() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.is_server()
