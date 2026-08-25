extends Node
##
## Съёмка карты с заданных ракурсов в PNG. Инструмент проверки, не геймплей.
##
## Запуск (обязательно с окном — headless не рисует):
##   godot --path godot_project --resolution 1600x900 -- --host --shots=C:/куда/класть
##
## Игра поднимает локальный хост, персонаж спавнится, затем камера обходит
## список ракурсов и сохраняет по кадру на каждый. В конце процесс завершается.
##

## Пауза перед первым кадром: миру нужно построиться, персонажу — приземлиться.
const WARMUP_SECONDS := 1.5

var out_dir := ""

var _world: Node3D
var _cam: Camera3D


## Ракурсы: имя файла, позиция камеры, точка взгляда.
## "strategy" вместо позиции означает штатную стратегическую камеру игры.
func _shots() -> Array:
	return [
		{
			"name": "01_вся_карта",
			"pos": Vector3(-780, 620, 780),
			"look": Vector3(0, 0, 0),
		},
		{
			"name": "02_перекрёсток_с_земли",
			"pos": Vector3(48, 6, 60),
			"look": Vector3(0, 8, 0),
		},
		{
			"name": "03_зона_эльфов_лес",
			"pos": Vector3(-300, 130, 60),
			"look": Vector3(-300, 10, -300),
		},
		{
			"name": "04_зона_императора_дворец",
			"pos": Vector3(300, 150, 60),
			"look": Vector3(300, 30, -300),
		},
		{
			"name": "05_зона_злодея_форт",
			"pos": Vector3(-300, 160, 640),
			"look": Vector3(-300, 20, 260),
		},
		{
			"name": "06_зона_людей_деревня",
			"pos": Vector3(300, 110, 560),
			"look": Vector3(300, 5, 300),
		},
		{
			"name": "07_шахта_злодея",
			"pos": Vector3(-560, 90, 590),
			"look": Vector3(-470, 10, 470),
		},
		{
			"name": "08_дворец_вблизи",
			"pos": Vector3(300, 45, -180),
			"look": Vector3(300, 40, -300),
		},
		{"name": "09_стратегическая_камера", "strategy": true},
	]


func start(world: Node3D, dir: String) -> void:
	_world = world
	out_dir = dir
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(WARMUP_SECONDS).timeout

	_cam = Camera3D.new()
	_cam.far = 4000.0
	add_child(_cam)

	var saved := 0
	for shot in _shots():
		if shot.get("strategy", false):
			_world.set_strategy_mode(true)
		else:
			_world.set_strategy_mode(false)
			_cam.current = true
			_cam.global_position = shot["pos"]
			_cam.look_at(shot["look"], Vector3.UP)

		# Два кадра: первый применяет трансформ, второй гарантированно отрисован.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var path := "%s/%s.png" % [out_dir, shot["name"]]
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(path)
		if err == OK:
			saved += 1
			print("[shot] ", path)
		else:
			push_warning("Не удалось сохранить %s (код %d)" % [path, err])

	print("[shot] готово, кадров: %d" % saved)
	get_tree().quit()
