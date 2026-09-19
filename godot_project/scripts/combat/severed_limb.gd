extends RigidBody3D
##
## Оторванная конечность: падает, лежит и её МОЖНО ПОДОБРАТЬ. Рейтинг 21+,
## расчленение показываем без смягчения (GDD, разделы 3-4).
##
## ЧЕМ ЭТО БЫЛО РАНЬШЕ И ПОЧЕМУ ИЗМЕНИЛОСЬ. Кусок был локальным визуалом:
## каждый пир создавал его себе сам, со своим случайным разлётом, и по сети не
## ходило ничего. Выглядело это правильно ровно до тех пор, пока на него не
## надо было наступить: у хоста рука лежала в одном месте, у клиента — в
## другом, и подбирать было нечего. Трофеи при этом начислялись сами, в момент
## отрыва, — рубить и собирать было одним действием.
##
## Теперь кусок рождается через общий `MultiplayerSpawner`, как груз каравана:
## одна нода на всех, хост решает, кто её забрал, и он же её убирает.
##
## ПОЧЕМУ ПАДЕНИЕ ВСЁ РАВНО СЧИТАЕТ КАЖДЫЙ САМ. Разлёт не реплицируется
## покадрово, и это не экономия: толчок приходит В ДАННЫХ СПАВНА, стартовая
## поза тоже, сталкивается кусок только со статичным миром (маска 1). Одинаковый
## вход плюс одинаковая физика дают одинаковое место падения без единого
## лишнего пакета. Появится взаимодействие с подвижными телами — это перестанет
## быть правдой, и тогда позицию придётся синхронизировать.
##

const RIG := preload("res://scripts/combat/rig.gd")

## На каком расстоянии подбирается. То же число, что у груза: подбор один и
## тот же, и разные радиусы у двух предметов на земле игрок читал бы как баг.
const PICKUP_RANGE := 3.5
## Сколько лежит, прежде чем исчезнуть. Дольше, чем держался локальный визуал:
## теперь это не декорация, а добыча, и за ней надо успеть дойти.
const LIFETIME := 240.0

## Какая это конечность (`body.gd::Limb`) и какой трофей даёт.
@export var limb: int = 0
@export var trophy: int = 0

var _place := Transform3D()
var _scale := Vector3.ONE
var _impulse := Vector3.ZERO
var _spin := Vector3.ZERO
var _taken := false


func setup(data: Dictionary) -> void:
	limb = int(data["limb"])
	trophy = int(data["trophy"])
	_place = Transform3D(Basis(), Vector3(data["point"]))
	_scale = Vector3.ONE * float(data.get("model_scale", 1.0))
	_impulse = Vector3(data["impulse"])
	_spin = Vector3(data["spin"])


func _ready() -> void:
	add_to_group("loot")
	transform = _place
	collision_layer = 0
	collision_mask = 1          # только статичный мир, живых не толкаем

	var mesh: Mesh = RIG.limb_mesh(limb)
	if mesh != null:
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.scale = _scale
		add_child(view)

		var box: AABB = mesh.get_aabb()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size * _scale
		shape.shape = box_shape
		shape.position = box.get_center() * _scale
		add_child(shape)

	# Толчок пришёл в данных спавна — одинаковый у всех, поэтому и упадёт
	# кусок у всех в одно место.
	linear_velocity = _impulse
	angular_velocity = _spin

	# Убирает ХОЗЯИН: у спавнера одна нода на всех, и снос её на клиенте
	# оставил бы у хоста предмет, которого клиент уже не видит.
	if Net.hosting():
		get_tree().create_timer(LIFETIME).timeout.connect(func() -> void:
			if is_instance_valid(self):
				queue_free()
		)


## Подобрать. Зовёт ТОЛЬКО хост, из `player.request_collect_loot`.
##
## Возвращает 0, если брать нечего или далеко, — подбор ищет ближайшее по
## группе «loot» и по ненулевому ответу понимает, что нашёл.
func collect(player: Node3D) -> int:
	if _taken or not Net.hosting() or player == null:
		return 0
	if global_position.distance_to(player.global_position) > PICKUP_RANGE:
		return 0
	if not player.has_method("note_trophy"):
		return 0
	player.note_trophy(trophy)
	_taken = true
	print("[трофей] игрок %d подобрал %s" % [int(player.peer_id), name_of(limb)])
	queue_free()
	return 1


## Как называется то, что лежит. Нужно подсказке в HUD.
static func name_of(which: int) -> String:
	match which:
		0: return "левая рука"
		1: return "правая рука"
		2: return "левая нога"
		_: return "правая нога"


func summary() -> String:
	return name_of(limb)
