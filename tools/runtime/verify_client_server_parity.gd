extends SceneTree
## Compare bytecode from the actual exported server and client packs.

func _initialize() -> void:
	var client = ""
	var manifest = ""
	var output = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--client="): client = arg.trim_prefix("--client=")
		if arg.begins_with("--manifest="): manifest = arg.trim_prefix("--manifest=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(manifest))
	var expected: Dictionary = {}
	for path in metadata.shared_source_sha256:
		if str(path).ends_with(".gd"):
			var compiled = "res://" + str(path).trim_suffix(".gd") + ".gdc"
			expected[compiled] = FileAccess.get_sha256(compiled) if FileAccess.file_exists(compiled) else ""
	var loaded = ProjectSettings.load_resource_pack(client, true)
	var checks: Array = []
	for path in expected:
		checks.append({"id": str(path).trim_prefix("res://"), "passed": loaded and not str(expected[path]).is_empty() and FileAccess.file_exists(path) and FileAccess.get_sha256(path) == expected[path]})
	var report = {"passed": loaded and not checks.is_empty() and checks.all(func(row): return row.passed), "checks": checks, "compiled_shared_modules": checks.size()}
	var file = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("CLIENT_SERVER_BYTECODE checks=%d passed=%s" % [checks.size(), report.passed])
	quit(0 if report.passed else 1)
