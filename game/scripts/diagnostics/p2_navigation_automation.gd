class_name P2NavigationAutomation
extends Node

const AIR := 0
const STONE := 3
const PLANKS := 5
const CASTLE_STONE := 8
const FIXTURE_REGION := AABB(Vector3(-6, -2, 32), Vector3(13, 5, 13))
const START := Vector3i(0, 0, 43)
const GOAL := Vector3i(0, 0, 33)

var app: CraftAndDefendApp
var failures: Array[String] = []
var contract: Dictionary = {}
var materials: Dictionary = {}
var invalidated_cells: Array[Vector3i] = []
var metrics: Dictionary = {}


func run(application: CraftAndDefendApp, mode: String) -> void:
	app = application
	contract = _read_json("res://data/navigation_spike.json")
	_index_materials()
	match mode:
		"phase1":
			await _run_phase1()
		"visual":
			await _run_visual()
		_:
			failures.append("unknown mode " + mode)
	_write_json(app.data_root.path_join("p2_navigation_results.json"), {"failures": failures, "metrics": metrics})
	if failures.is_empty():
		print("P2_NAVIGATION_AUTOMATION_PASS")
		get_tree().quit(0)
	else:
		push_error("P2_NAVIGATION_AUTOMATION_FAIL " + "; ".join(failures))
		get_tree().quit(1)


func _run_phase1() -> void:
	_test_api_contract()
	app._on_start_pressed()
	if not await _wait_ready():
		return
	app.session.player.deactivate()
	if not await _wait_fixture_loaded():
		return
	app.session.world.cell_changed.connect(_on_cell_changed)
	await _test_corridor_detour()
	await _test_trench()
	await _test_stair_entity()
	await _test_tunnel()
	await _test_bridge_invalidation()
	await _test_capability_obstruction()
	_record("T55_NAVIGATION_METRICS", _metrics_complete(), "both bounded planners report recomputation time and memory-scale evidence without a simulated stuck transition", metrics)


func _run_visual() -> void:
	app._on_start_pressed()
	if not await _wait_ready() or not await _wait_fixture_loaded():
		return
	app.session.player.deactivate()
	app.session.apply_world_settings("1030", false)
	_reset_fixture()
	for x in range(-2, 3):
		_set_wall_column(Vector3i(x, 0, 38), CASTLE_STONE)
	var snapshot := _capture_snapshot("visual")
	var route := LocalGridPathfinder.new().find_route(snapshot, START, GOAL, _capability("basic_raider"))
	var validation := LocalGridPathfinder.new().validate_route(snapshot, route.get("path", []), _capability("basic_raider"))
	var visual_root := Node3D.new()
	visual_root.name = "P2NavigationVisual"
	app.session.add_child(visual_root)
	for cell: Vector3i in route.get("path", []):
		_add_marker(visual_root, Vector3(cell) + Vector3(0.5, 0.08, 0.5), Color("43d9e6"), Vector3(0.22, 0.12, 0.22))
	_add_marker(visual_root, Vector3(START) + Vector3(0.5, 0.25, 0.5), Color("59dc7a"), Vector3(0.5, 0.5, 0.5))
	_add_marker(visual_root, Vector3(GOAL) + Vector3(0.5, 0.25, 0.5), Color("ef6b73"), Vector3(0.5, 0.5, 0.5))
	var probe := _add_probe_agent(visual_root)
	for cell: Vector3i in route.get("path", []):
		probe.position = Vector3(cell) + Vector3(0.5, 1.0, 0.5)
		await get_tree().create_timer(0.035).timeout
	app.session.player.position = Vector3(10.5, 12.0, 47.0)
	app.session.player.camera.look_at(Vector3(0.5, 0.0, 38.5), Vector3.UP)
	_add_visual_caption()
	for _frame in range(90):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := app.data_root.path_join("p2-navigation-spike.png")
	var error := image.save_png(path)
	_record("T56_NAVIGATION_VISUAL", route.get("ok", false) and validation.get("ok", false) and error == OK and not image.is_empty() and image.get_size() == Vector2i(1280, 720), "rendered diagnostic shows the 1x2 probe at the goal, its cyan route and the wall it detoured around", {"path": path, "size": image.get_size(), "route_length": route.get("path", []).size(), "validation": validation})


func _add_marker(parent: Node3D, marker_position: Vector3, color: Color, size: Vector3) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	mesh.material = material
	marker.mesh = mesh
	marker.position = marker_position
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(marker)
	return marker


func _add_probe_agent(parent: Node3D) -> MeshInstance3D:
	var probe := MeshInstance3D.new()
	probe.name = "Attacker1x2Probe"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.35
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffd45a")
	material.emission_enabled = true
	material.emission = Color("d89b2b")
	material.emission_energy_multiplier = 0.6
	mesh.material = material
	probe.mesh = mesh
	parent.add_child(probe)
	return probe


func _add_visual_caption() -> void:
	var caption := Label.new()
	caption.text = "P2 NAVIGATION SPIKE · 1×2 PROBE\nCYAN: local-grid route   GREEN: start   RED: goal   YELLOW: probe\nDiagnostic only — no raid or enemy gameplay added"
	caption.position = Vector2(24, 78)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	app.add_child(caption)


func _test_api_contract() -> void:
	var methods: Array = ClassDB.class_get_method_list("VoxelAStarGrid3D") if ClassDB.class_exists("VoxelAStarGrid3D") else []
	var names: Array[String] = []
	for method in methods:
		names.append(str(method.get("name", "")))
	var required := ["set_terrain", "set_region", "find_path", "find_path_async", "is_running_async", "debug_get_visited_positions"]
	var available := ClassDB.class_exists("VoxelAStarGrid3D") and required.all(func(name: String) -> bool: return names.has(name))
	var agent: Dictionary = contract.get("agent", {})
	var size_values: Array = agent.get("size_cells", [])
	var contract_ok: bool = size_values.size() == 3 and int(size_values[0]) == 1 and int(size_values[1]) == 2 and int(size_values[2]) == 1 and int(agent.get("max_step_up", -1)) == 1 and int(agent.get("max_drop_down", -1)) == 1
	_record("T51_PINNED_NAVIGATION_API", available and contract_ok, "the pinned Module exposes its experimental 1x2 voxel A* surface and the local spike contract matches that agent", {"class_available": available, "required_methods": required, "agent": agent})


func _test_corridor_detour() -> void:
	_reset_fixture()
	for x in range(-2, 3):
		_set_wall_column(Vector3i(x, 0, 38), STONE)
	var snapshot := _capture_snapshot("corridor")
	var local := _benchmark_local(snapshot, START, GOAL)
	var pinned := _benchmark_pinned(START, GOAL)
	var validation := LocalGridPathfinder.new().validate_route(snapshot, local.get("path", []), _capability("basic_raider"))
	metrics["corridor"] = {"local": _metric_summary(local), "pinned": _metric_summary(pinned), "snapshot": _snapshot_summary(snapshot), "validation": validation}
	_record("T52_CORRIDOR_DETOUR", local.get("ok", false) and pinned.get("ok", false) and validation.get("ok", false) and local.get("path", []).size() > 11, "one 1x2 agent routes around a two-cell-high wall and traverses every returned local-grid step without getting stuck", metrics.corridor)


func _test_trench() -> void:
	_reset_fixture()
	for x in range(-6, 7):
		app.session.world.set_cell(Vector3i(x, -1, 38), AIR)
		app.session.world.set_cell(Vector3i(x, -2, 38), AIR)
	var snapshot := _capture_snapshot("trench")
	var local := _benchmark_local(snapshot, START, GOAL)
	var pinned := _benchmark_pinned(START, GOAL)
	metrics["trench"] = {"local": _metric_summary(local), "pinned": _metric_summary(pinned), "snapshot": _snapshot_summary(snapshot)}
	_record("T53_TRENCH_BLOCKS_ROUTE", not local.get("ok", true) and not pinned.get("ok", true), "a two-cell-deep trench spanning the bounded region produces no route instead of an unsafe fall", metrics.trench)


func _test_stair_entity() -> void:
	_reset_fixture()
	for z in range(32, 45):
		_set_wall_column(Vector3i(-1, 0, z), STONE)
		_set_wall_column(Vector3i(1, 0, z), STONE)
	app.session.inventory.try_transaction({}, {"stone_stair": 1})
	var placed := app.session.interaction.try_place_item(Vector3i(0, 0, 38), "stone_stair", -1, 0)
	var snapshot := _capture_snapshot("stair")
	var local := _benchmark_local(snapshot, START, GOAL)
	var pinned := _benchmark_pinned(START, GOAL)
	var local_max_y := _max_path_y(local.get("path", []))
	var pinned_max_y := _max_path_y(pinned.get("path", []))
	metrics["stair"] = {"placed": placed, "local": _metric_summary(local), "pinned": _metric_summary(pinned), "local_max_y": local_max_y, "pinned_max_y": pinned_max_y, "snapshot": _snapshot_summary(snapshot)}
	_record("T52_STAIR_ENTITY", placed.get("ok", false) and local.get("ok", false) and pinned.get("ok", false) and local_max_y == 1 and pinned_max_y == 0, "the local snapshot accounts for the placed stair reservation while pinned voxel A* remains terrain-only", metrics.stair)
	if placed.get("ok", false):
		app.session.interaction.try_dismantle_station(str(placed.get("changes", {}).get("station", {}).get("instance_id", "")))


func _test_tunnel() -> void:
	_reset_fixture()
	for z in range(32, 45):
		_set_wall_column(Vector3i(-1, 0, z), STONE)
		_set_wall_column(Vector3i(1, 0, z), STONE)
		app.session.world.set_cell(Vector3i(0, 2, z), STONE)
	var open_snapshot := _capture_snapshot("tunnel_open")
	var local_open := _benchmark_local(open_snapshot, START, GOAL)
	var pinned_open := _benchmark_pinned(START, GOAL)
	app.session.world.set_cell(Vector3i(0, 1, 38), STONE)
	var blocked_snapshot := _capture_snapshot("tunnel_blocked")
	var local_blocked := _benchmark_local(blocked_snapshot, START, GOAL)
	var pinned_blocked := _benchmark_pinned(START, GOAL)
	metrics["tunnel"] = {"local_open": _metric_summary(local_open), "pinned_open": _metric_summary(pinned_open), "local_blocked": _metric_summary(local_blocked), "pinned_blocked": _metric_summary(pinned_blocked), "snapshot": _snapshot_summary(blocked_snapshot)}
	_record("T52_TUNNEL_CLEARANCE", local_open.get("ok", false) and pinned_open.get("ok", false) and not local_blocked.get("ok", true) and not pinned_blocked.get("ok", true), "a two-cell-high tunnel passes and one-cell headroom rejects for the 1x2 agent", metrics.tunnel)


func _test_bridge_invalidation() -> void:
	_reset_fixture()
	for x in range(-6, 7):
		app.session.world.set_cell(Vector3i(x, -1, 38), AIR)
		app.session.world.set_cell(Vector3i(x, -2, 38), AIR)
	app.session.world.set_cell(Vector3i(0, -1, 38), STONE)
	var before := _capture_snapshot("bridge_before")
	var local_before := _benchmark_local(before, START, GOAL)
	var pinned_before := _benchmark_pinned(START, GOAL)
	var before_summary := _snapshot_summary(before)
	invalidated_cells.clear()
	var revision_before := app.session.world.revision
	app.session.world.set_cell(Vector3i(0, -1, 38), AIR)
	var refresh := before.refresh_cells(invalidated_cells, _query_navigation_cell, app.session.world.revision)
	var after := before
	var local_after := _benchmark_local(after, START, GOAL)
	var pinned_after := _benchmark_pinned(START, GOAL)
	var invalidated: bool = invalidated_cells.has(Vector3i(0, -1, 38)) and after.source_revision > revision_before and refresh.get("refreshed_cells") == 1
	metrics["bridge"] = {"local_before": _metric_summary(local_before), "pinned_before": _metric_summary(pinned_before), "local_after": _metric_summary(local_after), "pinned_after": _metric_summary(pinned_after), "invalidated": invalidated, "revision_before": revision_before, "revision_after": after.source_revision, "snapshot_before": before_summary, "incremental_refresh": refresh, "snapshot_after": _snapshot_summary(after)}
	_record("T53_BRIDGE_INVALIDATION", local_before.get("ok", false) and pinned_before.get("ok", false) and invalidated and not local_after.get("ok", true) and not pinned_after.get("ok", true), "removing the only bridge emits an exact cell-change event and both bounded routes recompute to no route", metrics.bridge)


func _test_capability_obstruction() -> void:
	_reset_fixture()
	for x in range(-6, 7):
		_set_wall_column(Vector3i(x, 0, 38), PLANKS)
	var wood_snapshot := _capture_snapshot("wood_wall")
	var pathfinder := LocalGridPathfinder.new()
	var basic := _capability("basic_raider")
	var unarmed_plan := pathfinder.plan_next(wood_snapshot, START, GOAL, _movement_only_capability())
	var raider_plan := pathfinder.plan_next(wood_snapshot, START, GOAL, basic)
	var pinned := _benchmark_pinned(START, GOAL)
	var breach := _simulate_breach(wood_snapshot, basic)
	_reset_fixture()
	for x in range(-6, 7):
		_set_wall_column(Vector3i(x, 0, 38), CASTLE_STONE)
	var castle_snapshot := _capture_snapshot("castle_wall")
	var basic_castle := pathfinder.plan_next(castle_snapshot, START, GOAL, basic)
	var siege_castle := pathfinder.plan_next(castle_snapshot, START, GOAL, _capability("siege_breaker_candidate"))
	var action: Dictionary = raider_plan.get("action", {})
	metrics["capability"] = {"unarmed": _plan_summary(unarmed_plan), "basic_wood": _plan_summary(raider_plan), "wood_breach": breach, "pinned_wood": _metric_summary(pinned), "basic_castle": _plan_summary(basic_castle), "siege_castle": _plan_summary(siege_castle), "snapshot": _snapshot_summary(castle_snapshot)}
	var differentiated: bool = not unarmed_plan.get("ok", true) and raider_plan.get("reason") == "ATTACK_OBSTRUCTION" and action.get("material_id") == "planks" and int(action.get("estimated_hits", -1)) == 4 and breach.get("ok", false) and int(breach.get("total_hits", -1)) == 8 and breach.get("destroyed_cells", []).size() == 2 and not basic_castle.get("ok", true) and siege_castle.get("reason") == "ATTACK_OBSTRUCTION"
	_record("T54_CAPABILITY_OBSTRUCTION", differentiated and not pinned.get("ok", true), "a blocked basic raider deliberately attacks wood, refuses castle stone, and a siege-capable candidate receives its own damage plan; pinned A* reports only no route", metrics.capability)


func _simulate_breach(snapshot: NavigationSnapshot, capability: Dictionary) -> Dictionary:
	var pathfinder := LocalGridPathfinder.new()
	var destroyed: Array[Vector3i] = []
	var total_hits := 0
	for _action_index in range(4):
		var plan := pathfinder.plan_next(snapshot, START, GOAL, capability)
		if plan.get("reason") == "OK":
			var validation := pathfinder.validate_route(snapshot, plan.get("path", []), capability)
			return {"ok": validation.get("ok", false), "reason": "ROUTE_OPEN", "destroyed_cells": destroyed, "total_hits": total_hits, "path_length": plan.get("path", []).size(), "validation": validation}
		if plan.get("reason") != "ATTACK_OBSTRUCTION":
			return {"ok": false, "reason": plan.get("reason", "NO_ROUTE"), "destroyed_cells": destroyed, "total_hits": total_hits}
		var action: Dictionary = plan.get("action", {})
		var cell: Vector3i = action.get("cell", Vector3i.ZERO)
		total_hits += int(action.get("estimated_hits", 0))
		if not app.session.world.set_cell(cell, AIR):
			return {"ok": false, "reason": "WORLD_EDIT_FAILED", "cell": cell, "destroyed_cells": destroyed, "total_hits": total_hits}
		destroyed.append(cell)
		var refreshed := snapshot.refresh_cells([cell], _query_navigation_cell, app.session.world.revision)
		if not refreshed.get("ok", false):
			return {"ok": false, "reason": "SNAPSHOT_REFRESH_FAILED", "refresh": refreshed, "destroyed_cells": destroyed, "total_hits": total_hits}
	return {"ok": false, "reason": "BREACH_ACTION_LIMIT", "destroyed_cells": destroyed, "total_hits": total_hits}


func _reset_fixture() -> void:
	for y in range(-2, 3):
		for z in range(32, 45):
			for x in range(-6, 7):
				app.session.world.set_cell(Vector3i(x, y, z), STONE if y <= -1 else AIR)


func _set_wall_column(cell: Vector3i, voxel_id: int) -> void:
	app.session.world.set_cell(cell, voxel_id)
	app.session.world.set_cell(cell + Vector3i.UP, voxel_id)


func _capture_snapshot(label: String) -> NavigationSnapshot:
	var snapshot := NavigationSnapshot.new()
	var result := snapshot.capture(FIXTURE_REGION, _query_navigation_cell, app.session.world.revision)
	if not result.get("ok", false):
		failures.append("snapshot_%s" % label)
	return snapshot


func _query_navigation_cell(cell: Vector3i) -> Dictionary:
	var world_value := app.session.world.query_cell(cell)
	if str(world_value.get("state", "UNLOADED")) != "LOADED":
		return {"state": str(world_value.get("state", "UNLOADED")), "solid": true}
	var instance_id := app.session.workstations.station_at_cell(cell)
	if not instance_id.is_empty():
		var record := app.session.workstations.station(instance_id)
		return _material_cell("castle_stone", true, "entity", str(record.get("entity_id", "structure")))
	var voxel_id := int(world_value.get("voxel_id", AIR))
	if voxel_id == AIR:
		return {"state": "LOADED", "solid": false, "voxel_id": AIR, "material_id": "air", "tags": [], "integrity": 0, "protected": false, "source": "voxel"}
	var block := app.session.registry.block_for_voxel(voxel_id)
	var material_id := str(block.get("id", "unknown"))
	return _material_cell(material_id, bool(block.get("solid", true)), "voxel", material_id, voxel_id)


func _material_cell(material_id: String, solid: bool, source: String, source_id: String, voxel_id: int = -1) -> Dictionary:
	var definition: Dictionary = materials.get(material_id, {"integrity": 1, "tags": [], "protected": false})
	return {"state": "LOADED", "solid": solid, "voxel_id": voxel_id, "material_id": material_id, "source": source, "source_id": source_id, "tags": definition.get("tags", []).duplicate(), "integrity": definition.get("integrity", 1), "protected": definition.get("protected", false)}


func _benchmark_local(snapshot: NavigationSnapshot, start: Vector3i, goal: Vector3i) -> Dictionary:
	var pathfinder := LocalGridPathfinder.new()
	var timings: Array[int] = []
	var result: Dictionary = {}
	for _iteration in range(int(contract.get("benchmark", {}).get("iterations", 20))):
		result = pathfinder.find_route(snapshot, start, goal, _capability("basic_raider"))
		timings.append(int(result.get("elapsed_usec", 0)))
	timings.sort()
	result["median_usec"] = timings[timings.size() / 2]
	result["p95_usec"] = timings[mini(timings.size() - 1, ceili(float(timings.size()) * 0.95) - 1)]
	result["visited_count"] = result.get("visited", []).size()
	result["estimated_snapshot_bytes"] = snapshot.estimated_bytes
	return result


func _benchmark_pinned(start: Vector3i, goal: Vector3i) -> Dictionary:
	return PinnedVoxelAStarAdapter.new().benchmark(app.session.world.terrain, FIXTURE_REGION, start, goal, int(contract.get("benchmark", {}).get("iterations", 20)))


func _movement_only_capability() -> Dictionary:
	var agent: Dictionary = contract.get("agent", {})
	return {"max_step_up": int(agent.get("max_step_up", 1)), "max_drop_down": int(agent.get("max_drop_down", 1)), "damage_per_hit": {}}


func _capability(capability_id: String) -> Dictionary:
	for value in contract.get("capabilities", []):
		if value is Dictionary and str(value.get("id", "")) == capability_id:
			var result: Dictionary = value.duplicate(true)
			result.merge(_movement_only_capability(), false)
			return result
	return _movement_only_capability()


func _index_materials() -> void:
	materials.clear()
	for value in contract.get("materials", []):
		if value is Dictionary:
			materials[str(value.get("id", ""))] = value.duplicate(true)


func _max_path_y(path: Array) -> int:
	var result := -999
	for value in path:
		result = maxi(result, (value as Vector3i).y)
	return result


func _metric_summary(result: Dictionary) -> Dictionary:
	return {"ok": result.get("ok", false), "reason": result.get("reason", ""), "path_length": result.get("path", []).size(), "visited_count": result.get("visited_count", result.get("visited", []).size()), "median_usec": result.get("median_usec", 0), "p95_usec": result.get("p95_usec", 0), "memory_delta_bytes": result.get("memory_delta_bytes", 0), "estimated_snapshot_bytes": result.get("estimated_snapshot_bytes", 0)}


func _snapshot_summary(snapshot: NavigationSnapshot) -> Dictionary:
	return {"cells": snapshot.cells.size(), "capture_usec": snapshot.capture_usec, "estimated_bytes": snapshot.estimated_bytes, "source_revision": snapshot.source_revision}


func _plan_summary(result: Dictionary) -> Dictionary:
	return {"ok": result.get("ok", false), "reason": result.get("reason", ""), "action": result.get("action", {}), "visited_count": result.get("visited", []).size()}


func _metrics_complete() -> bool:
	for scenario in ["corridor", "trench", "stair", "tunnel", "bridge", "capability"]:
		if not metrics.has(scenario):
			return false
	var validation: Dictionary = metrics.get("corridor", {}).get("validation", {})
	return validation.get("ok", false) and int(validation.get("stuck_cases", -1)) == 0 and int(metrics.get("corridor", {}).get("snapshot", {}).get("estimated_bytes", 0)) > 0


func _on_cell_changed(cell: Vector3i, _previous: int, _next: int, _revision: int) -> void:
	invalidated_cells.append(cell)


func _wait_ready() -> bool:
	var started := Time.get_ticks_msec()
	while app.state != app.AppState.PLAYING and Time.get_ticks_msec() - started < 30000:
		await get_tree().process_frame
	if app.state != app.AppState.PLAYING:
		failures.append("session ready timeout: " + app.status_label.text)
		return false
	return true


func _wait_fixture_loaded() -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		if app.session.world.voxel_tool != null and app.session.world.voxel_tool.is_area_editable(FIXTURE_REGION):
			return true
		await get_tree().process_frame
	failures.append("fixture area load timeout")
	return false


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()


func _record(test_id: String, passed: bool, expected: String, evidence: Variant) -> void:
	print("%s %s expected=%s evidence=%s" % [test_id, "PASS" if passed else "FAIL", expected, JSON.stringify(evidence)])
	if not passed:
		failures.append(test_id)
