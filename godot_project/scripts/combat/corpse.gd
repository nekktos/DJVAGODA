extends Node3D
##
## Труп. GDD, раздел 3: труп остаётся в 3D-мире и не исчезает мгновенно.
##
## Показываем ту же модель персонажа в позе смерти — анимация "die" из пака
## Kenney, поставленная на последний кадр. Коллизии нет, чтобы живые не
## застревали в телах.
##

const MODELS := [
	"res://assets/characters/character-a.glb",
	"res://assets/characters/character-b.glb",
	"res://assets/characters/character-c.glb",
]
const MODEL_SCALE := 0.68


func setup(data: Dictionary) -> void:
	position = data["point"]
	rotation.y = float(data["yaw"])
	set_meta("slot", int(data["slot"]))
	set_meta("severed", int(data.get("severed", 0)))


func _ready() -> void:
	var slot: int = clampi(get_meta("slot", 0), 0, MODELS.size() - 1)
	var packed: PackedScene = load(MODELS[slot])
	var model: Node3D = packed.instantiate()
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)

	# Оторванные при жизни части у трупа тоже отсутствуют.
	var severed: int = get_meta("severed", 0)
	const PARTS := ["arm-left", "arm-right", "leg-left", "leg-right"]
	for i in PARTS.size():
		if severed & (1 << i):
			var mesh := _find_by_name(model, PARTS[i])
			if mesh != null:
				(mesh as MeshInstance3D).visible = false

	var anim := _find_anim(model)
	if anim != null and anim.has_animation("die"):
		anim.play("die")
		anim.seek(anim.get_animation("die").length, true)
		anim.pause()


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _find_by_name(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child in node.get_children():
		var found := _find_by_name(child, wanted)
		if found != null:
			return found
	return null
