class_name TrackCurve
extends RefCounted

## CoasterCraft tracks (docs/COASTERCRAFT_TRACKS.md): the one curve engine
## every smooth track piece shares. A curve is a JSON-safe Dictionary a
## station record carries under "curve": {kind, origin, along, side, up,
## params}; a piece also records the parameter range "t0".."t1" of the part
## of the curve that passes through its cell. Pieces ride the curve
## (`ride_point` = point at the nearest t inside the piece's range), lean
## into it (`up_at`: the centre of curvature, blended by the curve's bank),
## and draw it (`GameSession._build_curve_track_visual`).
##
## Kinds (t runs 0..1 along every curve):
## - line: origin + along * length * t + up * rise * t
## - helix: the loop - a circle in the along/up plane, radius r, `turns`
##   turns starting at the bottom, drifting `drift` cells along `side`
## - arc: a flat bend of radius r from `start` through `sweep` degrees in
##   the along/side plane (angle 0 = the curve heading along, turning
##   toward side as the angle grows)
## - vertical_arc: the same in the along/up plane (slope-in / crest)
## - s_bend: origin + along * length * t + side * shift * S(t) + up * rise * S(t)
##   with S the smoothstep, the lane switcher / climb blend

const SAMPLES := 48
const REFINE := 5
const EPSILON := 0.0005


static func make(kind: String, origin: Vector3, along: Vector3, side: Vector3, params: Dictionary, bank: float = 1.0) -> Dictionary:
	return {"kind": kind, "origin": [origin.x, origin.y, origin.z], "along": [along.x, along.y, along.z], "side": [side.x, side.y, side.z], "params": params, "bank": bank}


static func make_helix(bottom: Vector3, along: Vector3, side: Vector3, radius: float, drift: float = 1.0, turns: float = 1.0) -> Dictionary:
	return make("helix", bottom, along, side, {"radius": radius, "drift": drift, "turns": turns}, 1.0)


static func make_line(origin: Vector3, along: Vector3, side: Vector3, length: float, rise: float = 0.0) -> Dictionary:
	return make("line", origin, along, side, {"length": length, "rise": rise}, 0.0)


static func make_arc(center: Vector3, along: Vector3, side: Vector3, radius: float, start_degrees: float, sweep_degrees: float, bank: float = 0.35) -> Dictionary:
	return make("arc", center, along, side, {"radius": radius, "start": start_degrees, "sweep": sweep_degrees}, bank)


static func make_vertical_arc(center: Vector3, along: Vector3, side: Vector3, radius: float, start_degrees: float, sweep_degrees: float) -> Dictionary:
	return make("vertical_arc", center, along, side, {"radius": radius, "start": start_degrees, "sweep": sweep_degrees}, 1.0)


static func make_s_bend(origin: Vector3, along: Vector3, side: Vector3, length: float, shift: float, rise: float = 0.0) -> Dictionary:
	return make("s_bend", origin, along, side, {"length": length, "shift": shift, "rise": rise}, 0.35)


## A climb (or a descent: negative `rise`): slope-in, straight grade and
## slope-out in one smooth profile - an s_bend with no lateral shift. Bank 0
## keeps riders upright (the pitch comes from the heading; a vertical
## profile has no side to lean into).
static func make_climb(origin: Vector3, along: Vector3, side: Vector3, length: float, rise: float) -> Dictionary:
	return make("s_bend", origin, along, side, {"length": length, "shift": 0.0, "rise": rise}, 0.0)


static func _vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


static func origin_of(curve: Dictionary) -> Vector3:
	return _vector(curve.get("origin"), Vector3.ZERO)


static func along_of(curve: Dictionary) -> Vector3:
	return _vector(curve.get("along"), Vector3.FORWARD)


static func side_of(curve: Dictionary) -> Vector3:
	return _vector(curve.get("side"), Vector3.RIGHT)


## The point on `curve` at parameter `t` (clamped to 0..1).
static func point(curve: Dictionary, t: float) -> Vector3:
	t = clampf(t, 0.0, 1.0)
	var origin := origin_of(curve)
	var along := along_of(curve)
	var side := side_of(curve)
	var params: Dictionary = curve.get("params", {})
	match str(curve.get("kind", "")):
		"line":
			return origin + along * float(params.get("length", 1.0)) * t + Vector3.UP * float(params.get("rise", 0.0)) * t
		"helix":
			var radius := float(params.get("radius", 1.0))
			var theta := TAU * float(params.get("turns", 1.0)) * t
			return origin + Vector3.UP * radius + along * sin(theta) * radius - Vector3.UP * cos(theta) * radius + side * float(params.get("drift", 0.0)) * t
		"arc":
			var radius := float(params.get("radius", 1.0))
			var angle := deg_to_rad(float(params.get("start", 0.0)) + float(params.get("sweep", 90.0)) * t)
			return origin + along * sin(angle) * radius - side * cos(angle) * radius
		"vertical_arc":
			var radius := float(params.get("radius", 1.0))
			var angle := deg_to_rad(float(params.get("start", 0.0)) + float(params.get("sweep", 90.0)) * t)
			return origin + along * sin(angle) * radius - Vector3.UP * cos(angle) * radius
		"s_bend":
			var blend := t * t * (3.0 - 2.0 * t)
			return origin + along * float(params.get("length", 1.0)) * t + side * float(params.get("shift", 0.0)) * blend + Vector3.UP * float(params.get("rise", 0.0)) * blend
	return origin


## Unit direction of travel at `t`.
static func tangent(curve: Dictionary, t: float) -> Vector3:
	var ahead := point(curve, minf(1.0, t + EPSILON))
	var behind := point(curve, maxf(0.0, t - EPSILON))
	var direction := ahead - behind
	if direction.length() < 0.000001:
		return along_of(curve)
	return direction.normalized()


## The rider's up at `t`: the curve's centre-of-curvature direction blended
## with world up by the curve's bank (1 = lean fully into the curve, as a
## loop must; 0 = stay upright).
static func up_at(curve: Dictionary, t: float) -> Vector3:
	var h := 0.02
	var ahead := point(curve, minf(1.0, t + h))
	var behind := point(curve, maxf(0.0, t - h))
	var here := point(curve, t)
	var normal := ahead + behind - here * 2.0
	var bank := clampf(float(curve.get("bank", 1.0)), 0.0, 1.0)
	if normal.length() < 0.00001 or bank <= 0.0:
		return Vector3.UP
	normal = normal.normalized()
	var blended := Vector3.UP.lerp(normal, bank)
	if blended.length() < 0.05:
		return normal
	return blended.normalized()


## The parameter in `t0..t1` whose point lies nearest `target`: coarse
## samples, then refined by halving around the best.
static func nearest_t(curve: Dictionary, target: Vector3, t0: float = 0.0, t1: float = 1.0) -> float:
	var best_t := t0
	var best_distance := INF
	for index in range(SAMPLES + 1):
		var t := lerpf(t0, t1, float(index) / float(SAMPLES))
		var distance := point(curve, t).distance_squared_to(target)
		if distance < best_distance:
			best_distance = distance
			best_t = t
	var step := (t1 - t0) / float(SAMPLES)
	for _round in range(REFINE):
		step *= 0.5
		for candidate in [best_t - step, best_t + step]:
			var t := clampf(candidate, t0, t1)
			var distance := point(curve, t).distance_squared_to(target)
			if distance < best_distance:
				best_distance = distance
				best_t = t
	return best_t


## The cells the curve passes through, in order, each with the parameter
## range it covers: [{cell, t0, t1}]. `ride_height` is the rail-top offset
## of a piece's point above its cell floor (flat rails ride at 0.55).
static func cells(curve: Dictionary, steps: int = 720) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(steps + 1):
		var t := float(index) / float(steps)
		var p := point(curve, t)
		var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		if not result.is_empty() and Vector3i(result[result.size() - 1].cell) == cell:
			result[result.size() - 1].t1 = t
			continue
		var seen := false
		for entry in result:
			if Vector3i(entry.cell) == cell:
				seen = true
				break
		if seen:
			continue
		result.append({"cell": cell, "t0": t, "t1": t})
	return result


## Pieces for a lay tool: every cell of the curve as `entity_id` with the
## curve, its t range, joints to the previous / next cell (the ends join
## `before` / `after`) and `extra` merged in. Same shape as
## CoasterRails.loop_element_layout pieces.
static func pieces(curve: Dictionary, entity_id: String, rotation: int, before: Vector3i, after: Vector3i, extra: Dictionary = {}, steps: int = 720) -> Array[Dictionary]:
	var spans := cells(curve, steps)
	var out: Array[Dictionary] = []
	for index in range(spans.size()):
		var span: Dictionary = spans[index]
		var cell: Vector3i = span.cell
		var joints: Array[Vector3i] = []
		joints.append(Vector3i(spans[index - 1].cell) if index > 0 else before)
		joints.append(Vector3i(spans[index + 1].cell) if index + 1 < spans.size() else after)
		var piece_extra := extra.duplicate()
		piece_extra["curve"] = curve
		piece_extra["t0"] = float(span.t0)
		piece_extra["t1"] = float(span.t1)
		out.append({"cell": cell, "entity_id": entity_id, "rotation": rotation, "joints": joints, "extra": piece_extra})
	return out


## A piece's own parameter: the nearest t inside its range to its cell centre.
static func piece_t(record: Dictionary) -> float:
	var curve: Dictionary = record.get("curve", {})
	var anchor: Vector3i = record.get("anchor", Vector3i.ZERO)
	return nearest_t(curve, Vector3(anchor) + Vector3(0.5, 0.55, 0.5), float(record.get("t0", 0.0)), float(record.get("t1", 1.0)))
