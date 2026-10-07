extends SceneTree
const World = preload("res://scripts/combat/world.gd")
const Store = preload("res://scripts/core/save_store.gd")
const Session = preload("res://scripts/core/save_session.gd")
const Transfer = preload("res://scripts/core/save_transfer.gd")
const Migration = preload("res://scripts/core/save_migrations.gd")
const Profile = preload("res://scripts/core/meta_progress.gd")
var checks: Array = []
var failures: Array = []
var root_path = ""
class RejectedJournal extends RefCounted:
	func write(_value: Dictionary) -> bool: return false

func _initialize() -> void:
	call_deferred("run_suite")

func expect(condition: bool, message: String) -> void:
	checks.append(message)
	if not condition:
		failures.append(message)
		push_error(message)

func write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func digest(value) -> String:
	return JSON.stringify(Store.encode(value), "", true, true).sha256_text()

func envelope(schema: int, revision: int, data: Dictionary) -> String:
	var payload = JSON.stringify(Store.encode(data), "", true, true)
	return JSON.stringify({"schema": schema, "revision": revision, "sha256": payload.sha256_text(), "payload": payload}, "", true, true)

func run_suite() -> void:
	root_path = "user://save_transfer_%d" % Time.get_ticks_usec()
	var old_profile = FileAccess.get_file_as_string("res://tests/fixtures/legacy_profile_v1.json")
	var old_run = FileAccess.get_file_as_string("res://tests/fixtures/legacy_run_v1.json")
	expect(old_profile.sha256_text() == "14963814f097c3657e1a8ff4cf681c2297c28e544f4b43f2b21d3be8036b54e7" and old_run.sha256_text() == "c4d40e06d738bb95495bbc8ac8f4ca0d61e29cae8f5a4221881c27973d576518", "golden migration inputs are actual frozen pre-migration native QA journals")
	var legacy_profile = Store.parse_envelope(old_profile)
	var legacy_run = Store.parse_envelope(old_run)
	expect(legacy_profile.schema == 1 and legacy_run.schema == 1 and legacy_profile.snapshot.version == 1 and legacy_run.snapshot.version == 1, "golden inputs genuinely use both the former envelope and payload schemas")
	write_text(root_path.path_join("legacy/profile/checkpoint_1.json"), old_profile)
	write_text(root_path.path_join("legacy/saves/checkpoint_1.json"), old_run)
	var legacy = Session.new(root_path.path_join("legacy"))
	expect(not legacy.read_only and legacy.current.profile.version == 2 and legacy.current.checkpoint.version == 2, "a real old account and saved room migrate together into the v2 journal")
	expect(legacy.current.profile.content_version == Migration.content_version() and legacy.current.checkpoint.content_version == Migration.content_version(), "the migrated account and run record their actual content version")
	expect(FileAccess.get_file_as_string(root_path.path_join("legacy/profile/checkpoint_1.json")) == old_profile and FileAccess.get_file_as_string(root_path.path_join("legacy/saves/checkpoint_1.json")) == old_run, "automatic migration preserves both original v1 files byte for byte")
	expect(legacy.current.profile.merit == legacy_profile.snapshot.merit and legacy.current.profile.characters == legacy_profile.snapshot.characters and legacy.current.profile.runs == legacy_profile.snapshot.runs, "legacy earned currency, character unlocks and credit ledger retain their exact values")
	expect(legacy.current.checkpoint.rng == legacy_run.snapshot.rng and legacy.current.checkpoint.streams == legacy_run.snapshot.streams and legacy.current.checkpoint.reward_ledger == legacy_run.snapshot.reward_ledger, "migration preserves each random cursor and already-claimed reward key")
	var resumed_legacy = World.new()
	expect(resumed_legacy.restore(legacy.current.checkpoint) and resumed_legacy.run.room == legacy_run.snapshot.run.room, "the migrated actual legacy room is playable through the authoritative restore path")
	var legacy_reopened = Session.new(root_path.path_join("legacy"))
	expect(digest(legacy_reopened.current) == digest(legacy.current), "a fresh writer reads the migrated joint account/run instead of remigrating the old files")
	var source = Session.new(root_path.path_join("source"))
	var account = Profile.new("", source.view("profile"))
	var w = World.new()
	w.start("c_paper", 8219, 3)
	w.run.id = "portable-earned-credit"
	w.run.merit = 17
	w.stats.max_chain = 3
	w.run.relics = {"r01": 1}
	w.run.talents = ["t_fire_1a"]
	w.run.contracts = [{"id": "d02", "interest": 6}]
	w.reward_once("portable-already-paid")
	w.roll("loot").next_int()
	account.observe(w)
	expect(source.begin(), "account and room transactions begin from one committed snapshot")
	account.data.settings = {"music_volume": .65, "muted": false}
	expect(account.save() and source.view("checkpoint").write(w.snapshot()) and source.finish(), "a joint transaction writes account settings and the complete room in one generation")
	var source_reload = Session.new(root_path.path_join("source"))
	expect(source_reload.current.profile.settings.music_volume == .65 and source_reload.current.checkpoint.run.id == w.run.id, "reload observes both halves of the same committed generation")
	var packed = Transfer.export_code(source.portable_bundle())
	var unpacked = Transfer.inspect_code(packed)
	if not unpacked.ok:
		print("Transfer diagnostic: ", unpacked.message)
		quit(1)
		return
	expect(unpacked.ok and digest(unpacked.data) == digest(source.portable_bundle()), "compressed offline transfer preserves the entire paired snapshot")
	expect(packed.length() < Transfer.export_text(source.portable_bundle()).length(), "a complete mid-run snapshot is practically compressed for text transfer")
	var wrapped = " \n" + packed.left(40) + "\n" + packed.substr(40) + " \n"
	expect(Transfer.inspect_code(wrapped).ok, "message line wrapping does not invalidate otherwise complete transfer text")
	var file_path = ProjectSettings.globalize_path(root_path.path_join("transfer.incense.json"))
	expect(Transfer.write_file(file_path, source.portable_bundle()) and Transfer.read_file(file_path).ok, "the same paired save survives a real exported file and native file read")
	# A counter observed in real native QA loses one bit through decimal JSON.
	var precise = source.portable_bundle()
	var counter = "d0063a6da0d3f63f".hex_decode().decode_double(0)
	precise.checkpoint.player.still = counter
	var precise_path = ProjectSettings.globalize_path(root_path.path_join("fractional.incense.json"))
	var precise_code = Transfer.inspect_code(Transfer.export_code(precise))
	var precise_file_ok = Transfer.write_file(precise_path, precise)
	var precise_read = Transfer.read_file(precise_path)
	expect(precise_file_ok and precise_read.ok and precise_code.ok and digest(precise_read.data) == digest(precise) and digest(precise_code.data) == digest(precise), "real file and compressed transfers preserve the exact fractional timer from the native regression")
	var exact_journal = Store.new(root_path.path_join("fractional-journal"))
	expect(exact_journal.write(precise) and digest(Store.new(root_path.path_join("fractional-journal")).read()) == digest(precise), "a newly opened native journal preserves the same fractional simulation timer")
	var future_encoding = JSON.parse_string(Transfer.export_text(precise))
	future_encoding.number_encoding = "future-f64-v99"
	expect(not Transfer.inspect_text(JSON.stringify(future_encoding)).ok and not Store.valid_tree({"__float64": "ffffffffffffff7f"}) and not Store.valid_tree({"__float64": "not-hex-not-hex!"}), "future numeric encodings and malformed or nonfinite double tags are rejected before restoration")
	var receiver = Session.new(root_path.path_join("receiver"))
	var receiver_profile = Profile.new("", receiver.view("profile"))
	receiver_profile.data.merit = 5
	receiver_profile.data.settings = {"music_volume": .2, "muted": true}
	receiver_profile.save()
	var before_import = receiver.portable_bundle()
	expect(receiver.import_bundle(unpacked.data), "a validated transfer can be deliberately imported on a second native save root")
	expect(receiver.current.profile.merit == source.current.profile.merit and receiver.current.profile.settings == before_import.profile.settings, "import moves earned progress while retaining local sound and control settings by default")
	expect(receiver.current.backup.profile.merit == 5 and receiver.current.backup.checkpoint.is_empty(), "import retains the independent pre-import account and room as one undo snapshot")
	var fresh = Session.new(root_path.path_join("receiver"))
	expect(fresh.current.backup.profile.merit == 5 and fresh.current.checkpoint.run.id == w.run.id, "both imported progress and the undo snapshot survive process-style reload")
	var continued = World.new()
	expect(continued.restore(fresh.current.checkpoint), "an imported in-flight room restores the real combat simulation")
	expect(not continued.reward_once("portable-already-paid"), "import cannot claim a previously committed room reward again")
	expect(digest(w.relic_offer(3)) == digest(continued.relic_offer(3)), "imported independent reward streams produce the same next offer without a reroll")
	for i in 30:
		var frame = {"move": Vector2.ZERO, "aim": Vector2.UP, "fire": false}
		w.tick(frame)
		continued.tick(frame)
	expect(digest(w.snapshot()) == digest(continued.snapshot()), "the same thirty real combat inputs continue identically after transfer")
	var fresh_account = Profile.new("", fresh.view("profile"))
	var earned = fresh_account.data.merit
	fresh_account.observe(continued)
	expect(fresh_account.data.merit == earned, "re-observing an imported run cannot credit its earned merit a second time")
	var state_before_failure = digest(fresh.current)
	var original_journal = fresh.journal
	fresh.journal = RejectedJournal.new()
	expect(not fresh.import_bundle(source.portable_bundle()) and digest(fresh.current) == state_before_failure, "failed import commit preserves both current progress and the independent backup")
	expect(not fresh.restore_backup() and digest(fresh.current) == state_before_failure, "failed undo commit preserves the imported state and its recovery snapshot")
	fresh.journal = original_journal
	expect(digest(Session.new(root_path.path_join("receiver")).current) == state_before_failure, "failed commits leave the original on-disk joint journal unchanged")
	expect(fresh.restore_backup() and fresh.current.profile.merit == 5 and fresh.current.checkpoint.is_empty() and fresh.current.backup.is_empty(), "explicit undo restores both pre-import halves and consumes only the undo action")
	expect(fresh.import_bundle(source.portable_bundle(), true) and fresh.current.profile.settings == source.current.profile.settings, "the explicit settings option can also transfer the source controls and sound preferences")
	var before_preview = digest(fresh.current)
	var broken = JSON.new()
	broken.parse(Transfer.export_text(source.portable_bundle()))
	broken.data.payload += " "
	expect(not Transfer.inspect_text(JSON.stringify(broken.data)).ok and digest(fresh.current) == before_preview, "damaged payload checksums fail preview without changing the current journal")
	expect(not Transfer.inspect_code(packed.left(packed.length() - 4)).ok, "truncated text transfer is rejected before unpacking")
	expect(not Transfer.inspect_code("IDEBT2:999999999:0:AAAA").ok, "declared expansion size is bounded before native allocation")
	expect(not Store.valid_tree({"pos": {"__vector2": [1]}}, 0, [200000]), "malformed vector tags cannot reach the decoder")
	var bad_profile = source.current.profile.duplicate(true)
	bad_profile.version = 99
	expect(not Migration.profile(bad_profile).ok, "future account payload versions enter protection instead of reset")
	bad_profile = source.current.profile.duplicate(true)
	bad_profile.content_version = "future-content"
	expect(not Migration.profile(bad_profile).ok, "unknown content versions are preserved rather than silently mapped")
	bad_profile = source.current.profile.duplicate(true)
	bad_profile.settings.touch = "wrong-type"
	expect(not Migration.profile(bad_profile).ok, "invalid control-setting types cannot enter a restored interface")
	var bad_run = source.current.checkpoint.duplicate(true)
	bad_run.player.weapon = "removed-unknown-weapon"
	expect(not Migration.world(bad_run).ok, "unknown equipment cannot silently become a different weapon")
	bad_run = source.current.checkpoint.duplicate(true)
	bad_run.run.graph.edges.append([0, 999])
	expect(not Migration.world(bad_run).ok, "out-of-range graph edges are rejected before room restoration")
	bad_run = source.current.checkpoint.duplicate(true)
	bad_run.room_flags.waves = ["not-an-enemy-array"]
	expect(not Migration.world(bad_run).ok, "damaged incoming-wave plans fail before they can respawn enemies")
	var held_world = continued.snapshot()
	expect(not continued.restore(bad_run) and digest(continued.snapshot()) == digest(held_world), "a rejected snapshot does not partially mutate a running world")
	var training = source.portable_bundle()
	training.checkpoint.run.training = true
	expect(not Transfer.inspect_text(Transfer.export_text(training)).ok, "training snapshots cannot replace formal progression through transport")
	var recovered = Session.new(root_path.path_join("recover"))
	recovered.view("profile").write(source.current.profile)
	var previous_complete = recovered.current.duplicate(true)
	recovered.view("checkpoint").write(source.current.checkpoint)
	var newest = recovered.journal.folder.path_join("checkpoint_%d.json" % (recovered.journal.revision % 2))
	write_text(newest, "half-written-checkpoint")
	var recovered_reload = Session.new(root_path.path_join("recover"))
	expect(not recovered_reload.read_only and digest(recovered_reload.current) == digest(previous_complete), "a damaged newest import-era journal falls back to a complete paired generation")
	expect(not recovered_reload.message.is_empty(), "checksum recovery gives the player a readable explanation")
	var protected_root = root_path.path_join("future")
	var protected = Session.new(protected_root)
	var future_file = protected.journal.folder.path_join("checkpoint_0.json")
	var future_bytes = envelope(77, protected.journal.revision + 1, protected.current)
	write_text(future_file, future_bytes)
	var protected_reload = Session.new(protected_root)
	expect(protected_reload.read_only and not protected_reload.message.is_empty(), "a genuine future envelope protects its files and explains why")
	expect(not protected_reload.view("profile").write(source.current.profile) and not protected_reload.import_bundle(source.portable_bundle()), "automatic saves and manual replacement cannot overwrite an unknown future journal")
	expect(FileAccess.get_file_as_string(future_file) == future_bytes, "future-version protection preserves original bytes after attempted writes")
	var batch = Session.new(root_path.path_join("batch"))
	var before_batch = digest(batch.current)
	batch.begin()
	batch.view("profile").write(source.current.profile)
	batch.view("checkpoint").write(source.current.checkpoint)
	batch.journal = RejectedJournal.new()
	expect(not batch.finish() and digest(batch.current) == before_batch, "failure of a combined account/run commit cannot expose only one new half")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"legacy_fixture_source": "frozen real v1 native QA journals; not relabeled current snapshots",
		"scope": "real native journal migration, paired import/reload/undo, deterministic simulation continuation, failure and future-version preservation; physical mobile file picker and clipboard remain device acceptance"}
	var file = FileAccess.open(ProjectSettings.globalize_path("res://../docs/incense-debt/reports/runtime/save-transfer-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Save migration and transfer: %d checks; %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
