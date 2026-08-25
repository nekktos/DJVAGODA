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

const DEFAULT_PORT := 24545
## В сессии от 1 до 3 игроков, значит клиентов помимо хоста — максимум два.
## Свободные фракции ведёт ИИ (задача следующих этапов).
const MAX_CLIENTS := 2

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

var _connect_timeout_left := 0.0
var _steam_ready := false


func _ready() -> void:
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
		var err := enet.create_server(port, MAX_CLIENTS)
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
	if multiplayer.is_server() and multiplayer.get_peers().size() > MAX_CLIENTS:
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
