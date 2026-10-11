extends RefCounted
## Bounded attack provenance survives its emitter and never consumes gameplay RNG.
const Store = preload("res://scripts/core/save_store.gd")
const KINDS = ["unknown", "projectile", "split", "contact", "lunge", "zone", "debt", "hazard", "explosion"]
const ROLES = ["", "guard", "clone", "sigil"]
const LABELS = {"unknown": "未记来源", "projectile": "飞弹", "split": "裂弹", "contact": "近身", "lunge": "冲撞", "zone": "印区", "debt": "催债弹", "hazard": "铜刺", "explosion": "障碍爆炸"}

static func normalize(source: Dictionary, origin: Vector2, kind: String = "unknown") -> Dictionary:
	return {"id": str(source.get("id", "")), "table": str(source.get("table", "")), "kind": str(source.get("kind", kind)),
		"origin": Vector2(source.get("origin", origin)), "elite_id": str(source.get("elite_id", "")), "role": str(source.get("role", ""))}

static func from_enemy(w, enemy: Dictionary, kind: String) -> Dictionary:
	var identity = enemy
	var role = ""
	if enemy.has("guarding_boss"):
		role = "clone" if enemy.get("clone", false) else ("sigil" if enemy.get("sigil", false) else "guard")
		if role in ["clone", "sigil"]:
			var owner = w.enemy_by_uid(enemy.guarding_boss)
			if not owner.is_empty(): identity = owner
	return normalize({"id": identity.id, "table": "bosses" if identity.boss else "enemies", "kind": kind,
		"elite_id": identity.get("elite_id", ""), "role": role}, enemy.pos)

static func valid_source(source, db) -> bool:
	if not source is Dictionary: return false
	for key in ["id", "table", "kind", "elite_id", "role"]:
		if not source.get(key) is String: return false
	if not source.get("origin") is Vector2 or not source.origin.is_finite() or source.kind not in KINDS or source.role not in ROLES: return false
	if source.table not in ["", "enemies", "bosses", "debt_contracts", "obstacles"]: return false
	if source.table.is_empty():
		if not source.id.is_empty() or not source.elite_id.is_empty() or not source.role.is_empty(): return false
	elif db.row(source.table, source.id).is_empty(): return false
	if not source.elite_id.is_empty() and (source.table != "enemies" or db.row("elite_variants", source.elite_id).is_empty()): return false
	return true

static func valid_record(record, db) -> bool:
	if not record is Dictionary or not valid_source(record.get("source"), db): return false
	for key in ["raw", "damage", "absorbed", "hp_before", "hp_after", "floor", "room"]:
		if not Store.integer(record.get(key)) or record[key] < 0: return false
	if not Store.number(record.get("at")) or record.at < 0: return false
	if not record.get("pos") is Vector2 or not record.pos.is_finite() or not record.get("direction") is Vector2 or not record.direction.is_finite(): return false
	if not record.get("revived") is bool or not record.get("lethal") is bool: return false
	if record.raw <= 0 or record.hp_before <= 0: return false
	if record.hp_after != (1 if record.revived else maxi(0, record.hp_before - record.damage)): return false
	if record.revived and record.damage < record.hp_before: return false
	return int(record.floor) >= 1 and int(record.floor) <= 11 and record.damage + record.absorbed == record.raw and record.lethal == (record.hp_after == 0) and not (record.revived and record.lethal)

static func name_of(db, source: Dictionary) -> String:
	if source.get("table", "").is_empty(): return "未记攻击者"
	var name = db.name_of(source.table, source.id)
	if not source.get("elite_id", "").is_empty(): name = db.name_of("elite_variants", source.elite_id)
	return name + {"guard": " · 护账", "clone": " · 分身", "sigil": " · 护签"}.get(source.get("role", ""), "")

static func brief(db, record: Dictionary) -> String:
	if record.is_empty(): return "这页未记受击来源"
	return name_of(db, record.source) + " · " + LABELS.get(record.source.kind, "未记来源")

static func art_path(db, source: Dictionary) -> String:
	if source.get("role", "") == "sigil": return "res://assets/relics/r06.png"
	if not source.get("elite_id", "").is_empty(): return "res://assets/elites/" + source.elite_id + ".png"
	var table = str(source.get("table", ""))
	if table == "obstacles": return "res://assets/obstacles/" + source.id + ".png"
	if table == "debt_contracts": return "res://assets/relics/" + db.row(table, source.id).reward + ".png"
	return "res://assets/" + table + "/" + source.id + ".png" if table in ["enemies", "bosses"] else ""
