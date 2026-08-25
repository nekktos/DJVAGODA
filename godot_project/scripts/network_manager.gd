extends Node
##
## Сетевой менеджер (автолоад "Net"). Этап 0 — сетевой фундамент.
##
## Модель: P2P через Godot High-Level Multiplayer API (ENet).
## Один клиент — хост (peer id 1), второй подключается к нему по IP.
## Выделенного сервера и матчмейкинга нет — это отдельная задача на будущее
## (GDD, раздел 9).
##
## Авторитетность (решение принято на Этапе 0):
##   - Движение персонажа — клиент-авторитет: каждый пир управляет только своим
##     CharacterBody3D и реплицирует его трансформ остальным.
##   - Всё остальное (урон, ресурсы, стройка, караван) на последующих этапах
##     будет считаться ХОСТОМ. Движение написано через apply_input(), чтобы
##     переезд на host-авторитет позже был локальной правкой, а не переписыванием.
##

const DEFAULT_PORT := 24545
## В сессии от 1 до 3 игроков, значит клиентов помимо хоста — максимум два.
## Свободные фракции ведёт ИИ (задача следующих этапов).
const MAX_CLIENTS := 2

## Сколько ждать ответа хоста. ENet при отказе (сессия заполнена, хост не
## запущен) сигнала не присылает вообще — без таймаута клиент висит вечно.
const CONNECT_TIMEOUT := 8.0

## Человекочитаемый статус для меню/лога.
signal status_changed(text: String)
## Сессия поднялась и готова: хост создал сервер, либо клиент подключился.
signal session_started
## Сессия завершена (выход, разрыв, ошибка подключения).
signal session_ended

var is_host := false
var active := false
var _connect_timeout_left := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
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
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		_fail("Не удалось открыть порт %d (код %d). Порт занят другим процессом?" % [port, err])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	status_changed.emit("Хост запущен на порту %d. Ждём второго игрока…" % port)
	session_started.emit()
	return true


## Подключиться к хосту. true — попытка начата (не факт успеха, ждём сигнала).
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if active:
		leave()
	var addr := address.strip_edges()
	if addr.is_empty():
		_fail("Пустой адрес хоста.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, port)
	if err != OK:
		_fail("Не удалось начать подключение к %s:%d (код %d)." % [addr, port, err])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	_connect_timeout_left = CONNECT_TIMEOUT
	status_changed.emit("Подключаемся к %s:%d…" % [addr, port])
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


func _fail(text: String) -> void:
	push_warning(text)
	status_changed.emit(text)


func _on_peer_connected(id: int) -> void:
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
