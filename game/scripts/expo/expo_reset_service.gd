class_name ExpoResetService
extends RefCounted

## Development Expo reset groups (docs/DEVELOPMENT_EXPO.md section 14, handoff
## "Battlefield controls"): a **scenario reset boundary**.
##
## A district's exhibits may name a `reset_group` in the manifest. Every group
## that is not a whole district becomes a scenario: its boundary is the union
## of its parcels, and resetting it restores exactly what is inside that box
## and nothing else in the Expo. The Battlefield is the first scenario; a later
## one gets its own boundary for free by naming a new `reset_group`.
##
## One reset is three steps, in this order:
##
## 1. **Live state inside the box stops.** Any core-defense drill whose arena
##    centre lies in the boundary is cleared through the ordinary
##    `CoreDefenseService.clear_for_other_mode()` - attackers removed, drill
##    back to IDLE. A drill somewhere else in the Expo is left alone.
## 2. **The fixture is rebuilt.** Each of the group's exhibits is re-placed
##    through `ExpoBuilder.place_exhibit`, in manifest order, so the terrain
##    under it is levelled again first and every fixture that was destroyed is
##    placed again. A fixture still standing reports OCCUPIED and is kept.
## 3. **What survived is restored.** Every station inside the boundary goes
##    back to full integrity and every siege weapon back to its opening clip
##    (`WorkstationService.restore_integrity` / `restore_siege_ammo`), and the
##    group's container fixtures are restocked by their own exhibit builders.
##
## Steps 2 and 3 are queued on the builder, which drains them a budget per
## frame like any other build, so a reset never freezes the frame. Step 1 is
## immediate: pressing RESET BATTLEFIELD stops the fight at once.

## Groups are registered as `group -> {"district": id, "exhibits": [ids]}`.
var _groups: Dictionary = {}
var builder: ExpoBuilder
var layout: ExpoLayout


func configure(expo_builder: ExpoBuilder, expo_layout: ExpoLayout) -> void:
	builder = expo_builder
	layout = expo_layout


## Registers every scenario group the district's exhibits declare. A group may
## share its district's name (`battlefield`) without being the district's own
## group - that one is `district:<id>` and rebuilds the avenue and the whole
## pad with it. Returns the names registered by this call.
func register_district(district_id: String) -> PackedStringArray:
	var found := PackedStringArray()
	if layout == null:
		return found
	for exhibit_id: String in layout.exhibit_ids(district_id):
		var group := str(layout.exhibit(exhibit_id).get("reset_group", ""))
		if group.is_empty():
			continue
		if not _groups.has(group):
			_groups[group] = {"district": district_id, "exhibits": PackedStringArray()}
			found.append(group)
		var record: Dictionary = _groups[group]
		var members: PackedStringArray = record["exhibits"]
		if not members.has(exhibit_id):
			members.append(exhibit_id)
			record["exhibits"] = members
	return found


func groups() -> PackedStringArray:
	var names := PackedStringArray()
	for group: String in _groups.keys():
		names.append(group)
	names.sort()
	return names


func exhibits(group: String) -> PackedStringArray:
	var record: Dictionary = _groups.get(group, {})
	var members: Variant = record.get("exhibits", PackedStringArray())
	return members if members is PackedStringArray else PackedStringArray()


## The scenario's boundary: the union of its parcels ({} for an unknown group).
func group_bounds(group: String) -> Dictionary:
	if not _groups.has(group) or layout == null:
		return {}
	var low := Vector3i.MAX
	var high := Vector3i.MIN
	for exhibit_id: String in exhibits(group):
		var parcel := layout.parcel_for(exhibit_id)
		if parcel.is_empty():
			continue
		var origin: Vector3i = parcel["origin"]
		var size: Vector3i = parcel["size"]
		low = Vector3i(mini(low.x, origin.x), mini(low.y, origin.y), mini(low.z, origin.z))
		high = Vector3i(maxi(high.x, origin.x + size.x), maxi(high.y, origin.y + size.y), maxi(high.z, origin.z + size.z))
	if low == Vector3i.MAX:
		return {}
	# The pad under a parcel and the headroom over it belong to the scenario
	# too, so a body or a fixture standing on its ground counts as inside.
	low.y = mini(low.y, layout.ground_y() - 1)
	high.y = maxi(high.y, low.y + layout.clear_height() + 1)
	return {"origin": low, "size": high - low}


func contains(group: String, cell: Vector3i) -> bool:
	return _box_contains(group_bounds(group), cell)


## Restores one scenario without touching the rest of the Expo. Returns
## `{ok, group, exhibits, cleared_drill, bounds}`; the rebuild itself is queued
## on the builder, so the caller waits on `ExpoBuilder.progress()`.
func reset(session: GameSession, group: String) -> Dictionary:
	if builder == null or layout == null:
		return {"ok": false, "reason": "EXPO_RESET_UNBOUND", "group": group}
	if not _groups.has(group):
		return {"ok": false, "reason": "NO_GROUP", "group": group}
	if session == null:
		return {"ok": false, "reason": "NO_SESSION", "group": group}
	var bounds := group_bounds(group)
	var cleared := _clear_live_state(session, bounds)
	var members := exhibits(group)
	for exhibit_id: String in members:
		builder.place_exhibit(session, exhibit_id)
	builder.queue_action("reset:" + group, _restore_standing.bind(session, bounds))
	print("EXPO_RESET group=%s exhibits=%d drill_cleared=%s bounds=%s" % [group, members.size(), cleared, bounds.get("origin", Vector3i.ZERO)])
	return {"ok": true, "group": group, "exhibits": members.size(), "cleared_drill": cleared, "bounds": bounds}


## Step 1: the fight inside this boundary stops. A drill defending a core
## somewhere else in the Expo is not this scenario's business and is left
## running.
func _clear_live_state(session: GameSession, bounds: Dictionary) -> bool:
	var core_defense: CoreDefenseService = session.core_defense
	if core_defense == null:
		return false
	if not core_defense.is_active() and core_defense.living_raider_count() == 0:
		return false
	if not _box_contains(bounds, core_defense.arena_center):
		return false
	core_defense.clear_for_other_mode()
	return true


## Step 3: everything still standing inside the boundary goes back to the
## state the fixture opens in.
func _restore_standing(session: GameSession, bounds: Dictionary) -> void:
	var workstations: WorkstationService = session.workstations
	if workstations == null:
		return
	for instance_id: String in workstations.stations.keys():
		var record: Dictionary = workstations.stations[instance_id]
		if not _box_contains(bounds, record.get("anchor", Vector3i.ZERO)):
			continue
		workstations.restore_integrity(instance_id)
		if workstations.siege_status(instance_id).get("ok", false):
			workstations.restore_siege_ammo(instance_id)


static func _box_contains(box: Dictionary, cell: Vector3i) -> bool:
	if box.is_empty():
		return false
	var origin: Vector3i = box.get("origin", Vector3i.ZERO)
	var size: Vector3i = box.get("size", Vector3i.ZERO)
	return cell.x >= origin.x and cell.x < origin.x + size.x \
		and cell.y >= origin.y and cell.y < origin.y + size.y \
		and cell.z >= origin.z and cell.z < origin.z + size.z
