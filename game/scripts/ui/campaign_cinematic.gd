extends Control
## Narrative stills form a timed pan / dissolve sequence. The cursor is saveable simulation data.
const UI = preload("res://scripts/ui/game_theme.gd")
const Campaign = preload("res://scripts/core/expanded_campaign.gd")
var app
var image: Texture2D
var clock = 0.0
var story: Dictionary
var cursor = 0
var scene = 1

static func present(ui, opening: bool = false) -> void:
	ui.paused = true
	ui.screen = "cinematic"
	ui.adapter.clear()
	ui.clear_modal()
	ui.hud.visible = false
	ui.dim(1.0)
	var control = load("res://scripts/ui/campaign_cinematic.gd").new()
	control.app = ui
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.size = Vector2(1280, 720)
	control.story = ui.world.db.expansion.story[0] if opening else (ui.world.db.expansion.story[-1] if ui.world.mode == "epilogue" else Campaign.story_for_floor(ui.world.db, int(ui.world.run.transition.to_floor), ui.world.run.seed_text))
	control.cursor = int(ui.world.run.get("cinematic_cursor", 0))
	control.scene = scene_for(str(control.story.id), control.cursor)
	var path = "res://assets/story/expansion/scene_%02d.png" % control.scene
	if control.story.id.begins_with("floor_"):
		var destination = int(ui.world.run.transition.to_floor)
		path = Campaign.biome(ui.world.db, ui.world.run.seed_text, destination).backgrounds[0]
	if ResourceLoader.exists(path): control.image = load(path)
	ui.modal.add_child(control)
	ui.modal.set_meta("navigation_page", "cinematic_" + control.story.id)
	var caption = ui.panel(ui.modal, Rect2(78, 484, 1124, 170), Color(UI.INSET, .92), Color.TRANSPARENT)
	ui.label(caption, str(control.story.title), Rect2(32, 20, 1045, 45), 30, UI.JADE)
	ui.label(caption, str(control.story.lines[clampi(control.cursor, 0, control.story.lines.size() - 1)]), Rect2(32, 80, 1010, 64), 25)
	var next = ui.icon_button(ui.modal, "下一幕", "arrow-right", Rect2(1058, 662, 140, 50), func(): control.advance(opening), true, "继续")
	next.set_meta("nav_default", true)
	ui.icon_button(ui.modal, "收起播片，继续还愿", "skip-forward", Rect2(82, 662, 54, 50), func(): control.finish(opening))
	ui.audio.set_paused(true)

static func scene_for(id: String, index: int) -> int:
	if id == "opening": return 1 + mini(1, index)
	if id == "reveal": return 3 + mini(1, index)
	if id == "ordeal": return 5 + mini(1, index)
	if id == "final": return 7 + mini(2, index)
	if id == "ending": return 10 + mini(2, int(index / 2))
	return 2 + posmod(index + id.to_int(), 6)

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	if image == null: return
	var pan = 0.0 if app.settings.reduce_motion else minf(1.0, clock / 7.0)
	var expansion = 20 + 26 * pan
	var offset = Vector2(sin(scene * 1.7) * pan * 15, -pan * 9)
	draw_texture_rect(image, Rect2(Vector2(-expansion, -expansion) + offset, Vector2(1280,720) + Vector2.ONE * expansion * 2), false)
	draw_rect(Rect2(0,0,1280,720), Color(0,0,0,maxf(0, .75 - clock * 1.5)))

func advance(opening: bool) -> void:
	app.world.run.cinematic_cursor = cursor + 1
	if cursor + 1 >= story.lines.size(): finish(opening)
	else:
		app.save_current_run()
		present(app, opening)

func finish(opening: bool) -> void:
	app.world.run.erase("cinematic_cursor")
	if opening:
		app.world.run.opening_seen = true
		app.save_current_run()
		app.show_tutorial()
	elif app.world.mode == "epilogue":
		app.world.finish_epilogue()
		app.flush_events()
		app.show_result()
	else:
		app.world.continue_transition()
		app.flush_events()
		app.screen = "game"
		app.paused = false
		app.ui_signature = ""
