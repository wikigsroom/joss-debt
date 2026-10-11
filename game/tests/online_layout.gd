extends SceneTree
## Offline presentation fixtures only; live transport has separate native QA.
const Coop = preload("res://scripts/network/cooperative_match.gd")
const Duel = preload("res://scripts/network/duel_match.gd")
var app
var folder = ""
var checks: Array = []
var captures: Array = []
var serial = 0

func _initialize() -> void: call_deferred("run")

func frames(n: int = 4) -> void:
	for i in n: await process_frame

func check(id: String, passed: bool, detail: String = "") -> void:
	checks.append({"id": id, "passed": passed, "detail": detail})
	if not passed: print("LAYOUT_FAIL ", id, " ", detail)

func fixture(mode: String) -> Dictionary:
	var match_value = Coop.new() if mode == "coop" else Duel.new()
	match_value.begin("layout-fixture", [{"character": "c_paper", "weapon": "w14", "skill": "s09"}, {"character": "c_mask", "weapon": "w08", "skill": "s10"}], 14622)
	var state = match_value.view(0)
	state.merge({"op": "state", "room": "layout", "seat": 0, "link": "layout", "state_seq": 1, "lease": 1,
		"input_epoch": 1, "input_scene": 1, "names": ["纸偶还愿人测试长昵称", "队友测试昵称"], "code": "001725", "ready": [false, false],
		"resume_ready": [false, false], "rematch_ready": [false, false], "connected": [true, true], "grace_left": 90,
		"suspend_reason": "menu", "quick": false}, true)
	return state

func display(state: Dictionary, page: String) -> void:
	app.online.session.presentation.clear()
	app.online.session.event_match = ""
	app.online.session.link_id = "layout"
	app.online.session.authorized_room = "layout"
	serial += 1
	state.state_seq = serial
	# Install the fixture's page before accept_state emits changed. A previous
	# repayment page must not render against the next Duel fixture's actor shape.
	app.online.page = page
	app.online.session.accept_state(state)
	app.online.refresh()
	await frames()

func controls(node: Node, all: Array) -> void:
	if node is Control and node.is_visible_in_tree(): all.append(node)
	for child in node.get_children(): controls(child, all)

func visible_rect(control: Control) -> Rect2:
	var rect = control.get_global_rect()
	var parent = control.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return rect.intersection(Rect2(Vector2.ZERO, root.get_visible_rect().size))

func inspect(name_value: String) -> void:
	var all: Array = []
	controls(app.modal, all)
	var buttons = all.filter(func(node): return node is BaseButton or node is LineEdit)
	var viewport = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var full: Array = []
	for button in buttons:
		var id = str(button.get_meta("nav_id", button.name))
		var rect = visible_rect(button)
		if not rect.has_area(): continue
		check(name_value + "/within-viewport/" + id, viewport.encloses(rect))
		if rect.size.distance_to(button.get_global_rect().size) < 2:
			full.append(button)
			if app.mobile_ui:
				var pixels_per_logical = root.get_screen_transform().get_scale().y
				var minimum = 48.0 * app.qa_display_dpi / 160.0
				check(name_value + "/touch-target/" + id, button.size.y * pixels_per_logical >= minimum - 2, str(button.size.y * pixels_per_logical))
	for i in full.size():
		for j in range(i + 1, full.size()):
			if full[i].is_ancestor_of(full[j]) or full[j].is_ancestor_of(full[i]): continue
			var overlap = visible_rect(full[i]).intersection(visible_rect(full[j]))
			check(name_value + "/separate-controls/%s/%s" % [full[i].get_meta("nav_id", ""), full[j].get_meta("nav_id", "")], not overlap.has_area() or overlap.size.x < 1 or overlap.size.y < 1)
	for node in all:
		if node is Label or node is Button or node is LineEdit:
			check(name_value + "/no-endpoint/" + str(node.name), not "xhz-server" in node.text and not "wss://" in node.text and not "ws://" in node.text)
		if node is TextureRect and node.has_meta("online_art_size"):
			check(name_value + "/art-preserves-aspect/" + str(node.name), node.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and node.size == node.get_meta("online_art_size"))
	await RenderingServer.frame_post_draw
	var bitmap = root.get_texture().get_image()
	var path = folder.path_join(name_value + ".png")
	captures.append({"name": name_value, "saved": bitmap.save_png(path) == OK, "size": [bitmap.get_width(), bitmap.get_height()]})

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	folder = app.qa_directory
	await frames(8)
	app.online.enabled = true
	app.online.session.set_process(false)
	app.online.session.set_physics_process(false)
	for config in [{"id": "desktop", "size": Vector2i(1280, 720), "dpi": 160, "mobile": false},
		{"id": "x30", "size": Vector2i(2400, 1080), "dpi": 360, "mobile": true},
		{"id": "wide-phone", "size": Vector2i(2520, 1080), "dpi": 400, "mobile": true},
		{"id": "tablet", "size": Vector2i(2048, 1536), "dpi": 264, "mobile": true}]:
		app.mobile_ui = config.mobile
		app.qa_display_dpi = config.dpi
		app.qa_display_safe = Rect2(72, 24, config.size.x - 144, config.size.y - 72) if config.mobile else Rect2(Vector2.ZERO, config.size)
		root.size = config.size
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if config.mobile else Window.CONTENT_SCALE_ASPECT_KEEP
		await frames(6)
		app.apply_safe_area()
		await frames(6)
		app.online.session.room = {}
		app.online.session.state = "online"
		for page in ["hub", "profile", "loadout", "code", "identity"]:
			app.online.page = page
			app.online.refresh()
			await frames(5)
			await inspect(config.id + "-" + page)
		for mode in ["coop", "duel"]:
			var state = fixture(mode)
			for phase in ["lobby", "suspended", "finished"]:
				state.phase = phase
				await display(state.duplicate(true), "status")
				await inspect(config.id + "-" + mode + "-" + phase)
			state.phase = "suspended"
			state.builds = [["r01", "r34"], ["r08", "r40"]]
			for page in ["build", "arena", "leave_confirm"]:
				await display(state.duplicate(true), page)
				await inspect(config.id + "-" + mode + "-" + page)
			state.phase = "draft"
			if mode == "coop":
				state.choice_mode = "shop"
				state.picked = [-1, -1]
				state.offers = [{"kind": "relic", "id": "r01", "price": 20}, {"kind": "weapon", "id": "w14", "price": 24}, {"kind": "skill", "id": "s09", "price": 32}, {"kind": "heal", "id": "heal", "price": 12}]
			await display(state.duplicate(true), "status")
			await inspect(config.id + "-" + mode + "-draft")
			if mode == "coop":
				state.offers.pop_back()
				await display(state.duplicate(true), "status")
				await inspect(config.id + "-coop-three-gifts")
				state.choice_mode = "replace"
				state.actors[0].run.relics = {}
				for row in app.world.db.rows("relics").slice(0, 12): state.actors[0].run.relics[row.id] = 1
				await display(state.duplicate(true), "status")
				await inspect(config.id + "-coop-replacement")
				state.phase = "suspended"
				state.scene.stairs = true
				state.actors[0].run.coins = 100
				state.actors[0].run.contracts = [{"id": app.world.db.rows("debt_contracts")[0].id, "interest": 0}]
				for page in ["build", "repay"]:
					await display(state.duplicate(true), page)
					await inspect(config.id + "-coop-debt-" + page)
	var passed = checks.all(func(item): return item.passed) and captures.all(func(item): return item.saved)
	var file = FileAccess.open(folder.path_join("layout.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": checks, "captures": captures, "scope": "offline presentation fixtures; not a transport test", "physical_android": false}, "\t", true, true))
	file.close()
	print("LAYOUT_RESULT ", passed, " checks=", checks.size(), " captures=", captures.size())
	quit(0 if passed else 1)
