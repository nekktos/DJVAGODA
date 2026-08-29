extends SceneTree
##
## Что на самом деле собрал `building_look.gd`.
##
## Нужен потому, что «на снимке знамени не видно» — это два разных диагноза:
## его не создали или его создали не там. Глазами их не различить, а probe
## отвечает за секунду.
##
## Запуск: godot --headless --path godot_project --script res://tools/look_probe.gd
##

const LOOK := preload("res://scripts/economy/building_look.gd")
const RES := preload("res://scripts/economy/resources.gd")


func _initialize() -> void:
	for kind in RES.BUILDING_NAMES.size():
		var size: Vector3 = RES.BUILDING_SIZE[kind]
		var root: Node3D = LOOK.build(kind, size)
		print("--- %s, габарит (%.0f, %.0f, %.0f) ---" % [
			RES.BUILDING_NAMES[kind], size.x, size.y, size.z
		])
		print("  всего узлов: %d" % root.get_child_count())
		# Имена у вставленных сцен служебные (@Node3D@17), искать по ним нечего.
		# Украшения добавляются ПОСЛЕДНИМИ — печатаем хвост списка с координатами
		# и с тем, куда каждое смотрит после разворота.
		var tail: int = maxi(0, root.get_child_count() - 6)
		for i in range(tail, root.get_child_count()):
			var child: Node3D = root.get_child(i)
			var at: Vector3 = child.position
			# Берём ЛОКАЛЬНЫЙ базис: узел вне дерева, и global_transform у него
			# врёт — показывает единичный, из-за чего разворот кажется несделанным.
			var out: Vector3 = child.transform.basis * Vector3(1.0, 0.0, 0.0)
			print("  #%d %-20s в (%.2f, %.2f, %.2f), его +X смотрит в (%.2f, %.2f, %.2f)" % [
				i, child.get_class(), at.x, at.y, at.z, out.x, out.y, out.z
			])
	quit()
