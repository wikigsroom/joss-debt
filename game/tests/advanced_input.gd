extends SceneTree
const Adapter = preload("res://scripts/ui/input_adapter.gd")
const Assist = preload("res://scripts/ui/aim_assist.gd")
const Haptics = preload("res://scripts/ui/haptic_feedback.gd")
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Orientation = preload("res://scripts/ui/orientation_guard.gd")
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func key(code: int, pressed: bool = true) -> InputEventKey:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event

func touch(a, index: int, point: Vector2) -> void:
	var event = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = true
	a.event(event)

func run_suite() -> void:
	var adapter = Adapter.new()
	var profile = adapter.profile
	expect(profile.assign("keyboard", "fire", {"type": "key", "code": KEY_E}), "an occupied keyboard binding can be assigned")
	expect(profile.hint("fire") == "E" and profile.bindings.keyboard.interact.type == "mouse", "conflict swaps the old binding instead of erasing either action")
	expect(profile.event_matches("fire", key(KEY_E)) and not profile.event_matches("interact", key(KEY_E)), "one remapped press has one logical owner")
	expect(profile.assign("keyboard", "fire", {"type": "key", "code": KEY_Q}) and not profile.event_matches("skill", key(KEY_Q)), "a primary remap suppresses a conflicting optional shortcut")
	expect(not profile.assign("keyboard", "fire", {"type": "axis", "code": 0, "sign": 1}), "keyboard remapping rejects a controller axis")
	expect(profile.assign("keyboard", "dash", {"type": "key", "code": KEY_SHIFT}) and profile.event_matches("dash", key(KEY_SHIFT)), "standalone Shift can be used for the dash action")
	var snapshot = profile.bindings.duplicate(true)
	expect(not profile.assign("controller", "fire", {"type": "axis", "code": 9000, "sign": 1}) and snapshot == profile.bindings, "invalid bindings cannot partially modify the profile")
	var wheel = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	expect(not profile.assign("keyboard", "fire", profile.from_event(wheel, "keyboard")), "wheel pulses cannot be mistaken for a held attack button")
	var drift = InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_RIGHT_X
	drift.axis_value = .08
	adapter.event(drift)
	expect(adapter.last_device == "keyboard" and profile.from_event(drift, "controller").is_empty(), "idle controller drift does not take the mouse device or capture a binding")
	drift.axis_value = -.8
	var candidate = profile.from_event(drift, "controller")
	expect(candidate.sign == -1 and profile.assign("controller", "skill", candidate), "negative stick directions can be remapped as a logical action")
	var store = Store.new("user://advanced_input_tests")
	expect(store.write({"settings": {"bindings": profile.bindings, "fixed_sticks": true, "control_opacity": .6}}), "new input settings enter the actual checksum journal")
	var restored = Adapter.new()
	restored.configure(store.read().settings)
	expect(restored.profile.bindings == profile.bindings and restored.fixed_sticks and is_equal_approx(restored.control_opacity, .6), "saved mouse and controller mappings restore through JSON serialization")
	restored.configure({})
	expect(restored.profile.hint("skill") == "右键 / Q" and restored.control_scale == 1, "older profiles receive working defaults for newly added controls")
	restored.profile.load_data({"keyboard": {"up": {"type": "key", "code": KEY_S}}})
	expect(restored.profile.hint("up") == "W", "a duplicated binding set falls back to a usable device profile")
	profile.reset_device("keyboard")
	profile.assign("keyboard", "fire", {"type": "key", "code": KEY_J})
	adapter.clear()
	var press = key(KEY_J)
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	adapter.event(press)
	var w = World.new()
	w.start("c_paper", 6327)
	var frame = adapter.sample(Vector2(640, 100), w.player.pos)
	w.tick(frame)
	expect(frame.fire and w.stats.shots > 0, "a remapped physical key reaches a real weapon shot in the shared world")
	adapter.profile.reset_device("keyboard")
	adapter.clear()
	var arrow = key(KEY_RIGHT)
	Input.parse_input_event(arrow)
	Input.flush_buffered_events()
	adapter.event(arrow)
	frame = adapter.sample(Vector2.ZERO, w.player.pos)
	expect(frame.fire and frame.aim == Vector2.RIGHT and adapter.profile.hint("map") == "Tab", "the four arrow keys form a dedicated keyboard aim-and-fire stick while Tab remains the route map")
	Input.parse_input_event(key(KEY_RIGHT, false))
	Input.flush_buffered_events()
	adapter.clear()
	adapter.profile.assign("keyboard", "fire", {"type": "key", "code": KEY_J})
	adapter.clear()
	expect(not adapter.sample(Vector2.ZERO, Vector2.ZERO).fire, "opening a menu suppresses a held attack until release")
	Input.parse_input_event(key(KEY_J, false))
	Input.flush_buffered_events()
	adapter.sample(Vector2.ZERO, Vector2.ZERO)
	adapter.fire_toggle = true
	press = key(KEY_J)
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	adapter.event(press)
	expect(adapter.sample(Vector2.ZERO, Vector2.ZERO).fire, "toggle attack starts on a fresh remapped press")
	Input.parse_input_event(key(KEY_J, false))
	Input.flush_buffered_events()
	expect(adapter.sample(Vector2.ZERO, Vector2.ZERO).fire, "toggle attack persists after physical release")
	press = key(KEY_J)
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	adapter.event(press)
	expect(not adapter.sample(Vector2.ZERO, Vector2.ZERO).fire, "the second press stops toggle attack")
	Input.parse_input_event(key(KEY_J, false))
	Input.flush_buffered_events()
	adapter.clear()
	expect(not adapter.sample(Vector2.ZERO, Vector2.ZERO).fire, "pause cancels toggle attack rather than resuming it automatically")
	var layout = Adapter.new()
	expect(layout.move_control("skill", Vector2(.86, .55)), "a touch action can be moved to a safe separated position")
	var before = layout.layout.duplicate(true)
	var aim_point = (layout.control_center("aim") - layout.safe_rect.position) / layout.safe_rect.size
	expect(not layout.move_control("dash", aim_point) and before == layout.layout, "overlapping touch capture zones cannot be saved")
	layout.clear()
	touch(layout, 1, Vector2(160, 570))
	touch(layout, 2, Vector2(890, 570))
	touch(layout, 3, layout.skill_center())
	var drag = InputEventScreenDrag.new()
	drag.index = 2
	drag.position = Vector2(960, 570)
	layout.event(drag)
	frame = layout.sample(Vector2.ZERO, Vector2.ZERO)
	expect(frame.fire and frame.skill and layout.aim_id == 2 and layout.move_id == 1, "edited buttons preserve simultaneous movement, aiming and a third-finger skill")
	layout.mirror = true
	layout.safe_rect = Rect2(48, 8, 1184, 680)
	expect(layout.safe_rect.grow(-layout.control_radius("skill")).has_point(layout.skill_center()), "edited mirrored controls remain inside the actual safe area")
	var saved_layout = {"touch_layout": layout.layout, "control_scale": 1.0}
	var duplicate = Adapter.new()
	duplicate.configure(saved_layout)
	expect(duplicate.layout == layout.layout, "custom touch centers survive a profile reload")
	var fixed = Adapter.new()
	fixed.fixed_sticks = true
	touch(fixed, 7, fixed.control_center("move") + Vector2(35, 0))
	expect(fixed.move_touch.x > .45 and fixed.left_origin == fixed.control_center("move"), "a fixed joystick uses its displayed center on the first touch")
	var assist = Assist.new()
	w.geometry.build("room_open_1", 2)
	w.enemies.clear()
	var first = w.spawn_enemy("e01", Vector2(350, 330))
	var origin = Vector2(200, 300)
	var original = Vector2.RIGHT
	var adjusted = assist.apply(original, origin, w.enemies, w.geometry, 1, "light", 300, "room1")
	expect(adjusted.y > 0 and adjusted.angle() < deg_to_rad(15), "light assist gently corrects an in-cone visible target")
	expect(assist.apply(Vector2.UP, origin, w.enemies, w.geometry, 1, "light", 300, "room1") == Vector2.UP, "manual aim outside the cone releases light assistance immediately")
	expect(assist.apply(original, origin, w.enemies, w.geometry, 1, "light", 100, "room1") == original, "assistance cannot extend the authored weapon range")
	w.geometry.build("room_pillars_1", 2)
	first.pos = Vector2(440, 300)
	expect(assist.apply(original, origin, w.enemies, w.geometry, 1, "auto", 400, "room2") == original and assist.locked_uid == -1, "automatic aim cannot lock a target through a solid pillar")
	w.geometry.build("room_open_1", 2)
	first.pos = Vector2(420, 300)
	assist.apply(original, origin, w.enemies, w.geometry, 2, "auto", 400, "room3")
	var closer = w.spawn_enemy("e01", Vector2(300, 320))
	assist.apply(original, origin, w.enemies, w.geometry, 2.1, "auto", 400, "room3")
	expect(assist.locked_uid == first.uid, "automatic aim keeps a valid lock for 250ms when another enemy approaches")
	assist.apply(original, origin, w.enemies, w.geometry, 2.3, "auto", 400, "room3")
	expect(assist.locked_uid == closer.uid, "automatic aim can select a nearer target after its short lock expires")
	closer.dead = true
	assist.apply(original, origin, w.enemies, w.geometry, 2.31, "auto", 400, "room3")
	expect(assist.locked_uid == first.uid, "a dead target cancels lock retention immediately")
	closer.dead = false
	first.arrival = 8
	closer.arrival = 8
	expect(assist.apply(original, origin, w.enemies, w.geometry, 2.4, "auto", 400, "room3") == original and assist.locked_uid == -1, "arrival telegraphs do not become aimable actors early")
	var feedback = Haptics.new()
	var pulse = feedback.select([{"kind": "dash"}, {"kind": "skill"}, {"kind": "player_hurt"}], 10)
	expect(pulse.ms == 65 and pulse.priority == 3, "one event batch uses the highest-priority bounded haptic pulse")
	expect(feedback.select([{"kind": "dash"}], 10.02).is_empty(), "low-priority events cannot flood or interrupt a recent hurt pulse")
	feedback.enabled = false
	expect(feedback.select([{"kind": "player_hurt"}], 11).is_empty(), "disabling haptics suppresses all pulse requests")
	feedback.stop()
	var rotation = Orientation.new()
	expect(rotation.observe(Vector2i(1024, 768)).is_empty() and not rotation.blocked, "a four-to-three tablet surface retains the complete landscape room")
	expect(rotation.observe(Vector2i(720, 1280)) == "blocked" and rotation.blocked, "a portrait surface produces one pause transition")
	expect(rotation.observe(Vector2i(720, 1280)).is_empty(), "a stable portrait surface does not repeatedly write or rebuild the guard")
	expect(rotation.observe(Vector2i.ZERO).is_empty() and rotation.blocked, "a transient zero-size surface cannot dismiss the pause guard")
	expect(rotation.observe(Vector2i(1100, 1000)).is_empty() and rotation.blocked, "split-window aspect jitter does not repeatedly restore control")
	expect(rotation.observe(Vector2i(1280, 720)) == "restored" and not rotation.blocked, "a restored landscape surface issues one explicit confirmation transition")
	var pickup_world = World.new()
	pickup_world.start("c_paper", 9172)
	var pickup_origin = pickup_world.player.pos + Vector2(140, 0)
	pickup_world.pickups = [{"uid": 1, "kind": "coin", "pos": pickup_origin, "value": 2, "delay": 0.0, "natural": true, "magnet": false}]
	pickup_world.update_pickups(.016)
	expect(pickup_world.pickups[0].pos == pickup_origin, "default pickup settings preserve the original 120-unit coin range")
	pickup_world.set_pickup_scale(1.25)
	pickup_world.update_pickups(.016)
	expect(pickup_world.pickups[0].magnet and pickup_world.pickups[0].pos != pickup_origin, "enlarged pickup support pulls a coin inside its bounded 150-unit range")
	pickup_world.pickups = [{"uid": 2, "kind": "heal", "pos": pickup_world.player.pos + Vector2(28, 0), "value": 2, "delay": 0.0, "natural": false, "magnet": false}]
	pickup_world.update_pickups(.016)
	expect(not pickup_world.pickups[0].magnet, "accessibility pickup scaling cannot automatically consume nearby healing")
	pickup_world.pickups = [{"uid": 3, "kind": "ash", "pos": pickup_world.player.pos + Vector2(20, 0), "value": 2, "delay": .6, "natural": true, "magnet": false}]
	pickup_world.update_pickups(.016)
	expect(not pickup_world.pickups[0].magnet, "expanded pickup range still respects ash return delay and contract penalties")
	pickup_world.set_pickup_scale(.5)
	pickup_world.pickups = [{"uid": 4, "kind": "coin", "pos": pickup_world.player.pos + Vector2(75, 0), "value": 2, "delay": 0.0, "natural": true, "magnet": false}]
	pickup_world.update_pickups(.016)
	expect(not pickup_world.pickups[0].magnet, "the compact pickup option actually reduces the currency capture range")
	pickup_world.mode = "clear"
	pickup_world.update_pickups(.016)
	expect(pickup_world.pickups[0].magnet, "clear-room currency gathering remains available at the smallest pickup setting")
	pickup_world.set_pickup_scale(99)
	expect(pickup_world.run.pickup_radius_scale == 1.25, "pickup configuration is capped rather than accepting an unlimited radius")
	pickup_world.set_pickup_scale(NAN)
	expect(pickup_world.run.pickup_radius_scale == 1, "non-finite pickup values restore the original radius")
	pickup_world.set_pickup_scale(.5)
	store.write(pickup_world.snapshot())
	var resumed_pickups = World.new()
	expect(resumed_pickups.restore(store.read()) and resumed_pickups.run.pickup_radius_scale == .5, "the effective pickup setting survives an actual run checksum round trip")
	var old_run = pickup_world.snapshot()
	old_run.run.erase("pickup_radius_scale")
	expect(resumed_pickups.restore(old_run) and resumed_pickups.run.pickup_radius_scale == 1, "older runs obtain the original pickup behavior without rerolling the room")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "native shared input, real physical-key injection, checksum settings, touch IDs, aim geometry and haptic requests; no physical handset or controller claim"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/advanced-input-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Advanced input: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
