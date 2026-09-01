extends RefCounted
##
## Текстуры зданий и камня. Рисуются КОДОМ, как и звук.
##
## ПОЧЕМУ КОДОМ. Ровно та же причина, по которой звук синтезируется, а карта
## собрана из серых коробок: это заглушка, которая делает игру читаемой, не
## дожидаясь художника. Файл текстуры пришлось бы искать, лицензировать и
## хранить; шум и полосы, нарисованные в шестьдесят строк, дают ту же разницу
## между «серый куб» и «каменная стена» и правятся одной цифрой.
##
## ПОЧЕМУ ТРИПЛАНАР. Вся геометрия мира — коробки и цилиндры, созданные кодом.
## Развёртки у них нет вовсе: BoxMesh кладёт одну и ту же квадратную развёртку
## на все шесть граней, и текстура на стене длиной восемьдесят метров
## растягивается в одно исполинское пятно. Трипланар берёт цвет по МИРОВЫМ
## координатам, поэтому камень одинакового размера и на стометровой стене, и на
## трёхметровом валуне, и разворот коробки его не косит.
##
## ПОЧЕМУ КЭШ. Постройка собирает свой облик при каждом появлении, а горы в зоне
## злодея — сорок штук за проход. Рисовать 128×128 пикселей заново на каждую
## значило бы тратить секунды на то, что не меняется никогда.
##

## Сторона текстуры в пикселях. Больше не нужно: рисунок крупный, а генерация
## идёт на GDScript, и каждое удвоение стороны — вчетверо больше работы.
const SIZE := 128
## Сколько МЕТРОВ мира занимает один оборот текстуры. Меньше — мельче рисунок.
## Числа подобраны по снимкам, а не на глаз в редакторе: первый заход дал
## втрое мельче, и на стене форта рисунок сливался в ровную серую сетку, а
## издали — в ровную серую заливку. Крупнее — лучше: наша геометрия огромная,
## стена форта восемьдесят метров.
const WORLD_SCALE := {
	"stone": 6.0,
	"dark_stone": 6.0,
	"marble": 9.0,
	"wood": 3.0,
	"rock": 11.0,
	"roof": 2.2,
	"plaster": 4.0,
	"grass": 14.0,
}

static var _cache := {}


## Материал по имени. Второй и следующие вызовы отдают тот же самый объект.
static func of(key: String) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _draw(key)
	mat.roughness = 0.95
	# Трипланар — то, ради чего это всё и затевалось (см. шапку файла).
	mat.uv1_triplanar = true
	var span: float = float(WORLD_SCALE.get(key, 3.0))
	mat.uv1_scale = Vector3.ONE / span
	_cache[key] = mat
	return mat


## Копия материала: нужна там, где вид меняют на месте — прозрачность растущей
## стройки, например. Общий материал там красил бы разом все постройки мира.
static func copy_of(key: String) -> StandardMaterial3D:
	return of(key).duplicate()


static func _draw(key: String) -> ImageTexture:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	match key:
		"stone":
			_blocks(img, Color(0.58, 0.57, 0.55), Color(0.40, 0.39, 0.38), 4, 8)
		"dark_stone":
			_blocks(img, Color(0.37, 0.36, 0.39), Color(0.24, 0.23, 0.26), 4, 8)
		"marble":
			_veins(img, Color(0.86, 0.84, 0.79), Color(0.66, 0.64, 0.62))
		"wood":
			_planks(img, Color(0.49, 0.35, 0.22), Color(0.31, 0.21, 0.13))
		"rock":
			_speckle(img, Color(0.47, 0.44, 0.41), Color(0.29, 0.27, 0.26))
		"roof":
			_tiles(img, Color(0.78, 0.29, 0.24), Color(0.52, 0.18, 0.15))
		"plaster":
			_speckle(img, Color(0.88, 0.84, 0.77), Color(0.78, 0.74, 0.68))
		"grass":
			# Трава крупным пятном: холм в четыреста метров, покрашенный ровным
			# зелёным, читается как пластмасса, а не как поле.
			_speckle(img, Color(0.44, 0.52, 0.31), Color(0.27, 0.36, 0.22))
		_:
			img.fill(Color(0.6, 0.6, 0.6))
	# Мипмапы обязательны. Без них рисунок вдали превращается в мельтешащую
	# рябь: пиксель экрана берёт один случайный пиксель текстуры из десятка, и
	# картинка «кипит» при каждом шаге камеры. На площади перед дворцом это было
	# видно с первого снимка — она пошла муаровой сеткой.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Шум, повторяющийся по краям. Обычный FastNoiseLite на границе текстуры рвётся,
## и шов виден полосой через всю стену; здесь шум берётся с тора — координата
## идёт по кругу, поэтому левый край совпадает с правым, а верхний с нижним.
static func _noise(seed_value: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	return n


static func _tiled_value(n: FastNoiseLite, x: int, y: int, span: float) -> float:
	var u: float = TAU * float(x) / float(SIZE)
	var v: float = TAU * float(y) / float(SIZE)
	# Четырёхмерный шум по двум окружностям дал бы идеальный тор, но у нас его
	# нет; трёхмерного хватает: одна ось замкнута по кругу, вторая по кругу же,
	# и видимого шва не остаётся.
	return n.get_noise_3d(cos(u) * span, sin(u) * span, cos(v) * span + sin(v) * span)


## Каменная кладка: ряды блоков со швами, каждый блок своего оттенка.
static func _blocks(img: Image, light: Color, dark: Color, rows: int, cols: int) -> void:
	var n := _noise(4021)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var shades := []
	for i in rows * cols:
		shades.append(rng.randf())
	var row_h: float = float(SIZE) / float(rows)
	var col_w: float = float(SIZE) / float(cols)
	for y in SIZE:
		var row: int = int(float(y) / row_h)
		# Каждый второй ряд сдвинут на полблока: кладка встык столбиками
		# читается как плитка, а не как стена.
		var shift: float = 0.0 if row % 2 == 0 else col_w * 0.5
		for x in SIZE:
			var sx: float = fmod(float(x) + shift, float(SIZE))
			var col: int = int(sx / col_w)
			var in_seam: bool = fmod(sx, col_w) < 3.0 or fmod(float(y), row_h) < 3.0
			var shade: float = shades[(row * cols + col) % shades.size()]
			# Разброс оттенка блоков ШИРОКИЙ. Узкий (первый заход брал верхнюю
			# половину диапазона) даёт кладку, различимую только вплотную, а с
			# двадцати метров — ровную заливку.
			var base: Color = dark.lerp(light, 0.12 + shade * 0.88)
			base = base.lerp(dark, 0.55 * (_tiled_value(n, x, y, 6.0) * 0.5 + 0.5))
			img.set_pixel(x, y, dark.darkened(0.55) if in_seam else base)


## Мрамор: светлый камень с прожилками. Прожилка — тот же шум, но взятый по
## модулю: там, где он проходит через ноль, остаётся тонкая тёмная линия.
static func _veins(img: Image, light: Color, dark: Color) -> void:
	var n := _noise(9133)
	for y in SIZE:
		for x in SIZE:
			var v: float = _tiled_value(n, x, y, 4.0)
			var vein: float = 1.0 - clampf(absf(v) * 4.5, 0.0, 1.0)
			var base: Color = light.lerp(dark, 0.55 * (v * 0.5 + 0.5))
			img.set_pixel(x, y, base.lerp(dark.darkened(0.25), vein * 0.9))


## Доски: вертикальные полосы с тёмным швом и продольной волокнистостью.
static func _planks(img: Image, light: Color, dark: Color) -> void:
	var n := _noise(2207)
	var planks := 5
	var w: float = float(SIZE) / float(planks)
	for x in SIZE:
		var index: int = int(float(x) / w)
		var seam: bool = fmod(float(x), w) < 1.5
		for y in SIZE:
			# Волокно вытянуто вдоль доски: шум по Y частый, по X почти
			# постоянный — иначе получается не дерево, а гранит.
			var g: float = _tiled_value(n, x, y, 10.0) * 0.5 + 0.5
			var tone: float = 0.10 + 0.75 * g + 0.18 * float(index % 3)
			var base: Color = dark.lerp(light, clampf(tone, 0.0, 1.0))
			img.set_pixel(x, y, dark.darkened(0.5) if seam else base)


## Черепица: ряды со сдвигом, каждая плитка темнеет книзу.
static func _tiles(img: Image, light: Color, dark: Color) -> void:
	var rows := 8
	var cols := 8
	var row_h: float = float(SIZE) / float(rows)
	var col_w: float = float(SIZE) / float(cols)
	for y in SIZE:
		var row: int = int(float(y) / row_h)
		var down: float = fmod(float(y), row_h) / row_h
		var shift: float = 0.0 if row % 2 == 0 else col_w * 0.5
		for x in SIZE:
			var sx: float = fmod(float(x) + shift, float(SIZE))
			var edge: bool = fmod(sx, col_w) < 1.5
			# Нижний край плитки в тени от нахлёста следующего ряда.
			var shade: float = 0.05 + down * 0.8
			var base: Color = light.lerp(dark, shade)
			img.set_pixel(x, y, dark.darkened(0.45) if edge or down > 0.9 else base)


## Крапчатый камень: два слоя шума, крупный на форму и мелкий на зерно.
static func _speckle(img: Image, light: Color, dark: Color) -> void:
	var big := _noise(7717)
	var fine := _noise(1553)
	for y in SIZE:
		for x in SIZE:
			var a: float = _tiled_value(big, x, y, 3.0) * 0.5 + 0.5
			var b: float = _tiled_value(fine, x, y, 12.0) * 0.5 + 0.5
			# Мелкий шум идёт ДОБАВКОЙ вокруг нуля, а не слагаемым: сложенные
			# в лоб, оба слоя упирались в единицу, всё светлое сливалось в
			# белое, и камень выходил ровным пятном.
			img.set_pixel(x, y, dark.lerp(light, clampf(a + (b - 0.5) * 0.6, 0.0, 1.0)))
