# Player2.gd
# CHANGES: ALTERADO update_movement_state para que runner só ative quando _is_running_override == true;
#          ADICIONADO runner_speed_scale e walk_speed_scale e aplicação direta de speed_scale.
extends Node3D

@export var animation_player_node: NodePath = NodePath("AnimationPlayer")
@export var crossfade_time: float = 0.15

# thresholds apenas para diferenciar idle <-> walk quando não estiver em override de corrida
@export var walk_threshold: float = 0.1

# ADICIONADO: escalas de velocidade das animações
@export var walk_speed_scale: float = 1.0
@export var runner_speed_scale: float = 2.0

# desabilitei a lógica de escolher runner por velocidade — runner vem do boolean _is_running_override
@export var speed_blend_enabled: bool = false
@export var max_anim_speed_scale: float = 1.6

var _anim: AnimationPlayer = null
var _state_map: Dictionary = {}
var _current_state: String = ""
var _last_speed: float = 0.0
var _is_running_override: bool = false  # ADICIONADO: override vindo do Player

const STANDARD_STATES := ["idle", "walk", "runner", "sleep", "sitting"]

func _ready() -> void:
	_anim = get_node_or_null(animation_player_node) as AnimationPlayer
	if not _anim:
		push_error("Player2.gd: AnimationPlayer não encontrado em: %s" % animation_player_node)
		return
	_build_state_map()
	if _state_map.has("idle"):
		play_state("idle", 0.0)

func _build_state_map() -> void:
	_state_map.clear()
	var anims: Array = _anim.get_animation_list()
	for name in anims:
		if name is String and name.begins_with("State/"):
			var parts: Array = name.split("/")
			if parts.size() >= 2:
				var key: String = parts[1].to_lower()
				_state_map[key] = name
	for s in STANDARD_STATES:
		if not _state_map.has(s):
			push_warning("Player2.gd: animação State/%s não encontrada no AnimationPlayer." % s)

func play_state(state_name: String, blend: float = -1.0) -> void:
	if not _anim:
		return
	var key: String = state_name.to_lower()
	if not _state_map.has(key):
		push_warning("Player2.gd: play_state: state '%s' não mapeado." % state_name)
		return
	var anim_name: String = _state_map[key]
	var use_blend: float = crossfade_time if blend < 0.0 else blend
	_anim.play(anim_name, use_blend)
	_anim.advance(0.0)
	_current_state = key

# ALTERADO: agora runner só é escolhido quando _is_running_override == true.
# Se _is_running_override == false -> somente idle/walk são possíveis.
func update_movement_state(hspeed: float) -> void:
	_last_speed = hspeed
	var target_state: String = "idle"

	if _is_running_override:
		# se corrida for forçada, usar runner quando houver movimento
		if hspeed > 0.01:
			target_state = "runner"
		else:
			target_state = "idle"
	else:
		# sem override de corrida => somente idle ou walk
		if hspeed < walk_threshold:
			target_state = "idle"
		else:
			target_state = "walk"

	# só trocar de animação se diferente
	if target_state != _current_state:
		play_state(target_state)

	# aplicar speed_scale conforme o state (runner controlado pela boolean)
	if not _anim:
		return

	if target_state == "runner":
		_anim.speed_scale = runner_speed_scale
		_anim.advance(0.0)
	elif target_state == "walk":
		_anim.speed_scale = walk_speed_scale
		_anim.advance(0.0)
	else:
		_anim.speed_scale = 1.0
		_anim.advance(0.0)

# ADICIONADO: permite que Player force runner via chamada
func set_is_running(on: bool) -> void:
	_is_running_override = on
	# atualiza imediatamente o estado para refletir a override
	if _anim and _state_map.size() > 0:
		# forçar recalcular com a velocidade atual
		update_movement_state(_last_speed)

# ADICIONADO: API pública para setar anim speed diretamente
func set_anim_speed(scale: float) -> void:
	if not _anim:
		return
	_anim.speed_scale = scale
	_anim.advance(0.0)

func force_idle() -> void:
	play_state("idle")

func play_emote(emote_name: String, blend: float = -1.0) -> void:
	if not _anim:
		return
	var search_name: String = "Emote/" + emote_name
	if _anim.has_animation(search_name):
		var use_blend: float = crossfade_time if blend < 0.0 else blend
		_anim.play(search_name, use_blend)
		_anim.advance(0.0)
	else:
		push_warning("Player2.gd: emote '%s' não encontrado como %s" % [emote_name, search_name])
