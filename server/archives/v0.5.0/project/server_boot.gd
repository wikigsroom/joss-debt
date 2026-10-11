extends Node
const Runtime = preload("res://scripts/network/server_runtime.gd")
const Entry = preload("res://scripts/network/server_entry.gd")

func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	var server = Runtime.new()
	add_child(server)
	var options = Entry.options_from_arguments()
	if options.get("invalid_config", false): push_error("ONLINE_START_FAILED invalid_config"); get_tree().quit(1); return
	var error = server.start(options)
	if error != OK:
		push_error("ONLINE_START_FAILED error=" + str(error))
		get_tree().quit(1)
