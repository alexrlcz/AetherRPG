class_name RoomAnalysis
extends RefCounted
## Finds the rooms of a hand-made layout (a Dungeon Scrawl map) so the same
## population rules as generated levels can run on it (step 5 of procedural
## levels). Fills `layout.floor_cells`, `layout.blocked_edges` and
## `layout.rooms`, picks the start and exit rooms, and adds an "Exit" label
## when the map has none.
##
## Rooms: a floor cell is a room *core* when its 3x3 block is all floor, no
## partition wall touches it, and it is part of a 2x2 block of such cells, so
## passages up to 3 cells wide and door gaps are never core (a 3-wide
## corridor only has a 1-cell line of 3x3 centres). Connected cores of at
## least `min_core_cells` are rooms; each room then
## takes back the cells around its core (within `claim_radius` cells, reached
## by walking without crossing a wall). What is left is corridor.
## Roles: the start room holds the "start" label; the exit room holds an
## "exit" label, else it is the room furthest (walking) from the start. Rooms
## on the shortest room-to-room route between them are "path", the rest
## "side"; depth = rooms from the start.

## Smaller core blobs count as corridor.
var min_core_cells: int = 4
## How far (cells, any direction) a room reaches out from its core.
var claim_radius: int = 2

const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## Returns false (and reports why) when the map can't be used as a level.
func analyze(layout: DungeonLayout) -> bool:
	_find_floor(layout)
	_block_partitions(layout)
	var start_label: Variant = _label_point(layout, "start")
	if start_label == null:
		push_error("RoomAnalysis: the map has no 'start' label")
		return false
	var rooms := _find_rooms(layout)
	if rooms.is_empty():
		push_error("RoomAnalysis: no rooms found")
		return false
	layout.rooms.clear()
	for cells in rooms:
		var rect := Rect2i(cells[0], Vector2i.ONE)
		for c: Vector2i in cells:
			rect = rect.expand(c).expand(c + Vector2i.ONE)
		layout.rooms.append({"rect": rect, "cells": cells, "role": "path", "depth": 0, "parent": -1})
	_assign_roles(layout, start_label)
	return true


## Cells whose centre lies on the floor.
func _find_floor(layout: DungeonLayout) -> void:
	layout.floor_cells.clear()
	var b := layout.bounds()
	for y in range(floori(b.position.y), ceili(b.end.y)):
		for x in range(floori(b.position.x), ceili(b.end.x)):
			if layout.is_floor(Vector2(x + 0.5, y + 0.5)):
				layout.floor_cells[Vector2i(x, y)] = true


## Partition walls run along cell edges: crossing them is blocked.
func _block_partitions(layout: DungeonLayout) -> void:
	layout.blocked_edges.clear()
	for line in layout.partitions:
		for i in line.size() - 1:
			var a := Vector2i(roundi(line[i].x), roundi(line[i].y))
			var b := Vector2i(roundi(line[i + 1].x), roundi(line[i + 1].y))
			var d := (b - a).sign()
			var p := a
			while p != b:
				if d.x == 0:  # Vertical wall at x = p.x: between (x-1, y) and (x, y).
					var y := mini(p.y, p.y + d.y)
					layout.block_edge(Vector2i(p.x - 1, y), Vector2i(p.x, y))
				else:  # Horizontal wall at y = p.y: between (x, y-1) and (x, y).
					var x := mini(p.x, p.x + d.x)
					layout.block_edge(Vector2i(x, p.y - 1), Vector2i(x, p.y))
				p += d


func _find_rooms(layout: DungeonLayout) -> Array[Array]:
	var centres := {}
	for c: Vector2i in layout.floor_cells:
		if _is_core(layout, c):
			centres[c] = true
	# Only thick parts: a 1-cell line of centres is a corridor, not a room.
	var core := {}
	for c: Vector2i in centres:
		for corner in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
			var o: Vector2i = c + corner
			if centres.has(o) and centres.has(o + Vector2i.RIGHT) and centres.has(o + Vector2i.DOWN) 					and centres.has(o + Vector2i.ONE):
				core[c] = true
				break
	# Connected cores.
	var owner := {}  # cell -> room index
	var rooms: Array[Array] = []
	var keys := core.keys()
	keys.sort()  # Deterministic room order.
	for seed_cell: Vector2i in keys:
		if owner.has(seed_cell):
			continue
		var blob: Array[Vector2i] = [seed_cell]
		var queue: Array[Vector2i] = [seed_cell]
		owner[seed_cell] = -2
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in STEPS:
				var n: Vector2i = c + d
				if core.has(n) and not owner.has(n) and layout.can_step(c, n):
					owner[n] = -2
					blob.append(n)
					queue.append(n)
		if blob.size() < min_core_cells:
			for c in blob:
				owner.erase(c)
			continue
		for c in blob:
			owner[c] = rooms.size()
		rooms.append(blob)
	# Each room takes back the edge cells around its core. Only core cells
	# claim (a copy of the owners before growing), or rooms would spread
	# down the corridors one claimed cell at a time.
	var core_owner := owner.duplicate()
	for i in rooms.size():
		var added: Array[Vector2i] = []
		var queue: Array[Vector2i] = rooms[i].duplicate()
		var seen := {}
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in STEPS:
				var n: Vector2i = c + d
				if seen.has(n) or owner.has(n) or not layout.floor_cells.has(n) or not layout.can_step(c, n):
					continue
				seen[n] = true
				if _near_core(n, core_owner, i):
					owner[n] = i
					added.append(n)
					queue.append(n)
		rooms[i].append_array(added)
	for cells in rooms:
		cells.sort()
	return rooms


## 3x3 block all floor, and no blocked edge inside or around it.
func _is_core(layout: DungeonLayout, c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if not layout.floor_cells.has(n):
				return false
			for d in STEPS:
				if layout.blocked_edges.has(DungeonLayout.edge_key(n, n + d)):
					return false
	return true


## True when a core cell of `room` is within `claim_radius` of `c`.
func _near_core(c: Vector2i, core_owner: Dictionary, room: int) -> bool:
	for dy in range(-claim_radius, claim_radius + 1):
		for dx in range(-claim_radius, claim_radius + 1):
			if (dx != 0 or dy != 0) and core_owner.get(c + Vector2i(dx, dy), -1) == room:
				return true
	return false


func _assign_roles(layout: DungeonLayout, start_label: Vector2) -> void:
	var start_room := _room_near(layout, start_label)
	# Walking distance (cells) from the start label over the whole floor.
	var start_cell := Vector2i(floori(start_label.x), floori(start_label.y))
	var dist := layout.walk_distances(start_cell)
	var exit_room := -1
	var exit_label: Variant = _label_point(layout, "exit")
	if exit_label != null:
		exit_room = _room_near(layout, exit_label)
	else:
		var best := -1
		for i in layout.rooms.size():
			if i == start_room:
				continue
			var far := 0
			for c: Vector2i in layout.rooms[i]["cells"]:
				far = maxi(far, dist.get(c, 0))
			if far > best:
				best = far
				exit_room = i
		if exit_room < 0:
			exit_room = start_room
		layout.labels.append(["Exit", Vector2(layout.room_centre(exit_room)) + Vector2(0.5, 0.5)])
	# Room graph: rooms touching through corridors / doorways.
	var links := _room_links(layout)
	var depth := {start_room: 0}
	var parent := {start_room: -1}
	var queue := [start_room]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		for n: int in links[r]:
			if not depth.has(n):
				depth[n] = depth[r] + 1
				parent[n] = r
				queue.append(n)
	var on_route := {}
	var at := exit_room
	while at != -1 and parent.has(at):
		on_route[at] = true
		at = parent[at]
	for i in layout.rooms.size():
		var room: Dictionary = layout.rooms[i]
		room["depth"] = depth.get(i, 0)
		room["parent"] = parent.get(i, -1)
		room["role"] = "path" if on_route.has(i) else "side"
	layout.rooms[start_room]["role"] = "start"
	if exit_room != start_room:
		layout.rooms[exit_room]["role"] = "exit"


## Which rooms reach which, walking only through non-room floor between them.
func _room_links(layout: DungeonLayout) -> Array[Dictionary]:
	var owner := {}
	for i in layout.rooms.size():
		for c: Vector2i in layout.rooms[i]["cells"]:
			owner[c] = i
	var links: Array[Dictionary] = []
	for i in layout.rooms.size():
		var found := {}
		var seen := {}
		var queue: Array[Vector2i] = []
		for c: Vector2i in layout.rooms[i]["cells"]:
			seen[c] = true
			queue.append(c)
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in STEPS:
				var n: Vector2i = c + d
				if seen.has(n) or not layout.floor_cells.has(n) or not layout.can_step(c, n):
					continue
				seen[n] = true
				var o: int = owner.get(n, -1)
				if o == -1:
					queue.append(n)  # Corridor: keep walking.
				elif o != i:
					found[o] = true  # Another room: a link, stop there.
		links.append(found)
	return links


func _room_near(layout: DungeonLayout, point: Vector2) -> int:
	var best := 0
	var best_d := INF
	for i in layout.rooms.size():
		for c: Vector2i in layout.rooms[i]["cells"]:
			var d := (Vector2(c) + Vector2(0.5, 0.5)).distance_squared_to(point)
			if d < best_d:
				best_d = d
				best = i
	return best


static func _label_point(layout: DungeonLayout, label_name: String) -> Variant:
	for label in layout.labels:
		if (label[0] as String).strip_edges().to_lower() == label_name:
			return label[1]
	return null
