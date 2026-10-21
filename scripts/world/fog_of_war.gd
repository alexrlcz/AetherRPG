class_name FogOfWar
extends Node
## Fog of war over a DungeonLayout's cells. Every place is unexplored (drawn
## pitch black: not even the layout shows), explored (seen before: layout
## and props drawn dim and unlit, no enemies) or in sight now (lit as
## normal), with soft transitions between them.
##
## In sight = whatever the player has line of sight to (walls block it; it
## passes doorways, so the player sees a cone into a room through its door
## and straight down a corridor) within a circle of `sight_fade` cells around
## the player: fully lit up to `sight_radius`, fading out smoothly between
## the two (per pixel, from the player's exact position). Rooms are not lit
## as a whole: a big room shows only as far as the circle reaches. What has
## been in sight stays explored for the rest of the level, with the same
## soft edges. Enemies (children of `enemies`) are shown only while in line
## of sight within `enemy_sight`.
##
## Drawing: `mask` is an image in cell space, TEXELS_PER_CELL per cell:
## R = explored (per texel, 0..1), G = in line of sight (per cell). Texels just outside the floor (where the outer
## walls stand) take the brightest state of the floor cells next to them,
## so a lit room's walls are lit; interior walls lie on cell edges, so each
## face takes its own side's state. A quad in front of the camera runs
## shaders/fog_of_war.gdshader, which turns each pixel's world position
## back into a cell point, computes the falloff from the player (`viewer`)
## and darkens the pixel.
##
## Main calls setup() for every level. `enabled` (debug menu) turns all of
## it off: no darkening, every enemy shown.

signal updated

const SHADER := preload("res://shaders/fog_of_war.gdshader")
const TEXELS_PER_CELL := 4
## Most warp waves the shader takes (per axis: half of it).
const MAX_WAVES := 8
## No cell yet (the player hasn't stood on the floor).
const NO_CELL := Vector2i(-1000000, -1000000)
## Points (cell fractions) a line of sight may reach for a cell to count as
## seen: the centre and four points near the corners.
const SIGHT_SAMPLES: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.15, 0.15), Vector2(0.85, 0.15),
	Vector2(0.15, 0.85), Vector2(0.85, 0.85)]

@export var enabled: bool = true:
	set(value):
		enabled = value
		_apply_enabled()
@export var player: Node3D
## Its children are the enemies to hide.
@export var enemies: Node
## World metres per cell (DungeonBuilder.CELL).
@export var cell_size: float = 2.0
## Cells around the player that are fully lit (line of sight permitting):
## 3.5 cells = 7 m.
@export var sight_radius: float = 3.5
## Where the light has faded out completely (cells): 5 = 10 m.
@export var sight_fade: float = 5.0
## Rock outside the map (DungeonBuilder's cave fill) this many cells past
## the floor is explored (drawn dim) as far as the light reached the floor
## next to it, so the cave shows as dark shapes around explored places.
@export var rock_reach: int = 2
## Enemies in line of sight are shown within this many cells.
@export var enemy_sight: float = 4.5
## How far (cells) past the floor's edge the outer walls take its state.
@export var wall_reach: float = 0.8
## The sight is recomputed when the player has moved this far (cells).
@export var refresh_distance: float = 0.25
## Seconds between enemy visibility checks.
@export var enemy_check_interval: float = 0.1

var layout: DungeonLayout
## Cells (Vector2i keys) explored at least partly (their centre seen).
var explored: Dictionary = {}
## Cells (Vector2i keys) in line of sight within `sight_fade` now.
var visible_cells: Dictionary = {}
## The cell-space mask the shader reads.
var mask: Image

var _data: PackedByteArray
var _texture: ImageTexture
var _material: ShaderMaterial
var _quad: MeshInstance3D
## Cells in line of sight within `sight_fade` (keys).
var _sight_cells: Dictionary = {}
## Cell at the mask's (0, 0) texel block.
var _mask_cell_origin: Vector2i
## Floor cell -> PackedInt32Array of outside texels it lights.
var _outer_texels: Dictionary = {}
## Outside texel -> Array of the floor cells that light it.
var _texel_cells: Dictionary = {}
## Floor cell -> the non-floor cells within `rock_reach` of it (cave rock).
var _rock_cells: Dictionary = {}
var _player_cell: Vector2i = NO_CELL
## The player's cell point when the sight was last computed.
var _viewer: Vector2 = Vector2(-1000000, -1000000)
var _enemy_wait: float = 0.0


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = Material.RENDER_PRIORITY_MIN
	_quad = MeshInstance3D.new()
	_quad.name = "FogOfWarQuad"
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	_quad.mesh = quad_mesh
	_quad.material_override = _material
	_quad.extra_cull_margin = 16384.0  # Never frustum-culled: it covers the screen.
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_enabled()


## Starts the fog for a new level: nothing explored yet.
func setup(new_layout: DungeonLayout) -> void:
	layout = new_layout
	explored.clear()
	visible_cells.clear()
	_sight_cells.clear()
	_outer_texels.clear()
	_texel_cells.clear()
	_rock_cells.clear()
	_player_cell = NO_CELL
	_viewer = Vector2(-1000000, -1000000)
	if layout == null or layout.floor_cells.is_empty():
		mask = null
		_apply_enabled()
		return
	_build_mask()
	_set_shader_layout()
	_apply_enabled()
	refresh()


## Recomputes what the player sees now (also done automatically as the
## player moves).
func refresh() -> void:
	if layout == null or mask == null or player == null:
		return
	var point := layout.to_cell(player.global_position, cell_size)
	var cell := Vector2i(floori(point.x), floori(point.y))
	if not layout.floor_cells.has(cell):
		if not layout.floor_cells.has(_player_cell):
			return  # Off the floor and never on it yet: nothing to see from.
		cell = _player_cell
		point = _viewer
	_player_cell = cell
	_viewer = point
	_material.set_shader_parameter("viewer", point)
	_update_sight()
	_update_enemies()


## The floor cell (or wall cell) under a world position.
func cell_at(world: Vector3) -> Vector2i:
	var point := layout.to_cell(world, cell_size)
	return Vector2i(floori(point.x), floori(point.y))


func is_visible_at(world: Vector3) -> bool:
	return visible_cells.has(cell_at(world))


func is_explored_at(world: Vector3) -> bool:
	return explored.has(cell_at(world))


## An enemy standing at `world` is shown: in line of sight within
## `enemy_sight` cells.
func is_enemy_visible_at(world: Vector3) -> bool:
	var point := layout.to_cell(world, cell_size)
	var cell := Vector2i(floori(point.x), floori(point.y))
	return _sight_cells.has(cell) and point.distance_to(_viewer) <= enemy_sight


## How lit (0..1) a cell point is now: the distance falloff where the cell
## is in line of sight.
func light_at(cell_point: Vector2) -> float:
	var cell := Vector2i(floori(cell_point.x), floori(cell_point.y))
	if not _sight_cells.has(cell):
		return 0.0
	return _falloff(cell_point.distance_to(_viewer))


func _process(delta: float) -> void:
	if layout == null or mask == null or player == null:
		return
	_attach_quad()
	var point := layout.to_cell(player.global_position, cell_size)
	var cell := Vector2i(floori(point.x), floori(point.y))
	if layout.floor_cells.has(cell):
		_material.set_shader_parameter("viewer", point)
		if cell != _player_cell or point.distance_to(_viewer) >= refresh_distance:
			_player_cell = cell
			_viewer = point
			_update_sight()
	_enemy_wait -= delta
	if _enemy_wait <= 0.0:
		_enemy_wait = enemy_check_interval
		_update_enemies()


func _falloff(distance: float) -> float:
	return 1.0 - smoothstep(sight_radius, sight_fade, distance)


## Recomputes the line-of-sight cells from `_viewer`, writes the changes
## into the mask and marks what is lit as explored.
func _update_sight() -> void:
	var sight := {}
	var reach := ceili(sight_fade)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := _player_cell + Vector2i(dx, dy)
			if not layout.floor_cells.has(cell):
				continue
			var centre := Vector2(cell) + Vector2(0.5, 0.5)
			if centre.distance_to(_viewer) > sight_fade + 0.75:
				continue
			for sample: Vector2 in SIGHT_SAMPLES:
				if _line_of_sight(_viewer, Vector2(cell) + sample):
					sight[cell] = true
					break
	var changed := {}
	for cell: Vector2i in _sight_cells:
		if not sight.has(cell):
			changed[cell] = true
	for cell: Vector2i in sight:
		if not _sight_cells.has(cell):
			changed[cell] = true
	_sight_cells = sight
	visible_cells = sight
	var outer := {}
	for cell: Vector2i in changed:
		_write_cell_flags(cell)
		for texel: int in _outer_texels.get(cell, PackedInt32Array()):
			outer[texel] = true
	# Explored: every texel keeps the brightest light it has had.
	for cell: Vector2i in visible_cells:
		_explore_cell(cell)
		for texel: int in _outer_texels.get(cell, PackedInt32Array()):
			outer[texel] = true
	for texel: int in outer:
		_write_outer(texel)
	var rocks := {}
	for cell: Vector2i in visible_cells:
		for rock: Vector2i in _rock_cells.get(cell, []):
			rocks[rock] = true
	for rock: Vector2i in rocks:
		_explore_rock(rock)
	mask.set_data(mask.get_width(), mask.get_height(), false, Image.FORMAT_RGBA8, _data)
	_texture.update(mask)
	updated.emit()


## True when the straight line from `from` to `to` (cell points) crosses
## only floor cells and no walls (cell-by-cell walk along the line).
func _line_of_sight(from: Vector2, to: Vector2) -> bool:
	var cell := Vector2i(floori(from.x), floori(from.y))
	var end := Vector2i(floori(to.x), floori(to.y))
	var direction := to - from
	var step := Vector2i(int(signf(direction.x)), int(signf(direction.y)))
	var t_delta := Vector2(absf(1.0 / direction.x) if direction.x != 0.0 else INF,
		absf(1.0 / direction.y) if direction.y != 0.0 else INF)
	var t_max := Vector2(
		((cell.x + (1 if step.x > 0 else 0)) - from.x) / direction.x if direction.x != 0.0 else INF,
		((cell.y + (1 if step.y > 0 else 0)) - from.y) / direction.y if direction.y != 0.0 else INF)
	for i in 64:
		if cell == end:
			return true
		var next := cell
		if t_max.x < t_max.y:
			next.x += step.x
			t_max.x += t_delta.x
		else:
			next.y += step.y
			t_max.y += t_delta.y
		if not layout.floor_cells.has(next) or not layout.can_step(cell, next):
			return false
		cell = next
	return false


func _update_enemies() -> void:
	if enemies == null:
		return
	for enemy in enemies.get_children():
		var body := enemy as Node3D
		if body == null:
			continue
		if not enabled or layout == null or mask == null:
			body.visible = true
			continue
		body.visible = is_enemy_visible_at(body.global_position)


func _texel_index(cell: Vector2i, tx: int, ty: int) -> int:
	var base := (cell - _mask_cell_origin) * TEXELS_PER_CELL
	return (base.y + ty) * mask.get_width() + base.x + tx


## Writes the cell's line-of-sight flag (G) into its texels.
func _write_cell_flags(cell: Vector2i) -> void:
	var g := 255 if _sight_cells.has(cell) else 0
	for ty in TEXELS_PER_CELL:
		for tx in TEXELS_PER_CELL:
			_data[_texel_index(cell, tx, ty) * 4 + 1] = g


## Raises the cell's explored values (R) to the light they get now.
func _explore_cell(cell: Vector2i) -> void:
	var seen := false
	for ty in TEXELS_PER_CELL:
		for tx in TEXELS_PER_CELL:
			var point := Vector2(cell) + (Vector2(tx, ty) + Vector2(0.5, 0.5)) / TEXELS_PER_CELL
			var value := roundi(light_at(point) * 255.0)
			var i := _texel_index(cell, tx, ty) * 4
			if value > _data[i]:
				_data[i] = value
			seen = seen or _data[i] > 76
	if seen:
		explored[cell] = true


## A cave rock cell: explored (R only) as far as the light reaches it.
func _explore_rock(cell: Vector2i) -> void:
	for ty in TEXELS_PER_CELL:
		for tx in TEXELS_PER_CELL:
			var point := Vector2(cell) + (Vector2(tx, ty) + Vector2(0.5, 0.5)) / TEXELS_PER_CELL
			var value := roundi(_falloff(point.distance_to(_viewer)) * 255.0)
			var i := _texel_index(cell, tx, ty) * 4
			if value > _data[i]:
				_data[i] = value


## An outside texel: in sight when a cell that lights it is, and explored
## as far as its own position has been lit.
func _write_outer(texel: int) -> void:
	var g := 0
	var cells: Array = _texel_cells[texel]
	for cell: Vector2i in cells:
		if _sight_cells.has(cell):
			g = 255
			break
	var width := mask.get_width()
	var point := Vector2(_mask_cell_origin) + (Vector2(texel % width, texel / width) + Vector2(0.5, 0.5)) / TEXELS_PER_CELL
	var light := _falloff(point.distance_to(_viewer)) if g > 0 else 0.0
	var i := texel * 4
	_data[i] = maxi(_data[i], roundi(light * 255.0))
	_data[i + 1] = g


## Allocates the mask (all unexplored) and works out which outside texels
## each floor cell lights.
func _build_mask() -> void:
	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	for cell: Vector2i in layout.floor_cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var margin := maxi(ceili(wall_reach), rock_reach) + 1
	_mask_cell_origin = low - Vector2i.ONE * margin
	var cells := high - low + Vector2i.ONE * (1 + margin * 2)
	mask = Image.create(cells.x * TEXELS_PER_CELL, cells.y * TEXELS_PER_CELL, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 1))
	_data = mask.get_data()
	var reach := ceili(wall_reach)
	for cell: Vector2i in layout.floor_cells:
		var lit := PackedInt32Array()
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var outside := cell + Vector2i(dx, dy)
				if layout.floor_cells.has(outside):
					continue
				for ty in TEXELS_PER_CELL:
					for tx in TEXELS_PER_CELL:
						# Texel centre in cells, and its distance to the floor cell.
						var centre := Vector2(outside) + (Vector2(tx, ty) + Vector2(0.5, 0.5)) / TEXELS_PER_CELL
						var nearest := centre.clamp(Vector2(cell), Vector2(cell) + Vector2.ONE)
						if centre.distance_to(nearest) > wall_reach:
							continue
						var texel := _texel_index(outside, tx, ty)
						lit.append(texel)
						if not _texel_cells.has(texel):
							_texel_cells[texel] = []
						_texel_cells[texel].append(cell)
		_outer_texels[cell] = lit
		var rock: Array[Vector2i] = []
		for dy in range(-rock_reach, rock_reach + 1):
			for dx in range(-rock_reach, rock_reach + 1):
				var outside := cell + Vector2i(dx, dy)
				if not layout.floor_cells.has(outside):
					rock.append(outside)
		_rock_cells[cell] = rock
	if _texture == null:
		_texture = ImageTexture.create_from_image(mask)
	else:
		_texture.set_image(mask)


func _set_shader_layout() -> void:
	_material.set_shader_parameter("fog_mask", _texture)
	_material.set_shader_parameter("mask_origin", Vector2(_mask_cell_origin))
	_material.set_shader_parameter("mask_size", Vector2(mask.get_size()) / TEXELS_PER_CELL)
	_material.set_shader_parameter("layout_origin", layout.origin)
	_material.set_shader_parameter("cell_size", cell_size)
	_material.set_shader_parameter("sight_radius", sight_radius)
	_material.set_shader_parameter("sight_fade", sight_fade)
	var waves := layout.warp_waves()
	var per_axis := mini(waves[0].size(), MAX_WAVES / 2) if not waves.is_empty() else 0
	var packed: Array[Vector4] = []
	var amplitudes := PackedFloat32Array()
	packed.resize(MAX_WAVES)
	amplitudes.resize(MAX_WAVES)
	for axis in 2:
		for i in per_axis:
			var wave: Array = waves[axis][i]
			var dir: Vector2 = wave[0]
			packed[axis * per_axis + i] = Vector4(dir.x, dir.y, wave[1], wave[2])
			amplitudes[axis * per_axis + i] = wave[3]
	_material.set_shader_parameter("waves_per_axis", per_axis)
	_material.set_shader_parameter("waves", packed)
	_material.set_shader_parameter("amplitudes", amplitudes)


## Keeps the quad on the active camera.
func _attach_quad() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _quad.get_parent() == camera:
		return
	if _quad.get_parent():
		_quad.get_parent().remove_child(_quad)
	camera.add_child(_quad)


func _apply_enabled() -> void:
	if _quad == null:
		return
	_quad.visible = enabled and mask != null
	if is_inside_tree():
		_update_enemies()


func _exit_tree() -> void:
	if _quad and _quad.get_parent():
		_quad.get_parent().remove_child(_quad)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _quad and not _quad.is_inside_tree():
		_quad.free()
