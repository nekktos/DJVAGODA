extends RefCounted
##
## Камни настоящей формы вместо кубов.
##
## ЗАЧЕМ. Горы у форта злодея были коробками по семьдесят метров, а валуны у
## спавна — коробками по четыре. Каменная текстура на них легла, но куб остаётся
## кубом: прямые рёбра и три плоские грани видно с любого расстояния, и никакая
## раскраска этого не исправит. Форма читается раньше цвета.
##
## КАК СДЕЛАНО. Берём сферу-многогранник и толкаем каждую её вершину вдоль
## собственного направления на величину шума. Получается угловатый булыжник со
## сколами и неровным силуэтом — ровно то, что нужно: не гладкое яйцо и не
## коробка. Тем же кодом делается и галька под ногой, и скала в семьдесят
## метров, разница только в масштабе и семени.
##
## ПОЧЕМУ КОДОМ, А НЕ МОДЕЛЬЮ. Та же причина, что у текстур и звука: заглушка,
## которая делает игру читаемой, не дожидаясь художника. Плюс частная: камни в
## наборе Kenney обмерены и оказались плоскими плитками в четверть метра —
## галька под ноги, а не валуны, и уж тем более не горы.
##
## КОЛЛИЗИЯ — ВЫПУКЛАЯ ОБОЛОЧКА, а не сам меш. Треугольная коллизия на сорока
## горах по семьдесят метров стоила бы дорого и печению навигации, и физике, а
## разницы между «обошёл валун» и «обошёл его выпуклую тень» никто не заметит.
##

## Сколько граней у заготовки. Больше — глаже, меньше — грубее; на восьми
## сегментах булыжник ещё читается камнем, а не кристаллом.
const SEGMENTS := 10
const RINGS := 6

## Насколько сильно шум мнёт сферу. Единица — вершина уезжает на весь радиус.
const DENT := 0.34
## Крупность вмятин. Меньше — крупнее сколы.
const DENT_SCALE := 1.7

## Гора мнётся слабее булыжника: крупные вмятины на склоне читаются обвалом.
const PEAK_DENT := 0.20
const PEAK_DENT_SCALE := 1.1

static var _cache := {}


## Меш камня. `seed_value` задаёт форму: одинаковое семя — одинаковый камень.
##
## Формы кэшируются: сорок гор по семидесяти метрам — это сорок вызовов, и
## лепить каждую заново незачем, довольно дюжины разных на всю карту.
static func mesh(seed_value: int) -> ArrayMesh:
	var key: int = seed_value % 12
	if _cache.has(key):
		return _cache[key]

	var noise := FastNoiseLite.new()
	noise.seed = 7000 + key * 131
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = DENT_SCALE

	# Вершины считаем по сетке широта-долгота и запоминаем, чтобы соседние
	# грани брали ОДНУ И ТУ ЖЕ точку: посчитанные дважды, они разъезжаются на
	# доли миллиметра, и по камню идут светлые трещины.
	var grid: Array = []
	for ring in RINGS + 1:
		var row: Array = []
		var v: float = float(ring) / float(RINGS)
		var phi: float = v * PI
		for seg in SEGMENTS + 1:
			var u: float = float(seg) / float(SEGMENTS)
			var theta: float = u * TAU
			var dir := Vector3(
				sin(phi) * cos(theta),
				cos(phi),
				sin(phi) * sin(theta))
			# Швы по долготе: последняя долгота обязана совпасть с первой,
			# иначе камень разрезан вдоль и видно нутро.
			var sample: Vector3 = dir if seg < SEGMENTS else Vector3(
				sin(phi), cos(phi), 0.0)
			# ТОЛЬКО НАРУЖУ. Было `1.0 + шум * DENT`, а шум ходит от -1 до 1 —
			# то есть вершина вдавливалась внутрь на треть радиуса. На гальке
			# это незаметно, а на горе в семьдесят метров получался кратер в
			# двадцать: камни выглядели впалыми, будто из них вычерпали нутро.
			# Сдвигаем шум в 0..1, и сколы становятся выступами, а не ямами.
			var dent: float = noise.get_noise_3d(
				sample.x * 2.0, sample.y * 2.0, sample.z * 2.0) * 0.5 + 0.5
			var push: float = 1.0 + dent * DENT
			# Низ подбираем: камень стоит на земле, а не парит шаром.
			var squash: float = 1.0 if dir.y > -0.2 else 0.55
			row.append(Vector3(dir.x * push, dir.y * push * squash, dir.z * push))
		grid.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in RINGS:
		for seg in SEGMENTS:
			var a: Vector3 = grid[ring][seg]
			var b: Vector3 = grid[ring][seg + 1]
			var c: Vector3 = grid[ring + 1][seg + 1]
			var d: Vector3 = grid[ring + 1][seg]
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	# Нормали ПЛОСКИЕ, и это намеренно: у камня грани и сколы, а сглаженные
	# нормали превращают его в оплывший леденец.
	st.generate_normals()
	var made := st.commit()
	_cache[key] = made
	return made


## Готовый камень с коллизией: тело, которое кладут в мир.
##
## `size` — габарит в метрах по каждой оси. Неравные оси и нужны: камень,
## растянутый вширь, читается валуном, а растянутый вверх — скалой, и это две
## разные вещи на одной сетке.
static func build(size: Vector3, yaw: float, seed_value: int,
		material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.rotation.y = yaw

	var shape_mesh := mesh(seed_value)
	var view := MeshInstance3D.new()
	view.mesh = shape_mesh
	view.scale = size * 0.5
	view.material_override = material
	body.add_child(view)

	var shape := CollisionShape3D.new()
	var convex := shape_mesh.create_convex_shape()
	shape.shape = convex
	shape.scale = size * 0.5
	body.add_child(shape)
	return body


## Гора: конус со сколами, а не шар.
##
## ЗАЧЕМ ОТДЕЛЬНАЯ ФОРМА. Шар, растянутый вверх, горой не выглядит ни при каком
## шуме: у горы силуэт СУЖАЕТСЯ кверху и расширяется к подножию, а у шара он
## пузатый посередине. Рядом с фортом это читалось как валун-переросток.
##
## Профиль: радиус растёт от вершины к основанию степенью чуть меньше единицы —
## получается вогнутый склон, как у настоящей горы, а не прямой конус.
## Гребни — редкая волна по долготе: без них конус гладкий, как насыпь щебня.
static func peak(seed_value: int) -> ArrayMesh:
	var key: int = 1000 + seed_value % 12
	if _cache.has(key):
		return _cache[key]

	var noise := FastNoiseLite.new()
	noise.seed = 4400 + key * 97
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = PEAK_DENT_SCALE

	var grid: Array = []
	for ring in RINGS + 1:
		var row: Array = []
		var t: float = float(ring) / float(RINGS)      # 0 вершина, 1 подножие
		var profile: float = pow(t, 0.62)
		var y: float = 1.0 - t
		for seg in SEGMENTS + 1:
			var u: float = float(seg) / float(SEGMENTS)
			var theta: float = u * TAU if seg < SEGMENTS else 0.0
			var dir := Vector2(cos(theta), sin(theta))
			# Гребни и кулуары: волна по кругу, сильнее у подножия.
			var ridged: float = 1.0 + cos(theta * 3.0 + float(key)) * 0.16 * t
			var lump: float = 1.0 + (noise.get_noise_3d(
				dir.x * 2.0, y * 2.0, dir.y * 2.0) * 0.5 + 0.5) * PEAK_DENT
			var r: float = profile * ridged * lump
			row.append(Vector3(dir.x * r, y, dir.y * r))
		grid.append(row)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# ОБХОД ОБРАТНЫЙ шару. У шара кольца идут по phi сверху вниз, а здесь — по
	# высоте, и при том же порядке вершин нормали смотрят ВНУТРЬ: гора выходила
	# тёмным полым лепестком, потому что видно было её изнанку.
	for ring in RINGS:
		for seg in SEGMENTS:
			var a: Vector3 = grid[ring][seg]
			var b: Vector3 = grid[ring][seg + 1]
			var c: Vector3 = grid[ring + 1][seg + 1]
			var d: Vector3 = grid[ring + 1][seg]
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(a)
			st.add_vertex(d)
			st.add_vertex(c)
	# Подножие закрываем: открытый низ видно с любого склона, и гора выглядит
	# скорлупой. Вершина крышки чуть утоплена — иначе она z-борется с землёй.
	var floor_centre := Vector3(0.0, -0.02, 0.0)
	for seg in SEGMENTS:
		st.add_vertex(floor_centre)
		st.add_vertex(grid[RINGS][seg])
		st.add_vertex(grid[RINGS][seg + 1])
	st.generate_normals()
	var made := st.commit()
	_cache[key] = made
	return made


## Готовая гора с коллизией. `size` — ширина, высота, глубина в метрах.
## Низ горы лежит на нуле: ставят её на землю, а не по центру.
static func build_peak(size: Vector3, yaw: float, seed_value: int,
		material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.rotation.y = yaw
	var shape_mesh := peak(seed_value)
	var scale_to := Vector3(size.x * 0.5, size.y, size.z * 0.5)

	var view := MeshInstance3D.new()
	view.mesh = shape_mesh
	view.scale = scale_to
	view.material_override = material
	body.add_child(view)

	var col := CollisionShape3D.new()
	col.shape = shape_mesh.create_convex_shape()
	col.scale = scale_to
	body.add_child(col)
	return body
