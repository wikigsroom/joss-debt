extends RefCounted
## Lazy atlas textures keep the active chapter small; the paper-puppet pivots are shared.
const COUNTS = {"character": {"idle": 4, "run": 6, "cast": 4, "dash": 3, "hurt": 2, "death": 5},
	"enemy": {"idle": 3, "move": 4, "tell": 3, "attack": 3, "hurt": 2, "death": 5},
	"boss": {"idle": 3, "move": 8, "attack_a": 4, "attack_b": 4, "attack_c": 4, "phase": 3, "hurt": 2, "death": 6}, "npc": {"idle": 3, "talk": 3}}
const FPS = {"idle": 5, "run": 12, "move": 10, "cast": 12, "dash": 15, "hurt": 16, "death": 10,
	"tell": 10, "attack": 12, "attack_a": 10, "attack_b": 12, "attack_c": 14, "phase": 8, "talk": 6}
var strips: Dictionary = {}
var frames: Dictionary = {}

func texture(id: String, kind: String, state: String, elapsed: float, direction: String = "down") -> Texture2D:
	var character_kind = kind in ["character", "weapon_body", "weapon_hand"]
	var folder = {"character": "characters", "weapon_body": "weapon-bodies/animation", "weapon_hand": "weapon-bodies/hands", "enemy": "enemy-animation", "boss": "boss-animation", "npc": "npc-animation"}[kind]
	if id.begins_with("x"): folder = "elite-animation"
	var path = "res://assets/%s/%s/%s.png" % [folder, id, state]
	if not strips.has(path):
		if not ResourceLoader.exists(path): return null
		strips[path] = load(path)
	var column = frame_index("character" if character_kind else kind, state, elapsed)
	if kind in ["enemy", "boss"] and not id.begins_with("x") and int(id.substr(1)) >= (6 if kind == "boss" else 25):
		var count = int(strips[path].get_width() / (256 if kind == "boss" else 128))
		var index = maxi(0, int(elapsed * FPS[state]))
		column = index % count if state in ["idle", "move"] else mini(index, count - 1)
	var row = ["down", "left", "right", "up"].find(direction) if character_kind else 0
	var frame_size = 96 if character_kind else (256 if kind == "boss" else 128)
	var key = "%s:%d:%d" % [path, column, row]
	if not frames.has(key):
		var frame = AtlasTexture.new()
		frame.atlas = strips[path]
		frame.region = Rect2(column * frame_size, row * frame_size, frame_size, frame_size)
		frames[key] = frame
	return frames[key]

static func frame_index(kind: String, state: String, elapsed: float) -> int:
	var count = int(COUNTS[kind][state])
	var column = maxi(0, int(elapsed * FPS[state]))
	return column % count if state in ["idle", "run", "move", "talk"] else mini(column, count - 1)

func clear() -> void:
	frames.clear()
	strips.clear()
