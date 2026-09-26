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
const LABOURER := preload("res://scripts/units/labourer.gd")
const UNIT := preload("res://scripts/units/unit.gd")

enum State { HOLD, MARCH, FIGHT, RETURN }

const STATE_NAMES := ["обороняет базу", "идёт в набег", "дерётся", "отходит"]

## Как часто пересматривать обстановку. Чаще не нужно: бойцы и так идут сами,
## а частая смена цели превращает поход в топтание.
const THINK_INTERVAL := 2.0

## Насколько близко отряд должен подойти к точке маршрута, чтобы считать её
## пройденной и перенести якорь на следующую.
##
## Мало намеренно. С двенадцатью метрами отряд «проходил» точки, до которых не
## доходил, — то есть срезал углы маршрута, и срезал их СКВОЗЬ СТЕНЫ: точка
## считалась взятой, пока между ней и отрядом стояла стена зоны людей. Весь
## смысл маршрута в том, чтобы посетить его точки; расстояние по прямой о стенах
## ничего не знает.
##
## Меряем по БЛИЖАЙШЕМУ бойцу, а не по середине строя. Места в строю лежат
## позади якоря (FRONT_GAP), и середина отряда до точки не доходит никогда —
## отряд встал бы перед каждой.
const WAYPOINT_REACHED := 5.0

## И насколько близко должна быть СЕРЕДИНА отряда. Больше первого числа: строй
## растянут, и требовать от середины тех же пяти метров значило бы не проходить
## точки никогда.
const BAND_REACHED := 8.0

## Насколько якорь строя опережает отряд.
##
## Якорь — это точка сбора впереди, а не сама точка маршрута. Разница
## принципиальна: навигация сглаживает путь, и следующий его угол может лежать в
## двухстах метрах по прямому участку. Поставив якорь прямо на угол, я получал
## строй, растянутый через полкарты, и маршрут, который тут же пересчитывался
## заново уже от этого угла — отряд оставался на месте, а якорь прыгал между
## двумя точками.
const LEAD_DISTANCE := 14.0

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
## Восемьсот метров — по решению GDD 10.1: стороны под ИИ обязаны сталкиваться
## друг с другом сами, а рычаг для этого — радиус набега, а НЕ расстояние между
## базами (география карты проверена автотестами Этапа 1, двигать её рискованно,
## радиус же и так подлежит калибровке по playtest).
##
## Откуда именно восемьсот. Имущество есть только у злодея, и мерить надо до
## него:
##
##   эльфы  -> форт злодея        596 м
##   эльфы  -> середина маршрута  688 м
##   эльфы  -> шахта злодея       789 м
##   стража -> форт злодея        805 м
##   стража -> шахта злодея      1047 м
##
## При восьмистах эльфы достают до ВСЕГО хозяйства злодея, включая шахту и
## маршрут каравана, — это ровно то, чего просит GDD 10.1 и что там же названо
## их занятием. Стража остаётся в пяти метрах снаружи, и это сознательно:
## иначе злодея под ИИ прессуют с двух сторон разом, а решение прямо запрещает
## выбивать сторону подчистую без человека.
##
## Оговорка к решению. GDD 10.1 просила достать до маршрута и шахты, «а не
## обязательно до самой вражеской базы». Геометрически это невыполнимо: шахта
## ДАЛЬШЕ от эльфов, чем форт (789 против 596), и любой радиус, достающий до
## шахты, накрывает и форт. Ограничитель на постройки сторон под ИИ стоял здесь
## некоторое время и снят по решению: разрушать можно ВСЕ здания, и стороне под
## ИИ полагается защищать своё самой, а не правилом.
##
## Прежнее значение было 420 и выбиралось из обратного соображения: чтобы базы
## были вне досягаемости и ИИ не ходил к чужому спавну с первой секунды. Само
## это свойство сохраняется: чужие точки появления целями не бывают вовсе,
## в `_pick_target()` их нет по построению.
const RAID_RANGE := 800.0

## Отряд считается застрявшим, если за столько секунд похода его середина не
## сдвинулась на STUCK_STEP метров. Тогда набег отменяется.
##
## Это страховка, а не механика: путь по карте отряд получает от навигации
## (`navigation.gd`). Но в сетке нет деревьев — лес появляется и исчезает по
## мере приближения игроков, — да и вплотную друг к другу бойцы толкаются.
## Лучше вернуться домой, чем стоять у ствола до конца партии.
## Два метра — это «ползёт в обход», а не «стоит»: отряд, обходящий препятствие,
## движется медленно, и записывать его в застрявшие нельзя.
const STUCK_SECONDS := 24.0
const STUCK_STEP := 2.0

var _route := {}
var _stuck_t := {}
var _last_centre := {}
## Едущая цель, за которой сейчас идёт отряд, по сторонам. Неподвижную цель
## запоминать незачем: она никуда не денется.
var _cart := {}

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


## Якорь строя СТОИТ НА ТЕКУЩЕЙ ТОЧКЕ МАРШРУТА и переходит к следующей, только
## когда отряд до неё дошёл.
##
## Раньше якорь полз к цели сам, со своей скоростью, а отряд шёл за ним. Это
## ломалось каждый раз одинаково: якорь идёт по сетке и обходит препятствие, а
## бойцы срезают угол к своему месту в строю и упираются в него лбом. Пока они
## обходили, якорь уезжал, и приходилось вводить допуск отставания — после чего
## якорь замирал, ждал, место в строю переставало двигаться, и обходить
## становилось некуда. Любой допуск лишь переносил место затыка дальше по
## карте: 60 метров до цели, потом 36.
##
## Теперь оторваться он не может по построению: пока отряд не подошёл к точке,
## следующей точки просто нет.
func _move_anchors(_delta: float) -> void:
	for faction in _anchor.keys():
		var route: Array = _route.get(faction, [])
		var centre := _band_point(faction)
		# Точку проходит ОТРЯД, а не разведчик. Пока хватало одного ближайшего
		# бойца, вырвавшийся вперёд засчитывал точку за всех: якорь прыгал
		# дальше, маршрут пересчитывался от оставшихся позади — и так по кругу.
		# Отряд злодея так и толкся в собственных воротах, наматывая километры
		# на месте.
		while not route.is_empty() and _band_passed(faction, centre, route[0]):
			route.remove_at(0)
		_route[faction] = route

		# Якорь — на поводке впереди отряда, ВДОЛЬ МАРШРУТА.
		#
		# Раньше он ставился по прямой к следующей точке. На повороте — например
		# в воротах форта злодея — эта прямая уходит в стену, места в строю
		# оказываются внутри камня, и отряд ползёт вдоль неё, застревая снова и
		# снова. Так он за три минуты прошёл 181 метр из трёхсот и пять раз
		# объявлял себя застрявшим.
		var here: Vector3 = _lead_along(centre, route, _goal.get(faction, _anchor[faction]))
		# Разворот строя берём по НАПРАВЛЕНИЮ МАРШРУТА, а не по прямой от отряда к
		# якорю. На повороте — в воротах — эта прямая смотрит в стену, и места в
		# строю оказываются внутри камня: отряд толчётся у стены, вместо того
		# чтобы пройти проём.
		var course := _route_course(centre, route)
		_anchor[faction] = here
		_command(faction, here, course)


## Насколько близко к точке подошёл ближайший боец отряда.
## Прошёл ли ОТРЯД эту точку маршрута.
##
## Ближайшего бойца недостаточно: вырвавшийся вперёд засчитывал точку за всех,
## якорь прыгал дальше, маршрут пересчитывался от оставшихся позади — и так по
## кругу. Отряд злодея толокся в собственных воротах, наматывая километры на
## месте. Требуем обоих: разведчик подошёл вплотную, а середина строя хотя бы
## подтянулась.
func _band_passed(faction: int, centre: Vector3, point: Vector3) -> bool:
	if not centre.is_finite():
		return _nearest_distance(faction, point) <= WAYPOINT_REACHED
	# Точка считается пройденной, когда отряд рядом с ней, — и неважно, дошёл ли
	# до неё кто-то вплотную.
	#
	# Путь из форта злодея наружу это 56 точек на 599 метров, по десятку метров
	# на отрезок. Требовать, чтобы отряд прицельно посетил каждую, значит не
	# выпустить его из ворот вовсе: он и не выходил, три минуты толкаясь у
	# собственной стены. Точки, оставшиеся позади, надо просто отбрасывать.
	return _flat_distance(centre, point) <= BAND_REACHED


func _nearest_distance(faction: int, point: Vector3) -> float:
	var best := INF
	for unit in _band(faction):
		best = minf(best, _flat_distance(unit.global_position, point))
	return best


## Расстояние по горизонтали. Высота между якорем и отрядом законно расходится
## на подъёмах и спусках, и мерить её вместе с горизонталью значит наказывать
## отряд за рельеф.
func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Середина отряда. Vector3.INF, если отряда нет.
func _centre_of(faction: int) -> Vector3:
	var band := _band(faction)
	if band.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	for unit in band:
		sum += unit.global_position
	return sum / float(band.size())


## Место отряда, годное для навигации.
##
## Арифметическая середина для этого не годится, и это стоило пяти попыток
## выпустить отряд злодея из собственных ворот. Середина — это среднее по
## бойцам, и когда половина отряда прошла проём, а половина ещё нет, она
## приходится РОВНО НА СТЕНУ между ними. Навигация честно цепляет такую точку к
## ближайшему краю сетки — к наружной стороне стены, — и маршрут начинает
## строиться с той стороны, куда отряду ещё только предстоит попасть. Якорь
## уходит в камень, отряд упирается в него лбом и наматывает круги у ворот.
##
## Берём позицию бойца, ближайшего к середине. Боец — тело с формой
## столкновения, внутри стены он оказаться не может, и потому его место всегда
## законно для навигации.
func _band_point(faction: int) -> Vector3:
	var centre := _centre_of(faction)
	if not centre.is_finite():
		return centre
	var best: Vector3 = centre
	var closest := INF
	for unit in _band(faction):
		var gap: float = _flat_distance(unit.global_position, centre)
		if gap < closest:
			closest = gap
			best = unit.global_position
	return best


## Проложить маршрут по карте.
##
## Раньше здесь был список проходов, заданный руками: базы стоят за стенами, а
## якорь шёл к цели по прямой и уводил отряд в стену. Подпорка лечила только те
## препятствия, о которых я знал заранее. Теперь путь спрашивается у навигации
## (`navigation.gd`), и знать заранее ничего не нужно.
##
## Если пути нет — идём напрямую, как раньше. Это не «на всякий случай»: цель
## набега стоит внутри постройки, и попасть в её середину нельзя по определению.
func _set_route(faction: int, target: Vector3) -> void:
	# Путь считаем ОТ ОТРЯДА, а не от якоря: якорь — производная величина, он
	# висит на поводке впереди, и строить маршрут от него значит строить его от
	# точки, где никого нет.
	var here: Vector3 = _band_point(faction)
	if not here.is_finite():
		here = _anchor.get(faction, target)
	var world := get_parent()
	var route := []
	if "navigation" in world:
		var path: PackedVector3Array = world.navigation.path_between(
			here, world.navigation.closest_point(target))
		# Первую точку пропускаем: это проекция того места, где мы и так стоим.
		for i in range(1, path.size()):
			route.append(path[i])
	if route.is_empty():
		route.append(target)
	_route[faction] = route
	_goal[faction] = target
	_stuck_t[faction] = 0.0
	_last_centre[faction] = _centre_of(faction)


## Точка в LEAD_DISTANCE метрах впереди отряда, отмеренных ПО МАРШРУТУ.
##
## Идти надо не «в сторону следующей точки», а по самой ломаной: только так
## поводок остаётся внутри прохода, когда маршрут поворачивает.
func _lead_along(centre: Vector3, route: Array, fallback: Vector3) -> Vector3:
	if route.is_empty():
		return fallback
	if not centre.is_finite():
		return route[0]
	var left := LEAD_DISTANCE
	var from := centre
	for point in route:
		var step: float = _flat_distance(from, point)
		if step >= left:
			var to: Vector3 = point - from
			to.y = 0.0
			if to.length() < 0.01:
				return point
			var lead: Vector3 = from + to.normalized() * left
			# Высоту берём у точки маршрута: её дала навигация, и она на земле.
			lead.y = point.y
			return lead
		left -= step
		from = point
	return from


## Куда смотрит маршрут в том месте, где сейчас отряд.
func _route_course(centre: Vector3, route: Array) -> Vector3:
	if route.is_empty():
		return Vector3.ZERO
	var from: Vector3 = centre if centre.is_finite() else route[0]
	var course: Vector3 = route[0] - from
	course.y = 0.0
	if course.length() < 1.0 and route.size() > 1:
		# Стоим прямо на точке — смотрим на следующую.
		course = route[1] - route[0]
		course.y = 0.0
	return course


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
			else:
				_chase(faction)
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
	_set_state(faction, State.MARCH)
	_set_route(faction, target)
	if fresh:
		_announce_raid(faction, target)


## Подправить маршрут на ходу: цель может ЕХАТЬ.
##
## Караван не стоит на месте, а маршрут прокладывается один раз. Отряд приходил
## туда, где караван БЫЛ: варка показала это прямо — три набега эльфов на зону
## злодея за три минуты и ни одного перехвата.
##
## Заново набег не объявляем: он тот же самый, изменилось только куда идти.
##
## Сторож «застрял» при этом обязан сохраниться. `_set_route()` его сбрасывает,
## а караван уезжает быстрее, чем отряд идёт: пересчёт случался бы почти каждый
## такт, сторож не накопил бы ни секунды, и по-настоящему упёршийся отряд не
## сдался бы никогда. Поэтому вокруг пересчёта его сохраняем.
func _chase(faction: int) -> void:
	# Гонимся ТОЛЬКО за едущей целью. Пересчитывать маршрут к неподвижной
	# постройке незачем, а вредно: целей теперь две — склад и караван, — и
	# «ближайшая» прыгает между ними каждый такт. Отряд качается между двумя
	# точками и не доходит ни до одной. Варка показала это прямо: три набега в
	# зону злодея за пять минут и ни одной разрушенной постройки.
	# БЕЗ ТИПА, и это не небрежность. Освобождённый объект нельзя присвоить
	# типизированной переменной вовсе: движок ругается на самом присваивании, а
	# `is_instance_valid` строкой ниже до дела не доходит. Ровно на это я уже
	# попадался в `labourer.gd` — там проверка стояла внутри функции, а движок
	# ругался на её аргументе.
	#
	# Обоз исчезает не только разбитым: его сносит уборка проверок, смена мира,
	# «новая игра». Ссылка в `_cart` при этом остаётся, и каждый такт мышления
	# ИИ давал строку в лог — четыре сотни за прогон.
	var cart = _cart.get(faction, null)
	if cart == null or not is_instance_valid(cart):
		_cart.erase(faction)
		return
	var target := _intercept_point(faction, cart)
	var goal: Vector3 = _goal.get(faction, Vector3.INF)
	if goal.is_finite() and goal.distance_to(target) <= ARRIVE_RADIUS:
		return
	var stuck: float = _stuck_t.get(faction, 0.0)
	_set_route(faction, target)
	_stuck_t[faction] = stuck


## Куда идти: вражеская постройка, а если такой рядом нет — караван. Постройка
## первой не случайно: она не убегает, и её потеря стоит противнику дороже всего.
## И то и другое ищется только в пределах RAID_RANGE от своей базы.
##
## РАЗОРИТЬ МОЖНО ЛЮБУЮ СТОРОНУ И ВСЕГДА — решение владельца проекта,
## отменяющее прежнюю оговорку GDD 10.1 («у пустующей стороны целями бывают
## только караваны»). Пустующая сторона защищена ровно тем же, чем занятая:
## гарнизоном, отрядом и расстоянием. Проверка «за неё кто-то сидит» здесь стояла
## недолго и снята намеренно — не путать с недосмотром.
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
	var cart: Node = null
	if spawned != null:
		for node in spawned.get_children():
			# Караван узнаём по `path_ahead`: `state_text` есть и у лошади, а
			# гнаться отряду надо за обозом, а не за пасущейся лошадью.
			if not node.has_method("path_ahead") or not ("owner_id" in node):
				continue
			if not _hostile(faction, _side_of(world, node)):
				continue
			if base.distance_to(node.global_position) > RAID_RANGE:
				continue
			var d: float = here.distance_to(node.global_position)
			if d < best_distance:
				best_distance = d
				best = node.global_position
				cart = node
	if cart != null:
		# Не «куда он приехал», а «где мы его встретим».
		_cart[faction] = cart
		return _intercept_point(faction, cart)
	_cart.erase(faction)
	if best != Vector3.INF:
		return best

	# Чужой базы в этом списке нет намеренно. Штурм спавна — это ступень «в»:
	# без экономики и подкреплений отряд из четверых там только раздаст
	# убийства, а игрок получит осаду, которую нечем прекратить.
	return Vector3.INF


## Чья это повозка.
##
## Спрашиваем САМ КАРАВАН, а не владельца-персонажа. Караван стороны под ИИ
## создаётся без владельца (`owner_id` 0), поиск по владельцу возвращал для него
## «стороны нет», а «стороны нет» отряд не трогает никогда — то есть караваны
## ИИ не могли стать целью набега вовсе. Тот же поиск терял и караван игрока,
## который вышел из игры, пока его повозка ещё едет.
func _side_of(world: Node, node: Node) -> int:
	if "faction" in node:
		return int(node.faction)
	return int(world.faction_of(int(node.owner_id)))


## Где ВСТРЕТИТЬ едущую цель.
##
## Караван быстрее пешего отряда, и гнаться за его текущим положением
## бессмысленно: пять минут варки, три набега эльфов в зону злодея и ни одного
## перехвата — отряд всё время шёл туда, где караван уже не был.
##
## Берём его будущий путь и идём по нему вперёд, складывая время каравана до
## каждой точки. Первая точка, к которой отряд успевает раньше него, и есть
## место встречи. Не успеваем нигде — идём к последней: там он разгружается и
## какое-то время стоит, а стоящий караван догнать можно.
##
## Скорость отряда берём базовую, без учёта ранений и строя: это ОЦЕНКА, и
## завышенная точность здесь только создаёт видимость расчёта.
func _intercept_point(faction: int, cart: Node) -> Vector3:
	if not cart.has_method("path_ahead"):
		return cart.global_position
	var ahead: PackedVector3Array = cart.path_ahead()
	if ahead.is_empty():
		return cart.global_position
	var centre: Vector3 = _band_point(faction)
	if not centre.is_finite():
		centre = _anchor.get(faction, cart.global_position)
	var walked: Vector3 = cart.global_position
	var cart_time := 0.0
	var cart_speed: float = maxf(1.0, float(cart.SPEED))
	for point in ahead:
		cart_time += _flat_distance(walked, point) / cart_speed
		walked = point
		var band_time: float = _flat_distance(centre, point) / UNIT.BASE_SPEED
		if band_time <= cart_time:
			return point
	return ahead[ahead.size() - 1]


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
	_set_route(faction, base)


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
	# ВСЕ ЧУЖИЕ ВРАЖДЕБНЫ. Система отношений вырезана по решению автора игры, и
	# вместе с ней исчезло единственное, что делало чужую сторону невраждебной.
	return true


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


## Бойцы отряда: безвладельческие бойцы этой стороны, кроме распорядителя стражи
## и кроме работающих батраков.
##
## Распорядитель в набеги не ходит: он стоит на посту, через него идёт арка
## стражи. Батраки — тем более: они принадлежат стороне и владельца у них тоже
## нет, поэтому без этой проверки отряд уводил бы в набег лесорубов и шахтёров.
## Исключение — ополченец: он для того и ополченец, чтобы драться в общем строю.
func _band(faction: int) -> Array:
	var result := []
	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit) or not ("faction" in unit):
			continue
		if int(unit.faction) != faction or int(unit.owner_id) != 0:
			continue
		if "is_champion" in unit and unit.is_champion:
			continue
		if "sync_role" in unit and int(unit.sync_role) != LABOURER.Role.MILITIA:
			continue
		# Охрана обоза в набеговый отряд НЕ входит: она при деле. Считать её в
		# отряде значило бы, что сторона перестаёт нанимать войско, набрав
		# нужное число охранниками. Ровно так и вышло: отряд «полон» на шести,
		# из них двое едут с повозкой, и казарма простаивает.
		if unit.has_meta("escorting"):
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
	# В ЛОГ, а не на экран: игроку незачем знать, куда пошёл чужой отряд на
	# другом конце карты. Раньше это висело объявлением и было первым, что
	# бросалось в глаза в сборке для тестеров.
	objective.log_event.rpc("Набег: %s → %s" % [
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
