extends SceneTree
## Mount the published executable before parsing the capture harness.
## Startup display settings come from an isolated capture-only project.
func _initialize() -> void:
	var artifact = ""
	var harness = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--artifact="): artifact = argument.trim_prefix("--artifact=")
		if argument.begins_with("--harness="): harness = argument.trim_prefix("--harness=")
	if artifact.is_empty() or harness.is_empty() or not ProjectSettings.load_resource_pack(artifact):
		push_error("Published capture pack could not be mounted")
		quit(1)
		return
	var capture_script = load(harness)
	if capture_script == null:
		quit(1)
		return
	set_script(capture_script)
	call("_initialize")
