class_name WeaponComponent
extends Node
## Equips a WeaponDefinition on a character: puts its model in the hand,
## shapes the attack hitbox, sets the weapon trail, applies its animation and
## character overrides (restoring the previous weapon's), then emits
## `equipped`. The character's controller takes the weapon's attacks from
## that signal (or from `current` in its _ready()).
##
## Keep this node after the character's other components: it equips in its
## _ready(), once the hitbox, animator and reaction are ready.

signal equipped(weapon: WeaponDefinition)

@export var weapon: WeaponDefinition
## When not empty, one of these is picked at random on ready instead of
## `weapon` (enemy variety).
@export var random_weapons: Array[WeaponDefinition] = []
## The hand's bone attachment; the model goes under it.
@export var hand: Node3D
## Its first CollisionShape3D gets the weapon's box.
@export var hitbox: HitboxComponent
@export var trail: WeaponTrail
@export var animator: CharacterAnimator
@export var reaction: HitReactionComponent
## Receives `character_overrides`. Defaults to the parent.
@export var character: Node
## Override properties this character never takes (e.g. enemies skip the
## player's "idle_variants").
@export var ignored_overrides: Array[StringName] = []

## The weapon equipped now.
var current: WeaponDefinition

var _model: Node3D
## Object -> {property: value before any weapon overrode it}.
var _defaults: Dictionary = {}


func _ready() -> void:
	if character == null:
		character = get_parent()
	if not random_weapons.is_empty():
		weapon = random_weapons.pick_random()
	if weapon:
		equip(weapon)


func equip(new_weapon: WeaponDefinition) -> void:
	if new_weapon == null:
		return
	_restore_defaults()
	if _model:
		# Out of the hand now, so the new model gets its name and nothing
		# (silhouette refresh, hit flash) picks up the old one.
		_model.get_parent().remove_child(_model)
		_model.queue_free()
		_model = null
	current = new_weapon
	weapon = new_weapon
	if new_weapon.model and hand:
		_model = new_weapon.model.instantiate() as Node3D
		_model.name = "WeaponModel"
		_model.transform = new_weapon.model_transform
		hand.add_child(_model)
	if hitbox:
		for child in hitbox.get_children():
			if child is CollisionShape3D:
				var box := BoxShape3D.new()  # Never edit a shape other scenes share.
				box.size = new_weapon.hitbox_size
				child.shape = box
				child.transform = new_weapon.hitbox_transform
				break
		hitbox.refresh_shapes()
	if trail:
		trail.base_offset = new_weapon.trail_base
		trail.tip_offset = new_weapon.trail_tip
	_override(animator, new_weapon.animator_overrides)
	_override(reaction, new_weapon.reaction_overrides)
	_override(character, new_weapon.character_overrides)
	equipped.emit(new_weapon)


## The model node of the equipped weapon (null without a model).
func get_model() -> Node3D:
	return _model


func _override(target: Object, values: Dictionary) -> void:
	if target == null:
		return
	for property in values:
		if not property in target or StringName(property) in ignored_overrides:
			continue
		var saved: Dictionary = _defaults.get_or_add(target, {})
		if not saved.has(property):
			saved[property] = target.get(property)
		target.set(property, values[property])


func _restore_defaults() -> void:
	for target: Object in _defaults:
		if is_instance_valid(target):
			for property in _defaults[target]:
				target.set(property, _defaults[target][property])
	_defaults.clear()
