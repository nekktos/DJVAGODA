extends Node
##
## Навигация по карте (Этап 10). Пути для бойцов и отрядов ИИ.
##
## ЗАЧЕМ. До этого всё, что двигалось само, ходило ПО ПРЯМОЙ: `unit.gd` не знал
## о препятствиях вообще. Для отряда живого игрока это терпели с Этапа 6 —
## командир ведёт их сам и обходит стены глазами. Отряду ИИ вести некому, и
## первый же долгий прогон показал итог: стража вышла в набег, упёрлась в стену
## дворца в ста тридцати метрах от базы и простояла там до конца партии.
##
## Обходились это заранее заданными точками прохода, но подпорка лечила только
## те препятствия, о которых я знал заранее. Здесь — настоящий путь по карте.
##
## КАК. Карта строится процедурно (`world_builder.gd`) с фиксированным сидом,
## одинаково на всех пирах. Значит и навигационную сетку можно испечь на месте,
## после стройки, и ничего не реплицировать.
##
## СЧИТАЕТ ТОЛЬКО ХОСТ. Движение бойцов и решения ИИ — его дело, клиент получает
## готовые позиции. Поэтому и печём мы только у хоста: клиенту сетка не нужна, а
## печь её — это секунды на ровном месте.
##
## ПОСТРОЙКИ СЕТКА ЗНАЕТ — и те, что поставлены по ходу партии. Сперва сетку
## пекли один раз, при старте, и новый склад в ней не значился: путь шёл
## сквозь него, а вблизи цели бойцы и вожак ИИ и вовсе шли напрямую. Набор
## «ИИ-снаряжение» поймал вожака злодея, полторы минуты упиравшегося в стену
## собственного склада. Теперь поставленная или снесённая постройка просит
## перепечь сетку (`mark_dirty`), и печётся она в потоке: игра не встаёт.
##
## ЧЕГО СЕТКА НЕ ЗНАЕТ: деревьев. Лес — это MultiMesh с 1700 стволами, из
## которых объёмными в каждый момент лишь те, что рядом с игроками
## (`forest.gd`). Их в сетку не запечь: они появляются и исчезают. Бойцы об них
## по-прежнему спотыкаются — от этого спасает сторож «застрял» в `warband.gd`.
##

## Размер клетки сетки, метры. Карта 1200 на 1200, и это прямо решает, сколько
## печь: при 0.5 клеток вчетверо больше, чем при 1.0. Метр достаточен для
## grey-box из коробок, где узких проходов нет: самый тесный — ворота дворца,
## 34 метра.
const CELL_SIZE := 1.0
const CELL_HEIGHT := 0.5

## Габариты того, кто ходит. Все три величины КРАТНЫ размеру клетки: движок
## округляет их до вокселей сам и на каждое некратное значение ругается в лог.
##
## Радиус — ТРИ метра, а не полметра по капсуле бойца. Путь считается для
## ОТРЯДА: проложенный впритирку к стене, он заставляет строй идти по камню
## боком, и отряд злодея из-за этого не мог выйти из собственных ворот. Три
## метра отодвигают путь от стен и ничего не запирают — проходы на карте
## широкие, самый тесный ворота в 34 метра. Что это так и осталось, стережёт
## проверка «у каждой базы есть дорога наружу» в `--navtest`.
const AGENT_RADIUS := 3.0
const AGENT_HEIGHT := 2.0

## Уступ, на который боец способен взойти. Полклетки по высоте. Ступеньки полосы
## препятствий у спавна начинаются с 0.8 м, шестиметровый уступ плато
## непроходим — и это правильно: наверх ведёт пандус, сетка обязана знать
## именно это.
const AGENT_MAX_CLIMB := 0.5
const AGENT_MAX_SLOPE := 45.0

## Группа, из которой берётся геометрия для выпечки.
const SOURCE_GROUP := "navsource"
## Постройки — отдельной группой: их разбираем при каждой перепечке, а
## неподвижную карту — один раз.
const BUILDING_GROUP := "navbuilding"

## Сколько полигонов поиску разрешено перебрать, прежде чем сдаться.
##
## ЭТО И БЫЛ ТОТ САМЫЙ БЛОКЕР. У Godot здесь умолчание 4096, а в нашей сетке
## 17414 полигонов: карта 1200 на 1200 при клетке в метр. Дойдя до предела, A*
## НЕ возвращает пустой путь — он возвращает путь до лучшего, что успел найти,
## и ответ выглядит совершенно исправным. Молчаливый обрыв и есть причина, по
## которой он прятался месяцами.
##
## Как это выглядело в игре. Эльф просил путь от своего спавна до дворца —
## шестьсот метров по прямой. Поиск успевал расползтись по открытому полю,
## упирался в западную стену плато на x = 117 и отдавал путь туда: «не дошёл
## 183 метра». Ровно от 117 до 300. Короткие запросы при этом проходили
## безупречно — двор стражи до дворца, середина карты до дворца, — и поэтому
## восемь правок рельефа подряд ничего не меняли: рельеф был ни при чём.
##
## Бил он не только по игроку. Живой сеанс дал 442 набега эльфов и 440
## «застрял, набег отменён»: у стороны, чья база дальше всех от чужих, ни один
## длинный путь не укладывался в бюджет, и весь эльфийский ИИ стоял.
##
## Шестьдесят пять тысяч — это заведомо больше, чем полигонов в сетке, то есть
## «без предела». Держим числом, а не нулём: у нуля смысл «без предела» нигде
## не обещан, а лишний полный обход сетки стоит доли миллисекунды.
const SEARCH_BUDGET := 65536

var _region: NavigationRegion3D
var _ready_to_path := false
## Запрос и ответ держим постоянными, а не создаём на каждый путь: за них
## просят десятки раз в секунду, когда идут отряды и обозы.
var _query := NavigationPathQueryParameters3D.new()
var _answer := NavigationPathQueryResult3D.new()

## Своим ярусом считаем точку в пределах трёх метров по высоте: подвал под
## плато ниже пяти, а место в строю над землёй — выше двух.
const LEVEL_TOLERANCE := 3.0
const LEVEL_PROBE_RADII := [6.0, 12.0, 20.0]
const LEVEL_PROBE_ANGLES := 8

## Перепекать не сразу, а через столько секунд после последней перемены:
## распорядитель ИИ ставит постройки пачкой, и печь на каждую незачем.
const REBAKE_DELAY := 2.0
## Когда перепечь; меньше нуля — не нужно.
var _dirty_at := -1.0
## Разобранная неподвижная карта со стволами леса — запоминаем при первой
## выпечке. Разбирать её заново на каждую перепечку значило держать главный
## поток 80-90 мс (замер): полкарты коробок и 1700 временных стволов. Запинка
## в бою на каждую поставленную где-то постройку. Теперь заново разбираются
## одни постройки, а печётся в потоке.
##
## Цена: срубленное после старта дерево остаётся в сетке препятствием до
## конца партии — как и было до перепечки. Ствол узкий, путь его огибает.
var _static_source: NavigationMeshSourceGeometryData3D
## Полигонов в первой выпечке, по карте без поставленных построек. С ним
## сверяются перепечки: потерянный лес уносит треть сетки.
var first_polygons := 0
var _baking := false
## Задача выпечки в пуле потоков; меньше нуля — нет.
var _task := -1
## Сколько раз испечённая сетка ВОШЛА В ДЕЛО. По нему автопроверки ждут
## перепечки. Считаем не конец выпечки, а следующую итерацию карты: сервер
## навигации подхватывает сетку сам и не сразу, и путь, спрошенный в тот же
## кадр, шёл ещё по старой — проверка обхода постройки падала через раз.
var bakes := 0
## Номер итерации карты на конец выпечки; меньше нуля — ждать нечего.
var _baked_at_iteration := -1
## Сколько последняя перепечка держала главный поток: разбор построек идёт в
## нём, в потоке — сама выпечка.
var _stall_ms := 0


## Испечь сетку по уже построенной карте. Зовёт `world.gd` сразу после
## `WorldBuilder.build()` — раньше нечего печь, позже незачем ждать.
func bake(terrain: Node3D) -> void:
	if not Net.hosting():
		return
	if terrain == null:
		push_error("Навигация: карты нет, печь нечего")
		return
	terrain.add_to_group(SOURCE_GROUP)
	var mesh := _new_mesh(SOURCE_GROUP)

	_region = NavigationRegion3D.new()
	_region.name = "NavRegion"
	add_child(_region)

	var started := Time.get_ticks_msec()
	# Печём СИНХРОННО. В потоке было бы вежливее, но тогда первые секунды партии
	# ИИ ходил бы без сетки, а автопроверки стали бы зависеть от того, успел ли
	# поток. Мир строится один раз при входе в сессию — там эта пауза уместна.
	_static_source = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, _static_source, terrain)
	var first := NavigationMeshSourceGeometryData3D.new()
	first.merge(_static_source)
	first.merge(_parse_buildings())
	NavigationServer3D.bake_from_source_geometry_data(mesh, first)
	_region.navigation_mesh = mesh
	first_polygons = mesh.get_polygon_count()
	_on_bake_finished()
	# Сетка испечена, но сервер навигации регистрирует область и синхронизирует
	# карту в конце кадра. Спросить путь раньше — получить ошибку «запрос до
	# первой синхронизации»; ловится это только тем, кто спрашивает путь в
	# первом же кадре, как батраки на старте партии. Ждём кадр и лишь потом
	# объявляем себя готовыми: до этого `path_between` честно возвращает
	# пустой путь, а бойцы идут напрямую.
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(_region.get_navigation_map())
	_ready_to_path = true
	print("[навигация] сетка испечена за %d мс, полигонов %d"
		% [Time.get_ticks_msec() - started, mesh.get_polygon_count()])


## Постройка встала или снесена — перепечь сетку чуть погодя.
func mark_dirty() -> void:
	if not Net.hosting() or _region == null:
		return
	_dirty_at = Time.get_ticks_msec() / 1000.0 + REBAKE_DELAY


## Сетка с нашими настройками, пустая.
func _new_mesh(group: String) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = CELL_HEIGHT
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = AGENT_MAX_CLIMB
	mesh.agent_max_slope = AGENT_MAX_SLOPE
	# Берём КОЛЛИЗИЮ, а не видимые меши. Это не мелочь: у дерева и коробки
	# ресурса меш есть, а собирать по мешам значит запечь заодно дорожную
	# разметку и прочую плоскую мишуру.
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = group
	return mesh


## Разобрать постройки: их коробки и препятствия (`building.gd`).
func _parse_buildings() -> NavigationMeshSourceGeometryData3D:
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_new_mesh(BUILDING_GROUP), data, self)
	return data


func _process(_delta: float) -> void:
	if _baked_at_iteration >= 0 and _region != null:
		var map := _region.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(map) > _baked_at_iteration:
			_baked_at_iteration = -1
			bakes += 1
	if _dirty_at < 0.0 or _region == null or _baking:
		return
	if Time.get_ticks_msec() / 1000.0 < _dirty_at:
		return
	_dirty_at = -1.0
	var started := Time.get_ticks_usec()
	var data := NavigationMeshSourceGeometryData3D.new()
	data.merge(_static_source)
	data.merge(_parse_buildings())
	# Печём в НОВУЮ сетку: старая остаётся в деле, пока новая не готова.
	var fresh := _new_mesh(SOURCE_GROUP)
	_baking = true
	# Печём СВОЕЙ задачей в пуле потоков, а не `..._async`: обратный вызов
	# той приходит через главный поток, и дождаться её на выходе нельзя —
	# полный прогон падал в Godot на выходе, если ИИ-эльф ставил дом за секунду
	# до конца набора. Свою задачу `_exit_tree` дожидается честно.
	# Через слабую ссылку — чтобы задача не держала узел.
	var me: WeakRef = weakref(self)
	_task = WorkerThreadPool.add_task(func() -> void:
		NavigationServer3D.bake_from_source_geometry_data(fresh, data)
		var nav: Object = me.get_ref()
		if nav != null:
			nav.call_deferred("_apply_rebake", fresh))
	_stall_ms = (Time.get_ticks_usec() - started) / 1000


## Выйти посреди выпечки нельзя: поток доделает сетку и позовёт обратно, а
## движок к тому времени погасит сервер навигации. Полный прогон так и упал —
## ИИ-эльф поставил дом за секунду до конца набора, и Godot вылетел на выходе.
## Ждём выпечку: это меньше секунды и только на выходе.
func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _apply_rebake(fresh: NavigationMesh) -> void:
	_baking = false
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	if _region == null:
		return
	_region.navigation_mesh = fresh
	_on_bake_finished()


func _on_bake_finished() -> void:
	_baked_at_iteration = NavigationServer3D.map_get_iteration_id(_region.get_navigation_map())
	if bakes > 0:
		print("[навигация] сетка перепечена, полигонов %d, главный поток занят %d мс"
			% [_region.navigation_mesh.get_polygon_count(), _stall_ms])


## Нечего перепекать, ничего не печётся и испечённое уже в деле.
func settled() -> bool:
	return (_region != null and _dirty_at < 0.0 and not _baking
		and _baked_at_iteration < 0)


func polygon_count() -> int:
	if _region == null or _region.navigation_mesh == null:
		return 0
	return _region.navigation_mesh.get_polygon_count()


## Путь от точки до точки по карте. Пустой массив — идти некуда: либо сетки
## нет, либо цель за пределами проходимого.
##
## Первая точка пути — проекция начала на сетку, поэтому вызывающий её обычно
## пропускает: идти к тому месту, где стоишь, незачем.
func path_between(from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := _live_map()
	if not map.is_valid():
		return PackedVector3Array()
	# Не `map_get_path`: тот ходит с умолчаниями, а среди них предел поиска в
	# 4096 полигонов (см. SEARCH_BUDGET). Спрашиваем своим запросом.
	_query.map = map
	_query.start_position = from
	_query.target_position = to
	# Сглаживание коридора — ровно то, что делал `map_get_path(..., true)`:
	# путь по срезанным углам, а не по серединам полигонов.
	_query.path_postprocessing = (NavigationPathQueryParameters3D
		.PATH_POSTPROCESSING_CORRIDORFUNNEL)
	_query.path_search_max_polygons = SEARCH_BUDGET
	NavigationServer3D.query_path(_query, _answer)
	return _answer.path


## Карта, у которой уже прошла хотя бы одна синхронизация.
##
## Проверять свой флаг «испекли» недостаточно: сервер навигации регистрирует
## область и считает первую итерацию карты сам, в конце кадра, и любой запрос до
## этого валится с ошибкой. Спрашиваем номер итерации — это единственный
## надёжный признак, и он же назван в самом сообщении об ошибке.
func _live_map() -> RID:
	if not _ready_to_path or _region == null:
		return RID()
	var map := _region.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return RID()
	return map


## Есть ли вообще сетка. Автопроверки и вызывающие код отличают «пути нет» от
## «навигация не работает».
func is_ready() -> bool:
	return _live_map().is_valid()


## Ближайшая проходимая точка к заданной. Нужна, когда цель стоит вплотную к
## стене или внутри постройки: путь в саму цель не проложится, а к её краю —
## вполне.
##
## БЛИЖАЙШАЯ ПО ПРЯМОЙ — НЕ ВСЕГДА ТА. Плато дворца полое, и под его верхом
## сетка печёт недоступный подвал. Склад стражи стоит на плато и вырезан из
## сетки (`building.gd`): до верха плато от его середины девять метров вбок, до
## подвала — пять вниз, и «ближайшей» выходила точка в подвале. Путь оттуда
## упирался в стену: обоз стражи доезжал до подножия плато, за двести
## шестьдесят метров от шахты, и «грузить нечего». Поэтому, если ближайшая
## точка на другом ярусе, ищем ещё кольцами вокруг и берём ту, что на своём.
func closest_point(to: Vector3) -> Vector3:
	var map := _live_map()
	if not map.is_valid():
		return to
	var best: Vector3 = NavigationServer3D.map_get_closest_point(map, to)
	# Только когда найденная точка заметно НИЖЕ: подвал. Цель, висящая над
	# землёй (место в строю за прыгнувшим командиром), сюда не попадает — иначе
	# на холмах боец уходил к точке на пригорке в шести метрах от своей, и
	# набор «отряд» поймал колонну шириной в девять метров вместо четырёх.
	if to.y - best.y <= LEVEL_TOLERANCE:
		return best
	var nearest := INF
	var level := best
	for radius in LEVEL_PROBE_RADII:
		for i in LEVEL_PROBE_ANGLES:
			var angle := TAU * float(i) / float(LEVEL_PROBE_ANGLES)
			var probe := to + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var point: Vector3 = NavigationServer3D.map_get_closest_point(map, probe)
			if absf(point.y - to.y) > LEVEL_TOLERANCE:
				continue
			var gap: float = Vector2(point.x - to.x, point.z - to.z).length()
			if gap < nearest:
				nearest = gap
				level = point
	return level
