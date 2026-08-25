extends Area3D
##
## Зона попадания на персонаже. Задел под Этап 3 (ранения и протезы): там эти
## же зоны станут точками отрыва конечностей, поэтому разметку делаем сразу,
## пока персонаж простой.
##
## Зоны живут на отдельном слое физики, чтобы поиск целей оружием не цеплял
## ни землю, ни капсулу самого персонажа.
##

## Ключ зоны: head, torso, arm_l, arm_r, leg_l, leg_r.
@export var zone := "torso"
## Множитель урона по этой зоне.
@export var damage_multiplier := 1.0


## Персонаж, которому принадлежит зона. Идём вверх по дереву, а не берём
## прямого родителя: зоны лежат в группирующей ноде, и она может переехать
## (на Этапе 3 они привяжутся к костям скелета).
func owner_character() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("take_damage"):
			return node as Node3D
		node = node.get_parent()
	return null


## Собрать зону попадания из собственного AABB меша и повесить на него же.
##
## Общий помощник для персонажей и юнитов: зона строится из РАЗМЕРОВ модели, а
## не из захардкоженных чисел, и висит на самой части тела — значит едет за
## анимацией и переживает замену модели.
static func attach(mesh: MeshInstance3D, key: String, multiplier: float, layer: int) -> Area3D:
	var box := mesh.get_aabb()
	var area := Area3D.new()
	area.set_script(load("res://scripts/combat/hit_zone.gd"))
	area.zone = key
	area.damage_multiplier = multiplier
	area.collision_layer = layer
	area.collision_mask = 0
	area.monitoring = false
	area.position = box.get_center()

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	area.add_child(shape)

	mesh.add_child(area)
	return area
