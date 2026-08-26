extends "res://tools/test_base.gd"
##
## Автопроверка impostor-леса (Этап 8). Работает headless.
##
## Запуск одним пиром:
##   godot --headless --path godot_project -- --host --foresttest
## Двумя пирами (проверяется репликация рубки):
##   тот же ключ на хосте и на клиенте.
##

const FOREST := preload("res://scripts/forest.gd")
const RES := preload("res://scripts/economy/resources.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "лес"
	expected_host = 20
	expected_client = 2
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	var forest: Node = _world.forest
	if me == null or forest == null:
		fail("персонаж или лес не готовы")
		finish()
		return

	if not multiplayer.is_server():
		await _run_client(forest)
		finish()
		return

	_test_generation(forest)
	await _test_far_is_impostor(forest)
	await _test_near_becomes_solid(me, forest)
	await _test_hysteresis(me, forest)
	await _test_felling(me, forest)
	# Если рядом есть клиент, он проверяет репликацию рубки и ему нужно время.
	# Хост, закрывшись раньше, обрывает ему сессию и валит его тест.
	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(9.0).timeout
	finish()


## Лес построен целиком и в границах зоны, поляна под поселение свободна.
func _test_generation(forest: Node) -> void:
	var count: int = forest.tree_count()
	check(count == FOREST.TREE_COUNT, "плотность леса", "%d деревьев" % count)

	var centre := Vector2(-300.0, -300.0)
	var outside := 0
	var in_clearing := 0
	for i in count:
		var p: Vector3 = forest.tree_position(i)
		var d := Vector2(p.x, p.z).distance_to(centre)
		if d > 270.0:
			outside += 1
		if d < 70.0:
			in_clearing += 1
	check(outside == 0, "деревья в границах зоны", "за границей: %d" % outside)
	check(in_clearing == 0, "поляна под поселением свободна", "в поляне: %d" % in_clearing)


## Пока рядом никого нет, объёмных деревьев быть не должно — только билборды.
##
## Уводим ВСЕХ игроков, а не только своего: коллизия деревьев зависит от
## игровых объектов, а не от камеры, и второй игрок за эльфов спавнится прямо
## в лесу.
func _test_far_is_impostor(forest: Node) -> void:
	_teleport_everyone(Vector3(300.0, 2.0, 300.0))     # зона людей, лес далеко
	await get_tree().physics_frame
	await get_tree().physics_frame
	forest.refresh_lod()
	check(forest.near_count() == 0, "далеко от леса — только билборды",
		"объёмных: %d" % forest.near_count())
	check(forest.impostor_visible(0), "билборд дерева 0 виден", "да")


## Рядом с игроком дерево становится объёмным и обзаводится коллизией.
func _test_near_becomes_solid(me: Node3D, forest: Node) -> void:
	var target: Vector3 = forest.tree_position(0)
	me.global_position = target + Vector3(6.0, 2.0, 0.0)
	await get_tree().physics_frame
	forest.refresh_lod()

	check(forest.is_near(0), "дерево рядом стало объёмным", "near=%s" % forest.is_near(0))
	check(forest.is_solid(0), "у него есть коллизия", "solid=%s" % forest.is_solid(0))
	check(not forest.impostor_visible(0), "билборд при этом спрятан", "скрыт")
	check(forest.near_count() > 0 and forest.near_count() < FOREST.TREE_COUNT,
		"объёмными стали не все", "объёмных: %d из %d" % [forest.near_count(), FOREST.TREE_COUNT])


## Гистерезис: между радиусом входа и радиусом выхода дерево НЕ должно
## переключаться. Без этого оно мигает на границе каждый кадр.
func _test_hysteresis(me: Node3D, forest: Node) -> void:
	var target: Vector3 = forest.tree_position(0)
	# Точка между SOLID_RADIUS и SOLID_RELEASE: войти бы не смогли, но раз уже
	# внутри — должны остаться.
	var between := (FOREST.SOLID_RADIUS + FOREST.SOLID_RELEASE) * 0.5
	me.global_position = target + Vector3(between, 2.0, 0.0)
	await get_tree().physics_frame
	forest.refresh_lod()
	check(forest.is_solid(0), "в зоне гистерезиса дерево осталось твёрдым",
		"на %.0f м, вход %.0f, выход %.0f" % [between, FOREST.SOLID_RADIUS, FOREST.SOLID_RELEASE])

	# А за радиусом выхода — обязано отпустить и вернуться в билборд.
	me.global_position = target + Vector3(FOREST.VISUAL_RELEASE + 20.0, 2.0, 0.0)
	await get_tree().physics_frame
	forest.refresh_lod()
	check(not forest.is_near(0), "за радиусом выхода вернулось в билборд",
		"near=%s" % forest.is_near(0))
	check(forest.impostor_visible(0), "билборд снова виден", "да")


## Рубка: счётчик ударов, падение дерева и исчезновение из обоих слоёв.
func _test_felling(me: Node3D, forest: Node) -> void:
	var index := 1
	var target: Vector3 = forest.tree_position(index)
	me.global_position = target + Vector3(5.0, 2.0, 0.0)
	await get_tree().physics_frame
	forest.refresh_lod()

	var start: int = forest.hits_left(index)
	check(start == RES.SOURCE_HITS, "запас ударов у дерева", "%d" % start)

	var left: int = forest.hit_tree(index)
	check(left == start - 1, "удар уменьшает счётчик", "осталось %d" % left)

	while forest.hit_tree(index) > 0:
		pass
	forest.fell_tree.rpc(index)
	await get_tree().physics_frame

	check(forest.is_felled(index), "дерево срублено", "да")
	check(not forest.is_near(index), "объёмное дерево убрано", "near=%s" % forest.is_near(index))
	check(not forest.impostor_visible(index), "билборд убран", "скрыт")
	check(forest.felled_indices().has(index), "попало в список для догрузки",
		"срублено всего: %d" % forest.felled_count())

	# Повторный вызов не должен ломать состояние: пакет может прийти дважды.
	forest.fell_tree.rpc(index)
	await get_tree().physics_frame
	check(forest.felled_count() == 1, "повторная команда не задваивает",
		"срублено: %d" % forest.felled_count())

	# Срубленное дерево нельзя ударить ещё раз.
	check(forest.hit_tree(index) == -1, "срубленное дерево не бьётся", "-1")


## Развести всех игроков по одной далёкой точке. Разброс, чтобы не толкались.
func _teleport_everyone(point: Vector3) -> void:
	var i := 0
	for child in _world.get_node("Players").get_children():
		if child.has_method("teleport"):
			child.teleport.rpc(point + Vector3(i * 4.0, 0.0, 0.0))
		i += 1


## Клиентская половина: лес детерминирован, значит совпадает с хостом,
## а рубка хоста доезжает по сети.
func _run_client(forest: Node) -> void:
	check(forest.tree_count() == FOREST.TREE_COUNT, "лес построен и на клиенте",
		"%d деревьев" % forest.tree_count())
	# Ждём, пока хост дойдёт до проверки рубки.
	await get_tree().create_timer(7.0).timeout
	check(forest.felled_count() > 0, "рубка хоста доехала до клиента",
		"срублено: %d" % forest.felled_count())
