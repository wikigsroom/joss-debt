extends SceneTree

const Adapter = preload("res://scripts/ui/input_adapter.gd")
const Orientation = preload("res://scripts/ui/orientation_guard.gd")
const Haptics = preload("res://scripts/ui/haptic_feedback.gd")
const RuntimeQuality = preload("res://scripts/ui/runtime_quality.gd")
const World = preload("res://scripts/combat/world.gd")

var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, description: String) -> void:
	checks.append(description)
	if not condition:
		failures.append(description)
		push_error(description)

func read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func run_suite() -> void:
	var rules = read_json("res://data/rules.json")
	var platform = rules.get("platforms", {})
	expect(platform.get("orientation", "") == "landscape", "the shared platform contract keeps every target in landscape")
	expect(int(platform.get("pc_target_fps", 0)) == 60 and int(platform.get("mobile_target_fps", 0)) == 60, "desktop and mobile target the same fixed 60fps presentation cadence")
	expect(int(platform.get("mobile_low_fps", 0)) >= 24 and int(platform.get("mobile_low_fps", 0)) < int(platform.get("mobile_target_fps", 0)), "mobile low-performance fallback remains a meaningful 30fps-class budget")
	expect(int(platform.get("mobile_projectile_cap", 0)) >= 120 and int(platform.get("mobile_projectile_cap", 0)) <= 240, "mobile projectile cap stays within the authored safe range")
	expect(int(platform.get("pc_projectile_cap", 0)) >= int(platform.get("mobile_projectile_cap", 0)), "desktop projectile budget never falls below the mobile contract")
	expect(int(platform.get("mobile_vfx_particle_cap", 0)) >= 80 and int(platform.get("pc_vfx_particle_cap", 0)) >= int(platform.get("mobile_vfx_particle_cap", 0)), "VFX particle budgets are ordered for mobile and desktop")
	expect(int(platform.get("texture_memory_mb_budget", 0)) == 128 and int(platform.get("working_set_mb_budget", 0)) == 350, "texture and working-set budgets remain explicit instead of relying on a device guess")
	expect(int(platform.get("package_mb_budget", 0)) >= 180 and int(platform.get("target_touch_size", 0)) >= 56, "package and touch targets keep the documented release floor")
	expect(bool(platform.get("mobile_quality_auto", false)) and float(platform.get("mobile_quality_low_particle_scale", 1.0)) <= .6 and int(platform.get("mobile_quality_low_effect_cap", 120)) <= 80, "mobile quality fallback is explicit and presentation-only")
	var quality = RuntimeQuality.new()
	quality.set_mode("auto", true)
	for i in 96: quality.sample(1.0 / 30.0)
	var low_profile = quality.status()
	expect(low_profile.particle_scale < 1.0 and low_profile.effect_limit <= 120 and low_profile.profile == "auto-low", "sustained mobile frame pressure reaches the bounded low-cost presentation profile")
	for i in 420: quality.sample(1.0 / 60.0)
	expect(quality.particle_scale > low_profile.particle_scale and quality.status().profile == "auto-recovered", "stable mobile cadence gradually recovers the full presentation profile")
	quality.set_mode("battery", true)
	expect(quality.status().target_effect_limit == 72 and quality.status().target_particle_scale == .55, "the explicit battery profile is deterministic")
	quality.set_mode("high", true)
	expect(quality.status().target_effect_limit == 120 and quality.status().target_particle_scale == 1.0, "the explicit high-quality profile restores the authored presentation budget")

	var adapter = Adapter.new()
	adapter.minimum_action_radius = float(platform.get("target_touch_size", 56)) * .5
	for safe in [Rect2(0, 0, 1280, 720), Rect2(42, 8, 1196, 704), Rect2(80, 0, 1120, 720)]:
		adapter.safe_rect = safe
		for action in ["move", "aim", "dash", "skill"]:
			var center = adapter.control_center(action)
			var margin = adapter.control_radius(action) + 4
			expect(safe.grow(-margin).has_point(center), "" + action + " remains inside a notched safe area")
	expect(adapter.control_radius("move") >= 72 and adapter.control_radius("dash") >= 46, "touch controls preserve readable minimum radii")
	var before = adapter.layout.duplicate(true)
	var overlap_point = (adapter.control_center("aim") - adapter.safe_rect.position) / adapter.safe_rect.size
	expect(adapter.move_control("dash", overlap_point) == false and adapter.layout == before, "touch layout rejects a dangerous overlap instead of saving it")

	var orientation = Orientation.new()
	expect(orientation.observe(Vector2i(2400, 1080)).is_empty() and not orientation.blocked, "wide phone landscape does not show the rotation guard")
	expect(orientation.observe(Vector2i(1080, 2400)) == "blocked" and orientation.blocked, "portrait phone pauses through the same shared orientation guard")
	expect(orientation.observe(Vector2i(1100, 1000)).is_empty() and orientation.blocked, "foldable or split-window jitter cannot dismiss the guard")
	expect(orientation.observe(Vector2i(2400, 1080)) == "restored" and not orientation.blocked, "landscape restoration requires an explicit resume transition")

	var haptics = Haptics.new()
	var pulse = haptics.select([{"kind": "dash"}, {"kind": "player_hurt"}], 1.0)
	expect(pulse.ms == 65 and pulse.priority == 3 and pulse.ms <= 65, "haptic feedback is bounded and chooses the highest-priority event")
	haptics.stop()
	expect(haptics.select([{"kind": "player_hurt"}], 1.05).priority == 3, "clearing a lifecycle pause permits a fresh haptic request")

	var world = World.new()
	world.start("c_paper", 20261006)
	world.mode = "combat"
	world.enemies.clear()
	world.player.pos = Vector2(640, 360)
	world.player.aim = Vector2.RIGHT
	for i in 300:
		world.shoot_input(true, 0.0)
	expect(world.bullets.size() <= int(platform.get("pc_projectile_cap", 240)), "the shared world never exceeds the authored projectile cap")
	world.take_events()

	var runtime_manifest = read_json("res://data/runtime_assets.json")
	expect(runtime_manifest.get("assets", []).size() >= 675, "the runtime registry contains the complete verified asset set")
	expect(FileAccess.file_exists("res://assets/fonts/IncenseRounded-Medium.ttf") and FileAccess.file_exists("res://assets/fonts/SmileySans-Oblique.ttf"), "the rounded body and display fonts are packaged with the shared project")

	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "shared platform budgets, safe-area touch geometry, orientation lifecycle, bounded haptics, projectile cap and packaged font/resource contracts; no physical device claim"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/platform-contract-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Platform contract: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
