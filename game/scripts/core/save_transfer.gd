extends RefCounted
## Same checked offline format for files and compressed text on every native platform.
const Store = preload("res://scripts/core/save_store.gd")
const Session = preload("res://scripts/core/save_session.gd")
const MAX_BYTES = Store.MAX_BYTES
const FORMAT = "incense-debt-save"

static func export_text(bundle: Dictionary) -> String:
	var payload = JSON.stringify(Store.encode(bundle), "", true, true)
	return JSON.stringify({"format": FORMAT, "schema": 2, "number_encoding": Store.NUMBER_ENCODING, "created_at": Time.get_datetime_string_from_system(true), "sha256": payload.sha256_text(), "payload": payload}, "", true, true)

static func export_code(bundle: Dictionary) -> String:
	var bytes = export_text(bundle).to_utf8_buffer()
	if bytes.size() > MAX_BYTES: return ""
	var packed = bytes.compress(FileAccess.COMPRESSION_ZSTD)
	return "IDEBT2:%d:%s:%s" % [bytes.size(), packed.hex_encode().sha256_text(), Marshalls.raw_to_base64(packed)]

static func inspect_text(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "message": "愿簿文件过大，当前进度没有改变。"}
	var parser = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return {"ok": false, "message": "这份文件不是完整愿簿，当前进度没有改变。"}
	var envelope: Dictionary = parser.data
	if envelope.get("format", "") != FORMAT or not Store.integer(envelope.get("schema")) or int(envelope.schema) not in [1, 2] or not envelope.get("payload") is String: return {"ok": false, "message": "愿簿格式或版本无法识别，请保留原文件。"}
	if envelope.get("number_encoding", "decimal-json") not in ["decimal-json", Store.NUMBER_ENCODING]: return {"ok": false, "message": "愿簿数值编码尚不兼容，请保留原文件。"}
	if envelope.payload.sha256_text() != envelope.get("sha256", ""): return {"ok": false, "message": "愿簿校验未通过，请重新传递完整文件。"}
	if parser.parse(envelope.payload) != OK or not parser.data is Dictionary or not Store.valid_tree(parser.data, 0, [200000]): return {"ok": false, "message": "愿簿数据损坏，当前进度没有改变。"}
	var bundle: Dictionary = Store.decode(parser.data)
	# v1 transport already paired account and run but had no bundle version.
	if envelope.schema == 1 and not bundle.has("version"): bundle.version = 2
	var result = Session.normalize_bundle(bundle)
	if result.ok and not result.data.checkpoint.is_empty() and result.data.checkpoint.run.get("training", false): return {"ok": false, "message": "训练记录不能覆盖正式还愿。"}
	return result

static func inspect_code(source: String) -> Dictionary:
	if source.length() > MAX_BYTES: return {"ok": false, "message": "传递文字过长，当前进度没有改变。"}
	var text = source.strip_edges().replace("\n", "").replace("\r", "").replace("\t", "").replace(" ", "")
	var parts = text.split(":")
	if parts.size() != 4 or parts[0] != "IDEBT2" or not parts[1].is_valid_int(): return {"ok": false, "message": "传递文字不完整，请粘贴整份愿簿。"}
	var length = int(parts[1])
	if length < 1 or length > MAX_BYTES or parts[3].length() > MAX_BYTES: return {"ok": false, "message": "愿簿大小超出可恢复范围。"}
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
	if parts[3].length() % 4 != 0 or pattern.search(parts[3]) == null: return {"ok": false, "message": "传递文字含有缺失或无效字符。"}
	var bytes = Marshalls.base64_to_raw(parts[3])
	if bytes.hex_encode().sha256_text() != parts[2]: return {"ok": false, "message": "传递文字校验未通过，请重新复制。"}
	var decoded = bytes.decompress(length, FileAccess.COMPRESSION_ZSTD)
	if decoded.size() != length: return {"ok": false, "message": "传递文字无法展开，请重新导出。"}
	return inspect_text(decoded.get_string_from_utf8())

static func read_file(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "message": "这份愿簿无法打开，当前进度没有改变。"}
	if file.get_length() > MAX_BYTES: return {"ok": false, "message": "愿簿文件过大，当前进度没有改变。"}
	return inspect_text(file.get_as_text())

static func write_file(path: String, bundle: Dictionary) -> bool:
	var text = export_text(bundle)
	if text.to_utf8_buffer().size() > MAX_BYTES: return false
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	var result = file.get_error() == OK
	file.close()
	return result
