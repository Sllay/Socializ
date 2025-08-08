extends CharacterBody3D

# Configurações
@export var speed := 5.0              # Velocidade máxima
@export var acceleration := 8.0       # Aceleração
@export var deceleration := 12.0      # Desaceleração
@export var gravity := 9.8            # Gravidade

# Controle interno
var direction := Vector3.ZERO
var input_dir := Vector2.ZERO

# Controle de rede (apenas se usar multiplayer)
var last_sent_pos := Vector3.ZERO
var send_interval := 0.1
var send_timer := 0.0

func _physics_process(delta):
	# Gravidade
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Entrada de movimento (usa actions personalizadas)
	input_dir = Input.get_vector("left", "right", "up", "down")
	direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Movimento no plano XZ
	if direction != Vector3.ZERO:
		velocity.x = lerp(velocity.x, direction.x * speed, acceleration * delta)
		velocity.z = lerp(velocity.z, direction.z * speed, acceleration * delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, deceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, deceleration * delta)

	# Mover e tratar colisões
	move_and_slide()

	# Enviar posição para o servidor (somente se mudou)
	_update_network_position(delta)

func _update_network_position(delta):
	send_timer += delta
	if send_timer >= send_interval:
		send_timer = 0.0
		if position.distance_to(last_sent_pos) > 0.01: # só envia se mudou
			if Engine.has_singleton("Client"): # evita erro se não existir
				Client.send("update_position", {
					"uuid": Client.uuid,
					"x": position.x,
					"y": position.y,
					"z": position.z
				})
			last_sent_pos = position
