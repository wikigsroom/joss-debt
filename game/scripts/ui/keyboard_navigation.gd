extends RefCounted
## One modal focus owner. Combat keys and UI keys never share a live frame.
var memory: Dictionary = {}
var scope = ""
var pending = 0
var enabled = false
var hint: Label
var ring: Panel

func before_rebuild(app) -> void:
	remember(app)
	pending = 2
	hint = null

func remember(app) -> void:
	var focus = app.get_viewport().gui_get_focus_owner()
	if enabled and is_instance_valid(focus) and app.modal.is_ancestor_of(focus):
		memory[scope] = token(focus, candidates(app.modal))

func active(app) -> bool:
	return app.screen != "game" or app.world.mode in ["choice", "shop", "debt", "replace", "checkpoint", "result", "transition", "epilogue"]

func context(app) -> String:
	if app.screen == "menu": return "menu/" + app.menu_page
	if app.screen == "hub": return "hub/" + app.hub_page
	if app.screen == "game":
		var kind = str(app.world.choices[0].kind) if not app.world.choices.is_empty() else ""
		return "game/" + app.world.room_key() + "/" + app.world.mode + "/" + kind
	return app.screen + "/" + str(app.modal.get_meta("navigation_page", ""))

func candidates(root: Node) -> Array:
	var result: Array = []
	for child in root.get_children():
		if child is Control and not child.is_visible_in_tree(): continue
		if child is Control and child.focus_mode == Control.FOCUS_ALL and not child is ScrollBar:
			if not child is BaseButton or not child.disabled: result.append(child)
		result.append_array(candidates(child))
	return result

func token(control: Control, controls: Array) -> String:
	for key in ["nav_id", "save_slot", "character_id", "item_id", "preview_skill_id", "damage_index", "shop_trial_index", "setting_key"]:
		if control.has_meta(key): return key + ":" + str(control.get_meta(key))
	if control.has_meta("action_label") and not str(control.get_meta("action_label")).is_empty():
		return "action:" + str(control.get_meta("action_label"))
	return "index:" + str(controls.find(control))

func update(app) -> void:
	var next_enabled = active(app)
	if not next_enabled:
		if enabled:
			var owner = app.get_viewport().gui_get_focus_owner()
			if is_instance_valid(owner): owner.release_focus()
		enabled = false
		pending = 0
		return
	if pending > 0:
		pending -= 1
		if pending > 0: return
		settle(app)
	elif not enabled or not is_instance_valid(app.get_viewport().gui_get_focus_owner()):
		settle(app)

func settle(app) -> void:
	enabled = active(app)
	if not enabled: return
	scope = context(app)
	var controls = candidates(app.modal)
	if controls.is_empty(): return
	var target = null
	var saved = str(memory.get(scope, ""))
	for control in controls:
		if token(control, controls) == saved:
			target = control
			break
	if target == null:
		var owner = app.get_viewport().gui_get_focus_owner()
		if controls.has(owner): target = owner
	if target == null:
		for control in controls:
			if control.get_meta("nav_default", false):
				target = control
				break
	if target == null: target = controls[0]
	for control in controls:
		if not control.has_meta("navigation_wired"):
			control.set_meta("navigation_wired", true)
			control.focus_entered.connect(func(): reveal(control); describe(app, control))
		if control is ScrollContainer: control.follow_focus = true
	focus(app, target)

func reveal(control: Control) -> void:
	var ancestor = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.follow_focus = true
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()

func describe(app, control: Control) -> void:
	if is_instance_valid(ring): ring.queue_free()
	if not control is BaseButton:
		ring = Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.add_theme_stylebox_override("panel", app.UI.style(Color.TRANSPARENT, app.UI.ACCENT, 18, 2))
		control.add_child(ring)
	if app.mobile_ui: return
	if not is_instance_valid(hint):
		hint = Label.new()
		hint.position = Vector2(48, 692)
		hint.size = Vector2(1184, 25)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", app.UI.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app.modal.add_child(hint)
	var name_value = control.accessibility_name
	if name_value.is_empty(): name_value = str(control.get_meta("action_label", ""))
	if name_value.is_empty(): name_value = str(control.get_meta("keyboard_label", ""))
	hint.text = "↑ ↓ ← → 选择  ·  Enter 确认  ·  Esc 返回  ·  Tab 切换  ·  F1 详情" + ("    /    " + name_value if not name_value.is_empty() else "")

func focus(app, target: Control) -> void:
	target.grab_focus()
	reveal(target)
	describe(app, target)
	memory[scope] = token(target, candidates(app.modal))

func step(app, direction: Vector2) -> void:
	var controls = candidates(app.modal)
	if controls.is_empty(): return
	var owner = app.get_viewport().gui_get_focus_owner()
	if not controls.has(owner):
		focus(app, controls[0])
		return
	var rect: Rect2 = owner.get_global_rect()
	var center = rect.get_center()
	var best = null
	var score = INF
	for control in controls:
		if control == owner: continue
		var candidate: Rect2 = control.get_global_rect()
		var offset = candidate.get_center() - center
		var along = offset.dot(direction)
		if along <= 1: continue
		var across = absf(offset.cross(direction))
		var overlap = (candidate.position.x < rect.end.x and candidate.end.x > rect.position.x) if direction.y != 0 else (candidate.position.y < rect.end.y and candidate.end.y > rect.position.y)
		var candidate_score = along + across * (0.35 if overlap else 3.0)
		if candidate_score < score:
			score = candidate_score
			best = control
	if best != null: focus(app, best)

func cycle(app, backwards: bool) -> void:
	var controls = candidates(app.modal)
	if controls.is_empty(): return
	var current = controls.find(app.get_viewport().gui_get_focus_owner())
	focus(app, controls[posmod(current + (-1 if backwards else 1), controls.size())])

func scroll_for(app, owner) -> ScrollContainer:
	var node = owner
	while is_instance_valid(node):
		if node is ScrollContainer: return node
		node = node.get_parent()
	return first_scroll(app.modal)

func first_scroll(root: Node) -> ScrollContainer:
	for child in root.get_children():
		if child is ScrollContainer and child.is_visible_in_tree(): return child
		var found = first_scroll(child)
		if found != null: return found
	return null

func handle(app, event: InputEvent) -> bool:
	if not active(app) or not event is InputEventKey: return false
	var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var owner = app.get_viewport().gui_get_focus_owner()
	# Godot's popup owns its own arrows/Enter/Escape until it closes.
	if owner is OptionButton and owner.get_popup().visible: return false
	if not event.pressed: return code in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_TAB]
	if code == KEY_ESCAPE:
		if not event.echo: app.go_back()
		return true
	if code == KEY_TAB:
		if app.screen == "route" and not event.ctrl_pressed: app.go_back()
		else: cycle(app, event.shift_pressed)
		return true
	if app.screen == "inventory" and app.adapter.profile.event_matches("inventory", event):
		app.go_back()
		return true
	if owner is LineEdit or owner is TextEdit: return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	if code == KEY_F1:
		if is_instance_valid(owner) and not event.echo: app.show_focus_help(owner)
		return true
	if app.screen == "game" and app.world.mode in ["choice", "shop", "debt"]:
		var index = app.ChoiceShortcuts.index_for(event)
		if index >= 0:
			if not event.echo and index < app.world.choices.size():
				if app.mobile_ui:
					app.mobile_choice = index
					app.clear_modal()
					app.show_choices()
				else: app.choose_index(index)
			return true
	if code in [KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
		if owner is RichTextLabel:
			var bar = owner.get_v_scroll_bar()
			if code == KEY_HOME: bar.value = 0
			elif code == KEY_END: bar.value = bar.max_value
			else: bar.value += owner.size.y * .8 * (-1 if code == KEY_PAGEUP else 1)
			return true
		var scroll = scroll_for(app, owner)
		if scroll != null:
			if code == KEY_HOME: scroll.scroll_vertical = 0
			elif code == KEY_END: scroll.scroll_vertical = 100000
			else: scroll.scroll_vertical += roundi(scroll.size.y * .8) * (-1 if code == KEY_PAGEUP else 1)
		return true
	if code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		if owner is RichTextLabel and code in [KEY_UP, KEY_DOWN]:
			owner.get_v_scroll_bar().value += 64 * (-1 if code == KEY_UP else 1)
			return true
		if owner is Slider and code in [KEY_LEFT, KEY_RIGHT]: return false
		if is_instance_valid(owner) and owner.get_meta("keyboard_editor", false): return false
		if owner is ScrollContainer and code in [KEY_UP, KEY_DOWN]:
			owner.scroll_vertical += 64 * (-1 if code == KEY_UP else 1)
		else: step(app, {KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT}[code])
		return true
	if code in [KEY_ENTER, KEY_KP_ENTER]:
		if owner is OptionButton or (is_instance_valid(owner) and owner.get_meta("keyboard_editor", false)): return false
		if owner is BaseButton and not owner.disabled and not event.echo:
			if owner.toggle_mode: owner.button_pressed = not owner.button_pressed
			owner.pressed.emit()
		return true
	return false
