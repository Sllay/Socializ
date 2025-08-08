extends Node

# ==== SINAIS ====
signal joined_server
signal spawn_local_player
signal spawn_new_player
signal spawn_network_players
signal update_position
signal new_chat_message
signal player_disconnected

# ==== VARIÁVEIS ====
var uuid: String = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
var _peer := WebSocketPeer.new()
var _connected := false

# ==== PROCESSO PRINCIPAL ====
func _process(_delta):
	if _connected:
		_peer.poll()

		while _peer.get_available_packet_count() > 0:
			var data = _peer.get_packet().get_string_from_utf8()
			var parsed_data = JSON.parse_string(data)  # Godot 4 já retorna dicionário ou null

			if typeof(parsed_data) == TYPE_DICTIONARY:
				_handle_incoming_data(parsed_data)
			else:
				push_error("JSON inválido ou não é dicionário: %s" % str(parsed_data))

# ==== CONEXÃO COM SERVIDOR ====
func connect_to_server():
	print("Tentando conectar...")
	var err = _peer.connect_to_url("wss://servidorsocializ.onrender.com/")  # seu servidor
	if err != OK:
		push_error("Erro ao conectar: %s" % err)
	else:
		_connected = true
		print("Conectando...")

# ==== ENVIAR MENSAGEM PARA SERVIDOR ====
func send(cmd: String, content: Dictionary):
	var json = JSON.stringify({ "cmd": cmd, "content": content })
	_peer.send_text(json)

# ==== RECEBENDO DADOS ====
func _handle_incoming_data(data: Dictionary):
	match data.get("cmd", ""):
		"joined_server":
			uuid = str(data.get("content", {}).get("uuid", uuid))
			emit_signal("joined_server")

		"spawn_local_player":
			emit_signal("spawn_local_player", data.get("content", {}).get("player", {}))

		"spawn_new_player":
			emit_signal("spawn_new_player", data.get("content", {}).get("player", {}))

		"spawn_network_players":
			emit_signal("spawn_network_players", data.get("content", {}).get("players", []))

		"update_position":
			emit_signal("update_position", data.get("content", {}))

		"new_chat_message":
			emit_signal("new_chat_message", data.get("content", {}))

		"player_disconnected":
			emit_signal("player_disconnected", data.get("content", {}))

		_:
			push_error("Comando não reconhecido: %s" % str(data))
