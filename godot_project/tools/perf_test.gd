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

	get_tree().quit()


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
