extends SceneTree
func _initialize():
	var path = ProjectSettings.globalize_path("res://../.local-tools/combat-revision-verify/android_room_geometry.gdc")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--android-script="): path=argument.trim_prefix("--android-script=")
	var windows = load("res://scripts/combat/room_geometry.gd").new()
	var android = load(path).new()
	var same = FileAccess.get_sha256("res://scripts/combat/room_geometry.gdc")==FileAccess.get_sha256(path)
	var results: Array = []
	var corridor_results: Array = []
	for geometry in [windows,android]:
		geometry.blocks=[Rect2(400,300,32,32)]
		results.append(geometry.has_method("navigation_waypoint") and geometry.clear_swept_segment(Vector2(389,289),Vector2(381,281),12) and not geometry.clear_swept_segment(Vector2(381,281),Vector2(405,305),12) and not geometry.contains_floor(Vector2(640,360),5000))
		geometry.bounds=Rect2(225,115.6724,841,509.903)
		geometry.floor_polygon=PackedVector2Array([Vector2(295,115.6724),Vector2(996,115.6724),Vector2(1066,198.2956),Vector2(1066,542.9523),Vector2(996,625.5754),Vector2(295,625.5754),Vector2(225,542.9523),Vector2(225,198.2956)])
		geometry.blocks=[Rect2(256,200,64,64),Rect2(256,264,64,64)]
		var start=Vector2(243.185,197.5189)
		var waypoint=geometry.navigation_waypoint(start,Vector2(1043.999,360),12)
		corridor_results.append(start.distance_to(waypoint)>8 and geometry.clear_swept_segment(start,waypoint,12))
	var report={"passed":same and results.all(func(result): return result) and corridor_results.all(func(result): return result),"identical_compiled_geometry":same,"windows_and_android_actual_rounded_sweep_checks":results,"adaptive_thin_corridor_checks":corridor_results,"windows_geometry_sha256":FileAccess.get_sha256("res://scripts/combat/room_geometry.gdc"),"scope":"Windows embedded PCK and Android compiled geometry executed on the desktop engine; this is not an Android device test"}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--windows-artifact="): report.windows_artifact_sha256=FileAccess.get_sha256(argument.trim_prefix("--windows-artifact="))
		if argument.begins_with("--android-artifact="): report.android_artifact_sha256=FileAccess.get_sha256(argument.trim_prefix("--android-artifact="))
	print(JSON.stringify(report))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--compiled-scripts="):
			var scripts = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--compiled-scripts=")))
			var mismatches: Array = []
			for row in scripts:
				if FileAccess.get_sha256(row.file) != row.android_sha256: mismatches.append(row.file)
			report.compiled_script_count = scripts.size()
			report.compiled_script_mismatches = mismatches
			report.passed = report.passed and not scripts.is_empty() and mismatches.is_empty()
			print("Compiled-script parity: ", scripts.size(), " checked; mismatches ", mismatches)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): FileAccess.open(argument.trim_prefix("--report="),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0 if report.passed else 1)
