extends SceneTree
const Migration = preload("res://scripts/core/save_migrations.gd")
const Profile = preload("res://scripts/core/meta_progress.gd")
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
class Capture extends RefCounted:
	var captured: Dictionary = {}
	func write(value: Dictionary) -> bool:
		captured = value.duplicate(true)
		return true
func _initialize() -> void:
	var result = Migration.profile({})
	print("Default migration: ", result.get("ok"), " ", result.get("message", ""))
	var profile = Profile.new("user://save_probe_%d" % Time.get_ticks_usec())
	print("Account read only: ", profile.read_only, " reason: ", profile.recovery_message)
	print("Account write: ", profile.save())
	var journal = profile.store
	var capture = Capture.new()
	profile.store = capture
	var world = World.new()
	world.start("c_paper", 8141, 3)
	world.run.id = "meta-1"
	world.stats.max_chain = 3
	world.run.bosses_defeated = ["b01"]
	print("Observed: ", profile.observe(world))
	print("Valid memory: ", Store.valid_tree(capture.captured, 0, [200000]))
	print("Valid encoded: ", Store.valid_tree(Store.encode(capture.captured), 0, [200000]))
	print("Journal read status: ", journal.read_status, " write: ", journal.write(capture.captured), " after: ", journal.read_status)
	quit()
