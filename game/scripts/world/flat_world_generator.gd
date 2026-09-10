class_name FlatWorldGenerator
extends VoxelGeneratorScript

const CHANNEL := VoxelBuffer.CHANNEL_TYPE


func _get_used_channels_mask() -> int:
	return 1 << CHANNEL


func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod != 0:
		return
	var size := buffer.get_size()
	for local_z in range(size.z):
		var world_z := origin.z + local_z
		for local_y in range(size.y):
			var world_y := origin.y + local_y
			for local_x in range(size.x):
				var world_x := origin.x + local_x
				buffer.set_voxel(_block_at(world_x, world_y, world_z), local_x, local_y, local_z, CHANNEL)


func _block_at(x: int, y: int, z: int) -> int:
	if (x == 4 or x == 7) and z == 40 and y >= 0 and y < 4:
		return 4
	if x >= 8 and x < 11 and z >= 35 and z < 38 and y >= -4 and y < -2:
		return 6
	if x >= -8 and x < -5 and z >= 35 and z < 38 and y >= -4 and y < -2:
		return 7
	if y == -16:
		return 9
	if y >= -15 and y < -3:
		return 3
	if y >= -3 and y < -1:
		return 2
	if y == -1:
		return 1
	return 0

