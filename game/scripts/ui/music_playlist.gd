extends RefCounted
## Shuffle every track once per cycle; this RNG is independent of combat and saves.
var tracks: Array = []
var bag: Array = []
var current_id = ""
var current: Dictionary = {}
var rng = RandomNumberGenerator.new()
var cycles = 0

func _init() -> void:
	rng.randomize()
	if FileAccess.file_exists("res://data/music_playlist.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/music_playlist.json"))
		for track in data.get("tracks", []):
			if ResourceLoader.exists(str(track.path)): tracks.append(track)

func next_track() -> Dictionary:
	if tracks.is_empty(): return {}
	if bag.is_empty():
		bag = range(tracks.size())
		for i in range(bag.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			var value = bag[i]
			bag[i] = bag[j]
			bag[j] = value
		# The next pop is at the end, so rotate a repeated cycle boundary away.
		if tracks.size() > 1 and str(tracks[bag.back()].id) == current_id:
			var first = bag[0]
			bag[0] = bag.back()
			bag[bag.size() - 1] = first
		cycles += 1
	current = tracks[bag.pop_back()]
	current_id = str(current.id)
	return current
