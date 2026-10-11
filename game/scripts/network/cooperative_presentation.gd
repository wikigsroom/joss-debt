extends "res://scripts/combat/world.gd"
## Read-only rendering world. No client combat/loot/door authority.
var online_stairs = false
var online_scene = -1

func room_doors() -> Array:
	if online_stairs: return [{"direction": "north", "destination": -1, "pos": room_door_position("north"), "visited": false}]
	return super.room_doors()
