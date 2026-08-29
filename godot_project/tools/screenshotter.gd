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
			"name": "03b_лес_с_земли",
			"pos": Vector3(-300, 3, -120),
			"look": Vector3(-300, 14, -300),
		},
		{
			"name": "03c_лес_стык_3D_и_билбордов",
			"pos": Vector3(-300, 26, -140),
			"look": Vector3(-300, 6, -300),
		},
		{
			"name": "03d_призванный_волк",
			"pos": Vector3(-292, 3.4, -286),
			"look": Vector3(-300, 1.4, -294),
			"summon": true,
		},
		{
			"name": "03e_лавка_эльфов",
			"pos": Vector3(-292, 5.0, -262),
			"look": Vector3(-300, 2.0, -272),
		},
		{
			"name": "04c_уровни_снаряжения",
			"pos": Vector3(-21.5, 3.2, 36.0),
			"look": Vector3(-21.5, 1.4, 26.0),
			"gear_row": true,
		},
		{
			"name": "04b_командир_стражи",
			"pos": Vector3(276, 8.5, -226),
			"look": Vector3(270, 7.0, -235),
			"orders": true,
		},
		{
			"name": "04d_гарнизон_свободной_стороны",
			"pos": Vector3(-300.0, 6.0, -282.0),
			"look": Vector3(-300.0, 2.0, -300.0),
			"garrison": true,
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
			"name": "14_форт_стройка",
			"pos": Vector3(96.0, 34.0, 96.0),
			"look": Vector3(56.0, 2.0, 56.0),
			"buildings": true,
		},
		{
			"name": "15_караван_в_пути",
			"pos": Vector3(30.0, 6.0, 63.0),
			"look": Vector3(36.0, 1.6, 45.0),
			"caravan": true,
		},
		{
			"name": "18_дворец_точка_захвата",
			"pos": Vector3(300.0, 62.0, -200.0),
			"look": Vector3(300.0, 20.0, -300.0),
			"capture": true,
		},
		{
			"name": "16_отряд_шеренга",
			"pos": Vector3(-46.0, 14.0, 132.0),
			"look": Vector3(-60.0, 1.0, 108.0),
			"squad": 0,
		},
		{
			"name": "17_отряд_рассыпной_строй",
			"pos": Vector3(-46.0, 14.0, 132.0),
			"look": Vector3(-60.0, 1.0, 108.0),
			"squad": 3,
		},
		{
			"name": "19_роли_батраков",
			"pos": Vector3(-14.0, 3.0, 34.0),
			"look": Vector3(-14.0, 1.4, 26.0),
			"roles": true,
		},
		{
			"name": "20_кучи_ресурсов",
			"pos": Vector3(-34.0, 3.0, 38.0),
			"look": Vector3(-34.0, 0.7, 31.0),
			"loot": true,
		},
		{
			"name": "22_все_постройки",
			"pos": Vector3(-70.0, 26.0, 74.0),
			"look": Vector3(-70.0, 3.0, 40.0),
			"all_buildings": true,
		},
		{
			"name": "21_свободная_лошадь",
			"pos": Vector3(-44.0, 2.6, 38.0),
			"look": Vector3(-44.0, 1.2, 31.0),
			"horse": true,
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
		if shot.get("buildings", false):
			_stage_buildings()
			# Ждём дольше времени стройки, иначе в кадре будет котлован.
			await get_tree().create_timer(10.0).timeout
		if shot.get("caravan", false):
			_stage_caravan()
			await get_tree().create_timer(3.0).timeout
		if shot.get("capture", false):
			_stage_capture()
			await get_tree().create_timer(2.0).timeout
		if shot.get("garrison", false):
			# Гарнизон выставляется хостом сам, надо лишь дождаться его проверки
			# состава сторон.
			await get_tree().create_timer(5.0).timeout
		if shot.get("all_buildings", false):
			_stage_all_buildings()
			await get_tree().create_timer(1.0).timeout
		if shot.get("horse", false):
			_stage_horse()
			await get_tree().create_timer(1.0).timeout
		if shot.get("roles", false):
			await _stage_roles()
			await get_tree().create_timer(0.8).timeout
		if shot.get("loot", false):
			_stage_loot()
			await get_tree().create_timer(0.6).timeout
		if shot.get("gear_row", false):
			_stage_gear_row()
			await get_tree().create_timer(0.6).timeout
		if shot.get("orders", false):
			_stage_orders()
			await get_tree().create_timer(0.6).timeout
		if shot.get("summon", false):
			_stage_summon()
			await get_tree().create_timer(1.2).timeout
		if shot.has("squad"):
			await _stage_squad(int(shot["squad"]))
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
	# И явно ставим персонажа под камеру: со Этапа 7 стороны стартуют по своим
	# зонам, и полагаться на точку спавна больше нельзя.
	me.teleport.rpc(Vector3(-14.0, 2.0, 14.0))
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


## Поставить склад и казарму, чтобы на кадре была видна стройка, а не пустая
## поляна. Ресурсы выдаём напрямую: проверка оплаты — дело автотеста, а не кадра.
func _stage_buildings() -> void:
	const RES := preload("res://scripts/economy/resources.gd")
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.body.reset()
	me.health.revive()
	me.stock.grant([500, 500, 500, 500])
	_world.spawn_building(RES.Building.STORAGE, Vector3(52.0, 0.0, 44.0), me.peer_id)
	_world.spawn_building(RES.Building.SWORD_BARRACKS, Vector3(52.0, 0.0, 68.0), me.peer_id)
	me.global_position = Vector3(64.0, 2.0, 58.0)
	me.sync_position = me.global_position


## Отправить караван по маршруту у шахты, чтобы в кадре был он, а не пустая
## дорога. Склад тут не нужен: проверка «куда возвращаться» — дело автотеста.
func _stage_caravan() -> void:
	const RES := preload("res://scripts/economy/resources.gd")
	var me: Node3D = _world.local_player()
	if me == null:
		return
	_world.mine.stored = PackedInt32Array([0, 0, 200, 200])
	# Маршрут для кадра нарочно короткий и на открытом месте: у настоящей шахты
	# караван теряется среди 70-метровых скал и в кадр не читается.
	_world.spawn_caravan(PackedVector3Array([
		Vector3(10.0, 0.0, 45.0),
		Vector3(80.0, 0.0, 45.0),
	]), me.peer_id)


## Поставить отряд в заданное построение перед камерой. Казарму и бойцов
## выдаём напрямую: проверка оплаты и потолка — дело автотеста, а не кадра.
func _stage_squad(formation: int) -> void:
	const RES := preload("res://scripts/economy/resources.gd")
	var me: Node3D = _world.local_player()
	if me == null:
		return

	# Бойцов ставим прямо у камеры. Настоящий путь найма — казарма, ресурсы,
	# потолок отряда — проверяет автотест; тащить их сюда пешком через полкарты
	# от казармы из предыдущего кадра значит снимать марш, а не построение.
	if _world.units_of(me.peer_id).is_empty():
		for i in 10:
			var angle: float = float(i) * 0.9
			var radius: float = 3.0 + float(i) * 0.45
			_world.spawn_unit(me.peer_id, i, Vector3(
				-60.0 + cos(angle) * radius, 1.0, 100.0 + sin(angle) * radius
			))
		await get_tree().create_timer(0.5).timeout

	# Командир встаёт туда, где должен стоять строй: отряд равняется на него.
	me.global_position = Vector3(-60.0, 2.0, 108.0)
	me.sync_position = me.global_position
	me.rotation.y = 0.0
	me.request_squad_follow()
	me.request_formation(formation)
	# Даём построиться: бойцы идут к слотам своим ходом.
	await get_tree().create_timer(11.0).timeout
	var squad: Array = _world.units_of(me.peer_id)
	print("[shot] отряд: бойцов %d, казарма %s" % [
		squad.size(), "есть" if _world.barracks_of(int(me.faction)) != null else "НЕТ"
	])
	for unit in squad:
		if is_instance_valid(unit):
			print("[shot]   боец %s" % unit.global_position)


## Поставить злодея в точку захвата дворца, чтобы в кадре был виден захват,
## а не просто дворец.
func _stage_capture() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.body.reset()
	me.health.revive()
	me.teleport.rpc(_world.objective.PALACE + Vector3(0.0, 3.0, 0.0))


## Поставить эльфа на поляну и призвать волков. Способность идёт штатным путём
## через request_ability, чтобы в кадр попало ровно то, что увидит игрок.
func _stage_summon() -> void:
	const ABILITIES := preload("res://scripts/combat/abilities.gd")
	const FACTIONS := preload("res://scripts/factions.gd")
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.faction = FACTIONS.Kind.ELVES
	me.teleport.rpc(Vector3(-300.0, 2.0, -294.0))
	await get_tree().physics_frame
	for i in 2:
		me.sync_ability_cd[ABILITIES.Kind.SUMMON] = 0.0
		me.request_ability(ABILITIES.Kind.SUMMON)
		me.rotation.y += 0.8
		await get_tree().physics_frame


## Поставить игрока стражем у командира и взять приказ штатным путём.
## Предыдущий кадр (призыв волка) переводит персонажа в эльфы — возвращаем.
func _stage_orders() -> void:
	const FACTIONS := preload("res://scripts/factions.gd")
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.faction = FACTIONS.Kind.GUARD
	me.teleport.rpc(_world.commander.POSITION + Vector3(0.0, 2.0, 3.0))
	await get_tree().physics_frame
	me.request_report()
	await get_tree().physics_frame


## Три персонажа рядом с разными уровнями снаряжения: проверить, что купленный
## апгрейд действительно ВИДЕН, а не только записан в число.
##
## Ставим ботов вместо игроков: трёх живых для съёмки не собрать, а нужен именно
## ряд одинаковых фигур с разным оружием.
## Ряд из всех ролей разом: четыре батрака, мечник и лучник.
##
## Роли различаются моделью и инструментом в руке, и проверить это можно только
## глазами: headless-прогон скажет, что модель загрузилась, и ни слова о том,
## отличит ли их человек в толпе.
func _stage_roles() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.teleport.rpc(Vector3(-14.0, 2.0, 33.0))
	await get_tree().physics_frame
	var base := Vector3(-18.0, 2.0, 26.0)
	for role in 4:
		var worker: Node3D = _world.spawn_labourer(
			int(me.faction), base + Vector3(float(role) * 2.2, 0.0, 0.0), base, role
		)
		if worker != null:
			worker.leash = 0.0
	for i in 2:
		_world.spawn_unit(int(me.peer_id), i, base + Vector3(9.0 + float(i) * 2.2, 0.0, 0.0),
			false, i == 1)
	await get_tree().physics_frame


## Кучи всех четырёх сортов в ряд: дерево, камень, золото, железо.
## Все четыре вида построек в ряд: склад, две казармы и конюшня.
##
## Знамя на казарме и загон у конюшни ставились по тем же правилам, что и стены,
## но проверить их было негде: в кадре стройки конюшни нет вовсе. А ошибка в
## развороте модуля видна только глазами — headless-прогон о ней молчит.
func _stage_all_buildings() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.teleport.rpc(Vector3(-70.0, 2.0, 70.0))
	for kind in 4:
		_world.spawn_building(kind, Vector3(-100.0 + float(kind) * 22.0, 0.0, 40.0),
			int(me.peer_id), int(me.faction), true)


## Свободная лошадь рядом с игроком: проверяем модель, размер и разворот.
func _stage_horse() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.teleport.rpc(Vector3(-44.0, 2.0, 37.0))
	for i in 2:
		_world.spawn_horse(Vector3(-46.0 + float(i) * 4.0, 1.5, 31.0))


func _stage_loot() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.teleport.rpc(Vector3(-34.0, 2.0, 37.0))
	var piles := [
		PackedInt32Array([40, 0, 0, 0]),
		PackedInt32Array([0, 40, 0, 0]),
		PackedInt32Array([0, 0, 40, 0]),
		PackedInt32Array([0, 0, 0, 40]),
		PackedInt32Array([20, 20, 0, 0]),
	]
	for i in piles.size():
		_world.spawn_loot_pile(Vector3(-38.0 + float(i) * 2.2, 1.4, 31.0), piles[i])


func _stage_gear_row() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.teleport.rpc(Vector3(-24.0, 2.0, 26.0))
	me.gear_tier = 0
	await get_tree().physics_frame

	for tier in [1, 2]:
		var unit: Node3D = _world.spawn_unit(int(me.peer_id), tier, Vector3(
			-24.0 + tier * 2.5, 2.0, 26.0
		))
		if unit == null:
			continue
		# Боец носит меч того же вида, что и игрок: подменяем ему уровень
		# напрямую, чтобы в кадре оказался ряд из трёх разных клинков.
		var arm: MeshInstance3D = unit.get("_parts")["arm_r"] if unit.get("_parts") != null else null
		if arm != null:
			var WV := preload("res://scripts/combat/weapon_visual.gd")
			var W := preload("res://scripts/combat/weapons.gd")
			WV.attach(arm, W.Kind.SWORD, arm.get_node_or_null("Weapon"), tier)
	await get_tree().physics_frame
