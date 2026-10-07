extends TextureRect
const Motion = preload("res://scripts/ui/paper_animation.gd")
var animation = Motion.new()
var npc_id = "n01"
var speaking = false
var clock = 0.0

func _process(delta: float) -> void:
	clock += delta
	texture = animation.texture(npc_id, "npc", "talk" if speaking else "idle", clock)
