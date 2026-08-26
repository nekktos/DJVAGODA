extends Node3D
##
## Куча ресурсов, высыпавшаяся из разбитого каравана.
##
## Подобрать может ЛЮБОЙ, кто подошёл (DESIGN_ANSWERS.md, пункт 15) — в этом и
## смысл грабежа: эльф не просто вредит злодею, а богатеет сам, а владелец
## может отбить своё обратно, если успеет.
##
## Кто и что забрал, решает ТОЛЬКО хост.
##

const RES := preload("res://scripts/economy/resources.gd")

## На каком расстоянии подбирается.
const PICKUP_RANGE := 3.5
## Сколько лежит, прежде чем исчезнуть.
const LIFETIME := 240.0

@export var contents: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Уровень снаряжения, выпавший с убитого (Этап 10, шаг 1). 0 — снаряжения в
## куче нет, это обычный груз каравана.
@export var gear: int = 0

var _taken := false


func setup(data: Dictionary) -> void:
	position = data["point"]
	contents = data["contents"]
	gear = int(data.get("gear", 0))


func _ready() -> void:
	add_to_group("loot")

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.9, 1.6)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.60, 0.26)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.28, 0.08)
	mesh.material_override = mat
	mesh.position = Vector3(0.0, 0.45, 0.0)
	add_child(mesh)

	if Net.hosting():
		get_tree().create_timer(LIFETIME).timeout.connect(func() -> void:
			if is_instance_valid(self):
				queue_free()
		)


## Отдать содержимое подошедшему. Только на хосте.
func collect(player: Node3D) -> int:
	if not Net.hosting() or _taken or player == null:
		return 0
	if global_position.distance_to(player.global_position) > PICKUP_RANGE:
		return 0
	var total := 0
	for kind in RES.COUNT:
		total += player.stock.add(kind, contents[kind])

	# Снаряжение с трупа достаётся тому, у кого оно хуже. Своё лучшее на худшее
	# не меняем — иначе подобрать чужую кучу значило бы понизить себя.
	var took_gear := false
	if gear > int(player.gear_tier):
		player.gear_tier = gear
		took_gear = true

	if total <= 0 and not took_gear:
		return 0
	_taken = true
	print("[груз] игрок %d подобрал %d единиц%s"
		% [int(player.peer_id), total, ", снаряжение уровня %d" % gear if took_gear else ""])
	queue_free()
	return total


func summary() -> String:
	var parts := PackedStringArray()
	for i in RES.COUNT:
		if contents[i] > 0:
			parts.append("%s %d" % [RES.SHORT[i], contents[i]])
	return ", ".join(parts)
