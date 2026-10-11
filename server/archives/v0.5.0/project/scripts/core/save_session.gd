extends RefCounted
## Account and run commit in one checksum journal; imports preserve an independent undo snapshot.
const Store = preload("res://scripts/core/save_store.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
var journal
var current: Dictionary = {}
var pending: Dictionary = {}
var batching = false
var read_only = false
var message = ""

class JournalView extends RefCounted:
	var owner: WeakRef
	var key: String
	func _init(session, part: String) -> void:
		owner = weakref(session)
		key = part
	func read() -> Dictionary:
		var session = owner.get_ref()
		return session.current.get(key, {}).duplicate(true) if session != null else {}
	func write(value: Dictionary) -> bool:
		var session = owner.get_ref()
		return session.commit_part(key, value) if session != null else false

func _init(base: String = "user://", legacy_profile: String = "", legacy_run: String = "") -> void:
	journal = Store.new(base.path_join("save_bundle"))
	var data = journal.read()
	read_only = journal.read_only
	if read_only: message = "愿簿已保护：文件损坏或来自较新版本。原文件仍在保存目录，请保留并使用对应版本恢复。"
	var from_legacy = data.is_empty() and not read_only
	if from_legacy:
		var account = Store.new(legacy_profile if not legacy_profile.is_empty() else base.path_join("profile"))
		var run = Store.new(legacy_run if not legacy_run.is_empty() else base.path_join("saves"))
		data = {"version": 2, "profile": account.read(), "checkpoint": run.read(), "backup": {}}
		read_only = account.read_only or run.read_only
		if read_only: message = "旧愿簿已保护：存在损坏或未知版本，原文件没有被覆盖。"
	var normalized = normalize_bundle(data)
	if not normalized.ok:
		read_only = true
		message = normalized.message
		current = {"version": 2, "profile": Migration.profile({}).data, "checkpoint": {}, "backup": {}}
		return
	current = normalized.data
	if from_legacy and not read_only:
		if not journal.write(current):
			read_only = true
			message = "旧愿簿尚未转存成功，原文件已保留。检查保存目录后重试。"
		elif normalized.migrated: message = "旧愿簿已转存，原文件保留；当前还愿从暂停页继续。"
	elif journal.read_status == "recovered" and not read_only: message = "最新一代愿簿受损，已恢复上一份完整记录。"

static func normalize_bundle(source: Dictionary) -> Dictionary:
	if not Store.integer(source.get("version")) or int(source.version) != 2 or not source.get("profile") is Dictionary or not source.get("checkpoint") is Dictionary: return Migration.failure("这份整体愿簿版本或结构无法识别，原文件已保留。")
	if source.has("content_version") and source.content_version != Migration.content_version(): return Migration.failure("这份整体愿簿的内容版本尚不兼容，请保留原文件。")
	var profile = Migration.profile(source.profile)
	if not profile.ok: return profile
	var run = Migration.world(source.checkpoint)
	if not run.ok: return run
	var backup = source.get("backup", {})
	if not backup is Dictionary: return Migration.failure("导入前的备份记录损坏。")
	if not backup.is_empty():
		if not backup.get("profile") is Dictionary or not backup.get("checkpoint") is Dictionary: return Migration.failure("导入前的整体备份不完整。")
		var backup_profile = Migration.profile(backup.profile)
		var backup_run = Migration.world(backup.checkpoint)
		if not backup_profile.ok or not backup_run.ok: return Migration.failure("导入前的备份无法恢复，原文件已保留。")
		backup = {"profile": backup_profile.data, "checkpoint": backup_run.data}
	return {"ok": true, "data": {"version": 2, "content_version": Migration.content_version(), "profile": profile.data, "checkpoint": run.data, "backup": backup}, "migrated": profile.migrated or run.migrated}

func view(part: String):
	return JournalView.new(self, part)

func begin() -> bool:
	if read_only or batching: return false
	pending = current.duplicate(true)
	batching = true
	return true

func finish() -> bool:
	if not batching: return false
	batching = false
	var candidate = pending
	pending = {}
	return commit(candidate)

func commit(value: Dictionary) -> bool:
	if read_only or not journal.write(value): return false
	current = value.duplicate(true)
	return true

func commit_part(part: String, value: Dictionary) -> bool:
	if read_only or part not in ["profile", "checkpoint"]: return false
	if batching:
		pending[part] = value.duplicate(true)
		return true
	var candidate = current.duplicate(true)
	candidate[part] = value.duplicate(true)
	return commit(candidate)

func import_bundle(value: Dictionary, import_settings: bool = false) -> bool:
	if read_only or batching: return false
	var normalized = normalize_bundle(value)
	if not normalized.ok:
		message = normalized.message
		return false
	var candidate = normalized.data
	if not candidate.checkpoint.is_empty() and candidate.checkpoint.run.get("training", false):
		message = "训练记录不能覆盖正式还愿。"
		return false
	if not import_settings: candidate.profile.settings = current.profile.settings.duplicate(true)
	candidate.backup = {"profile": current.profile.duplicate(true), "checkpoint": current.checkpoint.duplicate(true)}
	if not commit(candidate):
		message = "愿簿未能写入，当前进度与导入前的备份都保持原样。"
		return false
	message = "愿簿已换入。准备好后从角色页继续，导入前的进度可在此恢复。"
	return true

func restore_backup() -> bool:
	if read_only or current.backup.is_empty(): return false
	var candidate = {"version": 2, "content_version": Migration.content_version(), "profile": current.backup.profile.duplicate(true), "checkpoint": current.backup.checkpoint.duplicate(true), "backup": {}}
	if not commit(candidate):
		message = "恢复未能写入，当前愿簿与备份都保持原样。"
		return false
	message = "已回到导入前的进度，准备好后再继续。"
	return true

func portable_bundle() -> Dictionary:
	return {"version": 2, "content_version": Migration.content_version(), "profile": current.profile.duplicate(true), "checkpoint": current.checkpoint.duplicate(true), "backup": {}}
