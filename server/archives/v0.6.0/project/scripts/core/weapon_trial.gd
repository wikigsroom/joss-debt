extends RefCounted
## The live shop stays untouched while its actual build is tried in a separate world.
const World = preload("res://scripts/combat/world.gd")
var origin
var index = -1

func active() -> bool:
	return origin != null

static func eligible(w, offer_index: int) -> bool:
	if w.run.is_empty() or w.mode != "shop" or w.run.get("training", false) or not w.run.result.is_empty() or offer_index < 0 or offer_index >= w.choices.size(): return false
	var choice: Dictionary = w.choices[offer_index]
	return choice.kind == "weapon" and not choice.get("taken", false) and not w.db.row("weapons", choice.id).is_empty()

func begin(w, offer_index: int):
	if active() or not eligible(w, offer_index): return null
	var trial = create(w, offer_index)
	if trial == null: return null
	origin = w
	index = offer_index
	return trial

func reset():
	return create(origin, index) if active() else null

func finish():
	var previous = origin
	origin = null
	index = -1
	return previous

static func create(w, offer_index: int):
	if not eligible(w, offer_index): return null
	var trial = World.new()
	if not trial.restore(w.snapshot()): return null
	trial.run.training = true
	trial.run.training_shop_weapon = w.choices[offer_index].id
	trial.player.weapon = w.choices[offer_index].id
	trial.player.pos = Vector2(640, 490)
	trial.player.aim = Vector2.UP
	trial.player.move = Vector2.ZERO
	trial.player.dash_left = 0.0
	trial.player.guard = 0.0
	trial.player.charge = 0.0
	trial.player.shot_cd = 0.0
	trial.player.skill_cd = 0.0
	trial.player.dash_cd = 0.0
	trial.player.invulnerable = 99999.0
	trial.player.energy = 100.0
	trial.enemies.clear()
	trial.bullets.clear()
	trial.zones.clear()
	trial.delayed.clear()
	trial.pickups.clear()
	trial.chains.clear()
	trial.choices.clear()
	trial.choice_queue.clear()
	trial.pair_cooldowns.clear()
	trial.events.clear()
	trial.mode = "combat"
	trial.run.replacement = {}
	trial.room_flags = {"combat_kills": 0, "dash_armor": 0, "passive_detonate": false, "summoned": 0, "summon_rewards": 0, "chain_pairs": {}, "forced_links": {}, "wave_index": 1, "wave_count": 1}
	trial.geometry.build("room_open_1", int(trial.run.floor))
	for position in [Vector2(640, 415), Vector2(520, 330), Vector2(760, 330), Vector2(640, 270)]:
		var dummy = trial.spawn_enemy("e01", position)
		dummy.hp = 5000.0
		dummy.max_hp = 5000.0
		dummy.speed = 0.0
		dummy.attack_cd = 99999.0
	return trial
