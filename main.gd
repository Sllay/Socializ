#main.gd
extends Node
# Main Entrypoint of program

@export var map: PackedScene = null

@onready var lobby = $Lobby
@onready var transition = $Transition


# Called when the node enters the scene tree for the first time.
func _ready():
	Client.connect("joined_server", Callable(self, "_on_joined_server"))
	
	
func _on_joined_server() -> void:
	add_child(map.instantiate())
	lobby.hide()
	transition.get_node("AnimationPlayer").play("transit")
	transition.show()
	await get_tree().create_timer(2.0).timeout
	transition.hide()
	transition.get_node("AnimationPlayer").stop()
	
