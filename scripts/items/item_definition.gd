class_name ItemDefinition
extends Resource
## Data for one kind of item that can lie on the ground (Pickup) or, later,
## sit in the inventory. One .tres per item in resources/items/.

enum Kind { CURRENCY, GEAR }

@export var id: StringName = &""
@export var display_name: String = "Item"
@export var kind: Kind = Kind.CURRENCY
## Picked up by walking near it (gold) instead of with the interact key (gear).
@export var auto_collect: bool = true
