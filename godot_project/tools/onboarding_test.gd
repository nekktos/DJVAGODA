extends "res://tools/test_base.gd"
##
## Подсказка первых минут: ведёт ли она куда-то, куда можно дойти.
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --onboardingtest
##
## ЗАЧЕМ. Подсказка — единственная часть игры, которая ОБЕЩАЕТ. Все остальные
## системы просто работают или нет; эта говорит человеку «иди туда» и ставит
## над местом столб. Ошибётся она — и игрок пойдёт шестьсот метров впустую,
## причём с полной уверенностью, что делает правильно. Это хуже, чем молчать.
##
## Поэтому главная проверка здесь не про текст, а про ГЕОГРАФИЮ: каждую точку
## каждой цепочки набор отдаёт навигации и требует, чтобы путь дошёл. Ровно на
## этом уже обожглись — шахта в GDD «есть», а её середина лежит внутри
## пятидесятиметровой глыбы, и маяк, поставленный в центр, звал бы в камень.
##

const ONBOARDING := preload("res://scripts/ui/onboarding.gd")
const WAYPOINT := preload("res://scripts/ui/waypoint.gd")
const FACTIONS := preload("res://scripts/factions.gd")

## Насколько близко путь обязан подвести к точке маяка.
##
## Число берём У САМОЙ ПОДСКАЗКИ: `ONBOARDING.ARRIVED` — это тот порог, на
## котором она засчитывает шаг «дойди». Если навигация не подводит ближе, шаг
## не выполнится никогда, и цепочка встанет намертво. Свой отдельный порог
## здесь означал бы, что проверка и игра меряют разное.
const REACH := ONBOARDING.ARRIVED

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "онбординг"
	expected_host = 8
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	_test_chains_are_filled()
	_test_last_step_never_ends()
	_test_places_are_reachable()
	_test_first_step_shows()
	_test_step_advances_when_moved(me)
	_test_step_never_goes_back(me)
	_test_strategy_step_counts(me)
	_test_waypoint_hides_without_target()
	finish()


## У каждой стороны цепочка не пуста и в каждом шаге есть текст.
func _test_chains_are_filled() -> void:
	var guide := ONBOARDING.new()
	var bad := PackedStringArray()
	for faction in FACTIONS.COUNT:
		var chain: Array = guide.chain_of(faction)
		if chain.is_empty():
			bad.append("%s: цепочки нет" % FACTIONS.name_of(faction))
			continue
		for i in chain.size():
			if String(chain[i].get("text", "")).strip_edges() == "":
				bad.append("%s: шаг %d без текста" % [FACTIONS.name_of(faction), i + 1])
	check(bad.is_empty(), "у каждой стороны цепочка заполнена",
		", ".join(bad))


## Последний шаг не выполняется НИКОГДА.
##
## Он и есть условие победы стороны: закончившись, подсказка оставила бы игрока
## с пустым местом наверху экрана ровно в тот момент, когда до победы ещё идти
## и идти.
func _test_last_step_never_ends() -> void:
	var guide := ONBOARDING.new()
	var bad := PackedStringArray()
	for faction in FACTIONS.COUNT:
		var chain: Array = guide.chain_of(faction)
		if chain.is_empty():
			continue
		var last: Dictionary = chain[chain.size() - 1]
		if last.has("done"):
			bad.append("%s: у последнего шага есть правило «%s»"
				% [FACTIONS.name_of(faction), last["done"]])
	check(bad.is_empty(), "последний шаг каждой стороны бесконечен", ", ".join(bad))


## КАЖДАЯ точка КАЖДОЙ цепочки достижима ногами.
func _test_places_are_reachable() -> void:
	var guide := ONBOARDING.new()
	var bad := PackedStringArray()
	var seen := 0
	for faction in FACTIONS.COUNT:
		var from: Vector3 = FACTIONS.SPAWN[faction]
		for step in guide.chain_of(faction):
			var at = step.get("at", null)
			if at == null:
				continue
			seen += 1
			var gap: float = _walk_gap(from, at)
			if gap > REACH:
				bad.append("%s → «%s»: не дошёл %.0f м"
					% [FACTIONS.name_of(faction), step.get("place", "?"), gap])
	note("точек с маяком в цепочках: %d" % seen)
	check(bad.is_empty() and seen > 0,
		"до каждого места из подсказки можно дойти ногами", ", ".join(bad))


## Насколько близко путь подводит к цели. ПО ГОРИЗОНТАЛИ: дворец на плато,
## лавка в низине, и разница высот — не недоход.
func _walk_gap(from: Vector3, to: Vector3) -> float:
	var path: PackedVector3Array = _world.navigation.path_between(from, to)
	if path.is_empty():
		return INF
	var last: Vector3 = path[path.size() - 1]
	return Vector2(last.x, last.z).distance_to(Vector2(to.x, to.z))


func _test_first_step_shows() -> void:
	var guide := ONBOARDING.new()
	var step: Dictionary = guide.current(_world, _world.local_player())
	check(not step.is_empty() and int(step.get("number", 0)) == 1,
		"на старте показан первый шаг",
		"получили %s" % step)


## Отошёл от спавна — шаг сменился.
##
## Проверяем РЕЗУЛЬТАТ (номер шага вырос), а не то, что счётчик расстояния
## что-то посчитал.
func _test_step_advances_when_moved(me: Node3D) -> void:
	var guide := ONBOARDING.new()
	var home: Vector3 = me.global_position
	guide.current(_world, me)                       # здесь запоминается спавн
	me.global_position = home + Vector3(ONBOARDING.LOOKED_AROUND + 20.0, 0.0, 0.0)
	var step: Dictionary = guide.current(_world, me)
	me.global_position = home
	check(int(step.get("number", 0)) >= 2, "отошёл от спавна — шаг сменился",
		"шаг остался %d" % int(step.get("number", 0)))


## Вернулся назад — подсказка НЕ откатилась.
##
## Иначе разрушенный склад вернул бы игрока к «построй склад» на двадцатой
## минуте боя.
func _test_step_never_goes_back(me: Node3D) -> void:
	var guide := ONBOARDING.new()
	var home: Vector3 = me.global_position
	guide.current(_world, me)
	me.global_position = home + Vector3(ONBOARDING.LOOKED_AROUND + 20.0, 0.0, 0.0)
	var ahead: int = int(guide.current(_world, me).get("number", 0))
	me.global_position = home
	var back: int = int(guide.current(_world, me).get("number", 0))
	check(back >= ahead, "подсказка не откатывается назад",
		"ушла с %d на %d" % [ahead, back])


## Открыл вид сверху — шаг засчитан.
func _test_strategy_step_counts(me: Node3D) -> void:
	if not FACTIONS.can_build(int(me.faction)) :
		note("сторона без стройки: шага «вид сверху» в её цепочке нет")
		check(true, "шаг «вид сверху» проверяется только у строящей стороны", "")
		return
	var guide := ONBOARDING.new()
	var home: Vector3 = me.global_position
	guide.current(_world, me)
	me.global_position = home + Vector3(ONBOARDING.LOOKED_AROUND + 20.0, 0.0, 0.0)
	var before: int = int(guide.current(_world, me).get("number", 0))
	guide.note_strategy()
	var after: int = int(guide.current(_world, me).get("number", 0))
	me.global_position = home
	check(after > before, "открыл вид сверху — шаг засчитан",
		"было %d, стало %d" % [before, after])


## Маяк без цели прячется, с целью — виден.
func _test_waypoint_hides_without_target() -> void:
	var beacon: Node3D = WAYPOINT.new()
	_world.add_child(beacon)
	beacon.aim(null, "")
	var hidden: bool = not beacon.visible
	beacon.aim(Vector3(10.0, 0.0, 10.0), "шахта")
	var shown: bool = beacon.visible
	beacon.queue_free()
	check(hidden and shown, "маяк прячется без цели и виден с целью",
		"без цели скрыт=%s, с целью виден=%s" % [hidden, shown])
