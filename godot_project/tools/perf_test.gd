extends Node
##
## Замер fps в обоих режимах камеры. Нужен, потому что глазами по одному кадру
## производительность не оценить: счётчик в HUD усредняется за секунду и после
## переключения камеры показывает провал, которого может уже не быть.
##
## Запуск (нужно окно — headless не рисует):
##   godot --path godot_project --resolution 1600x900 -- --host --perftest
##

const WARMUP := 2.0
const SAMPLE_SECONDS := 4.0

var _world: Node3D


func start(world: Node3D) -> void:
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(WARMUP).timeout

	_world.set_strategy_mode(false)
	await _settle()
	print("[perf] экшен-камера (от третьего лица): %.0f fps" % await _measure())

	for h in [90.0, 200.0, 340.0]:
		_world.set_strategy_mode(false)
		_world.set_strategy_mode(true, h)
		await _settle()
		print("[perf] стратегическая камера, высота %d м: %.0f fps" % [int(h), await _measure()])

	# ЗАМЕР В ПУСТОМ МИРЕ НИЧЕГО НЕ ЗНАЧИТ.
	#
	# Свежая партия — это четыре домика и десяток человек, и с такой нагрузкой
	# любая сборка покажет свои двести сорок. Тестер увидит игру на двадцатой
	# минуте: два десятка построенных домов, полсотни скиннутых персонажей на
	# экране, обозы. Именно там и просядет, если просядет, — и узнать об этом
	# надо здесь, а не из отчёта.
	await _crowd()
	_world.set_strategy_mode(false)
	await _settle()
	print("[perf] людно, экшен-камера: %.0f fps" % await _measure())
	_world.set_strategy_mode(true, 120.0)
	await _settle()
	print("[perf] людно, стратегическая камера: %.0f fps" % await _measure())

	get_tree().quit()


## Набить сцену тем, что в ней бывает к середине партии: домами и людьми.
##
## Числа с запасом против настоящей партии: потолок отряда меньше, построек
## столько не бывает. Если провалится здесь — в игре будет запас; если нет,
## запас тем более.
func _crowd() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	var here := me.global_position
	var kinds := [0, 1, 2, 3]
	for i in 12:
		var at := here + Vector3(-40.0 + float(i % 4) * 26.0, 0.0, -30.0 - float(i / 4) * 24.0)
		_world.spawn_building(kinds[i % kinds.size()], at, int(me.peer_id), int(me.faction), true)
	for i in 40:
		var at := here + Vector3(-20.0 + float(i % 8) * 3.0, 1.0, -10.0 - float(i / 8) * 3.0)
		_world.spawn_unit(int(me.peer_id), i, at, false, i % 3 == 0)
	# Дать им построиться, а анимациям — начать играть.
	await get_tree().create_timer(3.0).timeout


## Дать кадрам устояться после переключения, чтобы не мерить разовый скачок.
func _settle() -> void:
	for i in 30:
		await get_tree().process_frame


func _measure() -> float:
	var frames := 0
	var t0 := Time.get_ticks_usec()
	var limit := int(SAMPLE_SECONDS * 1000000.0)
	while Time.get_ticks_usec() - t0 < limit:
		await get_tree().process_frame
		frames += 1
	var elapsed := (Time.get_ticks_usec() - t0) / 1000000.0
	return frames / elapsed
