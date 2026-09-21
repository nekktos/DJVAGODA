extends "res://tools/test_base.gd"
##
## Вскрытие навигационной сетки: где она рвётся и где движок ругается на рёбра.
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --navdump
##
## ЗАЧЕМ. Эльф не может дойти до дворца, и восемь правок рельефа подряд ничего
## не изменили. Все они лечили догадку. Этот инструмент не гадает: он берёт уже
## испечённую сетку и разбирает её на полигоны и рёбра сам, не спрашивая
## NavigationServer — потому что именно ответ сервера («пути нет») и есть то,
## что надо объяснить.
##
## ЗА ЧТО ЗАЦЕПИЛИСЬ. В логе каждого прогона висит:
##
##   Navigation region synchronization had 2 edge error(s). This causes a
##   logical error in the navigation mesh geometry and is commonly caused by
##   overlap or too densely placed edges.
##
## «Edge error» в Godot — это ребро, за которое держатся БОЛЬШЕ ДВУХ полигонов.
## У исправной сетки ребро либо внутреннее (ровно два соседа), либо граничное
## (один). Три и больше — место, где геометрия налезла сама на себя, и сшивать
## там нечего. Найти такие рёбра можно перебором, и их координаты — это адрес
## поломки, а не догадка о ней.
##
## ЧТО СЧИТАЕТСЯ. Два разных вопроса, и путать их нельзя:
##
##   1. РЁБРА-ОШИБКИ — сколько рёбер с числом хозяев не 1 и не 2, и где они.
##      Это ровно то, на что ругается движок; числа должны сойтись.
##   2. СВЯЗНОСТЬ — на сколько несоединённых кусков распадается сетка и в каких
##      кусках лежат спавн эльфа, двор стражи и дворец. Если эльф и дворец в
##      РАЗНЫХ кусках, то никакие настройки агента не помогут: пути нет в самой
##      сетке, и лечить надо геометрию.
##

const OBJECTIVE := preload("res://scripts/objective.gd")
const FACTIONS := preload("res://scripts/factions.gd")

## Точность склейки вершин при поиске рёбер, метры.
##
## Полигоны Recast ссылаются на общий список вершин, но координаты хранятся
## float, и после пересчётов две «одинаковые» вершины могут разойтись на
## тысячные. Округляем до сантиметра: мельче — развалим исправные рёбра на
## мнимые границы, крупнее — склеим соседние клетки сетки (клетка метр).
const WELD := 0.01

## Интересные точки карты: между ними и рвётся путь.
##
## ВЫСОТЫ БЕРЁМ У ИГРЫ, А НЕ ПИШЕМ РУКОЙ. Первая версия этого щупа задавала все
## точки с нулевой высотой, и разбор бодро доложил, что сервер сажает дворец
## внутрь шестиметровой скалы. Так и было — но спрашивал так только щуп; игра
## хранит дворец на высоте 6. Проверка, которая сама придумала себе входные
## данные, отвечает про себя, а не про игру.
var _spots := {}


func _fill_spots() -> void:
	_spots = {
		"спавн эльфа": _world.local_player().global_position,
		"дворец": OBJECTIVE.PALACE,
		"двор стражи": Vector3(300.0, 6.0, -240.0),
		"кромка плато": Vector3(300.0, 6.0, -131.0),
		"низ пандуса": Vector3(300.0, 0.0, -60.0),
		"середина карты": Vector3(0.0, 0.0, 0.0),
		"дворец ровно на сетке": Vector3(300.0, 6.9, -300.0),
		"дворец повыше": Vector3(300.0, 12.0, -300.0),
	}

var _world: Node3D
var _parent: PackedInt32Array = PackedInt32Array()


func start(world: Node3D) -> void:
	tag = "разбор сетки"
	expected_host = 2
	expected_client = 0
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout

	if _world.local_player() == null:
		fail("персонаж не заспавнен")
		finish()
		return
	_fill_spots()

	var mesh := _mesh()
	if mesh == null:
		fail("сетки нет — печь было нечего")
		finish()
		return

	var verts := mesh.get_vertices()
	var polys := mesh.get_polygon_count()
	note("вершин %d, полигонов %d" % [verts.size(), polys])

	var owners := _edge_owners(mesh, verts, polys)
	_report_edge_errors(owners, polys)
	_report_components(owners, mesh, verts, polys)
	finish()


func _mesh() -> NavigationMesh:
	var region: NavigationRegion3D = _world.navigation.get_node_or_null("NavRegion")
	if region == null:
		return null
	return region.navigation_mesh


## Кто держится за каждое ребро. Ключ — пара округлённых вершин, значение —
## номера полигонов.
func _edge_owners(mesh: NavigationMesh, verts: PackedVector3Array,
		polys: int) -> Dictionary:
	var owners := {}
	for p in polys:
		var poly := mesh.get_polygon(p)
		var n := poly.size()
		for i in n:
			var a: Vector3 = verts[poly[i]]
			var b: Vector3 = verts[poly[(i + 1) % n]]
			var key := _edge_key(a, b)
			if owners.has(key):
				owners[key].append(p)
			else:
				owners[key] = [p]
	return owners


## Ключ ребра. Вершины СОРТИРУЕМ: ребро A→B и B→A у соседних полигонов — одно и
## то же ребро, и только так они и найдут друг друга.
func _edge_key(a: Vector3, b: Vector3) -> String:
	var one := _pin(a)
	var two := _pin(b)
	if one > two:
		var swap := one
		one = two
		two = swap
	return one + "|" + two


func _pin(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x / WELD), roundi(v.y / WELD), roundi(v.z / WELD)]


## Рёбра, за которые держатся больше двух полигонов. Это и есть «edge error».
func _report_edge_errors(owners: Dictionary, polys: int) -> void:
	var bad := []
	var border := 0
	var inner := 0
	for key in owners:
		var count: int = owners[key].size()
		if count == 1:
			border += 1
		elif count == 2:
			inner += 1
		else:
			bad.append([key, count])
	note("рёбер: внутренних %d, граничных %d, с ошибкой %d"
		% [inner, border, bad.size()])
	for entry in bad:
		note("  ошибка: ребро %s держат %d полигонов" % [entry[0], entry[1]])
	check(bad.is_empty(), "в сетке нет рёбер с тремя и более хозяевами",
		"таких рёбер %d" % bad.size())


## На сколько несвязанных кусков распадается сетка и кто в каком лежит.
func _report_components(owners: Dictionary, mesh: NavigationMesh,
		verts: PackedVector3Array, polys: int) -> void:
	_parent.resize(polys)
	for p in polys:
		_parent[p] = p
	for key in owners:
		var list: Array = owners[key]
		# Рёбра-ошибки в объединении НЕ участвуют: именно их движок и не
		# сшивает. Считать их проходимыми значит нарисовать связность,
		# которой у сервера нет.
		if list.size() != 2:
			continue
		_union(int(list[0]), int(list[1]))

	var sizes := {}
	for p in polys:
		var root := _find(p)
		sizes[root] = int(sizes.get(root, 0)) + 1
	note("несвязанных кусков сетки: %d" % sizes.size())

	var centers := _centroids(mesh, verts, polys)
	var big := sizes.keys()
	big.sort_custom(func(a, b): return int(sizes[a]) > int(sizes[b]))
	var bounds := {}
	for p in polys:
		var root := _find(p)
		var c: Vector3 = centers[p]
		if bounds.has(root):
			bounds[root] = bounds[root].expand(c)
		else:
			bounds[root] = AABB(c, Vector3.ZERO)
	# Размер и МЕСТО каждого куска. Без места число полигонов ничего не
	# говорит: «кусок на 3012 полигонов» — это плато или полкарты?
	for i in mini(8, big.size()):
		var root: int = int(big[i])
		var box: AABB = bounds[root]
		var mid := box.get_center()
		note("  кусок #%d: полигонов %5d, центр (%.0f, %.1f, %.0f), размах %.0f x %.0f, высоты %.1f..%.1f"
			% [i + 1, int(sizes[root]), mid.x, mid.y, mid.z,
				box.size.x, box.size.z, box.position.y, box.position.y + box.size.y])

	var where := {}
	for label in _spots:
		# Спрашиваем ТАК ЖЕ, КАК ИГРА: сперва у сервера, куда он сажает эту
		# точку на сетку, и только потом ищем полигон. Свой поиск «ближайший
		# по горизонтали» однажды уже соврал — выбрал крышу дворца на высоте
		# 33 вместо пола во дворе на высоте 7.
		var on_mesh: Vector3 = _world.navigation.closest_point(_spots[label])
		var near := _nearest_poly(centers, on_mesh)
		if near < 0:
			note("%s: сетки рядом нет" % label)
			continue
		var root := _find(near)
		where[label] = root
		note("%s: сервер сажает в (%.0f, %.1f, %.0f), это кусок %d (полигонов %d)"
			% [label, on_mesh.x, on_mesh.y, on_mesh.z, root, int(sizes[root])])

	# Где обрывается настоящий путь и в каком он куске. Это и есть связь между
	# разбором и жалобой: набор «проходимость» говорит «не дошёл 183 м», а
	# здесь видно, во что упёрлись.
	# Маршрут по ОТРЕЗКАМ. Целиком он не считается, и пока не разложишь его на
	# куски, не видно, какое именно звено рвётся.
	for pair in [
			["спавн эльфа", "низ пандуса"],
			["низ пандуса", "кромка плато"],
			["кромка плато", "двор стражи"],
			["двор стражи", "дворец"],
			["кромка плато", "дворец"],
			["спавн эльфа", "кромка плато"],
			["спавн эльфа", "двор стражи"],
			["середина карты", "дворец"],
			["спавн эльфа", "дворец ровно на сетке"],
			["спавн эльфа", "дворец повыше"],
		]:
		_trace_path(centers, sizes, pair[0], pair[1])
	_trace_path(centers, sizes, "спавн эльфа", "дворец", true)

	_report_around(centers, sizes, OBJECTIVE.PALACE, 70.0)
	if big.size() >= 2:
		_report_stacking(centers, int(big[0]), int(big[1]))

	var elf: int = int(where.get("спавн эльфа", -1))
	var palace: int = int(where.get("дворец", -2))
	check(elf == palace, "спавн эльфа и дворец в одном куске сетки",
		"эльф в куске %d, дворец в %d — пути между ними нет ФИЗИЧЕСКИ"
			% [elf, palace])


func _centroids(mesh: NavigationMesh, verts: PackedVector3Array,
		polys: int) -> Array:
	var out := []
	out.resize(polys)
	for p in polys:
		var poly := mesh.get_polygon(p)
		var sum := Vector3.ZERO
		for index in poly:
			sum += verts[index]
		out[p] = sum / float(maxi(1, poly.size()))
	return out


## Ближайший полигон к точке. По ТРЁМ ОСЯМ — но точку сюда передают уже
## посаженную на сетку сервером, а не сырой ориентир с нулевой высотой.
func _nearest_poly(centers: Array, to: Vector3) -> int:
	var best := -1
	var best_gap := INF
	for p in centers.size():
		var gap: float = centers[p].distance_squared_to(to)
		if gap < best_gap:
			best_gap = gap
			best = p
	return best


func _find(p: int) -> int:
	while _parent[p] != p:
		_parent[p] = _parent[_parent[p]]
		p = _parent[p]
	return p


func _union(a: int, b: int) -> void:
	var ra := _find(a)
	var rb := _find(b)
	if ra != rb:
		_parent[ra] = rb


## Что за сетка лежит ВОКРУГ точки и каким кускам она принадлежит.
##
## Один «ближайший полигон» врёт: он может оказаться случайным пятачком внутри
## стены. Нужна картина — сколько сетки вокруг и на сколько кусков она разбита.
func _report_around(centers: Array, sizes: Dictionary, at: Vector3,
		radius: float) -> void:
	var by_island := {}
	for p in centers.size():
		var c: Vector3 = centers[p]
		if Vector2(c.x, c.z).distance_to(Vector2(at.x, at.z)) > radius:
			continue
		var root := _find(p)
		by_island[root] = int(by_island.get(root, 0)) + 1
	note("вокруг дворца в %.0f м: полигонов %d, кусков %d"
		% [radius, _sum(by_island), by_island.size()])
	var keys := by_island.keys()
	keys.sort_custom(func(a, b): return int(by_island[a]) > int(by_island[b]))
	for i in mini(7, keys.size()):
		var root: int = int(keys[i])
		var box := AABB()
		var first := true
		for p in centers.size():
			if _find(p) != root:
				continue
			var c: Vector3 = centers[p]
			if Vector2(c.x, c.z).distance_to(Vector2(at.x, at.z)) > radius:
				continue
			if first:
				box = AABB(c, Vector3.ZERO)
				first = false
			else:
				box = box.expand(c)
		var mid := box.get_center()
		note("  кусок %d: рядом %d, всего %d, центр (%.0f, %.1f, %.0f), размах %.0f x %.0f"
			% [root, int(by_island[root]), int(sizes.get(root, 0)),
				mid.x, mid.y, mid.z, box.size.x, box.size.z])


## Лежат ли куски ДРУГ НА ДРУГЕ.
##
## Два несвязанных куска, накрывающих одну и ту же площадь, — это не дырка в
## сетке, а два пола: геометрию запекли дважды, и Recast развёл слои по высоте.
## Ищем это прямо: берём полигоны большого куска и смотрим, есть ли у второго
## куска полигон на том же месте по горизонтали.
func _report_stacking(centers: Array, one: int, two: int) -> void:
	var grid := {}
	for p in centers.size():
		if _find(p) != one:
			continue
		var c: Vector3 = centers[p]
		grid["%d,%d" % [roundi(c.x / 4.0), roundi(c.z / 4.0)]] = c.y
	var over := 0
	var total := 0
	var lift := 0.0
	for p in centers.size():
		if _find(p) != two:
			continue
		var c: Vector3 = centers[p]
		total += 1
		var key := "%d,%d" % [roundi(c.x / 4.0), roundi(c.z / 4.0)]
		if grid.has(key):
			over += 1
			lift += c.y - float(grid[key])
	if total == 0:
		return
	note("куски %d и %d: на одном месте по горизонтали %d из %d полигонов (%.0f%%)"
		% [one, two, over, total, 100.0 * float(over) / float(total)])
	if over > 0:
		note("  средний разрыв по высоте: %.2f м" % (lift / float(over)))


func _sum(counts: Dictionary) -> int:
	var total := 0
	for key in counts:
		total += int(counts[key])
	return total


## Проследить настоящий путь и сказать, в каком куске он оборвался.
func _trace_path(centers: Array, sizes: Dictionary, from_name: String,
		to_name: String, verbose := false) -> void:
	var from: Vector3 = _spots[from_name]
	var to: Vector3 = _spots[to_name]
	var path: PackedVector3Array = _world.navigation.path_between(from, to)
	if path.is_empty():
		note("%s → %s: путь пуст" % [from_name, to_name])
		return
	var last: Vector3 = path[path.size() - 1]
	# Промах меряем ПО ГОРИЗОНТАЛИ: цель записана с высотой поверхности, а путь
	# кладёт точки на высоту сетки, и разница в метр — это не недоход.
	var gap: float = Vector2(last.x, last.z).distance_to(Vector2(to.x, to.z))
	var island := -1
	var near := _nearest_poly(centers, last)
	if near >= 0:
		island = _find(near)
	note("%s → %s: точек %3d, конец (%.0f, %.1f, %.0f), промах %6.1f м, кусок %d (%d полигонов)"
		% [from_name, to_name, path.size(), last.x, last.y, last.z, gap,
			island, int(sizes.get(island, 0))])
	if not verbose:
		return
	# Путь целиком, по одной точке в строке. Куда он свернул, видно только так.
	var line := ""
	for i in path.size():
		var pt: Vector3 = path[i]
		line += "(%.0f,%.1f,%.0f) " % [pt.x, pt.y, pt.z]
		if i % 6 == 5:
			note("    " + line)
			line = ""
	if line != "":
		note("    " + line)
