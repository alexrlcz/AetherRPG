class_name DungeonLayout
extends RefCounted
## A level described on the 2 m cell grid, independent of how it was made (a
## Dungeon Scrawl map now, the seeded generator later). DungeonBuilder turns
## it into a scene.
##
## Coordinates are in cells: x -> world +X, y -> world +Z. The bounding-box
## centre of the floor is the world origin (`origin`).
##
## Curvature: everything stays on the straight grid in cell space (rooms,
## props, spawns, walking), but to_world() bends it with a smooth seeded
## warp (`curvature` scales it; 0 = the plain grid), and DungeonBuilder
## rounds the outline's corners, so walls, corridors and rooms come out
## curved. The warp never folds (its slope is capped), so whatever is apart
## on the grid stays apart in the world.

## Pixels per grid cell in Dungeon Scrawl maps.
const GRID_PX := 36.0

## Closed polygons (cells) bounding the floor. A point is floor when it lies
## inside an odd number of them: an outer outline, holes inside it, islands
## inside holes...
var floor_rings: Array[PackedVector2Array] = []
## Open polylines (cells) of interior walls.
var partitions: Array[PackedVector2Array] = []
## Door rectangles (cells, 4 corners).
var doors: Array[PackedVector2Array] = []
## [name: String, centre: Vector2 (cells)] -> one Marker3D each.
var labels: Array = []
## [kind: String, cell x, cell y, yaw degrees] (kinds: DungeonBuilder).
var props: Array = []
## Cell point placed at the world origin.
var origin: Vector2 = Vector2.ZERO
## The rooms, for the props, enemy and gate passes (LevelGenerator for
## generated levels, RoomAnalysis for hand-made maps). Room: {rect: Rect2i
## (bounding box), cells: Array[Vector2i], role: "start" | "path" | "exit" |
## "side", depth: rooms from the start, parent: room index or -1}.
## Generated levels also list their corridors: {rect: Rect2i, from: room
## index, to: room index, horizontal: bool}.
var rooms: Array[Dictionary] = []
var corridors: Array[Dictionary] = []
## Floor cells (keys: Vector2i) and the cell edges interior walls block
## (keys: edge_key()), for walking over the grid.
var floor_cells: Dictionary = {}
var blocked_edges: Dictionary = {}
## Where a hand-made layout came from (a .ds path), "" when generated.
var source: String = ""
## The seed this layout was generated from (0 for hand-made maps).
var seed: int = 0
## The level number it was populated for (enemy budget).
var level: int = 1
## Cells kept clear of props: the walking routes between a room's doors
## (PropScatter). Keys: Vector2i.
var reserved_cells: Dictionary = {}
## Cells holding a prop with collision (PropScatter). Keys: Vector2i.
var blocked_cells: Dictionary = {}
## Enemies to spawn once the level is built (EncounterPlanner):
## {cell: Vector2 (cell point), room: int, entry: EnemyEntry, yaw: degrees},
## plus boss: true for the boss of a boss floor.
var spawns: Array[Dictionary] = []
## The boss fight of a boss floor (EncounterPlanner.place_boss()); null on
## other levels. Its arena is the room with role "boss".
var boss: BossEncounter
## 0..1: how strongly the level bends (warp and corner rounding). The shape
## of the bend comes from curvature_seed().
var curvature: float = 1.0

## Warp: per world axis, WARP_WAVES sine waves along random directions.
## Amplitude and base wavelength (cells) are picked per seed in these ranges;
## the amplitude is then capped so the warp's slope stays under
## WARP_MAX_SLOPE (narrowest squeeze of a passage: 1 - slope).
const WARP_AMPLITUDE := Vector2(0.55, 0.9)
const WARP_WAVELENGTH := Vector2(12.0, 20.0)
const WARP_MAX_SLOPE := 0.3
const _WARP_WEIGHTS := [0.55, 0.3, 0.15]
const _WARP_LENGTH_SCALES := [1.0, 0.62, 1.7]

## [[dir: Vector2, wave number: float, phase: float, weight * amplitude], ...]
## per axis, built for `_warp_key`.
var _warp_waves: Array = []
var _warp_key: Array = []


const _STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## The doorways of room `index`: its cells you can walk out of into floor
## that isn't the room, grouped into one entry per doorway:
## [{cells: Array[Vector2i] (sorted), inward: Vector2i (into the room)}].
## Works for any room shape (generated rectangles, hand-made maps).
func room_entries(index: int) -> Array[Dictionary]:
	var cells: Array = rooms[index]["cells"]
	var inside := {}
	for c: Vector2i in cells:
		inside[c] = true
	var door_cells := {}  # cell -> inward direction
	for c: Vector2i in cells:
		for d in _STEPS:
			var n: Vector2i = c + d
			if floor_cells.has(n) and not inside.has(n) and can_step(c, n):
				door_cells[c] = -d
	var result: Array[Dictionary] = []
	var seen := {}
	var keys := door_cells.keys()
	keys.sort()
	for start: Vector2i in keys:
		if seen.has(start):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		seen[start] = true
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			group.append(c)
			for d in _STEPS:
				var n: Vector2i = c + d
				if door_cells.has(n) and not seen.has(n) and door_cells[n] == door_cells[start]:
					seen[n] = true
					queue.append(n)
		group.sort()
		result.append({"cells": group, "inward": door_cells[start]})
	return result


## The room cell nearest the room's centroid.
func room_centre(index: int) -> Vector2i:
	var cells: Array = rooms[index]["cells"]
	var sum := Vector2.ZERO
	for c: Vector2i in cells:
		sum += Vector2(c)
	var mean := sum / cells.size()
	var best: Vector2i = cells[0]
	for c: Vector2i in cells:
		if Vector2(c).distance_squared_to(mean) < Vector2(best).distance_squared_to(mean):
			best = c
	return best


## Key of the edge between two 4-adjacent cells (order doesn't matter).
static func edge_key(a: Vector2i, b: Vector2i) -> Array:
	return [a, b] if a < b else [b, a]


func block_edge(a: Vector2i, b: Vector2i) -> void:
	blocked_edges[edge_key(a, b)] = true


## True when you can walk from cell `a` to the 4-adjacent floor cell `b`.
func can_step(a: Vector2i, b: Vector2i) -> bool:
	return floor_cells.has(b) and not blocked_edges.has(edge_key(a, b))


## Steps from `from` to every floor cell it can reach: {cell: steps}.
func walk_distances(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in _STEPS:
			var n: Vector2i = c + d
			if not dist.has(n) and can_step(c, n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


## Sets `floor_rings` to the outlines of a set of floor cells (keys:
## Vector2i, cell (x, y) covers x..x+1, y..y+1). Collinear points are merged,
## so a straight wall is one edge however many cells it spans.
func set_floor_cells(cells: Dictionary) -> void:
	floor_cells = cells.duplicate()
	floor_rings.clear()
	# Directed unit edges around every floor cell's empty sides, clockwise
	# (y down), keyed by their start vertex.
	var edges := {}
	for c: Vector2i in cells:
		if not cells.has(c + Vector2i.UP):
			_add_edge(edges, c, c + Vector2i.RIGHT)
		if not cells.has(c + Vector2i.RIGHT):
			_add_edge(edges, c + Vector2i.RIGHT, c + Vector2i.ONE)
		if not cells.has(c + Vector2i.DOWN):
			_add_edge(edges, c + Vector2i.ONE, c + Vector2i.DOWN)
		if not cells.has(c + Vector2i.LEFT):
			_add_edge(edges, c + Vector2i.DOWN, c)
	# Walk them into closed loops. Where two loops touch at a corner a vertex
	# has two exits; any choice gives the same even-odd floor.
	var starts := edges.keys()
	starts.sort()  # Deterministic ring order.
	for s: Vector2i in starts:
		while not edges[s].is_empty():
			var ring: Array[Vector2i] = [s]
			var at: Vector2i = edges[s].pop_back()
			while at != s:
				ring.append(at)
				at = edges[at].pop_back()
			floor_rings.append(_simplify(ring))


static func _add_edge(edges: Dictionary, from: Vector2i, to: Vector2i) -> void:
	if not edges.has(from):
		edges[from] = []
	edges[from].append(to)


## Drops points in the middle of straight runs.
static func _simplify(ring: Array[Vector2i]) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ring.size()
	for i in n:
		var prev := ring[(i - 1 + n) % n]
		var next := ring[(i + 1) % n]
		var d1 := ring[i] - prev
		var d2 := next - ring[i]
		if d1.x * d2.y - d1.y * d2.x != 0:  # A corner.
			out.append(Vector2(ring[i]))
	return out


## True when the cell point lies on the floor (even-odd over `floor_rings`).
func is_floor(cell_point: Vector2) -> bool:
	var inside := false
	for ring in floor_rings:
		if Geometry2D.is_point_in_polygon(cell_point, ring):
			inside = not inside
	return inside


## World position of a cell point, `y` metres up (bent by the warp).
func to_world(cell_point: Vector2, cell_size: float, y: float = 0.0) -> Vector3:
	var p := (warp(cell_point) - origin) * cell_size
	return Vector3(p.x, y, p.y)


## Where the warp moves a cell point (cells). The identity at curvature 0.
func warp(cell_point: Vector2) -> Vector2:
	if curvature <= 0.0:
		return cell_point
	_ensure_warp()
	var offset := Vector2.ZERO
	for axis in 2:
		for wave: Array in _warp_waves[axis]:
			var dir: Vector2 = wave[0]
			offset[axis] += wave[3] * sin(dir.dot(cell_point) * wave[1] + wave[2])
	return cell_point + offset


## How far (radians, world yaw) the warp turns things at a cell point:
## props keep their angle to the walls.
func warp_rotation(cell_point: Vector2) -> float:
	var along := warp(cell_point + Vector2(0.25, 0.0)) - warp(cell_point - Vector2(0.25, 0.0))
	return -along.angle()


## Seed for the shape of the bend (and the builder's corner radii): the level
## seed, else the source map's path, else the outline.
func curvature_seed() -> int:
	if seed != 0:
		return hash([seed, "curvature"])
	if source != "":
		return hash([source, "curvature"])
	return hash([floor_rings, "curvature"])


func _ensure_warp() -> void:
	var key := [curvature_seed(), curvature]
	if key == _warp_key:
		return
	_warp_key = key
	var rng := RandomNumberGenerator.new()
	rng.seed = key[0]
	var base_length := rng.randf_range(WARP_WAVELENGTH.x, WARP_WAVELENGTH.y)
	var amplitude := rng.randf_range(WARP_AMPLITUDE.x, WARP_AMPLITUDE.y) * curvature
	# Slope of one axis' displacement <= amplitude * sum(weight * TAU / length).
	var slope_per_amplitude := 0.0
	for i in _WARP_WEIGHTS.size():
		slope_per_amplitude += _WARP_WEIGHTS[i] * TAU / (base_length * _WARP_LENGTH_SCALES[i])
	# The warp's Jacobian is I + D with D's two rows each at most that long,
	# so |D| <= sqrt(2) * that: under 1 nothing folds.
	amplitude = minf(amplitude, WARP_MAX_SLOPE / sqrt(2.0) / slope_per_amplitude)
	_warp_waves = []
	for axis in 2:
		var waves := []
		for i in _WARP_WEIGHTS.size():
			waves.append([Vector2.from_angle(rng.randf() * TAU),
				TAU / (base_length * _WARP_LENGTH_SCALES[i]), rng.randf() * TAU,
				_WARP_WEIGHTS[i] * amplitude])
		_warp_waves.append(waves)


## Bounding box of all floor rings, in cells.
func bounds() -> Rect2:
	var rect := Rect2(floor_rings[0][0], Vector2.ZERO)
	for ring in floor_rings:
		for p in ring:
			rect = rect.expand(p)
	return rect


## Puts the floor's bounding-box centre at the world origin.
func centre_origin() -> void:
	origin = bounds().get_center()


## Reads a Dungeon Scrawl map (.ds: a zip whose "map" entry is JSON): the
## template's dungeon shape (floor rings and partition polylines), door
## assets and text labels. Returns null (and reports why) on failure.
static func from_dungeon_scrawl(path: String) -> DungeonLayout:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(path)) != OK:
		push_error("DungeonLayout: cannot open %s" % path)
		return null
	var data: Variant = JSON.parse_string(zip.read_file("map").get_string_from_utf8())
	zip.close()
	if not data is Dictionary:
		push_error("DungeonLayout: %s has no readable map" % path)
		return null
	var nodes: Dictionary = data["state"]["document"]["nodes"]
	var geometry: Dictionary = data["data"]["geometry"]

	var layout := DungeonLayout.new()
	for node: Dictionary in nodes.values():
		match node["type"]:
			"TEMPLATE":
				# The dungeon shape is the template's GEOMETRY child.
				var shape: Dictionary = nodes[node["template"]["dungeonShape"]]
				var geo: Dictionary = geometry[shape["geometryId"]]
				for ring: Array in geo["polygons"][0]:
					layout.floor_rings.append(_to_cells(ring))
				for line: Array in geo["polylines"]:
					layout.partitions.append(_to_cells(line))
			"DUNGEON_ASSET":
				if node["kind"] == "door":
					var door_geo: Dictionary = nodes[node["children"][0]]
					layout.doors.append(_to_cells(geometry[door_geo["geometryId"]]["polygons"][0][0]))
			"TEXT":
				var t: Array = node["transform"]
				var size: float = node["style"]["fontSize"] * t[0]
				var text: String = node["content"]
				# Approximate the label's visual centre from its top-left.
				var centre := Vector2(t[4] + text.length() * size * 0.25, t[5] + size * 0.6)
				layout.labels.append([text, centre / GRID_PX])
	if layout.floor_rings.is_empty():
		push_error("DungeonLayout: no dungeon shape in %s" % path)
		return null
	# The outline's centre (the first ring is the template's outer boundary).
	var rect := Rect2(layout.floor_rings[0][0], Vector2.ZERO)
	for p in layout.floor_rings[0]:
		rect = rect.expand(p)
	layout.origin = rect.get_center()
	return layout


static func _to_cells(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points:
		out.append(Vector2(p[0], p[1]) / GRID_PX)
	return out
