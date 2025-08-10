# Player.gd
# CHANGES: ADICIONADO export invert_forward_input; ADICIONADO notificação de is_running ao States;
#          preservado código de multiplayer e integração com Camera3D dentro do camera_pivot.
extends CharacterBody3D

@export var speed: float = 5.0
@export var acceleration: float = 8.0
@export var deceleration: float = 12.0
@export var gravity: float = 9.8

# multiplicador de corrida (ex.: 2.0 = dobrar velocidade)
@export var run_multiplier: float = 2.0

@export var body_node_path: NodePath = NodePath(".")
@export var body_rotation_speed: float = 8.0
@export var face_negative_z: bool = true

@export var camera_pivot_path: NodePath = NodePath("")
@export var states_node_path: NodePath = NodePath("States")

# ADICIONADO: permite inverter o comportamento do eixo "up" (se seu InputMap retorna valores invertidos)
@export var invert_forward_input: bool = true

var direction: Vector3 = Vector3.ZERO
var input_dir: Vector2 = Vector2.ZERO

var _body_node: Node3D = null
var _states_manager: Node = null
var _camera_pivot: Node = null
var _camera_node: Camera3D = null

var is_running: bool = false

# MULTIPLAYER / NETWORK (preservado)
var last_sent_pos: Vector3 = Vector3.ZERO
var send_interval: float = 0.1
var send_timer: float = 0.0

func _ready() -> void:
	# cacheia body visual
	if body_node_path and body_node_path != NodePath(""):
		_body_node = get_node_or_null(body_node_path) as Node3D
		if not _body_node:
			push_warning("Player.gd: body_node_path definido, mas Node3D não encontrado: %s" % body_node_path)

	# cacheia states manager
	if states_node_path and states_node_path != NodePath(""):
		_states_manager = get_node_or_null(states_node_path)
		if not _states_manager:
			push_warning("Player.gd: states_node_path definido, mas Node não encontrado: %s" % states_node_path)
		else:
			if not _states_manager.has_method("update_movement_state"):
				push_warning("Player.gd: states_node não expõe update_movement_state(hspeed). Verifique Player2.gd")
			# ADICIONADO: inicializa override de corrida no States se expõe API
			if _states_manager.has_method("set_is_running"):
				_states_manager.set_is_running(is_running)

	# cacheia camera pivot e tenta encontrar a Camera3D filho
	if camera_pivot_path and camera_pivot_path != NodePath(""):
		_camera_pivot = get_node_or_null(camera_pivot_path)
		if not _camera_pivot:
			push_warning("Player.gd: camera_pivot_path definido mas não encontrado: %s" % camera_pivot_path)
		else:
			_camera_node = _find_camera_in_node(_camera_pivot)
			if not _camera_node:
				push_warning("Player.gd: não encontrei Camera3D dentro do camera_pivot. Movimento relativo à câmera pode ficar incorreto.")

func _find_camera_in_node(node: Node) -> Camera3D:
	for child in node.get_children():
		if child is Camera3D:
			return child
		var found := _find_camera_in_node(child)
		if found:
			return found
	return null

# ADICIONADO: toggle de corrida tratado no _process para captar Input.is_action_just_pressed robustamente
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		is_running = not is_running
		if _states_manager and _states_manager.has_method("set_is_running"):
			_states_manager.set_is_running(is_running)
		# força atualizar o state imediatamente (aplica runner se for o caso)
		if _states_manager and _states_manager.has_method("update_movement_state"):
			var hspeed_now: float = Vector2(velocity.x, velocity.z).length()
			_states_manager.update_movement_state(hspeed_now)

func _physics_process(delta: float) -> void:
	# Gravidade
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Entrada de movimento
	input_dir = Input.get_vector("left", "right", "up", "down")

	# velocidade máxima atual (aplica multiplicador se is_running)
	var max_speed: float = speed
	if is_running:
		max_speed = speed * run_multiplier

	# direção relativa à câmera (usa Camera3D quando possível; ignora pitch)
	var forward_mul: float = 1.0
	# ADICIONADO: ajustar sinal de forward se invert_forward_input estiver ativo
	if invert_forward_input:
		forward_mul = -1.0

	if _camera_node:
		var cam_basis: Basis = _camera_node.global_transform.basis
		var cam_forward: Vector3 = -cam_basis.z
		cam_forward.y = 0.0
		if cam_forward.length_squared() > 0.000001:
			cam_forward = cam_forward.normalized()
		else:
			cam_forward = Vector3.FORWARD
		var cam_right: Vector3 = cam_basis.x
		cam_right.y = 0.0
		if cam_right.length_squared() > 0.000001:
			cam_right = cam_right.normalized()
		else:
			cam_right = Vector3.RIGHT
		# ADICIONADO: aplica forward_mul para corrigir o mapeamento up/down se necessário
		var raw_dir: Vector3 = cam_forward * (input_dir.y * forward_mul) + cam_right * input_dir.x
		if raw_dir.length_squared() > 0.0001:
			direction = raw_dir.normalized()
		else:
			direction = Vector3.ZERO
	elif _camera_pivot:
		var pbasis: Basis = _camera_pivot.global_transform.basis
		var pfwd: Vector3 = -pbasis.z
		pfwd.y = 0.0
		if pfwd.length_squared() > 0.000001:
			pfwd = pfwd.normalized()
		else:
			pfwd = Vector3.FORWARD
		var pright: Vector3 = pbasis.x
		pright.y = 0.0
		if pright.length_squared() > 0.000001:
			pright = pright.normalized()
		else:
			pright = Vector3.RIGHT
		var raw_dir2: Vector3 = pfwd * (input_dir.y * forward_mul) + pright * input_dir.x
		if raw_dir2.length_squared() > 0.0001:
			direction = raw_dir2.normalized()
		else:
			direction = Vector3.ZERO
	else:
		# fallback final: player-local input (aplica forward_mul também)
		direction = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y * forward_mul)).normalized()

	# Movimento no plano XZ
	if direction != Vector3.ZERO:
		velocity.x = lerp(velocity.x, direction.x * max_speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * max_speed, acceleration * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, deceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, deceleration * delta)

	# Mover e tratar colisões
	move_and_slide()

	# RESTAURADO: envio de posição ao servidor (mesma lógica)
	_update_network_position(delta)

	# Rotacionar o corpo visual (suave) para direção do movimento
	if _body_node and direction != Vector3.ZERO:
		var target_angle: float
		if face_negative_z:
			target_angle = atan2(-direction.x, -direction.z)
		else:
			target_angle = atan2(direction.x, direction.z)

		var current_rot: Vector3 = _body_node.rotation
		var current_y: float = current_rot.y
		var interp_factor: float = clamp(body_rotation_speed * delta, 0.0, 1.0)
		var new_y: float = lerp_angle(current_y, target_angle, interp_factor)
		current_rot.y = new_y
		_body_node.rotation = current_rot

	# Atualiza States com a velocidade horizontal
	if _states_manager and _states_manager.has_method("update_movement_state"):
		var hspeed: float = Vector2(velocity.x, velocity.z).length()
		_states_manager.update_movement_state(hspeed)

func _update_network_position(delta: float) -> void:
	send_timer += delta
	if send_timer >= send_interval:
		send_timer = 0.0
		if position.distance_to(last_sent_pos) > 0.01:
			if Engine.has_singleton("Client"):
				Client.send("update_position", {
					"uuid": Client.uuid,
					"x": position.x,
					"y": position.y,
					"z": position.z
				})
			last_sent_pos = position
