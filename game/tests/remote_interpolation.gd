extends SceneTree
const Interpolation = preload("res://scripts/network/remote_interpolation.gd")
var checks: Array = []
func check(name: String, passed: bool) -> void:
	checks.append(passed); print("INTERPOLATION_", "PASS " if passed else "FAIL ", name)
func _initialize() -> void:
	var buffer = Interpolation.new()
	buffer.observe_clock(1.0, 1.0)
	buffer.observe("scene/enemies", [{"uid": 1, "pos": Vector2(100, 200)}], .9, 1)
	buffer.observe("scene/enemies", [{"uid": 1, "pos": Vector2(200, 200)}], 1.0, 2)
	check("intermediate_remote_position", buffer.sample("scene/enemies")[0].pos.is_equal_approx(Vector2(150, 200)))
	buffer.observe("scene/enemies", [{"uid": 1, "pos": Vector2(0, 200)}], .8, 1)
	check("old_sample_does_not_rewind", buffer.sample("scene/enemies")[0].pos.is_equal_approx(Vector2(150, 200)))
	buffer.current["scene/enemies"] = []
	buffer.observe("scene/enemies", [], 1.1, 3)
	check("dead_entities_are_removed", buffer.sample("scene/enemies").is_empty())
	buffer.observe("scene/bullets", [{"uid": 2, "pos": Vector2.ZERO, "dir": Vector2.RIGHT, "speed": 100}], 1.0, 2)
	buffer.clock = 2.0
	check("extrapolation_is_bounded", buffer.sample("scene/bullets")[0].pos.x <= 10.001)
	var clock = buffer.clock
	buffer.advance(.5, false)
	check("pause_freezes_clock", buffer.clock == clock)
	buffer.clear()
	check("scene_change_discards_history", buffer.sample("scene/bullets").is_empty())
	quit(0 if checks.all(func(passed): return passed) else 1)
