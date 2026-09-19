extends CharacterBody3D
##
## Лошадь (решение по ходу Этапа 10).
##
## ЗАЧЕМ. Караван ездил сам по себе — коробка, которая катится по земле без
## всякой причины. Теперь его тянет пара лошадей, и это не украшение: если обоз
## разграбили, а лошади уцелели, их можно увести и ездить на них самому. Груз
## пропал, но добыча осталась — и это ровно тот размен, ради которого на караван
## и нападают.
##
## ЧТО ЭТО ЗА СУЩНОСТЬ. Не боец: лошадь не дерётся, не входит в отряд и не имеет
## стороны. Её можно убить — тогда никто на ней не поедет. Пока на ней едут, её
## тело выключено, а всадник получает прибавку к скорости; спешился — лошадь
## снова стоит там, где её оставили.
##
## ПОЧЕМУ НЕ ЧЕРЕЗ unit.gd. Боец — это строй, поводок, приказы, оружие и урон.
## Лошади не нужно ничего из этого, а нужно ровно три вещи: стоять, умирать и
## возить. Наследовать ради трёх вещей систему на семьсот строк значит потом
## объяснять каждому читателю, почему лошадь ходит в набеги.
##

const EFFECTS := preload("res://scripts/combat/effects.gd")
const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")
const MODEL_ANIM := preload("res://scripts/model_anim.gd")
const MODEL := preload("res://assets/animals/Horse.glb")
## Модель сделана «в единицах Blender»: высота 4.8, длина 5.3. Приводим к
## росту около двух метров в холке.
const MODEL_SCALE := 0.45

const MAX_HEALTH := 90.0

## Во сколько раз быстрее пеший всадник. Полтора — заметно, но не превращает
## карту в маленькую: пешком до шахты идти две минуты, верхом чуть больше минуты.
const RIDE_SPEED_SCALE := 1.55

## Дальше этого сесть нельзя.
const MOUNT_RANGE := 4.0

signal died(point: Vector3)

@export var sync_position := Vector3.ZERO
@export var health := MAX_HEALTH
## Кто сейчас едет. Ноль — никто.
@export var rider_id := 0

var _zone: Area3D
var _alive := true
var _model: Node3D
var _anim: AnimationPlayer
var _current_anim := ""


func setup(data: Dictionary) -> void:
	position = data.get("point", Vector3.ZERO)
	sync_position = position


func _ready() -> void:
	add_to_group("horse")
	_build_visual()
	_build_hit_zone()


func _build_visual() -> void:
	# Настоящая модель со скелетом и анимациями (Quaternius, CC0). До неё лошадь
	# была четырьмя коробками: силуэт читался, но стоящая столбом коробка в
	# упряжке выглядела ящиком на колёсах, а не тягловым животным.
	_model = MODEL.instantiate()
	_model.scale = Vector3.ONE * MODEL_SCALE
	# Модель смотрит в +Z, игра считает передом -Z — как и у людей.
	_model.rotation.y = PI
	add_child(_model)
	_anim = _find_anim(_model)
	MODEL_ANIM.make_looping(_anim)
	_play("Idle")

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.7
	capsule.height = 2.2
	shape.shape = capsule
	shape.position = Vector3(0.0, 1.3, 0.0)
	add_child(shape)


func _build_hit_zone() -> void:
	_zone = HIT_ZONE.new()
	_zone.zone = "horse"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.0, 3.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.3, 0.0)
	_zone.add_child(shape)
	add_child(_zone)


func _physics_process(delta: float) -> void:
	if not Net.hosting():
		position = position.lerp(sync_position, clampf(delta * 12.0, 0.0, 1.0))
		return
	# Пока на ней едут, лошадь не существует отдельно: она под всадником.
	if rider_id != 0:
		return
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	sync_position = position


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _play(anim_name: String) -> void:
	if _anim == null or anim_name == _current_anim:
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name)


## Свободна ли: жива и без всадника.
func can_mount() -> bool:
	return _alive and rider_id == 0


func mount(peer: int) -> bool:
	if not Net.hosting() or not can_mount():
		return false
	rider_id = peer
	visible = false
	return true


func dismount(at: Vector3) -> void:
	if not Net.hosting():
		return
	rider_id = 0
	visible = true
	position = at
	sync_position = at


func take_damage(amount: float, attacker_id: int, _zone_name: String, point: Vector3,
		dir: Vector3, _aoe := false, _weapon := -1) -> void:
	if not Net.hosting() or not _alive:
		return
	health = maxf(0.0, health - amount)
	show_hit.rpc(point, dir, amount)
	if health > 0.0:
		return
	_alive = false
	print("[лошадь] убита игроком %d" % attacker_id)
	died.emit(global_position)
	queue_free()


@rpc("authority", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float) -> void:
	EFFECTS.blood(self, point, dir, amount)


## Для подсказки в интерфейсе.
func state_text() -> String:
	return "лошадь" if rider_id == 0 else "под седлом"
