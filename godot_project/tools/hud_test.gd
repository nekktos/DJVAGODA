extends "res://tools/test_base.gd"
##
## Интерфейс картинками: полоса запасов и панель команд вида сверху (решение
## автора от 28.09.2026: «чтоб всё было не текстом, а интерактивными
## менюшками с картинками»).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --hudtest
##
## ЧТО ПРОВЕРЯЕМ. Что меню ДЕЛАЕТ, а не что оно есть: щелчок по карточке
## склада включает стройку склада, по роли — переводит батрака, по найму —
## нанимает. И что оно ПОКАЗЫВАЕТ правду: числа запасов совпадают с казной,
## нехватка краснеет, клавиша на карточке — та, что стоит в раскладке.
##
## КАК ЛЕЖИТ на экране — проверками не увидеть: для этого снимки
## (`tools/hud_shot.gd`). Без экрана снимков иконок нет, есть плашки, и
## проверки это учитывают — они не смотрят в пиксели.
##

const RES := preload("res://scripts/economy/resources.gd")
const KEYMAP := preload("res://scripts/ui/keymap.gd")
const ICONS := preload("res://scripts/ui/icons.gd")
const STYLE := preload("res://scripts/ui/style.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")

const TEST_PATH := "user://keys_hudtest.cfg"

var _world: Node3D
var _main: Node


func start(world: Node3D) -> void:
	tag = "интерфейс"
	expected_host = 12
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	KEYMAP.config_path = TEST_PATH
	KEYMAP.reset_all()
	await get_tree().create_timer(1.0).timeout
	_main = _world.get_parent()
	var me: Node3D = _world.local_player()

	_test_icons()
	_test_cart_texture()
	await _test_resource_numbers(me)
	await _test_bar_only_from_above()
	await _test_build_card(me)
	await _test_keycap_follows_keymap()
	await _test_hire_and_role(me)
	await _test_route_card()
	await _test_prompt_above_bar()

	_world.set_strategy_mode(false)
	KEYMAP.reset_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	KEYMAP.config_path = KEYMAP.DEFAULT_PATH
	finish()


func _bar() -> Control:
	return _main._command_bar


## На каждый ключ — картинка, а не пустота: снимок или плашка.
func _test_icons() -> void:
	var empty := PackedStringArray()
	for key in ICONS.keys():
		var texture: Texture2D = _main._icons.icon(key)
		if texture == null or texture.get_width() <= 0:
			empty.append(key)
	check(empty.is_empty() and ICONS.keys().size() >= 25,
		"у каждой иконки есть картинка", "пусто: %s, всего ключей %d" % [
			", ".join(empty), ICONS.keys().size()])


## Телега была БЕЛОЙ: модель ссылается на Textures/colormap.png рядом с собой,
## а папки там не было. Нашлось на снимке иконки «обоз».
func _test_cart_texture() -> void:
	var cart: Node3D = (load("res://assets/props/cart.glb") as PackedScene).instantiate()
	var textured := false
	for node in cart.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface) as BaseMaterial3D
			if mat != null and mat.albedo_texture != null:
				textured = true
	cart.free()
	check(textured, "у модели телеги есть текстура", "материал без картинки — телега белая")


## Числа в полосе — те, что в казне; нехватка на цену — красным.
func _test_resource_numbers(me: Node3D) -> void:
	var wallet: Node = _world.treasury.of(int(me.faction))
	wallet.grant(RES.fit([77, 33, 21, 4, 9, 2]))
	await get_tree().process_frame
	await get_tree().process_frame
	var wrong := PackedStringArray()
	for kind in RES.COUNT:
		var slot: Node = _main._res_bar.find_child("Res%d" % kind, true, false)
		var shown: String = (slot.get_child(1) as Label).text
		if shown != str(int(wallet.get_amount(kind))):
			wrong.append("%s: показано %s, в казне %d" % [RES.NAMES[kind], shown, int(wallet.get_amount(kind))])
	check(wrong.is_empty(), "полоса запасов показывает казну стороны", "; ".join(wrong))

	# Казарма мечников хочет десять железа, а есть четыре: железо краснеет,
	# дерево (77 при цене 60) — нет.
	_main._res_bar.highlight_shortfall(RES.BUILDING_COST[RES.Building.SWORD_BARRACKS])
	_main._res_bar.refresh()
	var iron: Label = _main._res_bar.find_child("Res%d" % RES.Kind.IRON, true, false).get_child(1)
	var wood: Label = _main._res_bar.find_child("Res%d" % RES.Kind.WOOD, true, false).get_child(1)
	check(iron.get_theme_color("font_color") == STYLE.DANGER
			and wood.get_theme_color("font_color") != STYLE.DANGER,
		"нехватка на цену подсвечена красным, остальное — нет",
		"железо %s, дерево %s" % [iron.get_theme_color("font_color"), wood.get_theme_color("font_color")])
	_main._res_bar.highlight_shortfall([])


func _test_bar_only_from_above() -> void:
	_world.set_strategy_mode(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var hidden_in_fight: bool = not _bar().visible
	_world.set_strategy_mode(true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(hidden_in_fight and _bar().visible, "панель команд — только в виде сверху",
		"в бою видна %s, сверху видна %s" % [not hidden_in_fight, _bar().visible])


## Щелчок по карточке — это стройка, второй щелчок — отмена. И карточка, на
## которую не хватает, неактивна.
func _test_build_card(me: Node3D) -> void:
	var wallet: Node = _world.treasury.of(int(me.faction))
	wallet.grant(RES.fit([0, 0, 0, 0, 0, 0]))
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Button = _bar().find_child("Build%d" % RES.Building.STORAGE, true, false)
	var off_when_poor: bool = card.disabled
	wallet.grant(RES.fit([500, 500, 500, 500, 0, 0]))
	await get_tree().process_frame
	await get_tree().process_frame
	var on_when_rich: bool = not card.disabled
	check(off_when_poor and on_when_rich, "карточка тускнеет, когда не хватает, и оживает, когда хватает",
		"без денег неактивна %s, с деньгами активна %s" % [off_when_poor, on_when_rich])

	card.pressed.emit()
	await get_tree().process_frame
	var picked: bool = _world.build_controller.active \
		and int(_world.build_controller.kind) == RES.Building.STORAGE
	card.pressed.emit()
	await get_tree().process_frame
	var dropped: bool = not _world.build_controller.active
	check(picked and dropped, "щелчок по карточке включает стройку, второй — отменяет",
		"включилась %s, отменилась %s" % [picked, dropped])


## Клавиша на карточке — из раскладки и меняется вслед за ней.
func _test_keycap_follows_keymap() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_J
	KEYMAP.rebind(&"build_farm", event)
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Button = _bar().find_child("Build%d" % RES.Building.FARM, true, false)
	var cap: String = (card.find_child("Key", true, false).get_child(0) as Label).text
	check(cap == "J", "клавиша на карточке — из раскладки и следует за ней",
		"на карточке «%s», в раскладке J" % cap)
	KEYMAP.reset_all()


func _test_hire_and_role(me: Node3D) -> void:
	var before: int = _world.labourers_of(int(me.faction)).size()
	var hire: Button = _bar().find_child("Hire", true, false)
	hire.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	var after: int = _world.labourers_of(int(me.faction)).size()
	check(after == before + 1, "щелчок «нанять» нанимает батрака", "%d -> %d" % [before, after])

	var role := LABOURER.Role.FARMER
	var farmers_before := _count_role(me, role)
	var card: Button = _bar().find_child("Role%d" % role, true, false)
	card.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	await get_tree().process_frame
	var farmers_after := _count_role(me, role)
	var shown: String = (card.find_child("Count", true, false) as Label).text
	check(farmers_after == farmers_before + 1 and shown == str(farmers_after),
		"щелчок по роли переводит батрака, и карточка считает его",
		"фермеров %d -> %d, на карточке %s" % [farmers_before, farmers_after, shown])


func _count_role(me: Node3D, role: int) -> int:
	var count := 0
	for worker in _world.labourers_of(int(me.faction)):
		if int(worker.sync_role) == role:
			count += 1
	return count


## Карточка обоза включает прокладку маршрута. Склад нужен: без него карточка
## неактивна — каравану некуда вернуться.
func _test_route_card() -> void:
	var me: Node3D = _world.local_player()
	_world.spawn_building(RES.Building.STORAGE, me.global_position + Vector3(20.0, 0.0, 0.0),
		0, int(me.faction), true)
	await get_tree().process_frame
	await get_tree().process_frame
	var card: Button = _bar().find_child("Route", true, false)
	var usable: bool = not card.disabled
	card.pressed.emit()
	await get_tree().process_frame
	var on: bool = _world.route_controller.active
	_world.set_route_mode(false)
	check(usable and on, "карточка обоза включает прокладку маршрута",
		"активна %s, маршрут %s" % [usable, on])


## Строка действия поднимается над панелью: иначе «СТРОЙКА: ЛКМ поставить»
## пряталась бы за карточками.
func _test_prompt_above_bar() -> void:
	await get_tree().process_frame
	var prompt: Label = _main._hud.prompt
	var bar_top: float = _bar().get_global_rect().position.y
	var prompt_bottom: float = prompt.get_global_rect().end.y
	check(prompt_bottom <= bar_top, "строка действия стоит над панелью команд",
		"низ строки %.0f, верх панели %.0f" % [prompt_bottom, bar_top])
