extends SceneTree

func _initialize() -> void:
	for name in ["AudioStreamSynchronized", "AudioStreamPlaybackSynchronized", "AudioStreamOggVorbis", "AudioEffectRecord"]:
		var methods: Array = []
		for method in ClassDB.class_get_method_list(name, true):
			if "sync" in method.name or "record" in method.name or "length" in method.name or "parameter" in method.name: methods.append(method.name)
		print(name, ": ", methods)
	print("Synchronized properties: ", ClassDB.class_get_property_list("AudioStreamSynchronized", true).map(func(p): return p.name))
	print("Ogg packet properties: ", ClassDB.class_get_property_list("OggPacketSequence", true).map(func(p): return p.name))
	quit()
