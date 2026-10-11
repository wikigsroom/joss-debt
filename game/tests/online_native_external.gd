extends SceneTree
## Drive the actual exported client with an external acceptance fixture.
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var fixture_path = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--external-fixture="): fixture_path = argument.trim_prefix("--external-fixture=")
	if fixture_path.is_empty():
		push_error("Missing native acceptance fixture")
		quit(1)
		return
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var fixture = load(fixture_path).new()
	fixture.app = app
	fixture.directory = app.qa_directory
	app.add_child(fixture)
