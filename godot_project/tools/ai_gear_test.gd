extends "res://tools/test_base.gd"
##
## ИИ-вожак снаряжается, как игрок: закаляет оружие в кузне, покупает доспех.
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --aigeartest
##
## Набор идёт за эльфов: злодей — под ИИ. Кузню ставим сами, чтобы не ждать,
## пока распорядитель дойдёт до неё по очереди стройки; проверяется вожак.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")

const WAIT_SECONDS := 90.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "ИИ-снаряжение"
	expected_host = 3
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout
	var hero: Node3D = _world.ai_hero_of(FACTIONS.Kind.VILLAIN)
	if hero == null:
		fail("ИИ-вожака злодея нет")
		finish()
		return
	check(RES.Building.FORGE in _world.steward.BUILD_ORDER,
		"распорядитель злодея ставит кузню в очереди стройки", "")

	var wallet: Node = _world.treasury.of(FACTIONS.Kind.VILLAIN)
	wallet.grant(RES.fit([2000, 2000, 2000, 2000, 0, 500]))
	# Место — по тому же правилу стройки, что у распорядителя: поставленная
	# поверх его склада кузня загораживалась складом, и вожак упирался в стену.
	var spot := Vector3.INF
	var base: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]
	for radius in [30.0, 44.0, 58.0]:
		for i in 12:
			var angle := TAU * float(i) / 12.0
			var at := base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			if BUILD_CONTROLLER.is_spot_buildable(_world, at, RES.Building.FORGE):
				spot = at
				break
		if spot != Vector3.INF:
			break
	_world.spawn_building(RES.Building.FORGE, spot, 0, FACTIONS.Kind.VILLAIN, true)

	var waited := 0.0
	while waited < WAIT_SECONDS:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
		if int(hero.gear_tier) >= 1 and int(hero.armor_tier) >= 1:
			break
	note("прошло %d с" % int(waited))
	check(int(hero.gear_tier) >= 1, "ИИ-вожак сам закалил оружие в своей кузне",
		"оружие %d" % int(hero.gear_tier))
	check(int(hero.armor_tier) >= 1, "и купил доспех в своей лавке",
		"доспех %d" % int(hero.armor_tier))
	finish()
