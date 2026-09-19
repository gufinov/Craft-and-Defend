class_name PinnedVoxelAStarAdapter
extends RefCounted


func benchmark(terrain: VoxelTerrain, region: AABB, start: Vector3i, goal: Vector3i, iterations: int = 20) -> Dictionary:
	if not ClassDB.class_exists("VoxelAStarGrid3D"):
		return {"ok": false, "reason": "CLASS_UNAVAILABLE"}
	var finder := VoxelAStarGrid3D.new()
	finder.set_terrain(terrain)
	finder.set_region(region)
	var timings: Array[int] = []
	var path: Array = []
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for _iteration in range(maxi(1, iterations)):
		var started := Time.get_ticks_usec()
		path = finder.find_path(start, goal)
		timings.append(Time.get_ticks_usec() - started)
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	timings.sort()
	var visited: Array = finder.debug_get_visited_positions()
	return {
		"ok": not path.is_empty(),
		"reason": "OK" if not path.is_empty() else "NO_ROUTE",
		"path": path,
		"visited_count": visited.size(),
		"median_usec": timings[timings.size() / 2],
		"p95_usec": timings[mini(timings.size() - 1, ceili(float(timings.size()) * 0.95) - 1)],
		"memory_delta_bytes": maxi(0, memory_after - memory_before),
		"iterations": timings.size(),
	}
