extends "res://tools/test_base.gd"
##
## Автопроверка лошадей, упряжки и разграбления обоза (решение по ходу Этапа 10).
## Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --horsetest
##
## Хост берёт злодея: конюшня, обозы и лошади — его хозяйство, у эльфов и стражи
## этого нет вовсе.
##
## Проверяем не «лошадь добавлена», а то, ради чего она нужна: что от числа
## лошадей зависит скорость, что обоз без них стоит, что за ним нельзя убежать,
## и что все три способа отъёма дают РАЗНОЕ. Проверка «лошадь есть» была бы
## зелёной и бесполезной.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const CARAVAN := preload("res://scripts/economy/caravan.gd")
const HORSE := preload("res://scripts/units/horse.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "лошади"
	expected_host = 18
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	_test_starting_stock(me)
	_test_speed_grows_with_team()
	await _test_halts_when_chased(me)
	await _test_harness_can_be_killed(me)
	await _test_capture_gives_live_horses(me)
	await _test_riding(me)
	finish()


## Стартовое хозяйство: лошади есть с самого начала и их хватает на две упряжки.
##
## Это не мелочь и не украшение. Пока их не было, выходил замкнутый круг: обозу
## нужны лошади, лошадям конюшня, конюшне железо, а железо возит обоз. Сторона
## под ИИ на этом вставала намертво — за пять минут успевала поставить склад и
## больше ничего.
func _test_starting_stock(me: Node3D) -> void:
	var wallet: Node = _world.treasury.of(int(me.faction))
	check(wallet != null and wallet.horses >= 2 * CARAVAN.HORSES_MIN,
		"у злодея есть лошади на старте",
		"%d в конюшне" % (wallet.horses if wallet != null else -1))
	check(wallet != null and wallet.horses_free() == wallet.horses,
		"все они свободны, пока обозы не вышли",
		"свободно %d" % (wallet.horses_free() if wallet != null else -1))


## Скорость растёт от упряжки — но не пропорционально числу лошадей.
##
## Ровно эта нелинейность делает перехват возможным: шестёрка втрое быстрее
## одиночки, а не вшестеро. Иначе полная упряжка обгоняет всадника, и никакой
## расчёт точки встречи не поможет.
func _test_speed_grows_with_team() -> void:
	var cart: Node3D = _world.spawn_caravan(
		PackedVector3Array([Vector3.ZERO, Vector3(60.0, 0.0, 0.0)]), 1, 0, 1)
	if cart == null:
		fail("повозку для замера скорости создать не удалось")
		return
	cart.horses = 1
	var one: float = cart.speed_now()
	cart.horses = CARAVAN.HORSES_MAX
	var six: float = cart.speed_now()
	cart.horses = 0
	var none: float = cart.speed_now()

	check(six > one, "шестёрка быстрее одиночки", "%.1f против %.1f" % [six, one])
	check(six < one * float(CARAVAN.HORSES_MAX),
		"но не вшестеро — иначе обоз не догнать",
		"%.1f против %.1f при линейном росте" % [six, one * CARAVAN.HORSES_MAX])
	check(is_zero_approx(none), "без лошадей обоз не едет вовсе", "скорость 0")
	cart.queue_free()
	await get_tree().physics_frame


## Обоз встаёт, когда рядом враг.
##
## Без этого его нельзя догнать в принципе: он быстрее пешего. Пять минут варки
## и три набега эльфов в зону злодея кончались ничем именно поэтому.
func _test_halts_when_chased(me: Node3D) -> void:
	var away := Vector3(120.0, 0.0, 120.0)
	var cart: Node3D = _world.spawn_caravan(
		PackedVector3Array([away, away + Vector3(200.0, 0.0, 0.0)]),
		1, _enemy_of(int(me.faction)), 2)
	await get_tree().physics_frame
	if cart == null:
		fail("повозку для проверки погони создать не удалось")
		return

	me.teleport.rpc(away + Vector3(200.0, 2.0, 0.0))
	await get_tree().create_timer(0.6).timeout
	check(not cart.halted, "пока враг далеко, обоз едет", "не стоит")

	me.teleport.rpc(cart.global_position + Vector3(6.0, 2.0, 0.0))
	await get_tree().create_timer(0.6).timeout
	check(cart.halted, "враг рядом — обоз встал", "стоит")
	cart.queue_free()
	await get_tree().physics_frame


## Первый способ: выбить лошадей. Дешевле, но груз остаётся в целой телеге.
func _test_harness_can_be_killed(me: Node3D) -> void:
	var spot: Vector3 = me.global_position + Vector3(0.0, 0.0, 30.0)
	var cart: Node3D = _world.spawn_caravan(
		PackedVector3Array([spot, spot + Vector3(80.0, 0.0, 0.0)]),
		1, _enemy_of(int(me.faction)), 4)
	await get_tree().physics_frame
	if cart == null:
		fail("повозку для проверки упряжки создать не удалось")
		return
	var health_before: float = cart.health
	cart.hurt_harness(CARAVAN.HORSE_HEALTH + 1.0, cart.global_position, Vector3.FORWARD)
	check(cart.horses < 4, "удар по упряжке убивает лошадь",
		"осталось %d из 4" % cart.horses)
	check(is_equal_approx(cart.health, health_before),
		"телега при этом цела — груз никуда не делся",
		"здоровье повозки прежнее")

	cart.hurt_harness(CARAVAN.HORSE_HEALTH * 5.0, cart.global_position, Vector3.FORWARD)
	check(cart.horses == 0 and cart.halted,
		"выбив всех, обоз останавливают насовсем", "лошадей 0, стоит")
	cart.queue_free()
	await get_tree().physics_frame


## Второй способ: увести живыми. Единственный, после которого лошади кому-то
## достаются.
func _test_capture_gives_live_horses(me: Node3D) -> void:
	var spot: Vector3 = me.global_position + Vector3(0.0, 0.0, 40.0)
	var cart: Node3D = _world.spawn_caravan(
		PackedVector3Array([spot, spot + Vector3(80.0, 0.0, 0.0)]),
		1, _enemy_of(int(me.faction)), 3)
	await get_tree().physics_frame
	if cart == null:
		fail("повозку для проверки захвата создать не удалось")
		return

	check(cart.capture_horses() == 0,
		"у едущего обоза лошадей не выпрягают", "на ходу нельзя")

	me.teleport.rpc(cart.global_position + Vector3(3.0, 2.0, 0.0))
	await get_tree().create_timer(0.8).timeout
	check(cart.halted, "подошли — обоз встал", "стоит")
	check(me.caravan_to_rob() == cart, "стоящий чужой обоз виден как добыча",
		"нашёлся")

	var before: int = get_tree().get_nodes_in_group("horse").size()
	me.request_rob_caravan()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after: int = get_tree().get_nodes_in_group("horse").size()
	check(after > before, "уведённые лошади встают живыми телами",
		"в мире было %d, стало %d" % [before, after])
	check(cart.horses == 0, "у обоза их больше нет", "упряжка пуста")
	if is_instance_valid(cart):
		cart.queue_free()
	await get_tree().physics_frame


## Свободную лошадь можно оседлать, и верхом быстрее.
func _test_riding(me: Node3D) -> void:
	# Убираем лошадей, уведённых прошлой проверкой. Иначе «рядом» оказывается
	# одна из них, а не та, что мы поставили, и сравнение по тождеству падает —
	# при том что садиться герой садится верно. Первая версия падала именно так.
	for old in get_tree().get_nodes_in_group("horse"):
		if is_instance_valid(old):
			old.queue_free()
	await get_tree().physics_frame

	var horse: Node = _world.spawn_horse(me.global_position + Vector3(2.0, 0.0, 0.0))
	await get_tree().physics_frame
	if horse == null:
		fail("лошадь для проверки седла создать не удалось")
		return

	check(me.horse_nearby() == horse, "свободная лошадь рядом видна", "нашлась")
	check(is_equal_approx(me.mount_speed_scale(), 1.0),
		"пешком скорость обычная", "множитель 1.0")

	me.request_mount()
	await get_tree().physics_frame
	check(me.riding() == horse, "сели верхом", "едем")
	check(me.mount_speed_scale() > 1.0, "верхом быстрее",
		"множитель %.2f" % me.mount_speed_scale())
	check(not horse.can_mount(), "занятую лошадь второй раз не оседлать",
		"под седлом")

	me.request_mount()
	await get_tree().physics_frame
	check(me.riding() == null, "тем же нажатием спешились", "пешком")
	check(horse.can_mount(), "лошадь снова свободна", "можно садиться")
	if is_instance_valid(horse):
		horse.queue_free()
	await get_tree().physics_frame


func _enemy_of(faction: int) -> int:
	for other in FACTIONS.COUNT:
		if other != faction:
			return other
	return 0
