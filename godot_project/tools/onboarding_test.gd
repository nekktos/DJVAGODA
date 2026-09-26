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
const OBJECTIVE := preload("res://scripts/objective.gd")

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
	expected_host = 14
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
	_test_optional_step_is_skipped_when_broke(me)
	_test_goal_is_named_before_the_shop()
	_test_capture_rule_is_told()
	_test_last_step_reports_the_capture(me)
	_test_economy_comes_before_the_assault()
	_test_faction_change_restarts_the_chain(me)
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


## Необязательный шаг пропускается, когда сделать его нельзя.
##
## ЗАЧЕМ. Живой игрок дошёл до «зайди в лавку» и спросил: зачем мне туда, я
## ничего не покупаю? Пока шаг был обязательным, цепочка вставала на нём
## намертво: не пошёл в лавку — не узнал, что цель партии дворец. Шаг, который
## человек вправе не делать, обязан уметь пропускаться сам.
##
## Проверяем РЕЗУЛЬТАТ: опустошаем склад и требуем, чтобы шаг стал проходным.
func _test_optional_step_is_skipped_when_broke(me: Node3D) -> void:
	var guide := ONBOARDING.new()
	var optional := {}
	for step in guide.chain_of(FACTIONS.Kind.VILLAIN):
		if step.has("skip"):
			optional = step
	if optional.is_empty():
		check(false, "у злодея шаг про лавку помечен необязательным",
			"необязательных шагов в цепочке нет")
		return
	var cost: Array = me.next_gear_cost()
	while not cost.is_empty() and me.stock.can_afford(cost):
		me.stock.spend(cost)
		cost = me.next_gear_cost()
	check(guide._skipped(optional, me),
		"необязательный шаг пропускается, когда платить нечем",
		"склад пуст, а шаг всё равно обязателен")


## Цель партии названа РАНЬШЕ, чем лавка.
##
## Та же жалоба, вторая её половина: «нет определённой цели, поэтому я не
## понимаю, зачем мне сейчас туда идти». Снаряжение покупают ПЕРЕД чем-то;
## пока игрок не знает, что впереди дворец, покупка беспричинна.
func _test_goal_is_named_before_the_shop() -> void:
	var guide := ONBOARDING.new()
	var chain: Array = guide.chain_of(FACTIONS.Kind.VILLAIN)
	var goal := -1
	var shop := -1
	for i in chain.size():
		var place := String(chain[i].get("place", ""))
		if goal < 0 and place == "дворец":
			goal = i
		# Лавку ищем по ПРАВИЛУ ПРОПУСКА, а не по слову в подписи. Подпись уже
		# менялась — была «лавка эльфов», стала «своя лавка», — и проверка
		# тихо перестала находить шаг, о котором писана.
		if shop < 0 and String(chain[i].get("skip", "")) == "gear":
			shop = i
	check(goal >= 0 and shop >= 0 and goal < shop,
		"цель партии названа раньше лавки",
		"дворец на шаге %d, лавка на шаге %d" % [goal + 1, shop + 1])


## Последний шаг называет НАСТОЯЩЕЕ условие захвата.
##
## ЗАЧЕМ. Живой игрок встал внутри дворца и написал: «я стою и ничего дальше не
## происходит». Шаг говорил «войти в ворота с юга и стоять внутри» — правда, но
## не вся: точка берётся за двадцать секунд и только пока внутри нет чужого
## вожака. Неполная правда в подсказке работает как ложь.
##
## Проверяем, что число секунд в тексте — ТО ЖЕ, что в игре. Вписанное руками
## оно однажды разойдётся с `objective.gd`, и подсказка станет врать молча.
func _test_capture_rule_is_told() -> void:
	var guide := ONBOARDING.new()
	var seconds := "%d" % int(OBJECTIVE.CAPTURE_SECONDS)
	var bad := PackedStringArray()
	for faction in FACTIONS.COUNT:
		var chain: Array = guide.chain_of(faction)
		if chain.is_empty():
			continue
		var last: Dictionary = chain[chain.size() - 1]
		var words := String(last.get("text", "")) + " " + String(last.get("keys", ""))
		if String(last.get("place", "")) != "дворец":
			continue
		if not words.contains(seconds) or not words.contains("вожак"):
			bad.append(FACTIONS.name_of(faction))
	check(bad.is_empty(),
		"последний шаг называет срок захвата и правило про чужого вожака",
		"молчат: %s" % ", ".join(bad))


## Последний шаг ОТЧИТЫВАЕТСЯ о том, что происходит в точке.
##
## ЗАЧЕМ. Живой игрок встал во дворце и простоял пять минут: «другого вожака
## нет, просто не хочет дальше работать». Захват при этом был исправен — набор
## «проходимость» показывает, что дворец переходит за двадцать секунд. Сломано
## было другое: последний шаг не менялся НИКОГДА, и человек, смотревший ровно
## туда, где написана задача, не видел ни хода захвата, ни того, что дворец уже
## взят.
##
## Проверяем РЕЗУЛЬТАТ: меняем состояние точки и требуем, чтобы текст шага
## поменялся вслед.
func _test_last_step_reports_the_capture(me: Node3D) -> void:
	var guide := ONBOARDING.new()
	var goal: Node = _world.objective
	var owner_was: int = int(goal.palace_owner)
	var disputed_was: bool = bool(goal.contested)
	var progress_was: float = float(goal.capture_progress)

	# Гоним подсказку до последнего шага: он и есть живой. Сперва ОДИН вызов,
	# чтобы цепочка привязалась к стороне: иначе следующий вызов сбросит
	# прогресс как чужой.
	guide.current(_world, me)
	var chain: Array = guide.chain_of(int(me.faction))
	guide._passed = chain.size() - 1

	goal.palace_owner = (int(me.faction) + 1) % FACTIONS.COUNT
	goal.contested = false
	goal.capture_progress = 0.0
	var idle := String(guide.current(_world, me).get("text", ""))

	goal.capture_progress = 0.5
	var going := String(guide.current(_world, me).get("text", ""))

	goal.contested = true
	var fight := String(guide.current(_world, me).get("text", ""))

	goal.contested = false
	goal.palace_owner = int(me.faction)
	var taken := String(guide.current(_world, me).get("text", ""))

	goal.palace_owner = owner_was
	goal.contested = disputed_was
	goal.capture_progress = progress_was

	var all_different: bool = (idle != going and going != fight and fight != taken
		and idle != taken)
	check(all_different and going.contains("50") and fight.contains("ОСПАРИВАЕТСЯ")
			and taken.contains("ПОБЕДА"),
		"последний шаг отчитывается: идёт захват, оспаривается, взят",
		"покой=«%s» ход=«%s» спор=«%s» взят=«%s»" % [idle, going, fight, taken])


## Хозяйство и армия идут ДО штурма, а захват — последним шагом.
##
## ЗАЧЕМ. Решение живого игрока, и оно про темп: «не вижу смысла в том, что
## восьмое задание — буквально сразу пойти и захватывать; лучше отправить
## добывать железо и прокачивать базу и армию, а про захват чуть позже». До
## этого цепочка вела от первого железа прямо к дворцу, и вся середина игры —
## казармы, найм, конюшня — оставалась ненайденной: ровно та беда, из-за
## которой у тестера за сорок минут прошла мимо целая ветка с конечностями.
##
## Проверка стережёт ПОРЯДОК, а не тексты: шаги про базу обязаны лежать между
## железом и штурмом, а захват — быть последним.
func _test_economy_comes_before_the_assault() -> void:
	var guide := ONBOARDING.new()
	var chain: Array = guide.chain_of(FACTIONS.Kind.VILLAIN)
	var at := {}
	for i in chain.size():
		var rule := String(chain[i].get("done", ""))
		if rule != "" and not at.has(rule):
			at[rule] = i
	var last: int = chain.size() - 1
	var bad := PackedStringArray()
	if String(chain[last].get("live", "")) != "palace":
		bad.append("последний шаг не про захват дворца")
	for rule in ["barracks", "house", "squad", "stable"]:
		if not at.has(rule):
			bad.append("нет шага «%s»" % rule)
			continue
		if not at.has("iron") or int(at[rule]) < int(at["iron"]):
			bad.append("«%s» раньше железа" % rule)
		if int(at[rule]) >= last:
			bad.append("«%s» не раньше штурма" % rule)
	note("у злодея шагов %d, захват последний" % chain.size())
	check(bad.is_empty(),
		"база и армия объясняются до штурма, захват — последний шаг",
		", ".join(bad))


## Сменилась сторона — цепочка начинается заново и не валится за границу.
##
## ЗАЧЕМ. Цепочки у сторон РАЗНОЙ ДЛИНЫ: у злодея одиннадцать шагов, у стражи
## четыре. Прогресс жил сам по себе, и дойдя до шестого шага за злодея, а потом
## получив стража, подсказка обращалась к шагу номер пять в массиве из четырёх.
## Проверки при этом были ЗЕЛЁНЫМИ — поймало правило «ругань движка в логе тоже
## провал»: лог набора «стража» вырос на 3220 ошибок.
func _test_faction_change_restarts_the_chain(me: Node3D) -> void:
	var guide := ONBOARDING.new()
	var was: int = int(me.faction)
	var long_side := FACTIONS.Kind.VILLAIN
	var short_side := FACTIONS.Kind.GUARD

	me.faction = long_side
	guide.current(_world, me)
	guide._passed = guide.chain_of(long_side).size() - 1
	var far: int = int(guide.current(_world, me).get("number", 0))

	me.faction = short_side
	var after: Dictionary = guide.current(_world, me)
	me.faction = was

	var short_len: int = guide.chain_of(short_side).size()
	check(far > short_len and int(after.get("number", 0)) == 1
			and int(after.get("total", 0)) == short_len,
		"смена стороны начинает цепочку заново",
		"было %d из длинной, стало %d из %d" % [far,
			int(after.get("number", 0)), int(after.get("total", 0))])
