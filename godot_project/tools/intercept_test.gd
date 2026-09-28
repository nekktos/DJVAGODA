extends "res://tools/test_base.gd"
##
## Обозы обеих сторон, перехват и разграбление (GDD 9a, доработка концепции от
## 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --intercepttest
##
## Решение автора: «Караваны есть и у людей, и у злодея, их могут грабить эльфы
## (убив/отпустив лошадей и разграбив повозку); если караван перехватывает
## противостоящая сторона (злодей/люди), то его можно перенаправить на свой
## склад и по сути украсть ресурсы конкурента».
##
## Набор идёт ЗА ЗЛОДЕЯ: перехват проверяется его руками, по обозу стражи.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const CARAVAN := preload("res://scripts/economy/caravan.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "перехват"
	expected_host = 8
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(1.0).timeout
	var me: Node3D = _world.local_player()
	if me == null or int(me.faction) != FACTIONS.Kind.VILLAIN:
		fail("набор должен идти за злодея")
		finish()
		return

	_test_rules()
	_test_replicated()
	await _test_guard_sends_caravans()
	await _test_intercept(me)
	await _test_plunder(me)
	finish()


## Правило одно на всех: кто что может сделать со стоящим обозом.
func _test_rules() -> void:
	var V := FACTIONS.Kind.VILLAIN
	var E := FACTIONS.Kind.ELVES
	var G := FACTIONS.Kind.GUARD
	var wrong := PackedStringArray()
	var cases := [
		# кто, чей обоз, лошадей, стоит, груза, свой склад -> что
		[V, G, 2, true, 50, true, "intercept"],
		[G, V, 2, true, 50, true, "intercept"],
		[V, G, 2, true, 50, false, "rob"],
		[E, V, 2, true, 50, false, "rob"],
		[E, G, 2, true, 50, true, "rob"],
		[E, V, 0, true, 50, false, "plunder"],
		[V, G, 0, true, 50, true, "plunder"],
		[V, G, 2, false, 50, true, ""],
		[V, V, 2, true, 50, true, ""],
		[E, V, 0, true, 0, false, ""],
	]
	for case in cases:
		var got: String = CARAVAN.action_for(case[0], case[1], case[2], case[3], case[4], case[5])
		if got != case[6]:
			wrong.append("%s у обоза %s (лошадей %d, стоит %s, груз %d, склад %s): «%s», ждали «%s»" % [
				FACTIONS.name_of(case[0]), FACTIONS.name_of(case[1]), case[2], case[3],
				case[4], case[5], got, case[6]])
	check(wrong.is_empty(),
		"перехватывают соперники со складом, эльфы уводят лошадей, пустую упряжку грабят",
		"; ".join(wrong))


## Клиенту приходят лошади, «стоит», сторона и хозяин обоза. Без первых двух у
## игрока-клиента не бывало подсказки «выпрячь лошадей» вовсе.
func _test_replicated() -> void:
	var scene: PackedScene = load("res://scenes/Caravan.tscn")
	var node := scene.instantiate()
	var config: SceneReplicationConfig = node.get_node("Sync").replication_config
	var synced := []
	for path in config.get_properties():
		synced.append(String(path).get_slice(":", 1))
	node.free()
	var missing := PackedStringArray()
	for name in ["horses", "halted", "faction", "owner_id"]:
		if not synced.has(name):
			missing.append(name)
	check(missing.is_empty(), "по сети идут лошади, «стоит», сторона и хозяин обоза",
		"не синхронизируются: %s" % ", ".join(missing))


## Стража без командира возит обозы сама: распорядитель покупает лошадей и
## шлёт повозку. Её конюшня и склад стоят с начала партии.
func _test_guard_sends_caravans() -> void:
	var side := FACTIONS.Kind.GUARD
	var sent: Node3D = null
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		for cart in _world.caravans_of(0):
			if int(cart.faction) == side:
				sent = cart
		if sent != null:
			break
	var wallet: Node = _world.treasury.of(side)
	check(sent != null, "у стражи без командира обозы ходят сами",
		"обозов стражи нет; лошадей у неё %d" % int(wallet.horses))
	if sent != null:
		sent.queue_free()
		_world._on_caravan_home(int(sent.horses), side)
		await get_tree().physics_frame


## Злодей перехватывает стоящий обоз стражи: тот едет на склад злодея с грузом
## и лошадьми.
func _test_intercept(me: Node3D) -> void:
	var villain := FACTIONS.Kind.VILLAIN
	var guard := FACTIONS.Kind.GUARD
	var home: Vector3 = me.global_position + Vector3(30.0, 0.0, 0.0)
	_world.spawn_building(RES.Building.STORAGE, home, 0, villain, true)
	var guard_wallet: Node = _world.treasury.of(guard)
	var villain_wallet: Node = _world.treasury.of(villain)
	# Склад «уже стоявший» потолка не поднимает (это достройка, а он не
	# достраивался) — поднимаем сами, как подняла бы достройка. Без этого груз
	# ложился в склад с потолком ноль и пропадал.
	villain_wallet.raise_capacity(RES.STORAGE_BONUS)
	guard_wallet.horses += 2
	guard_wallet.horses_out += 2
	var villain_horses: int = int(villain_wallet.horses)
	var guard_horses: int = int(guard_wallet.horses)
	var spot: Vector3 = me.global_position + Vector3(0.0, 0.0, 12.0)
	var cart: Node3D = _world.spawn_caravan(
		PackedVector3Array([spot, spot + Vector3(0.0, 0.0, 200.0)]), 0, guard, 2)
	await get_tree().physics_frame
	cart.cargo = RES.fit([0, 0, 0, 60])
	cart.state = cart.State.TO_HOME
	me.teleport.rpc(cart.global_position + Vector3(2.5, 1.0, 0.0))
	await get_tree().create_timer(0.8).timeout
	check(me.caravan_action(cart) == "intercept", "злодей у стоящего обоза стражи может его перехватить",
		"действие «%s», стоит %s" % [me.caravan_action(cart), cart.halted])

	me.request_rob_caravan()
	await get_tree().physics_frame
	var end: Vector3 = cart.route[0]
	check(int(cart.faction) == villain and _flat(end).distance_to(_flat(home)) < 12.0,
		"перехваченный обоз меняет сторону и едет на склад злодея",
		"сторона %s, конец пути в %.0f м от склада" % [
			FACTIONS.name_of(int(cart.faction)), _flat(end).distance_to(_flat(home))])
	check(int(villain_wallet.horses) == villain_horses + 2 and int(guard_wallet.horses) == guard_horses - 2,
		"лошади упряжки переходят к перехватчику",
		"у злодея %d -> %d, у стражи %d -> %d" % [villain_horses, int(villain_wallet.horses),
			guard_horses, int(guard_wallet.horses)])

	# Везём до склада: уводим героя, чтобы обоз не стоял из-за «врага рядом»
	# (он теперь свой, но проверяем честно — ждём, пока доедет сам).
	me.teleport.rpc(home + Vector3(-40.0, 1.0, 0.0))
	var iron_before: int = int(villain_wallet.get_amount(RES.Kind.IRON))
	for i in 120:
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(cart) or int(villain_wallet.get_amount(RES.Kind.IRON)) > iron_before:
			break
	check(int(villain_wallet.get_amount(RES.Kind.IRON)) >= iron_before + 60,
		"груз перехваченного обоза ложится на склад злодея",
		"железа у злодея %d -> %d" % [iron_before, int(villain_wallet.get_amount(RES.Kind.IRON))])
	if is_instance_valid(cart):
		cart.queue_free()
	await get_tree().physics_frame


## Повозку без лошадей грабят: груз ложится на землю кучей, повозки больше нет.
func _test_plunder(me: Node3D) -> void:
	var spot: Vector3 = me.global_position + Vector3(0.0, 0.0, 15.0)
	var cart: Node3D = _world.spawn_caravan(
		PackedVector3Array([spot, spot + Vector3(0.0, 0.0, 200.0)]), 0, FACTIONS.Kind.GUARD, 1)
	await get_tree().physics_frame
	cart.cargo = RES.fit([0, 40, 0, 0])
	cart.hurt_harness(1000.0, cart.global_position, Vector3.FORWARD)
	me.teleport.rpc(cart.global_position + Vector3(2.5, 1.0, 0.0))
	await get_tree().create_timer(0.8).timeout
	var piles_before: int = get_tree().get_nodes_in_group("loot").size()
	var can: String = me.caravan_action(cart)
	me.request_rob_caravan()
	await get_tree().create_timer(0.4).timeout
	var piles_after: int = get_tree().get_nodes_in_group("loot").size()
	check(can == "plunder" and not is_instance_valid(cart) and piles_after > piles_before,
		"повозку без лошадей разграбляют: груз на землю, повозки нет",
		"действие «%s», повозка %s, куч %d -> %d" % [can,
			"есть" if is_instance_valid(cart) else "нет", piles_before, piles_after])


func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)
