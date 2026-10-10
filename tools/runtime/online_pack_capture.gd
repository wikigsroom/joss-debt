extends SceneTree
## The editor runner opens the accepted EXE's pack. Game scripts stay compiled;
## only this capture driver lives outside the pack and uses isolated QA saves.

func _initialize() -> void:
	call_deferred("boot")

func boot() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var removed = 0
	for child in app.get_children():
		var script = child.get_script()
		if script != null and str(script.resource_path).contains("online_native_qa"):
			child.free()
			removed += 1
	if removed != 1:
		push_error("Expected exactly one deferred compiled QA driver")
		quit(1)
		return
	var source = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-driver="): source = argument.trim_prefix("--capture-driver=")
	var fixture = load(source).new()
	fixture.app = app
	fixture.directory = app.qa_directory
	app.add_child(fixture)
