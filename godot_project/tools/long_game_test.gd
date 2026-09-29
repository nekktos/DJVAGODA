extends "res://tools/test_base.gd"
##
## Долгая партия: проходит ли ИИ-злодей ВСЮ хозяйственную цепочку сам — от
## пустых рук до войска и кузни. Работает headless, в общий прогон не входит:
##
##     ./run_tests.sh longgame
##
## ЗАЧЕМ. Машинный отчёт по playtest-6 честно записал в «чего не проверяли»:
## «экономическая цепочка целиком от пустых рук до армии — набор проверяет, что
## первая постройка по карману и что источник железа достижим, но не проходит
## весь путь караванами за реальное время». Каждое звено покрыто своим набором
## (подъём с нуля, хозяйство, обозы, снаряжение), но звенья проверены по
## отдельности, на подложенных ресурсах. Здесь ничего не подкладывается: мир
## идёт сам, и видно, где цепочка рвётся и сколько занимает каждое звено.
##
## Набор идёт за эльфов: злодей и стража гарантированно под ИИ. Вариант
## `longgame2` — за стражу: тогда против злодея играют эльфы под ИИ.
##
## ВРЕМЯ УСКОРЕНО. Двадцать пять игровых минут в реальном времени — это
## двадцать пять минут на прогон. `Engine.time_scale` поднимается вместе с
## числом физических тактов в секунду, так что ШАГ физики остаётся прежним —
## 1/60 игровой секунды, — и мир считается так же, только чаще. Если машина
## не успевает, игра просто замедлится: итог печатается в ИГРОВЫХ минутах.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

## Сколько игровых минут даём злодею.
const GAME_MINUTES := 25.0
## Во сколько раз ускоряем время.
const SPEED := 4.0
## Как часто смотрим, игровых секунд.
const SAMPLE := 5.0

const SIDE := FACTIONS.Kind.VILLAIN

var _world: Node3D
## Звено цепочки -> игровая секунда, когда оно впервые замечено.
var _reached := {}
var _started_real := 0


func start(world: Node3D) -> void:
	tag = "долгая партия"
	expected_host = 7
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	Engine.physics_ticks_per_second = int(60.0 * SPEED)
	Engine.max_physics_steps_per_frame = int(8.0 * SPEED)
	Engine.time_scale = SPEED
	_started_real = Time.get_ticks_msec()
	var game := 0.0
	while game < GAME_MINUTES * 60.0:
		await get_tree().create_timer(SAMPLE).timeout
		game += SAMPLE
		_sample(game)
		if _reached.has("gear"):
			break
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8

	var real := (Time.get_ticks_msec() - _started_real) / 1000.0
	note("прошло %.1f игровых минут за %.1f реальных (ускорение %.1f)"
		% [game / 60.0, real / 60.0, game / maxf(real, 0.001)])
	for key in ["storage", "labourers", "caravan", "iron", "barracks", "soldier", "forge", "gear"]:
		note("  %-10s %s" % [key, _when(key)])
	var wallet: Node = _world.treasury.of(SIDE)
	var stock := []
	for kind in RES.COUNT:
		stock.append(int(wallet.get_amount(kind)))
	note("казна злодея к концу: %s, батраков %d, бойцов %d"
		% [stock, _world.labourers_of(SIDE).size(), _soldiers()])

	check(_reached.has("storage"), "ИИ-злодей поставил склад", _when("storage"))
	check(_reached.has("caravan"), "отправил обоз", _when("caravan"))
	check(_reached.has("iron"), "обоз привёз железо с шахты", _when("iron"))
	check(_reached.has("barracks"), "построил казарму", _when("barracks"))
	check(_reached.has("soldier"), "нанял войско", _when("soldier"))
	check(_reached.has("forge"), "построил кузню", _when("forge"))
	check(_reached.has("gear"), "вожак закалил оружие", _when("gear"))
	finish()


func _sample(game: float) -> void:
	var wallet: Node = _world.treasury.of(SIDE)
	_mark("storage", game, _world.storage_of(SIDE) != null)
	_mark("labourers", game, _world.labourers_of(SIDE).size() > 0)
	var carts := 0
	for cart in _world.caravans_of(0):
		if int(cart.faction) == SIDE:
			carts += 1
	_mark("caravan", game, carts > 0)
	# Железо с микро-шахты не берётся — только обозом с шахты в лесу эльфов.
	# Потраченное тоже в счёт: казарма без железа не встанет.
	_mark("iron", game, int(wallet.get_amount(RES.Kind.IRON)) > 0
		or _world.barracks_of(SIDE) != null)
	_mark("barracks", game, _world.barracks_of(SIDE) != null
		or _world.barracks_of(SIDE, RES.Building.ARCHER_BARRACKS) != null)
	_mark("soldier", game, _soldiers() > 0)
	_mark("forge", game, _world.barracks_of(SIDE, RES.Building.FORGE) != null)
	var hero: Node3D = _world.ai_hero_of(SIDE)
	_mark("gear", game, hero != null and int(hero.gear_tier) >= 1)
	if int(game) % 60 == 0:
		note("%2d мин: звеньев %d, казна %s, батраков %d, бойцов %d, обозов %d"
			% [int(game / 60.0), _reached.size(), _stock_line(wallet),
				_world.labourers_of(SIDE).size(), _soldiers(), carts])
		var elf_hero: Node3D = _world.ai_hero_of(FACTIONS.Kind.ELVES)
		note("     эльфы: домов %d, живых эльфов %d, вожак ИИ %s"
			% [_world.elf_houses().size(), _world.living_elves(),
				"жив" if elf_hero != null and bool(elf_hero.health.alive) else "нет"])
		for cart in _world.caravans_of(0):
			if int(cart.faction) == SIDE:
				note("     обоз: состояние %d в %s, стоит %s, ждёт у склада %s, груз %d"
					% [int(cart.state), (cart as Node3D).global_position.round(),
						bool(cart.halted), bool(cart.waiting), int(cart.cargo_total())])


func _mark(key: String, game: float, ok: bool) -> void:
	if ok and not _reached.has(key):
		_reached[key] = game
		note("звено «%s» — на %s" % [key, _clock(game)])


func _when(key: String) -> String:
	return "на " + _clock(_reached[key]) if _reached.has(key) else "не дошёл"


func _clock(game: float) -> String:
	return "%d:%02d" % [int(game / 60.0), int(game) % 60]


func _stock_line(wallet: Node) -> String:
	var parts := []
	for kind in RES.COUNT:
		parts.append(str(int(wallet.get_amount(kind))))
	return "[" + ", ".join(parts) + "]"


## Бойцы злодея, НАНЯТЫЕ в казарме: пешки без роли батрака, не вожак и не
## гарнизон. Гарнизон стоит с начала партии, и считать его войском значило
## отметить звено «нанял войско» на пятой секунде — так первый прогон и сделал.
func _soldiers() -> int:
	var count := 0
	var garrison: Node = _world.get_node_or_null("Garrison")
	var standing: Array = garrison._garrisons.get(SIDE, []) if garrison != null else []
	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit) or int(unit.faction) != SIDE:
			continue
		if unit in standing:
			continue
		if "sync_role" in unit:
			continue
		if "is_champion" in unit and unit.is_champion:
			continue
		count += 1
	return count
