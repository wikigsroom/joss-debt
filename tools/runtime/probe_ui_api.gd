extends SceneTree
func _initialize() -> void:
	for type in ["Control", "Button", "Theme"]:
		var names = []
		for property in ClassDB.class_get_property_list(type):
			if "accessibility" in property.name or "icon" in property.name: names.append(property.name)
		print(type, ": ", names)
	quit()
