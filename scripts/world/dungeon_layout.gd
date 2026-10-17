class_name DungeonLayout
extends RefCounted
## A level described on the 2 m cell grid, independent of how it was made (a
## Dungeon Scrawl map now, the seeded generator later). DungeonBuilder turns
## it into a scene.
##
## Coordinates are in cells: x -> world +X, y -> world +Z. The bounding-box
## centre of the floor is the world origin (`origin`).

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
## Generated layouts: the rooms and corridors, for later passes (props,
## enemies, the gate). Room: {rect: Rect2i, role: "start" | "path" | "exit" |
## "side", depth: steps from the start along the main path (side rooms: their
## parent's + 1), parent: room index or -1}. Corridor: {rect: Rect2i,
## from: room index, to: room index, horizontal: bool}.
var rooms: Array[Dictionary] = []
var corridors: Array[Dictionary] = []
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
## {cell: Vector2 (cell point), room: int, entry: EnemyEntry, yaw: degrees}.
var spawns: Array[Dictionary] = []


## Where corridors enter room `index`: [{cells: Array[Vector2i] (the room's
## cells against the doorway), inward: Vector2i (into the room)}].
func room_entries(index: int) -> Array[Dictionary]:
	var r: Rect2i = rooms[index]["rect"]
	var result: Array[Dictionary] = []
	for c in corridors:
		if c["from"] != index and c["to"] != index:
			continue
		var cr: Rect2i = c["rect"]
		var cells: Array[Vector2i] = []
		var inward := Vector2i.ZERO
		if c["horizontal"]:
			var x := 0
			if cr.end.x == r.position.x:
				x = r.position.x
				inward = Vector2i.RIGHT
			elif cr.position.x == r.end.x:
				x = r.end.x - 1
				inward = Vector2i.LEFT
			if inward != Vector2i.ZERO:
				for y in range(cr.position.y, cr.end.y):
					cells.append(Vector2i(x, y))
		else:
			var y := 0
			if cr.end.y == r.position.y:
				y = r.position.y
				inward = Vector2i.DOWN
			elif cr.position.y == r.end.y:
				y = r.end.y - 1
				inward = Vector2i.UP
			if inward != Vector2i.ZERO:
				for x in range(cr.position.x, cr.end.x):
					cells.append(Vector2i(x, y))
		if not cells.is_empty():
			result.append({"cells": cells, "inward": inward})
	return result


## Sets `floor_rings` to the outlines of a set of floor cells (keys:
## Vector2i, cell (x, y) covers x..x+1, y..y+1). Collinear points are merged,
## so a straight wall is one edge however many cells it spans.
func set_floor_cells(cells: Dictionary) -> void:
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


## World position of a cell point, `y` metres up.
func to_world(cell_point: Vector2, cell_size: float, y: float = 0.0) -> Vector3:
	var p := (cell_point - origin) * cell_size
	return Vector3(p.x, y, p.y)


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
