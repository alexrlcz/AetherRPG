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

@export_group("Elite")
## Multipliers on the scene's enemy (EnemyController): body and reach, health,
## attack damage, and poise. 1 = a regular enemy; bosses are scaled-up
## elites until they get their own scenes (see BossEncounter).
@export var size_scale: float = 1.0
@export var health_scale: float = 1.0
@export var damage_scale: float = 1.0
@export var poise_scale: float = 1.0
