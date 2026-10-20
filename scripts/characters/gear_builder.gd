class_name GearBuilder
## Puts GearDefinition models on a Universal-skeleton character as skinned
## meshes (AppearanceComponent calls it). The model's surfaces are moved into
## skeleton space by the gear's fit, then weighted to bones by its rig, so
## they deform with the animation like the body does. Results are cached per
## gear and body (bone rests), so re-equipping is instant.
##
## Cloaks: `ensure_cloak_bones()` hangs CLOAK_COLUMNS chains of CLOAK_JOINTS
## bones from the anchor bone along the cloth's own surface, the cloth is
## weighted to them, and a SpringBoneSimulator3D ("CloakSpring" under the
## Skeleton3D) swings them with gravity and inertia, kept off the legs and
## torso by capsule colliders.

const CLOAK_COLUMNS := 5
const CLOAK_JOINTS := 4
const CLOAK_SPRING := "CloakSpring"
## Spring settings of every chain, tuned on the player (lift of the cloth
## from hanging straight down, world space, which includes the run cycle's
## forward lean): idle ~12 deg, running 6 m/s ~39 deg, sprinting 8 m/s ~52
## deg. Softer values let a heavy cloak fly up near horizontal.
const CLOAK_STIFFNESS := 8.0
const CLOAK_DRAG := 0.8
const CLOAK_GRAVITY := 5.0
## Cloth above this far (m) below the top of the cloak follows the torso
## (anchor bone) more than the chains, so the collar stays on the shoulders.
const CLOAK_COLLAR := 0.12

## Model surfaces in model space: scene path -> [{arrays, material}].
static var _surfaces: Dictionary = {}
## Built parts: key -> [[ArrayMesh, Skin], ...].
static var _built: Dictionary = {}


## The gear's meshes for `skeleton`, skinned and ready to attach.
static func build(gear: GearDefinition, skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if gear.model == null:
		return result
	if gear.rig == GearDefinition.Rig.CLOAK:
		ensure_cloak_bones(skeleton, gear)  # The skin binds name these bones.
	var sides: Array = [false, true] if gear.rig == GearDefinition.Rig.BOOTS else [false]
	for mirrored: bool in sides:
		var key := _cache_key(gear, skeleton, mirrored)
		if not _built.has(key):
			_built[key] = _build_parts(gear, skeleton, mirrored)
		for part: Array in _built[key]:
			var mesh := MeshInstance3D.new()
			mesh.name = "Gear_%s%s" % [String(gear.id).to_pascal_case(), "_L" if mirrored else ""]
			mesh.mesh = part[0]
			mesh.skin = part[1]
			result.append(mesh)
	return result


## Turns the cloak simulation on (with the cloak's chains) or off.
static func set_cloak_active(skeleton: Skeleton3D, gear: GearDefinition) -> void:
	var spring := skeleton.get_node_or_null(CLOAK_SPRING) as SpringBoneSimulator3D
	if gear == null:
		if spring:
			spring.active = false
		return
	ensure_cloak_bones(skeleton, gear)
	if spring == null:
		spring = _make_spring(skeleton)
	spring.active = true
	spring.reset()


## Adds (or re-places, for another body) the cloak chain bones.
static func ensure_cloak_bones(skeleton: Skeleton3D, gear: GearDefinition) -> void:
	var anchor := skeleton.find_bone(gear.anchor_bone)
	var points := _cloak_points(gear, skeleton)
	for c in CLOAK_COLUMNS:
		var parent := anchor
		for j in CLOAK_JOINTS:
			var bone_name := _cloak_bone(c, j)
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				bone = skeleton.get_bone_count()
				skeleton.add_bone(bone_name)
				skeleton.set_bone_parent(bone, parent)
			var at: Transform3D = Transform3D(Basis.IDENTITY, points[c][j])
			skeleton.set_bone_rest(bone, skeleton.get_bone_global_rest(parent).affine_inverse() * at)
			skeleton.reset_bone_pose(bone)
			parent = bone


static func _cloak_bone(column: int, joint: int) -> String:
	return "cloak_%d_%d" % [column, joint]


## Skeleton-space joint positions [column][joint], laid along the cloth:
## columns across 80% of the collar's width, joints from just under the
## collar to just above the hem, each at the cloth's mean depth there.
static func _cloak_points(gear: GearDefinition, skeleton: Skeleton3D) -> Array:
	var vertices := PackedVector3Array()
	var place := _placement(gear, skeleton, false)
	for surface: Dictionary in _model_surfaces(gear.model):
		for v: Vector3 in surface["arrays"][Mesh.ARRAY_VERTEX]:
			vertices.append(place * v)
	var top := -INF
	var bottom := INF
	for v in vertices:
		top = maxf(top, v.y)
		bottom = minf(bottom, v.y)
	var collar_lo := INF
	var collar_hi := -INF
	for v in vertices:
		if v.y > top - (top - bottom) * 0.1:
			collar_lo = minf(collar_lo, v.x)
			collar_hi = maxf(collar_hi, v.x)
	var centre := (collar_lo + collar_hi) * 0.5
	var half := (collar_hi - collar_lo) * 0.4
	var points := []
	for c in CLOAK_COLUMNS:
		var x := centre + lerpf(-half, half, float(c) / (CLOAK_COLUMNS - 1))
		var column := []
		for j in CLOAK_JOINTS:
			var y := lerpf(top - 0.06, bottom + 0.12, float(j) / (CLOAK_JOINTS - 1))
			var depth := 0.0
			var count := 0
			for v in vertices:
				if absf(v.x - x) < 0.08 and absf(v.y - y) < 0.08:
					depth += v.z
					count += 1
			column.append(Vector3(x, y, depth / count if count > 0 else -0.2))
		points.append(column)
	return points


static func _make_spring(skeleton: Skeleton3D) -> SpringBoneSimulator3D:
	var spring := SpringBoneSimulator3D.new()
	spring.name = CLOAK_SPRING
	skeleton.add_child(spring)
	spring.setting_count = CLOAK_COLUMNS
	for c in CLOAK_COLUMNS:
		spring.set_root_bone_name(c, _cloak_bone(c, 0))
		spring.set_end_bone_name(c, _cloak_bone(c, CLOAK_JOINTS - 1))
		spring.set_extend_end_bone(c, true)
		spring.set_end_bone_direction(c, SpringBoneSimulator3D.BONE_DIRECTION_FROM_PARENT)
		spring.set_end_bone_length(c, 0.3)
		spring.set_radius(c, 0.05)
		spring.set_stiffness(c, CLOAK_STIFFNESS)
		spring.set_drag(c, CLOAK_DRAG)
		spring.set_gravity(c, CLOAK_GRAVITY)
		spring.set_gravity_direction(c, Vector3.DOWN)
		spring.set_enable_all_child_collisions(c, true)
	# Keep the cloth off the body: thighs, calves and the torso.
	for side in ["l", "r"]:
		_capsule(spring, "thigh_" + side, Vector3(0, 0.22, 0), 0.1, 0.55)
		_capsule(spring, "calf_" + side, Vector3(0, 0.2, 0), 0.08, 0.5)
	_capsule(spring, "pelvis", Vector3(0, 0.05, 0), 0.17, 0.45)
	_capsule(spring, "spine_02", Vector3(0, 0.05, 0), 0.17, 0.5)
	return spring


static func _capsule(spring: SpringBoneSimulator3D, bone: String, offset: Vector3, radius: float,
		height: float) -> void:
	var capsule := SpringBoneCollisionCapsule3D.new()
	capsule.name = "Collide_" + bone
	capsule.bone_name = bone
	capsule.position_offset = offset
	capsule.radius = radius
	capsule.height = height
	spring.add_child(capsule)


static func _cache_key(gear: GearDefinition, skeleton: Skeleton3D, mirrored: bool) -> String:
	# Bodies differ by their rests: key on the bones the rigs use.
	var signature := ""
	for bone in [String(gear.anchor_bone), "foot_l", "calf_r", "ball_r", "Head"]:
		var i := skeleton.find_bone(bone)
		if i >= 0:
			signature += str(skeleton.get_bone_global_rest(i).origin.snapped(Vector3.ONE * 0.001))
	return "%s|%s|%s" % [gear.resource_path if gear.resource_path != "" else str(gear.get_instance_id()), mirrored, signature]


## Skeleton-space placement of the model (mirrored: on the other side, for
## the left boot).
static func _placement(gear: GearDefinition, skeleton: Skeleton3D, mirrored: bool) -> Transform3D:
	var anchor_name := String(gear.anchor_bone)
	if mirrored:
		anchor_name = anchor_name.replace("_r", "_l")
	var anchor := skeleton.get_bone_global_rest(skeleton.find_bone(anchor_name)).origin
	var fit := gear.fit
	if mirrored:
		fit = Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3.ZERO) * fit
	return Transform3D(Basis.IDENTITY, anchor) * fit


static func _build_parts(gear: GearDefinition, skeleton: Skeleton3D, mirrored: bool) -> Array:
	var place := _placement(gear, skeleton, mirrored)
	var normal_basis := place.basis.inverse().transposed()
	var flip := place.basis.determinant() < 0.0
	var parts := []
	for surface: Dictionary in _model_surfaces(gear.model):
		var arrays: Array = (surface["arrays"] as Array).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			vertices[i] = place * vertices[i]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i] = (normal_basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in range(0, tangents.size(), 4):
				var t := (place.basis * Vector3(tangents[i], tangents[i + 1], tangents[i + 2])).normalized()
				tangents[i] = t.x
				tangents[i + 1] = t.y
				tangents[i + 2] = t.z
				if flip:
					tangents[i + 3] = -tangents[i + 3]
			arrays[Mesh.ARRAY_TANGENT] = tangents
		if flip:
			# Mirrored: reverse the winding so faces still point out.
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for t in range(0, index.size(), 3):
				var second := index[t + 1]
				index[t + 1] = index[t + 2]
				index[t + 2] = second
			arrays[Mesh.ARRAY_INDEX] = index
		var skin := Skin.new()
		var weights := _weights(gear, skeleton, vertices, mirrored)
		var names: Array = weights[0]
		for bone_name: String in names:
			skin.add_named_bind(bone_name, skeleton.get_bone_global_rest(skeleton.find_bone(bone_name)).affine_inverse())
		arrays[Mesh.ARRAY_BONES] = weights[1]
		arrays[Mesh.ARRAY_WEIGHTS] = weights[2]
		for channel in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[channel] = null
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, surface["material"])
		parts.append([mesh, skin])
	return parts


## [bone names, ARRAY_BONES, ARRAY_WEIGHTS] (4 influences per vertex).
static func _weights(gear: GearDefinition, skeleton: Skeleton3D, vertices: PackedVector3Array,
		mirrored: bool) -> Array:
	var names: Array[String] = []
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(vertices.size() * 4)
	weights.resize(vertices.size() * 4)
	var slot := func(bone_name: String) -> int:
		var i := names.find(bone_name)
		if i < 0:
			names.append(bone_name)
			i = names.size() - 1
		return i
	match gear.rig:
		GearDefinition.Rig.RIGID:
			var anchor: int = slot.call(String(gear.anchor_bone))
			for v in vertices.size():
				bones[v * 4] = anchor
				weights[v * 4] = 1.0
		GearDefinition.Rig.BOOTS:
			var side := "l" if mirrored else "r"
			var calf: int = slot.call("calf_" + side)
			var foot: int = slot.call("foot_" + side)
			var ball: int = slot.call("ball_" + side)
			var ball_z := skeleton.get_bone_global_rest(skeleton.find_bone("ball_" + side)).origin.z
			for v in vertices.size():
				var p := vertices[v]
				var w_calf := smoothstep(0.1, 0.2, p.y)
				var w_ball := smoothstep(ball_z - 0.03, ball_z + 0.03, p.z) * (1.0 - w_calf)
				bones[v * 4] = calf
				weights[v * 4] = w_calf
				bones[v * 4 + 1] = foot
				weights[v * 4 + 1] = 1.0 - w_calf - w_ball
				bones[v * 4 + 2] = ball
				weights[v * 4 + 2] = w_ball
		GearDefinition.Rig.CLOAK:
			var points := _cloak_points(gear, skeleton)
			var anchor: int = slot.call(String(gear.anchor_bone))
			var top: float = points[0][0].y + 0.06
			var columns: Array[float] = []
			for c in CLOAK_COLUMNS:
				columns.append(points[c][0].x)
			var rows: Array[float] = []
			for j in CLOAK_JOINTS:
				rows.append(points[0][j].y)
			var ids := []
			for c in CLOAK_COLUMNS:
				var column := []
				for j in CLOAK_JOINTS:
					column.append(slot.call(_cloak_bone(c, j)))
				ids.append(column)
			for v in vertices.size():
				var p := vertices[v]
				# Between which two columns and which two joints.
				var cu := clampf(inverse_lerp(columns[0], columns[-1], p.x), 0.0, 1.0) * (CLOAK_COLUMNS - 1)
				var c0 := mini(int(cu), CLOAK_COLUMNS - 2)
				var cf := cu - c0
				var ju := clampf(inverse_lerp(rows[0], rows[-1], p.y), 0.0, 1.0) * (CLOAK_JOINTS - 1)
				var j0 := mini(int(ju), CLOAK_JOINTS - 2)
				var jf := ju - j0
				var collar := 1.0 - smoothstep(0.0, CLOAK_COLLAR, top - p.y)
				var cloth := 1.0 - collar
				bones[v * 4] = ids[c0][j0]
				weights[v * 4] = (1.0 - cf) * (1.0 - jf) * cloth
				bones[v * 4 + 1] = ids[c0 + 1][j0]
				weights[v * 4 + 1] = cf * (1.0 - jf) * cloth
				# The lower joints share their weight with the anchor's slot for
				# the collar part (4 influences: the anchor takes the 4th).
				bones[v * 4 + 2] = ids[c0 + (1 if cf >= 0.5 else 0)][j0 + 1]
				weights[v * 4 + 2] = jf * cloth
				bones[v * 4 + 3] = anchor
				weights[v * 4 + 3] = collar
	return [names, bones, weights]


## The model's surfaces in model space (node transforms applied), cached.
static func _model_surfaces(scene: PackedScene) -> Array:
	var key := scene.resource_path
	if _surfaces.has(key):
		return _surfaces[key]
	var result := []
	var root := scene.instantiate() as Node3D
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var node: Node = mi
		while node != root and node is Node3D:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var normal_basis := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in vertices.size():
				vertices[i] = xf * vertices[i]
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in normals.size():
					normals[i] = (normal_basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			if arrays[Mesh.ARRAY_TANGENT] != null:
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				for i in range(0, tangents.size(), 4):
					var t := (xf.basis * Vector3(tangents[i], tangents[i + 1], tangents[i + 2])).normalized()
					tangents[i] = t.x
					tangents[i + 1] = t.y
					tangents[i + 2] = t.z
				arrays[Mesh.ARRAY_TANGENT] = tangents
			if arrays[Mesh.ARRAY_INDEX] == null:
				var index := PackedInt32Array()
				for i in vertices.size():
					index.append(i)
				arrays[Mesh.ARRAY_INDEX] = index
			result.append({"arrays": arrays, "material": mi.get_active_material(s)})
	root.free()
	_surfaces[key] = result
	return result
