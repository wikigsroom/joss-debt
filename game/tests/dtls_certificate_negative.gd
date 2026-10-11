extends SceneTree
## Intentional TLS verification failures. Run separately from clean-log suites.
const Battle = preload("res://scripts/network/enet_battle.gd")
var mode = "hostname"
var output = ""
var server = Battle.new()
var client = Battle.new()
var ever_connected = false
var begin = 0
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if server.start_server("127.0.0.1", 19289, 2, {}) != OK: quit(1); return
	var pem = server.certificate_pem
	if mode == "trust":
		var other = Battle.new()
		if other.start_server("127.0.0.1", 19290, 1, {}) != OK: quit(1); return
		pem = other.certificate_pem; other.close()
	var error = client.connect_client("127.0.0.1", 19289, "different.invalid" if mode == "hostname" else "localhost", pem)
	if error != OK: quit(1); return
	begin = Time.get_ticks_msec()
func _process(_delta: float) -> bool:
	server.poll(); client.poll(); server.flush(); client.flush()
	ever_connected = ever_connected or client.connected()
	if Time.get_ticks_msec() - begin < 2500: return false
	client.close(); server.close()
	var passed = not ever_connected
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": passed, "mode": mode, "authenticated_transport_ever_connected": ever_connected,
		"scope": "Actual DTLS handshake with intentionally wrong hostname or unrelated trust root. Expected certificate verification errors are recorded separately."}, "\t") + "\n")
	quit(0 if passed else 1)
	return true
