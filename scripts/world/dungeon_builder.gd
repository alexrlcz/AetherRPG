class_name DungeonBuilder
extends RefCounted
## Turns a DungeonLayout into a level scene: floor, outer and partition walls
## (cut away on the camera's side of the player), door frames, wall torches,
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
##
## Curves: the layout's outline is smoothed in cell space first (each corner
## becomes an arc of a random radius, `CORNER_RADIUS` x layout.curvature,
## except next to doors and interior walls), cut into short pieces, and then
## every point goes through DungeonLayout.to_world(), whose warp bends the
## straight runs. Floor, walls and their colliders are meshes built from
## those points (ConcavePolygonShape3D colliders), so the navmesh follows the
## curves.

## World metres per map grid cell.
const CELL := 2.0
const WALL_HEIGHT := 4.2
## Walls are full height on every side (the camera orbits); their shader
## (shaders/wall_cutout.gdshader) cuts them down on the camera's side of the
## player. Door frames, torches and pillars use it too, so they go with them.
const WALL_SHADER := preload("res://shaders/wall_cutout.gdshader")
const FLOOR_SHADER := preload("res://shaders/dungeon_floor.gdshader")
const WALL_THICKNESS := 0.6
## Clear height of a doorway; the wall closes over it up to WALL_HEIGHT.
const DOOR_HEIGHT := 3.0
## Map pixels between a door rectangle and the wall gap it sits in.
const DOOR_GAP_PADDING_PX := 6.0
const WORLD_LAYER := 1
const SPIKE_TRAP := "res://scenes/world/hazards/spike_trap.tscn"

## Corner arc radius (cells) at full curvature, random per corner, capped at
## CORNER_MAX_FRACTION of the shorter neighbouring edge.
const CORNER_RADIUS := Vector2(0.7, 1.7)
const CORNER_MAX_FRACTION := 0.45
## Corners closer than this (cells) to a door or an interior wall's end stay
## sharp, so frames and partitions still meet the wall.
const CORNER_KEEP_CLEAR := 1.0
## A corner whose arc cuts into the floor (an inside corner of a room, the
## outer corner of a corridor bend) keeps at least this much floor (cells)
## between the arc and the wall across: rounding never pinches a passage
## shut. With the warp's worst squeeze (1 - WARP_MAX_SLOPE) a 0.8-cell gap is
## still 1.1 m, wider than the navmesh agent (1 m).
const MIN_PASSAGE := 0.8
## Longest straight piece (cells) of an outline: shorter pieces bend with the
## warp.
const SEGMENT := 0.5
## Floor resolution (cells) along the walls; cells away from them are whole.
const FLOOR_STEP := 0.2
## The floor reaches this far (cells) under the walls, so no gap shows.
const FLOOR_UNDER_WALL := 0.15
## Hewn walls: at full curvature the outline is pushed outward (never into a
## room) by up to WALL_BULGE cells, in two waves along the wall of about
## BULGE_WAVELENGTHS cells; none within BULGE_CLEAR of doors and interior
## wall ends, fading in over the next cell.
const WALL_BULGE := 0.32
const BULGE_WAVELENGTHS := Vector2(3.6, 1.7)
const BULGE_CLEAR := 0.6

## Wall torches: along each outline every TORCH_SPACING cells, only on
## gently curving stretches clear of doors.
const TORCH_SPACING := 5.0
const TORCH_HEIGHT := 2.6
const TORCH_COLOR := Color(1.0, 0.62, 0.32)

## Kinds understood in DungeonLayout.props.
const PROP_KINDS := ["pillar", "crate", "barrel", "table", "chest", "rubble", "statue",
	"brazier", "campfire", "throne"]
const DECOR_KINDS := ["carpet", "bedroll"]
const HAZARD_KINDS := ["spike_trap"]
## Footprint radius (cells) of blocking props: one pushed out of a rounded
## corner keeps this far from the wall.
const PROP_RADIUS := {"pillar": 0.32, "crate": 0.34, "barrel": 0.2, "table": 0.5,
	"chest": 0.3, "rubble": 0.38, "statue": 0.38, "brazier": 0.26, "campfire": 0.33,
	"throne": 0.65}
## Enemy spawns keep this far (cells) from the smoothed walls: the navmesh's
## agent radius (0.5 m) plus a margin.
const SPAWN_CLEARANCE := 0.4

var _mats := {}
var _layout: DungeonLayout
var _rng := RandomNumberGenerator.new()
## The smoothed outline (cells): closed rings (rounded corners, hewn
## bulges), and per ring point the unit normal pointing away from the floor.
var _outline: Array[PackedVector2Array] = []
var _outline_normals: Array[PackedVector2Array] = []
## Outline segments by cell (Vector2i -> [[a, b], ...]), for distance queries.
var _segment_grid := {}


## The level as a node tree (not yet in the scene tree; navmesh not baked).
## Its NavigationRegion3D already carries the settings to bake with.
## Also moves `layout.spawns` cells that a rounded corner or a bulge of the
## wall now crowds out to where the navmesh reaches (read them after build()).
func build(layout: DungeonLayout, level_name: String = "Dungeon") -> Node3D:
	_layout = layout
	_rng.seed = layout.curvature_seed()
	_make_materials()
	_smooth_outline()
	for spawn in layout.spawns:
		spawn["cell"] = _clear_of_walls(spawn["cell"], SPAWN_CLEARANCE)
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


## The smoothed outline the walls of `layout` are built along (cells, before
## the warp): rounded, subdivided and bulged rings (debugging, tests).
func smoothed_outline(layout: DungeonLayout) -> Array[PackedVector2Array]:
	_layout = layout
	_rng.seed = layout.curvature_seed()
	_smooth_outline()
	return _outline


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


## Floor of the smoothed outline (even-odd over its rings).
func _is_floor(cell_point: Vector2) -> bool:
	var inside := false
	for ring in _outline:
		if Geometry2D.is_point_in_polygon(cell_point, ring):
			inside = not inside
	return inside


# --- Outline ---------------------------------------------------------------

## Rounds and subdivides every floor ring into `_outline`, with normals.
func _smooth_outline() -> void:
	_outline.clear()
	_outline_normals.clear()
	_segment_grid.clear()
	var keep_sharp: Array[Vector2] = []
	for rect: PackedVector2Array in _layout.doors:
		var c := Vector2.ZERO
		for p in rect:
			c += p
		keep_sharp.append(c / rect.size())
		keep_sharp.append_array(rect)
	for line: PackedVector2Array in _layout.partitions:
		keep_sharp.append(line[0])
		keep_sharp.append(line[-1])
	for ring in _layout.floor_rings:
		var smooth := _subdivide(_round_corners(ring, keep_sharp), true)
		if smooth.size() >= 3:
			_outline.append(smooth)
	# Normals after all rings exist: the floor side needs the whole outline.
	for r in _outline.size():
		_outline[r] = _bulge(_outline[r], _ring_normals(_outline[r]), keep_sharp)
	for ring in _outline:
		_outline_normals.append(_ring_normals(ring))
		for i in ring.size():
			_add_to_grid(ring[i], ring[(i + 1) % ring.size()])


## The ring pushed outward along `normals` by a seeded wave (cells).
func _bulge(ring: PackedVector2Array, normals: PackedVector2Array,
		keep_sharp: Array[Vector2]) -> PackedVector2Array:
	var phase1 := _rng.randf() * TAU
	var phase2 := _rng.randf() * TAU
	var amount := WALL_BULGE * _layout.curvature
	if amount <= 0.0:
		return ring
	var out := PackedVector2Array()
	var travelled := 0.0
	for i in ring.size():
		if i > 0:
			travelled += ring[i].distance_to(ring[i - 1])
		var wave := 0.6 * sin(travelled * TAU / BULGE_WAVELENGTHS.x + phase1) 			+ 0.4 * sin(travelled * TAU / BULGE_WAVELENGTHS.y + phase2)
		var clear := INF
		for q in keep_sharp:
			clear = minf(clear, ring[i].distance_to(q))
		var fade := clampf(clear - BULGE_CLEAR, 0.0, 1.0)
		out.append(ring[i] + normals[i] * amount * (0.5 + 0.5 * wave) * fade)
	return out


## The ring with each corner replaced by an arc (cells).
func _round_corners(ring: PackedVector2Array, keep_sharp: Array[Vector2]) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ring.size()
	for i in n:
		var v := ring[i]
		var prev := ring[(i - 1 + n) % n]
		var next := ring[(i + 1) % n]
		var d1 := (v - prev).normalized()
		var d2 := (next - v).normalized()
		# Draw every corner's radius, used or not, so one corner's rule never
		# shifts the others' randomness.
		var radius := _rng.randf_range(CORNER_RADIUS.x, CORNER_RADIUS.y) * _layout.curvature
		if absf(d1.cross(d2)) < 0.01 or radius <= 0.0 or _near_any(v, keep_sharp, CORNER_KEEP_CLEAR):
			out.append(v)
			continue
		var theta := acos(clampf(-d1.dot(d2), -1.0, 1.0))  # The angle at the corner.
		var bisector := (d2 - d1).normalized()
		if _layout.is_floor(v + bisector * 0.05):
			# The arc bites into the floor by radius * (1 / sin(theta / 2) - 1)
			# along the bisector: leave MIN_PASSAGE to the wall across.
			var room := _clearance(v, bisector) - MIN_PASSAGE
			radius = minf(radius, maxf(room, 0.0) / (1.0 / sin(theta * 0.5) - 1.0))
		var tangent := radius / tan(theta * 0.5)
		var max_tangent := CORNER_MAX_FRACTION * minf(v.distance_to(prev), v.distance_to(next))
		if tangent > max_tangent:
			tangent = max_tangent
			radius = tangent * tan(theta * 0.5)
		if radius < 0.05:
			out.append(v)
			continue
		var t1 := v - d1 * tangent
		var t2 := v + d2 * tangent
		var centre := v + (d2 - d1).normalized() * (radius / sin(theta * 0.5))
		var a1 := (t1 - centre).angle()
		var sweep := wrapf((t2 - centre).angle() - a1, -PI, PI)
		var steps := maxi(2, ceili(absf(sweep) / (PI / 10.0)))
		for s in steps + 1:
			out.append(centre + Vector2.from_angle(a1 + sweep * s / steps) * radius)
	return out


## Distance (cells) from `from` along unit `dir` to the first floor ring or
## interior wall (half its thickness off) it meets; INF if none.
func _clearance(from: Vector2, dir: Vector2) -> float:
	var start := from + dir * 0.01
	var end := from + dir * 50.0
	var best := INF
	for ring in _layout.floor_rings:
		for i in ring.size():
			var hit: Variant = Geometry2D.segment_intersects_segment(start, end, ring[i], ring[(i + 1) % ring.size()])
			if hit != null:
				best = minf(best, from.distance_to(hit))
	var half := WALL_THICKNESS / CELL * 0.5
	for line: PackedVector2Array in _layout.partitions:
		for i in line.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(start, end, line[i], line[i + 1])
			if hit != null:
				best = minf(best, from.distance_to(hit) - half)
	return best


## Splits pieces longer than SEGMENT (cells).
static func _subdivide(points: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	var count := n if closed else n - 1
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % n]
		var pieces := maxi(1, ceili(a.distance_to(b) / SEGMENT))
		for k in pieces:
			out.append(a.lerp(b, float(k) / pieces))
	if not closed:
		out.append(points[n - 1])
	# Drop repeats (arc ends meet straight runs).
	var clean := PackedVector2Array()
	for p in out:
		if clean.is_empty() or not clean[-1].is_equal_approx(p):
			clean.append(p)
	if closed and clean.size() > 1 and clean[0].is_equal_approx(clean[-1]):
		clean.remove_at(clean.size() - 1)
	return clean


## Per point of a closed ring: the unit normal pointing away from the floor
## (the mean of its two pieces' normals).
func _ring_normals(ring: PackedVector2Array) -> PackedVector2Array:
	var n := ring.size()
	# Which side is floor: test beside the longest piece.
	var longest := 0
	for i in n:
		if ring[i].distance_to(ring[(i + 1) % n]) > ring[longest].distance_to(ring[(longest + 1) % n]):
			longest = i
	var a := ring[longest]
	var b := ring[(longest + 1) % n]
	var left := Vector2(-(b - a).normalized().y, (b - a).normalized().x)
	var sign := -1.0 if _is_floor((a + b) * 0.5 + left * 0.02) else 1.0
	var normals := PackedVector2Array()
	normals.resize(n)
	for i in n:
		var d_in := (ring[i] - ring[(i - 1 + n) % n]).normalized()
		var d_out := (ring[(i + 1) % n] - ring[i]).normalized()
		var avg := (Vector2(-d_in.y, d_in.x) + Vector2(-d_out.y, d_out.x)).normalized()
		normals[i] = avg * sign
	return normals


func _add_to_grid(a: Vector2, b: Vector2) -> void:
	var keys := {Vector2i(a.floor()): true, Vector2i(b.floor()): true}
	for key: Vector2i in keys:
		if not _segment_grid.has(key):
			_segment_grid[key] = []
		_segment_grid[key].append([a, b])


## Nearest point of the outline to `p` within about `reach` cells:
## [distance, point], or [INF, p] if none.
func _nearest_outline(p: Vector2, reach: int = 1) -> Array:
	var best := INF
	var best_point := p
	var base := Vector2i(p.floor())
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			for seg: Array in _segment_grid.get(base + Vector2i(dx, dy), []):
				var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
				var d := p.distance_to(q)
				if d < best:
					best = d
					best_point = q
	return [best, best_point]


static func _near_any(p: Vector2, points: Array[Vector2], distance: float) -> bool:
	for q in points:
		if p.distance_to(q) < distance:
			return true
	return false


# --- Geometry --------------------------------------------------------------

## Floor mesh and collider: whole cells away from the walls, FLOOR_STEP
## squares near them (in as far as FLOOR_UNDER_WALL under the wall). UV =
## the unbent grid position in metres (flagstones follow the curves).
func _build_floor(parent: Node3D) -> void:
	var body := _static_body(parent, "Floor")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var cache := {}
	var bounds := _layout.bounds().grow(1.0)
	var sub := roundi(1.0 / FLOOR_STEP)
	for y in range(floori(bounds.position.y), ceili(bounds.end.y)):
		for x in range(floori(bounds.position.x), ceili(bounds.end.x)):
			var centre := Vector2(x + 0.5, y + 0.5)
			if _nearest_outline(centre)[0] > 0.75:
				if _is_floor(centre):
					_floor_quad(st, faces, cache, Vector2(x, y), Vector2(x + 1, y + 1))
				continue
			for j in sub:
				var run_start := -1
				for i in sub + 1:
					var inside := false
					if i < sub:
						var p := Vector2(x + (i + 0.5) * FLOOR_STEP, y + (j + 0.5) * FLOOR_STEP)
						inside = _is_floor(p) or _nearest_outline(p)[0] < FLOOR_UNDER_WALL
					if inside and run_start < 0:
						run_start = i
					elif not inside and run_start >= 0:
						_floor_quad(st, faces, cache,
							Vector2(x + run_start * FLOOR_STEP, y + j * FLOOR_STEP),
							Vector2(x + i * FLOOR_STEP, y + (j + 1) * FLOOR_STEP))
						run_start = -1
	st.generate_tangents()
	_add_merged_mesh(body, st, _mats["floor"], "Mesh")
	_add_trimesh_shape(body, faces)


## One floor rectangle (cells, lo..hi), bent by the warp.
func _floor_quad(st: SurfaceTool, faces: PackedVector3Array, cache: Dictionary,
		lo: Vector2, hi: Vector2) -> void:
	var corners := [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]
	var w: Array[Vector3] = []
	for c: Vector2 in corners:
		var key := Vector2i((c / FLOOR_STEP).round())
		if not cache.has(key):
			cache[key] = _world(c)
		w.append(cache[key])
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var verts := [w[tri[0]], w[tri[1]], w[tri[2]]]
		var uvs := [corners[tri[0]] * CELL, corners[tri[1]] * CELL, corners[tri[2]] * CELL]
		_triangle(st, faces, verts, [Vector3.UP, Vector3.UP, Vector3.UP], uvs)


## Walls along the smoothed outline (outward from the floor edge) and along
## the partitions (centred on them): one mesh, one trimesh collider.
func _build_walls(parent: Node3D) -> void:
	var body := _static_body(parent, "Walls")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var t := WALL_THICKNESS / CELL  # thickness in cells
	for r in _outline.size():
		var ring := _outline[r]
		var normals := _outline_normals[r]
		var inner: Array[Vector2] = []
		var outer: Array[Vector2] = []
		for i in ring.size():
			inner.append(ring[i])
			outer.append(ring[i] + normals[i] * t)
		_wall_strip(st, faces, inner, outer, true)
	var door_points: Array[Vector2] = []
	for rect: PackedVector2Array in _layout.doors:
		door_points.append_array(rect)
	for line: PackedVector2Array in _layout.partitions:
		var d0 := (line[1] - line[0]).normalized()
		var d1 := (line[-1] - line[-2]).normalized()
		var extended := line.duplicate()
		# Ends run into the outer wall, but not into a doorway: with the warp's
		# squeeze that could narrow it below the navmesh agent's width.
		if not _near_any(line[0], door_points, 0.5):
			extended[0] = line[0] - d0 * t * 0.5
		if not _near_any(line[-1], door_points, 0.5):
			extended[-1] = line[-1] + d1 * t * 0.5
		var points := _subdivide(extended, false)
		var left: Array[Vector2] = []
		var right: Array[Vector2] = []
		for i in points.size():
			var d := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
			var n := Vector2(-d.y, d.x) * t * 0.5
			left.append(points[i] + n)
			right.append(points[i] - n)
		_wall_strip(st, faces, left, right, false)
	_add_merged_mesh(body, st, _mats["wall"], "Mesh")
	_add_trimesh_shape(body, faces)


## A WALL_HEIGHT wall between two matching point lines (cells): a face up
## each line (facing away from the other), a top, and end caps if open.
func _wall_strip(st: SurfaceTool, faces: PackedVector3Array, a_line: Array[Vector2],
		b_line: Array[Vector2], closed: bool) -> void:
	var n := a_line.size()
	var a0: Array[Vector3] = []
	var b0: Array[Vector3] = []
	for i in n:
		a0.append(_world(a_line[i]))
		b0.append(_world(b_line[i]))
	var up := Vector3.UP * WALL_HEIGHT
	var count := n if closed else n - 1
	for i in count:
		var j := (i + 1) % n
		var na_i := _flat_dir(b0[i], a0[i])
		var na_j := _flat_dir(b0[j], a0[j])
		_quad(st, faces, [a0[i], a0[j], a0[j] + up, a0[i] + up], [na_i, na_j, na_j, na_i])
		_quad(st, faces, [b0[i], b0[j], b0[j] + up, b0[i] + up], [-na_i, -na_j, -na_j, -na_i])
		_quad(st, faces, [a0[i] + up, a0[j] + up, b0[j] + up, b0[i] + up],
			[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	if not closed:
		for end in [[0, 1], [n - 1, n - 2]]:
			var e: int = end[0]
			var cap_n := _flat_dir(a0[end[1]].lerp(b0[end[1]], 0.5), a0[e].lerp(b0[e], 0.5))
			_quad(st, faces, [a0[e], b0[e], b0[e] + up, a0[e] + up], [cap_n, cap_n, cap_n, cap_n])


## Horizontal unit vector from `from` to `to`.
static func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.000001 else Vector3.FORWARD


## Two triangles a-b-c, a-c-d facing their normals.
func _quad(st: SurfaceTool, faces: PackedVector3Array, v: Array, normals: Array) -> void:
	_triangle(st, faces, [v[0], v[1], v[2]], [normals[0], normals[1], normals[2]])
	_triangle(st, faces, [v[0], v[2], v[3]], [normals[0], normals[2], normals[3]])


## Adds a triangle to the mesh and the collider faces, wound so its front
## (Godot: clockwise) faces the mean of `normals`.
func _triangle(st: SurfaceTool, faces: PackedVector3Array, v: Array, normals: Array,
		uvs: Array = []) -> void:
	var order := [0, 1, 2]
	var facing: Vector3 = normals[0] + normals[1] + normals[2]
	if (v[1] - v[0]).cross(v[2] - v[0]).dot(facing) > 0.0:
		order = [0, 2, 1]
	for k: int in order:
		st.set_normal(normals[k])
		if not uvs.is_empty():
			st.set_uv(uvs[k])
		st.add_vertex(v[k])
		faces.append(v[k])


## Door frames: posts and a lintel at DOOR_HEIGHT, with the wall closing
## over the doorway up to WALL_HEIGHT. Placed between the bent ends of the
## wall gap. All cut away like the walls.
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
		var axis := Vector2.RIGHT if horizontal else Vector2.DOWN
		var a := _world(centre - axis * half)
		var b := _world(centre + axis * half)
		var frame := Node3D.new()
		frame.name = "DoorFrame%d" % (group.get_child_count() + 1)
		frame.position = (a + b) * 0.5
		frame.rotation.y = -atan2(b.z - a.z, b.x - a.x)  # local X runs a -> b
		group.add_child(frame)
		var width := a.distance_to(b)
		var post := Vector3(0.4, DOOR_HEIGHT + 0.15, WALL_THICKNESS + 0.25)
		for side in [-1.0, 1.0]:
			_mesh(frame, BoxMesh, {"size": post}, _mats["door_wood"],
					Vector3(side * (width * 0.5 + post.x * 0.5 - 0.05), post.y * 0.5, 0))
		_mesh(frame, BoxMesh, {"size": Vector3(width + post.x * 2.0, 0.35, post.z)}, _mats["door_wood"],
				Vector3(0, DOOR_HEIGHT, 0))
		var header_height := WALL_HEIGHT - DOOR_HEIGHT - 0.175
		_mesh(frame, BoxMesh, {"size": Vector3(width + post.x * 2.0, header_height, WALL_THICKNESS)},
				_mats["wall"], Vector3(0, DOOR_HEIGHT + 0.175 + header_height * 0.5, 0))


func _build_torches(parent: Node3D) -> void:
	var group := Node3D.new()
	group.name = "Torches"
	parent.add_child(group)
	var avoid: Array[Vector2] = []
	for rect: PackedVector2Array in _layout.doors:
		avoid.append_array(rect)
	for line: PackedVector2Array in _layout.partitions:
		avoid.append_array(line)
	for r in _outline.size():
		var ring := _outline[r]
		var normals := _outline_normals[r]
		var n := ring.size()
		var travelled := TORCH_SPACING * 0.5
		for i in n:
			var a := ring[i]
			var b := ring[(i + 1) % n]
			travelled += a.distance_to(b)
			if travelled < TORCH_SPACING:
				continue
			# Only on straight-ish wall (not in tight arcs) and clear of doors.
			var bend := normals[i].angle_to(normals[(i + 2) % n])
			if absf(bend) > deg_to_rad(25.0) or _near_any(a, avoid, 1.2):
				continue
			travelled = 0.0
			var inward := -normals[i]
			var torch := _make_torch()
			torch.name = "Torch%d" % (group.get_child_count() + 1)
			torch.position = _world(a, TORCH_HEIGHT)
			var facing := _world(a + inward * 0.25) - _world(a)
			torch.rotation.y = atan2(-facing.x, -facing.z)  # local -Z faces the room
			group.add_child(torch)


func _make_torch() -> Node3D:
	var torch := Node3D.new()
	_mesh(torch, BoxMesh, {"size": Vector3(0.12, 0.12, 0.35)}, _mats["torch_metal"], Vector3(0, -0.05, -0.15))
	_mesh(torch, CylinderMesh, {"top_radius": 0.07, "bottom_radius": 0.05, "height": 0.35},
			_mats["door_wood"], Vector3(0, 0.05, -0.32))
	_mesh(torch, SphereMesh, {"radius": 0.11, "height": 0.26}, _mats["torch_flame"], Vector3(0, 0.28, -0.32))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.35, -0.6)
	light.light_color = TORCH_COLOR
	light.light_energy = 1.8
	light.omni_range = 8.0
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
		if node is Chest:
			# Its loot is rolled for the level, the same every time.
			node.level = _layout.level
			node.rng_seed = hash([_layout.seed, _layout.level, "chest", counts[kind]])
		node.name = "%s%d" % [kind.to_pascal_case(), counts[kind]]
		var at := Vector2(entry[1], entry[2])
		if PROP_RADIUS.has(kind):
			at = _clear_of_walls(at, PROP_RADIUS[kind])
		node.position = _world(at)
		# Turn with the warp so a prop keeps its angle to the wall.
		node.rotation.y = deg_to_rad(entry[3]) + _layout.warp_rotation(at)
		target.add_child(node)


## `p` (cells) moved straight away from the smoothed outline until a
## footprint of `radius` clears it: rounded corners and bulges reach further
## into a room than the grid's square walls that props and spawns were
## planned against.
func _clear_of_walls(p: Vector2, radius: float) -> Vector2:
	if not _is_floor(p):
		# Carved off by a rounded corner: step back in over the nearby wall.
		# Points nowhere near a wall are left alone.
		var nearest: Array = _nearest_outline(p, 2)
		var into: Vector2 = nearest[1] - p
		if nearest[0] > 1.0 or into.length_squared() < 0.000001:
			return p
		p = nearest[1] + into.normalized() * 0.05
	for attempt in 3:
		var nearest: Array = _nearest_outline(p, 2)
		var distance: float = nearest[0]
		if distance >= radius:
			break
		var away: Vector2 = p - nearest[1]
		if away.length_squared() < 0.000001:
			break
		p += away.normalized() * (radius - distance + 0.02)
	return p


func _build_prop(kind: String) -> StaticBody3D:
	var body: StaticBody3D = Chest.new() if kind == "chest" else StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	match kind:
		"pillar":
			# As tall as the walls, and cut away like them.
			_mesh(body, BoxMesh, {"size": Vector3(1.2, 0.3, 1.2)}, _mats["pillar_stone"], Vector3(0, 0.15, 0))
			_mesh(body, CylinderMesh, {"top_radius": 0.42, "bottom_radius": 0.48, "height": WALL_HEIGHT},
					_mats["pillar_stone"], Vector3(0, WALL_HEIGHT * 0.5, 0))
			_mesh(body, BoxMesh, {"size": Vector3(1.1, 0.25, 1.1)}, _mats["pillar_stone"], Vector3(0, WALL_HEIGHT, 0))
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
			# The lid hangs from a hinge along the back top edge (Chest opens it).
			_mesh(body, BoxMesh, {"size": Vector3(1.0, 0.5, 0.6)}, _mats["wood"], Vector3(0, 0.25, 0))
			var hinge := Node3D.new()
			hinge.name = "Lid"
			hinge.position = Vector3(0, 0.47, -0.32)
			body.add_child(hinge)
			_mesh(hinge, BoxMesh, {"size": Vector3(1.04, 0.16, 0.64)}, _mats["wood_dark"], Vector3(0, 0.08, 0.32))
			_mesh(body, BoxMesh, {"size": Vector3(0.12, 0.18, 0.05)}, _mats["gold"], Vector3(0, 0.45, 0.33))
			(body as Chest).lid_pivot = hinge
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
	# Gloomy: torches and braziers carry the light; tall walls throw deep
	# contact shadows (SSAO) and the flames bloom.
	env.ambient_light_color = Color(0.5, 0.52, 0.66)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.5
	env.glow_enabled = true
	env.glow_intensity = 0.8
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)
	# Dim cool key light so silhouettes and shapes stay readable between torches.
	var moon := DirectionalLight3D.new()
	moon.name = "FillLight"
	moon.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-55), deg_to_rad(30), 0)), Vector3(0, 10, 0))
	moon.light_color = Color(0.7, 0.75, 0.95)
	moon.light_energy = 0.32
	moon.shadow_enabled = true
	# The overview camera sits up to ~70 m from the player (IsoCameraRig).
	moon.directional_shadow_max_distance = 150.0
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
	var floor := ShaderMaterial.new()
	floor.shader = FLOOR_SHADER
	floor.set_shader_parameter("noise_texture", tex)
	_mats["floor"] = floor
	_mats["wall"] = _cutout_material(Color(0.42, 0.39, 0.37), tex)
	_mats["pillar_stone"] = _cutout_material(Color(0.52, 0.5, 0.47), tex)
	_mats["door_wood"] = _cutout_material(Color(0.3, 0.19, 0.11), tex, 0.9)
	_mats["torch_metal"] = _cutout_material(Color(0.22, 0.22, 0.24), null, 0.5, 0.7)
	var torch_flame := _cutout_material(Color(1.0, 0.6, 0.2), null)
	torch_flame.set_shader_parameter("emission_color", Color(1.0, 0.5, 0.15))
	torch_flame.set_shader_parameter("emission_energy", 4.0)
	torch_flame.set_shader_parameter("top_darkening", 1.0)
	_mats["torch_flame"] = torch_flame
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


## A wall_cutout.gdshader material: goes when the walls around it are cut.
## `tex` null = no noise.
func _cutout_material(color: Color, tex: Texture2D, roughness: float = 0.95,
		metallic: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WALL_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("use_noise", tex != null)
	if tex:
		m.set_shader_parameter("noise_texture", tex)
	m.set_shader_parameter("uv_scale", 0.2)
	m.set_shader_parameter("roughness_value", roughness)
	m.set_shader_parameter("metallic_value", metallic)
	m.set_shader_parameter("top_height", WALL_HEIGHT)
	return m


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


## One trimesh collider from triangle corner positions (both sides solid).
func _add_trimesh_shape(body: Node3D, faces: PackedVector3Array) -> void:
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


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
	if material == _mats["flame"] or material == _mats["torch_flame"]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # don't block its own light
	parent.add_child(mi)
	return mi
