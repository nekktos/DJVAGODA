extends SceneTree
##
## Диагностика импортированной модели: части, их размеры и положение.
##
## Трансформы считаем сами, спускаясь по дереву: global_transform в скрипте
## SceneTree ещё не распространён, и на него полагаться нельзя.
##
## Запуск: godot --headless --path godot_project --script res://tools/model_probe.gd
##

const MODEL := "res://assets/characters/character-a.glb"


func _initialize() -> void:
	var packed: PackedScene = load(MODEL)
	if packed == null:
		print("не удалось загрузить ", MODEL)
		quit(1)
		return

	print("--- части, размеры и путь ---")
	var total := AABB()
	var first := true
	for entry in _collect(packed.instantiate(), Transform3D(), ""):
		var box: AABB = entry["box"]
		print("%-11s размер(%.2f, %.2f, %.2f)  низ y=%.2f верх y=%.2f  центр(%.2f, %.2f, %.2f)" % [
			entry["name"],
			box.size.x, box.size.y, box.size.z,
			box.position.y, box.position.y + box.size.y,
			box.get_center().x, box.get_center().y, box.get_center().z,
		])
		print("            путь: %s" % entry["path"])
		total = box if first else total.merge(box)
		first = false

	print("--- весь персонаж ---")
	print("высота %.2f, ширина %.2f, глубина %.2f, низ y=%.2f" % [
		total.size.y, total.size.x, total.size.z, total.position.y
	])
	quit()


func _collect(node: Node, parent_xform: Transform3D, path: String) -> Array:
	var here := path + ("/" if path != "" else "") + String(node.name)
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform

	var found := []
	if node is MeshInstance3D:
		found.append({
			"name": String(node.name),
			"path": here,
			"box": xform * (node as MeshInstance3D).get_aabb(),
		})
	for child in node.get_children():
		found.append_array(_collect(child, xform, here))
	return found
