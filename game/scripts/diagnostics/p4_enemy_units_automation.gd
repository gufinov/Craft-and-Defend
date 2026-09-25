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

	core.clear_for_other_mode()
	await _run_encampment_gate()


# ----------------------------------------------------------- encampments (E1)

## Minion encampments (docs/ENCAMPMENTS.md), T248-T252. The camp under test is
## an authored one on a levelled plate near spawn: the world's own ambient
## camps stand 70-140 cells out, are never streamed in here and are dropped
## before the fixture is built, so nothing else moves during these records.
const CAMP_ORIGIN := Vector3i(-30, 0, 58)
const CAMP_PLATE := 30
const ENCAMPMENT_CAMP := "gate_camp"
const RAIL_LENGTH := 9
## One advance long enough to outlast `patrol_interval_seconds`, so the scout
## looks around on the very next tick.
const SCAN_STEP := 8.0


func _run_encampment_gate() -> void:
	var session := app.session
	var encampments: EncampmentService = session.encampments
	var workstations: WorkstationService = session.workstations
	var clock: DayNightClock = session.clock
	encampments.clear_for_other_mode()
	encampments.ambient = false
	encampments.world_ready = true
	var plate_origin := CAMP_ORIGIN + Vector3i(-CAMP_PLATE / 2, 0, -CAMP_PLATE / 2)
	var streamed := await _wait_for_region(plate_origin, CAMP_PLATE, CAMP_PLATE)
	if not streamed:
		failures.append("camp plate never streamed in")
		return
	_level_ground(plate_origin, CAMP_PLATE, CAMP_PLATE)
	for _frame in range(4):
		await get_tree().physics_frame

	# T248 the day/night cycle: the garrison patrols by day and sits at the
	# fire by night, driven by nothing but DayNightClock.
	clock.set_time_hhmm("1200")
	var registered := encampments.register_camp(ENCAMPMENT_CAMP, CAMP_ORIGIN, {"patrol_radius": 8, "sight_radius": 9.0})
	var started := encampments.start_camp(ENCAMPMENT_CAMP)
	var camp: Dictionary = encampments.camp(ENCAMPMENT_CAMP)
	var members: Array = camp.get("members", [])
	var fire_lit: bool = workstations.stations.has(str(camp.get("fire_id", "")))
	var day_state := str(camp.get("state", ""))
	var day_phases := _member_phases(camp)
	clock.set_time_hhmm("2200")
	encampments.advance(0.2, false)
	var night_state := str(camp.get("state", ""))
	var night_phases := _member_phases(camp)
	clock.set_time_hhmm("1000")
	encampments.advance(0.2, false)
	var back_to_day := str(camp.get("state", ""))
	_record("T248_ENCAMPMENT_CYCLE", registered.get("ok", false) and started.get("ok", false)
		and members.size() == 3 and fire_lit and encampments.is_day()
		and day_state == "patrolling" and not day_phases.has("camping")
		and night_state == "camping" and night_phases == ["camping"]
		and back_to_day == "patrolling",
		"a camp lit at noon patrols (every garrison body on patrol, its campfire standing); at 22:00 the same clock puts the whole garrison back at the fire, and 10:00 sends it out again — no wave, no scheduler",
		{"registered": registered.get("reason"), "started": started, "members": members.size(), "fire": str(camp.get("fire_id", "")), "fire_lit": fire_lit, "day_state": day_state, "day_phases": day_phases, "night_state": night_state, "night_phases": night_phases, "back_to_day": back_to_day})

	# T249 a rail line: discovered, exactly one piece broken, back on patrol,
	# and the chain now stops at the gap.
	var rail_origin := CAMP_ORIGIN + Vector3i(7, 0, -4)
	var rail_ids: Array[String] = []
	for step in range(RAIL_LENGTH):
		var placed := workstations.try_place("rail", rail_origin + Vector3i(0, 0, step), session.world.query_cell, AABB(), 0, {"_free": true})
		if placed.get("ok", false):
			rail_ids.append(str(placed.get("details", {}).get("station", {}).get("instance_id", "")))
	var rails_before := rail_ids.size()
	# One scout at a time: the other two are held off scanning so the record is
	# about one patrol's decision and not a race between three of them.
	_freeze_scanning(camp, 0)
	encampments.advance(SCAN_STEP, false)
	var scout: Dictionary = _first_member(camp)
	var discovered_entity := str(scout.get("target_entity", ""))
	var discovered_verb := str(scout.get("verb", ""))
	var discovered_phase := str(scout.get("phase", ""))
	var broken_cell: Vector3i = scout.get("target_cell", Vector3i.ZERO)
	var strikes := await _drive_strike(encampments, scout)
	var rails_after := _count_entities(workstations, "rail")
	var chain_reach := _chain_length(workstations, rail_origin)
	_record("T249_SABOTAGE_RAIL", discovered_entity == "rail" and discovered_verb == EncampmentService.VERB_BREAK_ONE
		and discovered_phase == "travelling" and rails_before == RAIL_LENGTH and rails_after == RAIL_LENGTH - 1
		and encampments.sabotage_events == 1 and strikes > 0
		and str(scout.get("phase", "")) == "patrolling" and str(scout.get("target_id", "")).is_empty()
		and float((camp.get("cooldowns", {}) as Dictionary).get("rail", 0.0)) > 0.0
		and chain_reach < RAIL_LENGTH and workstations.station_at_cell(broken_cell).is_empty(),
		"a patrol that notices a %d-piece rail line inside its sight radius walks to the nearest piece, breaks exactly that ONE piece and goes straight back on patrol; the line is severed (the chain from its near end now reaches %d of %d cells) and this camp leaves rails alone for the cooldown" % [RAIL_LENGTH, chain_reach, RAIL_LENGTH],
		{"entity": discovered_entity, "verb": discovered_verb, "phase_on_discovery": discovered_phase, "strikes": strikes, "rails_before": rails_before, "rails_after": rails_after, "broken_cell": broken_cell, "chain_reach": chain_reach, "phase_after": str(scout.get("phase", "")), "cooldown": (camp.get("cooldowns", {}) as Dictionary).get("rail", 0.0), "events": encampments.sabotage_events})

	# T250 a defensive structure: attacked until it is destroyed, then the
	# minion resumes patrolling.
	var ballista := workstations.try_place("ballista", CAMP_ORIGIN + Vector3i(-6, 0, 2), session.world.query_cell, AABB(), 0, {"_free": true})
	var ballista_id := str(ballista.get("details", {}).get("station", {}).get("instance_id", ""))
	# The scout finished T249 standing at the broken rail: put it back at its
	# own fire so this record starts from the camp, as a patrol leg would.
	await _recall(camp, 0)
	_freeze_scanning(camp, 0)
	encampments.advance(SCAN_STEP, false)
	var hunter: Dictionary = _first_member(camp)
	var structure_entity := str(hunter.get("target_entity", ""))
	var structure_verb := str(hunter.get("verb", ""))
	var structure_strikes := await _drive_strike(encampments, hunter)
	var ballista_gone := not workstations.stations.has(ballista_id)
	_record("T250_SABOTAGE_STRUCTURE", ballista.get("ok", false) and structure_entity == "ballista"
		and structure_verb == EncampmentService.VERB_DESTROY and ballista_gone
		and structure_strikes >= 2 and str(hunter.get("phase", "")) == "patrolling"
		and encampments.sabotage_events == 2,
		"a Ballista inside the patrol's sight radius is the `destroy` verb: the minion hits it with its own damage, through WorkstationService.try_damage, until it is gone (%d blows), and then goes back on patrol" % structure_strikes,
		{"placed": ballista.get("reason"), "entity": structure_entity, "verb": structure_verb, "strikes": structure_strikes, "destroyed": ballista_gone, "phase_after": str(hunter.get("phase", "")), "events": encampments.sabotage_events})

	# T251 the table is the whole decision: an entry set to `ignore` is left
	# alone and a kind the table never names is left alone.
	var table: Dictionary = encampments.rules["sabotage"]
	var before_verb := encampments.sabotage_verb("rail")
	table["rail"] = EncampmentService.VERB_IGNORE
	(camp["cooldowns"] as Dictionary).clear()
	var ignored_target := encampments.find_target(camp, Vector3(CAMP_ORIGIN) + Vector3(0.5, 0.9, 0.5))
	var workbench := workstations.try_place("workbench", CAMP_ORIGIN + Vector3i(3, 0, 3), session.world.query_cell, AABB(), 0, {"_free": true})
	var unknown_verb := encampments.sabotage_verb("workbench")
	var unknown_target := encampments.find_target(camp, Vector3(CAMP_ORIGIN) + Vector3(0.5, 0.9, 0.5))
	table["rail"] = before_verb
	_record("T251_SABOTAGE_TABLE", before_verb == EncampmentService.VERB_BREAK_ONE
		and ignored_target.is_empty() and unknown_verb == EncampmentService.VERB_IGNORE
		and unknown_target.is_empty() and encampments.sabotage_events == 2,
		"the sabotage table is the whole decision: with `rail` set to ignore the same rail line beside the camp is no longer a target, a Workbench (a kind the table never names) is no target either, and nothing is broken",
		{"rail_verb_before": before_verb, "ignored_target": ignored_target, "workbench_placed": workbench.get("ok", false), "workbench_verb": unknown_verb, "unknown_target": unknown_target, "events": encampments.sabotage_events})

	# T252 killing the garrison and breaking the fire clears the camp for good,
	# and a save round trip keeps it cleared.
	var core: CoreDefenseService = session.core_defense
	var kills := 0
	for value in camp.get("members", []):
		var entry: Dictionary = value
		var node: Variant = entry.get("node")
		if node is BasicRaider and core.try_damage_raider_node(node, 999, "player").get("ok", false):
			kills += 1
	var fire_id := str(camp.get("fire_id", ""))
	workstations.try_damage(fire_id, 9999)
	encampments.advance(0.2, false)
	var cleared_now := bool(encampments.camp(ENCAMPMENT_CAMP).get("cleared", false))
	var saved := encampments.snapshot()
	var json_round: Variant = JSON.parse_string(JSON.stringify(saved))
	encampments.clear_for_other_mode()
	encampments.ambient = false
	encampments.world_ready = true
	encampments.restore(json_round if json_round is Dictionary else saved)
	encampments.advance(0.2, false)
	encampments.advance(EncampmentService.MATERIALISE_SECONDS + 0.2, false)
	var restored: Dictionary = encampments.camp(ENCAMPMENT_CAMP)
	_record("T252_ENCAMPMENT_CLEARED", kills == 3 and cleared_now and encampments.camps_cleared >= 1
		and not restored.is_empty() and bool(restored.get("cleared", false))
		and not bool(restored.get("spawned", false)) and (restored.get("members", []) as Array).is_empty()
		and encampments.garrison_nodes().is_empty(),
		"killing all three garrison bodies (through the one damage API, so the player's sword reaches them) and breaking the campfire clears the camp; a JSON save round trip brings it back cleared, with no fire, no garrison and nothing that re-musters",
		{"kills": kills, "cleared": cleared_now, "camps_cleared": encampments.camps_cleared, "restored_cleared": restored.get("cleared"), "restored_spawned": restored.get("spawned"), "restored_members": (restored.get("members", []) as Array).size(), "garrison_nodes": encampments.garrison_nodes().size()})


## Walks the body it found to its target and lets it hit until the target is
## gone or the minion gives up. Returns how many blows it landed.
func _drive_strike(encampments: EncampmentService, entry: Dictionary) -> int:
	var node: Variant = entry.get("node")
	if not node is BasicRaider:
		return 0
	var body: BasicRaider = node
	var target: Vector3i = entry.get("target_cell", Vector3i.ZERO)
	body.active = false
	body.set_route([])
	body.global_position = Vector3(target) + Vector3(1.5, 0.9, 0.5)
	await get_tree().physics_frame
	var strikes := 0
	for _step in range(40):
		encampments.advance(2.0, false)
		if str(entry.get("phase", "")) == "sabotaging":
			strikes += 1
			continue
		if str(entry.get("phase", "")) != "travelling":
			break
	return strikes


func _member_phases(camp: Dictionary) -> Array[String]:
	var phases: Array[String] = []
	for value in camp.get("members", []):
		var phase := str((value as Dictionary).get("phase", ""))
		if not phases.has(phase):
			phases.append(phase)
	phases.sort()
	return phases


## Waits until every column of a plate has streamed in, so the fixture is
## levelled on loaded ground instead of racing the streamer.
func _wait_for_region(origin: Vector3i, width: int, depth: int) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var ready := true
		for x in range(width):
			for z in range(depth):
				for y in [-1, 0, 4]:
					if str(app.session.world.query_cell(origin + Vector3i(x, y, z)).get("state", "")) != "LOADED":
						ready = false
						break
				if not ready:
					break
			if not ready:
				break
		if ready:
			return true
		await get_tree().process_frame
	return false


## Puts one garrison body back beside its fire.
func _recall(camp: Dictionary, index: int) -> void:
	var members: Array = camp.get("members", [])
	if index >= members.size():
		return
	var entry: Dictionary = members[index]
	var node: Variant = entry.get("node")
	if not node is BasicRaider:
		return
	var body: BasicRaider = node
	body.active = false
	body.set_route([])
	body.clear_goal()
	body.global_position = Vector3(camp.get("cell", Vector3i.ZERO)) + Vector3(0.5, 0.9, 0.5)
	await get_tree().physics_frame


## Holds every garrison body but `active_index` off scanning, so one record
## observes one patrol's decision.
func _freeze_scanning(camp: Dictionary, active_index: int) -> void:
	var members: Array = camp.get("members", [])
	for index in range(members.size()):
		var entry: Dictionary = members[index]
		entry["scan_timer"] = 0.0 if index == active_index else 1.0e6
		entry["leg_timer"] = 1.0e6


func _first_member(camp: Dictionary) -> Dictionary:
	for value in camp.get("members", []):
		var entry: Dictionary = value
		if not str(entry.get("target_id", "")).is_empty():
			return entry
	var members: Array = camp.get("members", [])
	return members[0] if not members.is_empty() else {}


func _count_entities(workstations: WorkstationService, entity_id: String) -> int:
	var total := 0
	for record: Dictionary in workstations.stations.values():
		if str(record.get("entity_id", "")) == entity_id:
			total += 1
	return total


## How far a straight rail run still reaches from its first cell: the gap a
## broken piece leaves is exactly where this stops.
func _chain_length(workstations: WorkstationService, origin: Vector3i) -> int:
	var reach := 0
	for step in range(RAIL_LENGTH):
		var instance_id := workstations.station_at_cell(origin + Vector3i(0, 0, step))
		if instance_id.is_empty() or str(workstations.station(instance_id).get("entity_id", "")) != "rail":
			break
		reach += 1
	return reach


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
