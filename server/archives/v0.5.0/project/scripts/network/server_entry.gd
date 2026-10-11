extends SceneTree
const Runtime = preload("res://scripts/network/server_runtime.gd")
var server

static func options_from_arguments() -> Dictionary:
	var options: Dictionary = {"bind": "0.0.0.0", "data_directory": "user://online-server"}
	var overrides: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="): continue
		var parts = argument.trim_prefix("--").split("=", true, 1)
		overrides[parts[0].replace("-", "_")] = parts[1]
	if overrides.has("config"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(str(overrides.config)))
		if not parsed is Dictionary: return {"invalid_config": true}
		options.merge(parsed, true)
	options.merge(overrides, true)
	if options.has("data_dir"): options.data_directory = options.data_dir
	return options

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	server = Runtime.new()
	root.add_child.call_deferred(server)
	_start.call_deferred(options_from_arguments())

func _start(options: Dictionary) -> void:
	if options.get("invalid_config", false): push_error("ONLINE_START_FAILED invalid_config"); quit(1); return
	var error = server.start(options)
	if error != OK:
		push_error("ONLINE_START_FAILED error=" + str(error))
		quit(1)
