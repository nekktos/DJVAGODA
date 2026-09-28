extends "res://tools/test_base.gd"
##
## Раскладка и меню клавиш (решение автора от 28.09.2026: «меню настройки, чтоб
## каждый мог под себя назначить клавиши»).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --keystest
##
## ГЛАВНОЕ — ЧТО ПЕРЕНАЗНАЧЕНИЕ МЕНЯЕТ ИГРУ, а не только надпись. Меню, которое
## красиво показывает новую клавишу, а игра по-прежнему слушает старую, хуже
## отсутствия меню. Поэтому клавиши здесь НАЖИМАЮТСЯ — событием ввода, тем же
## путём, каким их нажимает человек, — и смотрится, что сделала игра.
##
## Раскладку пишем в свой файл: живой игрок на той же машине не должен
## обнаружить, что проверка переставила ему прыжок.
##

const KEYMAP := preload("res://scripts/ui/keymap.gd")
const RES := preload("res://scripts/economy/resources.gd")

const TEST_PATH := "user://keys_autotest.cfg"

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "клавиши"
	expected_host = 10
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	KEYMAP.config_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	KEYMAP.reset_all()
	await get_tree().create_timer(1.0).timeout

	_test_all_actions_bound()
	_test_defaults_do_not_clash()
	await _test_rebind_changes_the_game()
	_test_swap_on_conflict()
	_test_survives_restart()
	_test_reset()
	await _test_escape_opens_pause()

	KEYMAP.reset_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	KEYMAP.config_path = KEYMAP.DEFAULT_PATH
	finish()


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	return event


## Нажать и отпустить клавишу тем же путём, каким её жмёт человек.
func _press(code: int) -> void:
	var down := _key(code)
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := _key(code)
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _test_all_actions_bound() -> void:
	var missing := PackedStringArray()
	for entry in KEYMAP.ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			missing.append(String(action))
	check(missing.is_empty(), "у каждого действия раскладки есть клавиша",
		"без клавиши: %s" % ", ".join(missing))


## Умолчания сами с собой не спорят: одна клавиша — одно действие в режиме.
func _test_defaults_do_not_clash() -> void:
	var clashes := PackedStringArray()
	for entry in KEYMAP.ACTIONS:
		var action: StringName = entry[0]
		for event in InputMap.action_get_events(action):
			var other: StringName = KEYMAP.conflict(action, event)
			if other != &"":
				clashes.append("%s и %s: %s" % [action, other, KEYMAP.event_text(event)])
	check(clashes.is_empty(), "клавиши по умолчанию не пересекаются внутри режима",
		"; ".join(clashes))


## Переназначили «строить склад» — и склад строится НОВОЙ клавишей, а старая
## больше не строит.
func _test_rebind_changes_the_game() -> void:
	_world.set_strategy_mode(true)
	await get_tree().process_frame
	await _press(KEY_1)
	var old_works: bool = _world.build_controller.active and \
		int(_world.build_controller.kind) == RES.Building.STORAGE
	_world.set_build_mode(false, 0)
	await get_tree().process_frame
	check(old_works, "по умолчанию склад ставится своей клавишей",
		"режим стройки %s" % _world.build_controller.active)

	KEYMAP.rebind(&"build_storage", _key(KEY_J))
	await _press(KEY_1)
	var old_dead: bool = not _world.build_controller.active
	_world.set_build_mode(false, 0)
	await get_tree().process_frame
	await _press(KEY_J)
	var new_works: bool = _world.build_controller.active and \
		int(_world.build_controller.kind) == RES.Building.STORAGE
	_world.set_build_mode(false, 0)
	await get_tree().process_frame
	check(new_works and old_dead, "переназначенная клавиша работает в игре, старая — нет",
		"новая %s, старая молчит %s" % [new_works, old_dead])
	var help: String = _world.get_parent()._help_text()
	check(help.contains("J склад"), "справка показывает новую клавишу",
		"в справке нет «J склад»")
	_world.set_strategy_mode(false)
	await get_tree().process_frame


## Занятую клавишу не отнимают молча: действия меняются клавишами.
func _test_swap_on_conflict() -> void:
	KEYMAP.reset_all()
	var swapped: StringName = KEYMAP.rebind(&"jump", _key(KEY_W))
	var jump_w: bool = KEYMAP.same_input(KEYMAP.primary(&"jump"), _key(KEY_W))
	var forward_space: bool = KEYMAP.same_input(KEYMAP.primary(&"move_forward"), _key(KEY_SPACE))
	check(swapped == &"move_forward" and jump_w and forward_space,
		"занятая клавиша меняется местами, а не отнимается",
		"обмен с %s, прыжок %s, вперёд %s" % [swapped, KEYMAP.key_text(&"jump"),
			KEYMAP.key_text(&"move_forward")])


## Переназначенное переживает перезапуск: `install` читает файл заново.
func _test_survives_restart() -> void:
	KEYMAP.reset_all()
	KEYMAP.rebind(&"dash", _key(KEY_K))
	KEYMAP.install()
	check(KEYMAP.same_input(KEYMAP.primary(&"dash"), _key(KEY_K)),
		"переназначение сохраняется между запусками",
		"рывок после перезапуска: %s" % KEYMAP.key_text(&"dash"))


func _test_reset() -> void:
	KEYMAP.reset_all()
	KEYMAP.install()
	check(KEYMAP.same_input(KEYMAP.primary(&"dash"), _key(KEY_R))
			and KEYMAP.same_input(KEYMAP.primary(&"jump"), _key(KEY_SPACE)),
		"«сбросить всё» возвращает умолчания",
		"рывок %s, прыжок %s" % [KEYMAP.key_text(&"dash"), KEYMAP.key_text(&"jump")])


## Esc открывает паузу, второй Esc закрывает. Раньше Esc только отпускал мышь,
## и до настроек нельзя было добраться никак.
func _test_escape_opens_pause() -> void:
	var main: Node = _world.get_parent()
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	var opened: bool = main._settings.visible
	Input.parse_input_event(esc)
	await get_tree().process_frame
	var closed: bool = not main._settings.visible
	check(opened and closed, "Esc открывает паузу, второй Esc закрывает",
		"открылась %s, закрылась %s" % [opened, closed])
	main._settings.show_keys(false)
	var rows := 0
	for entry in KEYMAP.ACTIONS:
		if main._settings.find_child(String(entry[0]), true, false) != null:
			rows += 1
	main._settings.close()
	check(rows == KEYMAP.ACTIONS.size(), "в меню клавиш строка на каждое действие",
		"%d строк из %d" % [rows, KEYMAP.ACTIONS.size()])
