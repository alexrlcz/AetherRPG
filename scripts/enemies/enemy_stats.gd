class_name EnemyStats
extends Resource
## Data describing one enemy type. Create a .tres per enemy type.

@export var display_name: String = "Enemy"

@export_group("Survival")
@export var max_health: int = 60

@export_group("Movement")
@export var move_speed: float = 3.5
@export var turn_speed: float = 10.0

@export_group("Awareness")
## Starts chasing when the target comes this close.
@export var detection_radius: float = 8.0
## Gives up and returns home when the target gets this far away.
@export var lose_interest_radius: float = 14.0

@export_group("Attack")
## Starts an attack when the target is within this distance.
@export var attack_range: float = 1.7
@export var attack_damage: int = 15
## Telegraph time before the blow lands.
@export var attack_windup: float = 0.7
## How long the hitbox is live.
@export var attack_strike_duration: float = 0.12
## Pause after the blow before the enemy can act again.
@export var attack_recovery: float = 0.9
