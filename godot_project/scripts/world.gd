extends Node3D
##
## Мир: grey-box карта из 4 зон, спавн игроков и переключение камеры.
##
## Геометрия карты строится процедурно (world_builder.gd) с фиксированным сидом,
## одинаково на всех пирах, поэтому по сети она НЕ реплицируется — только
## персонажи, через MultiplayerSpawner.
##
## Порядок спавна намеренно построен так, чтобы World уже был в дереве у обоих
## пиров ДО установления соединения (World — часть главной сцены, а не
## подгружается после коннекта). Иначе MultiplayerSpawner на клиенте не успевает
## появиться к моменту, когда хост присылает команду спавна.
##

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
## То же и для строителя карты: обращаться к нему по class_name нельзя, кэш
## глобальных классов строится только редактором и на свежем клоне его нет.
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")
const CORPSE_SCENE := preload("res://scenes/Corpse.tscn")
const BUILDING_SCENE := preload("res://scenes/Building.tscn")
const CARAVAN_SCENE := preload("res://scenes/Caravan.tscn")
const LOOT_SCENE := preload("res://scenes/Loot.tscn")
const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const LABOURER_SCENE := preload("res://scenes/Labourer.tscn")
const LIMB_SCENE := preload("res://scenes/SeveredLimb.tscn")
const LABOURER := preload("res://scripts/units/labourer.gd")

## Сколько батраков у злодея в начале партии.
## Батраков на старте у злодея нет вовсе (GDD 9a): их нанимают на золото с
## микро-шахты. Раньше их было двое — и партия начиналась с работающего
## хозяйства, которое злодей не строил.
const STARTING_LABOURERS := 0
const RES := preload("res://scripts/economy/resources.gd")
const PROGRESS := preload("res://scripts/progression.gd")
const FACTIONS := preload("res://scripts/factions.gd")

## Казарма стражи стоит во дворце с начала партии: по GDD раздел 2.2 во дворце
## «уже есть и ресурсы, и здания». Без неё условие поражения стражи («казарма
## снесена И командир убит») было бы неопределимым — сносить нечего.
const GUARD_BARRACKS_POS := Vector3(332.0, 6.0, -238.0)

## Обжитое хозяйство стражи на плато (GDD 9a): «у людей со старта есть все
## постройки, фермы, поля с пшеницей, ангары». Ангары — это склады. Всё стоит
## внутри дворцовых стен и достроено сразу.
##
## Злодей и стража — ЗЕРКАЛЬНЫЕ стороны, и разница между ними не в том, что им
## доступно, а в том, с чего они начинают. Злодей строит всё это сам из
## разрушенного форта; страже оно досталось, и ей для стратегии нужно другое —
## пройти цепочку приказов командира.
const GUARD_ESTATE := [
	[RES.Building.STORAGE, Vector3(340.0, 6.0, -200.0)],
	[RES.Building.FARM, Vector3(220.0, 6.0, -210.0)],
	[RES.Building.FARM, Vector3(220.0, 6.0, -250.0)],
	[RES.Building.HOUSE, Vector3(380.0, 6.0, -240.0)],
	[RES.Building.STABLE, Vector3(380.0, 6.0, -200.0)],
]

## На каком расстоянии от своего склада ресурсы «при себе» перекладываются в
## него сами. Отдельной кнопки нет намеренно: вклад должен быть очевидным
## следствием возвращения на базу, а не ещё одним действием, которое забывают.
const DEPOSIT_RANGE := 14.0
## Как часто хост проверяет, не стоит ли кто у своего склада.
const DEPOSIT_INTERVAL := 1.0

## Через сколько секунд после смерти игрок возвращается в мир.
## Временное правило (DESIGN_ANSWERS.md, пункт 10) — настоящие условия
## респавна решаются вместе с кампаниями.
const RESPAWN_DELAY := 5.0
## Сколько трупов держим в мире. GDD требует, чтобы труп не исчезал мгновенно,
## но копить их без предела нельзя.
const CORPSE_LIMIT := 30
## На каком расстоянии от верстака им можно пользоваться. Проверяет ХОСТ:
## иначе клиент выдавал бы себе протезы из любой точки карты.
const WORKBENCH_RANGE := 7.0
## То же для лавки торговца.
const TRADER_RANGE := 7.0

## Дебаг-ключ --netlog: раз в секунду печатать позиции всех персонажей — видно,
## доезжает ли чужое движение до этого пира.
const DEBUG_LOG_INTERVAL := 1.0

## Сменился режим камеры: true — стратегическая, false — экшен.
signal camera_mode_changed(strategy: bool)

@onready var _players: Node3D = $Players
@onready var _menu_camera: Camera3D = $MenuCamera
@onready var _strategy_camera: Camera3D = $StrategyCamera
@onready var _terrain: Node3D = $Terrain
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _spawned: Node3D = $Spawned
@onready var _world_spawner: MultiplayerSpawner = $WorldSpawner
@onready var build_controller: Node3D = $BuildController
@onready var route_controller: Node3D = $RouteController
## Железная шахта. Отдельной ссылкой, потому что к ней ведёт обучение и за ней
## ходят проверки; все три — в `mines`.
@onready var mine: Node3D = $Mine
## Все шахты, в порядке `WORLD_BUILDER.MINES`: железо, камень, уголь, золото
## (GDD 9a).
@onready var mines: Array[Node3D] = [$Mine, $MineStone, $MineCoal, $MineGold]
@onready var objective: Node3D = $Objective
@onready var forest: Node3D = $Forest
@onready var commander: Node3D = $Commander
## Старейшина эльфов (задания). Узел заводим кодом: в сцене его нет.
var elder: Node3D = null
const ELDER := preload("res://scripts/elder.gd")
@onready var treasury: Node = $Treasury
@onready var savegame: Node = $Save
@onready var garrison: Node = $Garrison
## ÐÐ ÑÐ²Ð¾Ð±Ð¾Ð´Ð½ÑÑ ÑÑÐ¾ÑÐ¾Ð½, ÑÑÑÐ¿ÐµÐ½Ñ Â«Ð±Â»: ÐºÑÐ¾ Ð¸ ÐºÑÐ´Ð° ÑÐ¾Ð´Ð¸Ñ Ð²Ð¾ÐµÐ²Ð°ÑÑ.
@onready var warband: Node = $Warband
## Пути по карте. Печёт сетку после стройки, считает только у хоста.
@onready var navigation: Node = $Navigation
## Хозяйство свободных сторон, ступень «в»: наём, стройка, войско.
@onready var steward: Node = $Steward

var strategy_mode := false

var _netlog := false
## Сквозной номер для снарядов и трупов: имя ноды должно совпадать на всех
## пирах, иначе команда на удаление уедет не по тому пути.
var _spawn_counter := 0
var _corpses: Array[Node] = []
var _netlog_t := 0.0
var _deposit_t := 0.0
var _hunger_t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_netlog = args.has("--netlog")
	# Кастомная spawn_function: даёт положить в пакет спавна произвольные данные
	# (сейчас — номер слота, позже сюда же ляжет фракция).
	_spawner.spawn_function = _make_player
	_world_spawner.spawn_function = _make_spawned
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	Net.session_ending.connect(_on_session_ending)

	var builder := WORLD_BUILDER.new()
	builder.build(_terrain)
	# Лес зоны эльфов строит отдельная система: у него impostor-LOD и своя
	# адресация деревьев по индексу (GDD раздел 5, forest.gd).
	#
	# Строим его ДО выпечки сетки. Раньше было наоборот, и сетка о деревьях не
	# знала вовсе: путь шёл сквозь лес, бойцы упирались в стволы, а отряд эльфов
	# не мог выйти из собственного леса ни разу за прогон.
	forest.build(
		WORLD_BUILDER.ZONE_CENTERS[WORLD_BUILDER.Zone.ELVES],
		WORLD_BUILDER.ZONE_HALF - 30.0,
		70.0,
		3615,
		_mine_clearings(),
	)
	# Стволы для выпечки ставим временно: живые деревья появляются по мере
	# надобности, а сетке нужны все и сразу.
	var trunks: Node3D = forest.bake_obstacles(_terrain)
	navigation.bake(_terrain)
	trunks.queue_free()
	build_controller.place_requested.connect(_on_place_requested)
	route_controller.route_sent.connect(_on_route_sent)
	_place_mines()
	elder = ELDER.new()
	elder.name = "Elder"
	add_child(elder)
	# Мир построен, но НЕ запущен. Пока человек в меню, он не играет, и мир
	# играть за него не должен: см. `_set_running`.
	_set_running(false)


## Идёт ли жизнь в мире.
##
## Мир лежит в главной сцене с самого старта — так решено с Этапа 0, и это
## правильно: подгружать его после коннекта значит держать два разных состояния
## сцены на двух пирах. Но «лежит» молча превратилось в «живёт»: пока человек
## читал меню, шахта копила запас, отношения фракций дрейфовали, ИИ нанимал
## батраков и строил дома, а объявление победы могло случиться до того, как
## кто-нибудь вообще нажал кнопку.
##
## Партия обязана начинаться с начала, а не с того места, до которого мир дошёл
## сам, пока его никто не видел. Отсюда: без сессии узел World не тикает вовсе.
##
## Останавливаем ПОДДЕРЕВО целиком, а не каждую систему по отдельности. Иначе
## список «кого ещё надо остановить» пришлось бы дописывать при каждой новой
## системе, а забытая строка проявилась бы через полгода как «почему-то в новой
## партии у эльфов уже мир со стражей».
##
## Рисование это не трогает: камера меню показывает мир по-прежнему, просто он
## стоит. Сигналы тоже доходят — иначе `_on_session_started` не разбудил бы его.
func _set_running(on: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	# Живой фон — часть партии, а не программы: в меню лесу шуметь незачем.
	Ambience.set_running(on)


func _process(delta: float) -> void:
	_tick_deposit(delta)
	_tick_hunger(delta)
	if not _netlog or not Net.active:
		return
	_netlog_t += delta
	if _netlog_t < DEBUG_LOG_INTERVAL:
		return
	_netlog_t = 0.0
	var parts := PackedStringArray()
	for child in _players.get_children():
		var p: Vector3 = child.global_position
		parts.append("%s%s(%.1f, %.1f, %.1f)" % [
			child.name, "*" if child.is_multiplayer_authority() else "", p.x, p.y, p.z
		])
	print("[world] id=%d | %s" % [Net.local_id(), " ".join(parts)])


## Вклад: стоящий у своего достроенного склада перекладывает в него всё, что
## нёс при себе. Считает ТОЛЬКО хост — он же владеет казной.
##
## Отдельной кнопки нет намеренно: вклад должен быть очевидным следствием
## возвращения на базу, а не ещё одним действием, которое забывают нажать.
## Кормёжка артели. Раз в FEED_INTERVAL каждый батрак съедает свою долю еды из
## казны СВОЕЙ СТОРОНЫ.
##
## СТОРОНАМИ, А НЕ ПОШТУЧНО: еда лежит в общей казне, и списывать её батрак за
## батраком значило бы кормить первых и морить последних в случайном порядке.
## Считаем нужное на всю артель разом; не хватило на всех — не ест никто, и
## сторона узнаёт об этом одной внятной строкой, а не восемью.
##
## ПРЕДОХРАНИТЕЛЬ. Смерть от голода наступает с ТРЕТЬЕГО пропуска, то есть через
## пятнадцать минут громких предупреждений. Игрок, ушедший воевать, не должен
## вернуться на пепелище только потому, что играл в другую часть игры.
func _tick_hunger(delta: float) -> void:
	if not Net.hosting():
		return
	_hunger_t += delta
	if _hunger_t < RES.FEED_INTERVAL:
		return
	_hunger_t = 0.0

	for faction in FACTIONS.COUNT:
		var crew: Array = labourers_of(faction)
		if crew.is_empty():
			continue
		var wallet: Node = treasury.of(faction)
		if wallet == null:
			continue
		var need := RES.empty()
		need[RES.Kind.FOOD] = crew.size() * RES.FEED_PER_WORKER
		if wallet.spend(need):
			for worker in crew:
				worker.sync_hunger = 0
			continue

		var starved := 0
		for worker in crew:
			worker.sync_hunger += 1
			if worker.sync_hunger >= RES.HUNGER_FATAL:
				starved += 1
				worker.die_of_hunger()
		var left: Array = labourers_of(faction)
		var text := "ГОЛОД: %s — нечем кормить артель (%d ртов, надо %d еды)" % [
			FACTIONS.name_of(faction), crew.size(), need[RES.Kind.FOOD]]
		if starved > 0:
			text += ". Умерло от голода: %d" % starved
		print("[голод] %s, осталось %d" % [text, left.size()])
		if objective != null:
			# Объявлением, а не строкой в логе: свою артель игрок обязан
			# услышать. Чужой голод он и так не увидит — у каждой стороны
			# объявление своё, а в логе мир пишет всё.
			objective.log_event(text)


func _tick_deposit(delta: float) -> void:
	if not Net.hosting():
		return
	_deposit_t += delta
	if _deposit_t < DEPOSIT_INTERVAL:
		return
	_deposit_t = 0.0

	for child in _players.get_children():
		if not ("faction" in child) or not child.health.alive:
			continue
		if child.stock.carried_total() <= 0:
			continue
		var storage := storage_of(int(child.faction))
		if storage == null:
			continue
		if child.global_position.distance_to(storage.global_position) > DEPOSIT_RANGE:
			continue
		var moved: int = child.stock.deposit()
		if moved > 0:
			print("[склад] игрок %d сложил %d единиц" % [int(child.peer_id), moved])
			# Свою добычу игрок несёт сам — и опыт за неё его, а не вожака.
			child.award_xp_for_resources(moved)


# --- камера ----------------------------------------------------------------

## Свой персонаж на этом пире. null, если ещё не заспавнен.
func local_player() -> Node3D:
	if not Net.active:
		return null
	return _players.get_node_or_null(str(multiplayer.get_unique_id()))


## Стратегический режим есть у вожаков: у злодея по рождению, у командира
## стражи по повышению (GDD раздел 2.2).
##
## Погибший вожак не возрождается и остаётся НАБЛЮДАТЕЛЕМ: камера у него
## остаётся, чтобы он мог досмотреть партию, а управлять уже нечем.
func toggle_camera_mode() -> void:
	var player := local_player()
	if player != null and not player.has_strategy() and not is_spectating():
		return
	set_strategy_mode(not strategy_mode)


## Игрок стал наблюдателем: его вожак пал окончательно и не вернётся.
func is_spectating() -> bool:
	var player := local_player()
	return player != null and player.is_leader and not player.health.alive


func set_strategy_mode(on: bool, height: float = -1.0) -> void:
	var player := local_player()
	if player == null:
		return
	if on == strategy_mode:
		return
	strategy_mode = on
	# Персонаж продолжает симулироваться и реплицироваться в обоих режимах,
	# но в стратегическом не принимает управление: он стоит и уязвим.
	# Мёртвый вожак управления не получает никогда — он наблюдатель.
	player.control_enabled = not on and player.health.alive
	if not on:
		build_controller.set_active(false)
	if on:
		if height > 0.0:
			_strategy_camera.activate(player.global_position, height)
		else:
			_strategy_camera.activate(player.global_position)
	else:
		_strategy_camera.deactivate()
		player.set_view_active(true)
	camera_mode_changed.emit(on)


func strategy_height() -> float:
	return _strategy_camera.height()


# --- сессия и спавн --------------------------------------------------------

func _on_session_started() -> void:
	# Будим мир ПЕРВЫМ делом: всё, что ниже, ставит в него людей и постройки.
	_set_running(true)
	if Net.hosting():
		# Мир поднимаем ДО игроков: восстановленная казна и репутация должны
		# существовать к моменту, когда первый персонаж встанет в мир.
		savegame.load_world()
		# Если сейв вернул постройки, стартовую казарму он вернул тоже — или
		# не вернул, потому что её снесли. Ставить её здесь заново значит
		# отменять снос, а это половина условия поражения стражи.
		if not savegame.restored_buildings:
			_spawn_guard_barracks()
			_spawn_elf_houses()
		_spawn_starting_labourers()
		_spawn_player(1, Net.chosen_faction, Net.profile_id)
	else:
		# Клиент сам просит хоста о спавне — к этому моменту его World точно
		# готов принять реплицированную ноду.
		_request_spawn.rpc_id(1, Net.chosen_faction, Net.profile_id)


## Стереть партию из ПАМЯТИ — под новую игру.
##
## Нового файла мира мало. Выйдя в меню и нажав «Новая игра», человек остаётся
## в том же запущенном процессе: дома, батраки, казна, отношения и объявленная
## победа никуда не делись и уехали бы в новый мир целиком. «Новая игра»,
## которая начинается с чужой отстроенной базой, — это не новая игра, а обман, и
## заметить его можно только сыграв дважды подряд, не выходя из программы.
##
## Что сносим: всё, что порождено спавнером (дома, батраки, отряды, обозы,
## лошади, трупы, кучи), и всё накопленное состояние трёх узлов-хранителей.
## Чего НЕ трогаем: ландшафт, лес и дворец — они у мира постоянные.
func reset_for_new_game() -> void:
	for child in _spawned.get_children():
		child.free()
	_corpses.clear()
	_spawn_counter = 0
	treasury.reset()
	objective.reset()
	# Шахта копит сама и с потолком, но начинать новую партию с чужой полной
	# шахтой — это подарок в 300 единиц на ровном месте.
	for each in mines:
		each.stored = RES.empty()
	print("[мир] состояние прошлой партии стёрто, начинаем с чистого")


## Два батрака злодея на старте партии.
##
## Именно два, и это не круглое число ради круглого: батрак стоит золота, а
## золото добывают батраки. С нуля петля не запускается вовсе, с одним — тянется
## томительно долго. Двое дают выбор с первой минуты: оба на лес, оба в шахту
## или один туда, другой сюда.
##
## Сторона, а не игрок: батраки принадлежат злодею как СТОРОНЕ и существуют,
## даже если за неё ещё никто не сел. Иначе ИИ, добывающий «как игрок», начинал
## бы партию с пустыми руками.
func _spawn_starting_labourers() -> void:
	if STARTING_LABOURERS <= 0:
		return
	if not labourers_of(FACTIONS.Kind.VILLAIN).is_empty():
		return
	var base: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]
	for i in STARTING_LABOURERS:
		var angle := TAU * float(i) / float(STARTING_LABOURERS)
		var spot := base + Vector3(cos(angle) * 5.0, 0.5, sin(angle) * 5.0)
		spawn_labourer(FACTIONS.Kind.VILLAIN, spot, base, LABOURER.Role.LUMBERJACK)


## Казарма стражи во дворце. Ставится один раз на старте сессии и принадлежит
## СТОРОНЕ, а не игроку: она переживает уход любого конкретного стражника.
## Стартовые дома эльфов: три в кольце поселения, где стояли хижины. Два места
## под пятерых — строить сверх этого эльфы начинают сами.
const ELF_HOUSES_START := [
	Vector3(-255.0, 0.0, -300.0),
	Vector3(-340.4, 0.0, -280.3),
	Vector3(-310.0, 0.0, -343.9),
]


func _spawn_elf_houses() -> void:
	for point in ELF_HOUSES_START:
		spawn_building(RES.Building.ELF_HOUSE, point, 0, FACTIONS.Kind.ELVES, true)


## Дома эльфов: все (стоящие и строящиеся) или только достроенные.
func elf_houses(done_only := false) -> Array:
	var found := []
	for node in get_tree().get_nodes_in_group("building"):
		if not ("kind" in node) or not (int(node.kind) in RES.ELF_HOUSES):
			continue
		if int(node.faction) != FACTIONS.Kind.ELVES:
			continue
		if done_only and float(node.progress) < 1.0:
			continue
		found.append(node)
	return found


## Сколько домов могут держать эльфы: пять на своего игрока (не меньше, чем
## на одного — за пустую сторону держит ИИ).
func elf_house_limit() -> int:
	return RES.ELF_HOUSES_PER_PLAYER * maxi(1, players_of(FACTIONS.Kind.ELVES).size())


## Где возрождается эльф: у ближайшего ДОСТРОЕННОГО дома. Нет домов — нигде.
func elf_respawn_point(near: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	for house in elf_houses(true):
		var d: float = near.distance_to(house.global_position)
		if d < best_distance:
			best_distance = d
			best = house.global_position
	if best == Vector3.INF:
		return best
	# Рядом с домом, а не в нём: дом стоит на сваях, и под ним — коробка. С
	# СЕВЕРНОЙ стороны: персонаж встаёт лицом на север (-Z), и с южной он
	# смотрел бы в стену своего же дома — первый рывок упирался в неё.
	return best + Vector3(0.0, 1.0, -(RES.BUILDING_SIZE[RES.Building.ELF_HOUSE].z * 0.5 + 3.0))


## Живые эльфы: игроки, их ИИ-вожак и бойцы.
func living_elves() -> int:
	var count := 0
	# `characters_of`, а не `players_of`: ИИ-вожак эльфов игроком не
	# считается, но он живой эльф, и пока он жив, сторона не выбыла.
	for player in characters_of(FACTIONS.Kind.ELVES):
		if player.health.alive:
			count += 1
	for unit in get_tree().get_nodes_in_group("unit"):
		if "faction" in unit and int(unit.faction) == FACTIONS.Kind.ELVES and float(unit.health) > 0.0:
			# Старейшина не в счёт: он встаёт сам, и эльфы с ним не выбыли бы
			# никогда, как их ни вырезай.
			if "is_champion" in unit and bool(unit.is_champion):
				continue
			count += 1
	return count


func _spawn_guard_barracks() -> void:
	for node in get_tree().get_nodes_in_group("building"):
		if "faction" in node and int(node.faction) == FACTIONS.Kind.GUARD:
			return
	spawn_building(RES.Building.SWORD_BARRACKS, GUARD_BARRACKS_POS, 0, FACTIONS.Kind.GUARD, true)
	for entry in GUARD_ESTATE:
		spawn_building(int(entry[0]), entry[1], 0, FACTIONS.Kind.GUARD, true)


## Сессия закрывается — успеваем сохраниться.
##
## Именно здесь, а не в `_on_session_ended`: там пир уже закрыт, `Net.hosting()`
## возвращает false, и сохранение отказывается работать молча. Автосейв идёт раз
## в минуту, и без этой строки выход в меню стоил бы человеку до минуты игры —
## за минуту успевают построить дом.
func _on_session_ending() -> void:
	savegame.save_world()


func _on_session_ended() -> void:
	if strategy_mode:
		strategy_mode = false
		_strategy_camera.deactivate()
		camera_mode_changed.emit(false)
	for child in _players.get_children():
		child.queue_free()
	_menu_camera.current = true
	# И снова останавливаем: человек вернулся в меню, партия его больше не ждёт.
	_set_running(false)


func _on_peer_disconnected(id: int) -> void:
	if not Net.hosting():
		return
	var node := _players.get_node_or_null(str(id))
	if node != null:
		node.queue_free()


@rpc("any_peer", "reliable")
func _request_spawn(wanted_faction: int, profile: String) -> void:
	if not Net.hosting():
		return
	_spawn_player(multiplayer.get_remote_sender_id(), wanted_faction, profile)


func _spawn_player(id: int, wanted_faction: int = 0, profile: String = "") -> void:
	if _players.has_node(str(id)):
		return
	var slot := _next_free_slot()
	if slot < 0:
		push_warning("Сессия заполнена, игроку %d места нет." % id)
		return

	# ВЫБОР В МЕНЮ ГЛАВНЕЕ ПАМЯТИ.
	#
	# Раньше здесь стояло обратное: сторона бралась из сохранения и перебивала
	# выбор молча. Правило было благое — прогресс привязан к стороне (GDD раздел
	# 6), и пересаживать человека значит отбирать нажитое, — но следствие вышло
	# скверным: сыграв один раз за злодея, дальше нельзя было сесть ни за кого,
	# и меню показывало выбор, которого не существовало.
	#
	# Теперь прогресс лежит на паре профиль+сторона (`savegame._player_key`),
	# поэтому отбирать нечего: за каждой стороной своё нажитое, и выбор
	# исполняется буквально.
	var asked := wanted_faction

	# Свободных слотов у стороны может не остаться — тогда сажаем в ближайшую
	# свободную и говорим об этом вслух, а не молча.
	var faction := _assign_faction(asked)
	if faction < 0:
		push_warning("Свободных сторон не осталось, игроку %d места нет." % id)
		return
	if faction != asked:
		var told := "Сторона «%s» занята — вы играете за «%s»." % [
			FACTIONS.name_of(asked), FACTIONS.name_of(faction)]
		Net.status_changed.emit(told)
		# И ГРОМКО, на экран. Строка состояния живёт в МЕНЮ, а к этому мгновению
		# меню уже закрыто: человек оказывался на чужой базе, не получив ни
		# слова о том, почему. Живой отчёт «появляешься в форте злодея» пришёл
		# именно так — без единой подсказки, что сторона подменена.
		objective.announce(told)

	print("[world] спавню игрока %d, сторона %s, слот %d" % [id, FACTIONS.name_of(faction), slot])
	var node := _spawner.spawn({"id": id, "slot": slot, "faction": faction, "profile": profile})
	if node != null:
		# Сигналы нужны только хосту: и снаряды, и смерть считает он.
		node.death_reported.connect(_on_player_death)
		node.projectile_requested.connect(_on_projectile_requested)
		# Злодей — вожак по рождению: он один человек с личной армией. Страж
		# становится вожаком повышением у NPC, эльфы — никогда.
		node.is_leader = FACTIONS.has_strategy(faction)
		# Стартовый запас больше не выдаётся персонажу: он лежит в казне фракции
		# и разложен там ещё до появления игроков (treasury.gd).
		# Прогресс накатываем ПОСЛЕ выставления роли: сохранение знает и о
		# командовании, и его решение важнее умолчания по стороне.
		savegame.restore_player(node)


## Выполняется на всех пирах с одними и теми же данными, поэтому имя ноды и
## слот совпадают везде.
func _make_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	# Имя == peer id: по нему персонаж на всех пирах определяет своего авторитета.
	player.name = str(data["id"])
	player.spawn_slot = int(data["slot"])
	player.profile_id = String(data.get("profile", ""))
	player.faction = int(data.get("faction", 0))
	# До входа в дерево: `_enter_tree()` по этому флагу решает, кому авторитет.
	player.ai_led = bool(data.get("ai", false))
	return player


## Наименьший свободный слот. Считается только на хосте.
## Свободный номер места. Мест — сколько игроков вмещает сессия, и ещё по
## одному на ИИ-вожака каждой стороны.
##
## РАНЬШЕ МЕСТ БЫЛО ТРИ — по числу `SPAWN_POINTS`, — а сессия рассчитана на
## одиннадцать человек. С ИИ-вожаком злодея в мир помещались двое живых, и
## третий человек не появлялся вовсе («сессия заполнена»). Пряталось это, пока
## наборы шли вдвоём; вскрылось, когда ИИ-вожак появился и у эльфов.
func _next_free_slot() -> int:
	var used := {}
	for child in _players.get_children():
		used[child.spawn_slot] = true
	for i in FACTIONS.total_slots() + FACTIONS.COUNT:
		if not used.has(i):
			return i
	return -1


# --- бой: снаряды, трупы, респавн -----------------------------------------

## Общая фабрика для всего, что мир спавнит по сети. Выполняется на всех пирах
## с одинаковыми данными, поэтому имя и параметры совпадают везде.
func _make_spawned(data: Dictionary) -> Node:
	var node: Node
	match String(data["type"]):
		"projectile":
			node = PROJECTILE_SCENE.instantiate()
		"building":
			node = BUILDING_SCENE.instantiate()
		"caravan":
			node = CARAVAN_SCENE.instantiate()
		"loot":
			node = LOOT_SCENE.instantiate()
		"limb":
			node = LIMB_SCENE.instantiate()
		"unit":
			node = UNIT_SCENE.instantiate()
		"labourer":
			node = LABOURER_SCENE.instantiate()
		"horse":
			# У лошади нет сцены: она собирается кодом, как и караван. Заводить
			# .tscn ради четырёх коробок значит завести файл, который никто
			# никогда не откроет.
			node = CharacterBody3D.new()
			node.set_script(load("res://scripts/units/horse.gd"))
		_:
			node = CORPSE_SCENE.instantiate()
	node.name = "%s_%d" % [data["type"], int(data["id"])]
	node.setup(data)
	return node


## Стрела бойца-лучника. Отличается от игроцкой только тем, КТО стрелок: у бойца
## нет peer id, поэтому снаряд запоминает путь ноды и по нему исключает стрелка
## из собственного попадания.
func spawn_unit_arrow(origin: Vector3, dir: Vector3, shooter: Node3D) -> Node:
	if not Net.hosting() or shooter == null:
		return null
	_spawn_counter += 1
	return _world_spawner.spawn({
		"type": "projectile",
		"id": _spawn_counter,
		"kind": WEAPONS.Kind.BOW,
		"origin": origin,
		"dir": dir,
		"shooter": int(shooter.owner_id),
		"shooter_path": String(shooter.get_path()),
		"gear": 0,
	})


func _on_projectile_requested(kind: int, origin: Vector3, dir: Vector3, shooter_id: int, gear: int) -> void:
	if not Net.hosting():
		return
	_spawn_counter += 1
	_world_spawner.spawn({
		"type": "projectile",
		"id": _spawn_counter,
		"kind": kind,
		"origin": origin,
		"dir": dir,
		"shooter": shooter_id,
		# Уровень снаряжения кладём в пакет спавна, а не читаем у стрелка при
		# попадании: стрелок к тому моменту может быть уже мёртв или отключён.
		"gear": gear,
	})


func _on_player_death(player: Node3D, killer_id: int) -> void:
	if not Net.hosting():
		return
	print("[бой] %s убит игроком %d" % [player.name, killer_id])
	commander.report_kill(killer_id, int(player.faction))
	commander.report_victim(killer_id, player)
	elder.report_victim(killer_id, player)
	_award_kill_xp(killer_id, int(player.faction), bool(player.is_leader))
	# Гибель стража может провалить его решающий удар; гибель вожака — засчитать
	# чужой. Порядок важен: сперва снимаем провал, потом засчитываем победителю.
	commander.report_guard_death(player)
	if player.is_leader:
		commander.report_leader_kill(killer_id, int(player.faction))
	_spawn_corpse(player)
	_drop_belongings(player)
	player.set_dead.rpc(true)

	# Вожак не возвращается. Злодей — один человек с личной армией, командир
	# стражи — тот, кто заслужил место: их смерть окончательна и является
	# условием победы противника (GDD раздел 7). Рядовые эльфы и стражники
	# возрождаются как раньше.
	if player.is_leader:
		print("[смерть] вожак %s пал окончательно" % player.name)
		objective.report_leader_down(int(player.faction), faction_of(killer_id))
		# Игрок остаётся в сессии наблюдателем: партия не обрывается победой,
		# и досмотреть её он должен с камеры, а не с собственного трупа.
		if int(player.peer_id) == 1:
			player.become_spectator()
		else:
			player.become_spectator.rpc_id(int(player.peer_id))
		return

	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(player):
		return
	# ЭЛЬФ ВСТАЁТ У ДОМА, а домов может не быть (GDD 9a). Тогда ждём, пока
	# живые отстроят новый: павшему негде возродиться. Эльфы проигрывают, когда
	# домов нет и в живых никого — ждать тогда уже некого.
	while int(player.faction) == FACTIONS.Kind.ELVES and elf_houses(true).is_empty():
		if objective.out[FACTIONS.Kind.ELVES] == 1:
			return
		await get_tree().create_timer(2.0).timeout
		if not is_instance_valid(player):
			return
	# Здоровье возвращаем, РАНЕНИЯ — НЕТ (GDD раздел 4.1). Раньше здесь стоял
	# body.reset(), и это подрывало весь Этап 3: умереть и встать целым было
	# дешевле и быстрее, чем идти за протезом.
	player.health.revive()
	player.respawn_at_slot()
	player.set_dead.rpc(false)


## Смерть роняет всё, что персонаж нёс на себе: ресурсы при себе и купленный
## уровень снаряжения. Поднять может любой, кто подошёл, включая убийцу —
## ровно как груз разбитого каравана (GDD раздел 4.1).
##
## Базовое оружие не теряется никогда: без меча персонаж перестал бы быть
## персонажем. Теряется только купленный апгрейд.
func _drop_belongings(player: Node3D) -> void:
	var lost: PackedInt32Array = player.stock.drop_carried()
	var gear: int = int(player.gear_tier)
	player.gear_tier = 0
	# ПАДАЕТ ВСЁ, что было на теле (ответ автора от 29.09): доспех, бинты или
	# травы, зелья, стрелы. Раньше доспех оставался на вернувшемся.
	var armor: int = int(player.armor_tier)
	var bandages: int = int(player.body.bandages)
	var potions_heal: int = int(player.potions_heal)
	var potions_mana: int = int(player.potions_mana)
	var arrows: int = int(player.arrows)
	player.armor_tier = 0
	player.body.bandages = 0
	player.potions_heal = 0
	player.potions_mana = 0
	player.arrows = 0

	var total := 0
	for value in lost:
		total += value
	if total <= 0 and gear <= 0 and armor <= 0 and bandages + potions_heal + potions_mana + arrows <= 0:
		return

	_spawn_counter += 1
	_world_spawner.spawn({
		"type": "loot",
		"id": _spawn_counter,
		"point": player.global_position + Vector3.UP * 0.6,
		"contents": lost,
		"gear": gear,
		"armor": armor,
		"bandages": bandages,
		"potions_heal": potions_heal,
		"potions_mana": potions_mana,
		"arrows": arrows,
	})
	print("[смерть] с игрока %d выпало %d единиц, оружие %d, доспех %d, бинтов %d, зелий %d, стрел %d"
		% [int(player.peer_id), total, gear, armor, bandages, potions_heal + potions_mana, arrows])


func _spawn_corpse(player: Node3D) -> void:
	place_corpse(player.global_position, player.rotation.y, player.spawn_slot, player.body.severed_mask)


## Положить труп в заданной точке. Отдельным методом, потому что этим
## пользуются инструменты проверки (tools/screenshotter.gd).
func place_corpse(point: Vector3, yaw: float, slot: int, severed: int = 0) -> void:
	if not Net.hosting():
		return
	_spawn_counter += 1
	var corpse := _world_spawner.spawn({
		"type": "corpse",
		"id": _spawn_counter,
		"point": point,
		"yaw": yaw,
		"slot": slot,
		"severed": severed,
	})
	if corpse != null:
		_corpses.append(corpse)
	while _corpses.size() > CORPSE_LIMIT:
		var oldest: Node = _corpses.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Где стоит верстак. Клиент по этому же значению решает, показывать ли подсказку.
func workbench_position() -> Vector3:
	return WORLD_BUILDER.WORKBENCH_POS


func is_at_workbench(point: Vector3) -> bool:
	var flat := Vector3(point.x, 0.0, point.z)
	return flat.distance_to(workbench_position()) <= WORKBENCH_RANGE


## Где стоит торговец эльфов. Он в их поселении: чужому туда дойти можно, но
## идти придётся через весь лес — торговля намеренно не бесплатна географически.
## Где лавка ЭТОЙ стороны. У каждой своя, в её собственной зоне.
func trader_position(faction: int) -> Vector3:
	return WORLD_BUILDER.TRADER_POS.get(clampi(faction, 0, FACTIONS.COUNT - 1),
		WORLD_BUILDER.TRADER_POS[0])


## Стоит ли боец у СВОЕЙ лавки. Чужая не обслуживает вовсе — не по отношениям,
## как раньше, а по принадлежности: лавка эльфов эльфийская.
func is_at_trader(point: Vector3, faction: int) -> bool:
	var at: Vector3 = trader_position(faction)
	var flat := Vector2(point.x, point.z)
	return flat.distance_to(Vector2(at.x, at.z)) <= TRADER_RANGE


# --- стройка ---------------------------------------------------------------

## Поставить здание. Только на хосте: сюда попадают уже проверенные заявки
## (см. player.gd::request_build — там же списывается стоимость).
func spawn_building(kind: int, point: Vector3, owner_id: int, faction := -1,
		prebuilt := false, yaw := 0.0) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var side: int = faction if faction >= 0 else faction_of(owner_id)
	var node := _world_spawner.spawn({
		"type": "building",
		"id": _spawn_counter,
		"kind": kind,
		"point": point,
		"owner": owner_id,
		"faction": side,
		"prebuilt": prebuilt,
		# Разворот постройке сейчас никто не задаёт, но в сейв он пишется, и
		# ехать он обязан ЗДЕСЬ, вместе с остальными данными спавна: выставленный
		# после спавна на хосте, до клиентов он не доедет вовсе.
		"yaw": yaw,
	})
	if node != null:
		print("[стройка] %s стороны «%s» в %s" % [RES.BUILDING_NAMES[kind], FACTIONS.name_of(side), point])
		node.completed.connect(_on_building_completed.bind(node))
		node.destroyed_on_server.connect(_on_building_destroyed)
		node.hit_on_server.connect(_on_building_hit)
		navigation.mark_dirty()
	return node


## Как часто напоминать об одной и той же постройке под ударом, мс.
const HIT_ALERT_MS := 30000
## Постройка -> когда о ней последний раз предупреждали (мс).
var _hit_alerts := {}


## Постройку бьют — сказать стороне (решение автора от 29.09: жёсткий старт,
## «стойте за свой форт сами»). Живой игрок далеко, у обоза или в бою, и без
## этого узнавал о набеге, только вернувшись к пепелищу. Раз в полминуты на
## постройку: удар за ударом — не новость.
func _on_building_hit(building: Node3D) -> void:
	if not Net.hosting() or not is_instance_valid(building):
		return
	var id := building.get_instance_id()
	var now := Time.get_ticks_msec()
	if now - int(_hit_alerts.get(id, -HIT_ALERT_MS)) < HIT_ALERT_MS:
		return
	_hit_alerts[id] = now
	notify_side(int(building.faction), "%s под ударом! Прочность %d из %d" % [
		RES.BUILDING_NAMES[int(building.kind)], int(building.health),
		int(building.max_health())])


## Постройка разрушена. Для стражи это половина условия поражения (GDD раздел 7):
## сломлена она, только когда пал командир И снесена казарма.
func _on_building_destroyed(building: Node3D, killer_id: int) -> void:
	if not Net.hosting():
		return
	commander.report_building_down(building, killer_id)
	objective.check_victories()
	navigation.mark_dirty()


## Достроенный склад поднимает владельцу потолок хранения — по GDD это
## «главное здание, оно же склад и пункт приёма ресурсов».
func _on_building_completed(node: Node) -> void:
	if not Net.hosting() or node == null:
		return
	if int(node.kind) != RES.Building.STORAGE:
		return
	# Потолок поднимаем СТОРОНЕ, а не владельцу-персонажу. Казна и так
	# принадлежит стороне (treasury.gd), а искать владельца среди игроков
	# значит не заметить склад, построенный ИИ: у него владельца нет вовсе,
	# и его склад оставался украшением — сторона по-прежнему не могла
	# ничего сложить, а батраки носили добычу в никуда.
	var wallet: Node = treasury.of(int(node.faction))
	if wallet != null:
		wallet.raise_capacity(RES.STORAGE_BONUS)
		print("[стройка] склад достроен, потолок стороны «%s» поднят"
			% FACTIONS.name_of(int(node.faction)))


## Клик по земле в режиме стройки: заявку отправляет свой персонаж — у него
## есть и владелец, и запас ресурсов.
func _on_place_requested(kind: int, point: Vector3) -> void:
	var me := local_player()
	if me != null:
		me.ask_build(kind, point)
	build_controller.set_active(false)


## Стройка эльфа — из боевого вида: вида сверху у эльфов нет (GDD 9a).
## `kind` < 0 снимает режим.
func set_elf_build(kind: int) -> void:
	if kind < 0:
		build_controller.set_active(false)
		return
	build_controller.select(kind)
	build_controller.set_active(true)


## Стройка живёт только в стратегической камере.
func set_build_mode(on: bool, kind: int = -1) -> void:
	if on and not strategy_mode:
		return
	if kind >= 0:
		build_controller.select(kind)
	build_controller.set_active(on)


# --- караван ---------------------------------------------------------------

## Игрок дорисовал маршрут и нажал Enter.
func _on_route_sent(points: PackedVector3Array) -> void:
	var me := local_player()
	if me != null:
		me.ask_send_caravan(points)


## Прокладка маршрута живёт только в стратегической камере.
func set_route_mode(on: bool) -> void:
	if on and not strategy_mode:
		return
	if on:
		build_controller.set_active(false)
		# Снимаем фокус с любого элемента интерфейса. Сфокусированные Button и
		# LineEdit съедают Enter в фазе GUI, до _unhandled_input, и отправка
		# каравана молча не срабатывает. Живой тестер сообщил ровно это:
		# маршрут рисуется, Enter не отправляет. Причину по одному его логу
		# восстановить не вышло, поэтому убираем весь класс причин сразу.
		get_viewport().gui_release_focus()
	route_controller.set_active(on)


## Ближайший ДОСТРОЕННЫЙ склад игрока. Без него каравану некуда возвращаться.
## Достроенный склад СТОРОНЫ.
##
## По стороне, а не по владельцу-персонажу: казна и так принадлежит стороне
## (`treasury.gd`), и склад обязан ей же. Иначе выходила нелепость — игрок не мог
## сложить добытое в склад, который построил не он, хотя ресурсы всё равно шли в
## общий кошелёк. И тем более не мог сложить в склад, построенный ИИ до того, как
## он сел за эту сторону.
func storage_of(faction: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null:
			continue
		if int(building.kind) != RES.Building.STORAGE:
			continue
		if int(building.faction) != faction:
			continue
		if float(building.progress) < 1.0:
			continue
		return building
	return null


## Сколько бойцов сторона может держать. База плюс по слоту за каждый
## достроенный дом дружины, но не выше жёсткого потолка.
##
## СЧИТАЕМ ПО СТОРОНЕ, а не по владельцу: дом, построенный ИИ, тоже дом. Ровно
## та же ошибка уже была со складом — он поднимал потолок владельцу-персонажу,
## и склад свободной стороны оставался украшением.
func squad_capacity(faction: int) -> int:
	var houses := 0
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null:
			continue
		if int(building.kind) != RES.Building.HOUSE:
			continue
		if int(building.faction) != faction:
			continue
		if float(building.progress) < 1.0:
			continue
		houses += 1
	return mini(RES.SQUAD_LIMIT, RES.SQUAD_BASE + houses * RES.HOUSE_SLOTS)


## Отправить караван. Только на хосте: маршрут сюда попадает уже проверенным
## (см. player.gd::request_send_caravan).
func spawn_caravan(route: PackedVector3Array, owner_id: int, faction := -1,
		horses := 2) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var walked := _walkable_route(route)
	var node := _world_spawner.spawn({
		"type": "caravan",
		"id": _spawn_counter,
		"route": walked,
		"owner": owner_id,
		"faction": faction if faction >= 0 else faction_of(owner_id),
		"horses": horses,
	})
	if node != null:
		print("[караван] игрок %d отправил караван: точек %d (по карте %d), лошадей %d"
			% [owner_id, route.size(), walked.size(), horses])
		# Сторону обоза читаем В МИГ СОБЫТИЯ, а не при спавне: перехваченный
		# обоз (GDD 9a) по дороге меняет хозяина, и привязанная при спавне
		# сторона засчитала бы разбитый обоз злодея как обоз стражи.
		node.destroyed.connect(func(point: Vector3, cargo: PackedInt32Array, killer_id: int) -> void:
			_on_caravan_destroyed(point, cargo, killer_id, int(node.faction)))
		# Лошади уходят с обозом и возвращаются в конюшню, когда он доехал. На
		# обратном пути их могут увести или убить — тогда возвращать нечего, и
		# считать это должен сам обоз, а не отправитель.
		node.came_home.connect(func(team: int) -> void:
			_on_caravan_home(team, int(node.faction))
			commander.report_caravan_home(node))
	return node


## Перехватить чужой обоз (GDD 9a): он едет на склад перехватчика. Только хост.
##
## ЛОШАДИ ПЕРЕХОДЯТ ВМЕСТЕ С ОБОЗОМ: живые из упряжки уходят из конюшни прежнего
## хозяина и числятся у нового — как ушедшие в упряжку, а доехав, становятся
## свободными. Убитые по дороге остаются потерей прежнего хозяина.
##
## Для стражи это ещё и приказ «перехватить караван»: перенаправить обоз злодея
## к себе — ровно то, чего командир и хочет.
func intercept_caravan(cart: Node3D, player: Node3D) -> bool:
	if not Net.hosting() or cart == null or player == null:
		return false
	var side := int(player.faction)
	var storage: Node3D = storage_of(side)
	if storage == null:
		return false
	var old_side := int(cart.faction)
	var walked := _walkable_route(PackedVector3Array([storage.global_position, cart.global_position]))
	if walked.size() < 2:
		return false
	var team := int(cart.horses)
	var old_wallet: Node = treasury.of(old_side)
	if old_wallet != null:
		old_wallet.horses = maxi(0, int(old_wallet.horses) - team)
		old_wallet.horses_out = maxi(0, int(old_wallet.horses_out) - team)
	var new_wallet: Node = treasury.of(side)
	if new_wallet != null:
		new_wallet.horses = int(new_wallet.horses) + team
		new_wallet.horses_out = int(new_wallet.horses_out) + team
	commander.report_caravan_lost(cart.global_position, old_side)
	cart.redirect(side, int(player.peer_id), walked)
	commander.report_caravan_destroyed(int(player.peer_id), old_side)
	objective.log_event.rpc("Обоз «%s» перехвачен стороной «%s»" % [
		FACTIONS.name_of(old_side), FACTIONS.name_of(side)])
	return true


## Стража переходит к злодею: захвачен дворец (GDD 9a, ответ автора от 28.09 —
## «захват дворца злодеем отдаёт ему контроль над всеми землями людей и стражу
## записывает на его сторону»). Только хост.
##
## ЧТО ПЕРЕХОДИТ ЗЛОДЕЮ ЦЕЛИКОМ: постройки (склад, поля, дом, конюшня,
## казармы), бойцы стражи, её обозы, казна и лошади.
##
## ЧТО НЕТ: стражники-ИГРОКИ. Они остаются стражей — со своим оружием и без
## магии злодея, «обычные люди-воины», — становятся его союзниками
## (`FACTIONS.hostile`) и командование сохраняют (ответ автора от 29.09).
## Перекрасить живого игрока в злодея значило бы выдать ему чужое снаряжение и
## чужую магию посреди боя.
func absorb_guard() -> void:
	if not Net.hosting():
		return
	var guard := FACTIONS.Kind.GUARD
	var villain := FACTIONS.Kind.VILLAIN
	for node in get_tree().get_nodes_in_group("building"):
		if "faction" in node and int(node.faction) == guard:
			node.set_side.rpc(villain)
	for unit in get_tree().get_nodes_in_group("unit"):
		if "faction" in unit and int(unit.faction) == guard and unit.has_method("set_side"):
			unit.set_side.rpc(villain)
	for cart in caravans_of(0):
		if int(cart.faction) == guard:
			cart.faction = villain
	var from: Node = treasury.of(guard)
	var into: Node = treasury.of(villain)
	if from != null and into != null:
		# Казна стражи лежит в основном «при себе» (стартовые запасы), а склада
		# у злодея может не быть вовсе. Кладём в склад, сколько влезет, остаток —
		# при себе, как ложится любая добыча. Потолок поднимаем на склад стражи:
		# он теперь злодеев.
		into.raise_capacity(int(from.stored.capacity))
		for kind in RES.COUNT:
			var amount: int = int(from.get_amount(kind))
			if amount <= 0:
				continue
			var left: int = amount - int(into.add_stored(kind, amount))
			if left > 0:
				into.carried.capacity = maxi(int(into.carried.capacity),
					int(into.carried.get_amount(kind)) + left)
				into.add(kind, left)
		into.horses = int(into.horses) + int(from.horses)
		into.horses_out = int(into.horses_out) + int(from.horses_out)
		from.grant(RES.empty())
		from.horses = 0
		from.horses_out = 0
	# Командир стражи командование СОХРАНЯЕТ (ответ автора от 29.09: «с
	# командованием, но без магии — они обычные люди-воины»): он теперь служит
	# злодею, но отрядом, стройкой и наёмом распоряжается по-прежнему.
	print("[цель] стража перешла к злодею: постройки, бойцы, обозы, казна")


## Сказать всем людям стороны. На экран — как приказ командира.
func notify_side(faction: int, text: String) -> void:
	if not Net.hosting():
		return
	print("[сторона %s] %s" % [FACTIONS.name_of(faction), text])
	for player in players_of(faction):
		if int(player.peer_id) == 1:
			objective.announced.emit(text)
		else:
			objective.announce.rpc_id(int(player.peer_id), text)


## Обоз доехал: лошади снова свободны и годятся хоть в упряжку, хоть под седло.
func _on_caravan_home(horses: int, faction: int) -> void:
	var wallet: Node = treasury.of(faction)
	if wallet == null:
		return
	wallet.horses_out = maxi(0, wallet.horses_out - horses)


## Проложить нарисованный маршрут ПО КАРТЕ.
##
## Точки, которые игрок наметил кликами, остаются его решением и все до одной
## посещаются: короткий путь по открытому месту против длинного в обход — это
## выбор игрока (GDD 2.3), и отбирать его нельзя. Меняется только то, КАК караван
## идёт между ними: раньше по прямой, сквозь горы и с постоянной высотой, теперь
## по навигационной сетке, следуя земле.
##
## Если пути между двумя точками нет, оставляем прямой отрезок: пусть лучше
## упрётся, чем маршрут молча не отправится.
func _walkable_route(route: PackedVector3Array) -> PackedVector3Array:
	if route.size() < 2 or not navigation.is_ready():
		return route
	var walked := PackedVector3Array()
	walked.append(route[0])
	for i in range(1, route.size()):
		var leg: PackedVector3Array = navigation.path_between(
			navigation.closest_point(route[i - 1]), navigation.closest_point(route[i]))
		if leg.size() < 2:
			walked.append(route[i])
			continue
		# Первую точку отрезка пропускаем: это то место, где мы уже стоим.
		for j in range(1, leg.size()):
			walked.append(leg[j])
	return walked


## Разбитый караван высыпает груз на землю: подобрать может любой
## (DESIGN_ANSWERS.md, пункт 15).
func _on_caravan_destroyed(point: Vector3, cargo: PackedInt32Array, killer_id: int, caravan_faction: int) -> void:
	if not Net.hosting():
		return
	# Сторону каравана берём У НЕГО, а не через владельца: у каравана ИИ владельца
	# нет, и через faction_of(0) сторона выходила -1 — ни приказ стражи, ни
	# отношения такой разбитый караван не засчитывали.
	# Приказ стражи «перехватить караван» засчитывается тут же: командир сам
	# решит, его ли это караван и тот ли игрок его разбил.
	commander.report_caravan_destroyed(killer_id, caravan_faction)
	commander.report_caravan_lost(point, caravan_faction)
	elder.report_caravan_hit(killer_id, caravan_faction)
	var total := 0
	for value in cargo:
		total += value
	if total <= 0:
		return
	_spawn_counter += 1
	_world_spawner.spawn({
		"type": "loot",
		"id": _spawn_counter,
		"point": point,
		"contents": cargo,
	})


## Боец погиб. Приказ стражи «проредить войско злодея» засчитывает и бойцов,
## а не только самого злодея.
func report_unit_kill(killer_id: int, victim_faction: int, victim: Node3D = null) -> void:
	if not Net.hosting():
		return
	commander.report_kill(killer_id, victim_faction)
	if victim != null:
		commander.report_victim(killer_id, victim)
		elder.report_victim(killer_id, victim)
	_award_kill_xp(killer_id, victim_faction, false)


## Опыт за убийство — тому, кто убил.
##
## ЗА СВОИХ НЕ ДАЁМ. Иначе выгоднее всего было бы резать собственный гарнизон:
## он рядом, он не сопротивляется, и он бесконечно возобновляем.
func _award_kill_xp(killer_id: int, victim_faction: int, leader: bool) -> void:
	if not Net.hosting() or killer_id <= 0:
		return
	var killer: Node3D = _player_by_peer(killer_id)
	if killer == null or not FACTIONS.hostile(int(killer.faction), victim_faction):
		return
	killer.award_xp(PROGRESS.XP_LEADER_KILL if leader else PROGRESS.XP_UNIT_KILL,
		"убийство вожака" if leader else "убийство")


## Вожак стороны: живой игрок, а если стороной правит ИИ — его герой.
##
## Опыт за ОБЩЕЕ (донесённые батраками ресурсы, доехавшие обозы) идёт вожаку:
## хозяйство — его дело. Опыт за личное (убийства) идёт тому, кто это сделал.
func leader_of(faction: int) -> Node3D:
	for player in players_of(faction):
		if player != null and player.health.alive:
			return player
	return ai_hero_of(faction)


## Опыт стороне за хозяйственное событие.
func award_faction_xp(faction: int, amount: int, why: String) -> void:
	if not Net.hosting() or amount <= 0:
		return
	var boss: Node3D = leader_of(faction)
	if boss != null:
		boss.award_xp(amount, why)


## Опыт стороне за донесённые до склада ресурсы.
func award_faction_resources(faction: int, units: int) -> void:
	if not Net.hosting() or units <= 0:
		return
	var boss: Node3D = leader_of(faction)
	if boss != null:
		boss.award_xp_for_resources(units)


func _player_by_peer(peer: int) -> Node3D:
	for child in _players.get_children():
		if "peer_id" in child and int(child.peer_id) == peer:
			return child
	return null


## Нанять батрака. Считает и спавнит ТОЛЬКО хост.
##
## Владельца батрак не имеет (owner_id = 0), как гарнизон: он принадлежит
## СТОРОНЕ, а не персонажу. Так его переживают смерть игрока и смена персонажа,
## и так же его сможет нанимать ИИ, когда до этого дойдёт.
func spawn_labourer(faction: int, point: Vector3, home_point: Vector3, role: int) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var node := _world_spawner.spawn({
		"type": "labourer",
		"id": _spawn_counter,
		"owner": 0,
		"slot": labourers_of(faction).size(),
		"point": point,
		"beast": false,
		"champion": false,
		"faction": faction,
		"home": home_point,
		"leash": 0.0,
		"role": role,
	})
	if node != null:
		print("[батраки] %s: нанят %s, всего %d" % [FACTIONS.name_of(faction),
			node.role_name(), labourers_of(faction).size()])
	return node


## Батраки стороны, живые в этот момент.
func labourers_of(faction: int) -> Array:
	var found := []
	for node in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(node) or not ("sync_role" in node):
			continue
		if int(node.faction) == faction:
			found.append(node)
	return found


## Караваны игрока, живые в этот момент.
##
## Ищем по `path_ahead` — он есть только у каравана. По `state_text` искать
## нельзя: подпись для интерфейса есть и у лошади, и стоило появиться на карте
## свободной лошади, как перебор падал на чтении несуществующего `owner_id`, а
## вместе с ним переставала работать отправка обозов у ИИ.
func caravans_of(owner_id: int) -> Array:
	var found := []
	for child in _spawned.get_children():
		if child.has_method("path_ahead") and int(child.owner_id) == owner_id:
			found.append(child)
	return found


# --- отряд -----------------------------------------------------------------

## Ближайшая ДОСТРОЕННАЯ казарма игрока.
## Достроенная казарма СТОРОНЫ нужного рода войск. По той же причине, что и
## склад: постройка принадлежит стороне, а не тому, кто её поставил.
func barracks_of(faction: int, kind: int = RES.Building.SWORD_BARRACKS) -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null:
			continue
		if int(building.kind) != kind:
			continue
		if int(building.faction) != faction or float(building.progress) < 1.0:
			continue
		return building
	return null


## Записать игроку трофей: он кому-то что-то отрубил.
##
## Ищем по peer id, потому что рубит КОНКРЕТНЫЙ человек, а не сторона: некротический
## протез — личная добыча, и делить её на всю сторону было бы странно.
func award_trophy(attacker_id: int, kind: int) -> void:
	if not Net.hosting():
		return
	var node := _players.get_node_or_null(str(attacker_id))
	if node != null and node.has_method("note_trophy"):
		node.note_trophy(kind)


## Высыпать кучу ресурсов в точку. Нужно проверкам и съёмке: в самой игре
## кучи родятся от разбитого каравана и с убитого игрока, и подстроить их состав
## оттуда нельзя.
func spawn_loot_pile(point: Vector3, contents: PackedInt32Array) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	return _world_spawner.spawn({
		"type": "loot",
		"id": _spawn_counter,
		"point": point,
		"contents": contents,
	})


## Уронить оторванную конечность на землю ОДНУ НА ВСЕХ.
##
## Раньше кусок был локальным визуалом у каждого пира, а трофей начислялся
## нападавшему сам, в момент отрыва. Теперь рубить и собирать — разные
## действия: за отрубленным надо дойти, и его может увести кто угодно, ровно
## как груз разбитого каравана (GDD раздел 2.1 — «подобрать может любой»).
##
## Толчок считаем ЗДЕСЬ и кладём в данные спавна: каждый пир уронит кусок сам,
## но одинаково. Случайность на хосте — единственная, остальные её получают
## готовой.
func spawn_severed_limb(point: Vector3, limb: int, trophy: int, model_scale := 1.0) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return _world_spawner.spawn({
		"type": "limb",
		"id": _spawn_counter,
		"point": point,
		"limb": limb,
		"trophy": trophy,
		"model_scale": model_scale,
		"impulse": Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(2.0, 4.0),
			rng.randf_range(-2.5, 2.5)),
		"spin": Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0),
			rng.randf_range(-6.0, 6.0)),
	})


## Готовая конюшня стороны. Без неё лошадей брать негде.
func stable_of(faction: int) -> Node3D:
	return barracks_of(faction, RES.Building.STABLE)


## Выпустить лошадь в мир: увели у обоза, и теперь она стоит там, где её взяли.
##
## Живой лошадью, а не числом в казне: увести её — это добыча, которую надо
## довести до дома, а не строка в отчёте. По дороге её могут отбить.
func spawn_horse(point: Vector3) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	return _world_spawner.spawn({
		"type": "horse",
		"id": _spawn_counter,
		"point": point,
	})


## Живые бойцы игрока.
func units_of(owner_id: int) -> Array:
	var found := []
	for child in _spawned.get_children():
		if child.is_in_group("unit") and int(child.owner_id) == owner_id:
			found.append(child)
	return found


## Нанять бойца. Только на хосте: заявка сюда попадает уже проверенной
## (см. player.gd::request_train_unit).
func spawn_unit(owner_id: int, slot: int, point: Vector3, beast: bool = false,
		archer: bool = false) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var node := _world_spawner.spawn({
		"type": "unit",
		"id": _spawn_counter,
		"owner": owner_id,
		"slot": slot,
		"point": point,
		"beast": beast,
		"archer": archer,
		"faction": faction_of(owner_id),
	})
	if node != null:
		if beast:
			print("[призыв] игрок %d призвал волка, слот %d" % [owner_id, slot])
		else:
			print("[отряд] игрок %d нанял %s, слот %d"
				% [owner_id, "лучника" if archer else "мечника", slot])
	return node


# --- фракции ---------------------------------------------------------------

## Какие стороны уже заняты в сессии.
func taken_factions() -> Array:
	var taken := []
	for child in _players.get_children():
		if "faction" in child:
			taken.append(int(child.faction))
	return taken


func faction_of(peer: int) -> int:
	var node := _players.get_node_or_null(str(peer))
	return int(node.faction) if node != null and "faction" in node else -1


## Выдать сторону: запрошенную, если свободна, иначе первую свободную.
## Выдать сторону: запрошенную, если в ней есть место, иначе первую свободную.
##
## Сторона больше не уникальна — у эльфов и стражи по нескольку слотов
## (FACTIONS.SLOTS). Уникален только злодей.
func _assign_faction(wanted: int) -> int:
	if wanted >= 0 and wanted < FACTIONS.COUNT and _has_room(wanted):
		return wanted
	for i in FACTIONS.COUNT:
		if _has_room(i):
			return i
	return -1


func _has_room(faction: int) -> bool:
	return players_of(faction).size() < FACTIONS.slots(faction)


func players_of(faction: int) -> Array:
	var found := []
	for child in _players.get_children():
		if "faction" in child and int(child.faction) == faction and not child.ai_led:
			found.append(child)
	return found


## Завести героя стороне, за которую никто не сел (GDD 10.1).
##
## Персонаж ровно тот же, что у живого игрока: та же сцена, тот же вожак, та же
## окончательная смерть. Отличий два — нет пира и ввод даёт `ai/hero.gd`.
##
## Имя ноды ОТРИЦАТЕЛЬНОЕ и уникальное. Имя у персонажа это его peer id, по нему
## все пиры находят авторитета; занять чужой номер нельзя, а ноль недопустим.
## Отрицательные номера пирам не выдаются никогда, поэтому столкнуться не с чем.
func spawn_ai_hero(faction: int) -> Node:
	if not Net.hosting():
		return null
	if not characters_of(faction).is_empty():
		return null
	var slot := _next_free_slot()
	if slot < 0:
		return null
	var id := -1 - faction
	if _players.has_node(str(id)):
		return null
	print("[герой] %s: сторона свободна, за неё играет ИИ" % FACTIONS.name_of(faction))
	var node := _spawner.spawn({
		"id": id, "slot": slot, "faction": faction, "profile": "", "ai": true,
	})
	if node != null:
		node.death_reported.connect(_on_player_death)
		node.projectile_requested.connect(_on_projectile_requested)
		node.is_leader = FACTIONS.has_strategy(faction)
	return node


## Убрать героя ИИ: за сторону сел человек.
func despawn_ai_hero(faction: int) -> void:
	if not Net.hosting():
		return
	for child in _players.get_children():
		if "ai_led" in child and child.ai_led and int(child.faction) == faction:
			print("[герой] %s: за сторону сел игрок, ИИ уходит"
				% FACTIONS.name_of(faction))
			child.queue_free()


## Герой стороны под ИИ, если он есть.
func ai_hero_of(faction: int) -> Node3D:
	for child in _players.get_children():
		if "ai_led" in child and child.ai_led and int(child.faction) == faction:
			return child
	return null


## Все персонажи стороны, ВКЛЮЧАЯ героя под ИИ.
##
## Разделение обязательное, а не косметика. `players_of()` спрашивают в шести
## местах, и все шесть спрашивают одно: «сидит ли за этой стороной человек».
## От ответа зависит, распускать ли гарнизон, вести ли хозяйство, можно ли
## сносить постройки этой стороны и свободен ли слот. Считай герой ИИ игроком —
## сторона немедленно перестала бы быть свободной и сама себя выключила.
func characters_of(faction: int) -> Array:
	var found := []
	for child in _players.get_children():
		if "faction" in child and int(child.faction) == faction:
			found.append(child)
	return found


## Боец гарнизона свободной стороны (Этап 10, шаг 8а).
##
## Отличается от бойца игрока двумя вещами: у него нет владельца-пира (сторона
## задана прямо) и есть ДОМ с поводком — он обороняет зону, а не ходит за
## командиром.
func spawn_garrison_unit(faction: int, slot: int, point: Vector3, home: Vector3, leash: float,
		champion := false, archer := false) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	return _world_spawner.spawn({
		"type": "unit",
		"id": _spawn_counter,
		# Владельца нет: ноль не совпадает ни с одним peer id, поэтому командира
		# такой боец не найдёт никогда и останется на посту.
		"owner": 0,
		"slot": slot,
		"point": point,
		"beast": false,
		"champion": champion,
		"archer": archer,
		"faction": faction,
		"home": home,
		"leash": leash,
	})


## Поляны под шахты в лесу эльфов: [центр, радиус] для `forest.build`.
func _mine_clearings() -> Array:
	var out := []
	for info in WORLD_BUILDER.MINES:
		var at: Vector3 = info["at"]
		out.append([Vector2(at.x, at.z), WORLD_BUILDER.MINE_CLEARING])
	return out


## Расставить шахты по местам и сказать каждой, что она добывает.
func _place_mines() -> void:
	for i in mines.size():
		var info: Dictionary = WORLD_BUILDER.MINES[i]
		mines[i].position = info["at"]
		mines[i].kind = int(info["kind"])


## Шахта, ближайшая к точке. Так выбирается, куда едет обоз: к той шахте, у
## которой игрок поставил последнюю точку маршрута.
func mine_near(point: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for each in mines:
		var d: float = Vector2(point.x, point.z).distance_to(
			Vector2(each.global_position.x, each.global_position.z))
		if d < best_distance:
			best_distance = d
			best = each
	return best


## Шахта нужной породы.
func mine_of(kind: int) -> Node3D:
	for each in mines:
		if int(each.kind) == kind:
			return each
	return null


## Куда обоз едет за грузом: к ВХОДУ шахты, а не в середину скалы.
func mine_dock(which: Node3D) -> Vector3:
	return WORLD_BUILDER.mine_entrance(which.global_position)
