extends RefCounted
## Three local save slots with an independent selection journal. Slot 1 keeps the
## original user:// paths so existing Alpha saves migrate without copying files.
const Store = preload("res://scripts/core/save_store.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Content = preload("res://scripts/core/content_db.gd")

const SLOT_COUNT := 3
var root: String
var index_store
var selected: int = 1
var db = Content.new()

func _init(base: String = "user://") -> void:
	root = base
	index_store = Store.new(root.path_join("slot_index"))
	var index = index_store.read()
	if index.get("version", 0) == 1 and Store.integer(index.get("selected", 1)):
		selected = clampi(int(index.selected), 1, SLOT_COUNT)

func selected_slot() -> int:
	return selected

func select(slot: int) -> bool:
	var value = clampi(slot, 1, SLOT_COUNT)
	if value == selected: return true
	var previous = selected
	selected = value
	if index_store.write({"version": 1, "selected": selected}): return true
	selected = previous
	return false

func base_path(slot: int = selected) -> String:
	var value = clampi(slot, 1, SLOT_COUNT)
	return root if value == 1 else root.path_join("slots").path_join("slot_%d" % value)

func legacy_profile_path(slot: int = selected) -> String:
	return "" if clampi(slot, 1, SLOT_COUNT) == 1 else base_path(slot).path_join("profile")

func legacy_run_path(slot: int = selected) -> String:
	return "" if clampi(slot, 1, SLOT_COUNT) == 1 else base_path(slot).path_join("saves")

func summary(slot: int = selected) -> Dictionary:
	var value = clampi(slot, 1, SLOT_COUNT)
	var base = base_path(value)
	var bundle = Store.new(base.path_join("save_bundle")).read()
	if bundle.is_empty():
		var profile_path = base.path_join("profile")
		var legacy_profile = Store.new(profile_path).read()
		if legacy_profile.is_empty(): return {"slot": value, "occupied": false, "active": value == selected, "label": "空白槽位"}
		bundle = {"profile": legacy_profile, "checkpoint": Store.new(base.path_join("saves")).read()}
	var profile_result = Migration.profile(bundle.get("profile", {}))
	var run_result = Migration.world(bundle.get("checkpoint", {}))
	if not profile_result.ok: return {"slot": value, "occupied": true, "active": value == selected, "label": "需恢复", "protected": true}
	var profile = profile_result.data
	var run = run_result.data if run_result.ok else {}
	var checkpoint_run = run.get("run", {})
	var character = str(checkpoint_run.get("character", ""))
	var run_label = "无进行中还愿"
	if not checkpoint_run.is_empty() and str(checkpoint_run.get("result", "")) == "":
		run_label = "第%d章 · 房%d · %s" % [int(checkpoint_run.get("floor", 1)), int(checkpoint_run.get("room", 0)) + 1, db.name_of("characters", character)]
	return {"slot": value, "occupied": true, "active": value == selected, "label": "善缘 %d" % int(profile.get("merit", 0)),
		"merit": int(profile.get("merit", 0)), "characters": profile.get("characters", []).size(), "run": run_label,
		"has_run": not checkpoint_run.is_empty() and str(checkpoint_run.get("result", "")) == "", "achievements": profile.get("achievements", []).size()}

func summaries() -> Array:
	var result: Array = []
	for slot in range(1, SLOT_COUNT + 1): result.append(summary(slot))
	return result
