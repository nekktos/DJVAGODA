extends Node3D
##
## Труп. GDD, раздел 3: труп остаётся в 3D-мире и не исчезает мгновенно.
##
## Чистая декорация: коллизии нет, чтобы живые не застревали в телах, и по сети
## реплицируется только факт появления — двигаться труп не умеет.
##

const SLOT_COLORS := preload("res://scripts/player.gd").SLOT_COLORS


func setup(data: Dictionary) -> void:
	position = data["point"]
	rotation.y = float(data["yaw"])
	set_meta("slot", int(data["slot"]))


func _ready() -> void:
	var slot: int = clampi(get_meta("slot", 0), 0, SLOT_COLORS.size() - 1)

	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	# Труп темнее живого: сразу видно, что это тело, а не игрок.
	mat.albedo_color = SLOT_COLORS[slot].darkened(0.45)
	mesh.material_override = mat
	# Лежит на земле.
	mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	mesh.position = Vector3(0.0, 0.4, 0.0)
	add_child(mesh)
