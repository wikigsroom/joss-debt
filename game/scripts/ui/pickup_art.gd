extends RefCounted
## Shared generated objects for ground drops, healing offers and resource UI.
## Only presentation clocks are used; quantity and interaction remain in World.
const Clip = preload("res://scripts/ui/combat_fx.gd")
const ROOT = "res://assets/pickups/"
const KINDS = ["heal", "coin", "ash", "battery"]
const UI_KEYS = ["heart-solid", "heart", "heart-empty", "coins", "ash-pickup", "battery-pickup"]
const SIZES = {"heal": 44.0, "coin": 34.0, "coin_pair": 40.0, "ash": 36.0, "ash_bundle": 44.0, "battery": 46.0}
static var cache: Dictionary = {}

static func variant(drop: Dictionary) -> String:
	var kind = str(drop.kind)
	if kind == "coin" and int(drop.value) >= 2: return "coin_pair"
	if kind == "ash" and int(drop.value) >= 16: return "ash_bundle"
	return kind

static func path(id: String) -> String:
	return ROOT + id + ".png"

static func texture(id: String) -> Texture2D:
	if not cache.has(id): cache[id] = load(path(id))
	return cache[id]

static func icon(key: String) -> Texture2D:
	return texture(key + "-ui")

static func billboard(r, image: Texture2D, point: Vector2, size: float, angle: float = 0, tint: Color = Color.WHITE) -> void:
	Clip.sprite(r, image, point, Vector2(size, size / .84722), angle, tint)

static func draw(r, drop: Dictionary) -> void:
	var id = variant(drop)
	var size = float(SIZES[id])
	var phase = float(drop.uid) * .73
	var bob = 0.0 if r.reduce_motion else sin(r.clock * 2.6 + phase) * 2.0
	var tilt = 0.0 if r.reduce_motion or drop.kind == "ash" else sin(r.clock * 1.8 + phase) * .035
	var lift = 5.0 + bob
	var point = Vector2(drop.pos) - Vector2(0, (size * .36 + lift) / .84722)
	var nearby = Vector2(drop.pos).distance_squared_to(r.world.player.pos) < 96 * 96
	Clip.sprite(r, texture("ground-shadow"), drop.pos + Vector2(0, 3), Vector2(size * .85, 12), 0, Color(1, 1, 1, .9))
	# Both keylines follow the generated object's alpha, never a circle/diamond pedestal.
	billboard(r, texture(id + "-outline"), point, size + 2.0, tilt, Color(.08, .11, .13, .9))
	billboard(r, texture(id + "-outline"), point, size, tilt, Color(1, 1, 1, .65 if nearby else .4))
	billboard(r, texture(id), point, size, tilt)

static func collection(r, effect: Dictionary, progress: float) -> bool:
	var kind = str(effect.get("type", ""))
	if kind not in KINDS: return false
	# A brief rise of the very same generated object identifies the collected resource.
	var fade = (1.0 - progress) * .9
	var point = Vector2(effect.pos) - Vector2(0, (30 + (0 if r.reduce_motion else progress * 22)) / .84722)
	var size = 20.0 if r.reduce_motion else lerpf(24.0, 14.0, progress)
	billboard(r, texture(kind), point, size, 0, Color(1, 1, 1, fade))
	return true
