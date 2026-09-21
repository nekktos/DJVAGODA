extends "res://tools/test_base.gd"
##
## Автопроверка навигации (Этап 10). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --navtest
##
## Проверяем не «сетка испеклась», а то, ради чего она нужна: что путь ОБХОДИТ
## препятствия, о которых прямое движение не знало. Мест таких на карте два, и
## оба поймал живой прогон ИИ: стена дворца с единственным проёмом и
## шестиметровый уступ плато, наверх с которого ведёт один пандус.
##
## Ловушка, из-за которой такую проверку легко написать бесполезной: путь между
## двумя точками почти всегда непустой, потому что навигация вернёт хоть
## что-нибудь. Поэтому смотрим на ДЛИНУ пути против прямой и на то, через какие
## точки он проходит, — а не на факт его существования.
##

const FACTIONS := preload("res://scripts/factions.gd")
const BUILDER := preload("res://scripts/world_builder.gd")

## Центр дворца: точка захвата, вокруг неё стена с проёмом на юге.
const PALACE := Vector3(300.0, 6.0, -300.0)
## Подножие пандуса на плато императора (см. world_builder::_build_emperor).
const RAMP_FOOT := Vector3(300.0, 0.0, -75.0)
## Проём в южной стене дворца: единственный выход с базы стражи наружу.
const PALACE_GATE := Vector3(300.0, 6.0, -170.0)

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "навигация"
	expected_host = 15
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout

	_test_baked()
	_test_budget_covers_the_mesh()
	_test_leaves_plateau()
	_test_enters_palace()
	_test_every_base_has_a_way_out()
	_test_open_ground_is_straight()
	_test_unreachable()
	finish()


func _nav() -> Node:
	return _world.navigation


## Сетка есть. Без неё всё остальное бессмысленно, поэтому дальше не идём.
func _test_baked() -> void:
	check(_nav().is_ready(), "сетка испечена", "готова=%s" % _nav().is_ready())


## Бюджет поиска больше, чем полигонов в сетке.
##
## СТОРОЖ ЗА НАЙДЕННЫМ БЛОКЕРОМ. У Godot предел поиска по умолчанию 4096
## полигонов, а в нашей сетке их 17414. Превысив предел, A* не признаётся —
## он отдаёт путь до лучшего, что успел найти, и ответ неотличим от честного.
## Эльфы из-за этого не могли дойти до дворца, а их ИИ сорвал 440 набегов из
## 442, и всё это выглядело как ошибка рельефа.
##
## Проверка сравнивает бюджет с РАЗМЕРОМ сетки, а не с числом: карта ещё будет
## расти, и тогда предел надо поднять снова. Молча это не должно пройти.
func _test_budget_covers_the_mesh() -> void:
	var region: NavigationRegion3D = _nav().get_node_or_null("NavRegion")
	check(region != null, "область навигации на месте", "NavRegion не найден")
	if region == null:
		return
	var polys: int = region.navigation_mesh.get_polygon_count()
	var budget: int = _nav().SEARCH_BUDGET
	check(budget > polys, "бюджет поиска пути покрывает всю сетку",
		"полигонов %d, бюджет %d — длинные пути будут обрываться молча"
			% [polys, budget])


## Спуск с плато. Прямая от базы стражи к базе злодея идёт сквозь стену дворца и
## с шестиметрового обрыва; настоящий путь обязан быть заметно длиннее и пройти
## мимо пандуса.
func _test_leaves_plateau() -> void:
	var from: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.GUARD]
	var to: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]
	var path: PackedVector3Array = _nav().path_between(from, to)
	check(path.size() >= 2, "путь с базы стражи к базе злодея найден",
		"точек %d" % path.size())
	if path.size() < 2:
		return

	var straight: float = from.distance_to(to)
	var walked := _length(path)
	check(walked > straight * 1.05, "путь длиннее прямой — значит, что-то обходит",
		"%.0f м против %.0f м по прямой" % [walked, straight])

	check(_passes_near(path, RAMP_FOOT, 45.0), "путь проходит через пандус",
		"ближе всего к подножию: %.0f м" % _closest_to(path, RAMP_FOOT))

	# База стражи стоит ВНУТРИ стен дворца, и наружу ведёт один проём. Если путь
	# мимо него не проходит — значит, он идёт сквозь стену.
	#
	# Длину отрезков для этого проверять бесполезно, и я сначала попробовал
	# именно так: навигация сглаживает путь, и прямой участок через чистое поле
	# честно приходит одним отрезком в триста метров. Длинный отрезок ничего не
	# говорит о том, сквозь что он идёт.
	check(_passes_near(path, PALACE_GATE, 40.0), "путь выходит через проём в стене",
		"ближе всего к воротам: %.0f м" % _closest_to(path, PALACE_GATE))


## Вход во дворец. Точка захвата в середине двора, стена с проёмом на юге —
## прямой путь снаружи внутрь невозможен.
func _test_enters_palace() -> void:
	var from := Vector3(300.0, 6.0, -200.0)
	var path: PackedVector3Array = _nav().path_between(from, PALACE)
	check(path.size() >= 2, "путь внутрь дворца найден", "точек %d" % path.size())
	if path.size() < 2:
		return
	var last: Vector3 = path[path.size() - 1]
	check(Vector2(last.x, last.z).distance_to(Vector2(PALACE.x, PALACE.z)) < 25.0,
		"путь доводит до точки захвата", "конец в %.0f м от центра"
		% Vector2(last.x, last.z).distance_to(Vector2(PALACE.x, PALACE.z)))


## У КАЖДОЙ базы должен быть выход наружу.
##
## Проверка появилась после того, как отряд злодея три минуты не мог выйти из
## собственного форта. Базы стоят за стенами, и «путь есть» тут не риторика: если
## навигация не находит дороги с базы к середине карты, сторона заперта, и
## сколько ни чини поведение отряда, он не выйдет.
func _test_every_base_has_a_way_out() -> void:
	var centre := Vector3(0.0, 0.0, 0.0)
	for faction in FACTIONS.COUNT:
		var base: Vector3 = FACTIONS.SPAWN[faction]
		var path: PackedVector3Array = _nav().path_between(base, centre)
		var length := _length(path)
		var straight: float = base.distance_to(centre)
		check(path.size() >= 2 and length < straight * 3.0,
			"%s: с базы есть дорога наружу" % FACTIONS.name_of(faction),
			"%d точек, %.0f м против %.0f по прямой" % [path.size(), length, straight])


## На чистом поле путь обязан быть прямым. Иначе бойцы будут наматывать круги
## там, где раньше шли напрямую, и это стоило бы дороже, чем решало.
func _test_open_ground_is_straight() -> void:
	var from := Vector3(-100.0, 0.0, 100.0)
	var to := Vector3(100.0, 0.0, 100.0)
	var path: PackedVector3Array = _nav().path_between(from, to)
	if path.size() < 2:
		fail("на открытом поле пути нет — сетка дырявая")
		return
	var straight: float = from.distance_to(to)
	check(_length(path) < straight * 1.2, "на открытом поле путь почти прямой",
		"%.0f м против %.0f м" % [_length(path), straight])


## Цель внутри камня. Путь туда не проложится, и вызывающий должен уметь спросить
## ближайшую проходимую точку вместо неё.
func _test_unreachable() -> void:
	var inside := Vector3(300.0, 30.0, -300.0)     # внутри стен дворца, высоко
	var near: Vector3 = _nav().closest_point(inside)
	check(near.distance_to(inside) > 0.5, "для недостижимой точки есть проходимая рядом",
		"смещение %.0f м" % near.distance_to(inside))
	var path: PackedVector3Array = _nav().path_between(Vector3(0.0, 0.0, 0.0), near)
	check(path.size() >= 2, "к ней прокладывается путь", "точек %d" % path.size())


func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _max_step(path: PackedVector3Array) -> float:
	var longest := 0.0
	for i in range(1, path.size()):
		longest = maxf(longest, path[i - 1].distance_to(path[i]))
	return longest


func _closest_to(path: PackedVector3Array, point: Vector3) -> float:
	var best := INF
	for node in path:
		best = minf(best, Vector2(node.x, node.z).distance_to(Vector2(point.x, point.z)))
	return best


func _passes_near(path: PackedVector3Array, point: Vector3, radius: float) -> bool:
	return _closest_to(path, point) <= radius
