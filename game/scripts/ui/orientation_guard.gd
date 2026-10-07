extends RefCounted
## Hysteresis protects portrait/split surfaces; returning to landscape never resumes play.
var blocked = false

func observe(surface: Vector2i) -> String:
	if surface.x <= 0 or surface.y <= 0: return ""
	var aspect = float(surface.x) / surface.y
	if not blocked and aspect <= 1.05:
		blocked = true
		return "blocked"
	if blocked and aspect >= 1.20:
		blocked = false
		return "restored"
	return ""
