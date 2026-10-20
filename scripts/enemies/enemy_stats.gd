class_name EnemyStats
extends Resource
## Data describing one enemy type. Create a .tres per enemy type.

@export var display_name: String = "Enemy"

@export_group("Survival")
@export var max_health: int = 60
## Poise damage absorbed during its own attacks before a hit interrupts them.
@export var poise: float = 30.0
## Multiplier on knockback taken (heavier enemies < 1).
@export var knockback_scale: float = 1.0

@export_group("Stamina")
## Attacks pay their AttackProfile.stamina_cost from this pool; an exhausted
## enemy holds its ground until it recovers (a window to punish).
@export var max_stamina: float = 60.0
## Per second, after the StaminaComponent's regen_delay.
@export var stamina_regen: float = 8.0

@export_group("Movement")
@export var move_speed: float = 3.5
@export var turn_speed: float = 10.0

@export_group("Awareness")
## Starts chasing when the target comes this close.
@export var detection_radius: float = 8.0
## Gives up and returns home when the target gets this far away.
@export var lose_interest_radius: float = 14.0
## Detection also needs an unobstructed line of sight through world geometry.
@export var requires_line_of_sight: bool = true
## While chasing without sight, heads for the last seen position for this long
## before giving up.
@export var lose_sight_time: float = 3.0

@export_group("Attack")
## Seconds between dash attacks (counted from the start of the last one).
## The attacks themselves (swing, range, dash) come from the enemy's weapon
## (WeaponDefinition).
@export var dash_cooldown: float = 5.0
