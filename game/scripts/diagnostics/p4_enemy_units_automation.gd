class_name P4EnemyUnitsAutomation
extends Node

## P4F enemy units: the orc melee model (two cleavers), the brute as a scaled
## purple orc, the troll ranged model (crossbow) and the troll's stop-and-shoot
## behaviour. Runs with `--p4-enemy-units-automation=gate` (headless) and
## `--p4-enemy-units-automation=visual` (needs a window; renders one PNG).

var app: CraftAndDefendApp
var failures: Array[String] = []
var records: Array[Dictionary] = []


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	match mode:
		"gate":
			await _run_gate()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p4_enemy_units_results.json"), {"failures": failures, "records": records})
	if failures.is_empty():
		print("P4_ENEMY_UNITS_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P4_ENEMY_UNITS_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_gate() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	app.session.simulation_paused = true
	var core := app.session.core_defense

	# T144 enemy unit models: a wave with an orc, a brute and a troll builds
	# each kind as a multi-part model under its body; the entries carry the
	# kind's health and damage.
	var started := core.start_prototype({"raiders": 3, "brutes": 1, "trolls": 1, "spawn_distance": 12})
	var center := core.arena_center
	# Level the field before the bodies enter so no replan re-activates them.
	_level_ground(center + Vector3i(-8, 0, -14), 17, 22)
	core.warning_remaining = 0.0
	core._begin_attack()
	for node in core.raider_nodes():
		node.active = false
	var orc: BasicRaider = core.raider
	var brute: BasicRaider = null
	var troll: BasicRaider = null
	var brute_entry: Dictionary = {}
	var troll_entry: Dictionary = {}
	for entry in core.extra_raiders:
		if str(entry.kind) == BasicRaider.KIND_BRUTE:
			brute = entry.node
			brute_entry = entry
		elif str(entry.kind) == BasicRaider.KIND_TROLL:
			troll = entry.node
			troll_entry = entry
	var orc_swords := orc != null and orc.find_child("OrcSwordL", true, false) != null and orc.find_child("OrcSwordR", true, false) != null
	var orc_pauldron := orc != null and orc.find_child("OrcPauldron", true, false) != null
	var orc_parts := orc.find_children("*", "MeshInstance3D", true, false).size() if orc != null else 0
	var brute_model: Node3D = brute.find_child("Model", false, false) if brute != null else null
	var brute_scaled := brute_model != null and brute_model.scale.is_equal_approx(Vector3.ONE * BasicRaider.BRUTE_SCALE)
	var brute_swords := brute != null and brute.find_child("OrcSwordL", true, false) != null and brute.find_child("OrcSwordR", true, false) != null
	var troll_crossbow := troll != null and troll.find_child("TrollCrossbow", true, false) != null and troll.find_child("TrollQuiver", true, false) != null and troll.find_child("TrollTopknot", true, false) != null
	var troll_no_swords := troll != null and troll.find_child("OrcSwordL", true, false) == null
	var troll_parts := troll.find_children("*", "MeshInstance3D", true, false).size() if troll != null else 0
	var collision_direct := true
	for node in core.raider_nodes():
		var shapes := 0
		for child in node.get_children():
			if child is CollisionShape3D:
				shapes += 1
		collision_direct = collision_direct and shapes == 1
	var stats_ok: bool = brute_entry.get("health", 0) == 40 and brute_entry.get("damage", 0) == 10 and troll_entry.get("health", 0) == 28 and troll_entry.get("damage", 0) == 5 and bool(troll_entry.get("ranged", false)) and float(troll_entry.get("range", 0.0)) == 9.0 and float(troll_entry.get("attack_interval", 0.0)) == 2.0 and core.raider_health == 20
	var kinds_ok: bool = orc != null and orc.kind == BasicRaider.KIND_RAIDER and brute != null and brute.kind == BasicRaider.KIND_BRUTE and troll != null and troll.kind == BasicRaider.KIND_TROLL and troll.move_speed == BasicRaider.TROLL_MOVE_SPEED
	_record("T144_ENEMY_UNIT_MODELS", started.get("ok", false) and core.living_raider_count() == 3 and orc_swords and orc_pauldron and orc_parts >= 40 and brute_scaled and brute_swords and troll_crossbow and troll_no_swords and troll_parts >= 40 and collision_direct and stats_ok and kinds_ok, "a wave of three (orc, brute, troll) builds the orc with two cleavers and a pauldron, the brute as the same orc scaled 1.25, the troll with a crossbow, quiver and topknot; each body keeps one direct collision shape; entries carry 40/10, 28/5 (ranged, 9 cells, 2 s) and the lead orc 20/6", {"started": started.get("reason"), "count": core.living_raider_count(), "orc_swords": orc_swords, "orc_pauldron": orc_pauldron, "orc_parts": orc_parts, "brute_scaled": brute_scaled, "brute_swords": brute_swords, "troll_crossbow": troll_crossbow, "troll_no_swords": troll_no_swords, "troll_parts": troll_parts, "collision_direct": collision_direct, "stats_ok": stats_ok, "kinds_ok": kinds_ok})

	# T145 troll ranged attack: a troll 14 cells from the core keeps routing
	# (no shot); moved to 6 cells it stops, shoots every 2 s, each bolt costs
	# the core 5 and a bolt node flies from the crossbow.
	core.clear_for_other_mode()
	var ranged := core.start_prototype({"raiders": 3, "brutes": 0, "trolls": 1, "spawn_distance": 12})
	core.warning_remaining = 0.0
	core._begin_attack()
	for node in core.raider_nodes():
		node.active = false
	var shooter: BasicRaider = null
	var shooter_entry: Dictionary = {}
	for entry in core.extra_raiders:
		if str(entry.kind) == BasicRaider.KIND_TROLL:
			shooter = entry.node
			shooter_entry = entry
	var core_cell := core._core_cell()
	var integrity_start := core.core_integrity
	var far_ok := false
	var far_phase := ""
	var near_phase := ""
	var shots_after_first := -1
	var integrity_after_first := -1
	var integrity_after_second := -1
	var bolt_seen := false
	var still_routing_after_far := false
	if shooter != null:
		shooter.global_position = Vector3(core_cell + Vector3i(0, 0, -14)) + Vector3(0.5, 0.9, 0.5)
		await get_tree().physics_frame
		for _frame in range(10):
			core.advance(0.5, false)
		far_phase = str(shooter_entry.get("phase", ""))
		still_routing_after_far = far_phase == "routing"
		far_ok = core.core_integrity == integrity_start and core.ranged_shots == 0 and str(shooter_entry.get("target_type", "")) == "core"
		shooter.global_position = Vector3(core_cell + Vector3i(0, 0, -6)) + Vector3(0.5, 0.9, 0.5)
		await get_tree().physics_frame
		core.advance(0.5, false)
		near_phase = str(shooter_entry.get("phase", ""))
		core.advance(0.5, false)
		shots_after_first = core.ranged_shots
		integrity_after_first = core.core_integrity
		bolt_seen = not core.find_children("*TrollBolt*", "MeshInstance3D", false, false).is_empty()
		for _frame in range(4):
			core.advance(0.5, false)
		integrity_after_second = core.core_integrity
	var stopped := shooter != null and not shooter.active
	_record("T145_TROLL_RANGED_ATTACK", ranged.get("ok", false) and shooter != null and still_routing_after_far and far_ok and near_phase == "attacking_core" and stopped and shots_after_first == 1 and integrity_after_first == integrity_start - 5 and bolt_seen and integrity_after_second == integrity_start - 10 and core.ranged_shots == 2 and core.state == CoreDefenseService.ROUTING, "a troll 14 cells from the core keeps routing without shooting; at 6 cells it stops, engages the core, fires a visible bolt and costs the core 5 per shot every 2 s", {"ranged": ranged.get("reason"), "far_phase": far_phase, "far_ok": far_ok, "near_phase": near_phase, "stopped": stopped, "shots_after_first": shots_after_first, "integrity_start": integrity_start, "integrity_after_first": integrity_after_first, "integrity_after_second": integrity_after_second, "bolt_seen": bolt_seen, "shots": core.ranged_shots, "state": core.state})


## Rendered evidence: an orc, a brute and a troll side by side about four
## metres in front of the camera, in one 1280x720 view.
func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready():
		return
	var player := app.session.player
	player.deactivate()
	var core := app.session.core_defense
	var origin := Vector3i(-6, 0, 36)
	_level_ground(origin + Vector3i(-4, 0, -4), 16, 12)
	var camera_position := Vector3(origin) + Vector3(2.5, 1.5, -2.5)
	var units: Array[BasicRaider] = []
	var placements := {
		BasicRaider.KIND_RAIDER: Vector3(origin) + Vector3(0.5, 0.9, 2.0),
		BasicRaider.KIND_BRUTE: Vector3(origin) + Vector3(2.5, 0.9, 2.2),
		BasicRaider.KIND_TROLL: Vector3(origin) + Vector3(4.5, 0.9, 2.0),
	}
	for kind: String in placements.keys():
		var unit := BasicRaider.new()
		unit.configure(kind)
		core.add_child(unit)
		unit.global_position = placements[kind]
		unit.face_point(camera_position)
		units.append(unit)
	for _frame in range(4):
		await get_tree().physics_frame
	player.global_position = camera_position
	player.look_at(Vector3(origin) + Vector3(2.5, 0.9, 2.0), Vector3.UP)
	player.camera.rotation.x = -0.06
	for _frame in range(90):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image := texture.get_image() if texture != null else null
	var path := app.data_root.path_join("p4-enemy-units.png")
	if image == null:
		_record("T146_ENEMY_UNITS_RENDERED", false, "an orc, a brute and a troll render side by side in one 1280x720 view", {"path": path, "reason": "NO_RENDERED_VIEWPORT"})
		return
	var error := image.save_png(path)
	var mesh_parts := 0
	var kinds: Array[String] = []
	for unit in units:
		mesh_parts += unit.find_children("*", "MeshInstance3D", true, false).size()
		kinds.append(unit.kind)
	_record("T146_ENEMY_UNITS_RENDERED", error == OK and image.get_size() == Vector2i(1280, 720) and units.size() == 3 and mesh_parts >= 120, "an orc, a brute (scaled purple orc) and a troll with a crossbow render side by side about four metres in front of the camera in one 1280x720 view", {"path": path, "size": image.get_size(), "error": error, "mesh_parts": mesh_parts, "kinds": kinds})


func _level_ground(origin: Vector3i, width: int, depth: int) -> void:
	for x in range(width):
		for z in range(depth):
			app.session.world.set_cell(origin + Vector3i(x, -1, z), 3)
			for y in range(6):
				app.session.world.set_cell(origin + Vector3i(x, y, z), 0)


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while app.session == null or not app.session.world_ready:
		if Time.get_ticks_msec() >= deadline:
			failures.append("world ready timeout")
			return false
		await get_tree().process_frame
	return true


func _record(test_id: String, ok: bool, expected: String, evidence: Variant) -> void:
	records.append({"id": test_id, "ok": ok, "expected": expected, "evidence": evidence})
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if ok else "FAIL", expected, JSON.stringify(evidence)])
	if not ok:
		failures.append(test_id)


func _write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  ") + "\n")
