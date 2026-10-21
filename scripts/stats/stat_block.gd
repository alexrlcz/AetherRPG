class_name StatBlock
extends Resource
## A character's base core stats, before any modifier (gear, elite scaling,
## later buffs). CharacterStats turns them into the final values. Damage and
## move speed are multipliers with a base of 1, so they have no field here.
## EnemyStats extends this; the player's is resources/stats/player_stats.tres.

@export var max_health: int = 100
@export var max_stamina: float = 100.0
## Stamina per second, after the StaminaComponent's regen_delay.
@export var stamina_regen: float = 30.0
## Damage taken is reduced by armor / (armor + 100) (CharacterStats).
@export var armor: float = 0.0
