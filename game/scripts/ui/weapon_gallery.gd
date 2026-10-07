extends "res://scripts/ui/game_renderer.gd"
## Native viewport review of the same equipped-actor drawing code used in combat.
var page = 0
var direction = "down"
var pose_state = "cast"
var pose_time = .17
const ACTORS = ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]

func _ready() -> void:
	super._ready()
	stage = Transform2D(Vector2(1, 0), Vector2(0, .84722), Vector2.ZERO)

func _process(_delta: float) -> void: queue_redraw()

func _draw() -> void:
	for row in 6:
		for column in 6:
			var actor = ACTORS[column]
			var id = "w%02d" % (page * 6 + row + 1)
			var aim = {"down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP}[direction]
			var motion = {"weapon": id, "state": pose_state, "elapsed": pose_time, "aim": aim, "angle": .1, "scale": 1, "held_visible": true}
			var body = animation.texture(actor, "weapon_body", pose_state, pose_time, direction)
			if body != null: draw_equipped_actor(actor, Vector2(174 + column * 190, (166 + row * 89) / .84722), direction, motion, body)
