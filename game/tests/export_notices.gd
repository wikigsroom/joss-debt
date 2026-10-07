extends SceneTree

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/licenses"))
	var notices = "Godot Engine\n\n" + Engine.get_license_text() + "\n\nBundled third-party components\n"
	for item in Engine.get_copyright_info():
		notices += "\n" + item.name + "\n"
		for part in item.parts:
			notices += "\n".join(part.copyright) + "\nLicense: " + part.license + "\n"
	var licenses = Engine.get_license_info()
	for id in licenses: notices += "\n\n" + id + "\n\n" + licenses[id]
	var file = FileAccess.open("res://assets/licenses/Godot-THIRDPARTY.txt", FileAccess.WRITE)
	file.store_string(notices)
	file.close()
	print("Saved native Godot and bundled component notices.")
	quit()
