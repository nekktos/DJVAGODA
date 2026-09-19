extends Node3D
##
## Труп. GDD, раздел 3: труп остаётся в 3D-мире и не исчезает мгновенно.
##
## Показываем ту же модель персонажа в позе смерти — анимацию `Death`,
## поставленную на последний кадр. Коллизии нет, чтобы живые не застревали в
## телах.
##
## Модель тут своя, а не «та же, что была у покойника»: труп живёт отдельной
## нодой уже после того, как персонаж исчез из дерева, и тащить за собой его
## сборку значит держать вторую копию всей логики облика. Слот выбирает, кто
## именно лежит, — этого хватает, чтобы поле после схватки выглядело разным.
##

const RIG := preload("res://scripts/combat/rig.gd")
const MODEL_ANIM := preload("res://scripts/model_anim.gd")

const MODELS := [
	"res://assets/people/Villain.glb",
	"res://assets/people/Elf.glb",
	"res://assets/people/Guard.glb",
	"res://assets/people/Swordsman.glb",
	"res://assets/people/Archer.glb",
	"res://assets/people/Peasant.glb",
]
const MODEL_SCALE := 0.63


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
	# Тот же разворот, что у живых: модель смотрит в +Z, игра — в -Z.
	model.rotation.y = PI
	add_child(model)
	RIG.hide_built_in_weapon(model)

	# Оторванные при жизни части у трупа тоже отсутствуют: тем же схлопыванием
	# костей, что и у живого (см. `rig.gd`). Труп с целыми руками рядом с парой
	# оторванных стирает то, что человек только что видел.
	var skeleton := RIG.find_skeleton(model)
	RIG.apply_severed(skeleton, int(get_meta("severed", 0)))

	var anim := _find_anim(model)
	var death := MODEL_ANIM.resolve(anim, "die")
	if anim != null and death != "":
		anim.play(death)
		anim.seek(anim.get_animation(death).length, true)
		anim.pause()


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null
