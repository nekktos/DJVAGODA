extends "res://tools/test_base.gd"
##
## Автопроверка проходимости grey-box карты. Работает headless — физика в нём
## считается, окно не нужно.
##
## Запуск:
##   godot --headless --path godot_project -- --host --walktest
##
## Смысл: убедиться, что по карте реально можно ходить, а не только смотреть на
## неё. Скриншот показывает, что объект нарисован; этот тест показывает, что до
## него можно дойти.
##

class Scenario:
	var name: String
	var start: Vector3
	var move: Vector2
	var seconds: float
	var check: Callable
	var expectation: String

	func _init(n: String, s: Vector3, m: Vector2, sec: float, exp: String, c: Callable) -> void:
		name = n
		start = s
		move = m
		seconds = sec
		expectation = exp
		check = c


var _world: Node3D


func start(world: Node3D) -> void:
	tag = "walk"
	expected_host = 10
	expected_client = 7
	_world = world
	_run.call_deferred()


func _scenarios() -> Array:
	return [
		# Вход во дворец. Раньше дворец был монолитным кубом, точка захвата лежала
		# внутри камня, и условие победы злодея было невыполнимо — это нашёл живой
		# тестер, а ни одна автопроверка не видела. Теперь проверяем именно то,
		# что он делал: дойти до точки захвата.
		Scenario.new(
			"вход во дворец через ворота",
			Vector3(300.0, 7.0, -250.0), Vector2(0.0, -1.0), 14.0,
			"дошёл до точки захвата (ближе 30 м от центра дворца)",
			func(p: Vector3) -> bool: return Vector2(p.x, p.z).distance_to(Vector2(300.0, -300.0)) < 30.0
		),
		Scenario.new(
			"пандус на плато императора",
			Vector3(300.0, 2.0, -55.0), Vector2(0.0, -1.0), 16.0,
			"поднялся на плато (y >= 5.5)",
			func(p: Vector3) -> bool: return p.y >= 5.5
		),
		Scenario.new(
			"ворота форта злодея",
			Vector3(-300.0, 2.0, 370.0), Vector2(0.0, -1.0), 12.0,
			"прошёл сквозь стену внутрь двора (z < 320)",
			func(p: Vector3) -> bool: return p.z < 320.0
		),
		Scenario.new(
			"открытая равнина рядом с перекрёстком",
			# Специально в стороне от обелиска на (0,0): в него персонаж упирается,
			# и это правильное поведение, а не то, что здесь проверяется.
			Vector3(-60.0, 2.0, 60.0), Vector2(0.0, -1.0), 10.0,
			"прошёл не меньше 50 м без помех",
			func(p: Vector3) -> bool: return p.z < 10.0
		),
		# Порог поднят с полутора метров до шести, и это не поблажка.
		#
		# У мира появился рельеф: под плато лежит не идеальная плоскость, а поле
		# с холмами до двадцати с лишним метров. «Спустился к земле» больше не
		# значит «оказался на нуле» — значит «сошёл с плато», а плато здесь
		# высотой в восемь. Прежний порог проверял отсутствие рельефа, а не
		# спуск, и упал в тот же день, когда рельеф появился.
		Scenario.new(
			"спуск с плато императора обратно",
			Vector3(300.0, 8.0, -130.0), Vector2(0.0, 1.0), 14.0,
			"сошёл с плато и не застрял (y < 6)",
			func(p: Vector3) -> bool: return p.y < 6.0
		),
	]


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	var player: Node3D = _world.local_player()
	if player == null:
		fail("персонаж не заспавнен")
		finish()
		return

	for s in _scenarios():
		player.global_position = s.start
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.scripted_input = {"move": s.move, "jump": false}
		await get_tree().create_timer(s.seconds).timeout
		player.scripted_input = {}

		var p: Vector3 = player.global_position
		var ok: bool = s.check.call(p)
		check(ok, s.name, "итог (%.1f, %.1f, %.1f), ожидалось: %s" % [
			p.x, p.y, p.z, s.expectation
		])

	# Анимация ходьбы должна ИГРАТЬ и быть зациклена, пока персонаж идёт.
	# Без цикла она проигрывалась один раз, и дальше персонаж ехал в позе
	# последнего кадра — на playtest это выглядело как катающиеся пешки.
	player.global_position = Vector3(-60.0, 2.0, 60.0)
	player.scripted_input = {"move": Vector2(0.0, -1.0), "jump": false}
	await get_tree().create_timer(3.0).timeout
	var anim: Dictionary = player.animation_state()
	player.scripted_input = {}

	var walking: bool = bool(anim.get("playing", false)) and String(anim.get("name", "")) == "walk"
	var looping: bool = bool(anim.get("looping", false))
	check(walking, "анимация ходьбы играет", str(anim))
	check(looping, "анимация ходьбы зациклена", str(looping))

	await _test_sprint(player)
	finish()


## Бег на Shift: дальше за то же время и другой анимацией.
##
## Меряем ПРОЙДЕННОЕ РАССТОЯНИЕ, а не выставленную скорость: скорость проходит
## через ранения, благословение и седло, и проверка выставленного числа
## разошлась бы с тем, что видит игрок, при первой же правке любого из них.
func _test_sprint(player: Node3D) -> void:
	var walked: float = await _dash(player, false)
	var ran: float = await _dash(player, true)
	check(ran > walked * 1.4, "бегом дальше, чем шагом",
		"%.1f м против %.1f за те же две секунды" % [ran, walked])

	# И бег ВИДНО: чужой персонаж, кроющий землю бегом переставляя ноги шагом,
	# читается как ошибка сети.
	player.global_position = Vector3(-60.0, 2.0, 60.0)
	player.velocity = Vector3.ZERO
	player.scripted_input = {"move": Vector2(0.0, -1.0), "jump": false, "run": true}
	await get_tree().create_timer(1.5).timeout
	var anim: Dictionary = player.animation_state()
	player.scripted_input = {}
	check(String(anim.get("name", "")) == "run", "на бегу играет анимация бега", str(anim))

	# Ползущий не бежит: без ноги персонаж и так еле двигается, и «бег ползком»
	# был бы издевательством, а не механикой.
	player.body.severed_mask = player.body.severed_mask | 0b0100
	var crawled: float = await _dash(player, true)
	player.body.severed_mask = 0
	check(crawled < walked, "безногий не разгоняется бегом",
		"%.1f м против %.1f шагом на своих двоих" % [crawled, walked])


## Пробежка на две секунды по прямой. Возвращает пройденное расстояние.
func _dash(player: Node3D, running: bool) -> float:
	player.global_position = Vector3(-60.0, 2.0, 60.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	await get_tree().physics_frame
	var from: Vector3 = player.global_position
	player.scripted_input = {"move": Vector2(0.0, -1.0), "jump": false, "run": running}
	await get_tree().create_timer(2.0).timeout
	player.scripted_input = {}
	var to: Vector3 = player.global_position
	return Vector2(to.x - from.x, to.z - from.z).length()
