extends Node
##
## Военный отряд свободной стороны (Этап 10, шаг 8, ступень «б»).
##
## ЧТО ЭТО И ЧТО ЭТО НЕ. Ступень «а» (`garrison.gd`) поставила по четыре бойца
## на каждую незанятую сторону, чтобы мир не пустовал. Они стояли на базе и
## дрались только с тем, кто сам к ним пришёл. Ступень «б» даёт им войну:
## отряд выходит с базы, идёт строем к цели, дерётся с тем, что встретил, и
## возвращается, когда его проредили.
##
## Он НЕ строит, НЕ ведёт экономику, НЕ водит караваны и НЕ нанимает пополнение
## сам — состав по-прежнему держит `garrison.gd`. Всё это ступень «в», и браться
## за неё вместе с этой нельзя: ступени на то и ступени.
##
## Считает и командует ТОЛЬКО хост. Клиенты видят обычных бойцов, которые
## куда-то идут, — им не нужно знать, кто отдал приказ.
##
## ПОЧЕМУ У ОТРЯДА НЕТ СВОЕГО КОДА ДВИЖЕНИЯ. Боец получает от нас ровно то же,
## что от живого командира: якорь строя, разворот и вид построения (`unit.gd`:
## ai_anchor, ai_yaw, ai_formation). Дальше он идёт тем же кодом, что отряд
## человека. Если бы у ИИ был свой путь движения, у него был бы и свой набор
## ошибок, которого не видно в игре за людей.
##

const FACTIONS := preload("res://scripts/factions.gd")
const FORMATIONS := preload("res://scripts/units/formations.gd")
const GARRISON := preload("res://scripts/ai/garrison.gd")
const BUILDER := preload("res://scripts/world_builder.gd")

enum State { HOLD, MARCH, FIGHT, RETURN }

const STATE_NAMES := ["обороняет базу", "идёт в набег", "дерётся", "отходит"]

## Как часто пересматривать обстановку. Чаще не нужно: бойцы и так идут сами,
## а частая смена цели превращает поход в топтание.
const THINK_INTERVAL := 2.0

## Скорость якоря строя. Медленнее самого бойца, чтобы отстающие успевали
## подтянуться и колонна не растягивалась в цепочку.
const ANCHOR_SPEED := 5.0

## Ближе этого до цели отряд считается пришедшим.
const ARRIVE_RADIUS := 14.0

## Враг ближе этого от якоря — отряд принимает бой и перестраивается.
const FIGHT_RADIUS := 22.0

## Поводок в походе: насколько далеко от якоря боец гонится за целью.
const MARCH_LEASH := 26.0

## Отряд уходит домой, когда в строю осталось меньше этой доли штата. Половина —
## это «нас проредили», а не «мы почти победили»: отряд из двоих не возьмёт
## ничего и только раздарит убийства.
const RETREAT_FRACTION := 0.5

## Выйти в набег отряд может только полным. Иначе после первого же отхода он
## уходил бы обратно вдвоём и умирал по кругу.
const SALLY_FRACTION := 1.0

## Выше этого отношения сторона считается своей и целью не выбирается. Порог тот
## же, что у дипломатии для «дружелюбно».
const FRIENDLY_ABOVE := 20.0

## Насколько далеко от своей базы отряд вообще готов идти в набег.
##
## Число выбрано так, чтобы БАЗЫ ДРУГ ДРУГА были вне досягаемости: ближайшие
## разнесены на 596 м (эльфы и злодей), а всё, что игрок строит дальше своей
## половины, — внутри. Смысл именно в этом: ИИ не ходит лагерем к чужому спавну
## с первой секунды партии, но приходит за тем, чем игрок полез в его сторону.
##
## Первая версия этого не имела, и отряд стражи выходил в набег на базу злодея
## на первой же секунде — сторона, за которую никто не сел, немедленно
## опустошала свою зону и шла через полкарты. Это ловится только прогоном,
## глазами по коду не видно.
const RAID_RANGE := 420.0

## Насколько якорь строя может оторваться от отряда. Дальше он останавливается и
## ждёт: якорь — это не бегун, а точка сбора, и уходить без бойцов ему незачем.
## Без ожидания якорь ушёл к цели один, а отряд остался у стены, о которую
## споткнулся, — и снаружи это выглядело как идущий набег.
const LAG_LIMIT := 20.0

## Отряд считается застрявшим, если за столько секунд похода его середина не
## сдвинулась на STUCK_STEP метров. Тогда набег отменяется.
##
## Это страховка, а не механика: известные проходы описаны в
## `world_builder.gd::SORTIE_PATH`. Но бойцы ходят по прямой, карту им никто не
## объясняет, и застрять они могут о что угодно. Лучше вернуться домой, чем
## стоять у камня до конца партии.
## Шаг заведомо меньше того, что отряд проходит между размышлениями на марше
## (ANCHOR_SPEED × THINK_INTERVAL = 10 м): иначе идущий отряд копил бы секунды
## застревания просто потому, что порог выбран впритык.
const STUCK_SECONDS := 24.0
const STUCK_STEP := 6.0

var _route := {}
var _stuck_t := {}
var _last_centre := {}

var _think_t := 0.0
## Сторона -> состояние отряда.
var _state := {}
## Сторона -> куда идёт якорь строя.
var _goal := {}
## Сторона -> где якорь строя сейчас.
var _anchor := {}


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	_move_anchors(delta)
	_think_t += delta
	if _think_t < THINK_INTERVAL:
		return
	_think_t = 0.0
	for faction in FACTIONS.COUNT:
		_think(faction)


## Якорь строя ползёт к цели каждый кадр, а решения принимаются раз в две
## секунды. Иначе отряд дёргался бы рывками по интервалу размышления.
func _move_anchors(delta: float) -> void:
	for faction in _anchor.keys():
		var here: Vector3 = _anchor[faction]
		var there: Vector3 = _next_point(faction, here)
		var to := there - here
		to.y = 0.0

		# Ждём отстающих. Отряд идёт вокруг якоря, и если якорь уйдёт вперёд, они
		# просто не догонят: скорость у них та же.
		var centre := _centre_of(faction)
		if centre.is_finite() and centre.distance_to(here) > LAG_LIMIT:
			_command(faction, here, to)
			continue

		var step := ANCHOR_SPEED * delta
		if to.length() <= step:
			here = Vector3(there.x, here.y, there.z)
			_advance_route(faction)
		else:
			here += to.normalized() * step
		_anchor[faction] = here
		_command(faction, here, to)


## Следующая точка маршрута. Пока маршрут не пройден, якорь идёт по нему, а не
## напрямую к цели: базы стоят за стенами, а прямой путь ведёт в стену.
func _next_point(faction: int, fallback: Vector3) -> Vector3:
	var route: Array = _route.get(faction, [])
	if route.is_empty():
		return _goal.get(faction, fallback)
	return route[0]


func _advance_route(faction: int) -> void:
	var route: Array = _route.get(faction, [])
	if not route.is_empty():
		route.remove_at(0)
		_route[faction] = route


## Середина отряда. Vector3.INF, если отряда нет.
func _centre_of(faction: int) -> Vector3:
	var band := _band(faction)
	if band.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	for unit in band:
		sum += unit.global_position
	return sum / float(band.size())


## Проложить маршрут: сначала выход из своей зоны, потом цель. При возвращении
## порядок обратный. Точки прохода лежат в `world_builder.gd::SORTIE_PATH`.
func _set_route(faction: int, target: Vector3, outbound: bool) -> void:
	var gates: Array = BUILDER.SORTIE_PATH.get(faction, [])
	var route := []
	if outbound:
		for point in gates:
			route.append(point)
	else:
		for i in range(gates.size() - 1, -1, -1):
			route.append(gates[i])
	route.append(target)
	_route[faction] = route
	_goal[faction] = target
	_stuck_t[faction] = 0.0
	_last_centre[faction] = _centre_of(faction)


## Раздать бойцам стороны текущий приказ: якорь, разворот, построение, поводок.
func _command(faction: int, anchor: Vector3, facing: Vector3) -> void:
	var state: int = _state.get(faction, State.HOLD)
	var formation := _formation_for(state)
	var yaw := 0.0
	if facing.length() > 0.5:
		yaw = atan2(-facing.x, -facing.z)
	for unit in _band(faction):
		unit.ai_led = true
		unit.ai_anchor = anchor
		unit.ai_yaw = yaw
		unit.ai_formation = formation
		# Дома поводок прежний, широкий: там отряд обороняет зону. В походе он
		# короткий и привязан к якорю — иначе колонна рассыпалась бы за первым
		# же встречным.
		unit.leash = GARRISON.LEASH if state == State.HOLD else MARCH_LEASH


## Построение по обстановке — то самое «использует построения» из плана.
## Колонна быстрее всех, поэтому ей ходят; в бою она получает больше урона,
## поэтому перед дракой отряд разворачивается в шеренгу; дома, где отряд
## принимает удар первым, — стена щитов.
func _formation_for(state: int) -> int:
	match state:
		State.MARCH, State.RETURN:
			return FORMATIONS.Kind.COLUMN
		State.FIGHT:
			return FORMATIONS.Kind.LINE
		_:
			return FORMATIONS.Kind.SHIELD_WALL


func _think(faction: int) -> void:
	var band := _band(faction)
	if band.is_empty():
		_state.erase(faction)
		_goal.erase(faction)
		_anchor.erase(faction)
		_route.erase(faction)
		_stuck_t.erase(faction)
		_last_centre.erase(faction)
		return

	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	if not _anchor.has(faction):
		_anchor[faction] = base
		_goal[faction] = base
		_state[faction] = State.HOLD

	var was: int = _state.get(faction, State.HOLD)
	var here: Vector3 = _anchor[faction]

	# Драка важнее любых планов: пока рядом враг, отряд стоит и дерётся, куда бы
	# ни шёл. Без этого отряд маршировал бы сквозь бой, подставляя спины.
	if _enemy_near(faction, here):
		_set_state(faction, State.FIGHT)
		_goal[faction] = here
		return

	match was:
		State.FIGHT:
			# Бой кончился. Проредили — домой, целы — дальше по плану.
			if _spent(band):
				_go_home(faction, base)
			else:
				_plan_next(faction, band, base)
		State.MARCH:
			if _spent(band) or _is_stuck(faction, band):
				_go_home(faction, base)
			elif _arrived(faction, here):
				# Пришли, а бить некого: цель уже разрушена или ушла.
				_plan_next(faction, band, base)
		State.RETURN:
			if here.distance_to(base) <= ARRIVE_RADIUS or _is_stuck(faction, band):
				_set_state(faction, State.HOLD)
				_route[faction] = []
				_goal[faction] = base
			elif not _spent(band):
				# Цель появилась, пока шли домой. Целый отряд обязан её заметить:
				# иначе он пройдёт мимо только что построенного склада и будет
				# топать до базы, чтобы через минуту выйти сюда же снова.
				_plan_next(faction, band, base)
		_:
			_plan_next(faction, band, base)


## Выбрать следующее дело: идти в набег, если отряд полон и есть на кого, иначе
## стоять дома и ждать пополнения от `garrison.gd`.
func _plan_next(faction: int, band: Array, base: Vector3) -> void:
	if float(band.size()) < GARRISON.SIZE * SALLY_FRACTION:
		_stand_down(faction, base)
		return
	var target := _pick_target(faction)
	if target == Vector3.INF:
		_stand_down(faction, base)
		return
	var same_goal: bool = _goal.get(faction, Vector3.INF).distance_to(target) <= ARRIVE_RADIUS
	var fresh: bool = _state.get(faction, State.HOLD) != State.MARCH or not same_goal
	var from_home: bool = _state.get(faction, State.HOLD) == State.HOLD
	_set_state(faction, State.MARCH)
	# Выход из зоны нужен только когда выходим ИЗ НЕЁ. Отряд, уже стоящий в поле,
	# гнать обратно через собственные ворота незачем.
	_set_route(faction, target, from_home)
	if fresh:
		_announce_raid(faction, target)


## Куда идти: вражеская постройка, а если такой рядом нет — караван. Постройка
## первой не случайно: она не убегает, и её потеря стоит противнику дороже всего.
## И то и другое ищется только в пределах RAID_RANGE от своей базы.
##
## Возвращает Vector3.INF, если бить некого.
func _pick_target(faction: int) -> Vector3:
	var world := get_parent()
	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	var here: Vector3 = _anchor.get(faction, base)

	var best := Vector3.INF
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not ("faction" in building):
			continue
		if not _hostile(faction, int(building.faction)):
			continue
		if base.distance_to(building.global_position) > RAID_RANGE:
			continue
		var d: float = here.distance_to(building.global_position)
		if d < best_distance:
			best_distance = d
			best = building.global_position
	if best != Vector3.INF:
		return best

	var spawned := world.get_node_or_null("Spawned")
	if spawned != null:
		for node in spawned.get_children():
			if not node.has_method("state_text") or not ("owner_id" in node):
				continue
			if not _hostile(faction, int(world.faction_of(int(node.owner_id)))):
				continue
			if base.distance_to(node.global_position) > RAID_RANGE:
				continue
			var d: float = here.distance_to(node.global_position)
			if d < best_distance:
				best_distance = d
				best = node.global_position
	if best != Vector3.INF:
		return best

	# Чужой базы в этом списке нет намеренно. Штурм спавна — это ступень «в»:
	# без экономики и подкреплений отряд из четверых там только раздаст
	# убийства, а игрок получит осаду, которую нечем прекратить.
	return Vector3.INF


## Враждебна ли сторона. Своих не трогаем, дружелюбных тоже: перемирие поднимает
## отношения выше порога, и отряд обязан его уважать, иначе перемирие с ИИ
## ничего не значило бы.
## Дошёл ли отряд до цели: маршрут пройден весь, и у цели стоит либо якорь, либо
## сам отряд.
##
## Спрашивать только про якорь недостаточно. Бойцы останавливаются в замахе от
## цели, а у постройки замах считается от её края (`unit.gd::_reach_of`) — до
## склада это восемь метров. Отряд уже разбирает стену, а якорь до середины
## склада не дошёл, и приход не засчитывался: набег числился идущим, пока его не
## отменял сторож «застрял».
func _arrived(faction: int, here: Vector3) -> bool:
	if not _route.get(faction, []).is_empty():
		return false
	var goal: Vector3 = _goal.get(faction, here)
	if here.distance_to(goal) <= ARRIVE_RADIUS:
		return true
	var centre := _centre_of(faction)
	return centre.is_finite() and centre.distance_to(goal) <= ARRIVE_RADIUS


## Отбой. Дома — просто стоим; в поле — сначала возвращаемся.
##
## Разница не косметическая: «дома» разрешает гарнизону пополнять штат
## (`garrison.gd::_reinforce`), и объявить отбой посреди чужой зоны значило бы
## восполнять потери прямо во вражеском тылу.
func _stand_down(faction: int, base: Vector3) -> void:
	var here: Vector3 = _anchor.get(faction, base)
	if here.distance_to(base) > ARRIVE_RADIUS:
		# Уже отходим — не трогаем: перекладка маршрута каждое размышление
		# обнуляла бы и сторож «застрял», и весь смысл отсчёта.
		if _state.get(faction, State.HOLD) != State.RETURN:
			_go_home(faction, base)
		return
	_set_state(faction, State.HOLD)
	_route[faction] = []
	_goal[faction] = base


## Отход домой тем же путём, каким шли.
func _go_home(faction: int, base: Vector3) -> void:
	_set_state(faction, State.RETURN)
	_set_route(faction, base, false)


## Застрял ли отряд: середина строя не двигается, хотя он в походе. Бойцы ходят
## по прямой, и упереться могут во что угодно; отменённый набег лучше отряда,
## стоящего у камня до конца партии.
func _is_stuck(faction: int, band: Array) -> bool:
	if band.is_empty():
		return false
	var centre := _centre_of(faction)
	if not centre.is_finite():
		return false
	var was: Vector3 = _last_centre.get(faction, centre)
	if centre.distance_to(was) >= STUCK_STEP:
		_last_centre[faction] = centre
		_stuck_t[faction] = 0.0
		return false
	var waited: float = _stuck_t.get(faction, 0.0) + THINK_INTERVAL
	_stuck_t[faction] = waited
	if waited < STUCK_SECONDS:
		return false
	print("[отряд ИИ] %s: застрял, набег отменён" % FACTIONS.name_of(faction))
	_last_centre[faction] = centre
	_stuck_t[faction] = 0.0
	return true


func _hostile(faction: int, other: int) -> bool:
	if other < 0 or other == faction:
		return false
	var diplomacy: Node = get_parent().get_node_or_null("Diplomacy")
	if diplomacy == null:
		return true
	return float(diplomacy.value_of(faction, other)) <= FRIENDLY_ABOVE


## Проредили ли отряд настолько, что пора домой.
func _spent(band: Array) -> bool:
	return float(band.size()) < GARRISON.SIZE * RETREAT_FRACTION


## Есть ли враг вплотную к строю.
func _enemy_near(faction: int, point: Vector3) -> bool:
	var world := get_parent()
	for player in world.get_node("Players").get_children():
		if not ("faction" in player) or int(player.faction) == faction:
			continue
		if not player.health.alive:
			continue
		if point.distance_to(player.global_position) <= FIGHT_RADIUS:
			return true
	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit) or not ("faction" in unit):
			continue
		if int(unit.faction) == faction:
			continue
		if point.distance_to(unit.global_position) <= FIGHT_RADIUS:
			return true
	return false


## Бойцы отряда: гарнизон этой стороны без распорядителя стражи. Распорядитель
## в набеги не ходит — он стоит на посту, через него идёт арка стражи.
func _band(faction: int) -> Array:
	var result := []
	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit) or not ("faction" in unit):
			continue
		if int(unit.faction) != faction or int(unit.owner_id) != 0:
			continue
		if "is_champion" in unit and unit.is_champion:
			continue
		result.append(unit)
	return result


## Сказать всем, что сторона вышла в набег.
##
## Мир начал воевать сам, и без этого игрок видит только, что откуда-то пришли
## четверо и разбирают его склад. Это ровно та болезнь, на которую пожаловался
## первый тестер: игра делает что-то важное и молчит об этом. Объявляем в тот же
## канал, что и захват дворца.
##
## Объявляем ТОЛЬКО о новом набеге, а не при каждом пересчёте цели. Первая
## версия объявляла из `_plan_next` безусловно, и трёхминутный прогон выдал 52
## одинаковых сообщения: отряд дошёл до цели, не смог её сломать и заново ставил
## ту же самую каждые несколько секунд.
func _announce_raid(faction: int, target: Vector3) -> void:
	var objective: Node = get_parent().get_node_or_null("Objective")
	if objective == null:
		return
	# Без глагола: названия сторон разного числа («Злодей», «Лесные эльфы»), и
	# любая общая формулировка со сказуемым выходит безграмотной для половины.
	objective.announce.rpc("Набег: %s → %s" % [
		FACTIONS.name_of(faction), _place_name(target)])


## Как назвать точку на карте, чтобы игрок понял, куда идут. Ближайшая база —
## достаточный ориентир: карта разбита на зоны сторон.
func _place_name(point: Vector3) -> String:
	var best := -1
	var best_distance := INF
	for faction in FACTIONS.COUNT:
		var d: float = point.distance_to(FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)])
		if d < best_distance:
			best_distance = d
			best = faction
	if best < 0:
		return "неизвестно куда"
	return "зона %s" % FACTIONS.name_of(best)


func _set_state(faction: int, state: int) -> void:
	if _state.get(faction, -1) == state:
		return
	_state[faction] = state
	# Отсчёт «застрял» ведётся для текущего дела. Не сбросив его при смене
	# состояния, отряд после успешного набега объявлял себя застрявшим на
	# обратном пути: он и правда стоял, но пока стоял — не шёл.
	_stuck_t[faction] = 0.0
	_last_centre[faction] = _centre_of(faction)
	print("[отряд ИИ] %s: %s" % [FACTIONS.name_of(faction), STATE_NAMES[state]])


## Стоит ли отряд стороны дома. Гарнизон пополняет штат только в этом случае —
## см. `garrison.gd::_reinforce`. У стороны без отряда состояние пустое и
## считается домашним: до появления ИИ ступени «б» пополнение работало всегда,
## и ломать это возвращение к прежнему поведению не должно.
func at_home(faction: int) -> bool:
	return state_of(faction) == State.HOLD


## Что делает отряд стороны прямо сейчас. Для автопроверок и HUD.
func state_of(faction: int) -> int:
	return int(_state.get(faction, State.HOLD))


## Где сейчас якорь строя. Для автопроверок.
func anchor_of(faction: int) -> Vector3:
	return _anchor.get(faction, Vector3.INF)
