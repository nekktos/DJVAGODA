extends "res://tools/test_base.gd"
##
## Автопроверка ПЕРЕЗАХОДА: вышел в меню — вернулся — всё на месте и в одном
## экземпляре. Работает headless.
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ НАБОР. Сохранение проверено по частям: что пишется, что
## читается, что мир чистится перед стартом. Сам ПУТЬ, которым человек по этому
## всему проходит, не проверял никто — а он и есть самый ломкий:
##
##   выход в меню → сеть свернулась → мир остановился → «Продолжить» →
##   мир очищен → сеть поднялась заново → сохранение накатано → персонаж встал.
##
## Здесь семь переходов подряд в одном запущенном процессе, и половина из них
## трогает то, что обычно делается ровно один раз за жизнь программы: порт,
## спавнеры, подписки на сигналы. Ошибка тут выглядит для человека так:
## «вышел в меню, нажал Продолжить — не работает» или, что хуже, «вернулся, а
## домов вдвое больше».
##
## УДВОЕНИЕ — главное, что здесь ловится. Проверять «дома вернулись» мало:
## вернуться они могут и поверх не убранных старых, и разницу между «пять» и
## «пять плюс пять» видно только если считать.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=0 --reentrytest
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")

## Где ставим приметную постройку: по ней узнаём, что вернулся ТОТ мир.
const LANDMARK := Vector3(130.0, 0.0, -70.0)

var _world: Node3D
var _main: Node


func start(world: Node3D) -> void:
	tag = "перезаход"
	expected_host = 14
	expected_client = 1
	_world = world
	_main = world.get_parent()
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	if not session_ready():
		finish()
		return
	if not Net.hosting():
		check(_world.local_player() != null, "клиент в мире", "персонаж есть")
		finish()
		return

	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	var side: int = int(me.faction)
	var peer: int = int(me.peer_id)
	var wallet: Node = _world.treasury.of(side)

	# --- нажили ---------------------------------------------------------
	_world.spawn_building(RES.Building.STORAGE, LANDMARK, peer, side, true)
	_world.spawn_labourer(side, LANDMARK + Vector3(2.0, 0.5, 0.0), LANDMARK, 0)
	_world.spawn_labourer(side, LANDMARK + Vector3(-2.0, 0.5, 0.0), LANDMARK, 2)
	for node in _world.units_of(peer):
		node.free()
	_world.spawn_unit(peer, 0, LANDMARK + Vector3(0.0, 1.0, 3.0), false, false)
	_world.spawn_unit(peer, 1, LANDMARK + Vector3(0.0, 1.0, -3.0), false, true)
	wallet.stored.capacity = 1234
	# Куча груза и свободная лошадь — то, чего в сохранении НЕТ вовсе. Они и
	# показывают, зачем мир чистится перед стартом: восстановление кладёт
	# обратно только записанное, а брошенное прошлой сессией так и осталось бы
	# стоять посреди загруженной партии, как чужое наследство.
	_world.spawn_loot_pile(LANDMARK + Vector3(6.0, 0.5, 0.0), PackedInt32Array([5, 0, 0, 0]))
	_world.spawn_horse(LANDMARK + Vector3(-6.0, 0.5, 0.0))
	await get_tree().physics_frame

	var houses: int = _houses()
	var hands: int = _world.labourers_of(side).size()
	var squad: int = _world.units_of(peer).size()
	check(houses >= 1 and hands >= 2 and squad == 2, "нажитое на месте",
		"домов %d, батраков %d, бойцов %d" % [houses, hands, squad])
	check(_loose() > 0, "и брошенное тоже: куча и лошадь", "%d штук" % _loose())
	check(not _save().save_world().is_empty(), "и сохранено", _save().save_path())

	# --- вышли в меню ---------------------------------------------------
	# Меняем потолок склада ПОСЛЕ сохранения и больше не сохраняем сами. Если
	# после возвращения вернётся 4321, значит выход в меню сохранился сам; если
	# 1234 — значит человек, вышедший через минуту после стройки, теряет её.
	wallet.stored.capacity = 4321
	await get_tree().physics_frame
	Net.leave()
	await get_tree().create_timer(1.0).timeout
	check(not Net.active, "вышли в меню: сессии нет", "сеть свёрнута")
	check(_world.local_player() == null, "и персонажа в мире нет", "убран")

	# --- вернулись тем же путём, что и человек --------------------------
	# Жмём именно кнопку меню, а не `Net.host_game()` напрямую: проверяется
	# путь целиком, вместе с очисткой мира, которую делает кнопка. Позвав сеть
	# в обход неё, мы проверили бы половину и не заметили бы удвоения.
	_main._on_continue_pressed()
	await get_tree().create_timer(3.0).timeout
	check(Net.hosting(), "«Продолжить» подняло сессию заново",
		"хост" if Net.hosting() else "сети нет")

	var back: Node3D = _world.local_player()
	check(back != null, "персонаж вернулся в мир", "есть" if back != null else "нет")
	if back == null:
		finish()
		return

	# --- и ничего не удвоилось ------------------------------------------
	check(_houses() == houses, "ПОСТРОЙКИ вернулись, и ровно столько же",
		"%d было, %d стало" % [houses, _houses()])
	check(_world.labourers_of(side).size() == hands,
		"БАТРАКИ вернулись, и ровно столько же",
		"%d было, %d стало" % [hands, _world.labourers_of(side).size()])
	check(_world.units_of(int(back.peer_id)).size() == squad,
		"ОТРЯД вернулся, и ровно столько же",
		"%d было, %d стало" % [squad, _world.units_of(int(back.peer_id)).size()])

	var purse: Node = _world.treasury.of(int(back.faction))
	check(int(purse.stored.capacity) == 4321,
		"ВЫХОД В МЕНЮ сохранил нажитое после автосейва",
		"потолок %d — 1234 значит потеряно" % int(purse.stored.capacity))
	check(_at_landmark() != null, "приметный склад стоит там же, где стоял",
		"(%.0f, %.0f)" % [LANDMARK.x, LANDMARK.z])
	# А брошенное — НЕ вернулось. Его не было в файле, значит в загруженной
	# партии ему взяться неоткуда: если оно тут, мир перед стартом не чистили.
	check(_loose() == 0, "брошенное прошлой сессией не переехало",
		"%d осталось" % _loose())
	# И мир после возвращения снова ИДЁТ. Выход в меню его останавливает, и
	# незапущенный обратно он выглядел бы как «вернулся, а всё замерло»: люди
	# стоят, шахта не копит, ИИ не шевелится. Спрашиваем шахту, а не флаг:
	# флаг может стоять правильно при остановленном поддереве.
	_world.mine.stored = PackedInt32Array([0, 0, 0, 0])
	await get_tree().create_timer(1.5).timeout
	check(_world.mine.stored != PackedInt32Array([0, 0, 0, 0]),
		"и мир снова ИДЁТ, а не замер", str(_world.mine.stored))

	finish()


func _save() -> Node:
	return _world.savegame


## Что валяется в мире, но в сохранении не значится: кучи груза и вольные
## лошади. Ими и проверяется очистка мира перед стартом.
func _loose() -> int:
	return get_tree().get_nodes_in_group("loot").size() \
		+ get_tree().get_nodes_in_group("horse").size()


func _houses() -> int:
	return get_tree().get_nodes_in_group("building").size()


func _at_landmark() -> Node:
	for node in get_tree().get_nodes_in_group("building"):
		if node.position.distance_to(LANDMARK) < 0.5:
			return node
	return null
