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
		{
			"name": "10_кровь_и_трупы",
			"pos": Vector3(14, 4, 34),
			"look": Vector3(0, 1, 20),
			"gore": true,
		},
		{
			"name": "11_расчленение",
			"pos": Vector3(-11.0, 1.9, 17.2),
			"look": Vector3(-14, 1.0, 14),
			"wounds": true,
		},
		{
			"name": "12_слепота_на_половину_экрана",
			"pos": Vector3(-11.0, 1.9, 17.2),
			"look": Vector3(-14, 1.0, 14),
			"blind": true,
		},
		{
			"name": "13_ползание_без_ноги",
			"pos": Vector3(-11.0, 1.9, 17.2),
			"look": Vector3(-14, 0.5, 14),
			"crawl": true,
		},
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
		if shot.get("gore", false):
			_stage_gore()
			await get_tree().create_timer(0.4).timeout
		if shot.get("wounds", false):
			_stage_wounds(false)
			# Даём оторванным частям упасть на землю.
			await get_tree().create_timer(1.6).timeout
		if shot.get("blind", false):
			_stage_wounds(true)
			await get_tree().create_timer(0.6).timeout
		if shot.get("crawl", false):
			_stage_wounds(false, true)
			await get_tree().create_timer(1.6).timeout
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

		var me: Node3D = _world.local_player()
		print("[shot] %s | камера %s -> смотрит %s | персонаж %s" % [
			shot["name"], _cam.global_position, _cam.global_transform.basis.z * -1.0,
			me.global_position if me != null else Vector3.ZERO,
		])
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


## Разложить перед камерой трупы и плеснуть кровью: рейтинг 21+, эту часть тоже
## надо видеть на скриншоте, а не принимать на веру.
func _stage_gore() -> void:
	const EFFECTS := preload("res://scripts/combat/effects.gd")
	var spots := [
		Vector3(-2.0, 0.0, 18.0),
		Vector3(1.5, 0.0, 20.5),
		Vector3(-4.0, 0.0, 22.0),
	]
	for i in spots.size():
		_world.place_corpse(spots[i], float(i) * 1.3, i)
		EFFECTS.blood(_world, spots[i] + Vector3.UP * 1.0, Vector3.UP, 60.0)


## Оторвать персонажу руку и ногу, чтобы было видно расчленение и упавшие
## части. С take_eye — ещё и глаз, для кадра со слепотой.
func _stage_wounds(take_eye: bool, legs: bool = false) -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	# Начинаем с чистого тела: иначе последствия предыдущего кадра переезжают
	# в следующий и кадр показывает не то, что подписано.
	me.body.reset()
	me.health.revive()
	var zones := ["arm_l", "leg_r"] if legs else ["arm_l"]
	for zone in zones:
		for i in 6:
			me.body.register_hit(zone, 12.0)
			me.health.revive()
	if take_eye:
		me.body.register_hit("head", 40.0)
		me.health.revive()
	# Кровотечение гасим: иначе персонаж умрёт прямо в кадре.
	me.body.bleeding = false
