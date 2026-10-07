extends Node
## Keyboard-only driver; fixtures arrange optional rooms, never activate controls.
var app
var directory = ""
var checks: Array = []
var captures: Array = []
var previous_clipboard = ""

func _ready() -> void:
	call_deferred("run")

func frames(count: int = 3) -> void:
	for _frame in count: await get_tree().process_frame

func expect(id: String, condition: bool, detail: String = "") -> void:
	checks.append({"id": id, "passed": condition, "detail": detail})
	if not condition: print("KEYBOARD FAIL: ", id, " ", detail)

func key(code: int, shift: bool = false) -> void:
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		event.shift_pressed = shift
		Input.parse_input_event(event)
		await frames(2)
		# Input is consumed by the fixed physics clock. Rendering can run faster
		# than 60Hz, so two draws alone do not guarantee a gameplay input sample.
		await get_tree().physics_frame
		await get_tree().physics_frame
		await frames(1)

func target(meta: String, value: String) -> bool:
	var controls = app.keyboard.candidates(app.modal)
	for _attempt in controls.size() + 2:
		var owner = app.get_viewport().gui_get_focus_owner()
		if is_instance_valid(owner) and str(owner.get_meta(meta, "")) == value: return true
		await key(KEY_TAB)
	expect("focus_" + meta + "_" + value, false, "No keyboard path from " + app.screen + "/" + app.menu_page)
	return false

func action(value: String) -> void:
	if await target("action_label", value): await key(KEY_ENTER)

func capture(name_value: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image = app.get_viewport().get_texture().get_image()
	var path = directory.path_join("keyboard-" + name_value + ".png")
	captures.append({"name": name_value, "saved": image.save_png(path) == OK, "screen": app.screen, "page": app.menu_page})

func run() -> void:
	previous_clipboard = DisplayServer.clipboard_get()
	await frames(5)
	expect("title_initial_focus", app.menu_page == "splash" and app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "start")
	await key(KEY_ENTER)
	await capture("files")
	expect("title_to_files", app.menu_page == "files")
	await key(KEY_RIGHT)
	expect("slot_arrow_right", str(app.get_viewport().gui_get_focus_owner().get_meta("save_slot", "")) == "2")
	await key(KEY_ENTER)
	expect("file_to_main", app.menu_page == "title" and app.save_slot == 2)
	await capture("main")
	await key(KEY_DOWN)
	expect("disabled_continue_skipped", app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "challenges")
	await key(KEY_UP)
	expect("main_arrow_up", app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "new")
	await key(KEY_ENTER)
	expect("main_to_character", app.menu_page == "characters")
	await capture("characters")
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	expect("locked_character_details", app.screen == "character")
	await key(KEY_ESCAPE)
	expect("details_back_one_layer", app.menu_page == "characters" and app.screen == "menu")
	await target("character_id", "c_paper")
	await key(KEY_ENTER)
	await action("初始器具")
	expect("loadout_under_character", app.menu_page == "loadout")
	await key(KEY_ESCAPE)
	await action("角色成就")
	expect("character_achievements", app.screen == "achievements")
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	expect("character_filter_parent", app.screen == "menu" and app.menu_page == "characters")
	await key(KEY_ESCAPE)
	expect("character_back_to_main", app.menu_page == "title")
	await action("记录")
	await capture("stats")
	expect("stats_layer", app.menu_page == "stats")
	await action("物品图鉴")
	# Extra equipment tabs change geometric focus neighbors. Select a real
	# offering through Tab navigation before measuring its long-list scrolling.
	if await target("nav_id", "catalog_r01"): await key(KEY_ENTER)
	await key(KEY_PAGEDOWN)
	expect("collection_keyboard_page", app.menu_page == "items" and app.keyboard.first_scroll(app.modal).scroll_vertical > 0)
	for kind in ["active_items", "trinkets"]:
		if await target("nav_id", "collection_" + kind): await key(KEY_ENTER)
		expect("collection_keyboard_" + kind, app.menu_page == "items" and app.collection_kind == kind and app.keyboard.candidates(app.modal).filter(func(c): return str(c.get_meta("nav_id", "")).begins_with("catalog_")).size() == 12)
		await capture("collection-" + kind)
	await key(KEY_ESCAPE)
	await action("怪物图鉴")
	expect("bestiary_under_stats", app.menu_page == "bestiary")
	await key(KEY_ESCAPE)
	await action("结局")
	expect("endings_under_stats", app.menu_page == "ending_archive")
	await key(KEY_ESCAPE)
	await action("统计")
	expect("statistics_under_stats", app.menu_page == "statistics")
	await key(KEY_ESCAPE)
	await action("成就")
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	await key(KEY_DOWN)
	await key(KEY_PAGEDOWN)
	await key(KEY_ESCAPE)
	expect("stats_filter_parent", app.screen == "menu" and app.menu_page == "stats")
	await key(KEY_ESCAPE)
	await action("设置")
	expect("settings_initial_focus", app.screen == "settings" and app.get_viewport().gui_get_focus_owner().get_meta("setting_key", "") == "muted")
	var old_muted = app.settings.muted
	await key(KEY_ENTER)
	expect("settings_toggle_and_focus", app.settings.muted != old_muted and app.get_viewport().gui_get_focus_owner().get_meta("setting_key", "") == "muted")
	await key(KEY_ENTER)
	await action("音量混音")
	var volume_before = app.settings.master_volume
	await key(KEY_LEFT)
	expect("keyboard_slider", app.screen == "audio_settings" and app.settings.master_volume < volume_before)
	await key(KEY_DOWN)
	expect("slider_down_moves_focus", app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "music_volume")
	await key(KEY_ESCAPE)
	expect("audio_back_to_settings", app.screen == "settings")
	await action("关于与致谢")
	await key(KEY_PAGEDOWN)
	expect("credits_keyboard_scroll", app.get_viewport().gui_get_focus_owner().get_v_scroll_bar().value > 0)
	await key(KEY_ESCAPE)
	expect("credits_back_to_settings", app.screen == "settings")
	await action("操作映射")
	await target("nav_id", "binding_keyboard_up")
	await key(KEY_ENTER)
	await key(KEY_F)
	expect("keyboard_rebind_capture", app.capture_action.is_empty() and int(app.adapter.profile.bindings.keyboard.up.code) == KEY_F)
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	expect("rebind_cancel_stays_in_controls", app.screen == "controls" and app.capture_action.is_empty())
	await action("恢复此页默认")
	await key(KEY_ESCAPE)
	await action("瞄准与反馈")
	await key(KEY_END)
	expect("assistance_scroll_end", app.keyboard.first_scroll(app.modal).scroll_vertical > 0)
	await target("nav_id", "assistance_pickup_radius_scale")
	await key(KEY_ENTER)
	expect("assistance_rebuild_keeps_focus", app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "assistance_pickup_radius_scale")
	await key(KEY_ESCAPE)
	await action("触控布局")
	await target("nav_id", "layout_editor")
	var old_center = app.adapter.layout.move
	await key(KEY_RIGHT)
	expect("layout_keyboard_move", app.adapter.layout.move != old_center)
	await key(KEY_ENTER)
	expect("layout_keyboard_select", app.get_viewport().gui_get_focus_owner().selected == "aim")
	await key(KEY_TAB)
	expect("layout_tab_escape_editor", not app.get_viewport().gui_get_focus_owner().get_meta("keyboard_editor", false))
	await key(KEY_ESCAPE)
	await action("愿簿传递")
	await action("复制传递文字")
	await action("粘贴并预览")
	expect("save_paste_focus", app.screen == "save_paste" and app.get_viewport().gui_get_focus_owner() is TextEdit)
	await key(KEY_TAB)
	await action("从剪贴板粘贴")
	await action("预览愿簿")
	expect("save_preview_keyboard", app.screen == "save_preview")
	await key(KEY_ESCAPE)
	expect("preview_back_to_transfer", app.screen == "saves")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	expect("settings_back_to_main", app.screen == "menu" and app.menu_page == "title")
	await action("挑战")
	await action("选择挑战角色")
	expect("challenge_character_layer", app.menu_page == "characters" and app.selected_run_kind == "daily")
	await key(KEY_ESCAPE)
	expect("challenge_character_back", app.menu_page == "challenges")
	await key(KEY_ESCAPE)
	await action("新局")
	await action("入巷还愿  →")
	expect("keyboard_starts_tutorial", app.screen == "tutorial")
	await key(KEY_ENTER)
	expect("tutorial_to_game", app.screen == "game" and not app.paused)
	await key(KEY_ESCAPE)
	expect("game_to_pause", app.screen == "pause")
	await action("本局记录")
	await key(KEY_PAGEDOWN)
	await key(KEY_ESCAPE)
	expect("history_returns_pause", app.screen == "pause")
	await action("成就")
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	expect("pause_achievement_filter_parent", app.screen == "pause")
	await action("灯下设置")
	await action("音量混音")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	expect("pause_nested_settings_parent", app.screen == "pause")
	await action("存下这页 · 回主菜单")
	var before = app.checkpoint.duplicate(true)
	await action("新局")
	await action("入巷还愿  →")
	expect("new_run_overwrite_confirmation", app.screen == "new_run_confirm")
	await key(KEY_ESCAPE)
	expect("cancel_preserves_checkpoint", app.qa_same_save(before, app.checkpoint) and app.menu_page == "characters")
	await key(KEY_ESCAPE)
	await action("继续")
	expect("continue_to_pause", app.screen == "pause")
	await key(KEY_ENTER)
	await key(KEY_TAB)
	expect("tab_opens_map", app.screen == "route")
	await key(KEY_TAB)
	expect("tab_closes_map", app.screen == "game")
	await key(KEY_I)
	expect("inventory_opens_keyboard", app.screen == "inventory")
	await action("组合册")
	await key(KEY_PAGEDOWN)
	await key(KEY_I)
	expect("inventory_same_key_closes", app.screen == "game")
	await capture("closed-loop")
	await optional_flows()
	await finish()

func hold(code: int, ticks: int) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	for _tick in ticks: await get_tree().physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await frames(3)

func fixture(seed_value: int = 9243, character: String = "c_paper") -> void:
	app.begin_run(character, seed_value, false)
	app.world.player.invulnerable = 99999.0
	app.world.player.energy = 100.0
	await frames()

func room(kind: String, seed_value: int = 9243) -> void:
	await fixture(seed_value)
	app.paused = true
	var index = app.world.run.room_plan.find(kind)
	if index < 0:
		index = 3
		app.world.run.room_plan[index] = kind
		app.world.run.graph.types[index] = kind
	app.world.run.room = index
	app.world.enter_room()
	app.flush_events()
	app.resume_game()
	await frames()

func optional_flows() -> void:
	await fixture()
	var start: Vector2 = app.world.player.pos
	await hold(KEY_D, 12)
	expect("combat_keyboard_move", app.world.player.pos.x > start.x)
	app.world.enemies.clear()
	await hold(KEY_LEFT, 8)
	expect("combat_arrow_fire", app.world.bullets.size() > 0 and app.world.player.aim.x < -.9)
	await frames(4)
	expect("keyboard_aim_survives_release", app.adapter.aim.x < -.9)
	var dash_before = app.world.player.pos
	await key(KEY_SPACE)
	expect("keyboard_dash", app.world.player.pos.distance_to(dash_before) > 5)
	app.world.player.dash_left = 0.0
	app.world.player.energy = 100.0
	app.world.bullets.clear()
	var enemy = app.world.spawn_enemy("e01", app.world.player.pos + Vector2.LEFT * 90)
	app.world.add_mark(enemy, 3)
	var detonations = int(app.world.stats.detonations)
	await key(KEY_Q)
	expect("keyboard_skill", int(app.world.stats.detonations) > detonations, "screen=%s mode=%s energy=%s pending=%s" % [app.screen, app.world.mode, app.world.player.energy, app.adapter.pending_skill])
	# Clear-room fixture starts one step inside an actual door, then crosses it with WASD.
	app.world.enemies.clear()
	app.world.mode = "clear"
	app.world.run.visited = [int(app.world.run.room)]
	app.world.navigation_timer = 0.0
	var doors = app.world.room_doors()
	if not doors.is_empty():
		var door = doors[0]
		app.world.player.pos = door.pos - app.world.direction_vector(door.direction) * 76
		var old_room = int(app.world.run.room)
		app.ui_signature = ""
		await frames()
		await hold({"north": KEY_W, "south": KEY_S, "east": KEY_D, "west": KEY_A}[door.direction], 28)
		expect("keyboard_physical_door", int(app.world.run.room) != old_room, "position=%s door=%s mode=%s screen=%s" % [app.world.player.pos, door.pos, app.world.mode, app.screen])
	else: expect("keyboard_physical_door", false, "fixture has no real exit")
	for i in 4:
		await fixture(9260 + i)
		app.paused = true
		app.world.mode = "choice"
		app.world.choices = app.world.relic_offer(4)
		var chosen = str(app.world.choices[i].id)
		app.resume_game()
		await frames()
		await key(KEY_1 + i)
		expect("number_choice_" + str(i + 1), app.world.run.relics.has(chosen) and app.world.run.growth_log.back().id == chosen)
	await room("reward")
	await key(KEY_RIGHT)
	expect("reward_arrow_focus", app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "choice_1")
	var reward_id = str(app.world.choices[1].id)
	await key(KEY_F1)
	expect("choice_keyboard_full_details", app.screen == "focus_help")
	await key(KEY_ESCAPE)
	expect("details_restore_choice_focus", app.screen == "game" and app.get_viewport().gui_get_focus_owner().get_meta("nav_id", "") == "choice_1")
	await key(KEY_ENTER)
	expect("reward_arrow_enter", app.world.run.relics.has(reward_id))
	await fixture(9270)
	app.paused = true
	app.world.mode = "choice"
	app.world.choices = app.world.talent_offer()
	var old_offer = JSON.stringify(app.world.choices)
	var rerolls = int(app.world.run.rerolls)
	app.resume_game()
	await frames()
	await action("换一页")
	expect("keyboard_reroll", app.world.run.rerolls == rerolls - 1 and old_offer != JSON.stringify(app.world.choices))
	var talent = str(app.world.choices[0].id)
	await target("nav_id", "choice_0")
	await key(KEY_ENTER)
	expect("keyboard_talent", app.world.run.talents.has(talent))
	# Two queued decisions must both remain navigable after the first modal rebuild.
	await fixture(9272)
	app.paused = true
	app.world.mode = "choice"
	app.world.choices = app.world.relic_offer(3)
	app.world.choice_queue = [{"kind": "talent"}]
	app.resume_game()
	await frames()
	await key(KEY_ENTER)
	expect("queued_growth_keeps_focus", app.world.mode == "choice" and app.world.choices[0].kind == "talent" and app.get_viewport().gui_get_focus_owner() is Button)
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	expect("queued_growth_complete", app.world.mode == "clear" and app.world.run.talents.size() == 1)
	await fixture(9280, "c_bell")
	app.paused = true
	app.world.mode = "checkpoint"
	app.world.run.floor = 1
	app.world.run.room = 10
	app.resume_game()
	await frames()
	await action("去下一层")
	expect("checkpoint_to_skill_choice", app.world.mode == "choice" and app.world.choices[0].kind == "skill")
	await key(KEY_RIGHT)
	var skill = str(app.world.choices[1].id)
	await key(KEY_ENTER)
	expect("skill_arrow_enter", app.world.run.evolved and app.world.player.skill == skill)
	await room("shop", 8931)
	var wallet = int(app.world.run.coins)
	var stock = app.world.choices.duplicate(true)
	var trial_index = -1
	for i in app.world.choices.size():
		if app.world.choices[i].kind == "weapon": trial_index = i
	await target("shop_trial_index", str(trial_index))
	await key(KEY_ENTER)
	expect("keyboard_shop_trial", app.shop_trial.active() and app.world.run.training)
	await hold(KEY_UP, 6)
	await key(KEY_ESCAPE)
	expect("keyboard_shop_trial_return", not app.shop_trial.active() and app.world.mode == "shop" and app.world.run.coins == wallet and app.world.choices == stock)
	var controls = app.keyboard.candidates(app.modal)
	expect("shop_disabled_purchase_skipped", not controls.any(func(control): return control.get_meta("nav_id", "") == "choice_" + str(trial_index)))
	await action("留在此处 · 继续")
	expect("keyboard_shop_skip", app.world.mode == "clear")
	await room("shop", 8931)
	app.world.run.coins = 100
	# A shop modal pauses physics; arranging a funded fixture must redraw its
	# affordability controls explicitly instead of waiting for a combat tick.
	app.resume_game()
	await frames()
	var purchase_id = str(app.world.choices[trial_index].id)
	var price = int(app.world.choices[trial_index].price)
	await target("nav_id", "choice_" + str(trial_index))
	await key(KEY_ENTER)
	expect("keyboard_shop_purchase", app.world.player.weapon == purchase_id and app.world.run.coins == 100 - price, "weapon=%s expected=%s coins=%s price=%s" % [app.world.player.weapon, purchase_id, app.world.run.coins, price])
	await capture("shop")
	await room("debt")
	var contract = str(app.world.choices[0].id)
	await target("nav_id", "choice_0")
	await key(KEY_ENTER)
	expect("keyboard_debt_contract", app.world.run.contracts.any(func(entry): return entry.id == contract))
	await action("留在此处 · 继续")
	expect("keyboard_debt_exit", app.world.mode == "clear")
	app.paused = true
	app.world.mode = "checkpoint"
	app.world.run.coins = 100
	app.resume_game()
	await frames()
	await target("nav_id", "repay_0")
	await key(KEY_ENTER)
	expect("keyboard_repay", app.world.run.contracts.is_empty())
	for kind in ["sacrifice", "judge", "angel"]:
		await room(kind, 9320)
		app.world.player.hp = 10
		app.world.player.max_hp = 12
		app.ui_signature = ""
		await frames()
		await target("nav_id", "choice_0")
		await key(KEY_ENTER)
		expect("keyboard_special_" + kind, app.world.mode == "clear" and app.world.run.special_rooms.has(app.world.room_key()))
	await room("event")
	await key(KEY_ENTER)
	expect("keyboard_event_choice", app.world.run.name_pages == 1)
	await room("reward", 9400)
	app.paused = true
	app.world.run.relics.clear()
	for i in 12: app.world.run.relics["r%02d" % (i + 1)] = 1
	app.world.choices = [{"kind": "relic", "id": "r17", "price": 0}]
	app.resume_game()
	await frames()
	await key(KEY_ENTER)
	expect("replacement_keyboard_entry", app.world.mode == "replace", app.world.mode)
	await key(KEY_RIGHT)
	await key(KEY_ENTER)
	expect("replacement_keyboard_complete", app.world.mode == "clear" and app.world.run.relics.has("r17") and app.world.run.relics.size() == 12, app.world.mode)
	await key(KEY_ESCAPE)
	await action("本局记录")
	await key(KEY_DOWN)
	await key(KEY_END)
	await key(KEY_ESCAPE)
	await action("存下这页 · 回主菜单")
	await action("还愿庭")
	await action("动身还愿  →")
	expect("hub_keyboard_character_entry", app.menu_page == "characters")
	await key(KEY_ESCAPE)
	await action("记录")
	await action("旧愿")
	await key(KEY_ESCAPE)
	expect("story_hub_returns_stats", app.screen == "menu" and app.menu_page == "stats")
	# Finished-run fixture: no live run is credited or overwritten by viewing it.
	await fixture(9500)
	app.world.run.result = "defeat"
	app.world.mode = "result"
	app.world.player.hp = 0
	app.show_result()
	await frames()
	await action("受击与愿页")
	expect("keyboard_result_review", app.screen == "run_review")
	await action("查看本局构筑")
	expect("keyboard_review_build", app.screen == "run_build")
	await key(KEY_ESCAPE)
	expect("build_returns_review", app.screen == "run_review")
	await key(KEY_ESCAPE)
	expect("review_returns_result", app.screen == "result")
	await key(KEY_ESCAPE)
	expect("result_returns_main", app.screen == "menu" and app.menu_page == "title")
	await fixture(9520)
	app.world.run.result = "victory"
	app.world.mode = "result"
	app.world.run.floor = 3
	app.world.run.bosses_defeated = ["b01", "b02", "b03"]
	app.show_result()
	await frames()
	expect("victory_to_ending_choice", app.screen == "endings")
	await key(KEY_ENTER)
	expect("keyboard_ending_commit", app.screen == "result" and app.world.run.ending == "burn" and app.progress.data.endings.has("burn"))
	await key(KEY_ESCAPE)
	await action("记录")
	await action("结局")
	await action("焚账")
	expect("keyboard_ending_archive_read", app.menu_page == "ending_view")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	await action("离开")
	await key(KEY_ESCAPE)
	expect("keyboard_exit_cancel", app.screen == "menu" and app.menu_page == "title")
	await key(KEY_ESCAPE)
	await target("save_slot", "3")
	await key(KEY_ENTER)
	expect("slot_3_independent_defaults", app.save_slot == 3 and app.progress.data.endings.is_empty() and is_equal_approx(app.settings.master_volume, .8))
	await key(KEY_ESCAPE)
	await target("save_slot", "2")
	await key(KEY_ENTER)
	expect("slot_2_progress_restored", app.save_slot == 2 and app.progress.data.endings.has("burn"))
	await action("挑战")
	await action("选择挑战角色")
	await action("入巷还愿  →")
	if app.screen == "new_run_confirm": await action("确认开始新局")
	expect("keyboard_daily_start", app.screen == "tutorial" and app.world.run.daily and not app.world.run.daily_key.is_empty())
	await key(KEY_ENTER)
	await key(KEY_ESCAPE)
	await action("存下这页 · 回主菜单")
	await action("设置")
	await action("愿簿传递")
	var incoming = app.save_session.portable_bundle()
	incoming.profile.wish_name = "键盘验收"
	DisplayServer.clipboard_set(app.SaveUI.Transfer.export_code(incoming))
	await action("粘贴并预览")
	await key(KEY_TAB)
	await action("从剪贴板粘贴")
	await action("预览愿簿")
	await action("确认换入愿簿")
	expect("keyboard_import_commit", app.menu_page == "title" and app.progress.data.wish_name == "键盘验收" and not app.save_session.current.backup.is_empty())
	await action("设置")
	await action("愿簿传递")
	await action("回到导入前")
	await action("确认恢复")
	expect("keyboard_import_undo", app.menu_page == "title" and app.progress.data.wish_name != "键盘验收" and app.save_session.current.backup.is_empty())
	app.mobile_ui = true
	app.mobile_button_height = 90
	app.show_menu("title")
	await frames()
	await target("nav_id", "quit")
	expect("compact_main_keyboard_scroll", app.keyboard.first_scroll(app.modal).scroll_vertical > 0)
	await capture("main-mobile")
	app.open_character_select("normal")
	await frames()
	await capture("characters-mobile")
	var buttons: Array = []
	for semantic in ["角色详情", "角色成就", "初始器具", "入巷还愿  →"]:
		buttons.append(app.qa_button(app.modal, semantic))
	var overlap = false
	var notice_overlap = false
	for i in buttons.size():
		if buttons[i].get_global_rect().intersects(app.notice_label.get_parent().get_global_rect()): notice_overlap = true
		for j in range(i + 1, buttons.size()):
			if buttons[i].get_global_rect().intersects(buttons[j].get_global_rect()): overlap = true
	expect("compact_character_actions_do_not_overlap", not overlap)
	expect("menu_notice_does_not_cover_actions", app.notice_left > 0 and not notice_overlap)
	app.mobile_ui = false

func finish() -> void:
	DisplayServer.clipboard_set(previous_clipboard)
	var failures = checks.filter(func(item): return not item.passed)
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures,
		"driver": "native Input.parse_input_event key presses/releases; Tab navigation only; no mouse events, no grab_focus or button pressed emissions by the test driver",
		"scope": "native desktop menu and optional-room fixtures; not a human balance playtest or mobile device acceptance"}
	var file = FileAccess.open(directory.path_join("keyboard-flow.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("KEYBOARD FLOW: ", checks.size(), " checks; ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
