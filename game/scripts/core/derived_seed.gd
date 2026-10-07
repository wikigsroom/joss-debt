extends RefCounted
## Versioned, platform-independent SHA-256 derivation. Presentation has no access to streams.
const RandomStream = preload("res://scripts/core/run_rng.gd")
const VERSION = "incense-derived-v1"

static func valid(value: String) -> bool:
	if value.length() != 12: return false
	for i in value.length():
		if value.unicode_at(i) < 48 or value.unicode_at(i) > 57: return false
	return true

static func text(value: int) -> String:
	return "%012d" % posmod(value, 1000000000000)

static func fresh() -> String:
	var bytes = Crypto.new().generate_random_bytes(6)
	var value: int = 0
	for byte in bytes: value = value * 256 + int(byte)
	return text(value)

static func derive(seed_text: String, domain: String):
	assert(valid(seed_text))
	var digest = (VERSION + "\n" + seed_text + "\n" + domain).sha256_text()
	return RandomStream.new(posmod(digest.substr(0, 8).hex_to_int(), 2147483646))
