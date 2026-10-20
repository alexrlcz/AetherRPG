class_name LootSpawner
## Throws a rolled drop (LootTable.roll()) into the world as Pickups popping
## out from a point: currency as coins of up to `coin_value` each (at most
## `max_coins` per line), anything else as one pickup per line. Throws go out
## in a ring, or in a fan around `direction`; a throw that would cross a wall
## (`wall_mask`) is shortened to land 0.4 m in front of it.

const COIN_VALUE := 5
const MAX_COINS := 8
## Horizontal and upward launch speed ranges (m/s).
const OUT_SPEED := Vector2(1.2, 2.4)
const UP_SPEED := Vector2(3.5, 5.0)


## Spawns `drop` from `from` (world), landing at height `floor_y`, as
## children of `container` (a node in the tree). `direction` ZERO = all
## round, else a fan of +-`spread` radians around it. Returns the pickups.
static func spawn(drop: Array, from: Vector3, floor_y: float, container: Node,
		rng: RandomNumberGenerator, direction: Vector3 = Vector3.ZERO, spread: float = PI,
		wall_mask: int = 1) -> Array[Pickup]:
	var pieces := []  # [item, amount] per pickup
	for line: Array in drop:
		var item: ItemDefinition = line[0]
		var amount: int = line[1]
		if item.kind == ItemDefinition.Kind.CURRENCY:
			var coins := clampi(ceili(float(amount) / COIN_VALUE), 1, MAX_COINS)
			for i in coins:
				# Spread the total evenly; the first coins take the remainder.
				pieces.append([item, amount / coins + (1 if i < amount % coins else 0)])
		else:
			pieces.append([item, amount])
	var result: Array[Pickup] = []
	if pieces.is_empty():
		return result
	var space := (container as Node3D).get_world_3d().direct_space_state if container is Node3D else null
	var ground := Vector3(from.x, floor_y, from.z)
	var base_angle := atan2(direction.z, direction.x) if direction != Vector3.ZERO else rng.randf() * TAU
	for i in pieces.size():
		var pickup := Pickup.new()
		pickup.item = pieces[i][0]
		pickup.amount = pieces[i][1]
		container.add_child(pickup)
		var angle: float
		if direction == Vector3.ZERO:
			angle = base_angle + TAU * i / pieces.size() + rng.randf_range(-0.3, 0.3)
		else:
			var t := (i + 0.5) / pieces.size() * 2.0 - 1.0  # -1..1 across the fan
			angle = base_angle + t * spread + rng.randf_range(-0.15, 0.15)
		var out := Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(OUT_SPEED.x, OUT_SPEED.y)
		var up := rng.randf_range(UP_SPEED.x, UP_SPEED.y)
		if space:
			out *= _throw_scale(space, ground, out * Pickup.flight_time(up, from.y - floor_y), wall_mask)
		pickup.launch(from, out + Vector3.UP * up, floor_y)
		result.append(pickup)
	return result


## 1, or less if a wall stands within `landing` (horizontal offset) of
## `ground`: the pickup then lands 0.4 m short of it.
static func _throw_scale(space: PhysicsDirectSpaceState3D, ground: Vector3, landing: Vector3,
		wall_mask: int) -> float:
	var distance := landing.length()
	if distance < 0.01:
		return 1.0
	var from := ground + Vector3.UP * 0.5
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + landing, wall_mask))
	if hit.is_empty():
		return 1.0
	return maxf(from.distance_to(hit["position"]) - 0.4, 0.0) / distance
