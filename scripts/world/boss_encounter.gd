class_name BossEncounter
extends Resource
## The fight in a boss floor's arena (step 6 of procedural levels): one boss,
## optional escorts, and the arena's size. LevelGenerator.generate_boss()
## builds the floor; EncounterPlanner.place_boss() puts the fight in it; Main
## keeps the exit gate sealed until the boss dies. One .tres per boss in
## resources/encounters/.

## Shown on the boss health bar.
@export var title: String = "Boss"
## The boss (usually an elite: see EnemyEntry's Elite group).
@export var boss: EnemyEntry
## Regular enemies with it in the arena.
@export var escorts: Array[EnemyEntry] = []
@export var escort_count: int = 0
## Arena side, in cells (DungeonBuilder.CELL = 2 m).
@export var arena_size: int = 14
