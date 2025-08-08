extends CharacterBody3D

# Interpolação simples de posição recebida pela rede
var _target_position: Vector3 = Vector3.ZERO
var _interp_speed: float = 8.0

func _ready() -> void:
	print("network_player ready()")

func _process(delta: float) -> void:
	# interpola suavemente a posição visual para a target
	if global_transform.origin.distance_to(_target_position) > 0.01:
		var new_pos = global_transform.origin.lerp(_target_position, clamp(_interp_speed * delta, 0, 1))
		global_transform.origin = new_pos

# chamada externa para atualizar posição quando o mapa receber update_position
func set_target_position(p: Vector3) -> void:
	_target_position = p
