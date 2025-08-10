# PivotCamera.gd
# CameraPivot Node3D script:
# - input (mouse + touch) limitado a um Control opcional (rotation_control_path)
# - posição default exportável default_camera_local_pos (X lateral, Y vertical, Z distância)
# - colisão custom via raycast (PhysicsRayQueryParameters3D)
# - métodos públicos: set_pitch_limits, get_pitch_limits, set_rotation_control
extends Node3D

@export var spring_arm_node: NodePath = NodePath("SpringArm3D")
@export var camera_node: NodePath = NodePath("SpringArm3D/Camera3D")

# posição local padrão da câmera (X lateral, Y vertical, Z distância; Z negativo é "atrás")
@export var default_camera_local_pos: Vector3 = Vector3(0.0, 1.5, -4.0)

# recalcula automaticamente parâmetros derivados se true
@export var dynamic_adjustments: bool = true

# parâmetros derivados (visíveis para ajuste fino)
@export var spring_length: float = 4.0
@export var spring_margin: float = 0.15
@export var min_length: float = 0.5
@export var max_length: float = 8.0
@export var collision_mask: int = 1

# input / rotação
@export var mouse_sensitivity: float = 0.004
@export var touch_sensitivity: float = 0.02
@export var invert_y: bool = false
@export var min_pitch_deg: float = -20.0
@export var max_pitch_deg: float = 55.0

# suavização e robustez
@export var position_smooth_speed: float = 20.0
@export var rotation_smooth_speed: float = 12.0
@export var min_camera_distance: float = 0.25

# UI Control que limita a área de rotação (Control em um CanvasLayer)
@export var rotation_control_path: NodePath = NodePath("")

# usar colisão custom (raycast) - recomendado true se SpringArm3D clipa
@export var use_custom_collision: bool = true

# internals
var _spring_arm: SpringArm3D
var _camera: Camera3D

var _yaw: float = 0.0
var _pitch: float = 0.0
var _yaw_target: float = 0.0
var _pitch_target: float = 0.0

var _camera_target_global: Vector3
var _camera_prev_global: Vector3
var _current_length: float = 4.0

var _is_touching: bool = false
var _active_touch_index: int = -1
var _last_touch_pos: Vector2 = Vector2.ZERO
var _last_drag_frame_id: int = 0

var _rotation_control: Control = null
var _last_default_camera_local_pos: Vector3

func _ready():
	_spring_arm = get_node_or_null(spring_arm_node) as SpringArm3D
	_camera = get_node_or_null(camera_node) as Camera3D
	if not _spring_arm:
		push_error("PivotCamera.gd: SpringArm3D não encontrado em %s" % spring_arm_node)
		return
	if not _camera:
		push_error("PivotCamera.gd: Camera3D não encontrado em %s" % camera_node)
		return

	var r = rotation
	_yaw = r.y
	_pitch = r.x
	_yaw_target = _yaw
	_pitch_target = _pitch

	_camera_prev_global = _camera.global_transform.origin
	_camera_target_global = _camera_prev_global

	if rotation_control_path and rotation_control_path != NodePath(""):
		_rotation_control = get_node_or_null(rotation_control_path) as Control
		if not _rotation_control:
			push_warning("PivotCamera.gd: rotation_control_path definido, mas Control não encontrado: %s" % rotation_control_path)

	_last_default_camera_local_pos = default_camera_local_pos
	_recalculate_derived_from_default()

	# aplica spring_length inicial ao SpringArm
	_spring_arm.spring_length = _current_length

# recalcula parâmetros derivados quando default_camera_local_pos muda
func _recalculate_derived_from_default() -> void:
	var lx = default_camera_local_pos.x
	var ly = default_camera_local_pos.y
	var lz = default_camera_local_pos.z

	var suggested_length = abs(lz) if lz != 0 else sqrt(lx*lx + ly*ly)
	_current_length = max(suggested_length, min_camera_distance)
	spring_length = _current_length

	if dynamic_adjustments:
		min_length = max(min_camera_distance, _current_length * 0.25)
		max_length = max(_current_length * 1.8, min_length + 0.1)
		spring_margin = clamp(_current_length * 0.035, 0.03, 0.5)

	# aplica no SpringArm se existir
	if _spring_arm:
		_spring_arm.spring_length = _current_length

# verifica se coordenada de input está dentro do Control configurado
func _is_pos_within_control(pos: Vector2) -> bool:
	if not _rotation_control:
		return true
	var rect: Rect2 = _rotation_control.get_global_rect()
	return rect.has_point(pos)

func _input(event):
	# Mouse motion
	if event is InputEventMouseMotion:
		var pos = event.position
		if not _is_pos_within_control(pos):
			return
		var dx = -event.relative.x * mouse_sensitivity
		var dy = -event.relative.y * mouse_sensitivity
		_yaw_target += dx
		_pitch_target += (-dy if invert_y else dy)
		_clamp_pitch_target()

	# Mouse wheel (zoom)
	elif event is InputEventMouseButton:
		var mbe = event as InputEventMouseButton
		if not mbe.pressed and mbe.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var dir = -1.0 if mbe.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_current_length = clamp(_current_length + dir * 0.2, min_length, max_length)
			if position_smooth_speed <= 0.0 and _spring_arm:
				_spring_arm.spring_length = _current_length

	# Touch begin/end
	elif event is InputEventScreenTouch:
		var t = event as InputEventScreenTouch
		if t.pressed:
			if _is_pos_within_control(t.position):
				_is_touching = true
				_active_touch_index = t.index
				_last_touch_pos = t.position
		else:
			if t.index == _active_touch_index:
				_is_touching = false
				_active_touch_index = -1

	# Touch drag
	elif event is InputEventScreenDrag:
		var d = event as InputEventScreenDrag
		if not _is_pos_within_control(d.position):
			return
		var dx2 = -d.relative.x * touch_sensitivity
		var dy2 = -d.relative.y * touch_sensitivity
		_yaw_target += dx2
		_pitch_target += (-dy2 if invert_y else dy2)
		_clamp_pitch_target()
		_last_touch_pos = d.position
		_last_drag_frame_id = Engine.get_frames_drawn()

func _clamp_pitch_target():
	var min_r = deg_to_rad(min_pitch_deg)
	var max_r = deg_to_rad(max_pitch_deg)
	_pitch_target = clamp(_pitch_target, min_r, max_r)

func _physics_process(delta):
	# detectar mudança na default_camera_local_pos no Inspector
	if default_camera_local_pos != _last_default_camera_local_pos:
		_last_default_camera_local_pos = default_camera_local_pos
		_recalculate_derived_from_default()

	# rotação do pivot (suavizada)
	var rt = clamp(rotation_smooth_speed * delta, 0.0, 1.0)
	_yaw = lerp_angle(_yaw, _yaw_target, rt)
	_pitch = lerp_angle(_pitch, _pitch_target, rt)
	rotation = Vector3(_pitch, _yaw, 0)

	# fallback touch: se _is_touching e não veio drag recentemente, você pode implementar fallback aqui se quiser
	# aplicar colisão custom ou posição default
	if use_custom_collision:
		_apply_custom_camera_collision(delta)
	else:
		_apply_default_camera_position(delta)

# cria desired global da base default_camera_local_pos
func _compute_desired_global_from_default() -> Vector3:
	var pivot_global: Vector3 = global_transform.origin
	var lateral_world: Vector3 = global_transform.basis.x.normalized() * default_camera_local_pos.x
	var vertical_world: Vector3 = Vector3.UP * default_camera_local_pos.y
	var forward_world: Vector3 = -global_transform.basis.z.normalized() * abs(default_camera_local_pos.z)
	return pivot_global + lateral_world + vertical_world + forward_world

func _apply_default_camera_position(delta):
	var desired_global = _compute_desired_global_from_default()
	var smooth_t = clamp(position_smooth_speed * delta, 0.0, 1.0)
	_camera_target_global = desired_global
	_camera_prev_global = _camera.global_transform.origin
	var new_cam_pos = _camera_prev_global.lerp(_camera_target_global, smooth_t)
	var cam_xform = _camera.global_transform
	cam_xform.origin = new_cam_pos
	_camera.global_transform = cam_xform

# colisão custom via PhysicsRayQueryParameters3D
func _apply_custom_camera_collision(delta):
	var pivot_global: Vector3 = global_transform.origin
	var desired_global: Vector3 = _compute_desired_global_from_default()

	var exclude_arr: Array = []
	if get_parent():
		exclude_arr.append(get_parent())
	exclude_arr.append(_camera)

	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = pivot_global
	params.to = desired_global
	params.exclude = exclude_arr
	params.collision_mask = collision_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false

	var hit := space.intersect_ray(params)

	var target_pos: Vector3
	if hit and hit.size() > 0:
		var hit_pos: Vector3 = hit.get("position", hit.get("point", Vector3.ZERO))
		var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
		target_pos = hit_pos + hit_normal * spring_margin
	else:
		target_pos = desired_global

	if target_pos.distance_to(pivot_global) < min_camera_distance:
		var dir = (target_pos - pivot_global).normalized()
		if dir.length() == 0:
			dir = -global_transform.basis.z.normalized()
		target_pos = pivot_global + dir * min_camera_distance

	var smooth_t = clamp(position_smooth_speed * delta, 0.0, 1.0)
	_camera_target_global = target_pos
	_camera_prev_global = _camera.global_transform.origin
	var new_cam_pos = _camera_prev_global.lerp(_camera_target_global, smooth_t)

	var cam_xform = _camera.global_transform
	cam_xform.origin = new_cam_pos
	_camera.global_transform = cam_xform

# --- API pública para ser chamada de fora (ex: Player.gd) ---
func set_rotation_control(control: Control) -> void:
	_rotation_control = control

func set_pitch_limits(min_deg: float, max_deg: float) -> void:
	min_pitch_deg = min_deg
	max_pitch_deg = max_deg
	# garante que target esteja dentro dos limites
	_clamp_pitch_target()

func get_pitch_limits() -> Vector2:
	return Vector2(min_pitch_deg, max_pitch_deg)
