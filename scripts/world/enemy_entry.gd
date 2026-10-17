class_name EnemyEntry
extends Resource
## One enemy type a level can spend its budget on (see EnemyRoster).

@export var display_name: String = "Enemy"
@export var scene: PackedScene
## Weapon it spawns with (overrides the scene's random choice). Null = the
## scene decides.
@export var weapon: WeaponDefinition
## Budget points it costs.
@export var cost: int = 2
## First level it can appear on.
@export var min_level: int = 1
