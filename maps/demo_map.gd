extends Node3D
# Map should probably not contain network spawn code, but this is a prototype

var local_player = load("res://players/player.tscn")
var network_player = load("res://players/network_player.tscn")

@onready var player_list = $PlayerList


func _ready() -> void:
	Client.connect("spawn_local_player", Callable(self, "_on_spawn_local_player"))
	Client.connect("spawn_new_player", Callable(self, "_on_spawn_new_player"))
	Client.connect("spawn_network_players", Callable(self, "_on_spawn_network_players"))
	Client.connect("update_position", Callable(self, "_on_update_position"))
	Client.connect("player_disconnected", Callable(self, "_on_player_disconnected"))


func _on_spawn_local_player(player: Dictionary) -> void:
	var lp: CharacterBody3D = local_player.instantiate()
	var id = str(player.get("uuid", "sem_uuid"))
	lp.name = id
	lp.global_transform.origin = Vector3(
		float(player.get("x", 0.0)),
		float(player.get("y", 10.0)),
		float(player.get("z", 0.0))
	)
	player_list.add_child(lp)


func _on_spawn_new_player(player: Dictionary) -> void:
	_spawn_network_player(player)


func _on_spawn_network_players(players: Array) -> void:
	for p in players:
		if str(p.get("uuid", "")) != str(Client.uuid):
			_spawn_network_player(p)


func _spawn_network_player(player: Dictionary) -> void:
	var np: CharacterBody3D = network_player.instantiate()
	var id = str(player.get("uuid", "sem_uuid"))
	np.name = id
	np.global_transform.origin = Vector3(
		float(player.get("x", 0.0)),
		float(player.get("y", 10.0)),
		float(player.get("z", 0.0))
	)
	player_list.add_child(np)


func _on_update_position(content: Dictionary) -> void:
	var uuid = str(content.get("uuid", ""))
	for player in player_list.get_children():
		if player.name == uuid:
			# se o player tem set_target_position, usa interpolação; senão set direto
			var x = float(content.get("x", player.global_transform.origin.x))
			var y = float(content.get("y", player.global_transform.origin.y))
			var z = float(content.get("z", player.global_transform.origin.z))
			var target = Vector3(x, y, z)
			if player.has_method("set_target_position"):
				player.call("set_target_position", target)
			else:
				player.global_transform.origin = target


func _on_player_disconnected(content: Dictionary) -> void:
	var uuid = str(content.get("uuid", ""))
	for player in player_list.get_children():
		if player.name == uuid:
			player.queue_free()
			print("👋 Jogador saiu:", uuid)
