extends Node
##
## Снимок ГЛАВНОГО МЕНЮ, а не мира.
##
## Автопроверка `--newgametest` жмёт обработчики кнопок напрямую и знает, что
## они делают. Чего она не знает — как меню ВЫГЛЯДИТ: влезла ли подпись, не
## разъехалась ли панель от двух новых строк, читается ли текст. Это ровно тот
## разряд ошибок, которые не ловятся ничем, кроме глаза, и потому им нужен
## снимок, а не проверка.
##
## Сессию не поднимаем: меню видно, только пока её нет.
##
## Запуск (нужно окно, не headless):
##   godot --path godot_project -- --menushot=ПАПКА
##

## Сколько ждём перед снимком. Меню рисуется мгновенно, но окну надо появиться.
const SETTLE_SECONDS := 1.2

var _dir := ""
var _main: Node = null


func start(main: Node, dir: String) -> void:
	_main = main
	_dir = dir
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)
	await get_tree().create_timer(SETTLE_SECONDS).timeout

	# Два состояния, а не одно: пустое меню и меню с сохранением выглядят
	# по-разному, и разъехаться может любое из них.
	_shoot("menu-1-как-есть")

	# Переспрос «Новой игры» — самая длинная надпись на кнопке во всей игре.
	# Если её обрежет, узнать об этом надо здесь, а не от тестера.
	_main._on_new_pressed()
	await get_tree().process_frame
	_shoot("menu-2-переспрос")
	_main._reset_new_button()

	await get_tree().process_frame
	print("[меню-снимок] готово: %s" % _dir)
	get_tree().quit()


func _shoot(name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, name]
	image.save_png(path)
	print("[меню-снимок] %s" % path)
