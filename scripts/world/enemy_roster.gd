class_name EnemyRoster
extends Resource
## The enemies a set of levels can use, and how many: each fight room gets a
## point budget that grows with the level, spent on affordable entries
## (EncounterPlanner). One .tres per roster in resources/encounters/.

@export var entries: Array[EnemyEntry] = []

@export_group("Budget")
## Points per fight room: base + per_level × level, ± variance.
@export var base_budget: float = 2.0
@export var budget_per_level: float = 1.5
@export_range(0.0, 1.0) var budget_variance: float = 0.2
## Multipliers by room role.
@export var side_room_scale: float = 0.5
@export var exit_room_scale: float = 1.5

@export_group("Placement")
## Cells kept free of enemies in front of every doorway.
@export var door_clearance: int = 2
## At most one enemy per this many room cells.
@export var cells_per_enemy: int = 12
## No enemy within this many cells of the Start label, so nobody spots the
## player the moment the level begins (detection is 8 m = 4 cells).
@export var start_clearance: float = 6.0
## No enemy within this many cells (Chebyshev) of the exit gate.
@export var exit_clearance: int = 2


## Points for one room of `role` on `level`, before variance.
func room_budget(role: String, level: int) -> float:
	var budget := base_budget + budget_per_level * level
	match role:
		"start":
			return 0.0
		"side":
			return budget * side_room_scale
		"exit":
			return budget * exit_room_scale
	return budget


## Entries allowed on `level`.
func available(level: int) -> Array[EnemyEntry]:
	var result: Array[EnemyEntry] = []
	for e in entries:
		if e.min_level <= level:
			result.append(e)
	return result
