extends RefCounted
##
## Скелетный персонаж: зоны попадания на костях, расчленение и точка хвата.
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Про этот конкретный скелет знают трое: персонаж, боец и
## батрак. Раньше знание было размазано по всем троим в виде словаря «имя меша →
## зона», и замена модели означала правку в трёх местах с тремя шансами разойтись.
##
## ЧТО ИЗМЕНИЛОСЬ ПРОТИВ КОРОБОЧНОЙ МОДЕЛИ. У Kenney каждая часть тела — свой
## меш, и отрыв руки сводился к «спрятать ноду». У нормального персонажа тело —
## ОДИН скиннутый меш на скелете, прятать нечего. Поэтому:
##
##   - зоны попадания висят не на мешах, а на костях (`BoneAttachment3D`), и
##     едут за анимацией так же, как ехали за мешами;
##   - отрыв — это схлопывание кости в ноль: вся ветка ниже неё (предплечье,
##     кисть, пальцы) уходит в точку вместе с ней, потому что поза кости
##     умножается на позу родителя.
##
## ПОЧЕМУ СХЛОПЫВАНИЕ ВООБЩЕ РАБОТАЕТ. Анимация переписывает позу костей каждый
## кадр и затёрла бы масштаб — но дорожек масштаба в этих анимациях нет ни одной
## (проверено `tools/rig_probe.gd`: всего 0). Blender пишет их всегда, а импортёр
## Godot выбрасывает единичные. Значит масштаб — единственный канал позы, который
## никто, кроме нас, не трогает.
##
## ЗОНЫ — ШАРЫ, А НЕ КОРОБКИ. Кость повёрнута как ей удобно художнику, и коробка
## на ней встаёт под непредсказуемым углом: этого не видно в headless-прогоне и
## почти не видно на снимке. Шар одинаков со всех сторон, и ошибиться в нём
## нечем.
##

const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")

## Кость, которую схлопываем, отрывая конечность. Порядок — как в `body.gd::Limb`.
const SEVER_BONES := ["UpperArm.L", "UpperArm.R", "UpperLeg.L", "UpperLeg.R"]

## Зоны попадания: ключ → список [кость, радиус в единицах модели].
##
## Радиусы подобраны по позе покоя (кость головы на высоте 2.10, торса 1.54,
## бедра 1.01, колена 0.60). Голову намеренно держим выше плеч: при пересечении
## зон оружие выбирает ту, у которой множитель больше, и раздутый шар головы
## превратил бы любое попадание в корпус в попадание в голову.
const ZONE_BONES := {
	"head": [["Head", 0.32]],
	"torso": [["Torso", 0.36], ["Hips", 0.30]],
	"arm_l": [["UpperArm.L", 0.22], ["LowerArm.L", 0.24]],
	"arm_r": [["UpperArm.R", 0.22], ["LowerArm.R", 0.24]],
	"leg_l": [["UpperLeg.L", 0.26], ["LowerLeg.L", 0.26]],
	"leg_r": [["UpperLeg.R", 0.26], ["LowerLeg.R", 0.26]],
}

## Кость, к которой крепится оружие. У художника она уже есть — своих точек
## хвата считать не надо.
const WEAPON_BONE := "Weapon.R"

## Насколько схлопывается оторванная кость. Не ноль: нулевой масштаб вырождает
## матрицу позы, и Godot ругается на неортогональный базис.
const SEVERED_SCALE := 0.001


## Найти кость по имени, переживая переименование импортёром.
##
## Если в модели есть МЕШ с тем же именем, что и кость, Godot переименовывает
## кость: у клирика голова приехала как «Head_2», потому что голова у него ещё
## и отдельный меш. Ищем сначала точное имя, потом с любым суффиксом через
## подчёркивание — иначе у одного персонажа из шести нет зоны головы, и в
## голову ему просто нельзя попасть.
static func bone(skeleton: Skeleton3D, wanted: String) -> int:
	if skeleton == null:
		return -1
	var found := skeleton.find_bone(wanted)
	if found >= 0:
		return found
	for i in skeleton.get_bone_count():
		if String(skeleton.get_bone_name(i)).begins_with(wanted + "_"):
			return i
	return -1


## Меши самого ТЕЛА — те, что висят прямо на скелете.
##
## Нужны первому лицу: своё тело из глаз не видно, и показывать игроку изнанку
## собственной головы нельзя. Прятать приходится именно тело и только его —
## оружие, знамёна и всё навешенное живут на `BoneAttachment3D`, а не на самом
## скелете, и в этот список не попадают. Меч в руке в первом лице видеть надо.
static func body_meshes(skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if skeleton == null:
		return found
	for child in skeleton.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			found.append(mesh)
	return found


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null


## Спрятать оружие, которое художник положил персонажу в руку.
##
## У каждого из шести своё: меч, посох, лук, кинжал. В игре оружие своё, оно
## меняется цифрами и уровнем снаряжения, и два клинка в одной кисти — это не
## богатство выбора, а ошибка.
static func hide_built_in_weapon(model: Node) -> void:
	for mesh in _meshes(model):
		var name: String = String(mesh.name)
		if (name.containsn("sword") or name.containsn("staff") or name.containsn("bow")
				or name.containsn("dagger")):
			mesh.visible = false


## Развесить зоны попадания по костям. Возвращает словарь «ключ → список зон».
##
## Зон на ключ несколько: рука это плечо И предплечье, корпус — грудь И таз.
## Один шар на конечность либо не достаёт до кисти, либо залезает в туловище.
static func build_zones(skeleton: Skeleton3D, multipliers: Dictionary, layer: int) -> Dictionary:
	var zones := {}
	if skeleton == null:
		return zones
	for key in ZONE_BONES.keys():
		var made: Array[Area3D] = []
		for entry in ZONE_BONES[key]:
			var idx: int = bone(skeleton, entry[0])
			if idx < 0:
				push_warning("В скелете нет кости «%s»" % entry[0])
				continue
			var mount := BoneAttachment3D.new()
			mount.bone_name = skeleton.get_bone_name(idx)
			mount.bone_idx = idx
			skeleton.add_child(mount)

			var area := Area3D.new()
			area.set_script(HIT_ZONE)
			area.zone = key
			area.damage_multiplier = float(multipliers.get(key, 1.0))
			area.collision_layer = layer
			area.collision_mask = 0
			area.monitoring = false
			var shape := CollisionShape3D.new()
			var ball := SphereShape3D.new()
			ball.radius = float(entry[1])
			shape.shape = ball
			area.add_child(shape)
			mount.add_child(area)
			made.append(area)
		zones[key] = made
	return zones


## Точка хвата: узел, едущий за кистью. Оружие вешается сюда.
## Возвращает УЗЕЛ ХВАТА, а не саму привязку к кости: разворот кости в нём уже
## скомпенсирован, и вешать оружие надо именно сюда.
static func weapon_mount(skeleton: Skeleton3D) -> Node3D:
	if skeleton == null:
		return null
	var idx := bone(skeleton, WEAPON_BONE)
	if idx < 0:
		return null
	var mount := BoneAttachment3D.new()
	mount.name = "WeaponMount"
	mount.bone_name = skeleton.get_bone_name(idx)
	mount.bone_idx = idx
	skeleton.add_child(mount)

	# ХВАТ разворачиваем обратно, компенсируя разворот кости.
	#
	# Кость `Weapon.R` у моделей Quaternius повёрнута почти на прямой угол к
	# персонажу: измерено пробой (`tools/grip_probe.gd`), её Z смотрит в -X
	# модели, а Y — вниз. Оружие же собирается в осях ПЕРСОНАЖА: «+Z — куда
	# смотрит, +Y — вверх» (см. `weapon_visual.gd`). Повешенное прямо на кость,
	# оно и торчало вбок от бедра, как палка, вставленная в пояс.
	#
	# Берём базис ПОКОЯ, а не текущей позы: обратный к покою разворот делает
	# оружие правильным в стойке и оставляет ему разницу между позой и покоем —
	# то есть меч продолжает ходить вместе с рукой по анимации, а не висит
	# приклеенным к телу.
	var grip := Node3D.new()
	grip.name = "Grip"
	grip.transform.basis = skeleton.get_bone_global_rest(idx).basis.orthonormalized().inverse()
	mount.add_child(grip)
	return grip


## Схлопнуть или вернуть конечность. `mask` — биты `body.gd::Limb`.
##
## Зовём и при отрыве, и при получении маски по сети: поздний клиент обязан
## увидеть безрукого безруким, а одного вызова в момент отрыва для этого мало.
static func apply_severed(skeleton: Skeleton3D, mask: int) -> void:
	if skeleton == null:
		return
	for limb in SEVER_BONES.size():
		var idx := bone(skeleton, SEVER_BONES[limb])
		if idx < 0:
			continue
		var gone := (mask & (1 << limb)) != 0
		skeleton.set_bone_pose_scale(idx, Vector3.ONE * (SEVERED_SCALE if gone else 1.0))


## Схлопнута ли конечность НА САМОМ ДЕЛЕ. Нужна автопроверкам.
##
## Маска увечий и вид — две разные вещи, и разойтись они могут молча: в новой
## модели кость зовут иначе, `apply_severed` её не находит, маска стоит, все
## проверки правил зелёные, а рука на месте. Спрашиваем не «числится ли
## оторванной», а «схлопнута ли кость».
static func is_collapsed(skeleton: Skeleton3D, limb: int) -> bool:
	if skeleton == null or limb < 0 or limb >= SEVER_BONES.size():
		return false
	var idx := bone(skeleton, SEVER_BONES[limb])
	if idx < 0:
		return false
	return skeleton.get_bone_pose_scale(idx).x < 0.5


## Где сейчас находится оторванная конечность — чтобы там брызнула кровь и
## оттуда упал кусок.
static func limb_point(skeleton: Skeleton3D, limb: int) -> Vector3:
	if skeleton == null or limb < 0 or limb >= SEVER_BONES.size():
		return Vector3.ZERO
	var idx := bone(skeleton, SEVER_BONES[limb])
	if idx < 0:
		return skeleton.global_position
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin


## Меш оторванной конечности.
##
## Из скиннутого тела руку не вырезать: это один меш на весь силуэт, и «взять
## его кусок» значит резать геометрию по костям в рантайме. Кусок собираем из
## примитива — на земле среди крови капсула читается как конечность, а лишней
## системы за собой не тянет.
static func limb_mesh(limb: int) -> Mesh:
	var leg := limb >= 2
	var piece := CapsuleMesh.new()
	piece.radius = 0.12 if leg else 0.09
	piece.height = 0.90 if leg else 0.72
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.36, 0.32)
	mat.roughness = 0.85
	piece.material = mat
	return piece


## Покрасить модель, НЕ теряя текстуру.
##
## `material_override` с плоским цветом стирает всю раскраску: чемпион стражи
## превращался в красный силуэт без деталей. Здесь мы дублируем материал каждой
## поверхности и красим только `albedo_color` — он УМНОЖАЕТСЯ на текстуру, и
## доспех остаётся доспехом, только красным.
static func tint(model: Node, color: Color) -> void:
	for node in _meshes(model):
		var mesh: MeshInstance3D = node
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var from: Material = mesh.mesh.surface_get_material(surface)
			var mat: StandardMaterial3D = (
				from.duplicate() if from is StandardMaterial3D else StandardMaterial3D.new()
			)
			mat.albedo_color = color
			mesh.set_surface_override_material(surface, mat)


## Опознавательная перевязь стороны: цветная лента через грудь.
##
## ЗАЧЕМ. Живой отчёт по playtest-6 ответил «НЕТ» на два вопроса подряд:
## «стороны отличаются с первого взгляда» и «кто есть кто в бою понятно». И это
## правда: модель пешки одна на все стороны (`unit.gd::_look_model` выбирает её
## по РОЛИ — мечник или лучник), так что мечник злодея и мечник стражи
## выглядели одинаково до пикселя.
##
## ПОЧЕМУ НЕ ПЕРЕКРАСКА ЦЕЛИКОМ. `tint` красит модель в один цвет — так сделан
## распорядитель, и для одного особенного бойца это годится. Перекрасить так все
## стороны значит стереть с моделей кожу, волосы и одежду: вместо войска выйдут
## три толпы одноцветных силуэтов.
##
## ПОЧЕМУ КОЛЬЦОМ, А НЕ НАКИДКОЙ НА СПИНЕ. Лента видна со ВСЕХ сторон. Накидка
## читается только со спины, нагрудник только спереди, а в бою противник
## поворачивается как ему вздумается.
##
## Лента крепится к КОСТИ ГРУДИ и потому ездит вместе с телом: на привязанной к
## корню она оставалась бы висеть в воздухе, когда боец нагибается или падает.
static func faction_band(skeleton: Skeleton3D, color: Color) -> Node3D:
	if skeleton == null:
		return null
	var idx := bone(skeleton, "Torso")
	if idx < 0:
		return null
	var mount := BoneAttachment3D.new()
	mount.name = "FactionBand"
	mount.bone_name = skeleton.get_bone_name(idx)
	mount.bone_idx = idx
	skeleton.add_child(mount)

	var ring := CylinderMesh.new()
	# Чуть шире тела, чтобы лента лежала ПОВЕРХ, а не тонула в груди.
	ring.top_radius = 0.42
	ring.bottom_radius = 0.42
	ring.height = 0.22
	ring.radial_segments = 10
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	# Без бликов: лента должна читаться цветом, а не отсветом, и на солнце не
	# выбеливаться до белого пятна.
	mat.roughness = 1.0
	mat.metallic = 0.0
	var band := MeshInstance3D.new()
	band.name = "Band"
	band.mesh = ring
	band.material_override = mat
	mount.add_child(band)
	return mount


## Отметить выбитые глаза кровью на лице.
##
## Накладок на глазницы больше нет и быть не может: у Kenney лицо было отдельным
## мешем с известными размерами, у скиннутой модели — часть общего тела, и
## поставить квадратик «вот сюда» не по чему. Красим лицо кровью: видно с той же
## дистанции, а ошибиться в ориентации нечем.
##
## Если в модели отдельного лица нет (у следопыта его нет), не делаем ничего:
## потеря глаза при этом остаётся в силе, просто её не видно снаружи.
static func mark_eye_loss(model: Node, count: int) -> void:
	if count <= 0:
		return
	for node in _meshes(model):
		var mesh: MeshInstance3D = node
		var name: String = String(mesh.name).to_lower()
		if not (name.contains("face") or name.begins_with("head")):
			continue
		if mesh.mesh == null:
			continue
		var shade := Color(1.0, 1.0, 1.0).lerp(Color(0.45, 0.06, 0.06), clampf(count * 0.45, 0.0, 0.9))
		for surface in mesh.mesh.get_surface_count():
			var from: Material = mesh.mesh.surface_get_material(surface)
			var mat: StandardMaterial3D = (
				from.duplicate() if from is StandardMaterial3D else StandardMaterial3D.new()
			)
			mat.albedo_color = shade
			mesh.set_surface_override_material(surface, mat)


static func _meshes(node: Node) -> Array:
	var found := []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
