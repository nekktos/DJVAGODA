extends SceneTree
##
## Диагностика скелетной модели: кости, их положение в позе покоя и размеры
## мешей.
##
## Нужна ровно для одного: расчленение на скиннутой модели делается не «спрятать
## меш», а «схлопнуть кость». Чтобы это написать, надо знать имена костей, их
## иерархию и где они стоят — а по gltf это читается плохо: Godot переименовывает
## и перестраивает.
##
## Запуск:
##   godot --headless --path godot_project --script res://tools/rig_probe.gd
##   godot --headless --path godot_project --script res://tools/rig_probe.gd -- Guard
##

const DIR := "res://assets/people/"


func _initialize() -> void:
	var who := "Elf"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		who = args[0]

	# Свои модели из кузницы приезжают одним файлом `.glb`, покупные паки —
	# `.gltf` рядом с текстурами. Пробник обязан читать оба: иначе проверить
	# сделанное своими руками нечем.
	var path := ""
	for ext in [".gltf", ".glb"]:
		if ResourceLoader.exists(DIR + who + ext):
			path = DIR + who + ext
			break
	var packed: PackedScene = load(path) if path != "" else null
	if packed == null:
		print("не загрузилось: ", DIR + who + " (.gltf/.glb)")
		quit(1)
		return

	var root: Node = packed.instantiate()
	print("--- дерево ---")
	_print_tree(root, "")

	var skel := _find_skeleton(root)
	if skel == null:
		print("скелета нет")
		quit(1)
		return

	print("--- кости (", skel.get_bone_count(), ") ---")
	for i in skel.get_bone_count():
		var parent := skel.get_bone_parent(i)
		var rest: Transform3D = skel.get_bone_global_rest(i)
		print("%2d %-16s родитель %-16s покой(%.2f, %.2f, %.2f)" % [
			i, skel.get_bone_name(i),
			skel.get_bone_name(parent) if parent >= 0 else "-",
			rest.origin.x, rest.origin.y, rest.origin.z,
		])

	print("--- меши ---")
	for mesh in _meshes(root):
		var box: AABB = mesh.get_aabb()
		print("%-20s размер(%.2f, %.2f, %.2f) низ y=%.2f" % [
			mesh.name, box.size.x, box.size.y, box.size.z, box.position.y
		])

	var player := _find_anim(root)
	if player != null:
		print("--- анимации ---")
		print(", ".join(player.get_animation_list()))
		_report_scale_tracks(player)
	quit()


## Есть ли в анимациях НЕЕДИНИЧНЫЙ масштаб костей.
##
## Вопрос не праздный: расчленение на скиннутой модели делается схлопыванием
## кости в ноль, а анимация переписывает позу каждый кадр. Если дорожки масштаба
## везде единичные (Blender пишет их всегда, даже когда они ничего не делают),
## их можно выбросить — и тогда схлопнутая кость останется схлопнутой.
func _report_scale_tracks(player: AnimationPlayer) -> void:
	var total := 0
	var moving := 0
	var worst := 0.0
	var worst_where := ""
	for name in player.get_animation_list():
		var anim: Animation = player.get_animation(name)
		for track in anim.get_track_count():
			if anim.track_get_type(track) != Animation.TYPE_SCALE_3D:
				continue
			total += 1
			var off := 0.0
			for key in anim.track_get_key_count(track):
				var value: Vector3 = anim.track_get_key_value(track, key)
				off = maxf(off, (value - Vector3.ONE).length())
			if off > 0.001:
				moving += 1
			if off > worst:
				worst = off
				worst_where = "%s / %s" % [name, anim.track_get_path(track)]
	print("--- дорожки масштаба ---")
	print("всего %d, неединичных %d, наибольшее отклонение %.4f (%s)"
		% [total, moving, worst, worst_where])


func _print_tree(node: Node, indent: String) -> void:
	print("%s%s (%s)" % [indent, node.name, node.get_class()])
	# Кости скелета в дерево не выводим: их печатает отдельный список, иначе
	# вывод тонет в полусотне строк.
	if node is Skeleton3D:
		return
	for child in node.get_children():
		_print_tree(child, indent + "  ")


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _meshes(node: Node) -> Array:
	var found := []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
