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
