extends Node
##
## Снимки интерфейса в PNG. Инструмент проверки, не геймплей.
##
## Запуск (обязательно с окном — headless не рисует ни мир, ни иконки):
##   godot --path godot_project --resolution 1280x720 -- --host --faction=0 --hudshots=C:/куда
##
## Снимает то, что проверками не увидеть: как ЛЕЖАТ панели на экране базового
## размера, читаются ли иконки, не налезает ли одно на другое. Проверка скажет,
## что карточка есть и щёлкается; налезла ли она на соседнюю — только глаза.
##

const RES := preload("res://scripts/economy/resources.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")

var out_dir := ""
var _world: Node3D


func start(world: Node3D, dir: String) -> void:
	_world = world
	out_dir = dir
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(3.0).timeout
	var main: Node = _world.get_parent()
	# Ждём снимков иконок: без них на кадре были бы плашки-заглушки.
	for i in 40:
		if main._icons.rendered:
			break
		await get_tree().create_timer(0.25).timeout
	var me: Node3D = _world.local_player()
	var wallet: Node = _world.treasury.of(int(me.faction))
	wallet.grant(RES.fit([120, 60, 40, 5, 30, 0]))
	wallet.horses = 3
	var home: Vector3 = me.global_position
	for role in [0, 0, 1, 3, 4]:
		_world.spawn_labourer(int(me.faction), home + Vector3(4.0, 0.0, 4.0), home, role)
	await get_tree().create_timer(1.0).timeout

	# Заклинание на откате и лошадь под боком: так на кадре видны и затемнение
	# слота, и строка действия с клавишей и картинкой.
	me.armor_tier = 2
	me.sync_ability_cd[4] = 9.0
	me.mana = 20.0
	_world.spawn_horse(me.global_position + me.global_transform.basis.z * -2.5)
	await get_tree().create_timer(0.8).timeout
	await _shot("01_бой")
	_world.set_strategy_mode(true)
	await get_tree().create_timer(1.5).timeout
	await _shot("02_сверху")
	_world.set_build_mode(true, RES.Building.STORAGE)
	await get_tree().create_timer(0.5).timeout
	await _shot("03_сверху_стройка")
	_world.set_build_mode(false, 0)
	_world.set_strategy_mode(false)
	main._settings.show_keys(false)
	await get_tree().create_timer(0.5).timeout
	await _shot("04_клавиши")
	main._settings.show_pause()
	await get_tree().create_timer(0.3).timeout
	await _shot("05_пауза")
	main._settings.close()
	main._trader.visible = true
	main._refresh_trader(me)
	await get_tree().create_timer(0.3).timeout
	await _shot("06_лавка")
	main._trader.visible = false
	main._bench.visible = true
	main._refresh_bench(me)
	await get_tree().create_timer(0.3).timeout
	await _shot("07_верстак")
	main._bench.visible = false
	var stable: Node3D = _world.spawn_building(RES.Building.STABLE,
		me.global_position + Vector3(9.0, 0.0, 0.0), 0, int(me.faction), true)
	await get_tree().create_timer(0.5).timeout
	main._building_ui.open_for(_world, me, stable)
	await get_tree().create_timer(0.3).timeout
	await _shot("08_конюшня")
	main._building_ui.close_panel()
	# Латы на теле: камера спереди, на уровне груди.
	var eye := Camera3D.new()
	_world.add_child(eye)
	var chest: Vector3 = me.global_position + Vector3(0.0, 1.3, 0.0)
	var facing: Vector3 = -me.global_transform.basis.z
	eye.look_at_from_position(chest + facing * 3.2 + Vector3(0.8, 0.4, 0.0), chest)
	eye.current = true
	main._hud.visible = false
	await get_tree().create_timer(0.4).timeout
	await _shot("09_латы")
	main._hud.visible = true
	print("[снимки интерфейса] готово: %s" % out_dir)
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % name)
	image.save_png(path)
	print("[снимки интерфейса] %s" % path)
