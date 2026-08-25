extends RigidBody3D
##
## Оторванная конечность: падает и остаётся лежать. Рейтинг 21+, расчленение
## показываем без смягчения (GDD, разделы 3-4).
##
## Локальный визуал: каждый пир создаёт её сам, увидев в реплицированном
## состоянии тела, что конечность оторвана. По сети не ходит ничего.
##

## Сколько лежит, прежде чем исчезнуть. Полностью вечными их держать нельзя —
## в затяжном бою их накопятся сотни.
const LIFETIME := 90.0

var _mesh: Mesh
var _place := Transform3D()
var _scale := Vector3.ONE


func setup(mesh: Mesh, at: Transform3D, _model_scale: float) -> void:
	_mesh = mesh
	_scale = at.basis.get_scale()
	# Масштаб уносим в дочерний меш: масштабировать само физическое тело нельзя.
	_place = Transform3D(at.basis.orthonormalized(), at.origin)


func _ready() -> void:
	transform = _place
	collision_layer = 0
	collision_mask = 1          # только статичный мир, живых не толкаем

	if _mesh != null:
		var view := MeshInstance3D.new()
		view.mesh = _mesh
		view.scale = _scale
		add_child(view)

		var box: AABB = _mesh.get_aabb()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box.size * _scale
		shape.shape = box_shape
		shape.position = box.get_center() * _scale
		add_child(shape)

	# Отлетает в случайную сторону, чтобы куски не падали строго вниз.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	linear_velocity = Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(2.0, 4.0), rng.randf_range(-2.5, 2.5))
	angular_velocity = Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))

	var timer := get_tree().create_timer(LIFETIME)
	timer.timeout.connect(queue_free)
