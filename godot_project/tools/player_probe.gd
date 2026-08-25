extends Node
##
## Диагностика собранного персонажа в живой сцене: где он стоит, какие части
## нашлись, видимы ли они и где они в мире.
##
## Запуск: godot --headless --path godot_project -- --host --playerprobe
##

var _world: Node3D


func start(world: Node3D) -> void:
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		print("[персонаж] ПРОВАЛ: не заспавнен")
		get_tree().quit(1)
		return

	print("[персонаж] позиция %s" % me.global_position)
	var model: Node3D = me.get_node_or_null("Model")
	print("[персонаж] нода Model: %s" % ("есть" if model != null else "НЕТ"))
	if model != null:
		print("[персонаж] масштаб модели %s, поворот %s" % [model.scale, model.rotation])

	var found := 0
	for mi in _meshes(me):
		found += 1
		var box: AABB = mi.get_aabb()
		print("  %-12s видим=%s  мир(%.2f, %.2f, %.2f)  размер(%.2f, %.2f, %.2f)  материал=%s" % [
			mi.name, mi.visible,
			mi.global_position.x, mi.global_position.y, mi.global_position.z,
			box.size.x, box.size.y, box.size.z,
			"есть" if (mi.get_surface_override_material(0) != null or mi.material_override != null or (mi.mesh != null and mi.mesh.surface_get_material(0) != null)) else "НЕТ",
		])
	print("[персонаж] мешей всего: %d" % found)
	get_tree().quit()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
