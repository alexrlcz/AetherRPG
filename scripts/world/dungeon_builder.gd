class_name DungeonBuilder
extends RefCounted
## Turns a DungeonLayout into a level scene: floor, outer and partition walls
## (low on the camera side, full-height collision), door frames, wall torches,
## props, decor, hazards, lighting, a Marker3D per label and an ExitGate on an
## "Exit" label (under the navigation region: its pillars bake into the
## navmesh). Used at runtime
## (generated levels) and by tools/build_dungeon.gd (saved scenes).
##
##   var level := DungeonBuilder.new().build(layout)
##   add_child(level)
##   DungeonBuilder.bake_navigation(level, true)   # await its bake_finished
##
## Static geometry and props sit under the level's NavigationRegion3D on the
## world layer, so the navmesh bakes from their colliders; decor (no
## collision) and hazards stay outside it so they don't block paths.

## World metres per map grid cell.
const CELL := 2.0
const WALL_HEIGHT := 2.6
## Outer walls between the camera and the room are drawn this tall so they don't
## hide the room; their collision stays WALL_HEIGHT (movement, line of sight).
const LOW_WALL_HEIGHT := 0.9
## Horizontal direction from a target toward the camera (IsoCameraRig yaw 45°
## puts it at +X +Z). Walls facing it are low and get no torches.
const CAMERA_SIDE := Vector2(0.7071, 0.7071)
const WALL_THICKNESS := 0.6
const FLOOR_THICKNESS := 1.0
## Map pixels between a door rectangle and the wall gap it sits in.
const DOOR_GAP_PADDING_PX := 6.0
const WORLD_LAYER := 1
const SPIKE_TRAP := "res://scenes/world/hazards/spike_trap.tscn"

## Wall torches: one per wall edge at least this long (cells), two from twice it.
const TORCH_MIN_EDGE := 4.0
const TORCH_HEIGHT := 1.9
const TORCH_COLOR := Color(1.0, 0.62, 0.32)

## Kinds understood in DungeonLayout.props.
const PROP_KINDS := ["pillar", "crate", "barrel", "table", "chest", "rubble", "statue",
	"brazier", "campfire", "throne"]
const DECOR_KINDS := ["carpet", "bedroll"]
const HAZARD_KINDS := ["spike_trap"]

var _mats := {}
var _layout: DungeonLayout


## The level as a node tree (not yet in the scene tree; navmesh not baked).
## Its NavigationRegion3D already carries the settings to bake with.
func build(layout: DungeonLayout, level_name: String = "Dungeon") -> Node3D:
	_layout = layout
	_make_materials()
	var root := Node3D.new()
	root.name = level_name
	_build_environment(root)
	var nav := NavigationRegion3D.new()
	nav.name = "NavigationRegion3D"
	nav.navigation_mesh = make_navigation_mesh()
	root.add_child(nav)
	_build_floor(nav)
	_build_walls(nav)
	_build_doors(root)
	_build_torches(root)
	_build_props(nav, root)
	_build_markers(root)
	_build_exit_gate(nav)
	return root


## Navmesh settings for every dungeon: baked from static colliders on the
## world layer, agents 2 m tall (radius 0.5 m, the default).
static func make_navigation_mesh() -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = WORLD_LAYER
	navmesh.agent_height = 2.0
	return navmesh


## Bakes the navmesh of a built level that is in the scene tree. On a thread
## the call returns at once; await the region's `bake_finished` signal.
## Returns the region.
static func bake_navigation(level: Node3D, on_thread: bool) -> NavigationRegion3D:
	var nav := level.get_node("NavigationRegion3D") as NavigationRegion3D
	if nav.navigation_mesh == null:
		nav.navigation_mesh = make_navigation_mesh()
	nav.bake_navigation_mesh(on_thread)
	return nav


func _world(cell_point: Vector2, y: float = 0.0) -> Vector3:
	return _layout.to_world(cell_point, CELL, y)


func _is_floor(cell_point: Vector2) -> bool:
	return _layout.is_floor(cell_point)


# --- Geometry --------------------------------------------------------------

func _build_floor(parent: Node3D) -> void:
	var body := _static_body(parent, "Floor")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bounds := _layout.bounds()
	# One box per horizontal run of floor cells.
	for y in range(int(bounds.position.y), int(bounds.end.y)):
		var x := int(bounds.position.x)
		while x < int(bounds.end.x):
			if not _is_floor(Vector2(x + 0.5, y + 0.5)):
				x += 1
				continue
			var start := x
			while x < int(bounds.end.x) and _is_floor(Vector2(x + 0.5, y + 0.5)):
				x += 1
			var size := Vector3((x - start) * CELL, FLOOR_THICKNESS, CELL)
			var centre := _world(Vector2((start + x) * 0.5, y + 0.5), -FLOOR_THICKNESS * 0.5)
			_append_box(st, size, Transform3D(Basis(), centre))
			_add_box_shape(body, size, Transform3D(Basis(), centre))
	_add_merged_mesh(body, st, _mats["floor"], "Mesh")


func _build_walls(parent: Node3D) -> void:
	var body := _static_body(parent, "Walls")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_low := SurfaceTool.new()
	st_low.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t := WALL_THICKNESS / CELL  # thickness in cells
	for ring in _layout.floor_rings:
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			if a.is_equal_approx(b):
				continue
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			if _is_floor((a + b) * 0.5 + n * 0.1):
				n = -n  # n points away from the floor
			# Extend into convex corners only; reflex corners would poke into the room.
			var ext_a := t if not _is_floor(a - d * t * 0.5 + n * t * 0.5) else 0.0
			var ext_b := t if not _is_floor(b + d * t * 0.5 + n * t * 0.5) else 0.0
			var low := n.dot(CAMERA_SIDE) > 0.1
			_add_wall_segment(body, st_low if low else st, a - d * ext_a + n * t * 0.5,
					b + d * ext_b + n * t * 0.5, LOW_WALL_HEIGHT if low else WALL_HEIGHT)
	for line: PackedVector2Array in _layout.partitions:
		for i in line.size() - 1:
			var d := (line[i + 1] - line[i]).normalized()
			# Ends run into the outer wall / door frame.
			_add_wall_segment(body, st, line[i] - d * t * 0.5, line[i + 1] + d * t * 0.5, WALL_HEIGHT)
	_add_merged_mesh(body, st, _mats["wall"], "Mesh")
	_add_merged_mesh(body, st_low, _mats["wall"], "LowMesh")


## Adds a wall whose centre line runs from a to b (cells): a full-height
## collision box and a visual box `visual_height` tall.
func _add_wall_segment(body: StaticBody3D, st: SurfaceTool, a: Vector2, b: Vector2,
		visual_height: float) -> void:
	var wa := _world(a)
	var wb := _world(b)
	var length := wa.distance_to(wb)
	var basis := Basis(Vector3.UP, -atan2(wb.z - wa.z, wb.x - wa.x))
	var centre := (wa + wb) * 0.5
	_append_box(st, Vector3(length, visual_height, WALL_THICKNESS),
			Transform3D(basis, centre + Vector3.UP * visual_height * 0.5))
	_add_box_shape(body, Vector3(length, WALL_HEIGHT, WALL_THICKNESS),
			Transform3D(basis, centre + Vector3.UP * WALL_HEIGHT * 0.5))


func _build_doors(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Doors"
	parent.add_child(group)
	var pad := DOOR_GAP_PADDING_PX / DungeonLayout.GRID_PX
	for rect: PackedVector2Array in _layout.doors:
		var lo := rect[0]
		var hi := rect[0]
		for p in rect:
			lo = lo.min(p)
			hi = hi.max(p)
		var horizontal := (hi.x - lo.x) > (hi.y - lo.y)
		var half := ((hi.x - lo.x) if horizontal else (hi.y - lo.y)) * 0.5 + pad
		var centre := (lo + hi) * 0.5
		var frame := Node3D.new()
		frame.name = "DoorFrame%d" % (group.get_child_count() + 1)
		frame.position = _world(centre)
		frame.rotation.y = 0.0 if horizontal else -PI * 0.5
		group.add_child(frame)
		var width := half * 2.0 * CELL
		var post := Vector3(0.35, WALL_HEIGHT + 0.15, WALL_THICKNESS + 0.25)
		for side in [-1.0, 1.0]:
			_mesh(frame, BoxMesh, {"size": post}, _mats["wood_dark"],
					Vector3(side * (width * 0.5 + post.x * 0.5 - 0.05), post.y * 0.5, 0))
		_mesh(frame, BoxMesh, {"size": Vector3(width + post.x * 2.0, 0.3, post.z)}, _mats["wood_dark"],
				Vector3(0, WALL_HEIGHT - 0.05, 0))


func _build_torches(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Torches"
	parent.add_child(group)
	for ring in _layout.floor_rings:
		for i in ring.size():
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var length := a.distance_to(b)
			if length < TORCH_MIN_EDGE:
				continue
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x)
			if not _is_floor((a + b) * 0.5 + n * 0.1):
				n = -n  # n points into the room
			if n.dot(CAMERA_SIDE) < -0.1:
				continue  # low camera-side wall
			var spots := [0.5] if length < TORCH_MIN_EDGE * 2.0 else [0.25, 0.75]
			for f: float in spots:
				var torch := _make_torch()
				torch.name = "Torch%d" % (group.get_child_count() + 1)
				var pos := a.lerp(b, f)
				torch.position = _world(pos, TORCH_HEIGHT)
				torch.rotation.y = atan2(-n.x, -n.y)  # local -Z faces the room
				group.add_child(torch)


func _make_torch() -> Node3D:
	var torch := Node3D.new()
	_mesh(torch, BoxMesh, {"size": Vector3(0.12, 0.12, 0.35)}, _mats["metal"], Vector3(0, -0.05, -0.15))
	_mesh(torch, CylinderMesh, {"top_radius": 0.07, "bottom_radius": 0.05, "height": 0.35},
			_mats["wood_dark"], Vector3(0, 0.05, -0.32))
	_mesh(torch, SphereMesh, {"radius": 0.11, "height": 0.26}, _mats["flame"], Vector3(0, 0.28, -0.32))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.35, -0.6)
	light.light_color = TORCH_COLOR
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.omni_attenuation = 1.2
	torch.add_child(light)
	return torch


# --- Props -----------------------------------------------------------------

func _build_props(nav: Node3D, root: Node3D) -> void:
	var props := Node3D.new()
	props.name = "Props"
	nav.add_child(props)  # static props block navigation
	var decor := Node3D.new()
	decor.name = "Decor"
	root.add_child(decor)  # no collision, outside the navigation region
	var hazards := Node3D.new()
	hazards.name = "Hazards"
	root.add_child(hazards)
	var counts := {}
	for entry: Array in _layout.props:
		var kind: String = entry[0]
		counts[kind] = counts.get(kind, 0) + 1
		var node: Node3D
		var target := props
		if kind in HAZARD_KINDS:
			node = (load(SPIKE_TRAP) as PackedScene).instantiate()
			target = hazards
		elif kind in DECOR_KINDS:
			node = _build_decor(kind)
			target = decor
		else:
			node = _build_prop(kind)
		node.name = "%s%d" % [kind.to_pascal_case(), counts[kind]]
		node.position = _world(Vector2(entry[1], entry[2]))
		node.rotation.y = deg_to_rad(entry[3])
		target.add_child(node)


func _build_prop(kind: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	match kind:
		"pillar":
			_mesh(body, BoxMesh, {"size": Vector3(1.2, 0.3, 1.2)}, _mats["stone"], Vector3(0, 0.15, 0))
			_mesh(body, CylinderMesh, {"top_radius": 0.42, "bottom_radius": 0.48, "height": WALL_HEIGHT},
					_mats["stone"], Vector3(0, WALL_HEIGHT * 0.5, 0))
			_mesh(body, BoxMesh, {"size": Vector3(1.1, 0.25, 1.1)}, _mats["stone"], Vector3(0, WALL_HEIGHT, 0))
			_add_cylinder_shape(body, 0.55, WALL_HEIGHT)
		"crate":
			_mesh(body, BoxMesh, {"size": Vector3(0.9, 0.9, 0.9)}, _mats["wood"], Vector3(0, 0.45, 0))
			_mesh(body, BoxMesh, {"size": Vector3(0.94, 0.12, 0.94)}, _mats["wood_dark"], Vector3(0, 0.45, 0))
			_add_box_shape(body, Vector3(0.9, 0.9, 0.9), Transform3D(Basis(), Vector3(0, 0.45, 0)))
		"barrel":
			_mesh(body, CylinderMesh, {"top_radius": 0.34, "bottom_radius": 0.34, "height": 0.95},
					_mats["wood"], Vector3(0, 0.475, 0))
			for y in [0.18, 0.77]:
				_mesh(body, CylinderMesh, {"top_radius": 0.36, "bottom_radius": 0.36, "height": 0.06},
						_mats["metal"], Vector3(0, y, 0))
			_add_cylinder_shape(body, 0.38, 0.95)
		"table":
			_mesh(body, BoxMesh, {"size": Vector3(1.8, 0.1, 1.0)}, _mats["wood"], Vector3(0, 0.8, 0))
			for x in [-0.8, 0.8]:
				for z in [-0.4, 0.4]:
					_mesh(body, BoxMesh, {"size": Vector3(0.1, 0.75, 0.1)}, _mats["wood_dark"],
							Vector3(x, 0.375, z))
			_add_box_shape(body, Vector3(1.8, 0.85, 1.0), Transform3D(Basis(), Vector3(0, 0.425, 0)))
		"chest":
			_mesh(body, BoxMesh, {"size": Vector3(1.0, 0.5, 0.6)}, _mats["wood"], Vector3(0, 0.25, 0))
			_mesh(body, BoxMesh, {"size": Vector3(1.04, 0.16, 0.64)}, _mats["wood_dark"], Vector3(0, 0.55, 0))
			_mesh(body, BoxMesh, {"size": Vector3(0.12, 0.18, 0.05)}, _mats["gold"], Vector3(0, 0.45, 0.33))
			_add_box_shape(body, Vector3(1.0, 0.65, 0.6), Transform3D(Basis(), Vector3(0, 0.325, 0)))
		"rubble":
			var rocks := [[Vector3(0, 0.25, 0), Vector3(0.8, 0.5, 0.7), 15.0],
					[Vector3(0.55, 0.18, 0.3), Vector3(0.5, 0.36, 0.5), 40.0],
					[Vector3(-0.4, 0.15, 0.45), Vector3(0.45, 0.3, 0.4), -25.0]]
			for r: Array in rocks:
				var m := _mesh(body, BoxMesh, {"size": r[1]}, _mats["stone"], r[0])
				m.rotation_degrees = Vector3(8, r[2], -6)
			_add_box_shape(body, Vector3(1.4, 0.5, 1.2), Transform3D(Basis(), Vector3(0.05, 0.25, 0.15)))
		"statue":
			_mesh(body, BoxMesh, {"size": Vector3(1.4, 0.6, 1.4)}, _mats["stone"], Vector3(0, 0.3, 0))
			_mesh(body, CylinderMesh, {"top_radius": 0.25, "bottom_radius": 0.38, "height": 1.5},
					_mats["statue"], Vector3(0, 1.35, 0))
			_mesh(body, SphereMesh, {"radius": 0.22, "height": 0.44}, _mats["statue"], Vector3(0, 2.3, 0))
			_add_box_shape(body, Vector3(1.4, 2.5, 1.4), Transform3D(Basis(), Vector3(0, 1.25, 0)))
		"brazier":
			_mesh(body, CylinderMesh, {"top_radius": 0.12, "bottom_radius": 0.25, "height": 0.9},
					_mats["metal"], Vector3(0, 0.45, 0))
			_mesh(body, CylinderMesh, {"top_radius": 0.48, "bottom_radius": 0.3, "height": 0.25},
					_mats["metal"], Vector3(0, 1.0, 0))
			_mesh(body, SphereMesh, {"radius": 0.3, "height": 0.5}, _mats["flame"], Vector3(0, 1.2, 0))
			_add_light(body, Color(1.0, 0.45, 0.2), 3.0, 9.0, Vector3(0, 1.4, 0), false)
			_add_cylinder_shape(body, 0.48, 1.2)
		"campfire":
			for i in 7:
				var a := TAU * i / 7.0
				var stone := _mesh(body, BoxMesh, {"size": Vector3(0.28, 0.2, 0.22)}, _mats["stone"],
						Vector3(cos(a) * 0.5, 0.1, sin(a) * 0.5))
				stone.rotation.y = -a
			_mesh(body, SphereMesh, {"radius": 0.28, "height": 0.45}, _mats["flame"], Vector3(0, 0.2, 0))
			_add_light(body, Color(1.0, 0.55, 0.25), 10.0, 8.0, Vector3(0, 0.8, 0), true)
			_add_cylinder_shape(body, 0.62, 0.6)
		"throne":
			_mesh(body, BoxMesh, {"size": Vector3(2.4, 0.3, 2.0)}, _mats["stone"], Vector3(0, 0.15, 0))
			_mesh(body, BoxMesh, {"size": Vector3(1.2, 0.6, 0.9)}, _mats["stone_dark"], Vector3(0, 0.6, -0.1))
			_mesh(body, BoxMesh, {"size": Vector3(1.2, 2.0, 0.3)}, _mats["stone_dark"], Vector3(0, 1.3, 0.45))
			_mesh(body, BoxMesh, {"size": Vector3(0.9, 0.55, 0.7)}, _mats["carpet"], Vector3(0, 0.92, -0.1))
			_add_box_shape(body, Vector3(2.4, 2.3, 2.0), Transform3D(Basis(), Vector3(0, 1.15, 0)))
		_:
			push_error("DungeonBuilder: unknown prop kind '%s'" % kind)
	return body


func _build_decor(kind: String) -> Node3D:
	var node := Node3D.new()
	match kind:
		"carpet":
			_mesh(node, BoxMesh, {"size": Vector3(1.8, 0.02, 15.5)}, _mats["carpet"], Vector3(0, 0.01, 0))
		"bedroll":
			_mesh(node, BoxMesh, {"size": Vector3(0.8, 0.08, 1.9)}, _mats["cloth"], Vector3(0, 0.04, 0))
			_mesh(node, BoxMesh, {"size": Vector3(0.7, 0.15, 0.35)}, _mats["cloth_light"], Vector3(0, 0.1, -0.7))
	return node


func _build_markers(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Markers"
	parent.add_child(group)
	for label: Array in _layout.labels:
		var marker := Marker3D.new()
		marker.name = (label[0] as String).to_pascal_case()
		marker.position = _world(label[1])
		group.add_child(marker)


func _build_exit_gate(nav: Node3D) -> void:
	for label: Array in _layout.labels:
		if (label[0] as String).strip_edges().to_lower() == "exit":
			var gate := ExitGate.new()
			gate.name = "ExitGate"
			gate.position = _world(label[1])
			nav.add_child(gate)
			return


# --- Scene helpers ---------------------------------------------------------

func _build_environment(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)
	# Dim cool key light so silhouettes and shapes stay readable between torches.
	var moon := DirectionalLight3D.new()
	moon.name = "FillLight"
	moon.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(30), 0)), Vector3(0, 10, 0))
	moon.light_color = Color(0.7, 0.75, 0.95)
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	parent.add_child(moon)


func _make_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	# Subtle variation only: the noise just darkens the albedo by up to ~25%.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.75, 0.75))
	ramp.set_color(1, Color(1, 1, 1))
	tex.color_ramp = ramp
	_mats["floor"] = _stone_material(Color(0.5, 0.47, 0.43), tex, 0.12)
	_mats["wall"] = _stone_material(Color(0.42, 0.39, 0.37), tex, 0.2)
	_mats["stone"] = _stone_material(Color(0.55, 0.53, 0.5), tex, 0.5)
	_mats["stone_dark"] = _stone_material(Color(0.25, 0.24, 0.26), tex, 0.5)
	_mats["statue"] = _flat(Color(0.62, 0.66, 0.6), 0.8)
	_mats["wood"] = _flat(Color(0.5, 0.33, 0.18), 0.85)
	_mats["wood_dark"] = _flat(Color(0.3, 0.19, 0.11), 0.9)
	_mats["metal"] = _flat(Color(0.22, 0.22, 0.24), 0.5, 0.7)
	_mats["gold"] = _flat(Color(0.85, 0.65, 0.2), 0.35, 0.9)
	_mats["carpet"] = _flat(Color(0.5, 0.08, 0.08), 1.0)
	_mats["cloth"] = _flat(Color(0.32, 0.38, 0.25), 1.0)
	_mats["cloth_light"] = _flat(Color(0.7, 0.66, 0.55), 1.0)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color(1.0, 0.6, 0.2)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.5, 0.15)
	flame.emission_energy_multiplier = 3.0
	_mats["flame"] = flame


func _stone_material(color: Color, tex: Texture2D, scale: float) -> StandardMaterial3D:
	var m := _flat(color, 0.95)
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _flat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _static_body(parent: Node, body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	return body


func _append_box(st: SurfaceTool, size: Vector3, xf: Transform3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box, 0, xf)


func _add_merged_mesh(body: Node3D, st: SurfaceTool, material: Material, mesh_name: String) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	body.add_child(mi)


func _add_box_shape(body: Node3D, size: Vector3, xf: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)


func _add_cylinder_shape(body: Node3D, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	body.add_child(cs)


func _add_light(parent: Node3D, color: Color, energy: float, light_range: float,
		pos: Vector3, shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = shadows
	light.position = pos
	parent.add_child(light)


## Adds a MeshInstance3D with a new primitive mesh of `type` configured by `props`.
func _mesh(parent: Node3D, type: Variant, props: Dictionary, material: Material,
		pos: Vector3) -> MeshInstance3D:
	var mesh: PrimitiveMesh = type.new()
	for key: String in props:
		mesh.set(key, props[key])
	mesh.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	if material == _mats["flame"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # don't block its own light
	parent.add_child(mi)
	return mi
