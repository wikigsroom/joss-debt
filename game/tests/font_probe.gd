extends SceneTree

func _initialize() -> void:
	var file = load("res://assets/fonts/NotoSansSC.ttf")
	print("Axes: ", file.get_supported_variation_list())
	var server = TextServerManager.get_primary_interface()
	for coordinate in [100, 500, 700]:
		var font = FontVariation.new()
		font.base_font = file
		font.variation_opentype = {server.name_to_tag("wght"): coordinate}
		print("Weight ", coordinate, " / tag ", server.name_to_tag("wght"), " / RID coordinates ", server.font_get_variation_coordinates(font.get_rids()[0]))
	quit()
