extends Node2D

const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Progress = preload("res://scripts/core/meta_progress.gd")
const Story = preload("res://scripts/core/story_book.gd")
const BossPattern = preload("res://scripts/combat/boss_patterns.gd")
const Hub = preload("res://scripts/ui/hub_ui.gd")
const RouteMap = preload("res://scripts/ui/route_map.gd")
const Adapter = preload("res://scripts/ui/input_adapter.gd")
const Renderer = preload("res://scripts/ui/game_renderer.gd")
const RuntimeQuality = preload("res://scripts/ui/runtime_quality.gd")
const Audio = preload("res://scripts/ui/audio_director.gd")
const GameHud = preload("res://scripts/ui/game_hud.gd")
const ControlSettings = preload("res://scripts/ui/control_settings.gd")
const AimAssist = preload("res://scripts/ui/aim_assist.gd")
const Haptics = preload("res://scripts/ui/haptic_feedback.gd")
const Reader = preload("res://scripts/ui/narrative_reader.gd")
const Orientation = preload("res://scripts/ui/orientation_guard.gd")
const MobileSurface = preload("res://scripts/ui/mobile_surface.gd")
const SaveSession = preload("res://scripts/core/save_session.gd")
const SaveSlots = preload("res://scripts/core/save_slots.gd")
const SaveUI = preload("res://scripts/ui/save_transfer_ui.gd")
const UI = preload("res://scripts/ui/game_theme.gd")
const Modern = preload("res://scripts/ui/modern_ui.gd")
const CharacterSheet = preload("res://scripts/ui/character_sheet.gd")
const RunReview = preload("res://scripts/ui/run_review.gd")
const WeaponTrial = preload("res://scripts/core/weapon_trial.gd")
const DailySeed = preload("res://scripts/core/daily_seed.gd")
const ChoiceShortcuts = preload("res://scripts/core/choice_shortcuts.gd")
const RunTelemetry = preload("res://scripts/core/run_telemetry.gd")
const TrialUI = preload("res://scripts/ui/weapon_trial_ui.gd")
const MenuFlow = preload("res://scripts/ui/menu_flow.gd")
const KeyboardNavigation = preload("res://scripts/ui/keyboard_navigation.gd")
const Seed = preload("res://scripts/core/derived_seed.gd")
const SeedUI = preload("res://scripts/ui/seed_ui.gd")
const Cinematic = preload("res://scripts/ui/campaign_cinematic.gd")
const EquipmentUI = preload("res://scripts/ui/equipment_ui.gd")
const OnlineController = preload("res://scripts/network/online_controller.gd")
const PAPER = UI.TEXT
const GOLD = UI.MUTED
const INK = UI.BACKGROUND
const RED = UI.ACCENT
const CHARACTER_TAGS = ["焚账回灰", "远结连债", "灯宴流火", "重印招架", "回伞收灰", "穿名勾销"]

var world = World.new()
var online
var store
var save_session
var save_slots
var save_slot: int = 1
var menu_page: String = "characters"
var selected_run_kind = "normal"
var collection_kind = "relics"
var collection_id = ""
var archive_ending = ""
var page_parents: Dictionary = {}
var confirmation_parent: Dictionary = {}
var pending_start: Dictionary = {}
var keyboard = KeyboardNavigation.new()
var settings_return_menu_page: String = "characters"
var save_import_draft: Dictionary = {}
var save_import_settings = false
var progress
var telemetry
var adapter = Adapter.new()
var aim_assist = AimAssist.new()
var haptics = Haptics.new()
var orientation = Orientation.new()
var orientation_overlay: Control
var qa_surface = Vector2i.ZERO
var qa_rotation_time = 0.0
var qa_exploration_state: Dictionary = {}
var capture_action = ""
var capture_device = "keyboard"
var capture_scroll = 0
var renderer: Node2D
var quality = RuntimeQuality.new()
var audio: Node
var interface: Control
var hud: Control
var modal: Control
var font: Font
var title_font: Font
var selected = "c_paper"
var seed_draft = ""
var paused = true
var screen = "menu"
var ui_signature = ""
var resource_label: Label
var floor_label: Label
var skill_label: Label
var hint_label: Label
var energy_bar: ProgressBar
var notice_label: Label
var notice_left = 0.0
const DEFAULT_SETTINGS = {"muted": false, "touch": false, "mirror": false, "reduce_motion": false, "master_volume": .8, "music_volume": .7, "effects_volume": .8,
	"music_mode": "random",
	"bindings": {}, "touch_layout": {}, "touch_sizes": {}, "deadzone": .18, "fixed_sticks": false, "fire_toggle": false, "control_scale": 1.0, "control_opacity": 1.0,
	"aim_mode": "light", "haptics": true, "damage_numbers": true, "shake_scale": 1.0, "hitstop": true, "flash_scale": 1.0, "particle_scale": 1.0, "performance_mode": "auto", "shape_cues": false, "combat_text_scale": 1.0,
	"story_text_scale": 1.0, "pickup_radius_scale": 1.0}
var settings = DEFAULT_SETTINGS.duplicate(true)
var checkpoint: Dictionary = {}
var shop_trial = WeaponTrial.new()
var shop_trial_choice = 0
var shop_trial_focus = -1
var qa_active = false
var qa_capture_enabled = false
var qa_keyboard_enabled = false
var qa_equipment_enabled = false
var qa_consumables_enabled = false
var qa_display_enabled = false
var qa_online_enabled = false
var qa_display_safe = Rect2()
var qa_display_cutouts: Array = []
var qa_display_dpi = 0.0
var qa_expansion_enabled = false
var qa_tick = 0
var qa_capture_busy = false
var qa_captures: Array = []
var qa_directory = ""
var choice_buttons: Array = []
var selected_weapon = ""
var mobile_ui = false
var mobile_button_height = 80.0
var mobile_choice = 0
var mobile_interface_origin = Vector2.ZERO
var mobile_keyboard_button: Button
var mobile_safe_signature = ""
var mobile_safe_elapsed = 0.0
var story = Story.new()
var story_filter = ""
var npc_line_index = 0
var hub_page = ""
var settings_return_to_menu = true
var qa_asset_failures: Array = []
var qa_asset_count = 0
var qa_interaction_checks: Array = []
var qa_stress_frames: Array = []
var qa_stress_physics: Array = []
var qa_stress_ticks: Array = []
var qa_stress_memory = 0.0

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--qa-audio"):
		qa_active = true
		audio = Audio.new()
		add_child(audio)
		var fixture = preload("res://scripts/ui/audio_capture_qa.gd").new()
		fixture.director = audio
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--qa-output="): fixture.directory = argument.trim_prefix("--qa-output=")
		add_child(fixture)
		set_process(false)
		set_physics_process(false)
		return
	font = UI.body_font()
	title_font = UI.display_font()
	qa_capture_enabled = OS.get_cmdline_user_args().has("--qa-capture")
	qa_keyboard_enabled = OS.get_cmdline_user_args().has("--qa-keyboard")
	qa_expansion_enabled = OS.get_cmdline_user_args().has("--qa-expansion")
	qa_equipment_enabled = OS.get_cmdline_user_args().has("--qa-equipment")
	qa_consumables_enabled = OS.get_cmdline_user_args().has("--qa-consumables")
	qa_display_enabled = OS.get_cmdline_user_args().has("--qa-display")
	qa_online_enabled = OS.get_cmdline_user_args().has("--qa-online")
	qa_active = qa_capture_enabled or qa_keyboard_enabled or qa_expansion_enabled or qa_equipment_enabled or qa_consumables_enabled or qa_display_enabled or qa_online_enabled
	if not qa_active: telemetry = RunTelemetry.new()
	mobile_ui = OS.get_name() in ["Android", "iOS"] or OS.get_cmdline_user_args().has("--mobile-ui")
	if mobile_ui:
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		if OS.get_name() in ["Android", "iOS"]: DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	if qa_active:
		qa_directory = ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime")
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--qa-output="):
				qa_directory = argument.trim_prefix("--qa-output=")
		DirAccess.make_dir_recursive_absolute(qa_directory)
	if qa_keyboard_enabled or qa_expansion_enabled or qa_equipment_enabled or qa_consumables_enabled or qa_display_enabled or qa_online_enabled:
		save_slots = SaveSlots.new(qa_directory.path_join("isolated-saves").path_join(str(Time.get_ticks_usec())))
		save_slot = save_slots.selected_slot()
		save_session = SaveSession.new(save_slots.base_path(save_slot), save_slots.legacy_profile_path(save_slot), save_slots.legacy_run_path(save_slot))
	elif qa_active:
		save_slot = 1
		save_session = SaveSession.new("user://qa_session", "user://qa_profile", "user://qa_saves")
	else:
		save_slots = SaveSlots.new("user://")
		save_slot = save_slots.selected_slot()
		save_session = SaveSession.new(save_slots.base_path(save_slot), save_slots.legacy_profile_path(save_slot), save_slots.legacy_run_path(save_slot))
	store = save_session.view("checkpoint")
	progress = Progress.new("", save_session.view("profile"))
	progress.read_only = save_session.read_only
	for key in settings:
		if not qa_active: settings[key] = progress.data.settings.get(key, settings[key])
	settings.story_text_scale = clampf(float(settings.story_text_scale), 1.0, 1.5)
	settings.pickup_radius_scale = clampf(float(settings.pickup_radius_scale), .5, 1.25)
	adapter.touch_mode = OS.get_name() in ["Android", "iOS"] or OS.get_cmdline_user_args().has("--touch-preview")
	settings.touch = settings.touch or adapter.touch_mode
	quality.set_mode(str(settings.get("performance_mode", "auto")), mobile_ui)
	adapter.touch_mode = settings.touch
	adapter.mirror = settings.mirror
	adapter.configure(settings)
	renderer = Renderer.new()
	renderer.world = world
	renderer.adapter = adapter
	add_child(renderer)
	audio = Audio.new()
	add_child(audio)
	audio.set_muted(settings.muted)
	audio.set_levels(settings.master_volume, settings.music_volume, settings.effects_volume)
	renderer.reduce_motion = settings.reduce_motion
	apply_control_settings()
	var layer = CanvasLayer.new()
	add_child(layer)
	interface = Control.new()
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(interface)
	var theme = Theme.new()
	UI.install(theme)
	interface.theme = theme
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = theme
	layer.add_child(hud)
	modal = Control.new()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.add_child(modal)
	orientation_overlay = Control.new()
	orientation_overlay.size = Vector2(1280, 720)
	orientation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	orientation_overlay.visible = false
	interface.add_child(orientation_overlay)
	build_hud()
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()
	checkpoint = store.read()
	online = OnlineController.new()
	add_child(online)
	online.initialize(self, qa_directory.path_join("online-client") if qa_active else "user://online-client")
	show_menu("title" if qa_capture_enabled else "splash")
	if not qa_active and not save_session.message.is_empty(): notice(save_session.message)
	get_window().focus_exited.connect(on_focus_lost)
	get_window().focus_entered.connect(func(): audio.set_suspended(false))
	get_tree().auto_accept_quit = false
	if qa_keyboard_enabled:
		var fixture = preload("res://scripts/ui/keyboard_flow_qa.gd").new()
		fixture.app = self
		fixture.directory = qa_directory
		add_child(fixture)
	elif qa_expansion_enabled:
		var fixture = preload("res://scripts/ui/expansion_native_qa.gd").new()
		fixture.app = self
		fixture.directory = qa_directory
		add_child(fixture)
	elif qa_equipment_enabled:
		var fixture = preload("res://scripts/ui/equipment_native_qa.gd").new()
		fixture.app = self
		fixture.directory = qa_directory
		add_child(fixture)
	elif qa_consumables_enabled:
		var fixture = preload("res://scripts/ui/consumable_native_qa.gd").new()
		fixture.app = self
		fixture.directory = qa_directory
		add_child(fixture)
	elif qa_online_enabled:
		var fixture = preload("res://scripts/ui/online_native_qa.gd").new()
		fixture.app = self
		fixture.directory = qa_directory
		add_child(fixture)

func apply_safe_area(density_for_qa: float = 0) -> void:
	if not mobile_ui: return
	var viewport_rect = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var raw = qa_display_safe if qa_active and qa_display_safe.has_area() else Rect2(DisplayServer.get_display_safe_area())
	var cutouts = qa_display_cutouts if qa_active and not qa_display_cutouts.is_empty() else DisplayServer.get_display_cutouts()
	var safe = MobileSurface.safe_area(viewport_rect, get_viewport().get_screen_transform(), raw, cutouts)
	if adapter.safe_rect != safe.grow(-6): adapter.clear()
	adapter.safe_rect = safe.grow(-6)
	var fitting = MobileSurface.contained(safe)
	var scale_value = fitting.x.length()
	interface.scale = Vector2.ONE * scale_value
	interface.position = fitting.origin
	mobile_interface_origin = interface.position
	var pixel_scale = get_viewport().get_screen_transform().x.length() * scale_value
	if qa_active and qa_display_dpi > 0: density_for_qa = qa_display_dpi
	var dpi = maxf(160, density_for_qa if qa_active and density_for_qa > 0 else DisplayServer.screen_get_dpi())
	var dp_scale = dpi / 160.0 / maxf(.1, get_viewport().get_screen_transform().x.length())
	mobile_button_height = maxf(64, 48.0 * dpi / 160.0 / maxf(.1, pixel_scale))
	adapter.minimum_action_radius = maxf(40, 24 * dp_scale)
	adapter.minimum_stick_radius = maxf(48, 44 * dp_scale)
	adapter.control_gap = maxf(8, 8 * dp_scale)
	hud.position = safe.position
	hud.size = safe.size
	renderer.fit_surface(safe)
	if not adapter.valid_layout(): adapter.reset_layout("tablet" if safe.size.x / safe.size.y < 1.6 else "phone")
	for child in modal.get_children():
		if child.has_meta("surface_curtain"): fit_curtain(child)
	update_hud()

func refresh_safe_area(delta: float) -> void:
	if not mobile_ui or qa_active: return
	mobile_safe_elapsed += delta
	if mobile_safe_elapsed < .25: return
	mobile_safe_elapsed = 0
	# A 180-degree sensor rotation can move the camera/gesture inset without a
	# viewport resize. Refresh only when the platform's physical safe area changes.
	var signature = str(DisplayServer.get_display_safe_area()) + str(DisplayServer.get_display_cutouts()) + str(get_viewport().get_screen_transform())
	if signature != mobile_safe_signature:
		mobile_safe_signature = signature
		apply_safe_area()

func fit_curtain(curtain: ColorRect) -> void:
	curtain.position = -interface.position / interface.scale
	curtain.size = get_viewport().get_visible_rect().size / interface.scale

func hide_mobile_keyboard() -> void:
	if not mobile_ui: return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	var owner = get_viewport().gui_get_focus_owner()
	if owner is LineEdit or owner is TextEdit: owner.release_focus()
	if interface != null: interface.position = mobile_interface_origin
	if is_instance_valid(mobile_keyboard_button): mobile_keyboard_button.visible = false

func update_mobile_keyboard(height_for_qa: float = -1) -> void:
	if not mobile_ui or interface == null: return
	interface.position = mobile_interface_origin
	var pixels = height_for_qa if qa_active and height_for_qa >= 0 else (float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0)
	var owner = get_viewport().gui_get_focus_owner()
	var editing = pixels > 0 and (owner is LineEdit or owner is TextEdit) and interface.is_ancestor_of(owner)
	if is_instance_valid(mobile_keyboard_button): mobile_keyboard_button.visible = editing
	if not editing: return
	var safe = adapter.safe_rect
	var visible_bottom = minf(safe.end.y, get_viewport().get_visible_rect().size.y - pixels / get_viewport().get_screen_transform().y.length())
	var rect = owner.get_global_rect()
	interface.position.y -= maxf(0, rect.end.y - visible_bottom + 20)
	if not is_instance_valid(mobile_keyboard_button):
		var layer = CanvasLayer.new()
		layer.layer = 9
		add_child(layer)
		var control = Control.new()
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(control)
		mobile_keyboard_button = icon_button(control, "收起键盘", "chevron-down", Rect2(0,0,80,80), hide_mobile_keyboard)
	var diameter = maxf(64, adapter.minimum_action_radius * 2)
	mobile_keyboard_button.size = Vector2.ONE * diameter
	mobile_keyboard_button.position = Vector2(safe.end.x - diameter - 12, maxf(safe.position.y + 8, visible_bottom - diameter - 8))
	mobile_keyboard_button.visible = true

func update_orientation() -> void:
	if not mobile_ui: return
	var surface = qa_surface if qa_active and qa_surface != Vector2i.ZERO else DisplayServer.window_get_size()
	var transition = orientation.observe(surface)
	if transition == "blocked":
		adapter.clear()
		haptics.stop()
		aim_assist.clear()
		save_current_run()
		paused = true
		audio.set_paused(true)
		for child in orientation_overlay.get_children(): child.queue_free()
		var backdrop = ColorRect.new()
		backdrop.size = Vector2(1280, 720)
		backdrop.color = Color(INK, .98)
		orientation_overlay.add_child(backdrop)
		var card = panel(orientation_overlay, Rect2(294, 212, 692, 296), Color("30372f"))
		label(card, "把灯横过来", Rect2(36, 30, 620, 69), 42)
		label(card, "请横放设备，或展开更宽的窗口。\n这页账已暂停，横屏后再确认继续。", Rect2(36, 118, 620, 113), 25, GOLD)
		orientation_overlay.visible = true
	elif transition == "restored":
		orientation_overlay.visible = false
		adapter.clear()
		if screen == "game": show_pause("横屏已恢复，准备好再继续。")
		elif screen in ["menu", "hub", "story"]: audio.set_paused(false)

func starting_weapon(character: String) -> String:
	var weapons = progress.starting_weapons(character)
	if weapons.has(selected_weapon): return selected_weapon
	var preference = str(progress.data.loadouts.get(character, weapons[0])) if progress.has_feature("remember_unlocked_starting_weapon") else str(weapons[0])
	return preference if weapons.has(preference) else str(weapons[0])

func choose_starting_weapon(id: String) -> void:
	selected_weapon = id
	if progress.has_feature("remember_unlocked_starting_weapon"):
		progress.data.loadouts[selected] = id
		progress.save()
	show_menu()

func box_style(background: Color = INK, border: Color = GOLD, border_width: int = 1) -> StyleBoxFlat:
	var color = UI.EDGE if border in [GOLD, Color("635c44"), Color("665e48"), Color("53674d")] else border
	return UI.style(background, color if color != UI.EDGE else Color.TRANSPARENT, 24, border_width)

func panel(parent: Control, rect: Rect2, background: Color = INK, border: Color = GOLD) -> Panel:
	var result = Panel.new()
	result.position = rect.position
	result.size = rect.size
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_stylebox_override("panel", box_style(background, border))
	parent.add_child(result)
	return result

func label(parent: Control, text: String, rect: Rect2, size_value: int = 20, color: Color = PAPER) -> Label:
	var result = Label.new()
	result.position = rect.position
	result.size = rect.size
	result.text = text
	result.add_theme_font_size_override("font_size", size_value)
	if size_value >= 32:
		result.add_theme_font_override("font", title_font)
	elif size_value >= 23:
		result.add_theme_font_override("font", UI.body_font(true))
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func reading_text(parent: Control, lines: Array, rect: Rect2, base_size: int = 22, color: Color = PAPER) -> ScrollContainer:
	var reader = Reader.new()
	reader.name = "NarrativeReader"
	reader.position = rect.position
	reader.size = rect.size
	parent.add_child(reader)
	reader.populate(lines, font, roundi(base_size * float(settings.story_text_scale)), color)
	return reader

func button(parent: Control, text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	if mobile_ui: rect.size = rect.size.max(Vector2.ONE * mobile_button_height)
	var result = preload("res://scripts/ui/rounded_button.gd").new()
	result.position = rect.position
	result.size = rect.size
	result.text = text
	result.set_meta("action_label", text)
	result.accessibility_name = text
	result.tooltip_text = text
	UI.button_styles(result, primary, mini(24, roundi(rect.size.y * .5)))
	result.pressed.connect(func():
		hide_mobile_keyboard()
		if audio != null: audio.play("menu")
		callback.call())
	result.mouse_entered.connect(func():
		if not result.disabled and not settings.reduce_motion:
			result.create_tween().tween_property(result, "modulate", Color(1.1, 1.07, 1.0), .12))
	result.mouse_exited.connect(func(): result.create_tween().tween_property(result, "modulate", Color.WHITE, .12))
	parent.add_child(result)
	return result

func icon(parent: Control, key: String, rect: Rect2, color: Color = PAPER) -> TextureRect:
	var art = TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture = UI.icon(key)
	art.position = rect.position
	art.size = rect.size
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.modulate = UI.icon_tint(key, color)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art

func icon_button(parent: Control, semantic: String, key: String, rect: Rect2, callback: Callable, primary: bool = false, caption: String = "") -> Button:
	var result = button(parent, semantic, rect, callback, primary)
	result.text = caption
	result.icon = UI.icon(key)
	result.expand_icon = true
	result.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if caption.is_empty() else HORIZONTAL_ALIGNMENT_LEFT
	UI.button_styles(result, primary, roundi(minf(rect.size.x, rect.size.y) * .5))
	if key in UI.PickupArt.UI_KEYS:
		for state in ["normal", "hover", "pressed", "focus"]:
			result.add_theme_color_override("icon_" + state + "_color", Color.WHITE)
	return result

func clear_modal() -> void:
	if paused and world != null: world.clear_touch_charge()
	keyboard.before_rebuild(self)
	modal.remove_meta("navigation_page")
	haptics.stop()
	choice_buttons.clear()
	for child in modal.get_children():
		modal.remove_child(child)
		child.queue_free()

func dim(alpha: float = 0.82) -> void:
	var curtain = ColorRect.new()
	curtain.set_meta("surface_curtain", true)
	fit_curtain(curtain)
	curtain.color = Color(0.055, 0.06, 0.05, alpha)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(curtain)

func show_menu(page: String = "characters") -> void:
	if shop_trial.active(): end_shop_trial(false)
	menu_page = page
	Modern.menu(self)

func save_slot_summary(slot: int = save_slot) -> Dictionary:
	if qa_capture_enabled:
		return {"slot": slot, "occupied": slot == 1 and not save_session.current.profile.is_empty(), "active": slot == save_slot, "label": "QA" if slot == 1 else "空白槽位"}
	if save_slots == null: return {"slot": slot, "occupied": false, "active": slot == save_slot, "label": "空白槽位"}
	return save_slots.summary(slot)

func select_save_slot(slot: int) -> void:
	if qa_capture_enabled:
		save_slot = slot
		show_menu("title")
		return
	if save_slots == null: return
	if screen == "game" and not world.run.is_empty(): save_current_run()
	if not save_slots.select(slot):
		notice("存档槽位未能切换，当前愿簿保持不变。")
		return
	save_slot = save_slots.selected_slot()
	save_session = SaveSession.new(save_slots.base_path(save_slot), save_slots.legacy_profile_path(save_slot), save_slots.legacy_run_path(save_slot))
	store = save_session.view("checkpoint")
	progress = Progress.new("", save_session.view("profile"))
	progress.read_only = save_session.read_only
	reload_save_session()
	show_menu("title")

func page_state() -> Dictionary:
	return {"screen": screen, "menu": menu_page, "hub": hub_page, "page": str(modal.get_meta("navigation_page", ""))}

func remember_parent(page: String) -> void:
	if screen != page: page_parents[page] = page_state()

func return_to_state(state: Dictionary) -> void:
	screen = str(state.get("screen", "menu"))
	match str(state.get("screen", "menu")):
		"pause": show_pause()
		"hub": show_hub(str(state.get("hub", "wishes")))
		"result": show_result()
		"run_review": show_run_review(str(state.get("page", "damage")))
		"run_build", "inventory": show_inventory(str(state.get("page", "relics")))
		"run_history": show_run_history()
		"route": RouteMap.show_sheet(self, str(state.get("page", "map_build")).trim_prefix("map_"))
		"cinematic": Cinematic.present(self, not world.run.get("opening_seen", false))
		"seed_input": SeedUI.show(self)
		"achievements": show_achievements(str(state.get("page", "")))
		"settings": show_settings()
		"controls": ControlSettings.show_bindings(self, capture_device, capture_scroll)
		"assistance": ControlSettings.show_assistance(self)
		"touch_layout": ControlSettings.show_layout(self)
		"character": show_character_details()
		"audio_settings": show_audio_settings()
		"saves": SaveUI.show(self)
		"game": resume_game()
		_: show_menu(str(state.get("menu", "title")))

func return_to_parent(page: String) -> void:
	return_to_state(page_parents.get(page, {"screen": "menu", "menu": "title"}))

func open_character_select(kind: String = "normal") -> void:
	selected_run_kind = kind
	show_menu("characters")

func request_new_run() -> void:
	if save_session.read_only or not progress.data.characters.has(selected): return
	if selected_run_kind != "daily" and not seed_draft.is_empty() and not Seed.valid(seed_draft): SeedUI.show(self); return
	pending_start = {"character": selected, "daily": selected_run_kind == "daily", "seed_text": seed_draft}
	confirmation_parent = page_state()
	if not checkpoint.is_empty() and str(checkpoint.get("run", {}).get("result", "")) == "":
		MenuFlow.confirmation(self)
	else: confirm_new_run()

func confirm_new_run() -> void:
	if pending_start.is_empty(): return
	selected = str(pending_start.character)
	var daily = bool(pending_start.daily)
	var chosen_seed = str(pending_start.get("seed_text", ""))
	pending_start = {}
	if daily: begin_daily_run()
	else: begin_run(selected, chosen_seed.to_int(), true, {"seed_text": chosen_seed} if not chosen_seed.is_empty() else {})

func cancel_confirmation() -> void:
	pending_start = {}
	return_to_state(confirmation_parent)

func request_quit() -> void:
	if online != null and online.active():
		online.request_quit()
		return
	confirmation_parent = page_state()
	MenuFlow.confirmation(self, true)

func confirm_quit() -> void:
	if save_current_run(): get_tree().quit()

func save_to_menu() -> void:
	if save_current_run(): show_menu("title")

func show_focus_help(control: Control) -> void:
	var description = control.tooltip_text
	if description.is_empty(): return
	remember_parent("focus_help")
	paused = true
	screen = "focus_help"
	hud.visible = false
	adapter.clear()
	clear_modal()
	dim(.94)
	var sheet = panel(modal, Rect2(194, 100, 892, 520), UI.INSET, Color.TRANSPARENT)
	label(sheet, "详情", Rect2(36, 24, 730, 60), 36)
	reading_text(sheet, [description], Rect2(36, 117, 820, 278), 23)
	icon_button(sheet, "返回选择", "arrow-left", Rect2(36, 426, 820, 64), func(): return_to_parent("focus_help"), true, "返回")

func show_character_details(skill_id: String = "") -> void:
	CharacterSheet.show(self, skill_id)

func finish_ending(id: String) -> bool:
	if not save_session.begin(): return false
	var previous = progress.data.duplicate(true)
	var prior_ending = str(world.run.get("ending", ""))
	if not progress.finish(world, id):
		save_session.batching = false
		save_session.pending = {}
		return false
	store.write(world.snapshot())
	if save_session.finish():
		checkpoint = store.read()
		return true
	progress.data = previous
	world.run.ending = prior_ending
	notice("这一页未能存下，进度保持原样，请稍后重试。")
	return false

func begin_run(character: String, seed_value: int = 0, tutorial: bool = true, run_options: Dictionary = {}) -> void:
	if save_session.read_only:
		notice(save_session.message)
		return
	var seed_text = str(run_options.get("seed_text", ""))
	if seed_text.is_empty(): seed_text = Seed.fresh() if seed_value == 0 else Seed.text(seed_value)
	seed_value = seed_text.to_int()
	var preference = starting_weapon(character)
	var options = {"relic_pool": progress.relic_pool(), "coin_pickup_bonus": progress.coin_bonus(), "weapon": preference, "optional_bosses": progress.optional_bosses(), "pickup_radius_scale": settings.pickup_radius_scale}
	for key in run_options: options[key] = run_options[key]
	options.seed_text = seed_text
	if bool(options.get("daily", false)):
		options.relic_pool = world.db.rules.progression.initial_relic_ids.duplicate()
		options.coin_pickup_bonus = 0
		options.optional_bosses = []
		options.pickup_radius_scale = 1.0
		options.weapon = world.db.row("characters", character).weapon
	world.start(character, seed_value, 11 if not qa_active or qa_expansion_enabled or qa_equipment_enabled or qa_consumables_enabled else 3, options)
	world.run.opening_seen = not tutorial
	seed_draft = ""
	world.run.id = ("daily_%s_%s_%d" % [str(options.get("daily_key", "")), character, seed_value]) if bool(options.get("daily", false)) else ("%s_%d_%d" % [character, seed_value, Time.get_ticks_usec()])
	renderer.world = world
	renderer.hub = false
	renderer.visual_effects.clear()
	renderer.animation.clear()
	renderer.weapon_motion.clear()
	adapter.clear()
	ui_signature = ""
	hud.visible = true
	screen = "game"
	paused = false
	notice_left = 0.0
	audio.last_shot = -10.0
	audio.last_hit = -10.0
	audio.last_warning = -10.0
	audio.set_paused(false)
	clear_modal()
	flush_events()
	if tutorial:
		if world.run.get("campaign", false): Cinematic.present(self, true)
		else: show_tutorial()

func begin_daily_run() -> void:
	if save_session.read_only:
		notice(save_session.message)
		return
	if not progress.data.characters.has(selected):
		notice("先为这位还愿人留名，再参加每日种子。")
		return
	var date_value = Time.get_date_dict_from_system()
	var daily_key = DailySeed.key(date_value)
	begin_run(selected, DailySeed.seed_for(date_value), true, {"daily": true, "daily_key": daily_key, "daily_pool_version": DailySeed.pool_version()})

func restore_run() -> void:
	if save_session.read_only:
		notice(save_session.message)
		return
	checkpoint = store.read()
	if not world.restore(checkpoint):
		notice("这页账已无法续写。")
		return
	world.set_pickup_scale(float(settings.pickup_radius_scale))
	renderer.world = world
	renderer.hub = false
	hud.visible = true
	ui_signature = ""
	paused = true
	screen = "game"
	keyboard.memory.erase("pause/")
	show_pause("旧账已翻开，准备好再动身。")

func show_tutorial() -> void:
	paused = true
	screen = "tutorial"
	clear_modal()
	dim(.72)
	panel(modal, Rect2(170, 149, 940, 423), Color("2d3029"))
	label(modal, "先留余烬，再一起焚账。", Rect2(211, 180, 850, 65), 34)
	var tips = [["01  留烬", "连续命中会留下最多三枚余烬。\n靠近的敌人会被红色债线连接。"],
		["02  焚账", "点焚债图标，使余烬一起爆发。\n右杆推动瞄准并连续攻击。" if mobile_ui else "右键 / Q 使余烬同时爆发。\n纸童杀敌会返香；铃师更擅长连线。"],
		["03  回灰", "左杆移动，旁边的身法键闪避。\n点顶部地图看行路；走进门切房。" if mobile_ui else "自然掉落的香灰会补回香火。\n尖头青弹是危险；空格用身法穿过去。"]]
	for i in tips.size():
		label(modal, tips[i][0], Rect2(211 + i * 288, 266, 255, 40), 25, GOLD)
		label(modal, tips[i][1], Rect2(211 + i * 288, 319, 255, 124), 19)
	button(modal, "记住了 · 点灯", Rect2(720, 473, 338, mobile_button_height if mobile_ui else 50), resume_game, true)

func build_hud() -> void:
	var graphics = GameHud.new()
	graphics.world = world
	graphics.adapter = adapter
	graphics.app = self
	hud.add_child(graphics)
	var book = icon_button(hud, "愿簿", "book-open", Rect2(1132, 20, 56, 56), show_inventory)
	book.set_meta("hud_action", "inventory")
	var pause = icon_button(hud, "暂停", "pause", Rect2(1200, 20, 56, 56), func(): show_pause())
	pause.set_meta("hud_action", "pause")
	if mobile_ui:
		var map = icon_button(hud, "地图", "map", Rect2(1064, 20, 56, 56), func(): RouteMap.show_sheet(self))
		map.set_meta("hud_action", "map")
	var notice_box = panel(interface, Rect2(352, 640, 576, 56), Color(UI.INSET, .97), Color.TRANSPARENT)
	notice_box.z_index = 25
	notice_box.visible = false
	notice_label = label(notice_box, "", Rect2(18, 6, 540, 44), 17)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func update_hud() -> void:
	notice_label.get_parent().visible = notice_left > 0
	var reviewing = screen in ["result", "run_build", "run_review"]
	var top_notice = reviewing or keyboard.active(self)
	notice_label.get_parent().position.y = 4 if top_notice else (148 if screen == "game" and world.mode == "clear" else 640)
	notice_label.get_parent().size.y = 40 if top_notice else 56
	notice_label.position.y = 0 if top_notice else 6
	notice_label.size.y = 40 if top_notice else 44
	if world.run.is_empty():
		return
	var nav_size = maxf(64, mobile_button_height) if mobile_ui else 56.0
	for child in hud.get_children():
		if child is Button and child.has_meta("hud_action"):
			child.size = Vector2.ONE * nav_size
			var slot = {"pause": 0, "inventory": 1, "map": 2}.get(child.get_meta("hud_action"), 0)
			child.position = Vector2((hud.size.x if mobile_ui else 1280) - 24 - nav_size - (nav_size + 12) * slot, 20)

func _physics_process(delta: float) -> void:
	if qa_capture_enabled:
		qa_step()
	update_orientation()
	if online != null and online.active():
		online.physics(delta)
		return
	if not paused and screen == "game":
		if world.run.get("training", false): world.player.energy = 100.0
		adapter.set_phase(world.mode, not world.Equipment.active_row(world).is_empty())
		var frame = adapter.sample(renderer.to_world(get_viewport().get_mouse_position()), world.player.pos)
		if adapter.last_device in ["touch", "controller"]:
			var weapon = world.db.row("weapons", world.player.weapon)
			var radius = float(weapon.range)
			var assist_mode = str(settings.aim_mode)
			if frame.get("manual_aim", false) and assist_mode == "auto": assist_mode = "light"
			if str(weapon.mode) == "controlled": assist_mode = "off"
			frame.aim = aim_assist.apply(frame.aim, world.player.pos, world.enemies, world.geometry, world.time, assist_mode, radius, world.room_key(), str(weapon.mode))
		if frame.skill and adapter.last_device == "touch":
			if world.player.skill_cd > 0: notice("焚债还在冷却。")
			elif world.player.energy < world.skill_cost(): notice("香火不足。")
			elif world.db.row("skills", world.player.skill).requires_marked_target and world.skill_targets().is_empty(): notice("先攻击敌人，留下余烬。")
		if frame.active_item and adapter.last_device == "touch":
			var item = world.Equipment.active_row(world)
			if not item.is_empty() and world.run.active_item.charge < item.charge_rooms: notice("道具尚未充满。")
		if world.mode == "clear" and frame.interact and world.nearby_pickup().is_empty() and not world.run.get("training", false):
			if not world.try_enter_secret(): RouteMap.show_sheet(self)
		else:
			var begin = Time.get_ticks_usec()
			world.tick(frame, delta)
			if qa_active and qa_tick >= 500 and qa_tick < 680: qa_stress_ticks.append((Time.get_ticks_usec() - begin) / 1000.0)
		flush_events()
		var signature = world.mode + ":" + JSON.stringify(world.choices) + ":" + str(world.run.room) + ":" + str(world.nearby_secret_room()) + ":" + str(world.nearby_pickup().get("uid", -1))
		if signature != ui_signature:
			ui_signature = signature
			sync_game_modal()
	update_hud()

func _process(delta: float) -> void:
	refresh_safe_area(delta)
	update_mobile_keyboard()
	keyboard.update(self)
	notice_left = maxf(0, notice_left - delta)
	if quality != null and quality.sample(delta, screen == "game" and not paused):
		apply_runtime_quality()
	if renderer != null:
		renderer.combat_interface_visible = screen == "game" and not paused and world.mode in ["combat", "clear"]
	if qa_active and qa_tick >= 500 and qa_tick < 680:
		qa_stress_frames.append(delta * 1000.0)
		qa_stress_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		qa_stress_memory = maxf(qa_stress_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	if audio != null:
		audio.set_paused(paused and screen not in ["menu", "hub", "story"])
		audio.observe(world, screen)

func flush_events() -> void:
	var events = world.take_events()
	renderer.accept(events)
	audio.accept(events)
	haptics.accept(events, adapter.last_device)
	for event in events:
		if event.kind == "run_end" and not qa_active and telemetry != null:
			telemetry.record(world, event)
		if event.kind == "secret_discovered": notice("断绳松开了。靠近后，可以回应里面的愿。")
		if event.kind == "route_hint": notice("清房后，走到发光的门口进入下一张地图。")
		if event.kind == "item_notice": notice(str(event.text))
		if event.kind == "equipment_taken": notice(world.db.name_of({"active": "active_items", "trinket": "trinkets", "relic": "relics"}.get(event.type, "active_items"), str(event.id)) if event.type != "battery" else "火芯 · 充能 +1")
		if event.kind == "save_requested":
			if world.run.get("training", false): continue
			var previous = progress.data.duplicate(true)
			if not save_session.begin():
				notice(save_session.message)
				continue
			if not event.get("simulation_only", false):
				for message in progress.observe(world): notice(message)
			checkpoint = world.snapshot()
			store.write(checkpoint)
			if not save_session.finish():
				progress.data = previous
				checkpoint = store.read()
				notice("这页账没能存下，请稍后再试。")

func sync_game_modal() -> void:
	adapter.set_phase(world.mode, not world.Equipment.active_row(world).is_empty())
	# Ground prompts must not cancel held aim, firing, or a touch movement gesture.
	if world.mode not in ["combat", "clear"]:
		adapter.clear()
		world.clear_touch_charge()
	haptics.stop()
	clear_modal()
	hud.visible = true
	if world.run.get("campaign", false) and not world.run.get("opening_seen", false):
		Cinematic.present(self, true)
		return
	if world.mode == "clear":
		if world.run.get("training", false):
			icon_button(modal, "再演一遍", "refresh-cw", Rect2(527, 611, 226, mobile_button_height if mobile_ui else 56), reset_training, true, "重演")
		else:
			var entry_available = world.nearby_secret_room() >= 0
			var action_height = mobile_button_height if mobile_ui else 52
			var route_x = 850.0
			var route_y = (480.0 if mobile_ui else 536.0) if entry_available else (590.0 if mobile_ui else 594.0)
			icon_button(modal, "查看行路图", "map", Rect2(route_x, route_y, 230, action_height), func(): RouteMap.show_sheet(self), not entry_available, "行路")
			if entry_available:
				icon_button(modal, "拂绳 · 入断页", "link", Rect2(route_x, 590.0 if mobile_ui else 594.0, 260, action_height), func(): world.try_enter_secret(); flush_events(); ui_signature = "", true, "拂绳")
	elif world.mode in ["choice", "shop", "debt"]:
		show_choices()
	elif world.mode == "result":
		show_result()
	elif world.mode == "checkpoint":
		show_checkpoint()
	elif world.mode == "replace":
		show_replacement()
	elif world.mode in ["transition", "epilogue"]:
		Cinematic.present(self)
	if world.run.get("training", false) and world.mode in ["combat", "clear"]:
		if shop_trial.active(): TrialUI.controls(self)
		else: CharacterSheet.training_controls(self)
	if world.mode in ["combat", "clear"]: EquipmentUI.ground_hint(self)

func show_choices() -> void:
	Modern.choices(self)
	shop_trial_focus = -1

func choose_index(index: int) -> void:
	if world.take_choice(index):
		flush_events()
		ui_signature = ""
	else:
		notice(world.choice_reason(world.choices[index]) if index >= 0 and index < world.choices.size() else "这件供物暂时拿不了。")

func show_mobile_choice() -> void:
	Modern.mobile_choice(self)

func show_pause(reason: String = "灯还燃着，账可以慢慢还。") -> void:
	Modern.pause(self, reason)

func show_run_history() -> void:
	Modern.run_history(self)

func show_achievements(character_id: String = "") -> void:
	Modern.achievements(self, character_id)

func resume_game() -> void:
	if orientation.blocked: return
	adapter.clear()
	paused = false
	screen = "game"
	hud.visible = true
	ui_signature = ""
	clear_modal()
	audio.set_paused(false)
	sync_game_modal()

func show_settings() -> void:
	Modern.settings(self)

func apply_control_settings() -> void:
	if audio != null: audio.set_music_mode(str(settings.music_mode))
	quality.set_mode(str(settings.get("performance_mode", "auto")), mobile_ui)
	adapter.touch_mode = settings.touch
	adapter.mirror = settings.mirror
	adapter.deadzone = clampf(float(settings.deadzone), .08, .35)
	adapter.fixed_sticks = settings.fixed_sticks
	adapter.fire_toggle = settings.fire_toggle
	world.set_pickup_scale(float(settings.pickup_radius_scale))
	haptics.enabled = settings.haptics
	if not settings.haptics: haptics.stop()
	aim_assist.clear()
	if renderer != null:
		renderer.reduce_motion = settings.reduce_motion
		renderer.damage_numbers = settings.damage_numbers
		renderer.shake_scale = float(settings.shake_scale)
		renderer.hitstop = settings.hitstop
		renderer.flash_scale = float(settings.flash_scale)
		apply_runtime_quality()
		renderer.shape_cues = settings.shape_cues
		renderer.combat_text_scale = float(settings.combat_text_scale)

func apply_runtime_quality() -> void:
	if renderer == null:
		return
	renderer.particle_scale = clampf(float(settings.particle_scale) * quality.particle_scale, 0.0, 1.0)
	renderer.effect_limit = quality.effect_limit

func persist_settings() -> bool:
	settings.bindings = adapter.profile.bindings.duplicate(true)
	settings.touch_layout = adapter.layout.duplicate(true)
	settings.touch_sizes = adapter.control_sizes.duplicate(true)
	settings.control_scale = adapter.control_scale
	settings.control_opacity = adapter.control_opacity
	var previous = progress.data.settings.duplicate(true)
	progress.data.settings = settings.duplicate(true)
	if progress.save(): return true
	progress.data.settings = previous
	notice("设置暂未存下，请稍后重试。")
	return false

func back_to_settings() -> void:
	capture_action = ""
	persist_settings()
	screen = "settings"
	show_settings()

func _input(event_value: InputEvent) -> void:
	if event_value is InputEventScreenTouch and (not event_value.pressed or event_value.canceled): adapter.event(event_value)
	if event_value is InputEventScreenDrag and screen == "game" and not paused and adapter.fingers.has(event_value.index):
		adapter.event(event_value)
		get_viewport().set_input_as_handled()
		return
	if orientation.blocked:
		get_viewport().set_input_as_handled()
		return
	if online != null and online.handle_input(event_value):
		get_viewport().set_input_as_handled()
		return
	if capture_action.is_empty():
		if keyboard.handle(self, event_value): get_viewport().set_input_as_handled()
		return
	if event_value is InputEventMouseButton and event_value.pressed:
		var point = interface.get_global_transform_with_canvas().affine_inverse() * event_value.position
		if Rect2(96, 612, 1088, 66).has_point(point): return
	if event_value is InputEventKey and event_value.pressed and event_value.physical_keycode == KEY_ESCAPE:
		capture_action = ""
		ControlSettings.show_bindings(self, capture_device, capture_scroll)
		get_viewport().set_input_as_handled()
		return
	var candidate = adapter.Profile.from_event(event_value, capture_device)
	if not candidate.is_empty() and adapter.profile.assign(capture_device, capture_action, candidate):
		capture_action = ""
		adapter.clear()
		persist_settings()
		ControlSettings.show_bindings(self, capture_device, capture_scroll)
		get_viewport().set_input_as_handled()

func show_audio_settings() -> void:
	screen = "audio_settings"
	clear_modal()
	dim(.93)
	var sheet = panel(modal, Rect2(260, 35 if mobile_ui else 45, 760, 650 if mobile_ui else 620), UI.INSET, Color.TRANSPARENT)
	label(sheet, "声音", Rect2(36, 27, 603, 65), 38)
	var entries = [["音量", "master_volume", "volume-2"], ["音乐", "music_volume", "music"], ["音效", "effects_volume", "sparkles"]]
	for i in entries.size():
		var entry = entries[i]
		icon(sheet, entry[2], Rect2(38, 147 + i * 108, 28, 28), UI.JADE)
		label(sheet, entry[0], Rect2(86, 141 + i * 108, 122, 44), 23)
		var slider = HSlider.new()
		slider.set_meta("nav_id", str(entry[1]))
		slider.set_meta("nav_default", i == 0)
		slider.position = Vector2(237, 130 + i * 108)
		slider.size = Vector2(365, maxf(64, mobile_button_height) if mobile_ui else 64)
		slider.accessibility_name = entry[0]
		slider.min_value = 0
		slider.max_value = 1
		slider.step = .05
		slider.value = settings[entry[1]]
		var value_label = label(sheet, "%d%%" % roundi(slider.value * 100), Rect2(631, 141 + i * 108, 91, 43), 21, UI.MUTED)
		slider.value_changed.connect(func(value):
			settings[entry[1]] = value
			audio.set_levels(settings.master_volume, settings.music_volume, settings.effects_volume))
		slider.value_changed.connect(func(value): value_label.text = "%d%%" % roundi(value * 100))
		slider.drag_ended.connect(func(_changed): persist_settings())
		sheet.add_child(slider)
	button(sheet, "曲库随机" if settings.music_mode == "random" else "原主题音乐", Rect2(36, 450, 688, mobile_button_height if mobile_ui else 60), func():
		settings.music_mode = "score" if settings.music_mode == "random" else "random"
		audio.set_music_mode(settings.music_mode)
		persist_settings()
		show_audio_settings())
	icon_button(sheet, "收起 · 灯下设置", "arrow-left", Rect2(36, 554, 688, mobile_button_height if mobile_ui else 60), back_to_settings, false, "返回")

func show_inventory(page: String = "relics", selected_id: String = "") -> void:
	Modern.inventory(self, page, selected_id)

func show_credits() -> void:
	screen = "credits"
	clear_modal()
	dim(.94)
	label(modal, "香火债 · 灯下的名字", Rect2(154, 50, 970, 70), 40)
	label(modal, "字体：资源圆体、得意黑（OFL）。图标：Lucide（ISC / MIT）。引擎：Godot（MIT）。", Rect2(155, 140, 970, 62), 21, GOLD)
	var license_text = RichTextLabel.new()
	license_text.position = Vector2(155, 229)
	license_text.size = Vector2(970, 330)
	license_text.add_theme_font_override("normal_font", font)
	license_text.add_theme_font_size_override("normal_font_size", 17)
	license_text.text = FileAccess.get_file_as_string("res://assets/fonts/ResourceHanRounded-OFL.txt") + "\n\n" + FileAccess.get_file_as_string("res://assets/fonts/SmileySans-OFL.txt") + "\n\n" + FileAccess.get_file_as_string("res://assets/ui/icons/Lucide-LICENSE.txt") + "\n\n" + FileAccess.get_file_as_string("res://assets/fonts/OFL.txt") + "\n\n" + FileAccess.get_file_as_string("res://assets/licenses/Godot-THIRDPARTY.txt")
	license_text.selection_enabled = true
	license_text.focus_mode = Control.FOCUS_ALL
	license_text.set_meta("keyboard_editor", true)
	license_text.accessibility_name = "字体、图标与引擎许可"
	modal.add_child(license_text)
	button(modal, "回灯下设置", Rect2(662, 601, 463, mobile_button_height if mobile_ui else 54), back_to_settings, true)

func add_art(parent: Control, path: String, rect: Rect2) -> void:
	if not ResourceLoader.exists(path):
		return
	var art = TextureRect.new()
	art.texture = load(path)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = rect.position
	art.size = rect.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	if path.contains("/portraits/"): UI.round_texture(art, 16)

func show_checkpoint() -> void:
	dim(.85)
	label(modal, "借愿之后，也可以还愿。", Rect2(210, 166, 875, 80), 36)
	var story = ["我找不到债主。可账一直在响。", "这笔已经还过。他们把‘还’抄到了‘借’那一栏。", "总账停了。愿的归处，由你选择。"]
	label(modal, story[clampi(int(world.run.floor) - 1, 0, 2)], Rect2(210, 241, 880, 48), 20, GOLD)
	for i in world.run.contracts.size():
		var entry = world.run.contracts[i]
		var debt = world.db.row("debt_contracts", entry.id)
		var repayment = button(modal, "%s · %d纸钱偿还" % [debt.name, int(debt.repay_price) + int(entry.interest)], Rect2(210, 300 + i * 80, 850, 50), func(): world.repay(i); flush_events(); ui_signature = "")
		repayment.disabled = int(world.run.coins) < int(debt.repay_price) + int(entry.interest)
		repayment.set_meta("nav_id", "repay_" + str(i))
	button(modal, "去下一层", Rect2(719, 550, 341, 50), func(): world.advance_room(); flush_events(); ui_signature = "", true).set_meta("nav_default", true)

func show_result() -> void:
	Modern.result(self)

func show_run_review(page: String = "damage", selected_index: int = -1) -> void:
	RunReview.show(self, page, selected_index)

func show_endings() -> void:
	paused = true
	screen = "endings"
	hud.visible = false
	adapter.clear()
	clear_modal()
	Hub.endings(self)

func show_hub(page: String = "wishes") -> void:
	remember_parent("hub")
	npc_line_index = npc_line_index + 1 if hub_page == page else 0
	hub_page = page
	paused = true
	screen = "hub"
	hud.visible = false
	renderer.hub = true
	adapter.clear()
	clear_modal()
	audio.set_paused(false)
	Hub.draw(self, page)

func show_story_page(page: Dictionary) -> void:
	if not story.available(page, progress.data): return
	remember_parent("story")
	paused = true
	screen = "story"
	adapter.clear()
	clear_modal()
	dim(.9)
	var sheet = panel(modal, Rect2(184, 83, 912, 543), Color("30372f"))
	label(sheet, "旧愿 / " + progress.data.wish_name, Rect2(36, 25, 834, 35), 18, GOLD)
	label(sheet, page.title, Rect2(36, 84, 834, 59), 34)
	reading_text(sheet, page.lines, Rect2(36, 167, 834, 256))
	label(sheet, "滚轮 / 触屏拖动 · 方向键翻读", Rect2(36, 452, 443, 45), 17, GOLD)
	button(sheet, "收进愿簿", Rect2(504, 441, 370, 64 if mobile_ui else 51), func(): return_to_parent("story"), true)
	if not progress.data.read_story_ids.has(page.id):
		progress.data.read_story_ids.append(page.id)
		progress.save()

func begin_training(boss_id: String = "", phase: int = 0, preview_skill: String = "") -> void:
	if shop_trial.active(): end_shop_trial(false)
	var character = world.db.row("characters", selected)
	if character.is_empty() or (not preview_skill.is_empty() and not character.skills.has(preview_skill)): return
	world.start(selected, 1472, 1, {"relic_pool": progress.relic_pool(), "weapon": starting_weapon(selected)})
	world.run.training = true
	world.run.training_boss = boss_id
	world.run.training_phase = phase
	world.run.training_preview_skill = preview_skill
	if not preview_skill.is_empty():
		world.player.skill = preview_skill
		world.player.energy = 100.0
		world.player.pos = Vector2(640, 490)
	world.enemies.clear()
	if boss_id.is_empty():
		var positions = [Vector2(520, 330), Vector2(640, 270), Vector2(760, 330), Vector2(640, 390)]
		for i in 4:
			var dummy = world.spawn_enemy("e01", positions[i] if not preview_skill.is_empty() else Vector2(440 + i * 105, 340))
			dummy.attack_cd = 99999.0
			dummy.speed = 0.0
			if not preview_skill.is_empty():
				dummy.hp = 180.0
				dummy.max_hp = 180.0
				world.add_mark(dummy, 3)
		world.update_chains()
	else:
		var boss = world.spawn_boss(boss_id)
		boss.phase = phase
		boss.hp = boss.max_hp * (1.0 - float(phase) / 3.0 - .04)
		if phase > 0:
			world.enemies = world.enemies.filter(func(e): return e.boss)
			world.room_flags.summoned = 0
			BossPattern.phase_enter(world, boss, phase)
	world.player.invulnerable = 99999.0
	renderer.world = world
	renderer.hub = false
	renderer.visual_effects.clear()
	renderer.animation.clear()
	renderer.weapon_motion.clear()
	aim_assist.clear()
	ui_signature = ""
	hud.visible = true
	resume_game()

func bind_world(value) -> void:
	world = value
	renderer.world = world
	renderer.hub = false
	for child in hud.get_children():
		if child is GameHud: child.world = world
	renderer.visual_effects.clear()
	renderer.animation.clear()
	renderer.weapon_motion.clear()
	adapter.clear()
	aim_assist.clear()
	haptics.stop()
	ui_signature = ""

func begin_shop_trial(index: int) -> void:
	var trial = shop_trial.begin(world, index)
	if trial == null: return
	shop_trial_choice = mobile_choice
	bind_world(trial)
	notice_left = 0.0
	resume_game()

func reset_training() -> void:
	if shop_trial.active():
		var trial = shop_trial.reset()
		if trial != null:
			bind_world(trial)
			resume_game()
	else:
		begin_training(world.run.get("training_boss", ""), world.run.get("training_phase", 0), world.run.get("training_preview_skill", ""))

func end_shop_trial(return_to_shop: bool = true) -> void:
	if not shop_trial.active(): return
	shop_trial_focus = shop_trial.index
	bind_world(shop_trial.finish())
	mobile_choice = shop_trial_choice
	notice_left = 0.0
	if return_to_shop:
		paused = false
		screen = "game"
		sync_game_modal()

func save_current_run() -> bool:
	if online != null and online.active(): return true
	var saving_world = shop_trial.origin if shop_trial.active() else world
	if not saving_world.run.is_empty() and not saving_world.run.get("training", false):
		var candidate = saving_world.snapshot()
		if store.write(candidate):
			checkpoint = candidate
			return true
		notice("这一页未能存下，请重试后再离开。")
		return false
	return true

func reload_save_session() -> void:
	progress.data = save_session.current.profile.duplicate(true)
	checkpoint = save_session.current.checkpoint.duplicate(true)
	world = World.new()
	renderer.world = world
	for child in hud.get_children():
		if child is GameHud: child.world = world
	renderer.visual_effects.clear()
	renderer.animation.clear()
	renderer.weapon_motion.clear()
	adapter.clear()
	haptics.stop()
	selected = "c_paper"
	selected_weapon = ""
	settings = DEFAULT_SETTINGS.duplicate(true)
	for key in settings:
		settings[key] = progress.data.settings.get(key, settings[key])
	settings.touch = settings.touch or OS.get_name() in ["Android", "iOS"]
	adapter.configure(settings)
	apply_control_settings()
	audio.set_muted(settings.muted)
	audio.set_levels(settings.master_volume, settings.music_volume, settings.effects_volume)
	paused = true
	ui_signature = ""

func show_replacement() -> void:
	dim(.88)
	label(modal, "愿簿已满 · 为新供物留一格", Rect2(76, 69, 1120, 76), 35)
	var pending = world.run.replacement.choice
	var incoming = world.db.row("debt_contracts", pending.id).reward if pending.kind == "contract" else pending.id
	label(modal, "取走「%s」时，需要换出一件旧供物。" % world.db.name_of("relics", incoming), Rect2(77, 146, 1100, 43), 20, GOLD)
	var ids = world.run.relics.keys()
	for i in ids.size():
		var id = ids[i]
		var x = 76 + (i % 4) * 287
		var y = 216 + int(i / 4) * 125
		var item = button(modal, "", Rect2(x, y, 269, 110), func():
			if mobile_ui: show_replacement_confirmation(id)
			else: world.replace_relic(id); flush_events(); ui_signature = "")
		item.set_meta("nav_id", "replace_" + str(id))
		item.accessibility_name = "换出" + world.db.name_of("relics", id)
		add_art(item, "res://assets/relics/" + id + ".png", Rect2(9, 11, 82, 82))
		label(item, "%s\n×%d" % [world.db.name_of("relics", id), world.stack(id)], Rect2(103, 22, 151, 73), 18)
	button(modal, "留着旧愿 · 取消", Rect2(860, 604 if mobile_ui else 623, 334, mobile_button_height if mobile_ui else 48), func(): world.replace_relic(); flush_events(); ui_signature = "", true)

func return_to_replacement() -> void:
	screen = "game"
	paused = false
	adapter.clear()
	ui_signature = ""
	clear_modal()
	sync_game_modal()

func show_replacement_confirmation(old_id: String) -> void:
	if world.mode != "replace" or not world.run.relics.has(old_id): return
	paused = true
	screen = "replacement_confirm"
	adapter.clear()
	clear_modal()
	dim(.88)
	var pending = world.run.replacement.choice
	var incoming = world.db.row("debt_contracts", pending.id).reward if pending.kind == "contract" else pending.id
	var sheet = panel(modal, Rect2(140, 94, 1000, 544), UI.SURFACE)
	label(sheet, "换出旧愿", Rect2(26, 15, 948, 54), 32)
	for i in 2:
		var id = old_id if i == 0 else incoming
		var row = world.db.row("relics", id)
		var card = panel(sheet, Rect2(26 + i * 490, 82, 458, 310), UI.INSET)
		card.set_meta("replacement_preview", id)
		add_art(card, "res://assets/relics/" + id + ".png", Rect2(18, 18, 86, 86))
		label(card, row.name, Rect2(120, 18, 316, 68), 26)
		label(card, "换出 ×%d" % world.stack(id) if i == 0 else "获得", Rect2(120, 84, 316, 40), 20, GOLD if i == 0 else UI.JADE)
		reading_text(card, [str(row.get("behavior", ""))], Rect2(18, 139, 422, 145))
	button(sheet, "返回选择", Rect2(26, 432, 458, mobile_button_height), return_to_replacement)
	var confirm = button(sheet, "确认替换", Rect2(516, 432, 458, mobile_button_height), func():
		if world.replace_relic(old_id):
			flush_events()
			return_to_replacement(), true)
	confirm.set_meta("replacement_confirm", old_id)

func notice(text: String) -> void:
	notice_label.text = text
	notice_left = 3.0

func _unhandled_input(event_value: InputEvent) -> void:
	if orientation.blocked: return
	if adapter.profile.event_matches("pause", event_value):
		go_back()
		return
	if adapter.profile.event_matches("map", event_value) and screen == "game":
		RouteMap.show_sheet(self)
		return
	if adapter.profile.event_matches("inventory", event_value) and screen == "game":
		show_inventory()
		return
	if adapter.profile.event_matches("fullscreen", event_value):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if event_value is InputEventJoypadButton and event_value.pressed:
		adapter.last_device = "controller"
		if event_value.button_index == JOY_BUTTON_B and screen in ["pause", "run_history", "achievements", "inventory", "tutorial", "route", "hub", "story", "settings", "controls", "assistance", "touch_layout", "saves", "save_paste", "save_preview"]:
			go_back()
			return
	if event_value is InputEventKey and event_value.pressed and not event_value.echo:
		if event_value.physical_keycode == KEY_ESCAPE:
			go_back()
			return
		if screen == "game" and world.mode in ["choice", "shop", "debt"]:
			var index = ChoiceShortcuts.index_for(event_value)
			if index >= 0 and index < world.choices.size():
				if mobile_ui:
					mobile_choice = index
					clear_modal()
					show_choices()
				else:
					choose_index(index)
				get_viewport().set_input_as_handled()
			return
	if screen == "game" and not paused and world.mode in ["combat", "clear"]:
		adapter.event(event_value)

func on_focus_lost() -> void:
	if qa_active:
		return
	if audio != null: audio.set_suspended(true)
	adapter.clear()
	haptics.stop()
	aim_assist.clear()
	if online != null and online.active():
		online.focus_lost()
		return
	if screen == "game" and not world.run.is_empty():
		save_current_run()
		show_pause("这页账已存下，准备好再继续。")

func go_back() -> void:
	if orientation.blocked: return
	if mobile_ui and DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.virtual_keyboard_get_height() > 0:
		hide_mobile_keyboard()
		return
	if online != null and online.active():
		online.back()
		return
	if screen == "touch_trial":
		for child in get_children():
			if child.has_meta("touch_trial"): child.finish(); return
	if screen == "replacement_confirm": return_to_replacement(); return
	if screen == "seed_input": show_menu("characters"); return
	if screen == "cinematic": show_pause(); return
	if shop_trial.active() and screen in ["game", "pause"]:
		end_shop_trial()
		return
	if screen == "game" and world.run.get("training", false):
		var preview = str(world.run.get("training_preview_skill", ""))
		if not preview.is_empty(): show_character_details(preview)
		else: show_hub("training")
		return
	if screen in ["controls", "assistance", "touch_layout", "audio_settings", "credits"]:
		if screen == "touch_layout": persist_settings()
		back_to_settings()
		return
	if screen in ["save_preview", "save_paste"]:
		save_import_draft = {}
		SaveUI.show(self)
		return
	if screen == "saves":
		back_to_settings()
		return
	if screen == "focus_help":
		return_to_parent("focus_help")
		return
	if screen in ["run_build", "inventory"]:
		return_to_parent("inventory")
		return
	if screen == "run_review":
		show_result()
		return
	if screen in ["new_run_confirm", "quit_confirm"]:
		cancel_confirmation()
		return
	if screen == "menu":
		match menu_page:
			"splash": request_quit()
			"files": show_menu("splash")
			"title": show_menu("files")
			"characters": show_menu("challenges" if selected_run_kind == "daily" else "title")
			"loadout": show_menu("characters")
			"items", "bestiary", "ending_archive", "statistics": show_menu("stats")
			"ending_view": show_menu("ending_archive")
			_: show_menu("title")
		return
	if screen == "achievements":
		return_to_parent("achievements")
	elif screen == "run_history": show_pause()
	elif screen in ["pause", "tutorial", "route"]: resume_game()
	elif screen == "game": show_pause()
	elif screen == "story": return_to_parent("story")
	elif screen == "hub": return_to_parent("hub")
	elif screen == "character": show_menu("characters")
	elif screen == "result": show_menu("title")
	elif screen == "settings":
		persist_settings()
		return_to_parent("settings")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		confirm_quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED and not qa_active:
		on_focus_lost()
	elif what == NOTIFICATION_APPLICATION_RESUMED and not qa_active:
		if audio != null: audio.set_suspended(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()

func qa_step() -> void:
	if qa_capture_busy: return
	qa_tick += 1
	if qa_tick == 12:
		capture("menu")
	elif qa_tick == 14:
		var main_actions = screen == "menu" and menu_page == "title" and qa_button(modal, "继续") != null and qa_button(modal, "新局") != null and qa_button(modal, "记录") != null
		show_menu("files")
		var separate_slots = qa_find_meta(modal, "save_slot", "1") != null and qa_find_meta(modal, "save_slot", "2") != null and qa_find_meta(modal, "save_slot", "3") != null
		qa_interaction_checks.append({"name": "the title sheet keeps save slots in their own layer before the main new run, continue and stats actions", "passed": main_actions and separate_slots})
		show_menu("title")
	elif qa_tick == 30:
		begin_run("c_bell", 7193, false)
		world.enemies.clear()
		world.player.pos = Vector2(650, 490)
		world.player.invulnerable = 30.0
		for i in 4:
			var enemy = world.spawn_enemy(["e01", "e03", "e07", "e04"][i], Vector2(455 + i * 115, 327 + (i % 2) * 35))
			enemy.attack_cd = 15.0
			world.add_mark(enemy, 3)
		world.update_chains()
	elif qa_tick == 33:
		capture("chains")
	elif qa_tick == 48:
		world.cast_skill()
		flush_events()
	elif qa_tick == 50:
		capture("detonate")
	elif qa_tick == 66:
		world.run.room = 2
		world.enter_room()
		flush_events()
		ui_signature = ""
	elif qa_tick == 71:
		capture("choices")
	elif qa_tick == 86:
		world.run.room = 10
		world.enter_room()
		world.player.invulnerable = 30.0
		adapter.touch_mode = true
		world.enemies[0].attack_cd = 20.0
		world.enemies[0].windup = .8
		world.add_mark(world.enemies[0], 3)
		ui_signature = ""
	elif qa_tick == 90:
		capture("boss-touch")
	elif qa_tick == 106:
		world.run.relics = {"r01": 1, "r09": 2, "r17": 1, "r25": 1, "r33": 1, "r41": 1}
		world.run.talents = ["t_thread_1a", "t_ash_1b", "t_ink_1a"]
		show_inventory()
	elif qa_tick == 111:
		capture("inventory")
	elif qa_tick == 126:
		show_settings()
	elif qa_tick == 131:
		capture("settings")
	elif qa_tick == 146:
		world.run.room = 3
		world.enter_room()
		world.geometry.build("room_pillars_2")
		world.geometry.rebuild_flow(world.player.pos)
		adapter.touch_mode = false
		world.player.invulnerable = 30.0
		resume_game()
	elif qa_tick == 151:
		capture("obstacles")
	elif qa_tick == 164:
		world.run.relics.clear()
		world.run.room = 4
		world.enter_room()
		ui_signature = ""
	elif qa_tick == 169:
		capture("debt")
	elif qa_tick == 180:
		world.mode = "checkpoint"
		world.run.floor = 1
		world.run.room = 10
		world.advance_room()
		ui_signature = ""
	elif qa_tick == 186:
		capture("evolution")
	elif qa_tick == 189:
		qa_key(KEY_2)
		qa_interaction_checks.append({"name": "the PC number row directly commits the second skill evolution without an extra Enter press", "passed": world.run.evolved and world.player.skill == "s06" and world.mode == "combat"})
	elif qa_tick == 194:
		world.take_choice(0)
		world.run.room = 6
		world.enter_room()
		world.player.invulnerable = 30.0
		ui_signature = ""
	elif qa_tick == 200:
		capture("coin-vault")
	elif qa_tick == 208:
		world.run.floor = 3
		world.run.room = 10
		world.enter_room()
		world.player.invulnerable = 30.0
		ui_signature = ""
	elif qa_tick == 214:
		capture("ownerless-temple")
	elif qa_tick == 223:
		show_hub()
	elif qa_tick == 229:
		capture("hub")
	elif qa_tick == 237:
		show_hub("personal")
	elif qa_tick == 243:
		capture("personal")
	elif qa_tick == 251:
		clear_modal()
		renderer.hub = false
		show_endings()
	elif qa_tick == 257:
		capture("endings")
	elif qa_tick == 265:
		world.enemies.clear()
		world.run.floor = 1
		world.run.room = 3
		world.run.visited = [0, 1, 2]
		world.run.graph = World.Graph.build(World.RunRng.new(7145), 1, [])
		world.run.room_plan = world.run.graph.types.duplicate()
		world.mode = "clear"
		RouteMap.show_sheet(self)
	elif qa_tick == 271:
		capture("route")
	elif qa_tick == 279:
		mobile_ui = true
		mobile_button_height = 90
		begin_run("c_bell", 7145, false)
		world.run.room = world.run.room_plan.find("reward")
		world.enter_room()
		adapter.touch_mode = true
		screen = "game"
		paused = false
		ui_signature = ""
		clear_modal()
	elif qa_tick == 285:
		capture("mobile-choice")
	elif qa_tick == 293:
		show_settings()
	elif qa_tick == 299:
		capture("mobile-settings")
	elif qa_tick == 307:
		show_audio_settings()
	elif qa_tick == 313:
		capture("audio-mix")
	elif qa_tick == 321:
		mobile_ui = false
		show_story_page(story.content.pages[0])
	elif qa_tick == 327:
		capture("story")
	elif qa_tick == 335:
		selected = "c_paper"
		begin_training("b01", 2)
	elif qa_tick == 341:
		capture("training-phase3")
	elif qa_tick == 349:
		begin_run("c_paper", 8141, false)
		world.run.room = 3
		world.run.contracts = [{"id": "d02", "interest": 0}]
		world.enter_room()
		world.enemies = world.enemies.slice(0, 2)
		world.enemies[0].pos = Vector2(530, 330)
		world.enemies[1].pos = Vector2(730, 330)
		world.time = 3.1
		world.update_enemies(.001)
		world.time += .4
		flush_events()
		paused = true
		clear_modal()
	elif qa_tick == 355:
		capture("debt-warning")
	elif qa_tick == 363:
		mobile_ui = true
		mobile_button_height = 90
		world.run.visited = [0, 1, 2]
		world.mode = "clear"
		RouteMap.show_sheet(self)
	elif qa_tick == 369:
		capture("mobile-route")
	elif qa_tick == 377:
		mobile_ui = false
		show_animation_gallery()
	elif qa_tick == 383:
		capture("animation-sheet")
	elif qa_tick == 395:
		qa_verify_assets()
	elif qa_tick == 400:
		ControlSettings.show_bindings(self, "keyboard", 392)
	elif qa_tick == 401:
		var target = qa_button(modal, "右键 / Q")
		if target != null: target.grab_focus()
	elif qa_tick == 402:
		qa_key(KEY_ENTER)
		qa_interaction_checks.append({"name": "focused binding button opens capture through native GUI input", "passed": capture_action == "skill"})
	elif qa_tick == 403:
		qa_key(KEY_J)
		qa_interaction_checks.append({"name": "capture consumes the new key and updates the visible binding", "passed": capture_action.is_empty() and adapter.profile.hint("skill") == "J"})
		var stored = progress.store.read()
		qa_interaction_checks.append({"name": "GUI binding commit reaches the profile journal", "passed": int(stored.get("settings", {}).get("bindings", {}).get("keyboard", {}).get("skill", {}).get("code", 0)) == KEY_J})
	elif qa_tick == 406:
		capture("controls-mapping")
	elif qa_tick == 414:
		ControlSettings.show_bindings(self, "controller", 784)
	elif qa_tick == 420:
		capture("controls-pad")
	elif qa_tick == 428:
		mobile_ui = true
		ControlSettings.show_assistance(self)
	elif qa_tick == 434:
		capture("assistance")
	elif qa_tick == 442:
		ControlSettings.show_layout(self)
	elif qa_tick == 448:
		capture("touch-layout")
	elif qa_tick == 456:
		mobile_ui = false
	elif qa_tick == 458:
		ControlSettings.show_assistance(self, 1224)
	elif qa_tick in [459, 460]:
		var action = qa_setting_button(modal, "story_text_scale")
		if action != null:
			action.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 462:
		qa_interaction_checks.append({"name": "GUI narrative sizing reaches 150 percent and persists", "passed": is_equal_approx(float(settings.story_text_scale), 1.5) and is_equal_approx(float(progress.store.read().settings.story_text_scale), 1.5)})
	elif qa_tick == 464:
		capture("reading-settings")
	elif qa_tick == 466:
		progress.data.personal.c_paper.stage = 3
		show_story_page(story.content.pages.filter(func(page): return page.id == "story.personal.c_paper")[0])
	elif qa_tick == 469:
		var reader = modal.find_child("NarrativeReader", true, false)
		var paragraphs = reader.get_child(0) if reader != null else null
		qa_interaction_checks.append({"name": "large narrative body uses the rounded game font in a fixed clipped viewport", "passed": paragraphs != null and paragraphs.get_child(0).get_theme_font_size("font_size") == 33 and paragraphs.get_child(0).get_theme_font("font") == font and reader.clip_contents and reader.position.y + reader.size.y < 441})
		if reader != null:
			reader.grab_focus()
			qa_key(KEY_DOWN)
			qa_interaction_checks.append({"name": "keyboard navigation scrolls enlarged narrative without moving its close button", "passed": reader.scroll_vertical > 0})
			reader.scroll_vertical = 0
	elif qa_tick == 470:
		capture("story-large")
	elif qa_tick == 474:
		resume_game()
		mobile_ui = true
		qa_surface = Vector2i(720, 1280)
		qa_rotation_time = world.time
		update_orientation()
		qa_key(KEY_ESCAPE)
	elif qa_tick == 476:
		qa_interaction_checks.append({"name": "portrait guard clears touch capture and holds simulation despite menu input", "passed": orientation.blocked and orientation_overlay.visible and paused and adapter.move_id == -1 and adapter.aim_id == -1 and world.time == qa_rotation_time and screen == "game"})
	elif qa_tick == 478:
		capture("rotation-guard")
	elif qa_tick == 480:
		qa_surface = Vector2i(1280, 720)
		update_orientation()
		qa_interaction_checks.append({"name": "landscape restoration waits at explicit pause rather than firing or advancing", "passed": not orientation.blocked and not orientation_overlay.visible and paused and screen == "pause" and world.time == qa_rotation_time})
	elif qa_tick == 482:
		qa_surface = Vector2i.ZERO
		mobile_ui = false
	elif qa_tick == 488:
		begin_run("c_bell", 6327, false)
		world.run.room = 0
		world.enemies.clear()
		for i in 8:
			var enemy = world.spawn_enemy("e%02d" % (i * 3 + 1), Vector2(305 + (i % 4) * 220, 280 + int(i / 4) * 180))
			enemy.hp = 10000
			enemy.mark = 3
			enemy.mark_until = 1000
		world.player.invulnerable = 1000
		adapter.clear()
		audio.set_muted(true)
	elif qa_tick >= 490 and qa_tick < 680:
		while world.bullets.size() < 240:
			world.enemy_bullet(Vector2(230 + (world.bullets.size() % 22) * 38, 190 + int(world.bullets.size() / 22) * 30), Vector2.RIGHT.rotated(world.bullets.size() * .7), 110)
	elif qa_tick == 690:
		begin_run("c_bell", 7193, false)
		world.run.floor = 2
		world.run.graph = World.Graph.build(World.RunRng.new(7193 + 802), 2, [])
		world.run.room_plan = world.run.graph.types.duplicate()
		world.run.room = 5
		world.enter_room()
		paused = true
		clear_modal()
		for enemy in world.enemies.duplicate(): world.kill_enemy(enemy, "primary")
		world.tick({})
		flush_events()
	elif qa_tick == 695:
		capture("wave-incoming")
	elif qa_tick == 702:
		for i in 85: world.tick({})
		flush_events()
	elif qa_tick == 708:
		capture("wave-arrival")
	elif qa_tick == 716:
		var seed_value = 0
		for candidate in 100:
			if World.Graph.build(World.RunRng.new(candidate + 401), 1, []).types.has("secret"):
				seed_value = candidate
				break
		begin_run("c_paper", seed_value, false)
		world.run.room = 2
		world.enter_room()
		world.skip_choice()
		world.run.visited = [0, 1]
		flush_events()
		ui_signature = ""
	elif qa_tick == 718:
		RouteMap.show_sheet(self)
		qa_interaction_checks.append({"name": "route GUI omits the physically undiscovered secret node", "passed": qa_button(modal, "断绳") == null})
	elif qa_tick == 722:
		resume_game()
	elif qa_tick == 730:
		capture("secret-clue")
	elif qa_tick == 735:
		world.advance_room(3)
		for enemy in world.enemies.duplicate(): world.kill_enemy(enemy, "primary")
		world.tick({})
		while world.mode == "choice": world.skip_choice()
		flush_events()
		qa_exploration_state.coins = int(world.run.coins)
		qa_exploration_state.cleared = int(world.run.cleared)
		RouteMap.show_sheet(self)
		var back = qa_button(modal, "已行 · 供物")
		if back != null:
			back.grab_focus()
			qa_key(KEY_ENTER)
		var before_walk = int(world.run.room)
		var return_doors = world.room_doors().filter(func(door): return int(door.destination) == 2)
		if not return_doors.is_empty():
			var return_door = return_doors[0]
			var return_direction = world.direction_vector(str(return_door.direction))
			world.player.pos = return_door.pos - return_direction * 42
			world.tick({"move": return_direction, "aim": return_direction})
		qa_exploration_state.route_map_room_before_walk = before_walk
	elif qa_tick == 736:
		qa_interaction_checks.append({"name": "the route map is read-only and a physical walk into the selected door performs the actual cleared-room return", "passed": qa_exploration_state.route_map_room_before_walk == 3 and world.run.room == 2 and world.mode == "clear" and world.enemies.is_empty() and world.run.coins == qa_exploration_state.coins and world.run.cleared == qa_exploration_state.cleared})
	elif qa_tick == 738:
		capture("door-navigation")
	elif qa_tick == 739:
		qa_exploration_state.merit = int(progress.data.merit)
		world.player.pos = world.secret_entry().pos
		world.tick({}, .46)
		flush_events()
		var saved = store.read()
		qa_interaction_checks.append({"name": "physical reveal checkpoints its room ID without granting account merit", "passed": saved.run.graph.revealed.any(func(room): return int(room) == int(world.secret_entry().room)) and int(progress.data.merit) == qa_exploration_state.merit})
	elif qa_tick == 742:
		capture("secret-open")
	elif qa_tick == 745:
		RouteMap.show_sheet(self)
		var entry_button = qa_button(modal, "断绳")
		qa_interaction_checks.append({"name": "physical reveal enables the actual secret route button", "passed": entry_button != null and not entry_button.disabled})
	elif qa_tick == 748:
		capture("secret-route")
	elif qa_tick == 752:
		resume_game()
		qa_key(KEY_E)
	elif qa_tick == 754:
		qa_interaction_checks.append({"name": "native interaction key traverses the revealed physical entry into real reward choices", "passed": world.room_type() == "secret" and world.mode == "choice" and world.choices.any(func(choice): return choice.id == "interest")})
	elif qa_tick == 757:
		capture("secret-room")
	elif qa_tick == 761:
		world.skip_choice()
		world.advance_room(2)
		world.player.pos = world.secret_entry().pos
		flush_events()
		mobile_ui = true
		adapter.touch_mode = true
		qa_exploration_state.coins = int(world.run.coins)
		qa_exploration_state.cleared = int(world.run.cleared)
		ui_signature = ""
	elif qa_tick == 767:
		capture("mobile-secret-entry")
	elif qa_tick == 772:
		var entry_action = qa_button(modal, "拂绳 · 入断页")
		if entry_action != null:
			entry_action.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 775:
		qa_interaction_checks.append({"name": "mobile entry action safely returns to a visited secret without awarding it twice", "passed": world.room_type() == "secret" and world.mode == "clear" and world.choices.is_empty() and world.run.coins == qa_exploration_state.coins and world.run.cleared == qa_exploration_state.cleared})
	elif qa_tick == 782:
		mobile_ui = false
		settings.touch = false
		adapter.touch_mode = false
		SaveUI.show(self)
		qa_exploration_state.before_transfer = save_session.portable_bundle()
		qa_exploration_state.incoming = save_session.portable_bundle()
		qa_exploration_state.incoming.profile.merit += 7
	elif qa_tick == 785:
		capture("save-transfer")
	elif qa_tick == 790:
		var entry = qa_button(modal, "粘贴并预览")
		if entry != null:
			entry.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 793:
		capture("save-paste")
	elif qa_tick == 795:
		var text = modal.find_child("SaveTransferText", true, false)
		if text != null: text.text = SaveUI.Transfer.export_code(qa_exploration_state.incoming)
		var preview_action = qa_button(modal, "预览愿簿")
		if preview_action != null:
			preview_action.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 799:
		qa_interaction_checks.append({"name": "real transfer text field previews a checked incoming save without committing it", "passed": screen == "save_preview" and save_import_draft.get("profile", {}).get("merit", -1) == qa_exploration_state.incoming.profile.merit and save_session.current.profile.merit == qa_exploration_state.before_transfer.profile.merit})
	elif qa_tick == 803:
		capture("save-preview")
	elif qa_tick == 807:
		var cancel = qa_button(modal, "保留现在的愿簿")
		if cancel != null:
			cancel.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 811:
		qa_interaction_checks.append({"name": "canceling transfer preview keeps both original progress and its run", "passed": screen == "saves" and save_import_draft.is_empty() and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_transfer)})
		SaveUI.inspect(self, SaveUI.Transfer.inspect_text(SaveUI.Transfer.export_text(qa_exploration_state.incoming)))
	elif qa_tick == 815:
		var confirm = qa_button(modal, "确认换入愿簿")
		if confirm != null:
			confirm.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 819:
		qa_interaction_checks.append({"name": "focused import confirmation commits paired progress while returning safely to the title", "passed": screen == "menu" and paused and world.run.is_empty() and progress.data.merit == qa_exploration_state.incoming.profile.merit and checkpoint.run.id == qa_exploration_state.incoming.checkpoint.run.id and save_session.current.backup.profile.merit == qa_exploration_state.before_transfer.profile.merit})
		var resume = qa_button(modal, "继续")
		if resume != null:
			resume.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 823:
		qa_interaction_checks.append({"name": "resuming an imported real room waits for confirmation with no automatic attack or simulation", "passed": screen == "pause" and paused and world.run.id == qa_exploration_state.incoming.checkpoint.run.id and is_equal_approx(world.time, qa_exploration_state.incoming.checkpoint.time) and not adapter.fire_latched})
		qa_interaction_checks.append({"name": "after real import the existing HUD reads the restored world rather than stale character, health, currency and skill state", "passed": qa_hud_current()})
		SaveUI.show(self)
		var restore = qa_button(modal, "回到导入前")
		if restore != null:
			restore.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 827:
		var confirm = qa_button(modal, "确认恢复")
		if confirm != null:
			confirm.grab_focus()
			qa_key(KEY_ENTER)
	elif qa_tick == 831:
		qa_interaction_checks.append({"name": "real undo confirmation restores the original account and room together", "passed": screen == "menu" and paused and world.run.is_empty() and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_transfer) and save_session.current.backup.is_empty()})
		qa_interaction_checks.append({"name": "restoring the pre-import backup rebinds both world renderer and the existing HUD to the same live world", "passed": qa_hud_current() and renderer.world == world})
		var export_path = qa_directory.path_join("qa-transfer.incense.json")
		var wrote = SaveUI.Transfer.write_file(export_path, save_session.portable_bundle())
		var read_back = SaveUI.Transfer.read_file(export_path)
		qa_interaction_checks.append({"name": "native shipping code exports and rereads the complete checked file format", "passed": wrote and read_back.ok and qa_same_save(read_back.get("data", {}), save_session.portable_bundle()), "write_ok": wrote, "read_ok": read_back.ok, "read_message": read_back.get("message", ""), "equal_bundle": qa_same_save(read_back.get("data", {}), save_session.portable_bundle())})
		mobile_ui = true
		SaveUI.show(self)
	elif qa_tick == 835:
		capture("mobile-save-transfer")
	elif qa_tick == 839:
		SaveUI.inspect(self, SaveUI.Transfer.inspect_text(SaveUI.Transfer.export_text(qa_exploration_state.incoming)))
	elif qa_tick == 843:
		capture("mobile-save-preview")
	elif qa_tick == 847:
		qa_key(KEY_ESCAPE)
	elif qa_tick == 851:
		var confirm = qa_button(modal, "回灯下设置")
		qa_interaction_checks.append({"name": "mobile transfer preview back action clears the draft and preserves progress with usable controls", "passed": screen == "saves" and save_import_draft.is_empty() and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_transfer) and confirm != null and confirm.size.y >= 64})
	elif qa_tick in [855, 863, 871, 879, 887, 895]:
		var page = 1 if qa_tick in [863, 879, 895] else 0
		var direction = "up" if qa_tick in [871, 879] else ("left" if qa_tick == 887 else ("right" if qa_tick == 895 else "down"))
		show_weapon_gallery(page, direction)
	elif qa_tick in [859, 867, 875, 883, 891, 899]:
		capture({859: "held-tools-1", 867: "held-tools-2", 875: "held-tools-back-1", 883: "held-tools-back-2", 891: "held-tools-left", 899: "held-tools-right"}[qa_tick])
	elif qa_tick in [903, 911]:
		show_weapon_gallery(1 if qa_tick == 903 else 0, "left" if qa_tick == 903 else "right")
	elif qa_tick in [907, 915]:
		capture("held-tools-left-2" if qa_tick == 907 else "held-tools-right-1")
	elif qa_tick == 919:
		mobile_ui = false
		begin_run("c_ink", 4191, false)
		world.player.weapon = "w11"
		world.player.aim = Vector2.RIGHT
		world.player.shot_cd = 0
		world.shoot_input(true, .16)
		paused = true
		flush_events()
		clear_modal()
	elif qa_tick == 923:
		capture("held-brush-charge")
	elif qa_tick == 927:
		world.shoot_input(true, .1)
		flush_events()
		world.time += .08
	elif qa_tick == 931:
		capture("held-brush-fire")
		var shot_motion = renderer.weapon_motion.sample(world, false)
		qa_interaction_checks.append({"name": "the live shot direction selects the matching right-facing body, hand rig and muzzle presentation", "passed": renderer.facing(Vector2(shot_motion.aim)) == "right" and renderer.facing(Vector2(world.player.last_shot_direction)) == "right" and world.bullets.any(func(b): return b.friendly and b.dir.x > .9)})
	elif qa_tick == 943:
		mobile_ui = false
		settings.touch = false
		adapter.touch_mode = false
		begin_run("c_bell", 7184, false)
		world.player.invulnerable = 30
		world.run.relics = {"r01": 1, "r09": 2, "r17": 1, "r25": 1, "r33": 1, "r41": 1}
	elif qa_tick == 946:
		qa_click(qa_button(hud, "愿簿"))
	elif qa_tick == 950:
		qa_interaction_checks.append({"name": "pointer click on the icon-only HUD book opens the paused inventory with a named control", "passed": screen == "inventory" and paused and not hud.visible and not qa_button(hud, "愿簿").accessibility_name.is_empty()})
		qa_exploration_state.before_item_pick = world.snapshot()
		qa_click(qa_find_meta(modal, "item_id", "r09"))
	elif qa_tick == 955:
		qa_interaction_checks.append({"name": "selecting an offering icon exposes its correct detail without changing the paused run", "passed": qa_find_meta(modal, "detail_item_id", "r09") != null and qa_same_save(qa_exploration_state.before_item_pick, world.snapshot())})
		capture("inventory-detail")
	elif qa_tick == 958:
		qa_click(qa_button(modal, "收起愿簿"))
	elif qa_tick == 961:
		qa_interaction_checks.append({"name": "the round inventory close control returns to the same live HUD and run", "passed": screen == "game" and not paused and hud.visible and qa_hud_current()})
		qa_click(qa_button(hud, "暂停"))
	elif qa_tick == 965:
		qa_interaction_checks.append({"name": "pointer click on the pause icon hides the combat HUD and opens the round pause sheet", "passed": screen == "pause" and paused and not hud.visible and qa_button(modal, "继续动身") != null})
		capture("modern-pause")
	elif qa_tick == 966:
		qa_click(qa_button(modal, "本局记录"))
	elif qa_tick == 968:
		qa_interaction_checks.append({"name": "the pause sheet opens a chronological record of the initial weapon, skill and active item without resuming combat", "passed": screen == "run_history" and paused and qa_find_meta(modal, "history_entry_count", "3") != null and qa_button(modal, "返回暂停") != null})
		capture("run-history")
	elif qa_tick == 969:
		qa_key(KEY_ESCAPE)
	elif qa_tick == 970:
		qa_key(KEY_ESCAPE)
	elif qa_tick == 972:
		qa_interaction_checks.append({"name": "Escape closes the modern pause sheet and restores gameplay without changing the equipped character", "passed": screen == "game" and not paused and hud.visible and world.run.character == "c_bell"})
		show_pause()
		qa_click(qa_button(modal, "灯下设置"))
	elif qa_tick == 976:
		qa_exploration_state.previous_mute = settings.muted
		qa_click(qa_find_meta(modal, "setting_key", "muted"))
	elif qa_tick == 980:
		qa_interaction_checks.append({"name": "the icon toggle changes live sound and keeps settings reachable", "passed": screen == "settings" and settings.muted != qa_exploration_state.previous_mute and audio.muted == settings.muted and qa_button(modal, "收起") != null})
		ControlSettings.show_assistance(self)
	elif qa_tick == 982:
		qa_click(qa_button(modal, "轻度：15度扇区、25%修正；自动：保持目标0.25秒。"))
	elif qa_tick == 985:
		var label = qa_find_meta(modal, "setting_detail", "aim_mode")
		qa_interaction_checks.append({"name": "the information icon expands the assistance explanation while preserving the actual option control", "passed": label != null and label.visible and qa_setting_button(modal, "aim_mode") != null})
		capture("utility-help")
	elif qa_tick == 989:
		mobile_ui = true
		mobile_button_height = 90
		show_menu()
	elif qa_tick == 993:
		capture("modern-menu-mobile")
	elif qa_tick == 995:
		mobile_ui = false
		show_achievements()
	elif qa_tick == 997:
		qa_interaction_checks.append({"name": "the live achievements sheet opens from the menu with all thirty-two cards and character filtering", "passed": screen == "achievements" and qa_meta_count(modal, "achievement_id") == 32 and qa_find_meta(modal, "achievement_id", "ach_c_paper_burn") != null and qa_find_meta(modal, "achievement_id", "ach_global_ten_runs") != null and qa_button(modal, "纸童") != null})
		capture("achievements")
	elif qa_tick == 999:
		qa_key(KEY_ESCAPE)
		qa_interaction_checks.append({"name": "Escape returns from the achievement sheet to the character layer without entering a run", "passed": screen == "menu" and menu_page == "characters" and paused and not hud.visible})
	elif qa_tick == 1000:
		mobile_ui = false
		clear_modal()
		world.run.result = "defeat"
		show_result()
	elif qa_tick == 1001:
		capture("modern-result")
	elif qa_tick == 1005:
		begin_run("c_bell", 7119, false)
		paused = true
		world.player.max_hp = 12
		world.player.hp = 2
		world.player.armor = 3
		world.player.energy = 12
		world.player.skill_cd = 3.4
		world.player.dash_cd = 1.4
		for i in 12: world.run.relics["r%02d" % (i + 1)] = 1 + int(i % 3 == 0)
	elif qa_tick == 1009:
		capture("hud-extended")
	elif qa_tick == 1013:
		qa_interaction_checks.append({"name": "native rounded body, bold HUD and display fonts load with a rare-name CJK fallback", "passed": font.get_font_name().contains("Incense Rounded") and title_font.get_font_name().contains("Smiley") and renderer.font == UI.body_font(true) and font.has_char(0x9f98)})
		show_credits()
		var notices = modal.get_children().filter(func(child): return child is RichTextLabel)
		var licenses = ["res://assets/fonts/ResourceHanRounded-OFL.txt", "res://assets/fonts/SmileySans-OFL.txt", "res://assets/ui/icons/Lucide-LICENSE.txt", "res://assets/fonts/OFL.txt", "res://assets/licenses/Godot-THIRDPARTY.txt"]
		qa_interaction_checks.append({"name": "the actual credits page loads full packaged font, vector and engine notices", "passed": notices.size() == 1 and notices[0].text.contains("Cyano Hao") and notices[0].text.contains("atelierAnchor") and notices[0].text.contains("Lucide Icons and Contributors") and licenses.all(func(path): return FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > 1000)})
		show_ui_gallery()
	elif qa_tick == 1017:
		capture("ui-style")
	elif qa_tick == 1025:
		selected = "c_paper"
		selected_weapon = ""
		qa_exploration_state.before_character_trial = save_session.portable_bundle().duplicate(true)
		qa_exploration_state.character_checkpoint = checkpoint.duplicate(true)
		show_menu()
		qa_exploration_state.character_achievement_button = qa_find_meta(modal, "character_achievement_button", "c_paper") != null
		qa_click(qa_button(modal, "角色详情"))
	elif qa_tick == 1029:
		qa_interaction_checks.append({"name": "the character layer exposes a filtered achievement entry while its information icon opens the real character sheet", "passed": bool(qa_exploration_state.get("character_achievement_button", false)) and screen == "character" and paused and not hud.visible and qa_find_meta(modal, "character_detail_id", "c_paper") != null and qa_find_meta(modal, "character_passive", "c_paper") != null and qa_find_meta(modal, "preview_detail_id", "s01") != null})
		qa_exploration_state.character_world = world.snapshot()
		capture("character-details")
	elif qa_tick == 1033:
		qa_click(qa_find_meta(modal, "preview_skill_id", "s02"))
	elif qa_tick == 1037:
		qa_interaction_checks.append({"name": "selecting a skill icon discloses its own behavior and energy cost while preserving the paused run and checkpoint", "passed": qa_find_meta(modal, "preview_detail_id", "s02") != null and qa_find_meta(modal, "preview_trial_id", "s02") != null and qa_same_save(world.snapshot(), qa_exploration_state.character_world) and qa_same_save(checkpoint, qa_exploration_state.character_checkpoint)})
		capture("character-evolution")
	elif qa_tick == 1041:
		qa_click(qa_find_meta(modal, "preview_trial_id", "s02"))
	elif qa_tick == 1045:
		qa_interaction_checks.append({"name": "the trial action enters the actual simulator with the selected evolution, marked targets, round reset and return controls", "passed": screen == "game" and not paused and world.run.get("training", false) and world.run.character == "c_paper" and world.player.skill == "s02" and world.enemies.size() == 4 and world.enemies.all(func(e): return e.mark > 0) and qa_button(modal, "回还愿人") != null and qa_button(modal, "重置试演") != null})
		paused = true
		capture("character-training")
	elif qa_tick == 1053:
		qa_exploration_state.trial_hp = world.enemies.reduce(func(total, enemy): return total + enemy.hp, 0.0)
		world.tick({"move": Vector2.ZERO, "aim": Vector2.UP, "skill": true}, .0166667)
		flush_events()
	elif qa_tick == 1057:
		var remaining = world.enemies.reduce(func(total, enemy): return total + enemy.hp, 0.0)
		qa_interaction_checks.append({"name": "a trial skill input performs real damage and cooldown without committing rewards, character unlocks or the suspended run", "passed": world.stats.detonations == 1 and world.player.skill_cd > 0 and remaining < qa_exploration_state.trial_hp and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_character_trial) and qa_same_save(checkpoint, qa_exploration_state.character_checkpoint)})
		capture("character-training-cast")
	elif qa_tick == 1061:
		qa_click(qa_button(modal, "重置试演"))
	elif qa_tick == 1065:
		qa_interaction_checks.append({"name": "the round retry action retains the chosen evolution and resets targets without touching persisted progress", "passed": screen == "game" and world.player.skill == "s02" and world.stats.detonations == 0 and world.enemies.size() == 4 and world.enemies.all(func(e): return e.hp == 180 and e.mark == 3) and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_character_trial)})
		qa_click(qa_button(modal, "回还愿人"))
	elif qa_tick == 1069:
		qa_interaction_checks.append({"name": "the trial return action restores the selected skill detail and hides the combat interface", "passed": screen == "character" and paused and not hud.visible and qa_find_meta(modal, "preview_detail_id", "s02") != null})
		qa_key(KEY_ESCAPE)
	elif qa_tick == 1073:
		qa_interaction_checks.append({"name": "Escape returns from character details to the menu with the original profile and suspended run intact", "passed": screen == "menu" and selected == "c_paper" and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_character_trial) and qa_same_save(checkpoint, qa_exploration_state.character_checkpoint)})
		mobile_ui = true
		mobile_button_height = 90
		qa_exploration_state.character_profile = progress.data.duplicate(true)
		progress.data.characters.erase("c_mask")
		qa_exploration_state.locked_profile = progress.data.duplicate(true)
		show_menu()
	elif qa_tick == 1077:
		qa_touch(qa_find_meta(modal, "character_id", "c_mask"))
	elif qa_tick == 1081:
		var condition = qa_find_meta(modal, "character_progress_id", "c_mask")
		var trial = qa_find_meta(modal, "preview_trial_id", "s10")
		qa_interaction_checks.append({"name": "an injected touch on a locked character opens its actual unlock count and mobile-sized trial control without relying on hover", "passed": screen == "character" and selected == "c_mask" and condition != null and condition.text == CharacterSheet.unlock_note(self, "c_mask") and trial != null and trial.size.y >= mobile_button_height and not progress.data.characters.has("c_mask")})
		capture("character-locked-mobile")
	elif qa_tick == 1085:
		qa_touch(qa_find_meta(modal, "preview_skill_id", "s12"))
	elif qa_tick == 1089:
		var detail = qa_find_meta(modal, "preview_detail_id", "s12")
		qa_interaction_checks.append({"name": "a mobile skill tab uses a sufficiently large touch area and exposes the selected heavy evolution's actual cost and cooldown", "passed": detail != null and detail.accessibility_name.contains("38") and detail.accessibility_name.contains("7.0") and qa_find_meta(modal, "preview_skill_id", "s12").size.y >= mobile_button_height})
		capture("character-skills-mobile")
	elif qa_tick == 1093:
		qa_touch(qa_find_meta(modal, "preview_trial_id", "s12"))
	elif qa_tick == 1097:
		qa_interaction_checks.append({"name": "a locked character can preview its real evolution while its unlock, account and suspended checkpoint remain unchanged", "passed": screen == "game" and world.run.character == "c_mask" and world.player.skill == "s12" and world.run.get("training", false) and not progress.data.characters.has("c_mask") and qa_same_save(progress.data, qa_exploration_state.locked_profile) and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_character_trial) and qa_same_save(checkpoint, qa_exploration_state.character_checkpoint)})
		paused = true
	elif qa_tick == 1101:
		var trials: Array = []
		for character in world.db.rows("characters"):
			selected = character.id
			for skill in character.skills:
				begin_training("", 0, skill)
				paused = true
				world.tick({"move": Vector2.ZERO, "aim": Vector2.UP, "skill": true}, .0166667)
				for i in 125: world.tick({"move": Vector2.ZERO, "aim": Vector2.UP}, .0166667)
				flush_events()
				var health = world.enemies.reduce(func(total, enemy): return total + enemy.hp, 0.0)
				trials.append({"skill": skill, "passed": world.player.skill == skill and world.stats.detonations == 1 and health < 720})
		qa_interaction_checks.append({"name": "all eighteen character trial presets accept a real skill input and damage their targets without account or checkpoint writes", "passed": trials.size() == 18 and trials.all(func(trial): return trial.passed) and qa_same_save(progress.data, qa_exploration_state.locked_profile) and qa_same_save(save_session.portable_bundle(), qa_exploration_state.before_character_trial) and qa_same_save(checkpoint, qa_exploration_state.character_checkpoint), "trials": trials})
		selected = "c_paper"
		var before = world.snapshot()
		begin_training("", 0, "s18")
		qa_interaction_checks.append({"name": "a trial rejects another character's skill identifier before altering the simulator or persisted profile", "passed": qa_same_save(before, world.snapshot()) and qa_same_save(progress.data, qa_exploration_state.locked_profile)})
		progress.data = qa_exploration_state.character_profile
		mobile_ui = false
	elif qa_tick == 1110:
		progress.data = World.Migration.profile({}).data
		progress.save()
		selected = "c_paper"
		begin_run(selected, 9268, false)
		paused = true
		world.enemies.clear()
		world.bullets.clear()
		world.zones.clear()
		world.delayed.clear()
		world.geometry.build("room_open_1", 1)
		world.player.pos = Vector2(640, 400)
		world.time = 122.0
		world.stats.elapsed = 122.0
		world.player.hp = 3
		world.player.armor = 1
		world.run.relics = {"r29": 1, "r09": 1, "r17": 1, "r01": 2}
		world.run.merit = 7
		world.stats.detonations = 6
		world.stats.max_chain = 3
		world.run.talents = ["t_fire_1a", "t_ash_1a"]
		var attacker = world.spawn_enemy("e14", Vector2(850, 350))
		attacker.attack_cd = 99
		for raw in [1, 2]:
			world.player.invulnerable = 0
			world.enemy_bullet(world.player.pos + Vector2(100, 0), Vector2.LEFT, 300, raw, 7, world.source_of(attacker, "projectile"))
			world.update_bullets(.4)
		settings.flash_scale = 0.0
		settings.reduce_motion = true
		apply_control_settings()
		flush_events()
		clear_modal()
		renderer.visual_effects = renderer.visual_effects.filter(func(effect): return effect.kind == "hurt_source")
		qa_interaction_checks.append({"name": "real projectile damage supplies an incoming direction that remains visible when flashing and motion are disabled", "passed": world.run.damage_history.size() == 2 and world.run.damage_history[-1].direction.is_equal_approx(Vector2.RIGHT) and renderer.flash_scale == 0 and renderer.reduce_motion and renderer.visual_effects.any(func(effect): return effect.kind == "hurt_source")})
		capture("hurt-direction")
	elif qa_tick == 1118:
		var attacker = world.spawn_enemy("e03", Vector2(440, 260))
		world.player.invulnerable = 0
		world.enemy_bullet(world.player.pos - Vector2(0, 100), Vector2.DOWN, 300, 1, 7, world.source_of(attacker, "projectile"))
		world.update_bullets(.4)
		var killer = world.spawn_boss("b02")
		world.player.invulnerable = 0
		world.add_zone(world.player.pos, 80, .7, 1, false, 0, world.source_of(killer, "zone"))
		world.enemies.clear()
		world.update_zones(0)
		flush_events()
		var reloaded = SaveSession.new("user://qa_session")
		save_session = reloaded
		store = save_session.view("checkpoint")
		checkpoint = reloaded.current.checkpoint
		progress = Progress.new("", reloaded.view("profile"))
		world.restore(reloaded.current.checkpoint)
		show_result()
		qa_exploration_state.finished_world = world.snapshot()
		qa_exploration_state.finished_account = progress.data.duplicate(true)
		var cause = qa_find_meta(modal, "death_cause_id", "b02")
		qa_interaction_checks.append({"name": "a real terminal ground hit retains its removed boss and prior revival through an on-disk account/run reload and compact result", "passed": screen == "result" and paused and not hud.visible and cause != null and world.mode == "result" and world.run.damage_history.size() == 4 and world.run.damage_history[2].revived and world.run.death_cause.source.id == "b02" and qa_find_meta(modal, "result_item_id", "r09") != null})
		capture("result-source")
	elif qa_tick == 1122:
		qa_click(qa_find_meta(modal, "result_item_id", "r09"))
	elif qa_tick == 1126:
		qa_interaction_checks.append({"name": "an actual result relic icon opens the exact finished-build detail without advancing or crediting the run", "passed": screen == "run_build" and qa_find_meta(modal, "detail_item_id", "r09") != null and qa_same_save(world.snapshot(), qa_exploration_state.finished_world) and qa_same_save(progress.data, qa_exploration_state.finished_account)})
		capture("result-build")
	elif qa_tick == 1128:
		qa_key(KEY_ESCAPE)
	elif qa_tick == 1130:
		qa_interaction_checks.append({"name": "Escape from finished-build detail returns to the result and never resumes dead combat", "passed": screen == "result" and paused and world.mode == "result" and not hud.visible})
		qa_click(qa_button(modal, "受击与愿页"))
	elif qa_tick == 1134:
		qa_interaction_checks.append({"name": "the result review icon opens the most recent actual injury with its HP and mitigation detail", "passed": screen == "run_review" and qa_find_meta(modal, "review_damage_index", "3") != null and qa_same_save(world.snapshot(), qa_exploration_state.finished_world)})
		capture("run-damage")
	elif qa_tick == 1136:
		qa_click(qa_find_meta(modal, "damage_index", "2"))
	elif qa_tick == 1138:
		qa_interaction_checks.append({"name": "selecting a prior injury discloses the consumed revival without changing the finished world or committed ledger", "passed": screen == "run_review" and qa_find_meta(modal, "review_damage_index", "2") != null and qa_same_save(world.snapshot(), qa_exploration_state.finished_world) and qa_same_save(progress.data, qa_exploration_state.finished_account)})
		qa_click(qa_button(modal, "本局愿页"))
	elif qa_tick == 1142:
		var ledger = progress.data.runs[world.run.id]
		qa_interaction_checks.append({"name": "the wish-page disclosure shows only committed merit and personal pages after real disk reload", "passed": qa_find_meta(modal, "credited_merit", "22") != null and ledger.personal_pages == [1, 2] and ledger.bonus_merit == 15 and ledger.characters_unlocked == ["c_bell"] and qa_same_save(progress.data, qa_exploration_state.finished_account)})
		capture("run-pages")
	elif qa_tick == 1144:
		qa_click(qa_button(modal, "返回结算"))
	elif qa_tick == 1146:
		qa_interaction_checks.append({"name": "closing the review returns to the compact result with identical combat history and earned progress", "passed": screen == "result" and paused and qa_same_save(world.snapshot(), qa_exploration_state.finished_world) and qa_same_save(progress.data, qa_exploration_state.finished_account)})
		mobile_ui = true
		mobile_button_height = 90
		show_result()
		capture("result-source-mobile")
	elif qa_tick == 1150:
		var entry = qa_button(modal, "受击与愿页")
		qa_interaction_checks.append({"name": "the mobile result uses ninety-unit icon entry controls without a hover dependency", "passed": entry != null and entry.size.y >= 90 and qa_find_meta(modal, "result_item_id", "r09").size.y >= 90})
		qa_touch(entry)
	elif qa_tick == 1154:
		qa_interaction_checks.append({"name": "an injected native touch opens the actual latest injury with usable mobile tabs and close target", "passed": screen == "run_review" and qa_find_meta(modal, "review_damage_index", "3") != null and qa_button(modal, "本局愿页").size.y >= 90 and qa_button(modal, "返回结算").size.y >= 90})
		capture("run-damage-mobile")
	elif qa_tick == 1156:
		qa_touch(qa_button(modal, "本局愿页"))
	elif qa_tick == 1158:
		qa_interaction_checks.append({"name": "mobile page disclosure exposes committed merit without mutating the result or account", "passed": screen == "run_review" and qa_find_meta(modal, "credited_merit", "22") != null and qa_same_save(world.snapshot(), qa_exploration_state.finished_world) and qa_same_save(progress.data, qa_exploration_state.finished_account)})
		capture("run-pages-mobile")
	elif qa_tick == 1160:
		qa_touch(qa_button(modal, "返回结算"))
	elif qa_tick == 1162:
		qa_exploration_state.finished_id = world.run.id
		qa_exploration_state.finished_seed = world.run.seed
		qa_touch(qa_button(modal, "再点一盏 · 新局"))
	elif qa_tick == 1166:
		qa_interaction_checks.append({"name": "the real retry touch retains the character while creating a new seed and ID and clearing old injury and death records", "passed": screen == "tutorial" and paused and world.run.character == "c_paper" and world.run.id != qa_exploration_state.finished_id and world.run.seed != qa_exploration_state.finished_seed and world.run.damage_history.is_empty() and world.run.death_cause.is_empty() and progress.data.runs[qa_exploration_state.finished_id].merit == 7})
		world.run.result = "victory"
		world.run.bosses_defeated = ["b03"]
		world.mode = "result"
		show_result()
		qa_key(KEY_ESCAPE)
	elif qa_tick == 1170:
		qa_interaction_checks.append({"name": "the required final ending cannot be bypassed by Escape into dead combat or the result", "passed": screen == "endings" and paused and not hud.visible and world.run.ending.is_empty()})
		world.run.result = "defeat"
		world.run.bosses_defeated = []
		show_result()
		mobile_ui = false
	elif qa_tick == 1180:
		mobile_ui = false
		settings.reduce_motion = false
		settings.flash_scale = 1.0
		apply_control_settings()
		begin_run("c_mask", 6813, false)
		paused = true
		world.enemies.clear()
		world.bullets.clear()
		world.zones.clear()
		world.delayed.clear()
		world.geometry.build("room_open_1", 1)
		world.player.pos = Vector2(640, 460)
		world.player.aim = Vector2.UP
		world.player.invulnerable = 30
		var target = world.spawn_enemy("e01", Vector2(640, 340))
		target.hp = 5000
		target.max_hp = target.hp
		target.speed = 0
		target.attack_cd = 99
		qa_exploration_state.impact_uid = target.uid
		qa_exploration_state.impact_origin = Vector2(target.pos)
		flush_events()
		clear_modal()
	elif qa_tick == 1184:
		capture("impact-heavy-before")
	elif qa_tick == 1188:
		world.tick({"move": Vector2.ZERO, "aim": Vector2.UP, "fire": true})
		# Impulses apply to physical movement on the next fixed update after the hit.
		world.tick({"move": Vector2.ZERO, "aim": Vector2.UP})
		flush_events()
		var target = world.enemy_by_uid(qa_exploration_state.impact_uid)
		qa_interaction_checks.append({"name": "an actual seal attack damages and marks its target while beginning a bounded physical impulse instead of teleporting it", "passed": world.stats.shots == 1 and target.hp < target.max_hp and target.mark == 1 and target.get("push_left", 0) > 0 and target.pos.distance_to(qa_exploration_state.impact_origin) > 0 and target.pos.distance_to(qa_exploration_state.impact_origin) < 64})
		save_current_run()
		qa_exploration_state.impact_saved = checkpoint.duplicate(true)
	elif qa_tick == 1192:
		save_session = SaveSession.new("user://qa_session")
		store = save_session.view("checkpoint")
		progress = Progress.new("", save_session.view("profile"))
		restore_run()
		qa_interaction_checks.append({"name": "the real saved mid-impact run reloads from disk into the native confirmation pause with identical simulator and bound HUD", "passed": screen == "pause" and paused and qa_hud_current() and qa_same_save(world.snapshot(), qa_exploration_state.impact_saved) and world.enemy_by_uid(qa_exploration_state.impact_uid).get("push_left", 0) > 0 and not adapter.fire_latched})
	elif qa_tick == 1196:
		qa_click(qa_button(modal, "继续动身"))
	elif qa_tick == 1200:
		paused = true
		var target = world.enemy_by_uid(qa_exploration_state.impact_uid)
		qa_interaction_checks.append({"name": "the actual continue button resumes the pending impulse without an automatic extra shot", "passed": screen == "game" and world.stats.shots == 1 and target.pos.distance_to(qa_exploration_state.impact_origin) > qa_exploration_state.impact_saved.enemies[0].pos.distance_to(qa_exploration_state.impact_origin)})
		for i in 12: world.tick({"move": Vector2.ZERO, "aim": Vector2.UP})
		flush_events()
		qa_exploration_state.impact_settled = world.snapshot()
		settings.reduce_motion = true
		settings.flash_scale = 0.0
		apply_control_settings()
		qa_interaction_checks.append({"name": "physical heavy displacement completes sixty-four units and visual accessibility changes leave its combat state intact", "passed": absf(target.pos.distance_to(qa_exploration_state.impact_origin) - 64) < .001 and target.push_left == 0 and qa_same_save(world.snapshot(), qa_exploration_state.impact_settled)})
	elif qa_tick == 1204:
		capture("impact-heavy-after")
	elif qa_tick == 1210:
		selected = "c_bell"
		begin_training("", 0, "s05")
		paused = true
		world.enemies.clear()
		var ordinary = world.spawn_enemy("e01", Vector2(500, 340))
		var elite = world.spawn_enemy("e01", Vector2(640, 340), true)
		elite.elite_id = "x01"
		elite.sprite_id = "x01"
		var boss = world.spawn_boss("b01")
		boss.pos = Vector2(780, 340)
		for target in [ordinary, elite, boss]:
			target.hp = 5000
			target.max_hp = target.hp
			target.speed = 0
			target.attack_cd = 99
			world.add_mark(target, 3, false)
		qa_exploration_state.root_uids = [ordinary.uid, elite.uid, boss.uid]
		world.update_chains()
		world.cast_skill()
		flush_events()
		qa_interaction_checks.append({"name": "the native red-net cast roots ordinary and elite targets for their different caps while its visible boss remains immune", "passed": world.stats.detonations == 1 and absf(ordinary.stun_until - world.time - .5) < .001 and absf(elite.stun_until - world.time - .3) < .001 and boss.stun_until == 0 and world.delayed.any(func(action): return action.type == "skill_first")})
	elif qa_tick == 1214:
		capture("root-bound")
	elif qa_tick == 1218:
		for i in 20: world.tick({"move": Vector2.ZERO, "aim": Vector2.UP})
		flush_events()
		var ordinary = world.enemy_by_uid(qa_exploration_state.root_uids[0])
		var elite = world.enemy_by_uid(qa_exploration_state.root_uids[1])
		qa_interaction_checks.append({"name": "the elite binding releases after three tenths while the ordinary binding and delayed blast remain active with flashing and motion disabled", "passed": world.time >= elite.stun_until and world.time < ordinary.stun_until and world.delayed.any(func(action): return action.type == "skill_first") and renderer.flash_scale == 0 and renderer.reduce_motion})
	elif qa_tick == 1222:
		capture("root-release")
	elif qa_tick == 1230:
		begin_run("c_paper", 6893, false)
		paused = true
		world.enemies.clear()
		world.bullets.clear()
		world.player.pos = Vector2(640, 420)
		world.player.hp = 1
		world.player.invulnerable = 0
		var elite = world.spawn_enemy("e01", Vector2(640, 300), true)
		elite.elite_id = "x01"
		elite.sprite_id = "x01"
		world.enemy_bullet(Vector2(640, 320), Vector2.DOWN, 300, 1, 7, world.source_of(elite, "projectile"))
		world.enemies.clear()
		world.update_bullets(.4)
		flush_events()
		var reloaded = SaveSession.new("user://qa_session")
		save_session = reloaded
		store = save_session.view("checkpoint")
		progress = Progress.new("", save_session.view("profile"))
		world.restore(reloaded.current.checkpoint)
		show_result()
		qa_interaction_checks.append({"name": "a real removed elite's lethal projectile restores from disk and names the actual elite variant on the compact result", "passed": world.run.death_cause.source.elite_id == "x01" and qa_find_meta(modal, "death_cause_id", "e01") != null and qa_find_meta(modal, "death_cause_id", "e01").text.contains(world.db.name_of("elite_variants", "x01"))})
	elif qa_tick == 1234:
		capture("elite-source")
	elif qa_tick == 1238:
		begin_run("c_paper", 8931, false)
		paused = true
		world.run.room = world.run.room_plan.find("shop")
		world.enter_room()
		qa_exploration_state.shop_before = world.snapshot()
		clear_modal()
		sync_game_modal()
	elif qa_tick == 1240:
		var shop_index = -1
		for i in world.choices.size():
			if world.choices[i].kind == "weapon": shop_index = i
		qa_interaction_checks.append({"name": "the real shop exposes an icon-first weapon trial action without hiding its price or changing the candidate list", "passed": screen == "game" and paused and world.mode == "shop" and shop_index >= 0 and qa_find_meta(modal, "shop_trial_index", str(shop_index)) != null and qa_button(modal, "选择" + world.db.name_of("weapons", world.choices[shop_index].id)) != null})
		begin_shop_trial(shop_index)
	elif qa_tick == 1244:
		var original = shop_trial.origin
		qa_interaction_checks.append({"name": "the weapon trial switches to a live isolated room with the actual offered weapon while preserving the original shop snapshot", "passed": screen == "game" and not paused and shop_trial.active() and world.run.training and world.mode == "combat" and world.player.weapon == world.run.training_shop_weapon and original != world and qa_same_save(original.snapshot(), qa_exploration_state.shop_before) and qa_button(modal, "回灯摊") != null})
		capture("shop-trial-live")
	elif qa_tick == 1246:
		for i in 30: world.tick({"fire": true, "aim": Vector2.UP})
		end_shop_trial()
	elif qa_tick == 1248:
		qa_interaction_checks.append({"name": "returning from real shop practice restores the original stock, wallet and candidate RNG without charging the trial", "passed": screen == "game" and not paused and not shop_trial.active() and world.mode == "shop" and qa_same_save(world.snapshot(), qa_exploration_state.shop_before) and qa_find_meta(modal, "shop_trial_index", "3") != null})
		capture("shop-trial-return")
	elif qa_tick == 1250:
		capture("shop-trial")
	elif qa_tick == 1251:
		clear_modal()
		show_inventory("relics")
	elif qa_tick == 1252:
		var synergy_tab = qa_button(modal, "组合册")
		qa_interaction_checks.append({"name": "the live inventory exposes the icon-first synergy codex tab without changing the paused run", "passed": screen == "inventory" and paused and synergy_tab != null})
		qa_click(synergy_tab)
	elif qa_tick == 1254:
		var synergy_card = qa_find_meta(modal, "synergy_id", "combo01")
		qa_interaction_checks.append({"name": "the synergy codex renders relic progress and a selected route detail from the current build", "passed": screen == "inventory" and synergy_card != null and qa_find_meta(modal, "synergy_id", "combo01") != null and qa_button(modal, "收起愿簿") != null})
		capture("inventory-synergy")
	elif qa_tick == 1256:
		# Capture the four authored special-room centerpieces in the compiled
		# renderer, with the real choice sheet and ambient particles layered on top.
		begin_run("c_paper", 9321, false)
		world.player.invulnerable = 30.0
		world.run.room = world.run.graph.types.find("sacrifice")
		world.enter_room()
		paused = true
		clear_modal()
	elif qa_tick == 1258:
		capture("special-sacrifice")
	elif qa_tick == 1260:
		world.run.room = world.run.graph.types.find("judge")
		world.enter_room()
		paused = true
		clear_modal()
	elif qa_tick == 1262:
		capture("special-judge")
	elif qa_tick == 1264:
		world.run.room = world.run.graph.types.find("angel")
		world.enter_room()
		paused = true
		clear_modal()
	elif qa_tick == 1266:
		capture("special-angel")
	elif qa_tick == 1268:
		world.run.room = world.run.graph.types.find("challenge")
		world.enter_room()
		paused = true
		clear_modal()
	elif qa_tick == 1270:
		capture("special-challenge")
	elif qa_tick == 1272:
		var path = qa_directory.path_join("native-render.json")
		var file = FileAccess.open(path, FileAccess.WRITE)
		qa_stress_frames.sort()
		qa_stress_physics.sort()
		qa_stress_ticks.sort()
		var samples = qa_stress_frames.size()
		file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "driver": RenderingServer.get_current_rendering_method(),
			"captures": qa_captures, "asset_loads": qa_asset_count, "asset_failures": qa_asset_failures,
			"interaction_checks": qa_interaction_checks, "orientation_check_scope": "desktop fixture injects native surface dimensions; physical phone rotation remains pending",
			"stress": {"enemies": 8, "projectiles": 240, "sampled_render_frames": samples, "frame_ms_p95": qa_stress_frames[mini(samples - 1, int(samples * .95))], "physics_ms_p95": qa_stress_physics[mini(samples - 1, int(samples * .95))], "world_tick_ms_p95": qa_stress_ticks[mini(qa_stress_ticks.size() - 1, int(qa_stress_ticks.size() * .95))], "godot_static_memory_bytes": qa_stress_memory, "scope": "native desktop renderer fixture; not mobile or long-duration profiling"},
			"source": "real native viewport; fixture states for visual review", "frames": qa_tick}, "\t"))
		file.close()
		get_tree().quit()

func qa_button(parent: Node, text: String) -> Button:
	for child in parent.get_children():
		if child is Button and (child.text == text or child.get_meta("action_label", "") == text): return child
		var found = qa_button(child, text)
		if found != null: return found
	return null

func qa_hud_current() -> bool:
	var graphics = hud.get_children().filter(func(child): return child is GameHud)
	return graphics.size() == 1 and graphics[0].world == world

func qa_same_save(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(Store.encode(a), "", true, true) == JSON.stringify(Store.encode(b), "", true, true)

func qa_key(code: int) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func qa_click(target) -> void:
	if not target is Button or target.disabled: return
	var point = target.get_global_rect().get_center()
	var motion = InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func qa_touch(target) -> void:
	if not target is Button or target.disabled: return
	for down in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 0
		event.position = target.get_global_rect().get_center()
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func qa_find_meta(parent: Node, key: String, value: String):
	if str(parent.get_meta(key, "")) == value: return parent
	for child in parent.get_children():
		var found = qa_find_meta(child, key, value)
		if found != null: return found
	return null

func qa_meta_count(parent: Node, key: String) -> int:
	var count = 1 if parent.has_meta(key) else 0
	for child in parent.get_children(): count += qa_meta_count(child, key)
	return count

func qa_setting_button(parent: Node, key: String) -> Button:
	if parent.get_meta("setting_key", "") == key:
		for child in parent.get_children():
			if child is Button: return child
	for child in parent.get_children():
		var found = qa_setting_button(child, key)
		if found != null: return found
	return null

func qa_verify_assets() -> void:
	var registry = JSON.parse_string(FileAccess.get_file_as_string("res://data/runtime_assets.json"))
	for entry in registry.assets:
		var resource = load(entry.file)
		qa_asset_count += 1
		if resource == null: qa_asset_failures.append(entry.file)
		elif entry.kind == "texture" and (resource.get_width() != entry.size[0] or resource.get_height() != entry.size[1]): qa_asset_failures.append(entry.file + ": dimensions")
		elif entry.kind == "audio":
			var rate = resource.packet_sequence.sampling_rate if resource is AudioStreamOggVorbis else resource.mix_rate
			if rate != entry.sample_rate: qa_asset_failures.append(entry.file + ": sample rate")
			if absf(resource.get_length() - float(entry.duration)) > .025: qa_asset_failures.append(entry.file + ": duration")
		elif entry.kind == "font":
			if not resource is Font or not resource.has_char("债".unicode_at(0)): qa_asset_failures.append(entry.file + ": Chinese glyph coverage")

func show_weapon_gallery(page: int, direction: String) -> void:
	paused = true
	clear_modal()
	dim(.97)
	label(modal, "器具随身 · 四向持握核对", Rect2(42, 17, 1150, 43), 30)
	label(modal, "%s · %s" % ["前六器具" if page == 0 else "后六器具", {"down": "正面", "left": "左侧", "right": "右侧", "up": "背面"}[direction]], Rect2(940, 24, 285, 35), 18, GOLD)
	var gallery = load("res://scripts/ui/weapon_gallery.gd").new()
	gallery.page = page
	gallery.direction = direction
	modal.add_child(gallery)
	var actors = ["c_paper", "c_bell", "c_lantern", "c_mask", "c_umbrella", "c_ink"]
	for column in 6:
		label(modal, world.db.name_of("characters", actors[column]), Rect2(132 + column * 190, 73, 116, 30), 19)
	for row in 6:
		label(modal, world.db.name_of("weapons", "w%02d" % (page * 6 + row + 1)), Rect2(24, 130 + row * 89, 78, 52), 15, GOLD)

func show_animation_gallery() -> void:
	paused = true
	clear_modal()
	dim(.94)
	label(modal, "锁定原图 · 六种纸偶状态", Rect2(42, 16, 1150, 42), 30)
	var states = ["idle", "run", "cast", "dash", "hurt", "death"]
	var names = ["待机", "行走", "施术", "身法", "受击", "散纸"]
	for i in states.size(): label(modal, names[i], Rect2(206 + i * 165, 64, 155, 31), 22, GOLD)
	var characters = world.db.rows("characters")
	for i in characters.size():
		label(modal, characters[i].name, Rect2(43, 125 + i * 98, 151, 45), 25)
		for j in states.size():
			var art = TextureRect.new()
			art.texture = renderer.animation.texture(characters[i].id, "character", states[j], .17)
			art.position = Vector2(208 + j * 165, 93 + i * 98)
			art.size = Vector2(96, 96)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			modal.add_child(art)

func show_ui_gallery() -> void:
	paused = true
	screen = "ui_gallery"
	hud.visible = false
	clear_modal()
	dim(.985)
	label(modal, "香火债", Rect2(54, 37, 430, 80), 64)
	label(modal, "界面规范", Rect2(54, 119, 430, 40), 24, UI.MUTED)
	var keys = ["settings-2", "play", "book-open", "lock"]
	for i in keys.size():
		var action = icon_button(modal, ["设置", "动身", "愿簿", "暂未解锁"][i], keys[i], Rect2(54 + i * 104, 216, 72, 72), func(): pass, i == 1)
		if i == 2: action.grab_focus()
		if i == 3: action.disabled = true
	var fills = [UI.BACKGROUND, UI.SURFACE, UI.TEXT, UI.ACCENT, UI.JADE]
	for i in fills.size(): panel(modal, Rect2(54 + i * 78, 347, 60, 60), fills[i], Color.TRANSPARENT)
	label(modal, "焚债 · 还愿 · 龘", Rect2(54, 447, 422, 49), 26)
	label(modal, "灯还燃着，账可以慢慢还。", Rect2(54, 518, 422, 52), 19, UI.MUTED)
	icon_button(modal, "动身", "play", Rect2(54, 610, 388, 64), func(): pass, true, "动身")
	panel(modal, Rect2(516, 172, 708, 500), UI.INSET, Color.TRANSPARENT)
	var registry = JSON.parse_string(FileAccess.get_file_as_string("res://data/runtime_assets.json"))
	var vectors = registry.assets.filter(func(entry): return str(entry.file).begins_with("res://assets/ui/icons/") and str(entry.file).ends_with(".svg"))
	for i in vectors.size():
		var card = panel(modal, Rect2(540 + (i % 8) * 84, 195 + int(i / 8) * 56, 60, 48), UI.SURFACE, Color.TRANSPARENT)
		icon(card, str(vectors[i].file).get_file().trim_suffix(".svg"), Rect2(18, 12, 24, 24))

func capture(name: String) -> void:
	qa_capture_busy = true
	var requested_screen = screen
	var requested_tick = qa_tick
	var expected_screen = {"save-transfer": "saves", "save-paste": "save_paste", "save-preview": "save_preview",
		"mobile-save-transfer": "saves", "mobile-save-preview": "save_preview",
		"character-details": "character", "character-evolution": "character", "character-locked-mobile": "character", "character-skills-mobile": "character",
		"character-training": "game", "character-training-cast": "game", "hurt-direction": "game",
		"result-source": "result", "result-source-mobile": "result", "result-build": "run_build",
		"impact-heavy-before": "game", "impact-heavy-after": "game", "root-bound": "game", "root-release": "game", "elite-source": "result",
		"shop-trial": "game", "shop-trial-live": "game", "shop-trial-return": "game",
		"run-damage": "run_review", "run-pages": "run_review", "run-damage-mobile": "run_review", "run-pages-mobile": "run_review"}.get(name, requested_screen)
	var expected_mode = {"choices": "choice", "mobile-choice": "choice", "evolution": "choice",
		"debt": "debt", "secret-room": "choice", "character-training": "combat", "character-training-cast": "combat",
		"hurt-direction": "combat", "result-source": "result", "result-source-mobile": "result", "result-build": "result",
		"impact-heavy-before": "combat", "impact-heavy-after": "combat", "root-bound": "combat", "root-release": "combat", "elite-source": "result",
		"shop-trial": "shop", "shop-trial-live": "combat", "shop-trial-return": "shop",
		"run-damage": "result", "run-pages": "result", "run-damage-mobile": "result", "run-pages-mobile": "result"}.get(name, "")
	# Freeze the fixture clock through two real draws so slow persistence work or
	# physics catch-up cannot advance the sheet before its viewport is recorded.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var path = qa_directory.path_join(name + ".png")
	var result = image.save_png(path)
	qa_captures.append({"name": name, "path": path, "size": [image.get_width(), image.get_height()], "saved": result == OK,
		"screen": screen, "mode": world.mode, "expected_screen": expected_screen, "expected_mode": expected_mode,
		"fixture_tick": requested_tick, "state_stable": screen == requested_screen and screen == expected_screen and qa_tick == requested_tick and (expected_mode == "" or world.mode == expected_mode)})
	qa_capture_busy = false
	print("Captured " + name + ": " + str(result))
